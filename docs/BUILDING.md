# Building

## Requirements

* Intel Quartus Prime Lite **17.0** (the MiSTer standard; the `sys/` framework targets it).
* Windows PowerShell for `scripts/build.ps1` (or use the Quartus GUI).
* Python 3 only for regenerating MRAs (`scripts/romtool.py`).

## Compile

* GUI: open `RShark.qpf` and run *Processing > Start Compilation*.
* Command line: `powershell -ExecutionPolicy Bypass -File scripts\build.ps1`
  (optionally `-QuartusBin <path to quartus\bin64>`). The script waits until no other Quartus job is
  running on the machine, runs the full flow, and writes `build/quartus.log` and
  `build/build-summary.txt` (resources, timing per clock, errors).

Either way the post-flow script `scripts/release_rbf.tcl` copies `output_files/RShark.rbf` to
`Releases/RShark_YYYYMMDD.rbf`. The MRAs name the core without the date (`<rbf>RShark</rbf>`);
MiSTer loads the newest dated file in `_Arcade/cores/`.

A clean build takes roughly 20-25 minutes. Check the timing summary: every setup and hold slack must
be positive (core clock `emu|pll...general[0]` 94.37 MHz, sound clock `general[1]` 47.19 MHz).

## MRAs

The MRAs are generated, not hand-written:

```
python scripts/romtool.py mra --game rshark      # also: superx, rsharka, superxm
python scripts/romtool.py mracheck --game rshark --zip <path>/rshark.zip
```

`mracheck` rebuilds the ROM stream by interpreting the MRA XML and compares it with the layout the
core expects (needs the ROM zips; nothing is written to the repository). The stream format is
described in [MRA_FORMAT.md](MRA_FORMAT.md).
