# R-Shark / Super-X (Dooyong) for MiSTer

MiSTer FPGA core for Dooyong's 68000-based vertical shoot 'em ups **R-Shark** (1995) and
**Super-X** (1994): 68000 @ 8 MHz, Z80 @ 4 MHz, YM2151 + OKI M6295, four ROM-based tilemap layers and
buffered 16x16 sprites. One core (`RShark`) runs every supported set; each MRA tells the core which
game it is loading.

**Status: beta.** All four sets below boot, run their attract mode and are playable on MiSTer
hardware with graphics, controls and sound (owner-tested). In development every set was also
checked against MAME 0.289 in simulation (CPU bus traces, pixel-exact frames, sound-chip register
streams and audio) - see [docs/MILESTONES.md](docs/MILESTONES.md).

| Game | MAME set | MRA |
| --- | --- | --- |
| R-Shark (set 1), 1995 | `rshark` | `MRA/R-Shark (set 1).mra` |
| Super-X (NTC), 1994 | `superx` | `MRA/Super-X (NTC).mra` |
| R-Shark (set 2), 1995 | `rsharka` (clone of `rshark`) | `MRA/_Alternatives/_R-Shark/R-Shark (set 2).mra` |
| Super-X (Mitchell), 1994 | `superxm` (clone of `superx`) | `MRA/_Alternatives/_Super-X/Super-X (Mitchell).mra` |

## Quick start

1. Copy the newest `Releases/RShark_YYYYMMDD.rbf` to **`/media/fat/_Arcade/cores/`** (delete older
   `RShark_*.rbf` files there).
2. Copy the MRA files from `MRA/` to **`/media/fat/_Arcade/`**, and the `_R-Shark` / `_Super-X`
   folders from `MRA/_Alternatives/` to **`/media/fat/_Arcade/_alternatives/`**.
3. Put the MAME ROM zips (MAME 0.289 sets) in **`/media/fat/games/mame/`**.
4. Load a game from the **Arcade** menu.

ROMs are not included. You must supply your own.

### ROM sets

* `rshark.zip`, `superx.zip`: the parent sets (`mame -verifyroms rshark superx` = good).
* `rsharka.zip`, `superxm.zip`: **split or merged** clone sets. The clone MRAs look in the clone zip
  first and then in the parent zip, and name the files shared with the parent by MAME's merge names
  (`rse4.bin`, ...), so the parent zip must be present. A *non-merged* `rsharka.zip` that stores the
  shared files under the clone's own names (`4.19`, ...) will not load.

If you previously installed R-Shark from this repository, replace its MRA too: every MRA now sends
a game-select byte, and an old R-Shark MRA can leave the core in Super-X mode after a Super-X game.

## Controls

| Game | MiSTer (default pad) |
| --- | --- |
| 8-way joystick | D-pad / stick |
| Button 1 (shot) | A |
| Button 2 (bomb) | B |
| Buttons 3, 4 | X, Y (not used by the games as far as known) |
| Start | Start |
| Coin | Select |
| Service | R |
| Pause (core) | L |

Player 2 uses the second controller. All four sets use the same controls.

## OSD

* **Aspect ratio**, **Orientation** (Vert/Horz) and **Rotate CCW/CW** for HDMI; the games are
  rotated counter-clockwise (MAME ROT270).
* **Scandoubler Fx**.
* **DIP Switches** (from each MRA, as MAME defines them): coinage (two coin-type tables), lives,
  difficulty, continue, demo sounds, flip screen and SWA:1 (R-Shark: Service Mode; Super-X:
  "Unknown (SWA:1)" - documented as service mode on the board, but MAME notes it has no effect).
* **CRT Adjust** submenu (native 15 kHz analog output): H-Size, H-Position, V-Shift. Off by default.
  Because this raster has a short front porch, H-Position only goes 3 steps left, and wider
  H-Size settings move the picture right automatically to keep it inside the line.
* **Pause options** submenu.
* **Debug** submenu: hex debug overlay (below) and a colour-bar test pattern on the native raster.

## Known limitations

* The original PCB's video timing has never been measured; the core uses MAME's logical raster
  (512 x 256 total, 384 x 240 active, 15.36 kHz / 60.00 Hz). Native CRT output follows it.
* Tilemap scroll registers and the palette take effect once per frame (at vertical blank). The
  games write them mid-frame; whether the real board latches them is unverified.
* Very rarely a single sprite updates one frame later than in MAME (a sub-microsecond CPU timing
  race at the sprite-buffer copy).
* The busiest measured scene uses about 70 % of the per-line drawing budget; the debug overlay
  counts any overruns (none seen).

Details: [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

## Video

Native raster 512 x 256 total, 384 x 240 active, 7.864 MHz dot clock, **15.36 kHz / 60.00 Hz** -
MAME's logical raster (the original PCB timing has not been measured; docs/VIDEO.md). On an
analog/direct-video setup the core outputs the unrotated 15 kHz picture for a rotated (vertical)
CRT; HDMI uses the MiSTer framebuffer rotation.

## Debug overlay (OSD Debug submenu; top-left of the rotated picture)

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
