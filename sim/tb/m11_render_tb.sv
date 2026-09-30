// M10-M14: video render of a captured MAME frame through the production video path
// (rshark_video + rshark_sdram_arb + vendored sdram.sv + SDRAM chip model preloaded with the
// loader's image), compared pixel-exactly with MAME's rendered frame.
// Inputs: +FRAME=<dir> from scripts/mame/capture_frames.lua (palette.bin, sprbuf.bin, regs.txt,
// pixels.bin) and local/sim/sdram_be.bin (scripts/romtool.py images).
// The frame state is applied as MAME used it at render time (docs/MAME_REFERENCE.md), so the
// FPGA output must equal MAME's pixels.
`timescale 1ns/1ps
module m11_render_tb;
    logic clk = 0;
    always #5.298 clk = ~clk;
    logic init = 1, rst = 1;

    logic ce_pix, tick16, phi1, phi2, ce_4m, ce_1m;
    rshark_clocks clocks (.clk(clk), .rst(rst), .rst_video(init), .pause(1'b0),
        .ce_pix(ce_pix), .tick16(tick16), .phi1(phi1), .phi2(phi2), .ce_4m(ce_4m), .ce_1m(ce_1m));
    logic [8:0] hc; logic [7:0] vc; logic hb, vb, hs, vs, ls;
    rshark_video_timing timing (.clk(clk), .rst(init), .ce_pix(ce_pix),
        .hcount(hc), .vcount(vc), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .line_start(ls));

    // ------------------------------------------------------------------ frame state
    string frame;
    logic [255:0] regs;
    logic [7:0]   ctrl;
    logic [15:0]  palette [2048];
    logic [15:0]  spr [2048];
    logic [7:0]   mame_px [384*240*4];

    function automatic int read_bytes(input string f, ref logic [7:0] buf_[], input int n);
        int fd, i; logic [7:0] b;
        fd = $fopen(f, "rb");
        if (fd == 0) return -1;
        for (i = 0; i < n; i++) begin
            if ($fread(b, fd) != 1) break;
            buf_[i] = b;
        end
        $fclose(fd);
        return i;
    endfunction

    // sprite tables as rshark_main builds them (registered reads)
    logic [7:0]  ytab_addr, atab_addr;
    logic [13:0] ytab_data;
    logic [32:0] atab_data;
    always_ff @(posedge clk) begin
        automatic int e = ytab_addr * 8;
        automatic int f = atab_addr * 8;
        ytab_data <= {spr[e][0], spr[e + 1][7:4], spr[e + 6][8:0]};
        atab_data <= {spr[f + 1][3:0], spr[f + 4][8:0], spr[f + 3], spr[f + 7][3:0]};
    end

    // palette load through the CPU write port
    logic [1:0]  pal_we = 2'b00;
    logic [10:0] pal_addr;
    logic [15:0] pal_wdata;

    // ------------------------------------------------------------------ DUT
    logic tm_req, sp_req, tm_ack, sp_ack;
    logic [25:1] tm_addr, sp_addr;
    logic [63:0] mem_data;
    logic [23:0] rgb;
    logic ohb, ovb, ohs, ovs;
    logic [15:0] overruns;
    rshark_video video (
        .clk(clk), .rst(rst), .ce_pix(ce_pix), .hcount(hc), .vcount(vc), .line_start(ls),
        .hblank_in(hb), .vblank_in(vb), .hsync_in(hs), .vsync_in(vs),
        .regs(regs), .bg1_pri(ctrl[4]),
        .pal_we(pal_we), .pal_addr(pal_addr), .pal_wdata(pal_wdata),
        .ytab_addr(ytab_addr), .ytab_data(ytab_data), .atab_addr(atab_addr), .atab_data(atab_data),
        .tm_req(tm_req), .tm_addr(tm_addr), .tm_ack(tm_ack),
        .sp_req(sp_req), .sp_addr(sp_addr), .sp_ack(sp_ack), .mem_data(mem_data),
        .rgb(rgb), .hblank(ohb), .vblank(ovb), .hsync(ohs), .vsync(ovs), .dbg_overruns(overruns));

    logic [3:0] ack;
    logic [26:1] sd_addr; logic [15:0] sd_din; logic [1:0] sd_be; logic sd_req, sd_rnw, sd_ready;
    logic [63:0] sd_dout;
    logic [25:1] arb_addr [4];
    assign arb_addr[0] = '0; assign arb_addr[1] = '0; assign arb_addr[2] = tm_addr; assign arb_addr[3] = sp_addr;
    rshark_sdram_arb arb (
        .clk(clk), .rst(rst), .req({sp_req, tm_req, 2'b00}), .addr(arb_addr), .we(4'b0000),
        .wdata(16'd0), .wbe(2'b11), .ack(ack), .rdata(mem_data),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_req(sd_req), .sd_rnw(sd_rnw),
        .sd_dout(sd_dout), .sd_ready(sd_ready));
    assign tm_ack = ack[2];
    assign sp_ack = ack[3];

    wire [15:0] SDRAM_DQ; wire [12:0] SDRAM_A; wire [1:0] SDRAM_BA;
    wire SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CKE, SDRAM_CLK;
    sdram #(.CYCLES_PER_REFRESH(14'd730)) sdc (
        .init(init), .clk(clk), .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML),
        .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK),
        .ch1_addr(sd_addr), .ch1_dout(sd_dout), .ch1_din(sd_din), .ch1_be(sd_be), .ch1_req(sd_req),
        .ch1_rnw(sd_rnw), .ch1_ready(sd_ready),
        .ch2_addr('0), .ch2_dout(), .ch2_din('0), .ch2_req(1'b0), .ch2_rnw(1'b1), .ch2_ready(),
        .ch3_addr('0), .ch3_dout(), .ch3_din('0), .ch3_req(1'b0), .ch3_rnw(1'b1), .ch3_ready());
    sdr_sdram_model #(.TCK_NS(10.596)) chip (
        .clk(SDRAM_CLK), .cke(SDRAM_CKE), .csn(SDRAM_nCS), .rasn(SDRAM_nRAS), .casn(SDRAM_nCAS),
        .wen(SDRAM_nWE), .ba(SDRAM_BA), .a(SDRAM_A), .dqml(SDRAM_DQML), .dqmh(SDRAM_DQMH), .dq(SDRAM_DQ));

    // ------------------------------------------------------------------ stimulus / check
    int errors = 0, npix = 0, frames_seen = 0;
    bit capture = 0;
    int max_busy_clk = 0, busy_clk = 0;

    initial begin
        logic [7:0] tmp [];
        int fd, n;
        string line, name; int v [8];
        if (!$value$plusargs("FRAME=%s", frame)) frame = "local/frames/f01800";
        // regs.txt
        fd = $fopen({frame, "/regs.txt"}, "r");
        if (fd == 0) begin $display("FAIL M11_RENDER: no %s/regs.txt", frame); $finish; end
        for (int l = 0; l < 4; l++) begin
            n = $fscanf(fd, "%s %h %h %h %h %h %h %h %h\n", name, v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]);
            for (int i = 0; i < 8; i++) regs[l*64 + i*8 +: 8] = v[i];
        end
        n = $fscanf(fd, "%s %h\n", name, v[0]);
        ctrl = v[0];
        $fclose(fd);
        tmp = new[4096];
        if (read_bytes({frame, "/palette.bin"}, tmp, 4096) != 4096) begin $display("FAIL M11_RENDER: palette"); $finish; end
        for (int i = 0; i < 2048; i++) palette[i] = {tmp[2*i], tmp[2*i+1]};
        if (read_bytes({frame, "/sprbuf.bin"}, tmp, 4096) != 4096) begin $display("FAIL M11_RENDER: sprbuf"); $finish; end
        for (int i = 0; i < 2048; i++) spr[i] = {tmp[2*i], tmp[2*i+1]};
        tmp = new[384*240*4];
        if (read_bytes({frame, "/pixels.bin"}, tmp, 384*240*4) != 384*240*4) begin $display("FAIL M11_RENDER: pixels"); $finish; end
        for (int i = 0; i < 384*240*4; i++) mame_px[i] = tmp[i];
        chip.preload("local/sim/sdram_be.bin");

        repeat (4) @(posedge clk);
        init <= 0;
        // palette through the write port
        for (int i = 0; i < 2048; i++) begin
            @(posedge clk);
            pal_we <= 2'b11; pal_addr <= i; pal_wdata <= palette[i];
        end
        @(posedge clk) pal_we <= 2'b00;
        // SDRAM controller start-up (~12100 clocks) before the renderers run
        repeat (13000) @(posedge clk);
        rst <= 0;
    end

    // measure the renderer's per-line busy time
    always @(posedge clk) begin
        if (video.render_start) begin
            if (busy_clk > max_busy_clk) max_busy_clk = busy_clk;
            busy_clk = 0;
        end else if (video.tm_busy || video.sp_busy) busy_clk++;
    end

    logic ovb_d = 1;
    always @(posedge clk) if (ce_pix && !rst) begin
        ovb_d <= ovb;
        if (ovb_d && !ovb) begin          // first visible line of a frame (output timing)
            frames_seen++;
            if (frames_seen == 2) begin capture = 1; npix = 0; end
            if (frames_seen == 3) begin
                if (errors == 0 && npix == 384*240)
                    $display("PASS M11_RENDER: %s %0d pixels identical to MAME (max render %0d clk/line of 6144, overruns %0d)",
                        frame, npix, max_busy_clk, overruns);
                else
                    $display("FAIL M11_RENDER: %s %0d/%0d pixels differ (max render %0d clk/line, overruns %0d)",
                        frame, errors, npix, max_busy_clk, overruns);
                $finish;
            end
        end
        if (capture && !ohb && !ovb) begin
            automatic int i = npix * 4;
            automatic logic [23:0] m = {mame_px[i+2], mame_px[i+1], mame_px[i]};
            if (rgb !== m) begin
                if (errors < 8) $display("mismatch x=%0d y=%0d fpga=%06x mame=%06x", npix % 384, npix / 384, rgb, m);
                errors++;
            end
            npix++;
        end
    end
endmodule
