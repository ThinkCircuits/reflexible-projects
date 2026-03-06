# =============================================================================
# FOC Demo — Build System for iCE40 UltraPlus
#
# Targets:
#   all       — Full build (generate + synthesize + PnR + bitstream)
#   simple    — Simplified BLDC 6-step open-loop driver (no FOC)
#   openloop  — Open-loop sinusoidal (FOC-style) driver, smooth rotation
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
.PHONY: all generate program lint timing clean simple simple-program openloop openloop-program debug debug-program debug-lint position position-program torque torque-program speed speed-program

all: position

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
# Position variant (default — all three modes)
# =============================================================================
position: $(BUILD_DIR)/$(PROJECT).bin

position-program: $(BUILD_DIR)/$(PROJECT).bin
	$(ICEPROG) $<

# =============================================================================
# Synthesis (Yosys)
# =============================================================================
$(BUILD_DIR)/$(PROJECT).json: $(ALL_SOURCES) | $(BUILD_DIR)
	$(YOSYS) -p "read_verilog -sv -DFIRMWARE_VARIANT=2 $(ALL_SOURCES); synth_ice40 -top focdemo_top -dsp -json $@"

# =============================================================================
# Place and Route (nextpnr)
# =============================================================================
$(BUILD_DIR)/$(PROJECT).asc: $(BUILD_DIR)/$(PROJECT).json $(PCF)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) \
	    --pcf $(PCF) \
	    --json $< \
	    --asc $@ \
	    --freq $(FREQ_MHZ) \
	    --timing-allow-fail \
	    --seed 2

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
# Simple BLDC — 6-step open-loop driver (no FOC, no ADC)
# =============================================================================
SIMPLE_BUILD_DIR := build_simple
SIMPLE_PROJECT   := simple_bldc

SIMPLE_RTL_SOURCES := \
    rtl/pll_48mhz.v \
    rtl/drv8323_spi_init.v \
    rtl/serial_cmd.v \
    rtl/bldc_6step.v \
    rtl/simple_bldc_top.v

SIMPLE_GEN_SOURCES := \
    $(GEN_DIR)/pwm_3ph.sv \
    $(GEN_DIR)/uart_focdemo.sv

SIMPLE_ALL_SOURCES := $(SIMPLE_RTL_SOURCES) $(SIMPLE_GEN_SOURCES)

simple: $(SIMPLE_BUILD_DIR)/$(SIMPLE_PROJECT).bin

$(SIMPLE_BUILD_DIR):
	mkdir -p $(SIMPLE_BUILD_DIR)

$(SIMPLE_BUILD_DIR)/$(SIMPLE_PROJECT).json: $(SIMPLE_ALL_SOURCES) | $(SIMPLE_BUILD_DIR)
	$(YOSYS) -p "read_verilog -sv $(SIMPLE_ALL_SOURCES); synth_ice40 -top simple_bldc_top -dsp -json $@"

$(SIMPLE_BUILD_DIR)/$(SIMPLE_PROJECT).asc: $(SIMPLE_BUILD_DIR)/$(SIMPLE_PROJECT).json $(PCF)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) \
	    --pcf $(PCF) \
	    --json $< \
	    --asc $@ \
	    --freq $(FREQ_MHZ) \
	    --timing-allow-fail \
	    --seed 2

$(SIMPLE_BUILD_DIR)/$(SIMPLE_PROJECT).bin: $(SIMPLE_BUILD_DIR)/$(SIMPLE_PROJECT).asc
	$(ICEPACK) $< $@

simple-program: $(SIMPLE_BUILD_DIR)/$(SIMPLE_PROJECT).bin
	$(ICEPROG) $<

simple-lint: $(SIMPLE_GEN_SOURCES)
	$(VERILATOR) --lint-only -Wall \
	    -Wno-WIDTH -Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET \
	    --top-module simple_bldc_top \
	    rtl/ice40_cells_stub.v $(SIMPLE_ALL_SOURCES)

