// mesh_2x2.sv
// 2x2 mesh of SpikeRoute routers. Coordinates (x,y), x,y in {0,1}.
// Ports: 0=N(+y), 1=E(+x), 2=S(-y), 3=W(-x), 4=Local.
//   R(0,0): N->R(0,1).S, E->R(1,0).W, S/W edge, Local 0
//   R(1,0): N->R(1,1).S, W->R(0,0).E, S/E edge, Local 1
//   R(0,1): S->R(0,0).N, E->R(1,1).W, N/W edge, Local 2
//   R(1,1): S->R(1,0).N, W->R(0,1).E, N/E edge, Local 3
// Credit return between routers: B.fifo_pop[p] -> A.credit_ret[o].
// Edge ports are exposed for TB injection/collection; the TB returns
// their credits after consuming (credit_ret_edge).
`timescale 1ns/1ps

module mesh_2x2 #(
    parameter int FIFO_DEPTH = 4
) (
    input  logic        clk,
    input  logic        rst_n,

    // Local ports (4): index = router id (x + 2*y)
    input  logic [4*32-1:0]  local_in_data,
    input  logic [3:0]       local_in_valid,
    output logic [3:0]       local_in_ready,
    output logic [4*32-1:0]  local_out_data,
    output logic [3:0]       local_out_valid,
    input  logic [3:0]       local_out_ready,
    input  logic [3:0]       local_credit_ret,

    // Edge ports (8): order S0,W0,S1,E1,N2,W2,N3,E3 (router.port)
    input  logic [8*32-1:0]  edge_in_data,
    input  logic [7:0]       edge_in_valid,
    output logic [7:0]       edge_in_ready,
    output logic [8*32-1:0]  edge_out_data,
    output logic [7:0]       edge_out_valid,
    input  logic [7:0]       edge_out_ready,
    input  logic [7:0]       edge_credit_ret,

    // Table load per router (4 ports)
    input  logic [3:0]       tbl_we,
    input  logic [4*3-1:0]   tbl_idx,
    input  logic [4*16-1:0]  tbl_key,
    input  logic [4*16-1:0]  tbl_mask,
    input  logic [4*5-1:0]   tbl_pm,

    output logic [4*32-1:0]  forwarded_cnt,
    output logic [4*32-1:0]  dropped_cnt,
    output logic [4*32-1:0]  stalled_cnt
);
    // Per-router port bundles
    // NOTE: Verilator UNOPTFLAT warns of a combinational loop here, but
    // every router output is gated by registered FIFO state (head_valid
    // from fifo_cnt registers), so the loop is broken by registers.
    /* verilator lint_off UNOPTFLAT */
    logic [4:0]  r_in_valid [0:3], r_in_ready [0:3];
    logic [4:0]  r_out_valid [0:3], r_out_ready [0:3];
    logic [4:0]  r_credit_ret [0:3], r_fifo_pop [0:3];
    logic [159:0] r_in_data [0:3], r_out_data [0:3];

    genvar g;
    generate
        for (g = 0; g < 4; g++) begin : g_router
            router #(.FIFO_DEPTH(FIFO_DEPTH)) u_r (
                .clk(clk), .rst_n(rst_n),
                .in_valid(r_in_valid[g]), .in_ready(r_in_ready[g]),
                .in_data(r_in_data[g]),
                .out_valid(r_out_valid[g]), .out_ready(r_out_ready[g]),
                .out_data(r_out_data[g]),
                .credit_ret(r_credit_ret[g]), .fifo_pop(r_fifo_pop[g]),
                .tbl_we(tbl_we[g]), .tbl_idx(tbl_idx[g*3 +: 3]),
                .tbl_key(tbl_key[g*16 +: 16]), .tbl_mask(tbl_mask[g*16 +: 16]),
                .tbl_port_mask(tbl_pm[g*5 +: 5]),
                .forwarded_cnt(forwarded_cnt[g*32 +: 32]),
                .dropped_cnt(dropped_cnt[g*32 +: 32]),
                .stalled_cnt(stalled_cnt[g*32 +: 32])
            );
        end
    endgenerate

    // ---- Local ports: router lg port 4 ----
    always_comb begin
        for (int lg = 0; lg < 4; lg++) begin
            r_in_valid[lg][4]   = local_in_valid[lg];
            r_in_data[lg][4*32 +: 32] = local_in_data[lg*32 +: 32];
            local_in_ready[lg]  = r_in_ready[lg][4];
            local_out_valid[lg] = r_out_valid[lg][4];
            local_out_data[lg*32 +: 32] = r_out_data[lg][4*32 +: 32];
            r_out_ready[lg][4]  = local_out_ready[lg];
            r_credit_ret[lg][4] = local_credit_ret[lg];
        end
    end

    // ---- Internal links ----
    // R0.N(0) <-> R2.S(2); R0.E(1) <-> R1.W(3)
    // R1.N(0) <-> R3.S(2); R2.E(1) <-> R3.W(3)
    // (out_valid/data -> in_valid/data; in_ready -> out_ready;
    //  fifo_pop -> credit_ret)
    // R0 -> R2
    assign r_in_valid[2][2]   = r_out_valid[0][0];
    assign r_in_data[2][2*32 +: 32] = r_out_data[0][0*32 +: 32];
    assign r_out_ready[0][0]  = r_in_ready[2][2];
    assign r_credit_ret[0][0] = r_fifo_pop[2][2];
    // R2 -> R0
    assign r_in_valid[0][2]   = r_out_valid[2][2];
    assign r_in_data[0][2*32 +: 32] = r_out_data[2][2*32 +: 32];
    assign r_out_ready[2][2]  = r_in_ready[0][2];
    assign r_credit_ret[2][2] = r_fifo_pop[0][2];
    // R0 -> R1
    assign r_in_valid[1][3]   = r_out_valid[0][1];
    assign r_in_data[1][3*32 +: 32] = r_out_data[0][1*32 +: 32];
    assign r_out_ready[0][1]  = r_in_ready[1][3];
    assign r_credit_ret[0][1] = r_fifo_pop[1][3];
    // R1 -> R0
    assign r_in_valid[0][3]   = r_out_valid[1][3];
    assign r_in_data[0][3*32 +: 32] = r_out_data[1][3*32 +: 32];
    assign r_out_ready[1][3]  = r_in_ready[0][3];
    assign r_credit_ret[1][3] = r_fifo_pop[0][3];
    // R1 -> R3
    assign r_in_valid[3][2]   = r_out_valid[1][0];
    assign r_in_data[3][2*32 +: 32] = r_out_data[1][0*32 +: 32];
    assign r_out_ready[1][0]  = r_in_ready[3][2];
    assign r_credit_ret[1][0] = r_fifo_pop[3][2];
    // R3 -> R1
    assign r_in_valid[1][2]   = r_out_valid[3][2];
    assign r_in_data[1][2*32 +: 32] = r_out_data[3][2*32 +: 32];
    assign r_out_ready[3][2]  = r_in_ready[1][2];
    assign r_credit_ret[3][2] = r_fifo_pop[1][2];
    // R2 -> R3
    assign r_in_valid[3][3]   = r_out_valid[2][1];
    assign r_in_data[3][3*32 +: 32] = r_out_data[2][1*32 +: 32];
    assign r_out_ready[2][1]  = r_in_ready[3][3];
    assign r_credit_ret[2][1] = r_fifo_pop[3][3];
    // R3 -> R2
    assign r_in_valid[2][1]   = r_out_valid[3][1];
    assign r_in_data[2][1*32 +: 32] = r_out_data[3][1*32 +: 32];
    assign r_out_ready[3][1]  = r_in_ready[2][1];
    assign r_credit_ret[3][1] = r_fifo_pop[2][1];

    // ---- Edge ports: S0,W0,S1,E1,N2,W2,N3,E3 ----
    // R0.S(2), R0.W(3), R1.S(2), R1.E(1), R2.N(0), R2.W(3), R3.N(0), R3.E(1)
    logic [1:0] edge_r [0:7];
    logic [2:0] edge_p [0:7];
    always_comb begin
        edge_r[0] = 2'd0; edge_p[0] = 3'd2;
        edge_r[1] = 2'd0; edge_p[1] = 3'd3;
        edge_r[2] = 2'd1; edge_p[2] = 3'd2;
        edge_r[3] = 2'd1; edge_p[3] = 3'd1;
        edge_r[4] = 2'd2; edge_p[4] = 3'd0;
        edge_r[5] = 2'd2; edge_p[5] = 3'd3;
        edge_r[6] = 2'd3; edge_p[6] = 3'd0;
        edge_r[7] = 2'd3; edge_p[7] = 3'd1;
        for (int e = 0; e < 8; e++) begin
            r_in_valid[edge_r[e]][edge_p[e]]   = edge_in_valid[e];
            r_in_data[edge_r[e]][edge_p[e]*32 +: 32] = edge_in_data[e*32 +: 32];
            edge_in_ready[e]  = r_in_ready[edge_r[e]][edge_p[e]];
            edge_out_valid[e] = r_out_valid[edge_r[e]][edge_p[e]];
            edge_out_data[e*32 +: 32] = r_out_data[edge_r[e]][edge_p[e]*32 +: 32];
            r_out_ready[edge_r[e]][edge_p[e]]  = edge_out_ready[e];
            r_credit_ret[edge_r[e]][edge_p[e]] = edge_credit_ret[e];
        end
    end
endmodule
