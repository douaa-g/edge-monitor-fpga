# edge-monitor-fpga: run `make all` from the repo root.
# Needs: ghdl, yosys (+ghdl plugin), verilator, nextpnr-ice40, python3 + numpy + matplotlib.
SHELL := /bin/bash
export GHDL_PREFIX ?= /usr/lib/ghdl/mcode/vhdl
export PYTHONPATH := model
VL = verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-LATCH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE

.PHONY: all vectors test-vhdl test-spi mutation synth-sim test-system synth-fpga pnr analysis clean
all: vectors test-vhdl test-spi mutation synth-sim test-system synth-fpga pnr analysis

vectors:
	python3 model/gen_vectors.py results

test-vhdl:                      # VHDL blocks vs. Python golden model (GHDL, VHDL-2008)
	mkdir -p build/ghdl
	ghdl -a --std=08 --workdir=build/ghdl rtl/vhdl/ewma_cusum.vhd rtl/vhdl/uart_tx.vhd tb/tb_ewma_cusum.vhd tb/tb_uart_tx.vhd
	ghdl -r --std=08 --workdir=build/ghdl tb_ewma_cusum
	ghdl -r --std=08 --workdir=build/ghdl tb_uart_tx

test-spi:                       # SystemVerilog SPI master with live SVA assertions (Verilator)
	$(VL) --assert --top-module tb_spi_master -Mdir build/spi rtl/sv/spi_master.sv tb/tb_spi_master.sv >/dev/null
	./build/spi/Vtb_spi_master

mutation:                       # inject a bug; the assertions MUST fire (otherwise the test is vacuous)
	mkdir -p build/mut
	sed "s/state <= IDLE; sclk <= 1'b0; cs_n <= 1'b1/state <= IDLE; sclk <= 1'b1; cs_n <= 1'b1/" rtl/sv/spi_master.sv > build/mut/spi_master_mut.sv
	$(VL) --assert --top-module tb_spi_master -Mdir build/mut/o build/mut/spi_master_mut.sv tb/tb_spi_master.sv >/dev/null
	@if ./build/mut/o/Vtb_spi_master 2>&1 | grep -qiE "assert|error"; then echo "mutation caught by assertions: OK"; else echo "MUTATION NOT CAUGHT"; exit 1; fi

synth-sim:
	bash synth/synth.sh sim >/dev/null && bash synth/synth.sh sim_raw >/dev/null

test-system: synth-sim vectors  # whole brick, synthesised mixed VHDL+SV netlist, byte-exact vs. model
	for m in event raw; do n=netlist_sim; [ $$m = raw ] && n=netlist_sim_raw; \
	  $(VL) --top-module tb_system -Mdir build/sys_$$m build/$$n.v tb/tb_system.sv >/dev/null; \
	  ./build/sys_$$m/Vtb_system +N=12900 +STIM=results/stim.hex +OUT=build/rtl_$$m.hex | grep system; \
	  python3 model/compare.py build/rtl_$$m.hex results/expected_$$m.hex "$$m mode" || exit 1; done

synth-fpga:
	bash synth/synth.sh fpga >/dev/null && grep -E "^ +SB_(LUT4|DFF|RAM40|CARRY)" build/yosys_fpga.log | sort -u

pnr: synth-fpga                 # no pin constraints: timing of the logic only
	nextpnr-ice40 --hx8k --package ct256 --json build/fpga.json --freq 12 --seed 1 -l build/pnr_hx8k.log -q; grep "Max frequency" build/pnr_hx8k.log | tail -1
	nextpnr-ice40 --up5k --package sg48  --json build/fpga.json --freq 12 --seed 1 -l build/pnr_up5k.log -q; grep "Max frequency" build/pnr_up5k.log | tail -1

analysis:
	python3 model/analysis.py

clean:
	rm -rf build model/__pycache__
