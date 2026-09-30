#!/usr/bin/env python3
"""R-Shark ROM tooling (no ROM data is ever written into the repository).

Reference: MAME 0.289 src/mame/dooyong/dooyong.cpp ROM_START( rshark ) (docs/ROM_LAYOUT.md).

  romtool.py verify   [--zip Z]          CRC/size check against the MAME 0.289 definition
  romtool.py regions  [--zip Z] [--out D] MAME regions, byte-exact (maincpu.bin, sprite.bin, ...)
  romtool.py stream   [--zip Z] [--out D] the ioctl index-0 stream the MRA delivers (rshark.rom)
  romtool.py images   [--zip Z] [--out D] simulation images: SDRAM word image + BRAM hex files
  romtool.py mra      [--out FILE]        write the MRA
  romtool.py mracheck [--zip Z] [--mra F] rebuild the stream by interpreting the MRA XML and compare

Default zip: C:/Users/klest/Downloads/mame/roms/rshark.zip ; default output dir: local/
"""
import argparse, os, sys, zipfile, zlib, xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ZIP = os.environ.get("RSHARK_ZIP", "C:/Users/klest/Downloads/mame/roms/rshark.zip")
DEFAULT_OUT = os.path.join(ROOT, "local")

# name -> (size, crc32) from `mame -listroms rshark` (0.289)
ROMS = {
    "rspl00.bin": (0x20000, 0x40356b9d), "rspu00.bin": (0x20000, 0x6635c668),
    "rse3.bin":   (0x10000, 0x03c8fd17),
    "rse4.bin":   (0x80000, 0xb857e411), "rse5.bin": (0x80000, 0x7822d77a),
    "rse6.bin":   (0x80000, 0x80215c52), "rse7.bin": (0x80000, 0xbd28bbdc),
    "rse11.bin":  (0x80000, 0x8a0c572f), "rse10.bin": (0x80000, 0x139d5947),
    "rse15.bin":  (0x80000, 0xd188134d), "rse14.bin": (0x80000, 0x0ef637a7),
    "rse17.bin":  (0x80000, 0x7ff0f3c7), "rse16.bin": (0x80000, 0xc176c8bc),
    "rse21.bin":  (0x80000, 0x2ea665af), "rse20.bin": (0x80000, 0xef93e3ac),
    "rse12.bin":  (0x20000, 0xfadbf947), "rse13.bin": (0x20000, 0x323d4df6),
    "rse18.bin":  (0x20000, 0xe00c9171), "rse19.bin": (0x20000, 0xd214d1d0),
    "rse1.bin":   (0x20000, 0x0291166f), "rse2.bin": (0x20000, 0x5a26ee72),
}

# MAME regions: name -> (size, [(rom, offset, kind)]) ; kind "b16" = ROM_LOAD16_BYTE (every 2nd byte)
REGIONS = {
    "maincpu":  (0x40000,  [("rspl00.bin", 0, "b16"), ("rspu00.bin", 1, "b16")]),
    "audiocpu": (0x10000,  [("rse3.bin", 0, "load")]),
    "sprite":   (0x200000, [("rse4.bin", 0, "b16"), ("rse5.bin", 1, "b16"),
                            ("rse6.bin", 0x100000, "b16"), ("rse7.bin", 0x100001, "b16")]),
    "fg1":      (0x100000, [("rse11.bin", 0, "b16"), ("rse10.bin", 1, "b16")]),
    "fg0":      (0x100000, [("rse15.bin", 0, "b16"), ("rse14.bin", 1, "b16")]),
    "bg1":      (0x100000, [("rse17.bin", 0, "b16"), ("rse16.bin", 1, "b16")]),
    "bg0":      (0x100000, [("rse21.bin", 0, "b16"), ("rse20.bin", 1, "b16")]),
    "tmap_hi":  (0x80000,  [("rse12.bin", 0, "load"), ("rse13.bin", 0x20000, "load"),
                            ("rse18.bin", 0x40000, "load"), ("rse19.bin", 0x60000, "load")]),
    "oki":      (0x40000,  [("rse1.bin", 0, "load"), ("rse2.bin", 0x20000, "load")]),
}

