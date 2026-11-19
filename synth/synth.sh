#!/usr/bin/env bash
# Usage: synth/synth.sh <mode: sim|sim_raw|fpga> 
#   sim      : fast-simulation config, event mode  -> build/netlist_sim.v   (functional netlist)
#   sim_raw  : fast-simulation config, raw mode    -> build/netlist_sim_raw.v
#   fpga     : real config (12 MHz, 115200 baud, 1 kHz) -> build/fpga.json   (for nextpnr-ice40)
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:-fpga}
case $mode in
  sim)     CPB=16;  DIV=600;   RAW=0 ;;
  sim_raw) CPB=16;  DIV=600;   RAW=1 ;;
  fpga)    CPB=104; DIV=12000; RAW=0 ;;
  *) echo "unknown mode"; exit 1 ;;
esac
V=rtl/vhdl
if [ "$mode" = fpga ]; then OUT="write_json build/fpga.json"; else
  OUT="synth -top edge_monitor_top -flatten; opt_clean -purge; write_verilog -noattr build/netlist_${mode}.v"; fi
if [ "$mode" = fpga ]; then SYN="synth_ice40 -top edge_monitor_top -json build/fpga.json"; else SYN="$OUT"; fi
mkdir -p build
yosys -q -m ghdl -l build/yosys_${mode}.log -p "
  ghdl --std=08 $V/ewma_cusum.vhd $V/uart_tx.vhd -e ewma_cusum;
  ghdl --std=08 -gCLKS_PER_BIT=$CPB $V/ewma_cusum.vhd $V/uart_tx.vhd -e uart_tx;
  read_verilog -sv rtl/sv/spi_master.sv rtl/sv/byte_fifo.sv rtl/sv/packetizer.sv rtl/sv/edge_monitor_top.sv;
  chparam -set SAMPLE_DIV $DIV -set RAW $RAW edge_monitor_top;
  hierarchy -check -top edge_monitor_top;
  $SYN;
  stat
" 
echo "synth ($mode) done: see build/yosys_${mode}.log"
