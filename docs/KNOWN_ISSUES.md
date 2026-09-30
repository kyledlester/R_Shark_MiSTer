# Known issues and open questions

Unknowns are categorised: A = needed for CPU boot, B = for useful graphics, C = for gameplay,
D = accuracy item that can wait.

| # | Cat | Item | Status |
| --- | --- | --- | --- |
| 1 | D | PCB video timing (dot clock, totals, sync) unknown; MAME's 512x256@60 raster is used, sync placement is a CRT-friendly choice | open (M20) |
| 2 | D | Tilemap registers latched at vblank (game writes them at line ~125); palette live. Real hardware behaviour unverified. Relative to MAME, scroll/palette appear together with the sprites of the same game tick | design decision, docs/VIDEO.md |
| 3 | D | Flip screen (control bit 0, DIP default off) not implemented | open |
| 4 | D | Tilemap registers r2, r5, r7 and control bit 5 have no known function (stored, unused - as MAME) | as MAME |
| 5 | D | 0x0C0018/0x0C001A writes (watchdog?) ignored - as MAME | as MAME |
| 6 | D | Interrupt acknowledge timing: FX68K (real 68000 E-clock-synchronised autovector) differs from MAME's 68000 by < 1 us per interrupt; bus traces match MAME until the first interrupt, after that interrupts stay on MAME's lines | expected |
| 7 | D | Sprite-buffer copy (2.7 us at line 248) holds CPU writes to not-yet-copied sprite entries; MAME's copy is instantaneous | minor, documented |
| 8 | D | Sprite colour 0/15 priority rule reproduced from MAME ("seems a bit strange" in MAME) | as MAME |
| 9 | C | Render overload: if a line's sprites + tiles exceed 6144 clocks the engines are aborted (debug counter `overruns`); worst measured attract line uses 2826 | monitor |
