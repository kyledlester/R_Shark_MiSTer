# Video

## What MAME models (0.289) - verified by `scripts/refrender.py` (60/60 attract frames pixel-exact)

Raster: 512 x 256 bitmap, visible x 64..447, y 8..247 (384 x 240), ROT270. Palette: 2048 entries
xRGB_555 (bits 14-10 R, 9-5 G, 4-0 B; 8-bit = x<<3 | x>>2), black pen outside all layers.

Draw order and priority bitmap (`screen_update_rshark`):

1. fill black, priority 0
2. BG0: opaque (no transparent pen), priority |= 1
3. BG1: pen 15 transparent, priority |= (control bit 4 ? 2 : 1)
4. FG0: pen 15 transparent, priority |= 2
5. FG1: pen 15 transparent, priority |= 2
6. sprites, entry 255 down to 0 (`prio_transpen`, pen 15 transparent): a pixel is drawn only if
   `(1 << pri) & pmask == 0` with `pmask = 0xF0F0 | (colour 0 or 15 ? 0xCCCC : 0) | 1<<31`, and
   **every** opaque sprite pixel then sets pri = 31 (drawn or not). Consequences, used by the RTL:
   * only priority bit 1 matters: colour 0/15 sprites are hidden behind BG1 (when control bit 4)
     and FG0/FG1 opaque pixels, all other sprites are in front of every layer;
   * between sprites, the **highest index** opaque pixel wins, and if that pixel is hidden the
     tile shows (lower-index sprites never show through). Equivalent: draw sprites 0..255
     overwriting, then apply the colour-0/15 test to the surviving pixel.

### ROM tilemap (`rshark_rom_tilemap_device`)

Per layer, 8 byte registers (68000 word addresses, low byte): r0 X scroll low, r1 X "page" (units
of 256 pixels = 16 columns), r2 unknown (written continuously by some Dooyong games), r3/r4 Y
scroll low/high, r5 unknown (0x07 / 0x36 written at boot), r6 control (bit 4 = disable layer,
bit 5 = alternative "lastday" attribute format, never set by R-Shark), r7 unknown (0xFA / 0x00).

Tilemap: 64 x 32 tiles of 16x16 (1024 x 512 pixels), `TILEMAP_SCAN_COLS`, wrapping. For bitmap
pixel (x, y):

```
tx = (x + r0) & 1023            ty = (y + (r4:r3)) & 511
entry = ((tx>>4) * 32 + (ty>>4) + r1 * 512) & 0x1FFFF
attr  = region word[entry]      colour = tmap_hi[layer_offset + entry] & 15
code  = attr & 0x1FFF, flip X = attr bit 14, flip Y = attr bit 15   (bit 13 unused)
pen   = tile[code][ty&15 ^ 15*flipY][tx&15 ^ 15*flipX]
index = layer_base + colour*16 + pen   (BG0 1024, BG1 768, FG0 512, FG1 256)
```

(With r6 bit 5: code = attr bit15 << 9 | attr & 0x1FF, flip X/Y = attr bits 9/10; the colour is
still taken from tmap_hi.)

Tile pixels (MAME `spritelayout`): 128 bytes per tile; row r = 4 bytes at 4r (x 0-7) and 4 bytes at
64+4r (x 8-15); in each 4-byte group, bytes 0-1 hold x 0-3 and bytes 2-3 hold x 4-7, as nibbles
plane0 (MSB of the pen), plane1 | plane2, plane3, pixel 0 in the nibble MSB.

### Sprites

Sprite RAM 0x4D000 is `BUFFERED_SPRITERAM16`: copied at vblank begin (line 248), after the frame is
rendered. 256 entries x 8 words: w0 bit 0 enable; w1 bits 3-0 width-1, 7-4 height-1 (in 16-pixel
tiles); w3 code; w4 bits 8-0 X; w6 bits 8-0 Y (signed 9-bit); w7 bits 3-0 colour (palette 0-255).
Tiles are drawn row-major with code incrementing (`code % 16384`), at (X + 16*col, Y + 16*row) in
bitmap coordinates, clipped to the visible area, no wrap. Sprite pixels
(`gfx_8x8x4_col_2x2_group_packed_msb`): same row layout as the tilemap tiles, but each byte is two
packed pixels, high nibble first.

