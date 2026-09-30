# R-Shark (Dooyong, 1995) for MiSTer

MiSTer FPGA core for Dooyong's **R-Shark** (MAME set `rshark`), a vertical shoot 'em up on the
Dooyong 68000 board (68000 + Z80, YM2151 + OKI M6295, four ROM-based tilemaps, buffered sprites).

Status: in development - see [docs/MILESTONES.md](docs/MILESTONES.md).

ROMs are not included. You must supply your own `rshark.zip` (MAME 0.289 set).

## Building

* Quartus Prime Lite 17.0 (`C:\intelFPGA_lite\17.0`): `powershell -ExecutionPolicy Bypass -File scripts\build.ps1`
  (waits for any other Quartus job on the machine first; writes `build/build-summary.txt`,
  `output_files/RShark.rbf`, `Releases/RShark_YYYYMMDD.rbf`).
* Simulation (ModelSim-Intel Starter 10.5b from the same install): `scripts/sim.sh all`.
* ROM tooling (Python 3 + numpy): `python scripts/romtool.py verify|regions|stream|images|mra|mracheck`.
