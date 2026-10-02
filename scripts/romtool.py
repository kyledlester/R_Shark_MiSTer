#!/usr/bin/env python3
"""R-Shark / Super-X ROM tooling (no ROM data is ever written into the repository).

Reference: MAME 0.289 src/mame/dooyong/dooyong.cpp ROM_START( rshark ) / ROM_START( superx )
(docs/MRA_FORMAT.md). Both games use the same ioctl stream layout and SDRAM image; only the source
ROM files (and how MAME loads them) differ. The game is selected by a one-byte ioctl index-1
download (0 = R-Shark, 1 = Super-X) sent by each MRA.

  romtool.py verify   [--game G] [--zip Z]           CRC/size check against MAME 0.289
  romtool.py regions  [--game G] [--zip Z] [--out D] MAME regions, byte-exact (maincpu.bin, ...)
  romtool.py stream   [--game G] [--zip Z] [--out D] the ioctl index-0 stream the MRA delivers
  romtool.py images   [--game G] [--zip Z] [--out D] simulation images (SDRAM word image, BRAM hex)
  romtool.py mra      [--game G] [--out FILE]        write the MRA
  romtool.py mracheck [--game G] [--zip Z] [--mra F] rebuild the stream by interpreting the MRA

G = rshark (default), rsharka, superx or superxm (clones fall back to the parent zip for shared files). Default zip: C:/Users/klest/Downloads/mame/roms/<set>.zip.
Default output dir: local/ (rshark), local/superx/ (superx).
"""
import argparse, os, sys, zipfile, zlib, xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROMDIR = os.environ.get("RSHARK_ROMDIR", "C:/Users/klest/Downloads/mame/roms")

