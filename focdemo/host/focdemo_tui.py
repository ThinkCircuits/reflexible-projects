#!/usr/bin/env python3
"""
FOC Demo TUI — Curses-based dashboard for the iCE40 FOC BLDC controller.

Communicates via compact binary serial protocol over USB-serial adapter.
Frame format: [0xA5 sync][CMD 1B][LEN 1B][PAYLOAD 0-32B][CRC8 1B]

Usage:
    python3 focdemo_tui.py [--port /dev/ttyUSB0] [--baud 115200]
"""

import argparse
import curses
import struct
import sys
import threading
import time
from collections import deque

import serial

# =============================================================================
# Protocol Constants
# =============================================================================
SYNC_BYTE = 0xA5

# Host → FPGA commands
CMD_SET_MODE     = 0x01
CMD_SET_TORQUE   = 0x02
CMD_SET_SPEED    = 0x03
CMD_SET_POS      = 0x04
CMD_SET_ENABLE   = 0x05
CMD_SET_GAINS    = 0x06
CMD_GET_STATUS   = 0x10
CMD_STREAM_START = 0x20
CMD_STREAM_STOP  = 0x21
CMD_RESET        = 0xFF

# FPGA → Host responses
CMD_ACK    = 0x80
CMD_NACK   = 0x81
CMD_STATUS = 0x90

MODE_NAMES = {0: "TORQUE", 1: "SPEED", 2: "POSITION"}
VARIANT_NAMES = {0: "torque", 1: "speed", 2: "position"}
VARIANT_MAX_MODE = {0: 0, 1: 1, 2: 2}  # max mode supported by each variant

# Speed scaling: FPGA EMA accumulator = delta * 64 (shift=6).
# To convert FPGA units to counts/s: multiply by FOC_RATE / 64.
# FOC rate ≈ 20 kHz (ADC sample period 2400 clks @ 48 MHz).
SPEED_EMA_SHIFT = 6
FOC_RATE_HZ = 20000
SPEED_SCALE = FOC_RATE_HZ / (1 << SPEED_EMA_SHIFT)  # ~312.5 cnt/s per unit


# =============================================================================
# CRC-8/MAXIM (poly 0x31)
# =============================================================================
def crc8_maxim(data: bytes) -> int:
    crc = 0x00
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 0x01:
                crc = (crc >> 1) ^ 0x8C
            else:
                crc >>= 1
    return crc


# =============================================================================
# Frame Builder / Parser
# =============================================================================
def build_frame(cmd: int, payload: bytes = b"") -> bytes:
    """Build a binary protocol frame."""
    length = len(payload)
    body = bytes([cmd, length]) + payload
    crc = crc8_maxim(body)
    return bytes([SYNC_BYTE]) + body + bytes([crc])


def parse_status_payload(payload: bytes) -> dict:
    """Parse a STATUS response payload (21 bytes)."""
    if len(payload) < 13:
        return {}
    mode = payload[0]
    enable = payload[1]
    fault = payload[2]
    drv_fault_reg, = struct.unpack_from("<H", payload, 3)  # 11 bits in u16
    pos,   = struct.unpack_from("<H", payload, 5)
    speed, = struct.unpack_from("<h", payload, 7)
    id_val,= struct.unpack_from("<h", payload, 9)
    iq_val,= struct.unpack_from("<h", payload, 11)
    result = {
        "mode": mode,
        "enable": enable,
        "fault": fault,
        "drv_fault_reg": drv_fault_reg,
        "pos": pos,
        "speed": speed,
        "id": id_val,
        "iq": iq_val,
    }
    if len(payload) >= 21:
        ia, ib, ic, enc = struct.unpack_from("<HHHH", payload, 13)
        result.update({"ia": ia, "ib": ib, "ic": ic, "enc": enc})
    if len(payload) >= 22:
        result["firmware_variant"] = payload[21]
    return result


# DRV8323 Fault Status 1 register (0x00) bit definitions
DRV_FAULT_BITS = [
    (10, "FAULT"),
    (9,  "VDS_OCP"),
    (8,  "GDF"),
    (7,  "UVLO"),
    (6,  "OTSD"),
    (5,  "VDS_HA"),
    (4,  "VDS_LA"),
    (3,  "VDS_HB"),
    (2,  "VDS_LB"),
    (1,  "VDS_HC"),
    (0,  "VDS_LC"),
]


def decode_drv_fault(reg_val: int) -> str:
    """Decode DRV8323 Fault Status 1 register into flag names."""
    flags = [name for bit, name in DRV_FAULT_BITS if reg_val & (1 << bit)]
    return " | ".join(flags) if flags else "OK"


