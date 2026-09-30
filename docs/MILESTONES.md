# Milestones

| ID | Milestone | Status | Evidence |
| --- | --- | --- | --- |
| M0 | Project skeleton, PLL, build + sim scripts | done | Quartus build, `sim.sh m0` PASS |
| M1 | Hardware specification from MAME 0.289 | done | docs/MEMORY_MAP.md, VIDEO.md, AUDIO.md, MAME_REFERENCE.md |
| M2 | ROM inventory, regions, stream, MRA, loader | done | `romtool.py verify` 21/21 CRC; regions byte-exact vs MAME; `mracheck` PASS; `sim.sh m2`: full MRA stream through loader + arbiter + sdram.sv == expected SDRAM/BRAM images |
| M3 | FX68K boot from the real ROM | done | `sim.sh m3`: 200,000 bus transactions identical to MAME |
| M4 | Complete 68000 address decoder | done | 328,777 transactions identical (boot RAM tests, I/O, video registers) |
| M5 | Interrupts, frame timing, sprite buffering | done | interrupts on MAME's lines/transactions; divergence only in sub-us IACK timing (KNOWN_ISSUES 6) |
| M6 | Inputs / DIPs | implemented | active-low mapping as MAME, MRA DIP table; hardware test pending |
| M7 | Palette | done | pixel-exact renders |
| M8 | Dooyong ROM tilemap research | done | refrender.py pixel-exact on 60 attract, 17 gameplay, 12 flipped MAME frames |
| M9 | Video timing | done | m0; raster = MAME logical raster |
| M10-M14 | Tile decode, tilemaps, sprites, priority, flip | done | `sim.sh m11`: MAME frames (busiest, flipped) pixel-exact through the production path |
| M15 | Video-complete integration | done (sim) | `sim.sh m15` (whole board from reset): displayed frames 55-62 pixel-exact vs MAME; 68000 latch writes identical in count/values |
| M16 | Z80 sound CPU | done (sim) | `sim.sh m16`: 3 s, 10,419 YM/OKI writes identical to MAME in order |
| M17 | YM2151 | done (sim) | audio vs `mame -wavwrite`: envelope corr 0.912, spectrum corr 0.929 |
| M18 | OKI6295 | in verification | first OKI play command at 7.1 s; 8.2 s run pending |
| M19 | Mix / playable gate | built | RBF with timing closed; hardware test is the next information source |
| M22 | Timing closure | done | clk_sys +0.944 ns, clk_snd +4.009 ns, all setup/hold positive |
| M20, M21, M23 | CRT pass, accuracy, release | pending hardware feedback | |
