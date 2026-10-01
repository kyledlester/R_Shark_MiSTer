# R-Shark / Super-X (Dooyong) for MiSTer

MiSTer FPGA core for two Dooyong vertical shoot 'em ups on the same 68000 board (68000 @ 8 MHz,
Z80 @ 4 MHz, YM2151 + OKI M6295, four ROM-based tilemap layers, buffered 16x16 sprites):

| Game | MAME set | MRA | Status |
| --- | --- | --- | --- |
| R-Shark (set 1), 1995 | `rshark` | `mra/R-Shark (set 1).mra` | working on hardware (owner report) |
| Super-X (NTC), 1994 | `superx` | `mra/Super-X (NTC).mra` | verified in simulation against MAME 0.289 (boot, attract, gameplay, sound); hardware test pending |

One RBF (`RShark`) runs both; each MRA tells the core which game it is loading (a game-select
byte on ioctl index 1) and the core uses that game's 68000 address map.

ROMs are not included. Supply your own `rshark.zip` / `superx.zip` (MAME 0.289 sets; `mame
-verifyroms rshark superx` = good).

## Installation

1. Copy `Releases/RShark_YYYYMMDD.rbf` to `/media/fat/_Arcade/cores/` (remove older `RShark_*.rbf`).
2. Copy both MRAs from `mra/` to `/media/fat/_Arcade/`. Use the new R-Shark MRA too: it now sends
   the game-select byte.
3. Copy `rshark.zip` and/or `superx.zip` to `/media/fat/games/mame/`.
4. Load *R-Shark (set 1)* or *Super-X (NTC)* from the Arcade menu.

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

Player 2 uses the second controller. Both games use the same controls.

## OSD

* **Orientation** Vert/Horz and **Rotate CCW/CW** (HDMI; the game is rotated counter-clockwise).
* **DIP switches** (from each MRA, as MAME defines them): coinage, lives, difficulty, continue, demo
  sounds, flip screen, and SWA:1 (R-Shark: service mode; Super-X: "Unknown (SWA:1)" - documented as
  service mode but MAME notes it has no effect).
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
