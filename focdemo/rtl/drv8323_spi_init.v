`default_nettype none

// ----------------------------------------------------------------------------
// drv8323_spi_init.v
//
// One-shot SPI initialisation state machine for the DRV8323RX gate driver.
//
// SPI Mode 1 (CPOL=0, CPHA=1):
//   - SCLK idles low
//   - Data is captured on the FALLING edge of SCLK (SDI/SDO driven on rising)
//   - 16-bit frames, MSB first
//   - CS (spi_ncs) active low
//
// Clock: 48 MHz system clock
// SPI clock target: ~1 MHz  →  divider = 24  (half-period = 24 clocks)
//
// Configuration sequence:
//   1. Wait ~10 ms power-up delay (480 000 system clocks)
//   2. Write 0x02 (Driver Control)  frame 16'h0400
//   3. Write 0x05 (OCP Control)     frame 16'h0A96
//   4. Write 0x06 (CSA Control)     frame 16'h0C80
//   5. Read  0x01 (Fault Status)    frame 16'h8800  → capture 11 data bits
//   6. Assert init_done; assert init_fault if fault bits ≠ 0
// ----------------------------------------------------------------------------

module drv8323_spi_init (
    input  wire clk,        // 48 MHz system clock
    input  wire rst_n,      // active-low synchronous reset

    output reg  spi_sclk,   // SPI clock to DRV8323
    output reg  spi_sdi,    // MOSI: FPGA → DRV8323
    input  wire spi_sdo,    // MISO: DRV8323 → FPGA
    output reg  spi_ncs,    // chip-select, active low

    output reg  init_done,  // pulses / latches high when sequence complete
    output reg  init_fault  // latches high if fault register non-zero
);

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
localparam CLK_FREQ       = 48_000_000;
localparam SPI_HALF_PER   = 24;          // half-period counts → ~1 MHz SCLK
localparam POWERUP_CYCLES = 480_000;     // ~10 ms at 48 MHz
localparam CS_SETUP       = 4;           // CS assert → first SCLK edge (clks)
localparam CS_HOLD        = 4;           // last SCLK edge → CS deassert (clks)
localparam INTER_GAP      = 96;          // inter-frame gap (clks, ≥ 2 SCLK periods)

// Number of SPI frames
localparam NUM_FRAMES     = 4;
localparam FRAME_BITS     = 16;

// ---------------------------------------------------------------------------
// SPI frame ROM
// ---------------------------------------------------------------------------
// Index 0-2: writes; index 3: fault-status read
reg [15:0] frame_rom [0:NUM_FRAMES-1];
initial begin
    frame_rom[0] = 16'h0400; // W=0, ADDR=0x02, DATA=0x000 – Driver Control
    frame_rom[1] = 16'h0A96; // W=0, ADDR=0x05, DATA=0x096 – OCP Control
    frame_rom[2] = 16'h0C80; // W=0, ADDR=0x06, DATA=0x080 – CSA Control (gain=40)
    frame_rom[3] = 16'h8800; // R=1, ADDR=0x01, DATA=x     – Fault Status read
end

// ---------------------------------------------------------------------------
// State encoding
// ---------------------------------------------------------------------------
localparam [3:0]
    S_IDLE      = 4'd0,  // power-up delay
    S_CS_SETUP  = 4'd1,  // assert CS, wait setup time
    S_LOAD      = 4'd2,  // latch current frame into shift register
    S_SHIFT     = 4'd3,  // clock out/in 16 bits
    S_CS_HOLD   = 4'd4,  // deassert CS, wait hold time
    S_GAP       = 4'd5,  // inter-frame idle
    S_DONE      = 4'd6;  // all frames complete

// ---------------------------------------------------------------------------
// Registers
// ---------------------------------------------------------------------------
reg [3:0]  state;

// Delay / bit counters
reg [19:0] delay_cnt;    // up to 480 000 – needs 19 bits (2^19 = 524288 > 480000)
reg [4:0]  bit_cnt;      // 0..15 (16 bits per frame)
reg [2:0]  frame_idx;    // 0..3

// SPI clock divider
reg [4:0]  sclk_cnt;     // counts up to SPI_HALF_PER-1

// Shift register
reg [15:0] shift_reg;
reg [10:0] rx_data;      // captured MISO bits (11 data bits of last frame)

// Edge flags (single-cycle pulses in current clock domain)
wire sclk_rise_en;
wire sclk_fall_en;

// ---------------------------------------------------------------------------
// SPI clock divider
// sclk_cnt runs continuously while shifting; spi_sclk toggles each half period.
// sclk_rise_en / sclk_fall_en are one-cycle early-warning strobes so that
// state transitions and data capture happen on the same clock edge as SCLK.
// ---------------------------------------------------------------------------
// We generate SCLK only during S_SHIFT; it is held low at all other times.
// Because CPHA=1, the first (falling) SCLK edge clocks in bit 15 (MSB) of
// the frame; we drive SDI *before* CS asserts, so it is valid for the first
// falling edge.
//
// Timing inside S_SHIFT for one bit cycle (2 × SPI_HALF_PER = 48 clks):
//
//   sclk_cnt 0..23:  SCLK=0  (low half – drive phase)
//     At cnt==SPI_HALF_PER-1 → sclk_fall_en (transition to high half + toggle)
//
//   sclk_cnt 24..47: SCLK=1  (high half – capture phase)
//     At cnt==SPI_HALF_PER*2-2 → sclk_rise_en (transition to low half + toggle)
//
// Because CPHA=1 we sample SDO on the falling edge and update SDI on the
// rising edge (before the next falling edge).
// ---------------------------------------------------------------------------

// Generate SCLK in S_SHIFT only
always @(posedge clk) begin
    if (!rst_n) begin
        spi_sclk <= 1'b0;
        sclk_cnt <= 5'd0;
    end else if (state == S_SHIFT) begin
        if (sclk_cnt == SPI_HALF_PER - 1) begin
            spi_sclk <= ~spi_sclk;
            sclk_cnt <= 5'd0;
        end else begin
            sclk_cnt <= sclk_cnt + 5'd1;
        end
    end else begin
        spi_sclk <= 1'b0;
        sclk_cnt <= 5'd0;
    end
end

// sclk_fall_en: one clock *before* SCLK goes from 1→0 (i.e., on the last
//   count of the high half when spi_sclk is currently 1)
// sclk_rise_en: one clock *before* SCLK goes from 0→1 (i.e., on the last
//   count of the low half when spi_sclk is currently 0)
assign sclk_fall_en = (state == S_SHIFT) &&
                      (sclk_cnt == SPI_HALF_PER - 1) &&
                      (spi_sclk == 1'b1);

assign sclk_rise_en = (state == S_SHIFT) &&
                      (sclk_cnt == SPI_HALF_PER - 1) &&
                      (spi_sclk == 1'b0);

// ---------------------------------------------------------------------------
// Main state machine
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (!rst_n) begin
        state      <= S_IDLE;
        delay_cnt  <= 20'd0;
        bit_cnt    <= 5'd0;
        frame_idx  <= 3'd0;
        spi_ncs    <= 1'b1;
        spi_sdi    <= 1'b0;
        shift_reg  <= 16'd0;
        rx_data    <= 11'd0;
        init_done  <= 1'b0;
        init_fault <= 1'b0;
    end else begin
        case (state)

            // ------------------------------------------------------------------
            // S_IDLE – count down the power-up delay
            // ------------------------------------------------------------------
            S_IDLE: begin
                spi_ncs   <= 1'b1;
                spi_sdi   <= 1'b0;
                if (delay_cnt == POWERUP_CYCLES - 1) begin
                    delay_cnt <= 20'd0;
                    state     <= S_CS_SETUP;
                end else begin
                    delay_cnt <= delay_cnt + 20'd1;
                end
            end

            // ------------------------------------------------------------------
            // S_CS_SETUP – assert CS and pre-drive first data bit, then wait
            // ------------------------------------------------------------------
            S_CS_SETUP: begin
                spi_ncs <= 1'b0;
                // Pre-load shift register so spi_sdi is valid before first SCLK↓
                shift_reg <= frame_rom[frame_idx];
                spi_sdi   <= frame_rom[frame_idx][15];
                if (delay_cnt == CS_SETUP - 1) begin
                    delay_cnt <= 20'd0;
                    state     <= S_LOAD;
                end else begin
                    delay_cnt <= delay_cnt + 20'd1;
                end
            end

            // ------------------------------------------------------------------
            // S_LOAD – latch the frame (shift_reg already loaded in CS_SETUP)
            //          and set bit counter, then start clocking
            // ------------------------------------------------------------------
            S_LOAD: begin
                bit_cnt <= 5'd0;
                state   <= S_SHIFT;
            end

            // ------------------------------------------------------------------
            // S_SHIFT – clock 16 bits MSB first
            //
            // SPI Mode 1 (CPHA=1):
            //   Falling SCLK edge → capture SDO (DRV drives SDO on its rising)
            //   Rising  SCLK edge → update SDI for the next bit
            // ------------------------------------------------------------------
            S_SHIFT: begin
                // --- Falling edge: sample MISO ---
                if (sclk_fall_en) begin
                    // Shift received bit into rx_data (only lower 11 meaningful
                    // for the fault-status frame; harmless for writes)
                    rx_data <= {rx_data[9:0], spi_sdo};

                    // Count the completed bit
                    if (bit_cnt == FRAME_BITS - 1) begin
                        // All bits done – move on
                        bit_cnt <= 5'd0;
                        state   <= S_CS_HOLD;
                    end else begin
                        bit_cnt <= bit_cnt + 5'd1;
                    end
                end

                // --- Rising edge: drive next MOSI bit ---
                if (sclk_rise_en) begin
                    // Shift register: drive bit (14 - bit_cnt) next
                    // After the falling edge incremented bit_cnt, the next bit
                    // to drive is shift_reg[14 - bit_cnt] ... but we update
                    // sdi here for the *upcoming* falling edge.
                    // shift_reg bit to send = index 14 down to 0 after bit 15.
                    shift_reg <= {shift_reg[14:0], 1'b0};
                    spi_sdi   <= shift_reg[14]; // next MSB after left-shift
                end
            end

            // ------------------------------------------------------------------
            // S_CS_HOLD – deassert CS and wait hold time
            // ------------------------------------------------------------------
            S_CS_HOLD: begin
                spi_ncs <= 1'b1;
                spi_sdi <= 1'b0;
                if (delay_cnt == CS_HOLD - 1) begin
                    delay_cnt <= 20'd0;
                    // Last frame (fault status read)?
                    if (frame_idx == NUM_FRAMES - 1) begin
                        state <= S_DONE;
                    end else begin
                        frame_idx <= frame_idx + 3'd1;
                        state     <= S_GAP;
                    end
                end else begin
                    delay_cnt <= delay_cnt + 20'd1;
                end
            end

            // ------------------------------------------------------------------
            // S_GAP – inter-frame idle gap
            // ------------------------------------------------------------------
            S_GAP: begin
                spi_ncs <= 1'b1;
                spi_sdi <= 1'b0;
                if (delay_cnt == INTER_GAP - 1) begin
                    delay_cnt <= 20'd0;
                    state     <= S_CS_SETUP;
                end else begin
                    delay_cnt <= delay_cnt + 20'd1;
                end
            end

            // ------------------------------------------------------------------
            // S_DONE – latch results and assert init_done
            // ------------------------------------------------------------------
            S_DONE: begin
                init_done <= 1'b1;
                // rx_data holds the 11 data bits of the fault-status frame.
                // The DRV8323 fault status register 0x00/0x01 returns fault
                // information in bits [10:0].  Any non-zero value = fault.
                if (rx_data != 11'd0) begin
                    init_fault <= 1'b1;
                end
                // Stay in DONE forever (one-shot)
            end

            default: state <= S_IDLE;

        endcase
    end
end

endmodule

`default_nettype wire
