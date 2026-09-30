// R-Shark MiSTer core -- 68000 main board.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// MAME 0.289 rshark_state::rshark_map (docs/MEMORY_MAP.md): FX68K at 8 MHz (phi1/phi2 enables),
// program ROM / work RAM / sprite RAM in block RAM (zero wait states), I/O, sound latch, control
// byte, 4 x 8 tilemap control registers, palette write port, IRQ5/IRQ6 (HOLD_LINE semantics:
// pending until the 68000 acknowledges that level; autovectored), and the vblank sprite-buffer copy
// which builds the sprite engine's Y / attribute tables.
module rshark_main (
    input  logic        clk,
    input  logic        reset,
    input  logic        phi1,
    input  logic        phi2,

    // program ROM download (word address, big-endian 68000 words)
    input  logic        rom_we,
    input  logic [16:0] rom_waddr,
    input  logic [15:0] rom_wdata,

    // raster events (one clk each, start of the line)
    input  logic        irq5_evt,       // line 248
    input  logic        irq6_evt,       // line 120
    input  logic        vblank_evt,     // line 248: sprite copy + tilemap register latch

    input  logic [15:0] dsw,            // MAME port values (active low)
    input  logic [15:0] p1p2,
    input  logic  [7:0] system,

    output logic  [7:0] snd_latch,
    output logic        snd_latch_wr,
    output logic        flip,
    output logic        bg1_pri,
    output logic  [7:0] ctrl_byte,
    output logic [255:0] tm_regs,       // latched at vblank: layer*64 + reg*8 (bg0,bg1,fg0,fg1)

    // palette write port (palette RAM lives in the video block)
    output logic  [1:0] pal_we,
    output logic [10:0] pal_addr,
    output logic [15:0] pal_wdata,

    // sprite tables for the renderer (registered reads, 1 clk)
    input  logic  [7:0] ytab_addr,
    output logic [13:0] ytab_data,      // {en, h[3:0], y[8:0]}
    input  logic  [7:0] atab_addr,
    output logic [32:0] atab_data,      // {w[3:0], x[8:0], code[15:0], colour[3:0]}
    output logic        spr_copy_busy,

    // debug
    output logic [23:0] dbg_pc,         // address of the last program-space fetch
    output logic [15:0] dbg_irq5,
    output logic [15:0] dbg_irq6,
    output logic [15:0] dbg_frames,
    output logic [15:0] dbg_latch_writes
);
    // ------------------------------------------------------------------ CPU
    logic [2:0]  irq_level;
    logic        iack_service, iack_active, vpa_n;
    logic [2:0]  iack_level;
    logic        cpu_req, cpu_write;
    logic [23:0] cpu_addr;
    logic [15:0] cpu_wdata, cpu_rdata;
    logic [1:0]  cpu_be;
    logic        cpu_ack;
    logic [71:0] dbg_native;

    rshark_cpu68k cpu (
        .clk_sys(clk), .reset(reset), .en_phi1(phi1), .en_phi2(phi2),
        .irq_level(irq_level), .iack_service(iack_service), .iack_level(iack_level),
        .iack_active(iack_active), .vpa_n(vpa_n),
        .cpu_req(cpu_req), .cpu_write(cpu_write), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_byte_en(cpu_be), .cpu_rdata(cpu_rdata), .cpu_ack(cpu_ack),
        .debug_native(dbg_native)
    );

    // program fetches (FC = 010 user program / 110 supervisor program) for the debug PC
    wire [2:0] fc = dbg_native[65:63];
    always_ff @(posedge clk)
        if (!dbg_native[57] && fc[1:0] == 2'b10) dbg_pc <= dbg_native[23:0];

    // ------------------------------------------------------------------ decode (A23-A20 ignored)
    wire [19:0] a = cpu_addr[19:0];
    wire sel_rom = a[19:18] == 2'b00;
    wire sel_spr = a[19:12] == 8'h4D;
    wire sel_ram = a[19:16] == 4'h4 && !sel_spr;
    wire sel_c0  = a[19:12] == 8'hC0;
    wire sel_bg  = a[19:5]  == 15'h6200;        // C4000-C401F
    wire sel_pal = a[19:12] == 8'hC8;
    wire sel_fg  = a[19:5]  == 15'h6600;        // CC000-CC01F

    // ------------------------------------------------------------------ memories
    logic [15:0] rom_q, ram_q, spr_q;
    logic        acc_we;                        // the one-clock write strobe of an accepted write

    rshark_sdpram #(.AW(17), .DW(16)
`ifdef RSHARK_SIM_ROM
        , .INIT(`RSHARK_SIM_ROM)
