# =============================================================================
# FOC Demo — Build System for iCE40 UltraPlus
#
# Targets:
#   all       — Full build (generate + synthesize + PnR + bitstream)
#   generate  — Generate all derived sources (ReflexScript, templates)
#   program   — Program FPGA via iceprog
#   lint      — Verilator lint check
#   timing    — Show timing report from nextpnr
#   clean     — Remove build artifacts
# =============================================================================

# Paths
PROJECT      := focdemo
PLATFORM_DIR := ../../reflexible-platforms/device-lib/fpga
BUILD_DIR    := build
GEN_DIR      := generated

# Tools
REFLEXC      := $(shell which reflexc 2>/dev/null || echo ../../Reflexscript/build/reflexc)
PYTHON       := python3
YOSYS        := yosys
NEXTPNR      := nextpnr-ice40
ICEPACK      := icepack
ICEPROG      := iceprog
VERILATOR    := verilator

# FPGA target
DEVICE       := up5k
PACKAGE      := sg48
PCF          := constraints/focdemo.pcf
FREQ_MHZ     := 12

# Source files
RTL_SOURCES  := \
    rtl/pll_48mhz.v \
    rtl/drv8323_spi_init.v \
    rtl/serial_cmd.v \
    rtl/focdemo_top.v

GEN_SOURCES  := \
    $(GEN_DIR)/foc_closedloop.sv \
    $(GEN_DIR)/fp_trig_bram.sv \
    $(GEN_DIR)/adc_4ch.sv \
    $(GEN_DIR)/pwm_3ph.sv \
    $(GEN_DIR)/uart_focdemo.sv

ALL_SOURCES  := $(RTL_SOURCES) $(GEN_SOURCES)

# Template parameters
ADC_PARAMS   := instance_name=adc_4ch channels=4 sclk_div=6 sclk_div_bits=3 \
                sample_period=2400 sample_period_bits=12

PWM_PARAMS   := instance_name=pwm_3ph channels=3 resolution_bits=10 \
                alignment=center period_value=1023 dead_time_cycles=24 \
                'has_complementary=[true,true,true]'

UART_PARAMS  := instance_name=uart_focdemo baud_rate=115200 \
                clock_freq_hz=48000000 baud_div=417 baud_div_bits=9

# =============================================================================
# Default target
# =============================================================================
.PHONY: all generate program lint timing clean

all: $(BUILD_DIR)/$(PROJECT).bin

# =============================================================================
# Generate derived sources
# =============================================================================
generate: $(GEN_SOURCES)

# ReflexScript → SystemVerilog + BRAM LUT modules + hex data (reflexc outputs to a directory)
$(GEN_DIR)/foc_closedloop.sv $(GEN_DIR)/fp_trig_bram.sv: rfx/foc_closedloop.rfx | $(GEN_DIR)
	$(REFLEXC) --emit-verilog --verilog-fixed-point -o $(GEN_DIR)/_rfx_out $<
	cp $(GEN_DIR)/_rfx_out/foc_closedloop.sv $(GEN_DIR)/foc_closedloop.sv
	sed -i 's/^`timescale/\/\/ `timescale/' $(GEN_DIR)/foc_closedloop.sv
	@if [ -f $(GEN_DIR)/_rfx_out/fp_trig_bram.sv ]; then \
		cp $(GEN_DIR)/_rfx_out/fp_trig_bram.sv $(GEN_DIR)/fp_trig_bram.sv; \
		sed -i 's/^`timescale/\/\/ `timescale/' $(GEN_DIR)/fp_trig_bram.sv; \
	fi
	@if [ -f $(GEN_DIR)/_rfx_out/sin_lut.hex ]; then \
		cp $(GEN_DIR)/_rfx_out/sin_lut.hex $(GEN_DIR)/sin_lut.hex; \
	fi
	@if [ -f $(GEN_DIR)/_rfx_out/cos_lut.hex ]; then \
		cp $(GEN_DIR)/_rfx_out/cos_lut.hex $(GEN_DIR)/cos_lut.hex; \
	fi
	@if [ -f $(GEN_DIR)/_rfx_out/fp_trig_lut.sv ]; then \
		cp $(GEN_DIR)/_rfx_out/fp_trig_lut.sv $(GEN_DIR)/fp_trig_lut.sv; \
		sed -i 's/^`timescale/\/\/ `timescale/' $(GEN_DIR)/fp_trig_lut.sv; \
	fi