# ioctl index-0 stream layout (docs/ROM_LAYOUT.md). Word regions arrive big-endian per 16-bit word
# (ioctl_dout[15:8] = MAME even byte) ; byte regions arrive in order (ioctl_dout[7:0] = even byte).
#   (name, stream offset, length, source region, source offset, word?)
STREAM = [
    ("sprite",   0x000000, 0x200000, "sprite",   0, True),
    ("bg0",      0x200000, 0x100000, "bg0",      0, True),
    ("bg1",      0x300000, 0x100000, "bg1",      0, True),
    ("fg0",      0x400000, 0x100000, "fg0",      0, True),
    ("fg1",      0x500000, 0x100000, "fg1",      0, True),
    ("bg0map",   0x600000, 0x040000, "bg0",      0, True),
    ("bg1map",   0x640000, 0x040000, "bg1",      0, True),
    ("fg0map",   0x680000, 0x040000, "fg0",      0, True),
    ("fg1map",   0x6C0000, 0x040000, "fg1",      0, True),
    ("tmap_hi",  0x700000, 0x080000, "tmap_hi",  0, False),
    ("oki",      0x780000, 0x040000, "oki",      0, False),
    ("maincpu",  0x7C0000, 0x040000, "maincpu",  0, True),
    ("audiocpu", 0x800000, 0x010000, "audiocpu", 0, False),
]
STREAM_LEN = 0x810000

# SDRAM byte addresses (32 MB module). Graphics regions keep the stream address; map+colour
# regions are expanded to 2 words per tilemap entry (docs/ROM_LAYOUT.md "SDRAM image").
SDRAM_MAP_BASE = {"bg0": 0x600000, "bg1": 0x680000, "fg0": 0x700000, "fg1": 0x780000}
SDRAM_OKI_BASE = 0x800000
SDRAM_LEN = 0x840000
TMAP_HI_LAYER = ["fg1", "fg0", "bg1", "bg0"]   # tmap_hi offset / 0x20000 (MAME colorrom offsets)


def load_zip(path):
    z = zipfile.ZipFile(path)
    names = {i.filename.lower(): i.filename for i in z.infolist()}
    data = {}
    for n in ROMS:
        if n not in names:
            raise SystemExit(f"missing {n} in {path}")
        data[n] = z.read(names[n])
    return data


def verify(data):
    ok = True
    for n, (size, crc) in ROMS.items():
        d = data[n]
        c = zlib.crc32(d) & 0xffffffff
        good = len(d) == size and c == crc
        ok &= good
        print(f"{'OK ' if good else 'BAD'} {n:11s} size {len(d):#08x} crc {c:08x} (expect {size:#08x} {crc:08x})")
    return ok


def build_regions(data):
    regs = {}
    for name, (size, loads) in REGIONS.items():
        r = bytearray(size)
        for rom, off, kind in loads:
            d = data[rom]
            if kind == "b16":
                r[off:off + 2 * len(d):2] = d
            else:
                r[off:off + len(d)] = d
        regs[name] = bytes(r)
    return regs


def build_stream(regs):
    s = bytearray(STREAM_LEN)
    for name, soff, length, src, srcoff, word in STREAM:
        d = regs[src][srcoff:srcoff + length]
        if word:   # stream byte 2k = MAME odd byte (ioctl_dout[7:0]), 2k+1 = MAME even byte
            b = bytearray(length)
            b[0::2] = d[1::2]
            b[1::2] = d[0::2]
            d = bytes(b)
        s[soff:soff + length] = d
    return bytes(s)


def gfx_permute_word(w):
    """Word address inside a 128-byte tile: MAME {h, r[3:0], b} -> SDRAM {r[3:0], h, b}.
    w = byte_offset >> 1 ; bit5 = h (right half), bits4..1 = pixel row, bit0 = word in half-row."""
    return (w & ~0x3f) | (((w >> 1) & 0xf) << 2) | (((w >> 5) & 1) << 1) | (w & 1)


def map_entry_pos(i):
    """Tilemap entry index i = col*32 + row (MAME TILEMAP_SCAN_COLS, 32 rows) -> row*4096 + col."""
    return ((i & 31) << 12) | (i >> 5)


