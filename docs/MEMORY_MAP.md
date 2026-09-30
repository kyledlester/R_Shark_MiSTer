# Memory maps

Source: MAME 0.289 `rshark_state::rshark_map`, `dooyong_state::bluehawk_sound_map`; behaviour checks
from MAME traces (docs/MAME_REFERENCE.md).

## 68000 (8 MHz)

`map.global_mask(0xfffff)`: **A23-A20 are ignored**. This is load-bearing: the reset SSP is
`0x0034D000`, which only lands in RAM (0x4D000) through the mask.

| Address (20-bit) | R/W | Function | FPGA |
| --- | --- | --- | --- |
| 00000-3FFFF | R | program ROM (rspl00 even/high, rspu00 odd/low) | BRAM 128K x 16 |
| 40000-4CFFF | RW | work RAM | BRAM 32K x 16 (byte lanes) |
| 4D000-4DFFF | RW | sprite RAM (256 entries x 8 words) | BRAM 2K x 16, dual port (copy engine) |
| 4E000-4FFFF | RW | work RAM | same BRAM as 40000 |
| C0002 | R | DSW (SWA = bits 7-0, SWB = bits 15-8), active low | |
| C0004 | R | P1 (bits 7-0) / P2 (bits 15-8), active low | |
| C0006 | R | SYSTEM bits 7-0 (upper byte reads 0x00 in MAME) | |
| C0013 | W | sound latch (byte; a word write to C0012 also latches its low byte) | |
| C0015 | W | control: bit 0 flip screen, bit 4 BG1 priority, bit 5 unknown (written 1) | |
| C0018, C001A | W | 0x0000 written every IRQ5 - no function known; ignored | |
| C4000-C400F | W | BG0 control, 8 registers at word addresses, low byte only (umask 0x00ff) | |
| C4010-C401F | W | BG1 control | |
| C8000-C8FFF | W | palette RAM, 2048 x xRGB555 (byte lanes honoured) | BRAM 2K x 16 |
| CC000-CC00F | W | FG0 control | |
| CC010-CC01F | W | FG1 control | |
| everything else | - | unmapped: reads return 0 (MAME default), writes ignored, always DTACK | |

Interrupts (autovectored, `HOLD_LINE`: pending until the 68000 acknowledges that level):

| Level | When | Vector | Handler role (from traces) |
| --- | --- | --- | --- |
| 5 | start of line 248 ("vblank-out") | 0x0858 | control byte, C0018/C001A |
| 6 | start of line 120 ("timer?") | 0x08CA | tilemap registers, palette, sound latch |

## Super-X (MAME `superx_map`)

Same board, same devices and offsets; only the RAM block and the I/O + video block move, and the
program is at the same place. Global mask 0xFFFFF as for R-Shark (reset SSP 0x000DD000).

| R-Shark | Super-X | Function |
| --- | --- | --- |
| 00000-3FFFF | 00000-3FFFF | program ROM |
| 40000-4FFFF | D0000-DFFFF | work RAM (sprite RAM at +D000) |
| C0000-C0FFF | 80000-80FFF | DSW / inputs / sound latch / control / 0x18,0x1A writes |
| C4000-C401F | 84000-8401F | BG0 / BG1 registers |
| C8000-C8FFF | 88000-88FFF | palette |
| CC000-CC01F | 8C000-8C01F | FG0 / FG1 registers |

FPGA (rshark_main.sv): with `superx` set, the top address nibble is translated to R-Shark's (D -> 4,
8 -> C) before the shared decoder, and R-Shark's own blocks (4, C) become unmapped; everything else
(unmapped reads 0, e.g. Super-X's boot-time accesses to 0xE0000-0xEFFFF and 0x9xxxx) is unchanged.
`superx` comes from the MRA's ioctl index-1 byte (00 = R-Shark, 01 = Super-X), latched by
rshark_core.sv while the board is held in reset for the download.

## Z80 (4 MHz)

| Address | R/W | Function |
| --- | --- | --- |
| 0000-EFFF | R | rse3.bin (64 KB file, top 4 KB unmapped) |
| F000-F7FF | RW | RAM 2 KB |
| F800 | R | sound latch (generic_latch_8: no flags, no interrupt) |
| F808-F809 | RW | YM2151 (address/data, status) |
| F80A | RW | OKI M6295 |

IRQ: YM2151 IRQ -> Z80 INT (the program runs IM 1, handler at 0x0038 -> 0x009E). No NMI source.
The program also writes F806 and F80C in a few places (unmapped in MAME; ignored).

## Inputs

P1_P2 (C0004): bit 0 right, 1 left, 2 down, 3 up, 4-7 buttons 1-4 (P1); bits 8-15 same for P2.
SYSTEM (C0006): bit 0 coin 1, 1 start 1, 2 coin 2, 3 start 2, 4 service, 5-7 unused (read 1).
DSW: see docs/ARCHITECTURE.md "DIP switches" and the MRA.
