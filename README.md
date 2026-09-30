# R-Shark (Dooyong, 1995) for MiSTer

MiSTer FPGA core for Dooyong's **R-Shark** (MAME set `rshark`), a vertical shoot 'em up on the
Dooyong 68000 board: 68000 @ 8 MHz, Z80 @ 4 MHz, YM2151 + OKI M6295, four ROM-based tilemap layers
and buffered 16x16 sprites.

**Status: first pass, awaiting hardware validation.** In simulation against MAME 0.289: the whole
board runs the real game from reset with displayed frames pixel-exact to MAME, and the sound board's
register stream and audio match MAME (see [docs/MILESTONES.md](docs/MILESTONES.md)). Quartus timing
is closed.

ROMs are not included. You must supply your own `rshark.zip` (MAME 0.289 set, `mame -verifyroms
rshark` = good).

## Installation

1. Copy `Releases/RShark_YYYYMMDD.rbf` to `/media/fat/_Arcade/cores/`.
2. Copy `mra/R-Shark (set 1).mra` to `/media/fat/_Arcade/`.
3. Copy `rshark.zip` to `/media/fat/games/mame/`.
4. Load *R-Shark (set 1)* from the Arcade menu.

## Controls

| Game | MiSTer (default pad) |
| --- | --- |
| 8-way joystick | D-pad / stick |
| Button 1 (shot) | A |
| Button 2 (bomb) | B |
| Buttons 3, 4 | X, Y (unused by the game as far as known) |
| Start | Start |
| Coin | Select |
| Service | R |
| Pause (core) | L |

Player 2 uses the second controller.

## OSD

* **Orientation** Vert/Horz and **Rotate CCW/CW** (HDMI; the game is rotated counter-clockwise).
* **DIP switches** (from the MRA): coinage, lives, difficulty, continue, demo sounds, flip screen,
  service mode.
* **CRT Adjust** (analog 15 kHz geometry), **Scandoubler Fx**, **Pause** options.
* **Debug overlay**: six hex counters (see below). **Video test pattern**: colour bars on the
  native raster.

## Video

Native raster 512 x 256 total, 384 x 240 active, 7.864 MHz dot clock, **15.36 kHz / 60.00 Hz** -
MAME's logical raster (the original PCB timing has not been measured; docs/VIDEO.md). On an
analog/direct-video setup the core outputs the unrotated 15 kHz picture for a rotated (vertical)
CRT; HDMI uses the MiSTer framebuffer rotation.

## Debug overlay (top-left of the rotated picture)

| Line | Left 16 bits | Right 16 bits |
| --- | --- | --- |
| 1 | - | 68000 program address (24 bits) |
| 2 | frames (vblanks) | IRQ5 acknowledges |
| 3 | IRQ6 acknowledges | sound-latch writes (68000) |
| 4 | sound-latch reads (Z80) | Z80 interrupts (YM2151 timer) |
| 5 | YM2151 writes | OKI writes |
| 6 | render overruns | `loaded` flag, control byte |

## Building

* Quartus Prime Lite 17.0: `powershell -ExecutionPolicy Bypass -File scripts\build.ps1` (waits for any
  other Quartus job on the machine first; writes `build/build-summary.txt`, `output_files/RShark.rbf`,
  `Releases/RShark_YYYYMMDD.rbf`).
* Simulation (ModelSim-Intel Starter 10.5b from the Quartus install): `scripts/sim.sh <test>`; tests
  needing ROM data use images from `python scripts/romtool.py regions|stream|images` (written to
  `local/`, never committed) and MAME captures from `scripts/mame/*.lua`.

Documentation: [architecture](docs/ARCHITECTURE.md), [memory map](docs/MEMORY_MAP.md),
[ROM layout](docs/ROM_LAYOUT.md), [video](docs/VIDEO.md), [audio](docs/AUDIO.md),
[MAME reference](docs/MAME_REFERENCE.md), [reuse and licences](docs/REUSE_AND_LICENSES.md),
[known issues](docs/KNOWN_ISSUES.md).

## Licence

GPL-3.0-or-later (see `LICENSE`); MiSTer framework under `LICENSE.MiSTer`. Reused components and
their licences: [docs/REUSE_AND_LICENSES.md](docs/REUSE_AND_LICENSES.md).
