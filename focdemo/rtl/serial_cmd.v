`default_nettype none

// =============================================================================
// serial_cmd.v  –  Binary serial command handler for the FOC controller
//
// Frame format (host → FPGA):
//   [0xA5 sync][CMD 1B][LEN 1B][PAYLOAD 0-32B][CRC8 1B]
//
// CRC-8/MAXIM: polynomial 0x31, computed over CMD + LEN + PAYLOAD
// =============================================================================

module serial_cmd (
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // UART interface
    // -------------------------------------------------------------------------
    input  wire [7:0]  uart_rx_data,
    input  wire        uart_rx_valid,
    output reg  [7:0]  uart_tx_data,
    output reg         uart_tx_valid,
    input  wire        uart_tx_ready,

    // -------------------------------------------------------------------------
    // FOC control outputs
    // -------------------------------------------------------------------------
    output reg         enable,
    output reg  [7:0]  mode,
    output reg  signed [15:0] cmd_iq_ref,
    output reg  signed [15:0] cmd_speed_ref,
    output reg  [15:0] cmd_pos_ref,

    // Tunable gains  (three loops: id, iq, speed, pos)
    output reg  signed [15:0] kp_id,
    output reg  signed [15:0] ki_id,
    output reg  signed [15:0] kp_iq,
    output reg  signed [15:0] ki_iq,
    output reg  signed [15:0] kp_speed,
    output reg  signed [15:0] ki_speed,
    output reg  signed [15:0] kp_pos,

    // -------------------------------------------------------------------------
    // FOC telemetry inputs
    // -------------------------------------------------------------------------
    input  wire        foc_fault,
    input  wire [15:0] dbg_pos,
    input  wire signed [15:0] dbg_speed,
    input  wire signed [15:0] dbg_id,
    input  wire signed [15:0] dbg_iq,
    input  wire [15:0] dbg_pwm_a,
    input  wire [15:0] dbg_pwm_b,
    input  wire [15:0] dbg_pwm_c
);

// =============================================================================
// Parameters
// =============================================================================

// Clock cycles per millisecond (48 MHz assumed; adjust as needed)
localparam MS_CYCLES = 48_000;

// Maximum payload size
localparam MAX_PAYLOAD = 32;

// Sync byte
localparam SYNC_BYTE = 8'hA5;

// ---- Host→FPGA command codes ------------------------------------------------
localparam CMD_SET_MODE    = 8'h01;
localparam CMD_SET_TORQUE  = 8'h02;
localparam CMD_SET_SPEED   = 8'h03;
localparam CMD_SET_POS     = 8'h04;
localparam CMD_SET_ENABLE  = 8'h05;
localparam CMD_SET_GAINS   = 8'h06;
localparam CMD_GET_STATUS  = 8'h10;
localparam CMD_STREAM_START= 8'h20;
localparam CMD_STREAM_STOP = 8'h21;
localparam CMD_RESET       = 8'hFF;

// ---- FPGA→Host response codes -----------------------------------------------
localparam RSP_ACK         = 8'h80;
localparam RSP_NACK        = 8'h81;
localparam RSP_STATUS      = 8'h90;

// ---- NACK error codes -------------------------------------------------------
localparam ERR_BAD_CRC     = 8'h01;
localparam ERR_BAD_LEN     = 8'h02;
localparam ERR_UNKNOWN_CMD = 8'h03;

// ---- TX buffer size (max frame = 1+1+1+17+1 = 21 bytes) --------------------
localparam TX_BUF_SIZE = 24;

// =============================================================================
// RX state machine
// =============================================================================

localparam RX_SYNC    = 3'd0;
localparam RX_CMD     = 3'd1;
localparam RX_LEN     = 3'd2;
localparam RX_PAYLOAD = 3'd3;
localparam RX_CRC     = 3'd4;
localparam RX_DISPATCH= 3'd5;

reg [2:0]  rx_state;
reg [7:0]  rx_cmd;
reg [7:0]  rx_len;
reg [7:0]  rx_payload [0:MAX_PAYLOAD-1];
reg [5:0]  rx_payload_idx;   // counts bytes received into payload
reg [7:0]  rx_crc_got;       // CRC byte received from host

// Running CRC over the incoming frame (CMD + LEN + PAYLOAD)
reg [7:0]  rx_crc_calc;

// =============================================================================
// TX state machine
// =============================================================================

localparam TX_IDLE  = 2'd0;
localparam TX_SEND  = 2'd1;
localparam TX_WAIT  = 2'd2;

reg [1:0]  tx_state;
reg [7:0]  tx_buf   [0:TX_BUF_SIZE-1];
reg [4:0]  tx_len;          // total bytes to send in current frame
reg [4:0]  tx_idx;          // next byte index to send
reg        tx_trigger;      // single-cycle pulse: start sending tx_buf

// =============================================================================
// Streaming
// =============================================================================

reg        stream_active;
reg [7:0]  stream_period;   // period in milliseconds
reg [15:0] ms_cnt;          // millisecond accumulator  (counts ms elapsed)
reg [31:0] clk_cnt;         // sub-ms clock counter
reg        stream_trigger;  // single-cycle pulse when streaming fires

// =============================================================================
// CRC-8/MAXIM helper task
//
//   poly = 0x31, init = 0x00, RefIn = true, RefOut = true, XorOut = 0x00
//
//   Because RefIn = RefOut = true the computation is done bit-reversed:
//   shift right, XOR with reflected poly (0x8C) when bit 0 is 1.
// =============================================================================

// Combinational CRC update: next_crc = crc8_update(crc_in, data_in)
function [7:0] crc8_update;
    input [7:0] crc_in;
    input [7:0] data_in;
    integer     i;
    reg   [7:0] c;
    begin
        c = crc_in ^ data_in;
        for (i = 0; i < 8; i = i + 1) begin
            if (c[0])
                c = (c >> 1) ^ 8'h8C;   // 0x8C = reflected 0x31
            else
                c = c >> 1;
        end
        crc8_update = c;
    end
endfunction

// =============================================================================
// Build and enqueue a TX frame
//
//   build_ack(cmd_echo)
//   build_nack(cmd_echo, error)
//   build_status()
//
//   All write into tx_buf[], set tx_len, then assert tx_trigger.
// =============================================================================

// We use a shared helper to append the trailing CRC byte into tx_buf and
// finalize tx_len.  Called after payload bytes are written.
// Implemented inline in the dispatch block below.

// =============================================================================
// Reset defaults
// =============================================================================


// =============================================================================
// Main sequential logic
// =============================================================================

always @(posedge clk or negedge rst_n) begin : main_seq

    integer i;

    if (!rst_n) begin
        // -- RX ---------------------------------------------------------------
        rx_state       <= RX_SYNC;
        rx_cmd         <= 8'h00;
        rx_len         <= 8'h00;
        rx_payload_idx <= 6'd0;
        rx_crc_got     <= 8'h00;
        rx_crc_calc    <= 8'h00;

        // -- TX ---------------------------------------------------------------
        tx_state   <= TX_IDLE;
        tx_len     <= 5'd0;
        tx_idx     <= 5'd0;
        tx_trigger <= 1'b0;
        uart_tx_data  <= 8'h00;
        uart_tx_valid <= 1'b0;

        // -- Streaming --------------------------------------------------------
        stream_active  <= 1'b0;
        stream_period  <= 8'd10;    // default 10 ms
        ms_cnt         <= 16'd0;
        clk_cnt        <= 32'd0;
        stream_trigger <= 1'b0;

        // -- FOC control outputs ----------------------------------------------
        enable        <= 1'b0;
        mode          <= 8'h00;
        cmd_iq_ref    <= 16'sd0;
        cmd_speed_ref <= 16'sd0;
        cmd_pos_ref   <= 16'h0000;

        // -- Gain defaults ----------------------------------------------------
        kp_id    <= 16'sd128;
        ki_id    <= 16'sd16;
        kp_iq    <= 16'sd128;
        ki_iq    <= 16'sd16;
        kp_speed <= 16'sd64;
        ki_speed <= 16'sd4;
        kp_pos   <= 16'sd32;

        // -- Clear payload buffer ---------------------------------------------
        for (i = 0; i < MAX_PAYLOAD; i = i + 1)
            rx_payload[i] <= 8'h00;

        // -- Clear TX buffer --------------------------------------------------
        for (i = 0; i < TX_BUF_SIZE; i = i + 1)
            tx_buf[i] <= 8'h00;

    end else begin

        // =====================================================================
        // Default pulse signals (cleared every cycle)
        // =====================================================================
        tx_trigger     <= 1'b0;
        stream_trigger <= 1'b0;

        // =====================================================================
        // Millisecond timer
        // =====================================================================
        if (clk_cnt >= MS_CYCLES - 1) begin
            clk_cnt <= 32'd0;
            if (stream_active) begin
                if (ms_cnt >= ({8'h00, stream_period} - 16'd1)) begin
                    ms_cnt         <= 16'd0;
                    stream_trigger <= 1'b1;
                end else begin
                    ms_cnt <= ms_cnt + 16'd1;
                end
            end else begin
                ms_cnt <= 16'd0;
            end
        end else begin
            clk_cnt <= clk_cnt + 32'd1;
        end

        // =====================================================================
        // RX state machine
        // =====================================================================
        if (uart_rx_valid) begin
            case (rx_state)

                // ----- Wait for sync byte ------------------------------------
                RX_SYNC: begin
                    if (uart_rx_data == SYNC_BYTE) begin
                        rx_state    <= RX_CMD;
                        rx_crc_calc <= 8'h00;
                    end
                    // else stay in SYNC
                end

                // ----- Receive command byte ----------------------------------
                RX_CMD: begin
                    rx_cmd      <= uart_rx_data;
                    rx_crc_calc <= crc8_update(8'h00, uart_rx_data);
                    rx_state    <= RX_LEN;
                end

                // ----- Receive length byte -----------------------------------
                RX_LEN: begin
                    rx_len      <= uart_rx_data;
                    rx_crc_calc <= crc8_update(rx_crc_calc, uart_rx_data);
                    rx_payload_idx <= 6'd0;
                    if (uart_rx_data == 8'h00)
                        rx_state <= RX_CRC;
                    else if (uart_rx_data > MAX_PAYLOAD) begin
                        // Length exceeds maximum – abort and wait for re-sync
                        rx_state <= RX_SYNC;
                    end else
                        rx_state <= RX_PAYLOAD;
                end

                // ----- Receive payload bytes ---------------------------------
                RX_PAYLOAD: begin
                    rx_payload[rx_payload_idx] <= uart_rx_data;
                    rx_crc_calc <= crc8_update(rx_crc_calc, uart_rx_data);
                    if (rx_payload_idx == (rx_len - 8'h01))
                        rx_state <= RX_CRC;
                    else
                        rx_payload_idx <= rx_payload_idx + 6'd1;
                end

                // ----- Receive CRC byte, then dispatch -----------------------
                RX_CRC: begin
                    rx_crc_got <= uart_rx_data;
                    rx_state   <= RX_DISPATCH;
                end

                // ----- Dispatch (handled below outside uart_rx_valid) --------
                RX_DISPATCH: begin
                    // Shouldn't receive data while dispatching; re-sync
                    rx_state <= RX_SYNC;
                end

                default: rx_state <= RX_SYNC;
            endcase
        end

        // =====================================================================
        // Dispatch state (evaluated every cycle, not gated by uart_rx_valid)
        // =====================================================================
        if (rx_state == RX_DISPATCH) begin
            rx_state <= RX_SYNC; // always return to SYNC after dispatch

            if (rx_crc_got != rx_crc_calc) begin
                // ----- CRC error: send NACK ----------------------------------
                tx_buf[0]  <= SYNC_BYTE;
                tx_buf[1]  <= RSP_NACK;
                tx_buf[2]  <= 8'h02;          // payload length = 2
                tx_buf[3]  <= rx_cmd;
                tx_buf[4]  <= ERR_BAD_CRC;
                tx_buf[5]  <= crc8_update(crc8_update(crc8_update(8'h00,
                                  RSP_NACK), 8'h02), rx_cmd);
                // Note: full CRC over RSP_NACK + LEN + cmd_echo + error
                // Re-computed inline below for clarity
                begin : nack_crc_bad_crc
                    reg [7:0] c;
                    c = crc8_update(8'h00, RSP_NACK);
                    c = crc8_update(c,     8'h02);
                    c = crc8_update(c,     rx_cmd);
                    c = crc8_update(c,     ERR_BAD_CRC);
                    tx_buf[5] <= c;
                end
                tx_len    <= 5'd6;
                tx_trigger <= 1'b1;

            end else begin
                // ----- CRC OK: decode command --------------------------------
                case (rx_cmd)

                    // ----------------------------------------------------------
                    CMD_SET_MODE: begin
                        if (rx_len != 8'h01) begin
                            // bad length NACK
                            begin : nack_set_mode_len
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_NACK);
                                c = crc8_update(c,     8'h02);
                                c = crc8_update(c,     rx_cmd);
                                c = crc8_update(c,     ERR_BAD_LEN);
                                tx_buf[5] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_len    <= 5'd6;
                            tx_trigger <= 1'b1;
                        end else begin
                            mode <= rx_payload[0];
                            begin : ack_set_mode
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_ACK);
                                c = crc8_update(c,     8'h01);
                                c = crc8_update(c,     rx_cmd);
                                tx_buf[4] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_len    <= 5'd5;
                            tx_trigger <= 1'b1;
                        end
                    end

                    // ----------------------------------------------------------
                    CMD_SET_TORQUE: begin
                        if (rx_len != 8'h02) begin
                            begin : nack_set_torque_len
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_NACK);
                                c = crc8_update(c,     8'h02);
                                c = crc8_update(c,     rx_cmd);
                                c = crc8_update(c,     ERR_BAD_LEN);
                                tx_buf[5] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_len    <= 5'd6;
                            tx_trigger <= 1'b1;
                        end else begin
                            // Little-endian i16
                            cmd_iq_ref <= $signed({rx_payload[1], rx_payload[0]});
                            begin : ack_set_torque
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_ACK);
                                c = crc8_update(c,     8'h01);
                                c = crc8_update(c,     rx_cmd);
                                tx_buf[4] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_len    <= 5'd5;
                            tx_trigger <= 1'b1;
                        end
                    end

                    // ----------------------------------------------------------
                    CMD_SET_SPEED: begin
                        if (rx_len != 8'h02) begin
                            begin : nack_set_speed_len
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_NACK);
                                c = crc8_update(c,     8'h02);
                                c = crc8_update(c,     rx_cmd);
                                c = crc8_update(c,     ERR_BAD_LEN);
                                tx_buf[5] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_len    <= 5'd6;
                            tx_trigger <= 1'b1;
                        end else begin
                            cmd_speed_ref <= $signed({rx_payload[1], rx_payload[0]});
                            begin : ack_set_speed
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_ACK);
                                c = crc8_update(c,     8'h01);
                                c = crc8_update(c,     rx_cmd);
                                tx_buf[4] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_len    <= 5'd5;
                            tx_trigger <= 1'b1;
                        end
                    end

                    // ----------------------------------------------------------
                    CMD_SET_POS: begin
                        if (rx_len != 8'h02) begin
                            begin : nack_set_pos_len
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_NACK);
                                c = crc8_update(c,     8'h02);
                                c = crc8_update(c,     rx_cmd);
                                c = crc8_update(c,     ERR_BAD_LEN);
                                tx_buf[5] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_len    <= 5'd6;
                            tx_trigger <= 1'b1;
                        end else begin
                            cmd_pos_ref <= {rx_payload[1], rx_payload[0]};
                            begin : ack_set_pos
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_ACK);
                                c = crc8_update(c,     8'h01);
                                c = crc8_update(c,     rx_cmd);
                                tx_buf[4] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_len    <= 5'd5;
                            tx_trigger <= 1'b1;
                        end
                    end

                    // ----------------------------------------------------------
                    CMD_SET_ENABLE: begin
                        if (rx_len != 8'h01) begin
                            begin : nack_set_en_len
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_NACK);
                                c = crc8_update(c,     8'h02);
                                c = crc8_update(c,     rx_cmd);
                                c = crc8_update(c,     ERR_BAD_LEN);
                                tx_buf[5] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_len    <= 5'd6;
                            tx_trigger <= 1'b1;
                        end else begin
                            enable <= rx_payload[0][0];
                            begin : ack_set_en
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_ACK);
                                c = crc8_update(c,     8'h01);
                                c = crc8_update(c,     rx_cmd);
                                tx_buf[4] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_len    <= 5'd5;
                            tx_trigger <= 1'b1;
                        end
                    end

                    // ----------------------------------------------------------
                    // SET_GAINS payload: loop_id:u8, kp:i16 LE, ki:i16 LE  (5B)
                    // loop_id: 0=id, 1=iq, 2=speed, 3=pos (pos has no ki)
                    CMD_SET_GAINS: begin
                        if (rx_len != 8'h05) begin
                            begin : nack_set_gains_len
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_NACK);
                                c = crc8_update(c,     8'h02);
                                c = crc8_update(c,     rx_cmd);
                                c = crc8_update(c,     ERR_BAD_LEN);
                                tx_buf[5] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_len    <= 5'd6;
                            tx_trigger <= 1'b1;
                        end else begin
                            case (rx_payload[0])
                                8'h00: begin  // id loop
                                    kp_id <= $signed({rx_payload[2], rx_payload[1]});
                                    ki_id <= $signed({rx_payload[4], rx_payload[3]});
                                end
                                8'h01: begin  // iq loop
                                    kp_iq <= $signed({rx_payload[2], rx_payload[1]});
                                    ki_iq <= $signed({rx_payload[4], rx_payload[3]});
                                end
                                8'h02: begin  // speed loop
                                    kp_speed <= $signed({rx_payload[2], rx_payload[1]});
                                    ki_speed <= $signed({rx_payload[4], rx_payload[3]});
                                end
                                8'h03: begin  // pos loop (only kp meaningful)
                                    kp_pos <= $signed({rx_payload[2], rx_payload[1]});
                                end
                                default: ;
                            endcase
                            begin : ack_set_gains
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_ACK);
                                c = crc8_update(c,     8'h01);
                                c = crc8_update(c,     rx_cmd);
                                tx_buf[4] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_len    <= 5'd5;
                            tx_trigger <= 1'b1;
                        end
                    end

                    // ----------------------------------------------------------
                    // GET_STATUS – reply with STATUS frame immediately
                    CMD_GET_STATUS: begin
                        begin : build_status_on_request
                            reg [7:0] c;
                            // STATUS payload (17 bytes):
                            //   mode(1), enable(1), fault(1),
                            //   pos(2 LE), speed(2 LE),
                            //   id(2 LE), iq(2 LE),
                            //   pwm_a(2 LE), pwm_b(2 LE), pwm_c(2 LE)
                            tx_buf[0]  <= SYNC_BYTE;
                            tx_buf[1]  <= RSP_STATUS;
                            tx_buf[2]  <= 8'h11;          // 17 bytes payload
                            tx_buf[3]  <= mode;
                            tx_buf[4]  <= {7'h00, enable};
                            tx_buf[5]  <= {7'h00, foc_fault};
                            tx_buf[6]  <= dbg_pos[7:0];
                            tx_buf[7]  <= dbg_pos[15:8];
                            tx_buf[8]  <= dbg_speed[7:0];
                            tx_buf[9]  <= dbg_speed[15:8];
                            tx_buf[10] <= dbg_id[7:0];
                            tx_buf[11] <= dbg_id[15:8];
                            tx_buf[12] <= dbg_iq[7:0];
                            tx_buf[13] <= dbg_iq[15:8];
                            tx_buf[14] <= dbg_pwm_a[7:0];
                            tx_buf[15] <= dbg_pwm_a[15:8];
                            tx_buf[16] <= dbg_pwm_b[7:0];
                            tx_buf[17] <= dbg_pwm_b[15:8];
                            tx_buf[18] <= dbg_pwm_c[7:0];
                            tx_buf[19] <= dbg_pwm_c[15:8];
                            // CRC over CMD + LEN + PAYLOAD
                            c = crc8_update(8'h00, RSP_STATUS);
                            c = crc8_update(c,     8'h11);
                            c = crc8_update(c,     mode);
                            c = crc8_update(c,     {7'h00, enable});
                            c = crc8_update(c,     {7'h00, foc_fault});
                            c = crc8_update(c,     dbg_pos[7:0]);
                            c = crc8_update(c,     dbg_pos[15:8]);
                            c = crc8_update(c,     dbg_speed[7:0]);
                            c = crc8_update(c,     dbg_speed[15:8]);
                            c = crc8_update(c,     dbg_id[7:0]);
                            c = crc8_update(c,     dbg_id[15:8]);
                            c = crc8_update(c,     dbg_iq[7:0]);
                            c = crc8_update(c,     dbg_iq[15:8]);
                            c = crc8_update(c,     dbg_pwm_a[7:0]);
                            c = crc8_update(c,     dbg_pwm_a[15:8]);
                            c = crc8_update(c,     dbg_pwm_b[7:0]);
                            c = crc8_update(c,     dbg_pwm_b[15:8]);
                            c = crc8_update(c,     dbg_pwm_c[7:0]);
                            c = crc8_update(c,     dbg_pwm_c[15:8]);
                            tx_buf[20] <= c;
                            tx_len     <= 5'd21;
                        end
                        tx_trigger <= 1'b1;
                    end

                    // ----------------------------------------------------------
                    CMD_STREAM_START: begin
                        if (rx_len != 8'h01) begin
                            begin : nack_stream_start_len
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_NACK);
                                c = crc8_update(c,     8'h02);
                                c = crc8_update(c,     rx_cmd);
                                c = crc8_update(c,     ERR_BAD_LEN);
                                tx_buf[5] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_len    <= 5'd6;
                            tx_trigger <= 1'b1;
                        end else begin
                            stream_period <= (rx_payload[0] == 8'h00) ? 8'h01
                                                                        : rx_payload[0];
                            stream_active <= 1'b1;
                            ms_cnt        <= 16'd0;
                            begin : ack_stream_start
                                reg [7:0] c;
                                c = crc8_update(8'h00, RSP_ACK);
                                c = crc8_update(c,     8'h01);
                                c = crc8_update(c,     rx_cmd);
                                tx_buf[4] <= c;
                            end
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_len    <= 5'd5;
                            tx_trigger <= 1'b1;
                        end
                    end

                    // ----------------------------------------------------------
                    CMD_STREAM_STOP: begin
                        stream_active <= 1'b0;
                        ms_cnt        <= 16'd0;
                        begin : ack_stream_stop
                            reg [7:0] c;
                            c = crc8_update(8'h00, RSP_ACK);
                            c = crc8_update(c,     8'h01);
                            c = crc8_update(c,     rx_cmd);
                            tx_buf[4] <= c;
                        end
                        tx_buf[0] <= SYNC_BYTE;
                        tx_buf[1] <= RSP_ACK;
                        tx_buf[2] <= 8'h01;
                        tx_buf[3] <= rx_cmd;
                        tx_len    <= 5'd5;
                        tx_trigger <= 1'b1;
                    end

                    // ----------------------------------------------------------
                    CMD_RESET: begin
                        // Soft reset all control outputs and gains
                        enable        <= 1'b0;
                        mode          <= 8'h00;
                        cmd_iq_ref    <= 16'sd0;
                        cmd_speed_ref <= 16'sd0;
                        cmd_pos_ref   <= 16'h0000;
                        kp_id         <= 16'sd128;
                        ki_id         <= 16'sd16;
                        kp_iq         <= 16'sd128;
                        ki_iq         <= 16'sd16;
                        kp_speed      <= 16'sd64;
                        ki_speed      <= 16'sd4;
                        kp_pos        <= 16'sd32;
                        stream_active <= 1'b0;
                        ms_cnt        <= 16'd0;
                        begin : ack_reset
                            reg [7:0] c;
                            c = crc8_update(8'h00, RSP_ACK);
                            c = crc8_update(c,     8'h01);
                            c = crc8_update(c,     rx_cmd);
                            tx_buf[4] <= c;
                        end
                        tx_buf[0] <= SYNC_BYTE;
                        tx_buf[1] <= RSP_ACK;
                        tx_buf[2] <= 8'h01;
                        tx_buf[3] <= rx_cmd;
                        tx_len    <= 5'd5;
                        tx_trigger <= 1'b1;
                    end

                    // ----------------------------------------------------------
                    default: begin
                        // Unknown command
                        begin : nack_unknown
                            reg [7:0] c;
                            c = crc8_update(8'h00, RSP_NACK);
                            c = crc8_update(c,     8'h02);
                            c = crc8_update(c,     rx_cmd);
                            c = crc8_update(c,     ERR_UNKNOWN_CMD);
                            tx_buf[5] <= c;
                        end
                        tx_buf[0] <= SYNC_BYTE;
                        tx_buf[1] <= RSP_NACK;
                        tx_buf[2] <= 8'h02;
                        tx_buf[3] <= rx_cmd;
                        tx_buf[4] <= ERR_UNKNOWN_CMD;
                        tx_len    <= 5'd6;
                        tx_trigger <= 1'b1;
                    end

                endcase // rx_cmd
            end // CRC OK
        end // RX_DISPATCH

        // =====================================================================
        // Streaming STATUS trigger
        // When stream_trigger fires and TX is idle, load STATUS frame.
        // =====================================================================
        if (stream_trigger && (tx_state == TX_IDLE) && !tx_trigger) begin
            begin : build_status_stream
                reg [7:0] c;
                tx_buf[0]  <= SYNC_BYTE;
                tx_buf[1]  <= RSP_STATUS;
                tx_buf[2]  <= 8'h11;
                tx_buf[3]  <= mode;
                tx_buf[4]  <= {7'h00, enable};
                tx_buf[5]  <= {7'h00, foc_fault};
                tx_buf[6]  <= dbg_pos[7:0];
                tx_buf[7]  <= dbg_pos[15:8];
                tx_buf[8]  <= dbg_speed[7:0];
                tx_buf[9]  <= dbg_speed[15:8];
                tx_buf[10] <= dbg_id[7:0];
                tx_buf[11] <= dbg_id[15:8];
                tx_buf[12] <= dbg_iq[7:0];
                tx_buf[13] <= dbg_iq[15:8];
                tx_buf[14] <= dbg_pwm_a[7:0];
                tx_buf[15] <= dbg_pwm_a[15:8];
                tx_buf[16] <= dbg_pwm_b[7:0];
                tx_buf[17] <= dbg_pwm_b[15:8];
                tx_buf[18] <= dbg_pwm_c[7:0];
                tx_buf[19] <= dbg_pwm_c[15:8];
                c = crc8_update(8'h00, RSP_STATUS);
                c = crc8_update(c,     8'h11);
                c = crc8_update(c,     mode);
                c = crc8_update(c,     {7'h00, enable});
                c = crc8_update(c,     {7'h00, foc_fault});
                c = crc8_update(c,     dbg_pos[7:0]);
                c = crc8_update(c,     dbg_pos[15:8]);
                c = crc8_update(c,     dbg_speed[7:0]);
                c = crc8_update(c,     dbg_speed[15:8]);
                c = crc8_update(c,     dbg_id[7:0]);
                c = crc8_update(c,     dbg_id[15:8]);
                c = crc8_update(c,     dbg_iq[7:0]);
                c = crc8_update(c,     dbg_iq[15:8]);
                c = crc8_update(c,     dbg_pwm_a[7:0]);
                c = crc8_update(c,     dbg_pwm_a[15:8]);
                c = crc8_update(c,     dbg_pwm_b[7:0]);
                c = crc8_update(c,     dbg_pwm_b[15:8]);
                c = crc8_update(c,     dbg_pwm_c[7:0]);
                c = crc8_update(c,     dbg_pwm_c[15:8]);
                tx_buf[20] <= c;
                tx_len     <= 5'd21;
            end
            tx_trigger <= 1'b1;
        end

        // =====================================================================
        // TX state machine
        // =====================================================================
        case (tx_state)

            TX_IDLE: begin
                uart_tx_valid <= 1'b0;
                if (tx_trigger) begin
                    tx_idx    <= 5'd0;
                    tx_state  <= TX_SEND;
                end
            end

            TX_SEND: begin
                // Present the next byte; assert valid
                uart_tx_data  <= tx_buf[tx_idx];
                uart_tx_valid <= 1'b1;
                tx_state      <= TX_WAIT;
            end

            TX_WAIT: begin
                if (uart_tx_ready && uart_tx_valid) begin
                    uart_tx_valid <= 1'b0;
                    if (tx_idx == tx_len - 5'd1) begin
                        // All bytes sent
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_idx   <= tx_idx + 5'd1;
                        tx_state <= TX_SEND;
                    end
                end
                // If tx_trigger fires while we're busy, it is dropped.
                // A production design might use a FIFO here.
            end

            default: tx_state <= TX_IDLE;
        endcase

    end // rst_n
end // always

endmodule

`default_nettype wire
