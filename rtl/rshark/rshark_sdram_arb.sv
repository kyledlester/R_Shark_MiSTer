// R-Shark MiSTer core -- SDRAM channel-1 arbiter.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// One outstanding access on rtl/vendor/sdram.sv channel 1 (reads: 4-word burst, writes: one word
// with byte enables). Clients hold req (and their address) until they receive a one-clock ack;
// read data (64 bits, first word in [15:0]) is valid with the ack.
// Fixed priority: 0 loader (writes, download only), 1 OKI, 2 tilemap engine, 3 sprite engine.
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
    typedef enum logic [1:0] {IDLE, WAIT, CAPTURE, GAP} st_t;
    st_t st;
    logic [1:0] owner;
    logic       owner_we;

    always_ff @(posedge clk) begin
        ack    <= '0;
        sd_req <= 1'b0;
        if (rst) begin
            st <= IDLE;
        end else case (st)
            IDLE: if (req != 0) begin
                logic [1:0] c;
                c = req[0] ? 2'd0 : req[1] ? 2'd1 : req[2] ? 2'd2 : 2'd3;
                owner    <= c;
                owner_we <= we[c];
                sd_addr  <= {1'b0, addr[c]};
                sd_rnw   <= !we[c];
                sd_din   <= wdata;
                sd_be    <= wbe;
                sd_req   <= 1'b1;
                st       <= WAIT;
            end
            WAIT: if (sd_ready) begin
                if (owner_we) begin
                    ack[owner] <= 1'b1;
                    st <= GAP;
                end else
                    st <= CAPTURE;
            end
            CAPTURE: begin
                rdata      <= sd_dout;
                ack[owner] <= 1'b1;
                st         <= GAP;
            end
            GAP: st <= IDLE;            // the client drops req on the clock after its ack
        endcase
    end
endmodule
