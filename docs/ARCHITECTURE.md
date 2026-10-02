# Architecture

```
                         clk_sys 94.371840 MHz (rshark_pll) - everything is a clock enable of it
 HPS ioctl ──► rshark_loader ──► BRAM: 68000 ROM (128Kx16), Z80 ROM (64Kx8)
                     │
                     └──► rshark_sdram_arb ◄── OKI line cache (rshark_sound)
                               ▲   ▲         ◄── rshark_tilemap (4 layers, 1 engine)
                               │   └──────── ◄── rshark_sprites
                          sdram.sv (ch1, 4-word bursts) ─── SDRAM 32 MB
 rshark_main (FX68K 8 MHz, BRAM work RAM / sprite RAM, I/O, IRQ5/6, sprite copy, reg latch)
   ├─ palette write port ─► rshark_video (palette RAM, line buffers, mixer) ─► rgb
   ├─ sprite Y/attr tables ─► rshark_sprites
   ├─ latched tilemap regs ─► rshark_tilemap
   └─ sound latch ─► rshark_sound (T80 4 MHz, jt51 4 MHz, jt6295 1 MHz) ─► mono audio
 rshark_video_timing (512x256 @ ce_pix = clk/12) ─► IRQ6 (line 120), IRQ5 + copy + latch (line 248)
 RShark.sv: hps_io, pause, CRT Adjust, screen_rotate (ROT270 -> CCW, DDR3 FB), arcade_video
```

## Clocks (rshark_clocks.sv)

| Enable | Rate | Derivation |
| --- | --- | --- |
| ce_pix | 7.864320 MHz | clk_sys / 12, jitter-free |
| tick16 | 16 MHz average | fractional 3125/18432 of clk_sys (5-6 clocks apart) |
| phi1/phi2 | 8 MHz 68000 | alternate tick16 |
| ce_4m | 4 MHz | tick16 / 4 (Z80, YM2151) |
| ce_1m | 1 MHz | tick16 / 16 (OKI) |

`pause` freezes the emulated time bases and the interrupt events; the raster keeps running.

## Memory

| Data | Resource |
| --- | --- |
| 68000 program 256 KB | BRAM (256 M10K) - zero-wait, deterministic |
| work RAM 60 KB, sprite RAM 4 KB | BRAM (sprite RAM as 8 word-wide banks for a 256-clock copy) |
| palette 4 KB | BRAM (CPU write port, video read port) |
| Z80 program 64 KB, RAM 2 KB | BRAM |
| graphics, tilemaps, OKI samples (~8.3 MB) | SDRAM (docs/MRA_FORMAT.md) |

## Bus timing

The 68000 bus uses the owner's NA-1 FX68K transport (held request, registered DTACK) and a
backend that answers reads after 2 clocks and writes immediately: every bus cycle is 4 CPU clocks
(measured: AS-to-AS 8 ticks). Sprite RAM writes to entries not yet copied by the 2.7 us vblank copy
wait for it (makes the copy an atomic snapshot like MAME's).

## Video

docs/VIDEO.md. Line-buffered renderer, one line ahead of the raster, 4291 of 6144 clocks per line (70 %)
used in the measured busiest attract frame.

## Debug overlay

OSD Debug submenu; drawn at the top left of the rotated picture.

| Line | Left 16 bits | Right 16 bits |
| --- | --- | --- |
| 1 | - | 68000 program address (24 bits) |
| 2 | frames (vblanks) | IRQ5 acknowledges |
| 3 | IRQ6 acknowledges | sound-latch writes (68000) |
| 4 | sound-latch reads (Z80) | Z80 interrupts (YM2151 timer) |
| 5 | YM2151 writes | OKI writes |
| 6 | render overruns | `loaded` flag, control byte |

## Verification

During development every block was checked against MAME 0.289 in ModelSim simulation and with a
Python reference renderer: 68000 bus traces identical to MAME's from reset, ROM download into SDRAM,
pixel-exact frames through the production video path (attract, gameplay, flip screen, both games and
both clones), whole-board runs from reset including scripted coin/start/play, sound-chip register
streams and audio compared with `mame -wavwrite`, and every CRT Adjust setting. That tooling depends
on locally captured MAME data and ROM images and is not part of this repository.
