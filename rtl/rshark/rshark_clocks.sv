// R-Shark MiSTer core -- clock enables.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// clk_sys = 94.371840 MHz (rshark_pll.sv).
//   ce_pix   : clk_sys / 12 = 7.864320 MHz, exact and jitter-free (MiSTer CE_PIXEL contract).
//   tick16   : 16 MHz average (NUM/DEN = 3125/18432 of clk_sys), spacing 5 or 6 clk_sys.
//   phi1/phi2: FX68K phase enables, alternating on tick16 -> 68000 at 8 MHz (MAME 8_MHz_XTAL).
//   ce_4m    : tick16 / 4 -> Z80 and YM2151 clock (MAME 8_MHz_XTAL / 2).
//   ce_1m    : tick16 / 16 -> OKI M6295 clock (MAME 8_MHz_XTAL / 8).
// pause freezes every emulated time base (the raster keeps running).
module rshark_clocks #(
    parameter int NUM = 3125,
    parameter int DEN = 18432
) (
    input  logic clk,
    input  logic rst,          // emulated time base reset
    input  logic rst_video,    // raster divider reset (PLL loss only)
    input  logic pause,
    output logic ce_pix,
    output logic tick16,
    output logic phi1,
    output logic phi2,
    output logic ce_4m,
    output logic ce_1m
);
    logic [3:0]  pdiv;
    logic [14:0] acc;
    logic [3:0]  div;

    always_ff @(posedge clk) begin
        ce_pix <= 1'b0;
        if (rst_video) pdiv <= '0;
        else begin
            pdiv <= (pdiv == 4'd11) ? 4'd0 : pdiv + 4'd1;
            if (pdiv == 4'd11) ce_pix <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        tick16 <= 1'b0;
        phi1   <= 1'b0;
        phi2   <= 1'b0;
        ce_4m  <= 1'b0;
        ce_1m  <= 1'b0;
        if (rst) begin
            acc <= '0;
            div <= '0;
        end else if (!pause) begin
            if (acc + NUM >= DEN) begin
                acc    <= acc + NUM - DEN;
                tick16 <= 1'b1;
                div    <= div + 4'd1;
                phi1   <= !div[0];
                phi2   <=  div[0];
                ce_4m  <= div[1:0] == 2'd3;
                ce_1m  <= div == 4'd15;
            end else begin
                acc <= acc + NUM;
            end
        end
    end
endmodule
