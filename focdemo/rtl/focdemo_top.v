// =============================================================================
// focdemo_top — Top-Level Integration for iCE40 FOC Demo
//
// Integrates: PLL, ADC (4ch), FOC controller (ReflexScript, with built-in trig LUTs),
//             PWM (3ph), DRV8323RX SPI init, UART, serial command interface
// =============================================================================
`default_nettype none

module focdemo_top (
    // Clock
    input  wire clk_12mhz,

    // ADC SPI bus (shared CS/SCLK, 4 SDATA lines)
    output wire adc_sclk,
    output wire adc_cs,
    input  wire adc_d0,         // ISENB
    input  wire adc_d1,         // ISENC
    input  wire adc_d2,         // ISENA
    input  wire adc_d3,         // AS5600.OUT (analog encoder)

    // Motor PWM outputs (DRV8323RX half-bridge inputs)
    output wire pwm_ah,
    output wire pwm_al,
    output wire pwm_bh,
    output wire pwm_bl,
    output wire pwm_ch,
    output wire pwm_cl,

    // DRV8323RX SPI configuration
    output wire drv_sclk,
    output wire drv_sdi,
    input  wire drv_sdo,
    output wire drv_ncs,

    // UART
    output wire uart_tx,
    input  wire uart_rx
);

    // =========================================================================
    // PLL: 12 MHz → 48 MHz
    // =========================================================================
    // Reset tied high (no external button)
    wire rst_n = 1'b1;

    wire clk;
    wire pll_locked;

    pll_48mhz pll_inst (
        .clk_12mhz  (clk_12mhz),
        .rst_n       (rst_n),
        .clk_48mhz   (clk),
        .locked       (pll_locked)
    );

    wire rst_n_sync = pll_locked;

    // =========================================================================
    // DRV8323RX SPI Initialization
    // =========================================================================
    wire drv_init_done;
    wire drv_init_fault;
    wire [10:0] drv_fault_reg;

    drv8323_spi_init drv_init_inst (
        .clk             (clk),
        .rst_n           (rst_n_sync),
        .clear_fault_req (clear_fault_req),
        .spi_sclk        (drv_sclk),
        .spi_sdi         (drv_sdi),
        .spi_sdo         (drv_sdo),
        .spi_ncs         (drv_ncs),
        .init_done       (drv_init_done),
        .init_fault      (drv_init_fault),
        .fault_reg       (drv_fault_reg)
    );

    // =========================================================================
    // UART Transceiver
    // =========================================================================
    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;
    wire [7:0] uart_tx_data;
    wire       uart_tx_valid;
    wire       uart_tx_ready;
    wire [7:0] uart_tx_data_cmd;
    wire       uart_tx_valid_cmd;

    uart_focdemo uart_inst (
        .clk       (clk),
        .rst_n     (rst_n_sync),
        .tx        (uart_tx),
        .rx        (uart_rx),
        .tx_data   (uart_tx_data),
        .tx_valid  (uart_tx_valid),
        .tx_ready  (uart_tx_ready),
        .rx_data   (uart_rx_data),
        .rx_valid  (uart_rx_valid)
    );

    assign uart_tx_data  = uart_tx_data_cmd;
    assign uart_tx_valid = uart_tx_valid_cmd;

    // =========================================================================
    // Serial Command Interface
    // =========================================================================
    wire        cmd_enable;
    wire [7:0]  cmd_mode;
    wire signed [15:0] cmd_iq_ref;
    wire signed [15:0] cmd_speed_ref;
    wire [15:0] cmd_pos_ref;
    wire signed [15:0] kp_id, ki_id, kp_iq, ki_iq;
    wire signed [15:0] kp_speed, ki_speed, kp_pos;

    // Telemetry from FOC
    wire        foc_fault;
    wire [15:0] dbg_pos;
    wire signed [15:0] dbg_speed;
    wire signed [15:0] dbg_id;
    wire signed [15:0] dbg_iq;
    wire [15:0] foc_pwm_a, foc_pwm_b, foc_pwm_c;
    wire [15:0] dbg_ia, dbg_ib, dbg_ic, dbg_enc;

    serial_cmd serial_cmd_inst (
        .clk            (clk),
        .rst_n          (rst_n_sync),
        // UART
        .uart_rx_data   (uart_rx_data),
        .uart_rx_valid  (uart_rx_valid),
        .uart_tx_data   (uart_tx_data_cmd),
        .uart_tx_valid  (uart_tx_valid_cmd),
        .uart_tx_ready  (uart_tx_ready),
        // Control outputs
        .enable         (cmd_enable),
        .mode           (cmd_mode),
        .cmd_iq_ref     (cmd_iq_ref),
        .cmd_speed_ref  (cmd_speed_ref),
        .cmd_pos_ref    (cmd_pos_ref),
        // Gains
        .kp_id          (kp_id),
        .ki_id          (ki_id),
        .kp_iq          (kp_iq),
        .ki_iq          (ki_iq),
        .kp_speed       (kp_speed),
        .ki_speed       (ki_speed),
        .kp_pos         (kp_pos),
        // Telemetry
        .foc_fault      (foc_fault),
        .drv_fault_reg  (drv_fault_reg),
        .dbg_pos        (dbg_pos),
        .dbg_speed      (dbg_speed),
        .dbg_id         (dbg_id),
        .dbg_iq         (dbg_iq),
        .dbg_ia         (dbg_ia),
        .dbg_ib         (dbg_ib),
        .dbg_ic         (dbg_ic),
        .dbg_enc        (dbg_enc)
    );

    reg cmd_enable_d1;
    always @(posedge clk) if (rst_n_sync) cmd_enable_d1 <= cmd_enable;
    wire clear_fault_req = cmd_enable && !cmd_enable_d1;

    // =========================================================================
    // ADC 4-Channel Reader (AD7476A x4)
    // =========================================================================
    wire [11:0] adc_ch0_data;   // ISENB
    wire [11:0] adc_ch1_data;   // ISENC
    wire [11:0] adc_ch2_data;   // ISENA
    wire [11:0] adc_ch3_data;   // AS5600.OUT (encoder)
    wire        adc_new_data;

    adc_4ch adc_inst (
        .clk        (clk),
        .rst_n      (rst_n_sync),
        .enable     (drv_init_done),
        .ch0_sdata  (adc_d0),
        .ch1_sdata  (adc_d1),
        .ch2_sdata  (adc_d2),
        .ch3_sdata  (adc_d3),
        .cs_out     (adc_cs),
        .sclk_out   (adc_sclk),
        .ch0_data   (adc_ch0_data),
        .ch1_data   (adc_ch1_data),
        .ch2_data   (adc_ch2_data),
        .ch3_data   (adc_ch3_data),
        .new_data   (adc_new_data)
    );

    // =========================================================================
    // FOC Closed-Loop Controller (ReflexScript-generated)
    // Sin/cos computed internally via built-in trig LUTs
    // =========================================================================
    wire [15:0] theta_elec;
    // Motor enable gated by DRV8323 init + serial command enable
    wire motor_enable = drv_init_done & cmd_enable & ~drv_init_fault;

    // Clock enable for FOC: divide-by-3 (48 MHz / 3 = 16 MHz effective)
    // Gives combinational paths 62.5 ns to settle vs 20.8 ns at full rate
    reg [1:0] foc_ce_cnt;
    wire foc_ce = (foc_ce_cnt == 2'd0);
    always @(posedge clk) begin
        if (!rst_n_sync)
            foc_ce_cnt <= 2'd0;
        else
            foc_ce_cnt <= (foc_ce_cnt == 2'd2) ? 2'd0 : foc_ce_cnt + 2'd1;
    end

    // Latch ADC new_data until FOC can accept it on a ce-enabled cycle
    wire foc_ready;
    reg adc_data_pending;
    always @(posedge clk) begin
        if (!rst_n_sync)
            adc_data_pending <= 1'b0;
        else if (adc_new_data)
            adc_data_pending <= 1'b1;
        else if (foc_ce && foc_ready)
            adc_data_pending <= 1'b0;
    end

    wire foc_valid_out;

    foc_closedloop foc_inst (
        .clk            (clk),
        .rst_n          (rst_n_sync),
        .ce             (foc_ce),
        .valid_in       (adc_data_pending),
        .ready_out      (foc_ready),
        .valid_out      (foc_valid_out),
        .ready_in       (1'b1),         // Always accept FOC output
        // ADC current inputs (channel mapping from hwsetup.md)
        .ia_raw         ({4'b0, adc_ch2_data}),  // ISENA
        .ib_raw         ({4'b0, adc_ch0_data}),  // ISENB
        .ic_raw         ({4'b0, adc_ch1_data}),  // ISENC
        .encoder_raw    ({4'b0, adc_ch3_data}),  // AS5600.OUT
        // Control from serial command
        .enable         (motor_enable),
        .mode           (cmd_mode),
        .cmd_iq_ref     (cmd_iq_ref),
        .cmd_speed_ref  (cmd_speed_ref),
        .cmd_pos_ref    (cmd_pos_ref),
        // Tunable gains
        .kp_id          (kp_id),
        .ki_id          (ki_id),
        .kp_iq          (kp_iq),
        .ki_iq          (ki_iq),
        .kp_speed       (kp_speed),
        .ki_speed       (ki_speed),
        .kp_pos         (kp_pos),
        // Outputs
        .pwm_a          (foc_pwm_a),
        .pwm_b          (foc_pwm_b),
        .pwm_c          (foc_pwm_c),
        .theta_elec     (theta_elec),
        .fault          (foc_fault),
        .dbg_id         (dbg_id),
        .dbg_iq         (dbg_iq),
        .dbg_speed      (dbg_speed),
        .dbg_pos        (dbg_pos),
        .dbg_ia         (dbg_ia),
        .dbg_ib         (dbg_ib),
        .dbg_ic         (dbg_ic),
        .dbg_enc        (dbg_enc)
    );

    // =========================================================================
    // 3-Phase PWM with Dead-Time
    // =========================================================================
    pwm_3ph pwm_inst (
        .clk        (clk),
        .rst_n      (rst_n_sync),
        .global_en  (motor_enable & ~foc_fault),
        // Duty cycles from FOC controller
        .ch0_duty   (foc_pwm_a[9:0]),
        .ch0_en     (1'b1),
        .ch1_duty   (foc_pwm_b[9:0]),
        .ch1_en     (1'b1),
        .ch2_duty   (foc_pwm_c[9:0]),
        .ch2_en     (1'b1),
        // PWM outputs to DRV8323RX
        .ch0_pos_out (pwm_ah),
        .ch0_neg_out (pwm_al),
        .ch1_pos_out (pwm_bh),
        .ch1_neg_out (pwm_bl),
        .ch2_pos_out (pwm_ch),
        .ch2_neg_out (pwm_cl),
        .sync_pulse  ()             // Unused
    );

    // =========================================================================
    // Status LEDs via SB_RGBA_DRV hard IP (on-board RGB LED)
    // =========================================================================
    wire led_r_pwm = foc_fault | drv_init_fault;       // Red:   fault
    wire led_g_pwm = ~uart_rx;                              // Green: raw RX pin low (debug)
    wire led_b_pwm = drv_init_done;                     // Blue:  init done

    wire rgb0_pad, rgb1_pad, rgb2_pad;

    (* keep *)
    SB_RGBA_DRV #(
        .CURRENT_MODE ("0b1"),       // half-current mode
        .RGB0_CURRENT ("0b000001"),  // ~4 mA (blue)
        .RGB1_CURRENT ("0b000001"),  // ~4 mA (green)
        .RGB2_CURRENT ("0b000001")   // ~4 mA (red)
    ) rgb_drv (
        .CURREN   (1'b1),
        .RGBLEDEN (1'b1),
        .RGB0PWM  (led_b_pwm),      // RGB0 = blue
        .RGB1PWM  (led_g_pwm),      // RGB1 = green
        .RGB2PWM  (led_r_pwm),      // RGB2 = red
        .RGB0     (rgb0_pad),
        .RGB1     (rgb1_pad),
        .RGB2     (rgb2_pad)
    );

endmodule