`endif
    ) rom (
        .clk(clk), .w_addr(rom_waddr), .we(rom_we), .din(rom_wdata),
        .r_addr(a[17:1]), .dout(rom_q));

    rshark_spram16 #(.AW(15)) ram (
        .clk(clk), .addr(a[15:1]), .we({2{acc_we && sel_ram}} & cpu_be), .din(cpu_wdata), .dout(ram_q));

    // sprite RAM: 8 x (256 x 16) RAMs, one per word of an entry, so the vblank copy reads a whole
    // entry per clock (256 clocks). CPU on port A (byte lanes), copy engine on port B.
    logic [7:0]  copy_entry;
    logic [15:0] copy_w [8];
    logic [15:0] spr_w [8];
    logic [2:0]  spr_sel;
    for (genvar w = 0; w < 8; w++) begin : spr_words
        rshark_dpram #(.AW(8), .DW(8)) hi (
            .clk(clk), .a_addr(a[11:4]), .a_we(acc_we && sel_spr && a[3:1] == w && cpu_be[1]),
            .a_din(cpu_wdata[15:8]), .a_dout(spr_w[w][15:8]), .b_addr(copy_entry), .b_dout(copy_w[w][15:8]));
        rshark_dpram #(.AW(8), .DW(8)) lo (
            .clk(clk), .a_addr(a[11:4]), .a_we(acc_we && sel_spr && a[3:1] == w && cpu_be[0]),
            .a_din(cpu_wdata[7:0]), .a_dout(spr_w[w][7:0]), .b_addr(copy_entry), .b_dout(copy_w[w][7:0]));
    end
    assign spr_q = spr_w[a[3:1]];

    // ------------------------------------------------------------------ bus backend
    typedef enum logic [1:0] {B_IDLE, B_READ1, B_READ2, B_END} bstate_t;
    bstate_t bst;
    // A sprite RAM write to an entry the vblank copy has not read yet waits, so the copy is an
    // atomic snapshot of sprite RAM at the vblank instant, as MAME's buffered_spriteram16 copy.
    // (Reads never wait; the copy takes 256 clocks = 2.7 us.)
    logic copying;
    wire  spr_hold = sel_spr && cpu_write && (vblank_evt || (copying && a[11:4] >= copy_entry));
    wire  accept = bst == B_IDLE && cpu_req && !spr_hold;
    assign acc_we = accept && cpu_write;

    logic [7:0] regs_live [0:31];
    always_ff @(posedge clk) begin
        cpu_ack      <= 1'b0;
        snd_latch_wr <= 1'b0;
        if (reset) begin
            bst <= B_IDLE;
            ctrl_byte <= 8'h00;
            snd_latch <= 8'h00;
            dbg_latch_writes <= '0;
            for (int i = 0; i < 32; i++) regs_live[i] <= 8'h00;
        end else begin
            case (bst)
                B_IDLE: if (accept) begin
                    if (cpu_write) begin
                        if (sel_c0 && a[11:1] == 11'h009 && cpu_be[0]) begin   // C0012/C0013
                            snd_latch    <= cpu_wdata[7:0];
                            snd_latch_wr <= 1'b1;
                            dbg_latch_writes <= dbg_latch_writes + 16'd1;
                        end
                        if (sel_c0 && a[11:1] == 11'h00A && cpu_be[0])       // C0014/C0015
                            ctrl_byte <= cpu_wdata[7:0];
                        if ((sel_bg || sel_fg) && cpu_be[0])
                            regs_live[{sel_fg, a[4], a[3:1]}] <= cpu_wdata[7:0];
                        cpu_ack <= 1'b1;
                        bst <= B_END;
                    end else
                        bst <= B_READ1;
                end
                B_READ1: bst <= B_READ2;
                B_READ2: begin
                    cpu_rdata <= sel_rom ? rom_q :
                                 sel_ram ? ram_q :
                                 sel_spr ? spr_q :
                                 (sel_c0 && a[11:1] == 11'h001) ? dsw :
                                 (sel_c0 && a[11:1] == 11'h002) ? p1p2 :
                                 (sel_c0 && a[11:1] == 11'h003) ? {8'h00, system} :
                                 16'h0000;                      // unmapped: MAME unmap_value 0
                    cpu_ack <= 1'b1;
                    bst <= B_END;
                end
                B_END: if (!cpu_req) bst <= B_IDLE;
            endcase
        end
    end

    assign flip    = ctrl_byte[0];
    assign bg1_pri = ctrl_byte[4];

    assign pal_we    = {2{acc_we && sel_pal}} & cpu_be;
    assign pal_addr  = a[11:1];
    assign pal_wdata = cpu_wdata;

    // ------------------------------------------------------------------ interrupts
    logic pend5, pend6;
    always_ff @(posedge clk) begin
        if (reset) begin
            pend5 <= 1'b0; pend6 <= 1'b0;
            dbg_irq5 <= '0; dbg_irq6 <= '0;
        end else begin
            if (iack_service && iack_level == 3'd5) begin pend5 <= 1'b0; dbg_irq5 <= dbg_irq5 + 16'd1; end
            if (iack_service && iack_level == 3'd6) begin pend6 <= 1'b0; dbg_irq6 <= dbg_irq6 + 16'd1; end
            if (irq5_evt) pend5 <= 1'b1;
            if (irq6_evt) pend6 <= 1'b1;
        end
    end
    assign irq_level = pend6 ? 3'd6 : pend5 ? 3'd5 : 3'd0;

    // ------------------------------------------------------------------ vblank copy + register latch
    logic        rd_valid;
    logic [7:0]  rd_entry;
    logic        ytab_we;
    logic [7:0]  tab_waddr;
    logic [13:0] ytab_wdata;
    logic [32:0] atab_wdata;

    assign spr_copy_busy = copying || vblank_evt;

    always_ff @(posedge clk) begin
        ytab_we <= 1'b0;
        if (reset) begin
            copying <= 1'b0; copy_entry <= '0; rd_valid <= 1'b0;
            dbg_frames <= '0;
            tm_regs <= '0;
        end else begin
            if (vblank_evt && !copying) begin
                copying    <= 1'b1;
                copy_entry <= '0;
                rd_valid   <= 1'b0;
                dbg_frames <= dbg_frames + 16'd1;
                for (int i = 0; i < 32; i++) tm_regs[i*8 +: 8] <= regs_live[i];
            end else if (copying) begin
                // entry copy_entry is read this clock; its words arrive next clock
                rd_valid <= 1'b1;
                rd_entry <= copy_entry;
                if (copy_entry != 8'd255) copy_entry <= copy_entry + 8'd1;
                if (rd_valid) begin
                    ytab_we    <= 1'b1;
                    tab_waddr  <= rd_entry;
                    ytab_wdata <= {copy_w[0][0], copy_w[1][7:4], copy_w[6][8:0]};
                    atab_wdata <= {copy_w[1][3:0], copy_w[4][8:0], copy_w[3], copy_w[7][3:0]};
                    if (rd_entry == 8'd255) begin
                        copying  <= 1'b0;
                        rd_valid <= 1'b0;
                    end
                end
            end
        end
    end

    rshark_sdpram #(.AW(8), .DW(14)) ytab (
        .clk(clk), .w_addr(tab_waddr), .we(ytab_we), .din(ytab_wdata), .r_addr(ytab_addr), .dout(ytab_data));
    rshark_sdpram #(.AW(8), .DW(33)) atab (
        .clk(clk), .w_addr(tab_waddr), .we(ytab_we), .din(atab_wdata), .r_addr(atab_addr), .dout(atab_data));
endmodule
