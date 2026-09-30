#!/usr/bin/env python3
"""R-Shark reference renderer: an executable restatement of MAME 0.289's R-Shark video
(dooyong.cpp screen_update_rshark / draw_sprites, dooyong_tilemap.cpp rshark_rom_tilemap_device,
emu/drawgfx prio_transpen, emu/tilemap priority OR). Used to prove the hardware model against MAME
captures (scripts/mame/capture_frames.lua) and as the golden model for RTL render tests.

  refrender.py check  DIR...        render each captured frame, compare with MAME's pixels.bin
  refrender.py png    DIR OUT.png   write reference render (and MAME diff if mismatching)

Frame directory contents: palette.bin, sprbuf.bin, regs.txt (+ pixels.bin for 'check').
ROM regions come from local/regions (scripts/romtool.py regions).
"""
import os, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REG_DIR = os.environ.get("RS_REGIONS", os.path.join(ROOT, "local", "regions"))   # RS_REGIONS=local/superx/regions for Super-X

W, H = 512, 256                   # MAME raster (bitmap coordinates)
VX0, VX1, VY0, VY1 = 64, 448, 8, 248
LAYERS = [  # name, palette base, transparent pen, tmap_hi (colour ROM) offset
    ("bg0", 1024, None, 0x60000),
    ("bg1", 768, 15, 0x40000),
    ("fg0", 512, 15, 0x20000),
    ("fg1", 256, 15, 0x00000),
]

_cache = {}


def region(name):
    if name not in _cache:
        _cache[name] = np.frombuffer(open(os.path.join(REG_DIR, name + ".bin"), "rb").read(), dtype=np.uint8)
    return _cache[name]


