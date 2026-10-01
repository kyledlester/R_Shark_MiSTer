// M16-M18: Z80 sound board (rshark_sound: T80, jt51, jt6295) against MAME.
// The 68000's sound-latch writes are replayed at MAME's times (scripts/mame/sound_trace.lua ->
// local/traces/sound_trace.txt "M" lines); every Z80 write to F808/F809 (YM2151) and F80A (OKI)
// is compared in order with MAME's ("Z ... W" lines): address and data must match, and the time
// difference is reported. Status reads are not compared (their count depends on busy timing).
// Simulation clock: 8 MHz (1 clk = 125 ns), ce_4m every 2nd and ce_1m every 8th clock - the board
// only sees clock enables, so this keeps the production 4 MHz / 1 MHz rates at 1/12 of the cost.
// OKI sample ROM: served directly from local/regions/oki.bin (arbiter protocol, 3-clock latency).
// Audio: build/sim/sound.raw (signed 16-bit mono, one sample per 1 MHz tick = 1 MHz rate).
// Plusargs: +MS=<milliseconds to run> (default 400), +N=<writes to compare, 0 = all>.
`timescale 1ns/1ps
module m16_sound_tb;
    logic clk = 0, clk_snd = 0;
`ifdef M16_HALF
    // production-shaped crossing: clk_snd = clk / 2 (clk 16 MHz here), board ce every 2nd clk_snd
    always #31.25 clk = ~clk;
    always @(posedge clk) clk_snd <= ~clk_snd;
