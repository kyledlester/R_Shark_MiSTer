# Milestones

| ID | Milestone | Status | Evidence |
| --- | --- | --- | --- |
| M0 | Project skeleton, PLL, build + sim scripts | done | Quartus build (timing met), `sim.sh m0` PASS |
| M1 | Hardware specification from MAME 0.289 | done | docs/MEMORY_MAP.md, VIDEO.md, AUDIO.md, MAME_REFERENCE.md |
| M2 | ROM inventory, regions, stream, MRA | done | `romtool.py verify` (21/21 CRC), regions byte-exact vs MAME (`dump_regions.lua`), `mracheck` PASS |
| M3 | FX68K boot from the real ROM | done | `sim.sh m3`: 200,000 bus transactions identical to MAME |
| M4 | Complete 68000 address decoder | done | m3 long trace: 328,777 transactions identical (boot RAM tests, I/O, video registers) |
| M5 | Interrupts, frame timing, sprite buffering | done | all interrupts in 14 frames on MAME's lines/transactions; divergence only in sub-us IACK timing (KNOWN_ISSUES 6) |
| M6 | Inputs / DIPs | implemented | active-low mapping as MAME; MRA DIP table; hardware test pending |
| M7 | Palette | done | pixel-exact renders (m11) |
| M8 | Dooyong ROM tilemap research | done | refrender.py pixel-exact on 60/60 MAME frames |
| M9 | Video timing | done | m0; raster = MAME logical raster |
| M10-M14 | Tile decode, tilemaps, sprites, priority | done | `sim.sh m11`: MAME frame rendered through the production path pixel-exact |
| M15 | Integrated video-complete build | in progress | whole-board sim (m15) + Quartus build |
| M16-M19 | Z80, YM2151, OKI, mix | implemented | compiled; verification pending |
| M20-M23 | CRT pass, accuracy, timing closure, release | pending | |
