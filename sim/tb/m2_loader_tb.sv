// M2: ROM download path. The complete MRA stream (local/rshark.rom, scripts/romtool.py stream) is fed
// through the hps_io WIDE ioctl protocol into rshark_loader -> rshark_sdram_arb -> sdram.sv -> chip
// model. Afterwards every SDRAM word must equal scripts/romtool.py's SDRAM image
// (local/sim/sdram_be.bin) and every BRAM write must equal maincpu.hex / audiocpu.hex.
`timescale 1ns/1ps
module m2_loader_tb;
    logic clk = 0;
    always #5.298 clk = ~clk;
    logic init = 1;

    logic ioctl_download = 0, ioctl_wr = 0, ioctl_wait;
    logic [26:0] ioctl_addr;
    logic [15:0] ioctl_dout;
    logic ld_req, ld_ack;
    logic [25:1] ld_addr;
    logic [15:0] ld_wdata;
    logic rom68_we, romz80_we, loaded;
    logic [16:0] rom68_addr; logic [15:0] rom68_data, romz80_addr; logic [7:0] romz80_data;

    rshark_loader dut (
        .clk(clk), .rst(init), .ioctl_download(ioctl_download), .ioctl_index(16'd0), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_wait(ioctl_wait),
        .mem_req(ld_req), .mem_addr(ld_addr), .mem_wdata(ld_wdata), .mem_ack(ld_ack),
        .rom68_we(rom68_we), .rom68_addr(rom68_addr), .rom68_data(rom68_data),
        .romz80_we(romz80_we), .romz80_addr(romz80_addr), .romz80_data(romz80_data), .loaded(loaded));

    logic [3:0] ack; logic [63:0] rdata;
    logic [26:1] sd_addr; logic [15:0] sd_din; logic [1:0] sd_be; logic sd_req, sd_rnw, sd_ready;
    logic [63:0] sd_dout;
    logic [25:1] arb_addr [4];
    assign arb_addr[0] = ld_addr; assign arb_addr[1] = '0; assign arb_addr[2] = '0; assign arb_addr[3] = '0;
    rshark_sdram_arb arb (
        .clk(clk), .rst(init), .req({3'b000, ld_req}), .addr(arb_addr), .we(4'b0001),
        .wdata(ld_wdata), .wbe(2'b11), .ack(ack), .rdata(rdata),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_req(sd_req), .sd_rnw(sd_rnw),
        .sd_dout(sd_dout), .sd_ready(sd_ready));
    assign ld_ack = ack[0];

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

    logic [15:0] m68 [0:131071];
    logic [7:0]  z80 [0:65535];
    logic [15:0] exp68 [0:131071];
    logic [7:0]  expz80 [0:65535];
    always @(posedge clk) begin
        if (rom68_we) m68[rom68_addr] <= rom68_data;
        if (romz80_we) z80[romz80_addr] <= romz80_data;
    end

    initial begin
        int fd, n, errors, checked;
        logic [7:0] b0, b1;
        longint t0;
        string dir, stream;
        if (!$value$plusargs("SIMDIR=%s", dir)) dir = "local/sim";
        if (!$value$plusargs("STREAM=%s", stream)) stream = "local/rshark.rom";
        $readmemh({dir, "/maincpu.hex"}, exp68);
        $readmemh({dir, "/audiocpu.hex"}, expz80);
        repeat (4) @(posedge clk);
        init <= 0;
        repeat (13000) @(posedge clk);                    // SDRAM start-up
        fd = $fopen(stream, "rb");
        if (fd == 0) begin $display("FAIL M2_LOADER: no %s", stream); $finish; end
        ioctl_download <= 1;
        n = 0;
        while ($fread(b0, fd) == 1) begin
            void'($fread(b1, fd));
            @(posedge clk);
            while (ioctl_wait) @(posedge clk);
            ioctl_addr <= 2 * n; ioctl_dout <= {b1, b0}; ioctl_wr <= 1;
            @(posedge clk);
            ioctl_wr <= 0;
            n++;
        end
        $fclose(fd);
        @(posedge clk); while (ioctl_wait) @(posedge clk);
        repeat (20) @(posedge clk);
        ioctl_download <= 0;
        $display("streamed %0d words, loaded=%0d", n, loaded);
        // SDRAM image
        errors = 0; checked = 0;
        fd = $fopen({dir, "/sdram_be.bin"}, "rb");
        for (int k = 0; ; k++) begin
            logic [15:0] w;
            logic [15:0] got;
            if ($fread(w, fd) != 2) break;
            got = chip.mem.exists(k) ? chip.mem[k] : 16'hA5C3;
            // unwritten words: the image has 0 there (colour words' high bytes are written as 00)
            if (got !== w && !(w == 16'h0000 && !chip.mem.exists(k))) begin
                errors++;
                if (errors <= 8) $display("SDRAM word %06x: got %04x expected %04x", k, got, w);
            end
            checked++;
        end
        $fclose(fd);
        for (int i = 0; i < 131072; i++) if (m68[i] !== exp68[i]) begin errors++; if (errors <= 12) $display("68k ROM %05x: %04x vs %04x", i, m68[i], exp68[i]); end
        for (int i = 0; i < 65536; i++) if (z80[i] !== expz80[i]) begin errors++; if (errors <= 16) $display("Z80 ROM %04x: %02x vs %02x", i, z80[i], expz80[i]); end
        if (errors == 0 && loaded)
            $display("PASS M2_LOADER: %s: %0d stream words -> %0d SDRAM words, 131072 68000 ROM words, 65536 Z80 ROM bytes identical to romtool images", stream, n, checked);
        else
            $display("FAIL M2_LOADER: %0d errors (loaded=%0d)", errors, loaded);
        $finish;
    end
endmodule