# =============================================================================
# Open-loop FOC — Sinusoidal drive, no encoder/current feedback
# =============================================================================
OPENLOOP_BUILD_DIR := build_openloop
OPENLOOP_PROJECT   := openloop_bldc

OPENLOOP_RTL_SOURCES := \
    rtl/pll_48mhz.v \
    rtl/drv8323_spi_init.v \
    rtl/serial_cmd.v \
    rtl/open_loop_foc.v \
    rtl/openloop_bldc_top.v

OPENLOOP_GEN_SOURCES := \
    $(GEN_DIR)/pwm_3ph.sv \
    $(GEN_DIR)/uart_focdemo.sv

OPENLOOP_ALL_SOURCES := $(OPENLOOP_RTL_SOURCES) $(OPENLOOP_GEN_SOURCES)

openloop: $(OPENLOOP_BUILD_DIR)/$(OPENLOOP_PROJECT).bin

$(OPENLOOP_BUILD_DIR):
	mkdir -p $(OPENLOOP_BUILD_DIR)

$(OPENLOOP_BUILD_DIR)/$(OPENLOOP_PROJECT).json: $(OPENLOOP_ALL_SOURCES) | $(OPENLOOP_BUILD_DIR)
	$(YOSYS) -p "read_verilog -sv $(OPENLOOP_ALL_SOURCES); synth_ice40 -top openloop_bldc_top -dsp -json $@"

$(OPENLOOP_BUILD_DIR)/$(OPENLOOP_PROJECT).asc: $(OPENLOOP_BUILD_DIR)/$(OPENLOOP_PROJECT).json $(PCF)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) \
	    --pcf $(PCF) \
	    --json $< \
	    --asc $@ \
	    --freq $(FREQ_MHZ) \
	    --timing-allow-fail \
	    --seed 2

$(OPENLOOP_BUILD_DIR)/$(OPENLOOP_PROJECT).bin: $(OPENLOOP_BUILD_DIR)/$(OPENLOOP_PROJECT).asc
	$(ICEPACK) $< $@

openloop-program: $(OPENLOOP_BUILD_DIR)/$(OPENLOOP_PROJECT).bin
	$(ICEPROG) $<

# =============================================================================
# Debug Build — Direct peripheral control (no FOC controller)
# =============================================================================
DEBUG_BUILD_DIR := build_debug
DEBUG_PROJECT   := focdemo_debug

DEBUG_RTL_SOURCES := \
    rtl/pll_48mhz.v \
    rtl/drv_spi_master.v \
    rtl/serial_cmd_debug.v \
    rtl/debug_top.v

DEBUG_GEN_SOURCES := \
    $(GEN_DIR)/adc_4ch.sv \
    $(GEN_DIR)/pwm_3ph.sv \
    $(GEN_DIR)/uart_focdemo.sv

DEBUG_ALL_SOURCES := $(DEBUG_RTL_SOURCES) $(DEBUG_GEN_SOURCES)

debug: $(DEBUG_BUILD_DIR)/$(DEBUG_PROJECT).bin

$(DEBUG_BUILD_DIR):
	mkdir -p $(DEBUG_BUILD_DIR)

$(DEBUG_BUILD_DIR)/$(DEBUG_PROJECT).json: $(DEBUG_ALL_SOURCES) | $(DEBUG_BUILD_DIR)
	$(YOSYS) -p "read_verilog -sv $(DEBUG_ALL_SOURCES); synth_ice40 -top debug_top -dsp -json $@"

$(DEBUG_BUILD_DIR)/$(DEBUG_PROJECT).asc: $(DEBUG_BUILD_DIR)/$(DEBUG_PROJECT).json $(PCF)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) \
	    --pcf $(PCF) \
	    --json $< \
	    --asc $@ \
	    --freq $(FREQ_MHZ) \
	    --seed 2

$(DEBUG_BUILD_DIR)/$(DEBUG_PROJECT).bin: $(DEBUG_BUILD_DIR)/$(DEBUG_PROJECT).asc
	$(ICEPACK) $< $@