def decode_tiles_planar(reg):
    """MAME 'spritelayout' (dooyong.cpp): 16x16x4, planes {0,4,8,12}, x {0-3,16-19,256-259,272-275}
    (bit offsets, MSB-first), rows 32 bits apart, 128 bytes/tile. Returns [n,16,16] pens."""
    key = ("planar", id(reg))
    if key in _cache:
        return _cache[key]
    t = reg.reshape(-1, 2, 16, 4)                 # tile, half (x 0-7 / 8-15), row, byte
    bits = np.unpackbits(t, axis=3)                # [..., 32] MSB-first bit stream of the half-row
    pens = np.zeros((t.shape[0], 16, 16), np.uint8)
    for half in range(2):
        for i in range(8):
            base = 16 * (i // 4) + (i % 4)
            v = np.zeros((t.shape[0], 16), np.uint8)
            for p in range(4):
                v = (v << 1) | bits[:, half, :, base + 4 * p]
            pens[:, :, half * 8 + i] = v
    _cache[key] = pens
    return pens


def decode_tiles_packed(reg):
    """gfx_8x8x4_col_2x2_group_packed_msb: 16x16x4, x = nibbles (high first) of 4 bytes per 8-pixel
    half-row, right half +64 bytes, rows 4 bytes apart. Returns [n,16,16] pens."""
    key = ("packed", id(reg))
    if key in _cache:
        return _cache[key]
    t = reg.reshape(-1, 2, 16, 4)
    pens = np.zeros((t.shape[0], 16, 16), np.uint8)
    for half in range(2):
        for b in range(4):
            pens[:, :, half * 8 + 2 * b] = t[:, half, :, b] >> 4
            pens[:, :, half * 8 + 2 * b + 1] = t[:, half, :, b] & 15
    _cache[key] = pens
    return pens


def load_frame(d):
    pal = np.frombuffer(open(os.path.join(d, "palette.bin"), "rb").read(), dtype=">u2").astype(np.uint32)
    spr = np.frombuffer(open(os.path.join(d, "sprbuf.bin"), "rb").read(), dtype=">u2").astype(np.int64)
    regs, ctrl = {}, 0
    for line in open(os.path.join(d, "regs.txt")):
        f = line.split()
        if f[0] == "ctrl":
            ctrl = int(f[1], 16)
        else:
            regs[f[0]] = [int(x, 16) for x in f[1:]]
    return pal, spr, regs, ctrl


def palette_rgb(pal):
    """palette_device::xRGB_555 -> 8-bit via pal5bit (x<<3 | x>>2)."""
    def c5(x):
        return ((x << 3) | (x >> 2)).astype(np.uint8)
    rgb = np.stack([c5((pal >> 10) & 31), c5((pal >> 5) & 31), c5(pal & 31)], axis=1)
    return np.vstack([rgb, np.zeros((1, 3), np.uint8)])   # index 2048 = black pen


def tile_layer(name, regs, color_off):
    """Per-pixel (pen, colour) of one ROM tilemap over the whole 512x256 bitmap (MAME coordinates).
    Returns pens [H,W], palette colour [H,W], enabled."""
    r = regs[name]
    reg = region(name)
    words = reg[0::2].astype(np.int64) << 8 | reg[1::2]
    tmap_hi = region("tmap_hi")
    tiles = decode_tiles_planar(reg)
    scrollx = r[0]
    scrolly = r[3] | (r[4] << 8)
    ys, xs = np.mgrid[0:H, 0:W]
    tx = (xs + scrollx) & 1023                 # tilemap 64x32 tiles of 16x16, TILEMAP_SCAN_COLS
    ty = (ys + scrolly) & 511
    tile_index = (tx >> 4) * 32 + (ty >> 4)
    adj = tile_index + r[1] * (256 // 16) * 32  # adjust_tile_index
    attr = words[adj & 0x1ffff]
    if r[6] & 0x20:   # lastday-style word (never selected by R-Shark in the captures so far)
        code = ((attr >> 15) & 1) << 9 | (attr & 0x1ff)
        flipx = (attr >> 9) & 1
        flipy = (attr >> 10) & 1
    else:             # rshark_tile_callback: code = attr & 0x1fff; Y/X flip = bits 15/14
        code = attr & 0x1fff
        flipx = (attr >> 14) & 1
        flipy = (attr >> 15) & 1
    colour = tmap_hi[color_off + (adj & 0x1ffff)] & 0x0f
    px = (tx & 15) ^ (flipx * 15)
    py = (ty & 15) ^ (flipy * 15)
    pens = tiles[code % tiles.shape[0], py, px]
    return pens, colour, not (r[6] & 0x10)


def render(pal, spr, regs, ctrl):
    """Returns the 384x240 RGB image and the full-bitmap palette index / priority maps."""
    flip = bool(ctrl & 1)
    idx = np.full((H, W), 2048, np.int64)          # bitmap.fill(black_pen)
    pri = np.zeros((H, W), np.int64)               # screen.priority().fill(0)
    for name, base, trans, coff in LAYERS:
        lp = {"bg0": 1, "bg1": 2 if (ctrl & 0x10) else 1, "fg0": 2, "fg1": 2}[name]
        pens, colour, en = tile_layer(name, regs, coff)
        if not en:
            continue
        if flip:   # tilemap_t flip around the visible-area centre: (x, y) <- (511 - x, 255 - y)
            pens = pens[::-1, ::-1]
            colour = colour[::-1, ::-1]
        opaque = np.ones_like(pens, bool) if trans is None else pens != trans
        idx[opaque] = base + colour[opaque].astype(np.int64) * 16 + pens[opaque]
        pri[opaque] |= lp
    tiles = decode_tiles_packed(region("sprite"))
    for offs in range(len(spr) - 8, -1, -8):       # last entry first
        s = spr[offs:offs + 8]
        if not (s[0] & 1):
            continue
        code = int(s[3])
        color = int(s[7] & 15)
        pmask = 0xf0f0 | (0xcccc if color in (0, 15) else 0) | (1 << 31)
        width = int(s[1] & 15)
        height = int((s[1] >> 4) & 15)
        sx = int(s[4] & 0x1ff)
        sy = int(s[6] & 0x1ff)
        if sy & 0x100:
            sy -= 0x200
        if flip:   # dooyong_68k_state::draw_sprites flip branch
            sx = 498 - (16 * width) - sx
            sy = 240 - (16 * height) - sy
        for y in range(height + 1):
            for x in range(width + 1):
                t = tiles[code % tiles.shape[0]]
                if flip:
                    t = t[::-1, ::-1]
                    x0, y0 = sx + 16 * (width - x), sy + 16 * (height - y)
                else:
                    x0, y0 = sx + 16 * x, sy + 16 * y
                for yy in range(16):
                    py = y0 + yy
                    if py < VY0 or py >= VY1:
                        continue
                    for xx in range(16):
                        pxx = x0 + xx
                        if pxx < VX0 or pxx >= VX1:
                            continue
                        pen = t[yy, xx]
                        if pen == 15:
                            continue
                        if ((1 << int(pri[py, pxx])) & pmask) == 0:
                            idx[py, pxx] = color * 16 + pen
                        pri[py, pxx] = 31
                code += 1
    rgb = palette_rgb(pal)[idx[VY0:VY1, VX0:VX1]]
    return rgb, idx, pri


def mame_pixels(d):
    a = np.frombuffer(open(os.path.join(d, "pixels.bin"), "rb").read(), dtype=np.uint8).reshape(240, 384, 4)
    return a[:, :, [2, 1, 0]]       # ARGB32 little-endian -> B,G,R,A bytes


def main():
    cmd = sys.argv[1]
    if cmd == "check":
        fails = 0
        for d in sys.argv[2:]:
            rgb, _, _ = render(*load_frame(d))
            m = mame_pixels(d)
            bad = np.any(rgb != m, axis=2)
            n = int(bad.sum())
            if n:
                ys, xs = np.nonzero(bad)
                print(f"FAIL {os.path.basename(d)}: {n} pixels differ, first at x={xs[0]} y={ys[0]} ref={rgb[ys[0], xs[0]]} mame={m[ys[0], xs[0]]}")
                fails += 1
            else:
                print(f"PASS {os.path.basename(d)}")
        print(f"REFRENDER {len(sys.argv) - 2 - fails}/{len(sys.argv) - 2} frames pixel-exact")
        return 1 if fails else 0
    if cmd == "png":
        from PIL import Image
        d, out = sys.argv[2], sys.argv[3]
        rgb, _, _ = render(*load_frame(d))
        Image.fromarray(rgb).save(out)
        if os.path.exists(os.path.join(d, "pixels.bin")):
            Image.fromarray(np.ascontiguousarray(mame_pixels(d))).save(out.replace(".png", "_mame.png"))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