`else
    always #62.5 clk = ~clk;
    always @* clk_snd = clk;
`endif
    logic reset = 1;


    logic [7:0] latch = 8'h00;
    logic oki_req, oki_ack = 0;
    logic [25:1] oki_addr;
    logic [63:0] oki_data;
    logic signed [15:0] snd;
    logic [15:0] c_lat, c_ym, c_oki, c_irq;

    // clk_snd = the 8 MHz bench clock with ce_4m every 2nd clock (CE_NUM/CE_DEN = 1/2)
    rshark_sound #(.CE_NUM(1), .CE_DEN(2)) dut (
        .clk(clk), .clk_snd(clk_snd), .reset(reset), .pause(1'b0), .latch(latch),
        .rom_we(1'b0), .rom_waddr('0), .rom_wdata('0),
        .oki_req(oki_req), .oki_addr(oki_addr), .oki_ack(oki_ack), .oki_data(oki_data),
        .snd(snd), .dbg_latch_reads(c_lat), .dbg_ym_writes(c_ym), .dbg_oki_writes(c_oki), .dbg_z80_irqs(c_irq));

    // OKI ROM
    logic [7:0] oki_rom [0:262143];
    string oki_hex, strace, sraw;
    initial begin
        if (!$value$plusargs("OKIHEX=%s", oki_hex)) oki_hex = "local/sim/oki.hex";
        $readmemh(oki_hex, oki_rom);
    end
    logic [1:0] okcnt = 0;
    always_ff @(posedge clk) begin
        oki_ack <= 1'b0;
        if (oki_req && !oki_ack) begin
            okcnt <= okcnt + 2'd1;
            if (okcnt == 2'd2) begin
                automatic int b = (oki_addr - 25'h400000) * 2;
                for (int i = 0; i < 8; i++) oki_data[i*8 +: 8] <= oki_rom[(b + i) & 18'h3FFFF];
                oki_ack <= 1'b1;
                okcnt <= 0;
            end
        end
    end

    // MAME trace
    real   lat_t [$]; int lat_v [$];
    real   w_t [$]; int w_a [$]; int w_d [$];
    int    run_ms = 400, max_n = 0;
    int    afd;
    initial begin
        int fd, r; string kind, rw; real tt; int a, v;
        void'($value$plusargs("MS=%d", run_ms));
        void'($value$plusargs("N=%d", max_n));
        if (!$value$plusargs("STRACE=%s", strace)) strace = "local/traces/sound_trace.txt";
        fd = $fopen(strace, "r");
        if (fd == 0) begin $display("FAIL M16_SOUND: no %s", strace); $finish; end
        while (!$feof(fd)) begin
            r = $fscanf(fd, "%s", kind);
            if (r != 1) break;
            if (kind == "M") begin r = $fscanf(fd, "%f %h\n", tt, v); lat_t.push_back(tt); lat_v.push_back(v); end
            else begin
                r = $fscanf(fd, "%f %s %h %h\n", tt, rw, a, v);
                if (rw == "W") begin w_t.push_back(tt); w_a.push_back(a); w_d.push_back(v); end
            end
        end
        $fclose(fd);
        if (!$value$plusargs("SOUNDRAW=%s", sraw)) sraw = "build/sim/sound.raw";
        afd = $fopen(sraw, "wb");
        $display("trace: %0d latch writes, %0d Z80 chip writes", lat_t.size(), w_t.size());
        // a long reset like the ROM download's (covers jt51's minimum reset), then both CPUs start
        // at time 0 as in MAME
        repeat (5000) @(posedge clk_snd);
        reset <= 0;
    end

    // time in microseconds since reset release: 8 clocks per us
    longint clks = 0;
    always @(posedge clk_snd) if (!reset) clks++;
    real t_us;
    always @* t_us = clks / 8.0;

    int li = 0;
    always @(posedge clk) if (!reset) while (li < lat_t.size() && lat_t[li] <= t_us) begin latch <= lat_v[li]; li++; end

    // compare Z80 chip writes
    int wi = 0, errors = 0; real maxdt = 0;
    logic wr_n_d = 1;
    always @(posedge clk) begin
        wr_n_d <= dut.wr_n;
        if (!reset && wr_n_d && !dut.wr_n && !dut.mreq_n && (dut.A == 16'hF808 || dut.A == 16'hF809 || dut.A == 16'hF80A)) begin
            if (wi < w_t.size()) begin
                real dt;
                dt = t_us - w_t[wi];
                if (dt < 0) dt = -dt;
                if (dt > maxdt) maxdt = dt;
                if (dut.A != w_a[wi] || dut.cpu_do != w_d[wi]) begin
                    errors++;
                    if (errors <= 5) $display("MISMATCH write %0d at %.1f us: FPGA %04x=%02x MAME %04x=%02x (MAME t=%.1f)",
                        wi, t_us, dut.A, dut.cpu_do, w_a[wi], w_d[wi], w_t[wi]);
                end
            end
            wi++;
            if (max_n != 0 && wi >= max_n) finish_run();
        end
    end

    int n_xop = 0, n_xl = 0, n_xoki = 0; int mn_op = 0, max_ph = 0, n_phchg = 0; logic [9:0] last_ph; int n_keyon = 0, max_kc = 0, max_tl = 0, min_tl = 999, max_mul = 0; int pk_yl = 0, pk_yr = 0, pk_oki = 0, pk_mix = 0, ym_samples = 0, pk_op = 0, min_eg = 1023;
    always @(posedge clk_snd) begin
        if ($signed(dut.ym_l) > pk_yl) pk_yl = $signed(dut.ym_l);
        if ($signed(dut.ym_r) > pk_yr) pk_yr = $signed(dut.ym_r);
        if ($signed(dut.oki_snd) > pk_oki) pk_oki = $signed(dut.oki_snd);
        if ($signed(dut.snd_s) > pk_mix) pk_mix = $signed(dut.snd_s);
        if (dut.ym_sample) ym_samples++;
        if ($signed(dut.ym.op_out) > pk_op) pk_op = $signed(dut.ym.op_out);
        if (dut.ym.eg_XI < min_eg && t_us > 530000) min_eg = dut.ym.eg_XI;
        if (dut.ym.keyon_II && dut.ce_4m) n_keyon++;
        if ($signed(dut.ym.op_out) < mn_op) mn_op = $signed(dut.ym.op_out);
        if ($isunknown(dut.ym.op_out)) n_xop++;
        if ($isunknown(dut.ym_l)) n_xl++;
        if ($isunknown(dut.oki_snd)) n_xoki++;
        if (dut.ym.ph_X > max_ph) max_ph = dut.ym.ph_X;
        if (dut.ym.ph_X != last_ph) begin n_phchg++; last_ph = dut.ym.ph_X; end
        if (dut.ym.kc_I > max_kc) max_kc = dut.ym.kc_I;
        if (dut.ym.mul_VI > max_mul) max_mul = dut.ym.mul_VI;
        if (dut.ym.tl_VII > max_tl) max_tl = dut.ym.tl_VII;
        if (dut.ym.tl_VII < min_tl) min_tl = dut.ym.tl_VII;
    end
    always @(posedge clk_snd) if (dut.ce_1m && !reset) $fwrite(afd, "%c%c", snd[7:0], snd[15:8]);

    always @(posedge clk) if (t_us >= run_ms * 1000.0) finish_run();

    initial begin
        #2000000;   // 2 ms
        $display("X check @2ms: c1_enters %b m1 %b cycles %b cur_op %b eg %b ph %b op %b prev1 %b x %b phasemod %b",
            dut.ym.c1_enters, dut.ym.m1_enters, dut.ym.cycles, dut.ym.cur_op, dut.ym.eg_XI, dut.ym.ph_X,
            dut.ym.op_out, dut.ym.u_op.prev1, dut.ym.u_op.x, dut.ym.u_op.phasemod_II);
        $display("pg: phinc_III %b ph_VII %b ph_VIII %b pg_rst_VII %b kc_I %b kf_I %b dt1 %b mul %b pm %b rst %b",
            dut.ym.u_pg.phinc_III, dut.ym.u_pg.ph_VII, dut.ym.u_pg.ph_VIII, dut.ym.u_pg.pg_rst_VII,
            dut.ym.kc_I, dut.ym.kf_I, dut.ym.dt1_II, dut.ym.mul_VI, dut.ym.pm, dut.rst);
    end

    task automatic finish_run();
        int expected;
        expected = 0;
        while (expected < w_t.size() && w_t[expected] <= t_us) expected++;
        $fclose(afd);
        $display("audio peaks: ym_l %0d ym_r %0d oki %0d mix %0d; ym sample strobes %0d; op_out peak %0d, min eg after 530 ms %0d; keyon_II %0d, max kc %0d mul %0d tl %0d..%0d; op min %0d, phase max %0d changes %0d; X cycles op %0d ym_l %0d oki %0d", pk_yl, pk_yr, pk_oki, pk_mix, ym_samples, pk_op, min_eg, n_keyon, max_kc, max_mul, min_tl, max_tl, mn_op, max_ph, n_phchg, n_xop, n_xl, n_xoki);
        if (errors == 0 && wi > 0 && (wi == expected || wi == expected - 1 || wi == expected + 1))
            $display("PASS M16_SOUND: %.0f ms, %0d YM/OKI writes identical to MAME in order (MAME %0d by now, max time offset %.1f us); latch reads %0d, Z80 IRQs %0d, latch values replayed %0d",
                t_us / 1000.0, wi, expected, maxdt, c_lat, c_irq, li);
        else
            $display("FAIL M16_SOUND: %0d mismatches, %0d writes (MAME %0d by %.0f ms), max time offset %.1f us, Z80 IRQs %0d",
                errors, wi, expected, t_us / 1000.0, maxdt, c_irq);
        $finish;
    endtask
endmodule