debug-program: $(DEBUG_BUILD_DIR)/$(DEBUG_PROJECT).bin
	$(ICEPROG) $<

debug-lint: $(DEBUG_GEN_SOURCES)
	$(VERILATOR) --lint-only -Wall \
	    -Wno-WIDTH -Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET \
	    --top-module debug_top \
	    rtl/ice40_cells_stub.v $(DEBUG_ALL_SOURCES)

# =============================================================================
# Torque-only FOC — Current loops only, no speed/position (smallest)
# =============================================================================
TORQUE_BUILD_DIR := build_torque
TORQUE_GEN_DIR   := $(TORQUE_BUILD_DIR)/generated

TORQUE_GEN_SOURCES := \
    $(TORQUE_GEN_DIR)/foc_closedloop.sv \
    $(TORQUE_GEN_DIR)/fp_trig_bram.sv \
    $(GEN_DIR)/adc_4ch.sv \
    $(GEN_DIR)/pwm_3ph.sv \
    $(GEN_DIR)/uart_focdemo.sv

TORQUE_ALL_SOURCES := $(RTL_SOURCES) $(TORQUE_GEN_SOURCES)

torque: $(TORQUE_BUILD_DIR)/$(PROJECT).bin

$(TORQUE_BUILD_DIR):
	mkdir -p $(TORQUE_BUILD_DIR)

$(TORQUE_GEN_DIR):
	mkdir -p $(TORQUE_GEN_DIR)

$(TORQUE_GEN_DIR)/foc_closedloop.sv $(TORQUE_GEN_DIR)/fp_trig_bram.sv: rfx/foc_torque.rfx | $(TORQUE_GEN_DIR)
	$(REFLEXC) --emit-verilog --verilog-fixed-point -o $(TORQUE_GEN_DIR)/_rfx_out $<
	cp $(TORQUE_GEN_DIR)/_rfx_out/foc_closedloop.sv $(TORQUE_GEN_DIR)/foc_closedloop.sv
	sed -i 's/^`timescale/\/\/ `timescale/' $(TORQUE_GEN_DIR)/foc_closedloop.sv
	@if [ -f $(TORQUE_GEN_DIR)/_rfx_out/fp_trig_bram.sv ]; then \
		cp $(TORQUE_GEN_DIR)/_rfx_out/fp_trig_bram.sv $(TORQUE_GEN_DIR)/fp_trig_bram.sv; \
		sed -i 's/^`timescale/\/\/ `timescale/' $(TORQUE_GEN_DIR)/fp_trig_bram.sv; \
	fi
	@if [ -f $(TORQUE_GEN_DIR)/_rfx_out/sin_lut.hex ]; then \
		cp $(TORQUE_GEN_DIR)/_rfx_out/sin_lut.hex $(TORQUE_GEN_DIR)/sin_lut.hex; \
	fi
	@if [ -f $(TORQUE_GEN_DIR)/_rfx_out/cos_lut.hex ]; then \
		cp $(TORQUE_GEN_DIR)/_rfx_out/cos_lut.hex $(TORQUE_GEN_DIR)/cos_lut.hex; \
	fi

$(TORQUE_BUILD_DIR)/$(PROJECT).json: $(TORQUE_ALL_SOURCES) | $(TORQUE_BUILD_DIR)
	$(YOSYS) -p "read_verilog -sv -DFIRMWARE_VARIANT=0 $(TORQUE_ALL_SOURCES); synth_ice40 -top focdemo_top -dsp -json $@"

$(TORQUE_BUILD_DIR)/$(PROJECT).asc: $(TORQUE_BUILD_DIR)/$(PROJECT).json $(PCF)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) \
	    --pcf $(PCF) \
	    --json $< \
	    --asc $@ \
	    --freq $(FREQ_MHZ) \
	    --timing-allow-fail \
	    --seed 2

$(TORQUE_BUILD_DIR)/$(PROJECT).bin: $(TORQUE_BUILD_DIR)/$(PROJECT).asc
	$(ICEPACK) $< $@

torque-program: $(TORQUE_BUILD_DIR)/$(PROJECT).bin
	$(ICEPROG) $<

