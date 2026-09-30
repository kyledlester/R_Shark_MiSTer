// M0: clock enables and raster timing.
// Checks: ce_pix = clk/12 exactly; tick16 count over a frame = 16 MHz average within 1 tick;
// phi1/phi2 alternate; ce_4m = tick16/4; ce_1m = tick16/16; raster 512 x 256, visible 384 x 240,
// line_start once per line; frame period = 512*256 pixels.
`timescale 1ns/1ps
module m0_timing_tb;
    logic clk = 0;
    always #5.298 clk = ~clk;       // ~94.37 MHz (value irrelevant: counts are in clk cycles)
    logic rst = 1, rst_video = 1;
    logic ce_pix, tick16, phi1, phi2, ce_4m, ce_1m;
    rshark_clocks dut_c (.clk(clk), .rst(rst), .rst_video(rst_video), .pause(1'b0),
        .ce_pix(ce_pix), .tick16(tick16), .phi1(phi1), .phi2(phi2), .ce_4m(ce_4m), .ce_1m(ce_1m));
    logic [8:0] hc; logic [7:0] vc; logic hb, vb, hs, vs, ls;
    rshark_video_timing dut_t (.clk(clk), .rst(rst_video), .ce_pix(ce_pix),
        .hcount(hc), .vcount(vc), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .line_start(ls));

    int errors = 0, checks = 0;
    task automatic check(input bit cond, input string msg);
        checks++;
        if (!cond) begin errors++; if (errors < 10) $display("FAIL-DETAIL %s", msg); end
    endtask

    longint clks = 0, pix = 0, t16 = 0, p1 = 0, p2 = 0, c4 = 0, c1 = 0, lines = 0, vis = 0;
    int since_pix = 0; bit last_phi = 0; bit seen_phi = 0;
    int hsync_len = 0, vsync_lines = 0;
    initial begin
        repeat (4) @(posedge clk);
        rst <= 0; rst_video <= 0;
        // align the window to a frame boundary (line_start into line 0), then run exactly
        // 2 frames of clk: 2 * 512*256*12 clocks
        do @(posedge clk); while (!(ls && vc == 8'd0));
        repeat (2 * 512 * 256 * 12) begin
            @(posedge clk);
            clks++;
            if (ce_pix) begin
                if (pix > 0) check(since_pix == 12, $sformatf("ce_pix spacing %0d", since_pix));
                since_pix = 0; pix++;
                if (!hb && !vb) vis++;
            end
            since_pix++;
            if (tick16) t16++;
            if (phi1) begin p1++; if (seen_phi) check(last_phi == 1, "phi1 twice"); last_phi = 0; seen_phi = 1; end
            if (phi2) begin p2++; if (seen_phi) check(last_phi == 0, "phi2 twice"); last_phi = 1; seen_phi = 1; end
            if (ce_4m) c4++;
            if (ce_1m) c1++;
            if (ls) lines++;
        end
        // expected tick16 over 2 frames = 2/60 s * 16e6 = 533333.3
        check(pix == 2 * 512 * 256, $sformatf("pixels %0d", pix));
        check(t16 >= 533332 && t16 <= 533334, $sformatf("tick16 %0d", t16));
        check(p1 + p2 == t16, "phi count");
        check(c4 == t16 / 4 || c4 == t16 / 4 + 1, $sformatf("ce_4m %0d", c4));
        check(c1 == t16 / 16 || c1 == t16 / 16 + 1, $sformatf("ce_1m %0d", c1));
        check(lines == 512, $sformatf("lines %0d", lines));
        check(vis == 2 * 384 * 240, $sformatf("visible %0d", vis));
        if (errors == 0) $display("PASS M0_TIMING: %0d checks, clk=%0d pix=%0d tick16=%0d ce4=%0d ce1=%0d lines=%0d", checks, clks, pix, t16, c4, c1, lines);
        else $display("FAIL M0_TIMING: %0d/%0d checks failed", errors, checks);
        $finish;
    end
endmodule
