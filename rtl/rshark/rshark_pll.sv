// R-Shark MiSTer core -- system PLL.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// One fractional-N PLL: 50 MHz board clock -> clk_sys = 94.371840 MHz.
//
// 94.371840 MHz = 12 x 7.864320 MHz, and 7.864320 MHz = 512 x 256 x 60 Hz: the dot clock that
// reproduces MAME's logical raster (screen.set_size(512,256), set_refresh_hz(60)) exactly with an
// integer /12 pixel enable. The PCB dot clock is NOT verified (docs/VIDEO.md). The 68000 (8 MHz),
// Z80/YM2151 (4 MHz) and OKI (1 MHz) run from an average-exact fractional 16 MHz tick
// (rshark_clocks.sv). A second output, clk_snd = clk_sys / 2, clocks the Z80 sound board (jt51 and
// T80 do not close timing at 94 MHz; they are normally run at ~48 MHz in MiSTer cores).
//
// HIERARCHY IS LOAD-BEARING: sys/sys_top.sdc places the core clock in its own clock group only if
// it matches *|pll|pll_inst|altera_pll_i|*[*].*|divclk, so emu instantiates this module as "pll"
// (same shape as a MegaWizard MiSTer PLL; pattern from the owner's NB-1 / Neratte Chu cores).
module rshark_pll (
    input  wire refclk,   // CLK_50M
    input  wire rst,
    output wire clk_sys,  // 94.371840 MHz
    output wire clk_snd,  // 47.185920 MHz = clk_sys / 2, phase aligned (sound board domain)
    output wire locked
);
    rshark_pll_core pll_inst (
        .refclk(refclk),
        .rst(rst),
        .clk_sys(clk_sys),
        .clk_snd(clk_snd),
        .locked(locked)
    );
endmodule

module rshark_pll_core (
    input  wire refclk,
    input  wire rst,
    output wire clk_sys,
    output wire clk_snd,
    output wire locked
);
    wire [1:0] clocks;

    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("50.0 MHz"),
        .operation_mode("direct"),
        .number_of_clocks(2),
        .output_clock_frequency0("94.371840 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .output_clock_frequency1("47.185920 MHz"),
        .phase_shift1("0 ps"),
        .duty_cycle1(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) altera_pll_i (
        .refclk(refclk),
        .rst(rst),
        .outclk(clocks),
        .locked(locked),
        .fboutclk(),
        .fbclk(1'b0)
    );

    assign clk_sys = clocks[0];
    assign clk_snd = clocks[1];
endmodule
