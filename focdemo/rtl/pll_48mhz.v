// PLL Module to generate 48 MHz from 12 MHz input
// Using iCE40 SB_PLL40_PAD primitive (clock from package pin)

module pll_48mhz (
    input  wire clk_12mhz,
    input  wire rst_n,
    output wire clk_48mhz,
    output wire locked
);

    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),         // DIVR = 0
        .DIVF(7'b0011111),      // DIVF = 31
        .DIVQ(3'b011),          // DIVQ = 3
        .FILTER_RANGE(3'b001)   // FILTER_RANGE = 1
    ) pll_inst (
        .PACKAGEPIN(clk_12mhz),
        .PLLOUTCORE(clk_48mhz),
        .LOCK(locked),
        .RESETB(rst_n),
        .BYPASS(1'b0)
    );

    // PLL calculation:
    // F_OUT = F_IN * (DIVF + 1) / (2^DIVQ * (DIVR + 1))
    // F_OUT = 12 MHz * (31 + 1) / (2^3 * (0 + 1))
    // F_OUT = 12 MHz * 32 / 8 = 48 MHz

endmodule