# =============================================================================
# Speed FOC — Torque + speed modes, no position (medium)
# =============================================================================
SPEED_BUILD_DIR := build_speed
SPEED_GEN_DIR   := $(SPEED_BUILD_DIR)/generated

SPEED_GEN_SOURCES := \
    $(SPEED_GEN_DIR)/foc_closedloop.sv \
    $(SPEED_GEN_DIR)/fp_trig_bram.sv \
    $(GEN_DIR)/adc_4ch.sv \
    $(GEN_DIR)/pwm_3ph.sv \
    $(GEN_DIR)/uart_focdemo.sv

SPEED_ALL_SOURCES := $(RTL_SOURCES) $(SPEED_GEN_SOURCES)

speed: $(SPEED_BUILD_DIR)/$(PROJECT).bin

$(SPEED_BUILD_DIR):
	mkdir -p $(SPEED_BUILD_DIR)

$(SPEED_GEN_DIR):
	mkdir -p $(SPEED_GEN_DIR)

$(SPEED_GEN_DIR)/foc_closedloop.sv $(SPEED_GEN_DIR)/fp_trig_bram.sv: rfx/foc_speed.rfx | $(SPEED_GEN_DIR)
	$(REFLEXC) --emit-verilog --verilog-fixed-point -o $(SPEED_GEN_DIR)/_rfx_out $<
	cp $(SPEED_GEN_DIR)/_rfx_out/foc_closedloop.sv $(SPEED_GEN_DIR)/foc_closedloop.sv
	sed -i 's/^`timescale/\/\/ `timescale/' $(SPEED_GEN_DIR)/foc_closedloop.sv
	@if [ -f $(SPEED_GEN_DIR)/_rfx_out/fp_trig_bram.sv ]; then \
		cp $(SPEED_GEN_DIR)/_rfx_out/fp_trig_bram.sv $(SPEED_GEN_DIR)/fp_trig_bram.sv; \
		sed -i 's/^`timescale/\/\/ `timescale/' $(SPEED_GEN_DIR)/fp_trig_bram.sv; \
	fi
	@if [ -f $(SPEED_GEN_DIR)/_rfx_out/sin_lut.hex ]; then \
		cp $(SPEED_GEN_DIR)/_rfx_out/sin_lut.hex $(SPEED_GEN_DIR)/sin_lut.hex; \
	fi
	@if [ -f $(SPEED_GEN_DIR)/_rfx_out/cos_lut.hex ]; then \
		cp $(SPEED_GEN_DIR)/_rfx_out/cos_lut.hex $(SPEED_GEN_DIR)/cos_lut.hex; \
	fi

$(SPEED_BUILD_DIR)/$(PROJECT).json: $(SPEED_ALL_SOURCES) | $(SPEED_BUILD_DIR)
	$(YOSYS) -p "read_verilog -sv -DFIRMWARE_VARIANT=1 $(SPEED_ALL_SOURCES); synth_ice40 -top focdemo_top -dsp -json $@"

$(SPEED_BUILD_DIR)/$(PROJECT).asc: $(SPEED_BUILD_DIR)/$(PROJECT).json $(PCF)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) \
	    --pcf $(PCF) \
	    --json $< \
	    --asc $@ \
	    --freq $(FREQ_MHZ) \
	    --timing-allow-fail \
	    --seed 2

$(SPEED_BUILD_DIR)/$(PROJECT).bin: $(SPEED_BUILD_DIR)/$(PROJECT).asc
	$(ICEPACK) $< $@

speed-program: $(SPEED_BUILD_DIR)/$(PROJECT).bin
	$(ICEPROG) $<

# =============================================================================
# Clean
# =============================================================================
clean:
	rm -rf $(BUILD_DIR) $(DEBUG_BUILD_DIR) $(SIMPLE_BUILD_DIR) $(OPENLOOP_BUILD_DIR) $(TORQUE_BUILD_DIR) $(SPEED_BUILD_DIR) $(GEN_DIR)