# ------------------------------------------------------------------------------------ game data
# ROMS: name -> (size, crc32) from `mame -listroms <set>` (0.289).
# REGIONS: name -> (size, [(rom, offset, kind)]); kind "b16" = ROM_LOAD16_BYTE (every 2nd byte),
# "ws" = ROM_LOAD16_WORD_SWAP (file bytes swapped pairwise into the big-endian region),
# "load" = ROM_LOAD.
GAMES = {
    "rshark": dict(
        game_id=0,
        name="R-Shark (set 1)", year="1995", manufacturer="Dooyong",
        mra="R-Shark (set 1).mra",
        roms={
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
        },
        regions={
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
        },
        dips=[
            # (bits, name, ids): bit numbers in the 16-bit DSW word (SWA = bits 0-7, SWB = 8-15),
            # ids for bit values 0..2^n-1 as MAME defines them (active-low port values).
            ("0", "Service Mode", "On,Off"),
            ("1", "Coin Type", "B,A"),
            ("2", "Demo Sounds", "Off,On"),
            ("3", "Flip Screen", "On,Off"),
            ("4,5", "Coin A (type A/B)", "2C3C/4C1C,2C1C/3C1C,1C2C/2C1C,1C1C/1C1C"),
            ("6,7", "Coin B (type A/B)", "2C3C/1C6C,2C1C/1C4C,1C2C/1C3C,1C1C/1C2C"),
            ("8,9", "Lives", "1,4,2,3"),
            ("10,11", "Difficulty", "Hardest,Hard,Easy,Normal"),
            ("15", "Allow Continue", "No,Yes"),
        ],
    ),
    "superx": dict(
        game_id=1,
        name="Super-X (NTC)", year="1994", manufacturer="Dooyong (NTC license)",
        mra="Super-X (NTC).mra",
        roms={
            "2.3m":         (0x20000, 0xbe7aebe7), "3.3l": (0x20000, 0xdc4a25fc),
            "1.5u":         (0x10000, 0x6894ce05),
            "spxo-m05.10m": (0x200000, 0x9120dd84),
            "spxb-m04.8f":  (0x100000, 0x91a7ac6e),
            "spxb-m03.8j":  (0x100000, 0x8b42861b),
            "spxb-m02.8a":  (0x100000, 0x21b8db78),
            "spxb-m01.8c":  (0x100000, 0x60c69129),
            "spxb-ms3.10f": (0x20000, 0x8bf8c77d), "spxb-ms4.10j": (0x20000, 0xd418a900),
            "spxb-ms2.10a": (0x20000, 0x5ec87adf), "spxb-ms1.10c": (0x20000, 0x40b4fe6c),
            "4.7v":         (0x20000, 0x434290b5), "5.7u": (0x20000, 0xebe6abb4),
        },
        regions={
            "maincpu":  (0x40000,  [("2.3m", 0, "b16"), ("3.3l", 1, "b16")]),
            "audiocpu": (0x10000,  [("1.5u", 0, "load")]),
            "sprite":   (0x200000, [("spxo-m05.10m", 0, "ws")]),
            "fg1":      (0x100000, [("spxb-m04.8f", 0, "ws")]),
            "fg0":      (0x100000, [("spxb-m03.8j", 0, "ws")]),
            "bg1":      (0x100000, [("spxb-m02.8a", 0, "ws")]),
            "bg0":      (0x100000, [("spxb-m01.8c", 0, "ws")]),
            "tmap_hi":  (0x80000,  [("spxb-ms3.10f", 0, "load"), ("spxb-ms4.10j", 0x20000, "load"),
                                    ("spxb-ms2.10a", 0x40000, "load"), ("spxb-ms1.10c", 0x60000, "load")]),
            "oki":      (0x40000,  [("4.7v", 0, "load"), ("5.7u", 0x20000, "load")]),
        },
        dips=[
            # INPUT_PORTS_START( superx ): dooyongm68_generic with SWA:1 redefined as "Unknown"
            # (documented as service mode, "never had any effect in game" per MAME).
            ("0", "Unknown (SWA:1)", "On,Off"),
            ("1", "Coin Type", "B,A"),
            ("2", "Demo Sounds", "Off,On"),
            ("3", "Flip Screen", "On,Off"),
            ("4,5", "Coin A (type A/B)", "2C3C/4C1C,2C1C/3C1C,1C2C/2C1C,1C1C/1C1C"),
            ("6,7", "Coin B (type A/B)", "2C3C/1C6C,2C1C/1C4C,1C2C/1C3C,1C1C/1C1C"),
            ("8,9", "Lives", "1,4,2,3"),
            ("10,11", "Difficulty", "Hardest,Hard,Easy,Normal"),
            ("15", "Allow Continue", "No,Yes"),
        ],
    ),
}

# Clones (MAME 0.289 -listxml): same board and map as their parent; only the files differ.
# "zips" lists where the MRA (and this tool) look for files: clone zip first, then the parent's,
# so both split and merged/non-merged ROM sets work.
import copy as _copy
GAMES["rsharka"] = dict(
    _copy.deepcopy(GAMES["rshark"]), parent="rshark",
    name="R-Shark (set 2)", mra="_alternatives/_R-Shark/R-Shark (set 2).mra",
    # files shared with rshark use MAME's merge names (as in split and merged sets)
    roms={
        "9.1":   (0x20000, 0xdafa38df), "8.2": (0x20000, 0x31bd7b90),
        "1.15":  (0x10000, 0x8be49bc1),
        "rse4.bin":  (0x80000, 0xb857e411), "rse5.bin": (0x80000, 0x7822d77a),
        "rse6.bin":  (0x80000, 0x80215c52), "rse7.bin": (0x80000, 0xbd28bbdc),
        "11.13": (0x80000, 0xb5912b55), "10.12": (0x80000, 0x345456af),
        "rse15.bin": (0x80000, 0xd188134d), "rse14.bin": (0x80000, 0x0ef637a7),
        "17.7":  (0x80000, 0xf47e164c), "16.6": (0x80000, 0x52fae286),
        "21.4":  (0x80000, 0x0b7b6cc4), "20.3": (0x80000, 0x31f218bf),
        "12.14": (0x20000, 0xd5cab49c), "rse13.bin": (0x20000, 0x323d4df6),
        "18.8":  (0x20000, 0x5e0091a1), "19.5": (0x20000, 0xe5ae7112),
        "2.16":  (0x20000, 0xdbe5632b), "3.17": (0x20000, 0x0dcd3ffb),
    },
    regions={
        "maincpu":  (0x40000,  [("9.1", 0, "b16"), ("8.2", 1, "b16")]),
        "audiocpu": (0x10000,  [("1.15", 0, "load")]),
        "sprite":   (0x200000, [("rse4.bin", 0, "b16"), ("rse5.bin", 1, "b16"),
                                ("rse6.bin", 0x100000, "b16"), ("rse7.bin", 0x100001, "b16")]),
        "fg1":      (0x100000, [("11.13", 0, "b16"), ("10.12", 1, "b16")]),
        "fg0":      (0x100000, [("rse15.bin", 0, "b16"), ("rse14.bin", 1, "b16")]),
        "bg1":      (0x100000, [("17.7", 0, "b16"), ("16.6", 1, "b16")]),
        "bg0":      (0x100000, [("21.4", 0, "b16"), ("20.3", 1, "b16")]),
        "tmap_hi":  (0x80000,  [("12.14", 0, "load"), ("rse13.bin", 0x20000, "load"),
                                ("18.8", 0x40000, "load"), ("19.5", 0x60000, "load")]),
        "oki":      (0x40000,  [("2.16", 0, "load"), ("3.17", 0x20000, "load")]),
    })
