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
    logic clk = 0;
    always #62.5 clk = ~clk;
    logic reset = 1;

    logic [3:0] div = 0;
    logic ce_4m, ce_1m;
    always_ff @(posedge clk) div <= div + 4'd1;
    assign ce_4m = div[0];
    assign ce_1m = div[2:0] == 3'd7;

    logic [7:0] latch = 8'h00;
    logic oki_req, oki_ack = 0;
    logic [25:1] oki_addr;
    logic [63:0] oki_data;
    logic signed [15:0] snd;
    logic [15:0] c_lat, c_ym, c_oki, c_irq;

    rshark_sound dut (
        .clk(clk), .reset(reset), .ce_4m(ce_4m), .ce_1m(ce_1m), .latch(latch),
        .rom_we(1'b0), .rom_waddr('0), .rom_wdata('0),
        .oki_req(oki_req), .oki_addr(oki_addr), .oki_ack(oki_ack), .oki_data(oki_data),
        .snd(snd), .dbg_latch_reads(c_lat), .dbg_ym_writes(c_ym), .dbg_oki_writes(c_oki), .dbg_z80_irqs(c_irq));

    // OKI ROM
    logic [7:0] oki_rom [0:262143];
    initial $readmemh("local/sim/oki.hex", oki_rom);
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
        fd = $fopen("local/traces/sound_trace.txt", "r");
        if (fd == 0) begin $display("FAIL M16_SOUND: no local/traces/sound_trace.txt"); $finish; end
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
        afd = $fopen("build/sim/sound.raw", "wb");
        $display("trace: %0d latch writes, %0d Z80 chip writes", lat_t.size(), w_t.size());
        repeat (4) @(posedge clk);
        reset <= 0;       // MAME starts both CPUs at time 0
    end

    // time in microseconds since reset release: 8 clocks per us
    longint clks = 0;
    always @(posedge clk) if (!reset) clks++;
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

    always @(posedge clk) if (ce_1m && !reset) $fwrite(afd, "%c%c", snd[7:0], snd[15:8]);

    always @(posedge clk) if (t_us >= run_ms * 1000.0) finish_run();

    task automatic finish_run();
        int expected;
        expected = 0;
        while (expected < w_t.size() && w_t[expected] <= t_us) expected++;
        $fclose(afd);
        if (errors == 0 && wi > 0 && (wi == expected || wi == expected - 1 || wi == expected + 1))
            $display("PASS M16_SOUND: %.0f ms, %0d YM/OKI writes identical to MAME in order (MAME %0d by now, max time offset %.1f us); latch reads %0d, Z80 IRQs %0d, latch values replayed %0d",
                t_us / 1000.0, wi, expected, maxdt, c_lat, c_irq, li);
        else
            $display("FAIL M16_SOUND: %0d mismatches, %0d writes (MAME %0d by %.0f ms), max time offset %.1f us, Z80 IRQs %0d",
                errors, wi, expected, t_us / 1000.0, maxdt, c_irq);
        $finish;
    endtask
endmodule
