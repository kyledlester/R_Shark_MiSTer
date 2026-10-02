# R-Shark / Super-X (Dooyong) for MiSTer

A MiSTer FPGA core for Dooyong's 68000-based vertical shoot 'em ups **R-Shark** (1995) and
**Super-X** (1994). One core (`RShark`) runs every supported game; each game has its own MRA.

I created this core because I wanted to play these games on my MiSTer FPGA. I am posting it here and open sourcing it for everyone to enjoy and give feedback/make improvements. This core was created with the assistance of AI tooling.

**Status: beta.** All four sets boot, run their attract mode and are playable on real MiSTer
hardware with graphics, controls and sound.

## Quick start

1. Copy the core from [`Releases/`](Releases/) (`RShark_YYYYMMDD.rbf`) to
   **`/media/fat/_Arcade/cores/`**.
2. Copy the MRA files from [`MRA/`](MRA/) to **`/media/fat/_Arcade/`**.
   For the alternative sets, copy the `_<Game>` folders from
   [`MRA/_alternatives/`](MRA/_alternatives/) to **`/media/fat/_Arcade/_alternatives/`**.
3. Put the MAME ROM zips (MAME 0.289 sets) in **`/media/fat/games/mame/`**.
4. Load a game from the **Arcade** menu.

ROMs are not included. You must supply your own.

## Supported games

| Game | MAME set | Year | Genre | Board | Status |
| --- | --- | --- | --- | --- | --- |
| R-Shark (set 1) | `rshark` | 1995 | Vertical shoot 'em up | Dooyong | Boots to title screen and is playable |
| Super-X (NTC) | `superx` | 1994 | Vertical shoot 'em up | Dooyong | Boots to title screen and is playable |

### Alternatives

These use the same core and the same board settings as the main set, with a
different ROM set.

| Game | MAME set | Year | Parent game | Status |
| --- | --- | --- | --- | --- |
| R-Shark (set 2) | `rsharka` | 1995 | R-Shark | Boots to title screen and is playable |
| Super-X (Mitchell) | `superxm` | 1994 | Super-X | Boots to title screen and is playable |

### ROM notes

* The alternative sets work with **split or merged** zips. Their MRAs look in the clone zip first
  and then in the parent zip, so `rshark.zip` / `superx.zip` must also be present. A *non-merged*
  `rsharka.zip` that stores the shared files under the clone's own names will not load.

## About the hardware

R-Shark and Super-X run on the same Dooyong board:

* Motorola **68000** main CPU at 8 MHz.
* **Z80** sound CPU at 4 MHz with a Yamaha **YM2151** (FM) and an **OKI M6295** (ADPCM samples).
* Four ROM-based tilemap layers (the tile maps themselves are stored in ROM, not RAM) and buffered
  16x16 sprites.
* Vertical (rotated) monitor, 384 x 240 visible.

## About the core

* One RBF for both games. The MRA sends a game-select byte; Super-X's different memory map is
  handled in the core. See [docs/MRA_FORMAT.md](docs/MRA_FORMAT.md).
* Full video: all four tilemap layers, sprites, priorities and flip screen.
* Sound: YM2151 and OKI M6295, mixed with MAME's levels.
* Native 15 kHz output for CRTs, with optional CRT Adjust (H-size, H-position, V-shift) thanks to
  rmonic79/MiSTer-CRT-Adjust.
* OSD options: aspect ratio, orientation and rotation for HDMI, scandoubler effects, DIP switches
  (from each MRA), CRT Adjust, pause options, and a Debug submenu (status overlay, test pattern).

MAME's `dooyong` driver (0.289) is the behavioural reference.

### Known issues

* The original PCB's video timing has never been measured; the core uses MAME's raster
  (15.36 kHz / 60.00 Hz). Native CRT output follows it.
* Because this raster has a short front porch, CRT Adjust's H-Position only goes 3 steps left.
* Very rarely a single sprite updates one frame later than it should.

More detail: [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

## Releases

Builds are in [`Releases/`](Releases/) as `RShark_YYYYMMDD.rbf`. The MRAs name the core without
the date (`<rbf>RShark</rbf>`), and MiSTer loads the newest dated file in `_Arcade/cores/`. You are
welcome to run your own build if you'd prefer.

## Building

Quartus Prime Lite 17.0. Open `RShark.qpf` and compile; the build copies a dated RBF into
`Releases/`. See [docs/BUILDING.md](docs/BUILDING.md).

## Documentation

* [Architecture](docs/ARCHITECTURE.md)
* [Memory map](docs/MEMORY_MAP.md)
* [Video](docs/VIDEO.md)
* [Audio](docs/AUDIO.md)
* [MRA format](docs/MRA_FORMAT.md)
* [Known issues](docs/KNOWN_ISSUES.md)
* [Building](docs/BUILDING.md)
* [Credits and third-party components](docs/REFERENCES.md)

## License

GPL-3.0-or-later (see [LICENSE](LICENSE)). The MiSTer framework in `sys/` keeps its own notices
([LICENSE.MiSTer](LICENSE.MiSTer)); FX68K, jt51, jt6295, the SDRAM controller and CRT Adjust are
GPL-3.0-or-later, and T80 uses a BSD-style licence. See [docs/REFERENCES.md](docs/REFERENCES.md).

No ROMs or other game data are included in this repository.