GAMES["superxm"] = dict(
    _copy.deepcopy(GAMES["superx"]), parent="superx",
    name="Super-X (Mitchell)", manufacturer="Dooyong (Mitchell license)", mra="_alternatives/_Super-X/Super-X (Mitchell).mra")
_sx = GAMES["superxm"]
for _old, _new, _crc in (("2.3m", "2_m.3m", 0x41c50aac), ("3.3l", "3_m.3l", 0x6738b703), ("1.5u", "1_m.5u", 0x319fa632)):
    _sx["roms"] = {(_new if k == _old else k): ((v[0], _crc) if k == _old else v) for k, v in _sx["roms"].items()}
    for _r, (_size, _loads) in _sx["regions"].items():
        _sx["regions"][_r] = (_size, [(_new if f == _old else f, o, k) for f, o, k in _loads])

# ioctl index-0 stream layout (docs/MRA_FORMAT.md), shared by both games. Word regions arrive
# big-endian per 16-bit word (ioctl_dout[15:8] = MAME even byte); byte regions arrive in order
# (ioctl_dout[7:0] = even byte).   (name, stream offset, length, source region, source offset, word?)
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
# regions are expanded to 2 words per tilemap entry (docs/MRA_FORMAT.md "SDRAM image").
SDRAM_MAP_BASE = {"bg0": 0x600000, "bg1": 0x680000, "fg0": 0x700000, "fg1": 0x780000}
SDRAM_OKI_BASE = 0x800000
SDRAM_LEN = 0x840000
TMAP_HI_LAYER = ["fg1", "fg0", "bg1", "bg0"]   # tmap_hi offset / 0x20000 (MAME colorrom offsets)


def load_zip(g, path):
    """Read the set's files from `path`, falling back to the parent set's zip (split sets)."""
    paths = [path]
    if g.get("parent"):
        paths.append(os.path.join(os.path.dirname(path), g["parent"] + ".zip"))
    zips = [zipfile.ZipFile(p) for p in paths if os.path.exists(p)]
    if not zips:
        raise SystemExit(f"missing {path}")
    data = {}
    for n in g["roms"]:
        for z in zips:
            names = {i.filename.lower(): i.filename for i in z.infolist()}
            if n in names:
                data[n] = z.read(names[n])
                break
        else:
            raise SystemExit(f"missing {n} in {' / '.join(paths)}")
    return data


