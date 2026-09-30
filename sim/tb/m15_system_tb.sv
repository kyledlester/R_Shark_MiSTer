// M15: whole board (rshark_core: 68000 board, video, Z80 sound board, SDRAM arbiter) running the
// real program from reset, with the production clocks, SDRAM controller and a preloaded chip model.
// ROM BRAMs and SDRAM are preloaded (the loader is tested separately), so the run starts at reset.
// Plusargs:
//   +FRAMES=<n>   run until the n-th vblank (default 40)
//   +DUMPA=<a> +DUMPB=<b> dump the displayed frames that follow vblanks a..b to build/sim/frames/cNNNNN.rgb
// Writes build/sim/latch.txt ("frame line value" per sound-latch write) and prints board counters.
// scripts/syscheck.py compares the dumps with MAME (docs/MAME_REFERENCE.md timing mapping).
// Requires +define+RSHARK_SIM_ROM=... +define+RSHARK_SIM_Z80ROM=... (scripts/sim.sh m15).
`timescale 1ns/1ps
module m15_system_tb;
    logic clk = 0;
    always #5.298 clk = ~clk;
    logic init = 1, reset = 1;

    logic [26:1] sd_addr; logic [15:0] sd_din; logic [1:0] sd_be; logic sd_req, sd_rnw, sd_ready;
    logic [63:0] sd_dout;
    logic ce_pix; logic [23:0] rgb; logic hb, vb, hs, vs;
    logic signed [15:0] snd;
    logic ioctl_wait;

    rshark_core dut (
        .clk(clk), .init(init), .reset(reset), .pause(1'b0),
        .ioctl_download(1'b0), .ioctl_index(16'd0), .ioctl_wr(1'b0), .ioctl_addr('0), .ioctl_dout('0),
        .ioctl_wait(ioctl_wait),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_req(sd_req), .sd_rnw(sd_rnw),
        .sd_dout(sd_dout), .sd_ready(sd_ready),
        .joy0(32'd0), .joy1(32'd0), .test_pattern(1'b0), .dbg_overlay(1'b0),
        .ce_pix(ce_pix), .rgb(rgb), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .snd(snd));

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

    int max_frames = 40, dump_a = -1, dump_b = -1;
    int lfd;
    initial begin
        void'($value$plusargs("FRAMES=%d", max_frames));
        void'($value$plusargs("DUMPA=%d", dump_a));
        void'($value$plusargs("DUMPB=%d", dump_b));
        chip.preload("local/sim/sdram_be.bin");
        lfd = $fopen("build/sim/latch.txt", "w");
        // MAME's CPU/raster phase (see m3_boot_tb): CPU released 65 clocks before the raster.
        // The SDRAM controller starts with the raster (init) and is ready long before line 8.
        repeat (8) @(posedge clk);
        reset <= 0;
        repeat (65) @(posedge clk);
        init <= 0;
    end

    wire [15:0] frames = dut.dbg_frames;
    always @(posedge clk) if (dut.main.snd_latch_wr)
        $fdisplay(lfd, "%0d %0d %02x", frames, dut.vcount, dut.main.cpu_wdata[7:0]);

    // frame dumps (output timing: rgb/hblank/vblank are aligned)
    int fd = 0, npix = 0;
    logic vb_d = 1;
    always @(posedge clk) if (ce_pix && !init) begin
        vb_d <= vb;
        if (vb_d && !vb) begin
            if (fd) begin $fclose(fd); fd = 0; end
            if (frames >= dump_a && frames <= dump_b) begin
                fd = $fopen($sformatf("build/sim/frames/c%05d.rgb", frames), "wb");
                npix = 0;
            end
        end
        if (fd && !hb && !vb) begin
            $fwrite(fd, "%c%c%c", rgb[23:16], rgb[15:8], rgb[7:0]);
            npix++;
        end
    end

    logic [15:0] last_frames = 0;
    always @(posedge clk) begin
        if (frames != last_frames) begin
            last_frames <= frames;
            if (frames % 10 == 0)
                $display("frame %0d: pc %06x irq5 %0d irq6 %0d latch %0d | z80 latch rd %0d irqs %0d ym %0d oki %0d | overruns %0d",
                    frames, dut.dbg_pc, dut.dbg_irq5, dut.dbg_irq6, dut.dbg_latch, dut.dbg_lat_rd, dut.dbg_zirq,
                    dut.dbg_ym, dut.dbg_oki, dut.dbg_overruns);
            if (frames >= max_frames) begin
                $display("PASS M15_SYSTEM: ran %0d frames: pc %06x irq5 %0d irq6 %0d latch writes %0d; z80 latch reads %0d irqs %0d ym writes %0d oki writes %0d; render overruns %0d",
                    frames, dut.dbg_pc, dut.dbg_irq5, dut.dbg_irq6, dut.dbg_latch, dut.dbg_lat_rd, dut.dbg_zirq,
                    dut.dbg_ym, dut.dbg_oki, dut.dbg_overruns);
                $fclose(lfd);
                $finish;
            end
        end
    end
endmodule
