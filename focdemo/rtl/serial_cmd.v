`default_nettype none

// =============================================================================
// serial_cmd.v  –  Binary serial command handler for the FOC controller
//
// Frame format (host → FPGA):
//   [0xA5 sync][CMD 1B][LEN 1B][PAYLOAD 0-32B][CRC8 1B]
//
// CRC-8/MAXIM: polynomial 0x31, computed over CMD + LEN + PAYLOAD
//
// TX CRC is computed on-the-fly: as each byte is transmitted via UART, the
// CRC accumulator is updated. After the last data byte, the CRC is sent
// automatically. This uses a single crc8_update instance instead of
// duplicated combinational CRC chains.
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
    input  wire [10:0] drv_fault_reg,
    input  wire [15:0] dbg_pos,
    input  wire signed [15:0] dbg_speed,
    input  wire signed [15:0] dbg_id,
    input  wire signed [15:0] dbg_iq,
    input  wire [15:0] dbg_ia,
    input  wire [15:0] dbg_ib,
    input  wire [15:0] dbg_ic,
    input  wire [15:0] dbg_enc
);

// =============================================================================
// Parameters
// =============================================================================

localparam MS_CYCLES = 48_000;
localparam MAX_PAYLOAD = 6;
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

// ---- TX buffer (holds SYNC + CMD + LEN + PAYLOAD, CRC computed on-the-fly) --
localparam TX_BUF_SIZE = 25;   // max: 1 sync + 1 cmd + 1 len + 21 payload + 1 unused

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
reg [5:0]  rx_payload_idx;
reg [7:0]  rx_crc_got;
reg [7:0]  rx_crc_calc;

// =============================================================================
// TX state machine
//
// tx_buf holds data bytes (SYNC + CMD + LEN + PAYLOAD).
// tx_data_len = number of data bytes in tx_buf (excluding CRC).
// TX FSM sends tx_buf[0..tx_data_len-1], computing CRC over bytes 1..N-1
// (skipping sync at index 0), then sends the CRC byte automatically.
// =============================================================================

localparam TX_IDLE     = 2'd0;
localparam TX_SEND     = 2'd1;
localparam TX_WAIT     = 2'd2;

reg [1:0]  tx_state;
reg [7:0]  tx_buf   [0:TX_BUF_SIZE-1];
reg [4:0]  tx_data_len;     // number of data bytes (no CRC)
reg [4:0]  tx_idx;
reg        tx_trigger;
reg [7:0]  tx_crc;          // on-the-fly CRC accumulator
reg        tx_crc_phase;    // true when sending the final CRC byte

// =============================================================================
// Streaming
// =============================================================================

reg        stream_active;
reg [7:0]  stream_period;
reg [7:0]  ms_cnt;
reg [15:0] clk_cnt;
reg        stream_trigger;

// =============================================================================
// CRC-8/MAXIM helper
// =============================================================================

function [7:0] crc8_update;
    input [7:0] crc_in;
    input [7:0] data_in;
    integer     i;
    reg   [7:0] c;
    begin
        c = crc_in ^ data_in;
        for (i = 0; i < 8; i = i + 1) begin
            if (c[0])
                c = (c >> 1) ^ 8'h8C;
            else
                c = c >> 1;
        end
        crc8_update = c;
    end
endfunction

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
        tx_state     <= TX_IDLE;
        tx_data_len  <= 5'd0;
        tx_idx       <= 5'd0;
        tx_trigger   <= 1'b0;
        tx_crc       <= 8'h00;
        tx_crc_phase <= 1'b0;
        uart_tx_data  <= 8'h00;
        uart_tx_valid <= 1'b0;

        // -- Streaming --------------------------------------------------------
        stream_active  <= 1'b0;
        stream_period  <= 8'd10;
        ms_cnt         <= 8'd0;
        clk_cnt        <= 16'd0;
        stream_trigger <= 1'b0;

        // -- FOC control outputs ----------------------------------------------
        enable        <= 1'b0;
        mode          <= 8'h00;
        cmd_iq_ref    <= 16'sd2000;  // default torque limit for speed/position modes
        cmd_speed_ref <= 16'sd0;
        cmd_pos_ref   <= 16'h0000;

        // -- Gain defaults ----------------------------------------------------
        kp_id    <= 16'sd128;
        ki_id    <= 16'sd16;
        kp_iq    <= 16'sd128;
        ki_iq    <= 16'sd16;
        kp_speed <= 16'sd1024;
        ki_speed <= 16'sd128;
        kp_pos   <= 16'sd512;

        // -- Clear buffers ----------------------------------------------------
        for (i = 0; i < MAX_PAYLOAD; i = i + 1)
            rx_payload[i] <= 8'h00;
        for (i = 0; i < TX_BUF_SIZE; i = i + 1)
            tx_buf[i] <= 8'h00;

    end else begin

        // =====================================================================
        // Default pulse signals
        // =====================================================================
        tx_trigger     <= 1'b0;
        stream_trigger <= 1'b0;

        // =====================================================================
        // Millisecond timer
        // =====================================================================
        if (clk_cnt >= MS_CYCLES - 1) begin
            clk_cnt <= 16'd0;
            if (stream_active) begin
                if (ms_cnt >= (stream_period - 8'd1)) begin
                    ms_cnt         <= 8'd0;
                    stream_trigger <= 1'b1;
                end else begin
                    ms_cnt <= ms_cnt + 8'd1;
                end
            end else begin
                ms_cnt <= 8'd0;
            end
        end else begin
            clk_cnt <= clk_cnt + 16'd1;
        end

        // =====================================================================
        // RX state machine
        // =====================================================================
        if (uart_rx_valid) begin
            case (rx_state)

                RX_SYNC: begin
                    if (uart_rx_data == SYNC_BYTE) begin
                        rx_state    <= RX_CMD;
                        rx_crc_calc <= 8'h00;
                    end
                end

                RX_CMD: begin
                    rx_cmd      <= uart_rx_data;
                    rx_crc_calc <= crc8_update(8'h00, uart_rx_data);
                    rx_state    <= RX_LEN;
                end

                RX_LEN: begin
                    rx_len      <= uart_rx_data;
                    rx_crc_calc <= crc8_update(rx_crc_calc, uart_rx_data);
                    rx_payload_idx <= 6'd0;
                    if (uart_rx_data == 8'h00)
                        rx_state <= RX_CRC;
                    else if (uart_rx_data > MAX_PAYLOAD)
                        rx_state <= RX_SYNC;
                    else
                        rx_state <= RX_PAYLOAD;
                end

                RX_PAYLOAD: begin
                    rx_payload[rx_payload_idx] <= uart_rx_data;
                    rx_crc_calc <= crc8_update(rx_crc_calc, uart_rx_data);
                    if (rx_payload_idx == (rx_len - 8'h01))
                        rx_state <= RX_CRC;
                    else
                        rx_payload_idx <= rx_payload_idx + 6'd1;
                end

                RX_CRC: begin
                    rx_crc_got <= uart_rx_data;
                    rx_state   <= RX_DISPATCH;
                end

                RX_DISPATCH: begin
                    rx_state <= RX_SYNC;
                end

                default: rx_state <= RX_SYNC;
            endcase
        end

        // =====================================================================
        // Dispatch (evaluated every cycle, not gated by uart_rx_valid)
        // =====================================================================
        if (rx_state == RX_DISPATCH) begin
            rx_state <= RX_SYNC;

            if (rx_crc_got != rx_crc_calc) begin
                // CRC error: NACK
                tx_buf[0] <= SYNC_BYTE;
                tx_buf[1] <= RSP_NACK;
                tx_buf[2] <= 8'h02;
                tx_buf[3] <= rx_cmd;
                tx_buf[4] <= ERR_BAD_CRC;
                tx_data_len <= 5'd5;
                tx_trigger  <= 1'b1;

            end else begin
                case (rx_cmd)

                    CMD_SET_MODE: begin
                        if (rx_len != 8'h01) begin
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_data_len <= 5'd5;
                            tx_trigger  <= 1'b1;
                        end else begin
                            mode <= rx_payload[0];
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_data_len <= 5'd4;
                            tx_trigger  <= 1'b1;
                        end
                    end

                    CMD_SET_TORQUE: begin
                        if (rx_len != 8'h02) begin
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_data_len <= 5'd5;
                            tx_trigger  <= 1'b1;
                        end else begin
                            cmd_iq_ref <= $signed({rx_payload[1], rx_payload[0]});
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_data_len <= 5'd4;
                            tx_trigger  <= 1'b1;
                        end
                    end

                    CMD_SET_SPEED: begin
                        if (rx_len != 8'h02) begin
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_data_len <= 5'd5;
                            tx_trigger  <= 1'b1;
                        end else begin
                            cmd_speed_ref <= $signed({rx_payload[1], rx_payload[0]});
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_data_len <= 5'd4;
                            tx_trigger  <= 1'b1;
                        end
                    end

                    CMD_SET_POS: begin
                        if (rx_len != 8'h02) begin
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_data_len <= 5'd5;
                            tx_trigger  <= 1'b1;
                        end else begin
                            cmd_pos_ref <= {rx_payload[1], rx_payload[0]};
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_data_len <= 5'd4;
                            tx_trigger  <= 1'b1;
                        end
                    end

                    CMD_SET_ENABLE: begin
                        if (rx_len != 8'h01) begin
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_data_len <= 5'd5;
                            tx_trigger  <= 1'b1;
                        end else begin
                            enable <= rx_payload[0][0];
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_data_len <= 5'd4;
                            tx_trigger  <= 1'b1;
                        end
                    end

                    CMD_SET_GAINS: begin
                        if (rx_len != 8'h05) begin
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_data_len <= 5'd5;
                            tx_trigger  <= 1'b1;
                        end else begin
                            case (rx_payload[0])
                                8'h00: begin
                                    kp_id <= $signed({rx_payload[2], rx_payload[1]});
                                    ki_id <= $signed({rx_payload[4], rx_payload[3]});
                                end
                                8'h01: begin
                                    kp_iq <= $signed({rx_payload[2], rx_payload[1]});
                                    ki_iq <= $signed({rx_payload[4], rx_payload[3]});
                                end
                                8'h02: begin
                                    kp_speed <= $signed({rx_payload[2], rx_payload[1]});
                                    ki_speed <= $signed({rx_payload[4], rx_payload[3]});
                                end
                                8'h03: begin
                                    kp_pos <= $signed({rx_payload[2], rx_payload[1]});
                                end
                                default: ;
                            endcase
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_data_len <= 5'd4;
                            tx_trigger  <= 1'b1;
                        end
                    end

                    CMD_GET_STATUS: begin
                        tx_buf[0]  <= SYNC_BYTE;
                        tx_buf[1]  <= RSP_STATUS;
                        tx_buf[2]  <= 8'h15;       // 21 bytes payload
                        tx_buf[3]  <= mode;
                        tx_buf[4]  <= {7'h00, enable};
                        tx_buf[5]  <= {7'h00, foc_fault};
                        tx_buf[6]  <= drv_fault_reg[7:0];
                        tx_buf[7]  <= {5'h00, drv_fault_reg[10:8]};
                        tx_buf[8]  <= dbg_pos[7:0];
                        tx_buf[9]  <= dbg_pos[15:8];
                        tx_buf[10] <= dbg_speed[7:0];
                        tx_buf[11] <= dbg_speed[15:8];
                        tx_buf[12] <= dbg_id[7:0];
                        tx_buf[13] <= dbg_id[15:8];
                        tx_buf[14] <= dbg_iq[7:0];
                        tx_buf[15] <= dbg_iq[15:8];
                        tx_buf[16] <= dbg_ia[7:0];
                        tx_buf[17] <= dbg_ia[15:8];
                        tx_buf[18] <= dbg_ib[7:0];
                        tx_buf[19] <= dbg_ib[15:8];
                        tx_buf[20] <= dbg_ic[7:0];
                        tx_buf[21] <= dbg_ic[15:8];
                        tx_buf[22] <= dbg_enc[7:0];
                        tx_buf[23] <= dbg_enc[15:8];
                        tx_data_len <= 5'd24;
                        tx_trigger  <= 1'b1;
                    end

                    CMD_STREAM_START: begin
                        if (rx_len != 8'h01) begin
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_NACK;
                            tx_buf[2] <= 8'h02;
                            tx_buf[3] <= rx_cmd;
                            tx_buf[4] <= ERR_BAD_LEN;
                            tx_data_len <= 5'd5;
                            tx_trigger  <= 1'b1;
                        end else begin
                            stream_period <= (rx_payload[0] == 8'h00) ? 8'h01
                                                                        : rx_payload[0];
                            stream_active <= 1'b1;
                            ms_cnt        <= 8'd0;
                            tx_buf[0] <= SYNC_BYTE;
                            tx_buf[1] <= RSP_ACK;
                            tx_buf[2] <= 8'h01;
                            tx_buf[3] <= rx_cmd;
                            tx_data_len <= 5'd4;
                            tx_trigger  <= 1'b1;
                        end
                    end

                    CMD_STREAM_STOP: begin
                        stream_active <= 1'b0;
                        ms_cnt        <= 8'd0;
                        tx_buf[0] <= SYNC_BYTE;
                        tx_buf[1] <= RSP_ACK;
                        tx_buf[2] <= 8'h01;
                        tx_buf[3] <= rx_cmd;
                        tx_data_len <= 5'd4;
                        tx_trigger  <= 1'b1;
                    end

                    CMD_RESET: begin
                        enable        <= 1'b0;
                        mode          <= 8'h00;
                        cmd_iq_ref    <= 16'sd2000;
                        cmd_speed_ref <= 16'sd0;
                        cmd_pos_ref   <= 16'h0000;
                        kp_id         <= 16'sd128;
                        ki_id         <= 16'sd16;
                        kp_iq         <= 16'sd128;
                        ki_iq         <= 16'sd16;
                        kp_speed      <= 16'sd1024;
                        ki_speed      <= 16'sd128;
                        kp_pos        <= 16'sd512;
                        stream_active <= 1'b0;
                        ms_cnt        <= 8'd0;
                        tx_buf[0] <= SYNC_BYTE;
                        tx_buf[1] <= RSP_ACK;
                        tx_buf[2] <= 8'h01;
                        tx_buf[3] <= rx_cmd;
                        tx_data_len <= 5'd4;
                        tx_trigger  <= 1'b1;
                    end

                    default: begin
                        tx_buf[0] <= SYNC_BYTE;
                        tx_buf[1] <= RSP_NACK;
                        tx_buf[2] <= 8'h02;
                        tx_buf[3] <= rx_cmd;
                        tx_buf[4] <= ERR_UNKNOWN_CMD;
                        tx_data_len <= 5'd5;
                        tx_trigger  <= 1'b1;
                    end

                endcase
            end
        end

        // =====================================================================
        // Streaming STATUS trigger
        // =====================================================================
        if (stream_trigger && (tx_state == TX_IDLE) && !tx_trigger) begin
            tx_buf[0]  <= SYNC_BYTE;
            tx_buf[1]  <= RSP_STATUS;
            tx_buf[2]  <= 8'h15;       // 21 bytes payload
            tx_buf[3]  <= mode;
            tx_buf[4]  <= {7'h00, enable};
            tx_buf[5]  <= {7'h00, foc_fault};
            tx_buf[6]  <= drv_fault_reg[7:0];
            tx_buf[7]  <= {5'h00, drv_fault_reg[10:8]};
            tx_buf[8]  <= dbg_pos[7:0];
            tx_buf[9]  <= dbg_pos[15:8];
            tx_buf[10] <= dbg_speed[7:0];
            tx_buf[11] <= dbg_speed[15:8];
            tx_buf[12] <= dbg_id[7:0];
            tx_buf[13] <= dbg_id[15:8];
            tx_buf[14] <= dbg_iq[7:0];
            tx_buf[15] <= dbg_iq[15:8];
            tx_buf[16] <= dbg_ia[7:0];
            tx_buf[17] <= dbg_ia[15:8];
            tx_buf[18] <= dbg_ib[7:0];
            tx_buf[19] <= dbg_ib[15:8];
            tx_buf[20] <= dbg_ic[7:0];
            tx_buf[21] <= dbg_ic[15:8];
            tx_buf[22] <= dbg_enc[7:0];
            tx_buf[23] <= dbg_enc[15:8];
            tx_data_len <= 5'd24;
            tx_trigger  <= 1'b1;
        end

        // =====================================================================
        // TX state machine with on-the-fly CRC
        //
        // Sends tx_buf[0..tx_data_len-1], then appends CRC byte.
        // CRC accumulates over bytes 1..tx_data_len-1 (skipping sync at [0]).
        // =====================================================================
        case (tx_state)

            TX_IDLE: begin
                uart_tx_valid <= 1'b0;
                if (tx_trigger) begin
                    tx_idx       <= 5'd0;
                    tx_crc       <= 8'h00;
                    tx_crc_phase <= 1'b0;
                    tx_state     <= TX_SEND;
                end
            end

            TX_SEND: begin
                if (tx_crc_phase) begin
                    // Send the accumulated CRC byte
                    uart_tx_data <= tx_crc;
                end else begin
                    // Send next data byte from buffer
                    uart_tx_data <= tx_buf[tx_idx];
                end
                uart_tx_valid <= 1'b1;
                tx_state      <= TX_WAIT;
            end

            TX_WAIT: begin
                if (uart_tx_ready && uart_tx_valid) begin
                    uart_tx_valid <= 1'b0;

                    if (tx_crc_phase) begin
                        // CRC byte sent — frame complete
                        tx_state <= TX_IDLE;
                    end else begin
                        // Update CRC with the byte we just sent (skip sync at idx 0)
                        if (tx_idx > 5'd0)
                            tx_crc <= crc8_update(tx_crc, uart_tx_data);

                        if (tx_idx == tx_data_len - 5'd1) begin
                            // Last data byte sent — send CRC next
                            tx_crc_phase <= 1'b1;
                            tx_state     <= TX_SEND;
                        end else begin
                            tx_idx   <= tx_idx + 5'd1;
                            tx_state <= TX_SEND;
                        end
                    end
                end
            end

            default: tx_state <= TX_IDLE;
        endcase

    end // rst_n
end // always

endmodule

`default_nettype wire