def verify(g, data):
    ok = True
    for n, (size, crc) in g["roms"].items():
        d = data[n]
        c = zlib.crc32(d) & 0xffffffff
        good = len(d) == size and c == crc
        ok &= good
        print(f"{'OK ' if good else 'BAD'} {n:13s} size {len(d):#08x} crc {c:08x} (expect {size:#08x} {crc:08x})")
    return ok


def build_regions(g, data):
    regs = {}
    for name, (size, loads) in g["regions"].items():
        r = bytearray(size)
        for rom, off, kind in loads:
            d = data[rom]
            if kind == "b16":
                r[off:off + 2 * len(d):2] = d
            elif kind == "ws":
                r[off:off + len(d):2] = d[1::2]
                r[off + 1:off + len(d):2] = d[0::2]
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
def region_parts(g, src, length):
    """MRA elements delivering the first `length` bytes of word region `src` in stream order
    (stream byte 2k = MAME odd byte, 2k+1 = MAME even byte)."""
    loads = g["regions"][src][1]
    full = length == g["regions"][src][0]
    out = []
    if all(k == "ws" for _, _, k in loads):
        # ROM_LOAD16_WORD_SWAP: region even byte = file byte 2k+1, odd = file byte 2k, so the file's
        # own byte order is exactly the stream order - the file is sent as is.
        for rom, off, kind in loads:
            ln = "" if full else f' offset="0" length="0x{length:X}"'
            out.append(f'        <part name="{rom}" crc="{g["roms"][rom][1]:08x}"{ln}/>')
        return out
    # ROM_LOAD16_BYTE pairs: even-offset ROM -> MAME even byte (map "10"), odd-offset ROM -> "01"
    pairs = {}
    for rom, off, kind in loads:
        assert kind == "b16"
        pairs.setdefault(off & ~1, [None, None])[off & 1] = rom
    for base in sorted(pairs):
        even, odd = pairs[base]
        out.append('        <interleave output="16">')
        ln = "" if full else f' offset="0" length="0x{length // 2:X}"'
        out.append(f'            <part name="{even}" crc="{g["roms"][even][1]:08x}"{ln} map="10"/>')
        out.append(f'            <part name="{odd}" crc="{g["roms"][odd][1]:08x}"{ln} map="01"/>')
        out.append("        </interleave>")
    return out


def make_mra(key):
    g = GAMES[key]
    L = []
    a = L.append
    a("<!--")
    a(f"  {g['name']} - {g['manufacturer']} {g['year']} - MRA for the RShark MiSTer core.")
    a(f"  MAME set {key} (MAME 0.289 dooyong.cpp). No ROM data is embedded in this file.")
    a("  Generated by scripts/romtool.py mra ; layout documented in docs/MRA_FORMAT.md.")
    a("")
    a(f"  ioctl index 1: game select byte {g['game_id']:02X} (00 = R-Shark map, 01 = Super-X map).")
    a("  ioctl index 0 stream (hps_io WIDE=1; 16-bit regions arrive as big-endian 68000 words):")
    for name, soff, length, src, srcoff, word in STREAM:
        a(f"    {soff:06X}-{soff + length - 1:06X}  {name:9s} MAME region '{src}' +{srcoff:#x} ({'word' if word else 'byte'})")
    a("")
    a("  DIP switches (index 254): bytes 0/1 = DSW bits 7-0 (SWA) / 15-8 (SWB), MAME port values")
    a("  (active low). Default FF,FF = MAME defaults.")
    a("-->")
    a("<misterromdescription>")
    a(f"    <name>{g['name']}</name>")
    a(f"    <setname>{key}</setname>")
    if g.get("parent"):
        a(f"    <parent>{g['parent']}</parent>")
    a("    <rbf>RShark</rbf>")
    a("    <mameversion>0289</mameversion>")
    a(f"    <year>{g['year']}</year>")
    a(f"    <manufacturer>{g['manufacturer']}</manufacturer>")
    a("    <category>Shooter</category>")
    a("    <players>2</players>")
    a("    <joystick>8-way</joystick>")
    a("    <rotation>vertical (ccw)</rotation>")
    a('    <buttons names="Shot,Bomb,Button 3,Button 4,Start,Coin,Service,Pause" default="A,B,X,Y,Start,Select,R,L"/>')
    a("")
    a('    <switches default="FF,FF" base="16">')
    for bits, name, ids in g["dips"]:
        a(f'        <dip bits="{bits}" name="{name}" ids="{ids}"/>')
    a("    </switches>")
    a("")
    a('    <rom index="1">')
    a(f"        <part>{g['game_id']:02X}</part>")
    a("    </rom>")
    zips = f"{key}.zip" + (f"|{g['parent']}.zip" if g.get("parent") else "")
    a(f'    <rom index="0" zip="{zips}" md5="None">')
    for name, soff, length, src, srcoff, word in STREAM:
        a(f"        <!-- {soff:06X} {name} -->")
        if word:
            L.extend(region_parts(g, src, length))
        else:
            for rom, off, kind in g["regions"][src][1]:
                a(f'        <part name="{rom}" crc="{g["roms"][rom][1]:08x}"/>')
    a("    </rom>")
    a("</misterromdescription>")
    return "\n".join(L) + "\n"