# =============================================================================
# Serial Communication Thread
# =============================================================================
class FocSerial:
    def __init__(self, port: str, baud: int):
        self.ser = serial.Serial(port, baud, timeout=0.1)
        self.lock = threading.Lock()
        self.status = {}
        self.connected = True
        self.rx_thread = threading.Thread(target=self._rx_loop, daemon=True)
        self.rx_thread.start()
        # Telemetry history for sparkline plots
        self.iq_history = deque(maxlen=40)
        self.id_history = deque(maxlen=40)
        self.speed_history = deque(maxlen=40)

    def _rx_loop(self):
        """Background thread: read and parse incoming frames."""
        buf = bytearray()
        while self.connected:
            try:
                data = self.ser.read(64)
                if not data:
                    continue
                buf.extend(data)
                # Try to parse frames from buffer
                while len(buf) >= 4:
                    # Find sync byte
                    idx = buf.find(SYNC_BYTE)
                    if idx < 0:
                        buf.clear()
                        break
                    if idx > 0:
                        del buf[:idx]
                    if len(buf) < 4:
                        break
                    cmd = buf[1]
                    length = buf[2]
                    frame_len = 4 + length  # sync + cmd + len + payload + crc
                    if len(buf) < frame_len:
                        break
                    payload = bytes(buf[3 : 3 + length])
                    crc_rx = buf[3 + length]
                    crc_calc = crc8_maxim(bytes(buf[1 : 3 + length]))
                    if crc_rx == crc_calc:
                        self._handle_frame(cmd, payload)
                    del buf[:frame_len]
            except (serial.SerialException, OSError):
                self.connected = False
                break

    def _handle_frame(self, cmd: int, payload: bytes):
        if cmd == CMD_STATUS:
            status = parse_status_payload(payload)
            with self.lock:
                self.status = status
                self.iq_history.append(status.get("iq", 0))
                self.id_history.append(status.get("id", 0))
                self.speed_history.append(status.get("speed", 0))

    def send(self, cmd: int, payload: bytes = b""):
        frame = build_frame(cmd, payload)
        with self.lock:
            try:
                self.ser.write(frame)
            except (serial.SerialException, OSError):
                self.connected = False

    def set_enable(self, en: bool):
        self.send(CMD_SET_ENABLE, bytes([1 if en else 0]))

    def set_mode(self, mode: int):
        self.send(CMD_SET_MODE, bytes([mode & 0xFF]))

    def set_torque(self, iq_ref: int):
        self.send(CMD_SET_TORQUE, struct.pack("<h", iq_ref))

    def set_speed(self, speed: int):
        self.send(CMD_SET_SPEED, struct.pack("<h", speed))

    def set_position(self, pos: int):
        self.send(CMD_SET_POS, struct.pack("<H", pos))

    def set_gains(self, loop_id: int, kp: int, ki: int):
        self.send(CMD_SET_GAINS, struct.pack("<Bhh", loop_id, kp, ki))

    def start_stream(self, period_ms: int = 50):
        self.send(CMD_STREAM_START, bytes([period_ms & 0xFF]))

    def stop_stream(self):
        self.send(CMD_STREAM_STOP)

    def get_status(self):
        self.send(CMD_GET_STATUS)

    def reset(self):
        self.send(CMD_RESET)

    def close(self):
        self.connected = False
        self.stop_stream()
        time.sleep(0.1)
        self.ser.close()


# =============================================================================
# Sparkline Rendering
# =============================================================================
SPARK_CHARS = " _.,:-=!#"


def sparkline(values, width=40, vmin=None, vmax=None):
    """Render a sparkline string from a sequence of numeric values."""
    if not values:
        return " " * width
    vals = list(values)[-width:]
    if vmin is None:
        vmin = min(vals)
    if vmax is None:
        vmax = max(vals)
    span = vmax - vmin if vmax != vmin else 1
    chars = []
    for v in vals:
        idx = int((v - vmin) / span * (len(SPARK_CHARS) - 1))
        idx = max(0, min(len(SPARK_CHARS) - 1, idx))
        chars.append(SPARK_CHARS[idx])
    return "".join(chars).ljust(width)


