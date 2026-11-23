// router.sv
// SpikeRoute single router: 5 ports (0=N, 1=E, 2=S, 3=W, 4=Local),
// single-flit 32-bit packets {key[31:16], payload[15:0]}.
//
// Features (see docs/spec.md):
//   - 5 input FIFOs (depth FIFO_DEPTH), in_ready = !full.
//   - Table-driven multicast: 8 entries {key, mask, port_mask[4:0]},
//     match when (pkt.key & mask) == (entry.key & mask), lowest wins.
//   - Default route: mesh-port arrivals go straight through (opposite
//     port); local injections with no match are dropped + counted.
//   - Credit-based flow control per output (init = FIFO_DEPTH,
//     saturating counter, credit_ret from downstream).
//   - Per-output round-robin arbitration.
//   - Atomic multicast grant: a packet forwards only when ALL target
//     outputs grant it in the same cycle (no hold-and-wait, ADR-0002).
//   - Counters: forwarded / dropped / stalled cycles.
`timescale 1ns/1ps

module router #(
    parameter int NUM_PORTS   = 5,
    parameter int FIFO_DEPTH  = 4,
    parameter int NUM_ENTRIES = 8,
    parameter int PKT_W       = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Input ports (from neighbors / local injector)
    input  logic [NUM_PORTS-1:0]  in_valid,
    output logic [NUM_PORTS-1:0]  in_ready,
    input  logic [NUM_PORTS*PKT_W-1:0] in_data,

    // Output ports (to neighbors / local sink)
    output logic [NUM_PORTS-1:0]  out_valid,
    input  logic [NUM_PORTS-1:0]  out_ready,
    output logic [NUM_PORTS*PKT_W-1:0] out_data,

    // Credit return from downstream (one pulse per consumed flit)
    input  logic [NUM_PORTS-1:0]  credit_ret,
    // FIFO pop pulses (mesh uses these to return credits upstream)
    output logic [NUM_PORTS-1:0]  fifo_pop,

    // Routing table load
    input  logic                  tbl_we,
    input  logic [$clog2(NUM_ENTRIES)-1:0] tbl_idx,
    input  logic [15:0]           tbl_key,
    input  logic [15:0]           tbl_mask,
    input  logic [NUM_PORTS-1:0]  tbl_port_mask,

    // Counters
    output logic [31:0]           forwarded_cnt,
    output logic [31:0]           dropped_cnt,
    output logic [31:0]           stalled_cnt
);
    localparam int PTR_W = $clog2(FIFO_DEPTH);
    localparam int CNT_W = $clog2(FIFO_DEPTH + 1);

    // ---------------- Routing table ----------------
    logic [15:0]          tbl_key_q   [0:NUM_ENTRIES-1];
    logic [15:0]          tbl_mask_q  [0:NUM_ENTRIES-1];
    logic [NUM_PORTS-1:0] tbl_pm_q    [0:NUM_ENTRIES-1];
    logic                 tbl_valid_q [0:NUM_ENTRIES-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                tbl_valid_q[i] <= 1'b0;
                tbl_key_q[i]   <= '0;
                tbl_mask_q[i]  <= '0;
                tbl_pm_q[i]    <= '0;
            end
        end else if (tbl_we) begin
            tbl_valid_q[tbl_idx] <= 1'b1;
            tbl_key_q[tbl_idx]   <= tbl_key;
            tbl_mask_q[tbl_idx]  <= tbl_mask;
            tbl_pm_q[tbl_idx]    <= tbl_port_mask;
        end
    end

    // ---------------- Input FIFOs ----------------
    logic [PKT_W-1:0] fifo_mem [0:NUM_PORTS-1][0:FIFO_DEPTH-1];
    logic [PTR_W-1:0] head_ptr [0:NUM_PORTS-1];
    logic [PTR_W-1:0] tail_ptr [0:NUM_PORTS-1];
    logic [CNT_W-1:0] fifo_cnt [0:NUM_PORTS-1];

    logic [NUM_PORTS-1:0] head_valid;
    logic [NUM_PORTS*PKT_W-1:0] head_data;

    genvar gp;
    generate
        for (gp = 0; gp < NUM_PORTS; gp++) begin : g_fifo
            assign in_ready[gp]  = (fifo_cnt[gp] != FIFO_DEPTH[CNT_W-1:0]);
            assign head_valid[gp] = (fifo_cnt[gp] != '0);
            assign head_data[gp*PKT_W +: PKT_W] = fifo_mem[gp][head_ptr[gp]];
        end
    endgenerate

    // ---------------- Route compute (per input) ----------------
    logic [NUM_PORTS-1:0] target_mask [0:NUM_PORTS-1];
    logic                 is_drop     [0:NUM_PORTS-1];

    function automatic logic [NUM_PORTS-1:0] opposite_port(input logic [2:0] p);
        case (p)
            3'd0: opposite_port = 5'b00100;  // N -> S
            3'd1: opposite_port = 5'b01000;  // E -> W
            3'd2: opposite_port = 5'b00001;  // S -> N
            3'd3: opposite_port = 5'b00010;  // W -> E
            default: opposite_port = '0;
        endcase
    endfunction

    always_comb begin
        for (int p = 0; p < NUM_PORTS; p++) begin
            logic [15:0] key;
            logic found;
            logic [NUM_PORTS-1:0] pm;
            key   = head_data[p*PKT_W + 16 +: 16];
            found = 1'b0;
            pm    = '0;
            for (int e = NUM_ENTRIES-1; e >= 0; e--) begin
                if (tbl_valid_q[e] &&
                    ((key & tbl_mask_q[e]) == (tbl_key_q[e] & tbl_mask_q[e]))) begin
                    pm    = tbl_pm_q[e];  // lowest index wins (last write)
                    found = 1'b1;
                end
            end
            if (found) begin
                target_mask[p] = pm;
                is_drop[p]     = 1'b0;
            end else if (p == 4) begin
                target_mask[p] = '0;      // local, no route: drop
                is_drop[p]     = 1'b1;
            end else begin
                target_mask[p] = opposite_port(p[2:0]);  // straight through
                is_drop[p]     = 1'b0;
            end
        end
    end

    // ---------------- Per-output round-robin arbiters ----------------
    logic [2:0] rr_ptr [0:NUM_PORTS-1];
    logic [NUM_PORTS-1:0] arb_sel [0:NUM_PORTS-1];  // one-hot per output

    always_comb begin
        for (int o = 0; o < NUM_PORTS; o++) begin
            logic [NUM_PORTS-1:0] req;
            logic [2:0] ptr;
            logic found;
            req = '0;
            for (int p = 0; p < NUM_PORTS; p++)
                req[p] = head_valid[p] && !is_drop[p] && target_mask[p][o];
            ptr   = rr_ptr[o];
            found = 1'b0;
            arb_sel[o] = '0;
            // Scan from rr_ptr, wrapping; first requester wins.
            // (Wide temp: 3-bit addition would wrap at 8 before the
            // mod-5 correction when ptr=4, k=4.)
            for (int k = 0; k < NUM_PORTS; k++) begin
                int cand_i;
                cand_i = int'(ptr) + k;
                if (cand_i >= NUM_PORTS) cand_i = cand_i - NUM_PORTS;
                if (!found && req[cand_i]) begin
                    arb_sel[o][cand_i] = 1'b1;
                    found = 1'b1;
                end
            end
        end
    end

    // ---------------- Credit counters ----------------
    logic [CNT_W-1:0] credit_cnt [0:NUM_PORTS-1];

    // ---------------- Atomic grant ----------------
    // NOTE: Verilator UNOPTFLAT reports grant -> out_valid -> (mesh
    // wiring) -> out_ready -> grant as circular, but in the mesh every
    // out_ready is a neighbor's in_ready = (fifo_cnt != depth), i.e.
    // gated by registers, so no combinational loop exists.
    /* verilator lint_off UNOPTFLAT */
    logic [NUM_PORTS-1:0] grant;
    logic [NUM_PORTS-1:0] drop;
    logic [NUM_PORTS-1:0] pop;

    always_comb begin
        for (int p = 0; p < NUM_PORTS; p++) begin
            logic ok;
            ok = head_valid[p] && !is_drop[p] && (target_mask[p] != '0);
            for (int o = 0; o < NUM_PORTS; o++) begin
                if (target_mask[p][o])
                    ok = ok && arb_sel[o][p] &&
                         (credit_cnt[o] != '0) && out_ready[o];
            end
            grant[p] = ok;
            drop[p]  = head_valid[p] && is_drop[p];
            pop[p]   = grant[p] || drop[p];
        end
    end
    assign fifo_pop = pop;

    // ---------------- Output crossbar (replication) ----------------
    always_comb begin
        out_valid = '0;
        out_data  = '0;
        for (int p = 0; p < NUM_PORTS; p++) begin
            if (grant[p]) begin
                for (int o = 0; o < NUM_PORTS; o++) begin
                    if (target_mask[p][o]) begin
                        out_valid[o] = 1'b1;
                        out_data[o*PKT_W +: PKT_W] =
                            head_data[p*PKT_W +: PKT_W];
                    end
                end
            end
        end
    end

    // ---------------- Sequential: FIFOs, credits, RR, counters ----------------
    logic [31:0] fwd_q, drop_q, stall_q;
    assign forwarded_cnt = fwd_q;
    assign dropped_cnt   = drop_q;
    assign stalled_cnt   = stall_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int p = 0; p < NUM_PORTS; p++) begin
                head_ptr[p] <= '0;
                tail_ptr[p] <= '0;
                fifo_cnt[p] <= '0;
            end
            for (int o = 0; o < NUM_PORTS; o++) begin
                credit_cnt[o] <= FIFO_DEPTH[CNT_W-1:0];
                rr_ptr[o]     <= '0;
            end
            fwd_q   <= 32'd0;
            drop_q  <= 32'd0;
            stall_q <= 32'd0;
        end else begin
            // FIFOs
            for (int p = 0; p < NUM_PORTS; p++) begin
                logic push, pop_p;
                push  = in_valid[p] && in_ready[p];
                pop_p = pop[p];
                if (push) begin
                    fifo_mem[p][tail_ptr[p]] <= in_data[p*PKT_W +: PKT_W];
                    tail_ptr[p] <= tail_ptr[p] + 1'b1;
                end
                if (pop_p)
                    head_ptr[p] <= head_ptr[p] + 1'b1;
                unique case ({push, pop_p})
                    2'b10:   fifo_cnt[p] <= fifo_cnt[p] + 1'b1;
                    2'b01:   fifo_cnt[p] <= fifo_cnt[p] - 1'b1;
                    default: fifo_cnt[p] <= fifo_cnt[p];
                endcase
            end
            // Credits (saturating at FIFO_DEPTH) + RR pointers
            for (int o = 0; o < NUM_PORTS; o++) begin
                logic grant_to_o;
                logic [CNT_W-1:0] nxt;
                grant_to_o = 1'b0;
                for (int p = 0; p < NUM_PORTS; p++)
                    grant_to_o = grant_to_o || (grant[p] && target_mask[p][o]);
                nxt = credit_cnt[o] + CNT_W'(credit_ret[o]) - CNT_W'(grant_to_o);
                if (nxt > FIFO_DEPTH[CNT_W-1:0])
                    credit_cnt[o] <= FIFO_DEPTH[CNT_W-1:0];
                else
                    credit_cnt[o] <= nxt;
                if (grant_to_o) begin
                    for (int p = 0; p < NUM_PORTS; p++)
                        if (grant[p] && target_mask[p][o])
                            rr_ptr[o] <= (p == NUM_PORTS-1) ? 3'd0 : 3'(p+1);
                end
            end
            // Counters
            fwd_q <= fwd_q + 32'(popcount(grant));
            drop_q <= drop_q + 32'(popcount(drop));
            if (|(head_valid & ~pop))
                stall_q <= stall_q + 32'd1;
        end
    end

`ifdef FORMAL
    // Safety invariants proved with SymbiYosys. Inputs are unconstrained:
    // stalls, malformed return pulses, and table updates cannot overflow.
    always_ff @(posedge clk) begin
        if (rst_n) begin
            for (int fp = 0; fp < NUM_PORTS; fp++) begin
                assert(fifo_cnt[fp] <= FIFO_DEPTH);
                assert(credit_cnt[fp] <= FIFO_DEPTH);
                if (grant[fp]) begin
                    assert(head_valid[fp]);
                    assert(target_mask[fp] != '0);
                    for (int fo = 0; fo < NUM_PORTS; fo++) begin
                        if (target_mask[fp][fo]) begin
                            assert(arb_sel[fo][fp]);
                            assert(credit_cnt[fo] != 0);
                            assert(out_valid[fo]);
                            assert(out_data[fo*PKT_W +: PKT_W] ==
                                   head_data[fp*PKT_W +: PKT_W]);
                        end
                    end
                end
            end
        end
    end
`endif

    function automatic int popcount(input logic [NUM_PORTS-1:0] v);
        int c;
        c = 0;
        for (int i = 0; i < NUM_PORTS; i++) c += v[i] ? 1 : 0;
        popcount = c;
    endfunction
endmodule