def interpret_mra(mra_path, data):
    """Independent MRA interpreter (MiSTer semantics: map digit i from the right = output byte i,
    digit value = input byte number (1-based), 0 = not written). Returns {index: bytes}."""
    root = ET.parse(mra_path).getroot()
    streams = {}

    def part_bytes(p):
        if p.get("repeat"):
            return bytes.fromhex(p.text.strip()) * int(p.get("repeat"), 0)
        if p.get("name") is None:
            return bytes.fromhex(p.text.strip())
        d = data[p.get("name")]
        off = int(p.get("offset", "0"), 0)
        ln = int(p.get("length", str(len(d) - off)), 0)
        return d[off:off + ln]

    for rom in root.findall("rom"):
        out = bytearray()
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
        streams[int(rom.get("index"))] = bytes(out)
    return streams


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("--game", default="rshark", choices=sorted(GAMES))
    ap.add_argument("--zip", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--mra", default=None)
    a = ap.parse_args()
    g = GAMES[a.game]
    mra = a.mra or os.path.join(ROOT, "MRA", g["mra"])
    if a.cmd == "mra":
        path = a.out or mra
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", newline="\n").write(make_mra(a.game))
        print("wrote", path)
        return 0
    data = load_zip(g, a.zip or os.path.join(ROMDIR, a.game + ".zip"))
    out = a.out or (os.path.join(ROOT, "local") if a.game == "rshark" else os.path.join(ROOT, "local", a.game))
    os.makedirs(out, exist_ok=True)
    if a.cmd == "verify":
        return 0 if verify(g, data) else 1
    if not verify(g, data):
        return 1
    regs = build_regions(g, data)
    if a.cmd == "regions":
        d = os.path.join(out, "regions")
        os.makedirs(d, exist_ok=True)
        for n, r in regs.items():
            open(os.path.join(d, n + ".bin"), "wb").write(r)
        print("regions written to", d)
    elif a.cmd == "stream":
        s = build_stream(regs)
        open(os.path.join(out, a.game + ".rom"), "wb").write(s)
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
        got = interpret_mra(mra, data)
        want = build_stream(regs)
        sel = got.get(1, b"")
        if sel != bytes([g["game_id"]]):
            print(f"FAIL mracheck: index-1 game select {sel.hex()} expected {g['game_id']:02x}")
            return 1
        s0 = got.get(0, b"")
        if s0 != want:
            n = min(len(s0), len(want))
            first = next((i for i in range(n) if s0[i] != want[i]), n)
            print(f"FAIL mracheck: len {len(s0):#x} vs {len(want):#x}, first difference at {first:#x}")
            return 1
        print(f"PASS mracheck {a.game}: MRA stream == layout stream ({len(s0):#x} bytes), game select {sel.hex()}")
    else:
        ap.error("unknown command")
    return 0


if __name__ == "__main__":
    sys.exit(main())