# ADC template → SystemVerilog
$(GEN_DIR)/adc_4ch.sv: $(PLATFORM_DIR)/adc_reader/adc_reader.sv.j2 render_template.py | $(GEN_DIR)
	$(PYTHON) render_template.py $< $@ $(ADC_PARAMS)

# PWM template → SystemVerilog
$(GEN_DIR)/pwm_3ph.sv: $(PLATFORM_DIR)/pwm_controller/pwm_controller.sv.j2 render_template.py | $(GEN_DIR)
	$(PYTHON) render_template.py $< $@ $(PWM_PARAMS)

# UART template → SystemVerilog
$(GEN_DIR)/uart_focdemo.sv: $(PLATFORM_DIR)/uart_transceiver/uart_transceiver.sv.j2 render_template.py | $(GEN_DIR)
	$(PYTHON) render_template.py $< $@ $(UART_PARAMS)

$(GEN_DIR):
	mkdir -p $(GEN_DIR)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# =============================================================================
# Synthesis (Yosys)
# =============================================================================
$(BUILD_DIR)/$(PROJECT).json: $(ALL_SOURCES) | $(BUILD_DIR)
	$(YOSYS) -p "read_verilog -sv $(ALL_SOURCES); synth_ice40 -top focdemo_top -dsp -json $@"

# =============================================================================
# Place and Route (nextpnr)
# =============================================================================
$(BUILD_DIR)/$(PROJECT).asc: $(BUILD_DIR)/$(PROJECT).json $(PCF)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) \
	    --pcf $(PCF) \
	    --json $< \
	    --asc $@ \
	    --freq $(FREQ_MHZ) \
	    --timing-allow-fail

# =============================================================================
# Bitstream (icepack)
# =============================================================================
$(BUILD_DIR)/$(PROJECT).bin: $(BUILD_DIR)/$(PROJECT).asc
	$(ICEPACK) $< $@

# =============================================================================
# Program FPGA
# =============================================================================
program: $(BUILD_DIR)/$(PROJECT).bin
	$(ICEPROG) $<

# =============================================================================
# Lint (Verilator)
# =============================================================================
lint: $(GEN_SOURCES)
	$(VERILATOR) --lint-only -Wall \
	    -Wno-WIDTH -Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET \
	    --top-module focdemo_top \
	    rtl/ice40_cells_stub.v $(ALL_SOURCES)

# =============================================================================
# Timing report
# =============================================================================
timing: $(BUILD_DIR)/$(PROJECT).asc
	@echo "=== Timing Report ==="
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) \
	    --pcf $(PCF) \
	    --json $(BUILD_DIR)/$(PROJECT).json \
	    --asc /dev/null \
	    --freq $(FREQ_MHZ) \
	    --report $(BUILD_DIR)/timing.json 2>&1 | tail -20

# =============================================================================
# ReflexScript tests
# =============================================================================
REFLEXRT_INC := ../../Reflexscript/include
REFLEXRT_LIB := ../../Reflexscript/build/libreflexrt.a

.PHONY: test
test: rfx/foc_closedloop.rfx | $(BUILD_DIR)
	$(REFLEXC) --copy_rt -o $(BUILD_DIR)/rfx_test $<
	gcc -std=c11 -I$(REFLEXRT_INC) \
	    $(BUILD_DIR)/rfx_test/foc_closedloop.c \
	    $(BUILD_DIR)/rfx_test/foc_closedloop-test.c \
	    $(REFLEXRT_LIB) -lm \
	    -o $(BUILD_DIR)/rfx_test/foc_closedloop-tests
	$(BUILD_DIR)/rfx_test/foc_closedloop-tests

# =============================================================================
# Clean
# =============================================================================
clean:
	rm -rf $(BUILD_DIR) $(GEN_DIR)