def build_sdram(regs):
    """16-bit word image (list of ints) exactly as the loader writes it."""
    mem = [0] * (SDRAM_LEN // 2)
    for name, base in (("sprite", 0x000000), ("bg0", 0x200000), ("bg1", 0x300000),
                       ("fg0", 0x400000), ("fg1", 0x500000)):
        r = regs[name]
        for w in range(len(r) // 2):
            mem[(base >> 1) + gfx_permute_word(w)] = (r[2 * w] << 8) | r[2 * w + 1]
    for layer, base in SDRAM_MAP_BASE.items():
        r = regs[layer]
        for i in range(0x20000):
            mem[(base >> 1) + 2 * map_entry_pos(i)] = (r[2 * i] << 8) | r[2 * i + 1]
    th = regs["tmap_hi"]
    for t in range(len(th)):
        layer = TMAP_HI_LAYER[t >> 17]
        mem[(SDRAM_MAP_BASE[layer] >> 1) + 2 * map_entry_pos(t & 0x1ffff) + 1] = th[t]
    oki = regs["oki"]
    for k in range(len(oki) // 2):
        mem[(SDRAM_OKI_BASE >> 1) + k] = (oki[2 * k + 1] << 8) | oki[2 * k]   # little-endian pair
    return mem


def write_hex16(path, words):
    with open(path, "w") as f:
        f.write("\n".join(f"{w:04x}" for w in words))
        f.write("\n")


def write_hex8(path, data):
    with open(path, "w") as f:
        f.write("\n".join(f"{b:02x}" for b in data))
        f.write("\n")


# ---------------------------------------------------------------------------------------- MRA
ROMSRC = {  # stream entry -> (even-byte rom, odd-byte rom) for word regions / [roms] for byte regions
    "sprite": [("rse4.bin", "rse5.bin"), ("rse6.bin", "rse7.bin")],
    "bg0": [("rse21.bin", "rse20.bin")], "bg1": [("rse17.bin", "rse16.bin")],
    "fg0": [("rse15.bin", "rse14.bin")], "fg1": [("rse11.bin", "rse10.bin")],
    "maincpu": [("rspl00.bin", "rspu00.bin")],
}

MRA_DIPS = [
    # (bits, name, ids) ; bit numbers in the 16-bit DSW word (SWA = bits 0-7, SWB = bits 8-15),
    # ids listed for bit values 0..2^n-1 as MAME defines them (active-low port values).
    ("0", "Service Mode", "On,Off"),
    ("1", "Coin Type", "B,A"),
    ("2", "Demo Sounds", "Off,On"),
    ("3", "Flip Screen", "On,Off"),
    ("4,5", "Coin A (type A/B)", "2C3C/4C1C,2C1C/3C1C,1C2C/2C1C,1C1C/1C1C"),
    ("6,7", "Coin B (type A/B)", "2C3C/1C6C,2C1C/1C4C,1C2C/1C3C,1C1C/1C2C"),
    ("8,9", "Lives", "1,4,2,3"),
    ("10,11", "Difficulty", "Hardest,Hard,Easy,Normal"),
    ("15", "Allow Continue", "No,Yes"),
]


def make_mra():
    L = []
    a = L.append
    a("<!--")
    a("  R-Shark (set 1) - Dooyong 1995 - MRA for the RShark MiSTer core.")
    a("  MAME set rshark (MAME 0.289 dooyong.cpp). No ROM data is embedded in this file.")
    a("  Generated by scripts/romtool.py mra ; layout documented in docs/ROM_LAYOUT.md.")
    a("")
    a("  ioctl index 0 stream (hps_io WIDE=1; 16-bit regions arrive as big-endian 68000 words):")
    for name, soff, length, src, srcoff, word in STREAM:
        a(f"    {soff:06X}-{soff + length - 1:06X}  {name:9s} MAME region '{src}' +{srcoff:#x} ({'word' if word else 'byte'})")
    a("")
    a("  DIP switches (index 254): bytes 0/1 = DSW bits 7-0 (SWA) / 15-8 (SWB), MAME port values")
    a("  (active low). Default FF,FF = MAME defaults.")
    a("-->")
    a("<misterromdescription>")
    a("    <name>R-Shark (set 1)</name>")
    a("    <setname>rshark</setname>")
    a("    <rbf>RShark</rbf>")
    a("    <mameversion>0289</mameversion>")
    a("    <year>1995</year>")
    a("    <manufacturer>Dooyong</manufacturer>")
    a("    <category>Shooter</category>")
    a("    <players>2</players>")
    a("    <joystick>8-way</joystick>")
    a("    <rotation>vertical (ccw)</rotation>")
    a('    <buttons names="Shot,Bomb,Button 3,Button 4,Start,Coin,Service,Pause" default="A,B,X,Y,Start,Select,R,L"/>')
    a("")
    a('    <switches default="FF,FF" base="16">')
    for bits, name, ids in MRA_DIPS:
        a(f'        <dip bits="{bits}" name="{name}" ids="{ids}"/>')
    a("    </switches>")
    a("")
    a('    <rom index="0" zip="rshark.zip" md5="None">')
    for name, soff, length, src, srcoff, word in STREAM:
        a(f"        <!-- {soff:06X} {name} -->")
        if word:
            full = length == REGIONS[src][0]
            for even, odd in ROMSRC[src]:
                a('        <interleave output="16">')
                ln = "" if full else f' offset="0" length="0x{length // 2:X}"'
                a(f'            <part name="{even}" crc="{ROMS[even][1]:08x}"{ln} map="10"/>')
                a(f'            <part name="{odd}" crc="{ROMS[odd][1]:08x}"{ln} map="01"/>')
                a("        </interleave>")
        else:
            for rom, off, kind in REGIONS[src][1]:
                a(f'        <part name="{rom}" crc="{ROMS[rom][1]:08x}"/>')
    a("    </rom>")
    a("</misterromdescription>")
    return "\n".join(L) + "\n"


def interpret_mra(mra_path, data):
    """Independent MRA interpreter (MiSTer semantics: map digit i from the right = output byte i,
    digit value = input byte number (1-based), 0 = not written)."""
    root = ET.parse(mra_path).getroot()
    rom = root.find("rom")
    out = bytearray()

    def part_bytes(p):
        if p.get("repeat"):
            return bytes.fromhex(p.text.strip()) * int(p.get("repeat"), 0)
        d = data[p.get("name")]
        off = int(p.get("offset", "0"), 0)
        ln = int(p.get("length", str(len(d) - off)), 0)
        return d[off:off + ln]

    for el in rom:
        if el.tag == "part":
            out += part_bytes(el)
        elif el.tag == "interleave":
            width = int(el.get("output")) // 8
            parts = [(part_bytes(p), p.get("map")) for p in el.findall("part")]
            n = len(parts[0][0])
            block = bytearray(n * width)
            for d, m in parts:
                digits = [int(c) for c in reversed(m)]    # digits[i] -> output byte i
                inw = max(digits)
                for k in range(n // inw):
                    for i, dg in enumerate(digits):
                        if dg:
                            block[k * width + i] = d[k * inw + dg - 1]
            out += block
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("--zip", default=DEFAULT_ZIP)
    ap.add_argument("--out", default=None)
    ap.add_argument("--mra", default=os.path.join(ROOT, "mra", "R-Shark (set 1).mra"))
    a = ap.parse_args()
    if a.cmd == "mra":
        path = a.out or a.mra
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", newline="\n").write(make_mra())
        print("wrote", path)
        return 0
    data = load_zip(a.zip)
    out = a.out or DEFAULT_OUT
    os.makedirs(out, exist_ok=True)
    if a.cmd == "verify":
        return 0 if verify(data) else 1
    if not verify(data):
        return 1
    regs = build_regions(data)
    if a.cmd == "regions":
        d = os.path.join(out, "regions")
        os.makedirs(d, exist_ok=True)
        for n, r in regs.items():
            open(os.path.join(d, n + ".bin"), "wb").write(r)
        print("regions written to", d)
    elif a.cmd == "stream":
        s = build_stream(regs)
        open(os.path.join(out, "rshark.rom"), "wb").write(s)
        print(f"stream {len(s):#x} bytes crc {zlib.crc32(s) & 0xffffffff:08x}")
    elif a.cmd == "images":
        d = os.path.join(out, "sim")
        os.makedirs(d, exist_ok=True)
        mem = build_sdram(regs)
        with open(os.path.join(d, "sdram_be.bin"), "wb") as f:   # big-endian 16-bit words
            f.write(b"".join(w.to_bytes(2, "big") for w in mem))
        mc = regs["maincpu"]
        write_hex16(os.path.join(d, "maincpu.hex"), [(mc[2 * i] << 8) | mc[2 * i + 1] for i in range(len(mc) // 2)])
        write_hex8(os.path.join(d, "audiocpu.hex"), regs["audiocpu"])
        write_hex8(os.path.join(d, "oki.hex"), regs["oki"])
        print("simulation images written to", d)
    elif a.cmd == "mracheck":
        got = interpret_mra(a.mra, data)
        want = build_stream(regs)
        if got != want:
            n = min(len(got), len(want))
            first = next((i for i in range(n) if got[i] != want[i]), n)
            print(f"FAIL mracheck: len {len(got):#x} vs {len(want):#x}, first difference at {first:#x}")
            return 1
        print(f"PASS mracheck: MRA stream == layout stream ({len(got):#x} bytes)")
    else:
        ap.error("unknown command")
    return 0


if __name__ == "__main__":
    sys.exit(main())
