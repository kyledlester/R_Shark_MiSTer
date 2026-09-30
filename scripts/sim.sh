#!/bin/sh
# R-Shark core -- simulation runner (ModelSim-Intel FPGA Starter 10.5b from the Quartus 17.0 install).
# Usage: scripts/sim.sh <test> [vsim args/plusargs...]    scripts/sim.sh all   (regression list)
# Each bench prints "PASS <NAME>: ..." or "FAIL <NAME>: ..."; the runner greps for the verdict.
# Logs: build/sim/<test>.log. Benches that need ROM data read local/ images made by
# scripts/romtool.py (never committed).
set -u
MS=${MODELSIM:-/c/intelFPGA_lite/17.0/modelsim_ase/win32aloem}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
mkdir -p build/sim

FX68K="rtl/vendor/fx68k/fx68k.sv rtl/vendor/fx68k/fx68kAlu.sv rtl/vendor/fx68k/uaddrPla.sv"
T80="rtl/vendor/t80/T80_Pack.vhd rtl/vendor/t80/T80_ALU.vhd rtl/vendor/t80/T80_Reg.vhd rtl/vendor/t80/T80_MCode.vhd rtl/vendor/t80/T80.vhd"
JT51=$(ls rtl/vendor/jt51/*.v | tr '\n' ' ')
JT6295="rtl/vendor/jt6295/jt6295.v rtl/vendor/jt6295/jt6295_adpcm.v rtl/vendor/jt6295/jt6295_timing.v rtl/vendor/jt6295/jt6295_acc.v rtl/vendor/jt6295/jt6295_ctrl.v rtl/vendor/jt6295/jt6295_rom.v rtl/vendor/jt6295/jt6295_serial.v rtl/vendor/jt6295/jt6295_sh_rst.v rtl/vendor/jt6295/jt12_interpol.v rtl/vendor/jt6295/jt12_comb.v"
MAIN="rtl/rshark/rshark_ram.sv rtl/rshark/rshark_cpu_bus.sv rtl/rshark/rshark_cpu68k.sv rtl/rshark/rshark_main.sv"
VIDEO="rtl/rshark/rshark_ram.sv rtl/rshark/rshark_tilemap.sv rtl/rshark/rshark_sprites.sv rtl/rshark/rshark_video.sv"

# test -> "top|vhdl files|sv files|fx68k?"
spec() {
  case "$1" in
    m0)  echo "m0_timing_tb|||rtl/rshark/rshark_clocks.sv rtl/rshark/rshark_video_timing.sv sim/tb/m0_timing_tb.sv" ;;
    *) echo "" ;;
  esac
}

run() {
  t=$1; shift
  s=$(spec "$t")
  [ -z "$s" ] && { echo "unknown test $t"; return 2; }
  top=${s%%|*}; rest=${s#*|}; vhd=${rest%%|*}; rest=${rest#*|}; cpu=${rest%%|*}; sv=${rest#*|}
  lib=build/sim/lib_$t
  rm -rf "$lib"; "$MS/vlib.exe" "$lib" >/dev/null
  log=build/sim/$t.log
  : > "$log"
  if [ -n "$vhd" ]; then "$MS/vcom.exe" -2008 -quiet -work "$lib" $vhd >> "$log" 2>&1 || { echo "FAIL $t: vcom (see $log)"; tail -20 "$log"; return 1; }; fi
  # FX68K mixes initial and always_ff writes to register arrays (ModelSim check 7061); suppress
  # only for the imported CPU (see rtl/vendor/fx68k/ORIGIN.md).
  if [ -n "$cpu" ]; then "$MS/vlog.exe" -sv -quiet -suppress 7061 -work "$lib" $FX68K >> "$log" 2>&1 || { echo "FAIL $t: vlog fx68k (see $log)"; return 1; }; fi
  "$MS/vlog.exe" -sv -quiet -work "$lib" ${VLOGDEFS:-} +incdir+sim/tb $sv >> "$log" 2>&1 || { echo "FAIL $t: vlog (see $log)"; grep -E "Error|error" "$log" | head -20; return 1; }
  "$MS/vsim.exe" -c -L altera_mf_ver -L altera_ver -lib "$lib" "$top" "$@" -do 'run -all; quit -f' >> "$log" 2>&1
  r=$(grep -E "^# (PASS|FAIL) " "$log" | tail -1 | sed 's/^# //')
  if [ -z "$r" ]; then echo "FAIL $t: no verdict (see $log)"; grep -E "Error|Fatal" "$log" | head -10; return 1; fi
  echo "$r"
  case "$r" in PASS*) return 0 ;; *) return 1 ;; esac
}

if [ "${1:-}" = all ]; then
  fails=0
  for t in ${SIM_TESTS:-m0}; do run "$t" || fails=$((fails+1)); done
  echo "REGRESSION: $fails failing"
  exit $fails
fi
run "$@"