# =============================================================================
# TUI Application
# =============================================================================
def tui_main(stdscr, foc: FocSerial, args):
    curses.curs_set(0)
    stdscr.timeout(100)  # 100ms refresh
    stdscr.clear()

    # Initialize color pairs
    if curses.has_colors():
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_RED, -1)
        curses.init_pair(2, curses.COLOR_GREEN, -1)
        curses.init_pair(3, curses.COLOR_CYAN, -1)
        curses.init_pair(4, curses.COLOR_YELLOW, -1)

    # Local state for editing
    local_enable = False
    local_mode = 0
    local_target = 0
    editing_target = False
    editing_cmd = None  # 't', 's', or 'p' — which key initiated editing
    target_buf = ""
    stream_period = 50

    # Start streaming
    foc.start_stream(stream_period)

    # Gain state: [loop_id, kp, ki] for each loop
    gains = {
        "id":    [0, 128, 16],
        "iq":    [1, 128, 16],
        "speed": [2, 1024, 128],
        "pos":   [3, 512,  0],
    }

    while True:
        try:
            h, w = stdscr.getmaxyx()
        except curses.error:
            break

        if h < 20 or w < 56:
            stdscr.clear()
            stdscr.addstr(0, 0, "Terminal too small (min 56x20)")
            stdscr.refresh()
            key = stdscr.getch()
            if key == ord("q"):
                break
            continue

        stdscr.erase()

        # Get current status
        with foc.lock:
            st = dict(foc.status)
            iq_hist = list(foc.iq_history)
            id_hist = list(foc.id_history)

        conn_str = "Connected" if foc.connected else "DISCONNECTED"
        fault_str = "FAULT" if st.get("fault", 0) else "None"
        fw_variant = st.get("firmware_variant", 2)  # default to position if unknown
        fw_name = VARIANT_NAMES.get(fw_variant, f"v{fw_variant}")
        max_mode = VARIANT_MAX_MODE.get(fw_variant, 2)

        # Header
        title = f" FOC Demo Controller ({fw_name}) "
        stdscr.addstr(0, 0, "+" + "-" * (w - 2) + "+")
        stdscr.addstr(0, (w - len(title)) // 2, title, curses.A_BOLD)
        row = 1
        info = f" Port: {args.port}  Baud: {args.baud}  Status: {conn_str}"
        stdscr.addstr(row, 0, "|" + info.ljust(w - 2) + "|")
        row += 1

        # Motor section
        stdscr.addstr(row, 0, "+" + "- Motor " + "-" * (w - 10) + "+")
        row += 1

        en_str = " ON " if local_enable else " OFF"
        mode_str = MODE_NAMES.get(local_mode, "???")
        drv_reg = st.get("drv_fault_reg", 0)
        drv_str = decode_drv_fault(drv_reg)
        motor_line = f" Enable: [{en_str}]   Mode: [{mode_str:8s}]   Fault: {fault_str}"
        stdscr.addstr(row, 0, "|" + motor_line.ljust(w - 2) + "|")
        if st.get("fault", 0) and curses.has_colors():
            stdscr.chgat(row, motor_line.index("Fault:") + 1, len(fault_str) + 7, curses.color_pair(1) | curses.A_BOLD)
        row += 1
        drv_line = f" DRV8323: 0x{drv_reg:03X} = {drv_str}"
        stdscr.addstr(row, 0, "|" + drv_line.ljust(w - 2) + "|")
        if drv_reg and curses.has_colors():
            stdscr.chgat(row, 1, len(drv_line), curses.color_pair(1) | curses.A_BOLD)
        row += 1

        if editing_target:
            edit_label = {'t': 'Torque', 's': 'Speed', 'p': 'Position'}.get(editing_cmd, 'Target')
            target_line = f" {edit_label}: {target_buf}_"
        else:
            unit = {0: "", 1: " cnt/s (EMA)", 2: " counts"}.get(local_mode, "")
            target_line = f" Target: {local_target}{unit}"
        stdscr.addstr(row, 0, "|" + target_line.ljust(w - 2) + "|")
        row += 1

        # Telemetry section
        stdscr.addstr(row, 0, "+" + f"- Telemetry ({stream_period}ms) " + "-" * (w - 20) + "+")
        row += 1

        pos_val = st.get("pos", 0)
        spd_raw = st.get("speed", 0)
        spd_val = spd_raw * SPEED_SCALE
        tel1 = f" Position: {pos_val:6d}    Speed: {spd_val:8.0f} cnt/s"
        stdscr.addstr(row, 0, "|" + tel1.ljust(w - 2) + "|")
        row += 1

        id_val = st.get("id", 0)
        iq_val = st.get("iq", 0)
        tel2 = f" Id:       {id_val:6d}    Iq:    {iq_val:6d}"
        stdscr.addstr(row, 0, "|" + tel2.ljust(w - 2) + "|")
        row += 1

        ia  = st.get("ia",  0)
        ib  = st.get("ib",  0)
        ic  = st.get("ic",  0)
        enc = st.get("enc", 0)
        tel3 = f" ADC raw:  Ia={ia:4d}  Ib={ib:4d}  Ic={ic:4d}  Enc={enc:4d}"
        stdscr.addstr(row, 0, "|" + tel3.ljust(w - 2) + "|")
        row += 1

        # Gains section
        stdscr.addstr(row, 0, "+" + "- Gains " + "-" * (w - 10) + "+")
        row += 1

        g1 = f" Id PI:  Kp={gains['id'][1]:4d}  Ki={gains['id'][2]:4d}     Iq PI:  Kp={gains['iq'][1]:4d}  Ki={gains['iq'][2]:4d}"
        stdscr.addstr(row, 0, "|" + g1.ljust(w - 2) + "|")
        row += 1

        g2 = f" Speed:  Kp={gains['speed'][1]:4d}  Ki={gains['speed'][2]:4d}     Pos:    Kp={gains['pos'][1]:4d}"
        stdscr.addstr(row, 0, "|" + g2.ljust(w - 2) + "|")
        row += 1

        # Sparkline plots
        stdscr.addstr(row, 0, "+" + "- Current Plot " + "-" * (w - 17) + "+")
        row += 1

        plot_w = min(40, w - 10)
        iq_spark = sparkline(iq_hist, plot_w, vmin=-2048, vmax=2048)
        id_spark = sparkline(id_hist, plot_w, vmin=-2048, vmax=2048)
        stdscr.addstr(row, 0, "|" + f"  Iq {iq_spark}".ljust(w - 2) + "|")
        row += 1
        stdscr.addstr(row, 0, "|" + f"  Id {id_spark}".ljust(w - 2) + "|")
        row += 1

        # Keys section
        stdscr.addstr(row, 0, "+" + "- Keys " + "-" * (w - 9) + "+")
        row += 1
        keys_parts = [" e:enable", "t:torque"]
        if max_mode >= 1:
            keys_parts.append("s:speed")
        if max_mode >= 2:
            keys_parts.append("p:pos")
        keys_parts.extend(["g:gains", "r:reset", "q:quit"])
        keys = "  ".join(keys_parts)
        stdscr.addstr(row, 0, "|" + keys.ljust(w - 2) + "|")
        row += 1
        stdscr.addstr(row, 0, "+" + "-" * (w - 2) + "+")

        stdscr.refresh()

        # Handle input
        key = stdscr.getch()
        if key < 0:
            continue

        if editing_target:
            if key == 10 or key == curses.KEY_ENTER:  # Enter
                try:
                    local_target = int(target_buf)
                except ValueError:
                    pass
                editing_target = False
                target_buf = ""
                # Send appropriate command based on which key initiated editing
                if editing_cmd == 't':
                    foc.set_torque(local_target)
                elif editing_cmd == 's':
                    # Convert counts/s to FPGA EMA units
                    foc.set_speed(int(local_target / SPEED_SCALE))
                elif editing_cmd == 'p':
                    foc.set_position(local_target & 0xFFFF)
            elif key == 27:  # Escape
                editing_target = False
                target_buf = ""
            elif key == curses.KEY_BACKSPACE or key == 127 or key == 8:
                target_buf = target_buf[:-1]
            elif 32 <= key < 127:
                target_buf += chr(key)
            continue

        if key == ord("q"):
            break
        elif key == ord("e"):
            local_enable = not local_enable
            foc.set_enable(local_enable)
        elif key == ord("m"):
            local_mode = (local_mode + 1) % (max_mode + 1)
            foc.set_mode(local_mode)
        elif key == ord("t"):
            # Set torque value: direct iq_ref in torque mode, torque limit in speed/position mode
            editing_target = True
            editing_cmd = 't'
            target_buf = ""
        elif key == ord("s") and max_mode >= 1:
            local_mode = 1
            foc.set_mode(1)
            editing_target = True
            editing_cmd = 's'
            target_buf = ""
        elif key == ord("p") and max_mode >= 2:
            local_mode = 2
            foc.set_mode(2)
            editing_target = True
            editing_cmd = 'p'
            target_buf = ""
        elif key == ord("r"):
            foc.reset()
            local_enable = False
            local_mode = 0
            local_target = 0
        elif key == ord("g"):
            # Cycle through gain editing (simplified: prompt via status line)
            # In a full implementation this would open a sub-dialog
            pass


def main():
    parser = argparse.ArgumentParser(description="FOC Demo TUI Controller")
    parser.add_argument("--port", default="/dev/ttyUSB0", help="Serial port")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate")
    args = parser.parse_args()

    try:
        foc = FocSerial(args.port, args.baud)
    except serial.SerialException as e:
        print(f"ERROR: Cannot open {args.port}: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        curses.wrapper(lambda stdscr: tui_main(stdscr, foc, args))
    finally:
        foc.close()


if __name__ == "__main__":
    main()
