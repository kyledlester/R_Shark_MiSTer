// R-Shark MiSTer core -- raster timing.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// MAME logical raster (dooyong.cpp dooyong_68k()): set_size(64*8, 32*8) = 512 x 256,
// visarea x 64..447, y 8..247 (384 x 240), 60 Hz. With ce_pix = 7.864320 MHz this is
// 15.360 kHz / 60.000 Hz. hcount/vcount are MAME's hpos/vpos (beam coordinates).
//
// Sync placement is a MiSTer/CRT choice, not PCB-verified (docs/VIDEO.md):
//   H: active 64..447, front porch 448..467, HSync 468..504 (37 dots = 4.7 us), back porch.
//   V: active 8..247, front porch 248..249, VSync 250..252, back porch 253..7.
// Events (one clk_sys pulse, on the ce_pix that enters dot 0 of the line):
//   line_start : every line, with the new vcount valid.
// Reset phase: MAME starts its screen at vblank begin (screen.cpp: m_vblank_start_time = 0), i.e.
// the beam is at line 248, dot 0 at time 0. The raster leaves reset at the same position so CPU
// time and interrupt lines keep MAME's phase (used to compare bus traces with MAME during development).
module rshark_video_timing (
    input  logic       clk,
    input  logic       rst,
    input  logic       ce_pix,
    output logic [8:0] hcount,     // 0..511
    output logic [7:0] vcount,     // 0..255
    output logic       hblank,
    output logic       vblank,
    output logic       hsync,
    output logic       vsync,
    output logic       line_start
);
    always_ff @(posedge clk) begin
        line_start <= 1'b0;
        if (rst) begin
            hcount <= '0;
            vcount <= 8'd248;
        end else if (ce_pix) begin
            hcount <= hcount + 9'd1;
            if (hcount == 9'd511) begin
                vcount     <= vcount + 8'd1;
                line_start <= 1'b1;
            end
        end
    end

    always_comb begin
        hblank = (hcount < 9'd64) || (hcount >= 9'd448);
        vblank = (vcount < 8'd8) || (vcount >= 8'd248);
        hsync  = (hcount >= 9'd468) && (hcount <= 9'd504);
        vsync  = (vcount >= 8'd250) && (vcount <= 8'd252);
    end
endmodule
