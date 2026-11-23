module router_formal;
    localparam int P = 5;
    localparam int D = 2;
    localparam int E = 2;
    (* gclk *) logic clk;
    (* anyseq *) logic rst_n;
    (* anyseq *) logic [P-1:0] in_valid;
    (* anyseq *) logic [P*32-1:0] in_data;
    (* anyseq *) logic [P-1:0] out_ready;
    (* anyseq *) logic [P-1:0] credit_ret;
    (* anyseq *) logic tbl_we;
    (* anyseq *) logic [$clog2(E)-1:0] tbl_idx;
    (* anyseq *) logic [15:0] tbl_key, tbl_mask;
    (* anyseq *) logic [P-1:0] tbl_port_mask;
    logic [P-1:0] in_ready, out_valid, fifo_pop;
    logic [P*32-1:0] out_data;
    logic [31:0] forwarded_cnt, dropped_cnt, stalled_cnt;

    router #(.FIFO_DEPTH(D), .NUM_ENTRIES(E)) dut (
        .clk, .rst_n, .in_valid, .in_ready, .in_data,
        .out_valid, .out_ready, .out_data, .credit_ret, .fifo_pop,
        .tbl_we, .tbl_idx, .tbl_key, .tbl_mask, .tbl_port_mask,
        .forwarded_cnt, .dropped_cnt, .stalled_cnt
    );

    logic past_valid = 1'b0;
    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) assume(!rst_n);
        else assume(rst_n);

    end
endmodule
