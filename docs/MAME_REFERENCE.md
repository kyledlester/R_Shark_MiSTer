# MAME reference

MAME is used as the executable hardware specification.

| Item | Value |
| --- | --- |
| MAME binary | 0.289 (`mame0289`), `C:\Users\klest\Downloads\mame\mame.exe` |
| MAME source | tag `mame0289`, commit `f34f02505e32c1993c6a782b6814232cbfc74e36` (sparse checkout in `local/mame`, not committed) |
| Driver | `src/mame/dooyong/dooyong.cpp` (`rshark_state`, `dooyong_68k_state`) |
| Tilemap device | `src/mame/dooyong/dooyong_tilemap.cpp/.h` (`rshark_rom_tilemap_device`) |
| Also read | `emu/drawgfx.cpp` + `drawgfxt.ipp` (prio_transpen), `emu/tilemap.cpp`, `emu/screen.cpp` (vblank order), `emu/video/generic.cpp` (sprite gfx layout), `devices/video/bufsprite.h`, `devices/sound/okim6295.cpp`, `devices/sound/ymopm.cpp` |
| ROM set | `rshark.zip`, 21 files, `mame -verifyroms rshark`: good (CRCs in `scripts/romtool.py`) |

## Capture tooling (`scripts/mame/`)

All scripts are MAME Lua autoboot scripts; run from the MAME directory, e.g.

```
mame rshark -rompath roms -autoboot_script <repo>/scripts/mame/capture_frames.lua -nothrottle -video none -sound none -skip_gameinfo
```

Environment variables select output (`RS_OUT`), frames (`RS_FRAMES`) and optional input events
(`RS_INPUTS`). MAME 0.289 Lua has no `screen:vpos()`; the beam is derived from
`screen:time_until_pos(0,0)` and `frame_period` / `scan_period`.

| Script | Output |
| --- | --- |
| `io_trace.lua` | every 68000 access to 0x0C0000-0x0CFFFF with frame/line/dot (palette writes summarized) |
| `write_hist.lua` | scanline histograms of sprite RAM / palette traffic, reads of unmapped space |
| `dump_regions.lua` | MAME's ROM regions (16-bit regions via `read_u16`) - compared byte-exact with `romtool.py regions` |
| `capture_frames.lua` | per frame: palette, sprite buffer, tilemap/ctrl registers, work RAM, rendered pixels |

### Established MAME behaviours (measured)

* **Render instant.** `screen_device::vblank_begin` calls `frame_update()` (the whole frame is
  rendered - R-Shark never forces partial updates) and *then* the vblank callbacks, so
  `buffered_spriteram16_device::vblank_copy_rising` copies sprite RAM **after** the frame is drawn.
  vblank begins at line 248 (visible area bottom + 1). Frame N therefore uses: tilemap registers,
  control byte and palette as of line 248 of frame N, and the sprite RAM copied at line 248 of
  frame N-1.
* **`screen:pixels()`** returns the previously completed bitmap: the pixels of the frame rendered
  at `frame_done(N)` are read at `frame_done(N+1)` (`capture_frames.lua` RS_PIXDELAY=1). With that,
  `scripts/refrender.py` reproduces all 60 captured attract frames (every 60th frame up to 3600)
  pixel-exactly.
* **Palette at readout.** MAME keeps the screen as palette indices and converts them to RGB when
  the bitmap is read out, so `pixels()` at `frame_done(N+1)` applies the palette as of N+1. Frames
  where the palette changes between N and N+1 (Super-X flash effects) match the reference only with
  the N+1 palette; with it, Super-X attract frames 356/358/360 are pixel-exact too.
* The scripts detect the set (`manager.machine.system.name`) and use the Super-X addresses
  (I/O block 0x080000, RAM 0x0D0000) when running `superx`.
* **When the game writes** (1800 frames of attract, `io_trace.lua` / `write_hist.lua`):
  * all 32 tilemap control registers: in the IRQ6 handler, lines 123-126 (every frame);
  * palette: IRQ6 handler, lines 122-133 (and 207-218 during some fades); never read back;
  * control byte 0x0C0015 and the 0x0C0018/0x0C001A zero writes: IRQ5 handler, line 248;
  * sound latch 0x0C0013: IRQ6 handler, line 122;
  * sprite RAM: read and written by the main loop throughout the frame;
  * DSW / P1_P2 / SYSTEM reads; no reads of palette, tilemap registers or unmapped addresses; no
    writes to 0x050000-0x0BFFFF.
* Register values seen: tilemap reg 6 = 0x00 (never bit 5 = "lastday" format, never bit 4 = layer
  disable in attract), reg 5 = 0x07/0x36, reg 7 = 0xFA/0x00, control byte 0x20/0x30 (bit 4 toggles).
