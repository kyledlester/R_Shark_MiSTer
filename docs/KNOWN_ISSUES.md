# Known issues and open questions

Unknowns are categorised: A = needed for CPU boot, B = for useful graphics, C = for gameplay,
D = accuracy item that can wait.

| # | Cat | Item | Status |
| --- | --- | --- | --- |
| 1 | D | PCB video timing (dot clock, totals, sync) unknown; MAME's 512x256@60 raster is used, sync placement is a CRT-friendly choice | open (M20) |
| 2 | D | Tilemap registers and palette latched at vblank (the games write them at line ~120-131). Real hardware behaviour unverified. Relative to MAME, scroll/palette appear together with the sprites of the same game tick | design decision, docs/VIDEO.md |
| 13 | D | A sprite entry rewritten within ~1 us of the vblank copy can land one frame later than in MAME (CPU timing differs from MAME's by < 1 us, see 6); seen once in 240 Super-X gameplay frames (one sprite, one frame) | expected |
| 12 | D | Super-X SWA:1 is labelled "Unknown (SWA:1)" as in MAME (board documentation calls it service mode; MAME notes it has no effect) | as MAME |
| 14 | C | CRT Adjust: turning it On made the OSD/picture disappear for good (owner, both games). Cause: the glue's vertical blank comes from the core's "next line" vblank, which was tied to 0, so the adjusted stream had no vertical blank and the scaler never saw a frame; separately, the H-Position limits were Neratte Chu's (455-dot raster) and a left shift past 3 steps put HSync inside the picture (no picture at all) | fixed; `sim.sh m17` checks every H-Size at both H-Position extremes, V-Shift, line/frame timing, 16 vblank lines and the full picture |
| 3 | D | Flip screen | implemented, m11 pixel-exact on flipped MAME frames |
| 4 | D | Tilemap registers r2, r5, r7 and control bit 5 have no known function (stored, unused - as MAME) | as MAME |
| 5 | D | 0x0C0018/0x0C001A writes (watchdog?) ignored - as MAME | as MAME |
| 6 | D | Interrupt acknowledge timing: FX68K (real 68000 E-clock-synchronised autovector) differs from MAME's 68000 by < 1 us per interrupt; bus traces match MAME until the first interrupt, after that interrupts stay on MAME's lines | expected |
| 7 | D | Sprite-buffer copy (2.7 us at line 248) holds CPU writes to not-yet-copied sprite entries; MAME's copy is instantaneous | minor, documented |
| 8 | D | Sprite colour 0/15 priority rule reproduced from MAME ("seems a bit strange" in MAME) | as MAME |
| 10 | D | Sound programs race the 68000 on the sound latch (no handshake; Super-X overwrites a command 3.7 ms later, the Z80 polls every ~3.6 ms), so Z80/68000 start phase matters | fixed: Z80 starts with the 68000; m16/m16x write streams identical to MAME |
| 11 | D | M10K usage 512/553 (93 %): 68000 program ROM (256 blocks) is in BRAM for zero-wait determinism | monitor |
| 9 | C | Render overload: if a line's sprites + tiles exceed 6144 clocks the engines are aborted (debug counter `overruns`); worst measured line (attract frame 2760) uses 4291 = 70 % | monitor |
