# Milestones

| ID | Milestone | Status | Evidence |
| --- | --- | --- | --- |
| M0 | Project skeleton, PLL, build + sim scripts | done | Quartus build, `sim.sh m0` PASS |
| M1 | Hardware specification from MAME 0.289 | done | docs/MEMORY_MAP.md, VIDEO.md, AUDIO.md, MAME_REFERENCE.md |
| M2 | ROM inventory, regions, stream, MRA, loader | done | `romtool.py verify` 21/21 CRC; regions byte-exact vs MAME; `mracheck` PASS; `sim.sh m2`: full MRA stream through loader + arbiter + sdram.sv == expected SDRAM/BRAM images |
| M3 | FX68K boot from the real ROM | done | `sim.sh m3`: 200,000 bus transactions identical to MAME |
| M4 | Complete 68000 address decoder | done | 328,777 transactions identical (boot RAM tests, I/O, video registers) |
| M5 | Interrupts, frame timing, sprite buffering | done | interrupts on MAME's lines/transactions; divergence only in sub-us IACK timing (KNOWN_ISSUES 6) |
| M6 | Inputs / DIPs | done (sim) | `sim.sh m6`: 27 checks (all joystick/button/coin/start/service bits, DIP download); hardware test pending |
| M7 | Palette | done | pixel-exact renders |
| M8 | Dooyong ROM tilemap research | done | refrender.py pixel-exact on 60 attract, 17 gameplay, 12 flipped MAME frames |
| M9 | Video timing | done | m0; raster = MAME logical raster |
| M10-M14 | Tile decode, tilemaps, sprites, priority, flip | done | `sim.sh m11`: MAME frames (busiest, flipped) pixel-exact through the production path |
| M15 | Video-complete integration | done (sim) | `sim.sh m15` (whole board from reset): displayed frames 55-62 pixel-exact vs MAME; 68000 latch writes identical in count/values |
| M16 | Z80 sound CPU | done (sim) | `sim.sh m16`: 3 s, 10,419 YM/OKI writes identical to MAME in order |
| M17 | YM2151 | done (sim) | audio vs `mame -wavwrite`: envelope corr 0.912, spectrum corr 0.929 |
| M18 | OKI6295 | done (sim) | 8.2 s run: OKI phrases play from 7.13 s; audio 7.1-8.2 s level ratio 1.00, envelope corr 0.961 vs MAME |
| M19 | Mix / playable gate | built, awaiting hardware | `Releases/RShark_20260930.rbf` (timing closed) + MRA; mix = MAME gains; physical MiSTer test is the next information source |
| M22 | Timing closure | done | build 3: clk_sys +0.438 ns setup, all setup/hold positive; 82 % ALMs, 512/553 M10K |
| M20, M21, M23 | CRT pass, accuracy, release | pending hardware feedback | |

## Super-X support (shared RBF)

| ID | Item | Status | Evidence |
| --- | --- | --- | --- |
| SX1 | ROM set, regions, MRA | done | `mame -verifyroms superx` good; `romtool.py regions --game superx` == MAME region dump 9/9 (word-swapped regions included); `mracheck --game superx` PASS |
| SX2 | Game select | done | MRA ioctl index-1 byte; `sim.sh m6`: select/keep/clear checks (32 checks total) |
| SX3 | Super-X 68000 map | done | `sim.sh m3x +SUPERX`: 260,340 bus transactions identical to MAME, 4 interrupt entries at MAME's transactions (then the known IACK timing difference) |
| SX4 | ROM download | done | `sim.sh m2 +STREAM=local/superx/superx.rom +SIMDIR=local/superx/sim` PASS |
| SX5 | Video | done | refrender: attract 59/60 + 12/12 flipped + 60/60 gameplay pixel-exact (the remaining attract frame differs only by MAME's readout-time palette); RTL `m11` 7/7 Super-X frames (attract, flipped, gameplay boss scene) pixel-exact; `m15x` whole board frames 55-62 pixel-exact |
| SX6 | Sound | done | `m16x`: chip writes identical to MAME through the latch race once the Z80 starts with the 68000; audio vs MAME 0.4-11 s ratio 0.99, envelope 0.991, spectrum 0.989; OKI window 10.3-11 s ratio 1.03 |
| SX7 | Controls / gameplay on the FPGA | in progress | `m15x` with scripted coin/start/fire/movement vs MAME with the same inputs |
| SX8 | Shared RBF | built | timing closed (rebuild with the sound-reset change pending) |
