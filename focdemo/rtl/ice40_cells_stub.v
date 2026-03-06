// Stubs for iCE40 primitives (Verilator lint only — not for synthesis)
/* verilator lint_off DECLFILENAME */
module SB_PLL40_PAD #(
    parameter FEEDBACK_PATH = "SIMPLE",
    parameter DIVR = 4'b0000,
    parameter DIVF = 7'b0000000,
    parameter DIVQ = 3'b000,
    parameter FILTER_RANGE = 3'b000
)(
    input  PACKAGEPIN,
    output PLLOUTCORE,
    output LOCK,
    input  RESETB,
    input  BYPASS
);
    assign PLLOUTCORE = PACKAGEPIN;
    assign LOCK = RESETB;
endmodule
module SB_RGBA_DRV #(
    parameter CURRENT_MODE = "0b0",
    parameter RGB0_CURRENT = "0b000000",
    parameter RGB1_CURRENT = "0b000000",
    parameter RGB2_CURRENT = "0b000000"
)(
    input  CURREN,
    input  RGBLEDEN,
    input  RGB0PWM,
    input  RGB1PWM,
    input  RGB2PWM,
    output RGB0,
    output RGB1,
    output RGB2
);
    assign RGB0 = CURREN & RGBLEDEN & RGB0PWM;
    assign RGB1 = CURREN & RGBLEDEN & RGB1PWM;
    assign RGB2 = CURREN & RGBLEDEN & RGB2PWM;
endmodule
/* verilator lint_on DECLFILENAME */
