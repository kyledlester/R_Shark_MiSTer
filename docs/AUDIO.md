# Audio

## What MAME models (0.289, `dooyong_68k`, `sound_2151`, `bluehawk_sound_map`)

| Part | Clock | Notes |
| --- | --- | --- |
| Z80 | 8 MHz / 2 = 4 MHz ("4MHz measured on Super-X") | program rse3.bin; IM 1 (verified in the ROM: `ED 56` at 0000) |
| YM2151 | 8 MHz / 2 = 4 MHz | IRQ -> Z80 INT (level); output L and R each x0.35 into one mono speaker |
| OKI M6295 | 8 MHz / 8 = 1 MHz, `PIN7_HIGH` | divider 132 -> 7575.8 Hz sample rate; x0.42 into mono; 256 KB sample ROM (rse1 + rse2, no gaps) |
| sound latch | `generic_latch_8` | 68000 writes 0x0C0013, Z80 reads 0xF800; no flag, no interrupt - the Z80 polls it from its YM timer IRQ |

The 68000 writes the latch in its IRQ6 handler (line 122 of each frame, docs/MAME_REFERENCE.md).
The Z80 program also writes 0xF806 / 0xF80C and (per MAME's TODO) 0x0003/0x0004 of ROM space: all
unmapped / ignored, as in MAME.

## FPGA implementation (`rtl/rshark/rshark_sound.sv`)

* Clock domain: `clk_snd` = clk_sys / 2 = 47.185920 MHz (second output of the core PLL, phase
  aligned, so every crossing is synchronous and timing-analysed). jt51 and T80 did not close timing
  at 94 MHz (first full build: -1.28 ns, all failing paths inside them). `ce_4m` is an exact-average
  fractional enable (4,000,000 / 47,185,920), `ce_1m = ce_4m / 4`. Crossings: dual-clock Z80 ROM
  (download in clk_sys), sound latch (static, sampled), OKI SDRAM reads via a level handshake,
  audio output registered back into clk_sys.
* Reset: synchronised and stretched to 4096 clk_snd with the clock enables running, because jt51's
  shift-register pipelines (`jt51_sh.v`) only take their reset value when reset spans as many
  enabled clocks as they have stages.

* T80s (MiSTer T80, Mode 0) on `ce_4m` (4 MHz average, fractional from clk_sys), ROM 64K x 8 and RAM
  2K x 8 in block RAM (zero wait), WAIT_n unused.
* jt51 (YM2151) on `cen = ce_4m`, `cen_p1` = every second `ce_4m`; one write strobe per Z80 write
  cycle; `irq_n` -> Z80 `INT_n`.
* jt6295 (OKI) on `cen = ce_1m`, `ss = 1` (pin 7 high, /132), `INTERPOL = 0`. Sample ROM read from
  SDRAM through an 8-byte line cache (`rom_ok` = cache hit), arbiter priority above the video
  engines.
* Mix: `(YM_L + YM_R) * 45/128 + OKI * 860/128`, saturated to 16 bits = MAME's gains (0.35, 0.42 with
  OKI's 12-bit voices scaled to 16-bit full range: x16). MiSTer mono (AUDIO_L =
  AUDIO_R).

## Verification

* `sim.sh m16` replays MAME's 68000 sound-latch writes at MAME's times into the board and compares
  every Z80 write to the YM2151 and OKI with MAME's (scripts/mame/sound_trace.lua): 3 s of attract,
  10,419 writes identical in order and value, max time offset 16.9 us, 827 latch reads, 828 YM timer
  interrupts. Passes with clk_snd == clk and with the production 2:1 crossing (`+define+M16_HALF`).
* Simulation note: ModelSim is 4-state; jt51's pipelines rely on FPGA power-up zeros, so the audio
  bench deposits 0 into the jt51 instance before running (`PRERUN="do sim/tb/zero_regs.do
  /m16_sound_tb/dut/ym;"`), which is what the FPGA does at configuration.
* `scripts/audiocheck.py` compares the bench's audio with `mame -wavwrite` output (envelope and
  spectrum correlation, level ratio).