Flip screen (control bit 0, set by the game from the Flip Screen DIP): `tilemap_t` flips around the
visible-area centre (`effective_rowscroll` with extent 512 / 256), i.e. display (x, y) shows the
unflipped tilemap pixel (511 - x, 255 - y); sprites use `sx = 498 - 16*w - sx`,
`sy = 240 - 16*h - sy` with flipped tiles, i.e. display (x, y) shows the unflipped sprite pixel
(513 - x, 255 - y) - a 2-dot offset against the tilemaps that MAME reproduces from its formula.
refrender.py implements both literally and matches 12/12 MAME frames captured with the DIP on.

## FPGA implementation

### Raster (rshark_video_timing.sv)

`ce_pix` = clk_sys / 12 = 7.864320 MHz: 512 x 256 at 15.360 kHz / 60.000 Hz, identical to MAME's
logical raster. HSync dots 468-504 (4.7 us), VSync lines 250-252. **Not PCB-verified**: no
measurement of the real board's dot clock or totals was found (see KNOWN_ISSUES).

### Register timing (design decision)

The game writes all tilemap registers mid-frame (IRQ6, lines 123-126) and the palette in the same
handler. MAME samples everything at line 248, which a raster cannot do. The FPGA:

* latches the 32 tilemap registers at the start of line 248 (with the sprite-buffer copy), so the
  whole displayed frame uses one consistent set, together with the sprites of the same game tick;
* latches the palette at line 248 too: CPU writes go to a shadow palette that is copied (2048
  clocks, inside vblank) to the display palette. Super-X rewrites 233 palette entries every other
  frame in some scenes, in the same IRQ6 window as the registers (lines 120-131); a live palette
  would show a torn band at line ~125 on those frames. (R-Shark ran on hardware with a live palette
  before this change; its palette writes are far rarer.)
* keeps the control byte live (written in vblank).

Relative to MAME the tilemaps and palette therefore appear one frame later in relation to the
sprites (MAME shows scroll of tick T with sprites of tick T-1; the FPGA shows both of tick T one
frame later). Documented as an unverified hardware assumption.

### Pipeline (per line, double-buffered line buffers)

During raster line v, line v+1 is rendered (for v+1 in 8..247):

* `rshark_tilemap`: one engine, layers BG0, BG1, FG0, FG1 in turn. Per layer 13 map bursts (2
  entries + colours each, from the row-major map copy) and 24-25 pixel-row bursts; writes 1 pixel
  per clock into the tile line buffer entry {valid, pri, index[10:0]} (BG0 writes every pixel,
  the others only non-15 pens; pri = layer sets priority bit 1). Overwrite order equals MAME's OR
  of priority bits because only BG0 precedes BG1.
* `rshark_sprites`: scans a 256-entry Y table (built during the vblank copy) one entry per clock in
  index order 0..255, draws every hit tile row with 2 pixels per clock into an even/odd banked
  sprite line buffer {colour, pen}; later entries overwrite earlier ones.
* output: at dot h the two buffers are read (and cleared); sprite pixel shown unless transparent or
  (colour 0/15 and tile pri); else tile index, else black; palette lookup; one-dot pipeline delay
  (blank/sync delayed with it).

Flip screen: the renderers draw logical line 255 - y for display line y, and the output side
reads the tile buffer at 511 - x and the sprite buffer at 513 - x.

Budget: 6144 clk_sys per line. Load reduction:
* map cache: tilemap entries are ROM and one tile row serves 16 lines; each layer keeps its row's
  13 column-pair bursts (tag {row, first pair}), so map fetches happen on 1 line in 16;
* sprite tiles entirely outside x 64..449 are not fetched (MAME clips them);
* the SDRAM arbiter issues the next client's request as soon as the controller completes the
  previous access.

Measured (sim m11, production path): busiest attract frame 2760 (197 visible sprite tile-rows on
one line) 4291 clocks = 70 % of the line; frame 1800 2617; flipped frame 3000 3152. The busiest
gameplay frame of a MAME demo run (frames 600-7200, coin/start/autofire) has 164 visible tile-rows
on its worst line.
