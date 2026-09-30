#!/usr/bin/env python3
"""Compare FPGA system-simulation frames (sim/tb/m15_system_tb.sv dumps) with MAME.

Mapping (docs/VIDEO.md "Register timing", docs/MAME_REFERENCE.md): MAME frame_done(N) happens at
the vblank begin at t = (N+1) * frame period; the FPGA's dbg_frames counts vblank begins, so FPGA
vblank c == MAME frame_done(c-1). At that vblank the FPGA latches the tilemap registers and copies
sprite RAM, and then displays one frame with them. The expected FPGA frame c is therefore MAME's
state captured at frame_done(c-1): regs.txt, palette.bin and spr_live.bin of local/frames_seq/f(c-1).
(The palette is live in the FPGA; frames where the game rewrites it mid-frame can differ.)

  syscheck.py [--sim build/sim/frames] [--mame local/frames_seq] [--png DIR]
"""
import argparse, glob, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import refrender as R


def expected(mdir):
    pal, _, regs, ctrl = R.load_frame(mdir)
    spr = np.frombuffer(open(os.path.join(mdir, "spr_live.bin"), "rb").read(), dtype=">u2").astype(np.int64)
    rgb, _, _ = R.render(pal, spr, regs, ctrl)
    return rgb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", default="build/sim/frames")
    ap.add_argument("--mame", default="local/frames_seq")
    ap.add_argument("--png", default=None)
    a = ap.parse_args()
    files = sorted(glob.glob(os.path.join(a.sim, "c*.rgb")))
    if not files:
        print("FAIL SYSCHECK: no frames in", a.sim)
        return 1
    fails = 0
    for f in files:
        c = int(os.path.basename(f)[1:6])
        raw = np.frombuffer(open(f, "rb").read(), dtype=np.uint8)
        if raw.size != 384 * 240 * 3:
            print(f"FAIL c{c:05d}: incomplete dump ({raw.size} bytes)")
            fails += 1
            continue
        got = raw.reshape(240, 384, 3)
        mdir = os.path.join(a.mame, f"f{c - 1:05d}")
        if not os.path.isdir(mdir):
            print(f"SKIP c{c:05d}: no MAME capture {mdir}")
            continue
        exp = expected(mdir)
        bad = np.any(got != exp, axis=2)
        n = int(bad.sum())
        if a.png:
            from PIL import Image
            os.makedirs(a.png, exist_ok=True)
            Image.fromarray(np.concatenate([got, exp], axis=1)).save(os.path.join(a.png, f"c{c:05d}.png"))
        if n:
            ys, xs = np.nonzero(bad)
            print(f"FAIL c{c:05d}: {n} pixels differ, first x={xs[0]} y={ys[0]} fpga={got[ys[0], xs[0]]} ref={exp[ys[0], xs[0]]}")
            fails += 1
        else:
            print(f"PASS c{c:05d}: pixel-exact vs MAME frame_done({c - 1})")
    print(f"SYSCHECK {len(files) - fails}/{len(files)} frames pixel-exact")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
