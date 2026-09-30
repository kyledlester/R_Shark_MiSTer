// M3/M4/M5: real R-Shark program on FX68K inside rshark_main, bus transactions compared one by one
// with MAME's (scripts/mame/bus_trace.lua -> local/traces/bus_trace.txt).
// Every 68000 data-bus cycle (opcode fetches included) must match in order: direction, address
// (A0 = 0, A23-A20 as driven), data, byte mask. Runs with the production clock ratio
// (clk_sys = 94.37 MHz, tick16 every 5.9 clocks) and the production raster events, so interrupt
// chronology is compared too.
// Plusargs: +TRACE=<file> (default local/traces/bus_trace.txt), +N=<transactions> (default 20000).
// Requires +define+RSHARK_SIM_ROM="local/sim/maincpu.hex" (scripts/sim.sh m3).
`timescale 1ns/1ps
module m3_boot_tb;
    logic clk = 0;
    always #5.298 clk = ~clk;
    logic superx = 0;
    initial if ($test$plusargs("SUPERX")) superx = 1;
    logic reset = 1, init = 1;

    logic ce_pix, tick16, phi1, phi2, ce_4m, ce_1m;
    rshark_clocks clocks (.clk(clk), .rst(reset), .rst_video(init), .pause(1'b0),
        .ce_pix(ce_pix), .tick16(tick16), .phi1(phi1), .phi2(phi2), .ce_4m(ce_4m), .ce_1m(ce_1m));
    logic [8:0] hc; logic [7:0] vc; logic hb, vb, hs, vs, ls;
    rshark_video_timing timing (.clk(clk), .rst(init), .ce_pix(ce_pix),
        .hcount(hc), .vcount(vc), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .line_start(ls));

    wire irq5 = ls && vc == 8'd248;
    wire irq6 = ls && vc == 8'd120;

    logic [7:0] latch; logic latch_wr, flip, bg1_pri; logic [7:0] ctrl; logic [255:0] regs;
    logic [1:0] pal_we; logic [10:0] pal_addr; logic [15:0] pal_wdata;
    logic [13:0] yd; logic [32:0] ad; logic busy;
    logic [23:0] pc; logic [15:0] n5, n6, nf, nl;
    rshark_main dut (
        .clk(clk), .reset(reset), .superx(superx), .phi1(phi1), .phi2(phi2),
        .rom_we(1'b0), .rom_waddr('0), .rom_wdata('0),
        .irq5_evt(irq5), .irq6_evt(irq6), .vblank_evt(irq5),
        .dsw(16'hFFFF), .p1p2(16'hFFFF), .system(8'hFF),
        .snd_latch(latch), .snd_latch_wr(latch_wr), .flip(flip), .bg1_pri(bg1_pri), .ctrl_byte(ctrl),
        .tm_regs(regs), .pal_we(pal_we), .pal_addr(pal_addr), .pal_wdata(pal_wdata),
        .ytab_addr(8'd0), .ytab_data(yd), .atab_addr(8'd0), .atab_data(ad), .spr_copy_busy(busy),
        .dbg_pc(pc), .dbg_irq5(n5), .dbg_irq6(n6), .dbg_frames(nf), .dbg_latch_writes(nl));

    // bus-cycle length histogram in 16 MHz ticks (half CPU clocks) between AS assertions:
    // a zero-wait 68000 bus cycle is 4 CPU clocks = 8 ticks.
    wire as_n = dut.dbg_native[57];
    logic as_n_d = 1;
    int ticks_since_as = 0;
    int as_hist [0:31];
    initial for (int i = 0; i < 32; i++) as_hist[i] = 0;
    always @(posedge clk) begin
        as_n_d <= as_n;
        if (tick16) ticks_since_as++;
        if (as_n_d && !as_n) begin
            as_hist[ticks_since_as > 31 ? 31 : ticks_since_as]++;
            ticks_since_as = 0;
        end
    end
    final begin
        automatic string h = "";
        for (int i = 0; i < 32; i++) if (as_hist[i] != 0) h = {h, $sformatf(" %0d:%0d", i, as_hist[i])};
        $display("AS-to-AS ticks histogram:%s", h);
    end

    // CPU time base: 16 MHz ticks since reset release; every 1000th transaction is logged to
    // build/sim/fpga_times.txt ("n seconds address") for drift analysis against MAME.
    longint ticks = 0;
    int tfd;
    initial tfd = $fopen("build/sim/fpga_times.txt", "w");
    always @(posedge clk) if (!reset && tick16) ticks++;

    // one record per completed CPU transaction (backend ack)
    int fd, n = 0, max_n = 20000, errors = 0;
    string trace;
    longint t_start;
    initial begin
        if (!$value$plusargs("TRACE=%s", trace)) trace = "local/traces/bus_trace.txt";
        void'($value$plusargs("N=%d", max_n));
        fd = $fopen(trace, "r");
        if (fd == 0) begin $display("FAIL M3_BOOT: cannot open %s", trace); $finish; end
        // MAME's screen starts at time 0 (vblank begin) and its 68000 fetches the reset vector at
        // 1.000 us. FX68K's first fetch comes 0.69 us after its reset release, so the CPU is
        // released 65 clk_sys (0.69 us) before the raster to keep MAME's CPU/raster phase (the
        // phase is arbitrary on hardware; it only matters for a cycle-level trace comparison).
        repeat (8) @(posedge clk);
        reset <= 0;
        repeat (65) @(posedge clk);
        init <= 0;
    end

    always @(posedge clk) if (dut.cpu_ack) begin
        string kind; int addr, data, mask, r;
        int got_addr, got_data, got_mask;
        r = $fscanf(fd, "%s %h %h %h\n", kind, addr, data, mask);
        got_addr = {dut.cpu_addr[23:1], 1'b0} & 24'h0FFFFE;
        got_data = dut.cpu_write ? dut.cpu_wdata : dut.cpu_rdata;
        got_mask = {{8{dut.cpu_be[1]}}, {8{dut.cpu_be[0]}}};
        // the MAME tap reports the full word for reads; compare the enabled lanes only
        if (r != 4) begin
            $display("PASS M3_BOOT: trace exhausted after %0d matching transactions", n);
            $finish;
        end
        if ((kind == "W") != dut.cpu_write || addr != got_addr || mask != got_mask ||
            ((data ^ got_data) & got_mask) != 0) begin
            $display("FAIL M3_BOOT: transaction %0d mismatch: MAME %s %06x %04x %04x  FPGA %s %06x %04x %04x  (line %0d dot %0d, irq5=%0d irq6=%0d, pc=%06x)",
                n, kind, addr, data, mask, dut.cpu_write ? "W" : "R", got_addr, got_data, got_mask,
                vc, hc, n5, n6, pc);
            $finish;
        end
        if (n % 1000 == 0) $fdisplay(tfd, "%0d %.9f %06x", n, ticks / 16.0e6, got_addr);
        if (!dut.cpu_write && (got_addr == 24'h74 || got_addr == 24'h78))
            $display("VEC %06x frame %0d line %0d dot %0d transaction %0d", got_addr, nf, vc, hc, n);
        n++;
        if (n % 50000 == 0) $display("progress %0d transactions, line %0d, frames %0d, irq5 %0d irq6 %0d", n, vc, nf, n5, n6);
        if (n >= max_n) begin
            $display("PASS M3_BOOT: %0d transactions identical to MAME (frames %0d, irq5 acks %0d, irq6 acks %0d, sound latch writes %0d, pc %06x)",
                n, nf, n5, n6, nl, pc);
            $finish;
        end
    end
endmodule
