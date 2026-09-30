// R-Shark MiSTer core -- board top (M0 skeleton: raster + test pattern).
// SPDX-License-Identifier: GPL-3.0-or-later
module rshark_core (
    input  logic        clk,
    input  logic        init,
    input  logic        reset,
    input  logic        pause,

    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [15:0] ioctl_dout,
    output logic        ioctl_wait,

    output logic [26:1] sd_addr,
    output logic [15:0] sd_din,
    output logic  [1:0] sd_be,
    output logic        sd_req,
    output logic        sd_rnw,
    input  logic [63:0] sd_dout,
    input  logic        sd_ready,

    input  logic [31:0] joy0,
    input  logic [31:0] joy1,
    input  logic        test_pattern,
    input  logic        dbg_overlay,

    output logic        ce_pix,
    output logic [23:0] rgb,
    output logic        hblank,
    output logic        vblank,
    output logic        hsync,
    output logic        vsync,
    output logic signed [15:0] snd
);
    logic tick16, phi1, phi2, ce_4m, ce_1m;
    rshark_clocks clocks (
        .clk(clk), .rst(reset), .rst_video(init), .pause(pause),
        .ce_pix(ce_pix), .tick16(tick16), .phi1(phi1), .phi2(phi2), .ce_4m(ce_4m), .ce_1m(ce_1m)
    );

    logic [8:0] hcount;
    logic [7:0] vcount;
    logic hb, vb, hs, vs, line_start;
    rshark_video_timing timing (
        .clk(clk), .rst(init), .ce_pix(ce_pix),
        .hcount(hcount), .vcount(vcount), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs),
        .line_start(line_start)
    );

    // Test pattern: 8 colour bars across the active width, a 1-dot white border.
    always_ff @(posedge clk) if (ce_pix) begin
        hblank <= hb; vblank <= vb; hsync <= hs; vsync <= vs;
        if (hcount == 9'd64 || hcount == 9'd447 || vcount == 8'd8 || vcount == 8'd247)
            rgb <= 24'hFFFFFF;
        else begin
            logic [2:0] bar;
            bar = 3'((hcount - 9'd64) / 9'd48);
            rgb <= {{8{bar[2]}}, {8{bar[1]}}, {8{bar[0]}}};
        end
    end

    assign ioctl_wait = 1'b0;
    assign sd_addr = '0;
    assign sd_din  = '0;
    assign sd_be   = 2'b11;
    assign sd_req  = 1'b0;
    assign sd_rnw  = 1'b1;
    assign snd     = '0;
endmodule
