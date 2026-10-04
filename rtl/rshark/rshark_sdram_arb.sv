// R-Shark MiSTer core -- SDRAM channel-1 arbiter.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Clients hold req (and their address) until they receive a one-clock ack; read data (64 bits,
// first word in [15:0]) is valid with the ack. Fixed priority: 0 loader (writes, download only),
// 1 OKI, 2 tilemap engine, 3 sprite engine.
// Chaining: when the controller signals completion of one access, the next client's request is
// issued in the same clock (sdram.sv latches ch1_req and accepts it on its next idle state), so a
// different client's access overlaps the capture/acknowledge of the previous one.
// A client is not eligible again until it has seen its ack and dropped req (block mask).
// sdram.sv raises ch1_ready one clock before the last burst word reaches ch1_dout, so read data is
// captured one clock after ready.
module rshark_sdram_arb (
    input  logic        clk,
    input  logic        rst,

    input  logic  [3:0] req,
    input  logic [25:1] addr [4],
    input  logic  [3:0] we,
    input  logic [15:0] wdata,          // client 0 only
    input  logic  [1:0] wbe,            // client 0 only
    output logic  [3:0] ack,
    output logic [63:0] rdata,

    output logic [26:1] sd_addr,
    output logic [15:0] sd_din,
    output logic  [1:0] sd_be,
    output logic        sd_req,
    output logic        sd_rnw,
    input  logic [63:0] sd_dout,
    input  logic        sd_ready
);
    logic       busy;           // an access is in the controller
    logic [1:0] owner;
    logic       owner_we;
    logic       cap;            // capture read data for cap_owner this clock
    logic [1:0] cap_owner;
    logic [3:0] block;

    wire [3:0] avail = req & ~block & ~(busy ? (4'b0001 << owner) : 4'b0000);
    wire [1:0] pick  = avail[0] ? 2'd0 : avail[1] ? 2'd1 : avail[2] ? 2'd2 : 2'd3;
    wire       done  = busy && sd_ready;
    wire       issue = (avail != 0) && (!busy || done);

    always_ff @(posedge clk) begin
        ack    <= '0;
        sd_req <= 1'b0;
        if (rst) begin
            busy  <= 1'b0;
            cap   <= 1'b0;
            block <= '0;
        end else begin
            block <= block & req;
            // completion of the access in flight
            cap <= 1'b0;
            if (done) begin
                block[owner] <= 1'b1;          // not eligible until it has dropped req after its ack
                if (owner_we) begin
                    ack[owner]   <= 1'b1;
                end else begin
                    cap       <= 1'b1;
                    cap_owner <= owner;
                end
            end
            if (cap) begin
                rdata          <= sd_dout;
                ack[cap_owner] <= 1'b1;
            end
            // next access
            if (issue) begin
                owner    <= pick;
                owner_we <= we[pick];
                sd_addr  <= {1'b0, addr[pick]};
                sd_rnw   <= !we[pick];
                sd_din   <= wdata;
                sd_be    <= wbe;
                sd_req   <= 1'b1;
                busy     <= 1'b1;
            end else if (done)
                busy <= 1'b0;
        end
    end
endmodule
