# ModelSim: emulate FPGA power-up zeros for jt51's shift-register pipelines (jt51_sh 'bits' arrays),
# which never leave X in a 4-state simulator (on the FPGA they start at 0 and the reset flush then
# loads their reset values). Only memories are touched. Usage: PRERUN="do sim/tb/zero_regs.do <path>;"
set root $1
set m 0
foreach line [split [mem list -r $root] "\n"] {
    if {[regexp {(/\S+)} $line -> path]} {
        if {![catch {mem load -filldata 0 $path}]} { incr m }
    }
}
echo "zero_regs: zero-filled $m memories under $root"
