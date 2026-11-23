# SpikeRoute — 2×2 multicast spike-packet router

Status: **RTL and directed Track B smoke complete; project verification and performance characterization remain in progress.** This is a four-router mesh with masked-key multicast routing, per-output round-robin arbitration, credit flow control, and all-or-nothing multicast grants.

## Reproduce

```sh
make lint
make test       # cocotb single-router + mesh smoke, CDG self-test, SymbiYosys proof
make results    # refresh mesh smoke latency CSV/plot and generic Yosys cell-count proxy
make clean
```

Requires Verilator, cocotb 1.9.2, Python 3, and for `make test`, Yosys/SymbiYosys with z3. `make smoke` omits formal for environments without SymbiYosys.

## Design

Ports are N/E/S/W/Local = 0..4 and each flit is `{key[15:0],payload[15:0]}`. Routing is masked-key table lookup with default opposite-port forwarding for transit packets, credit flow control, and atomic multicast grants.

## Evidence pack (Rule Zero)

| Evidence | Current result | Artifact |
|---|---|---|
| Verilator lint | PASS | reproducible with `make lint` |
| Single-router directed tests | PASS: table/default unicast, local drop, multicast fan-out 2/4, credit stall/recovery | `results/router_coverage.txt` |
| 2×2 integration | PASS: one directed R0-local→R1-local transfer | `results/mesh_smoke.txt`, `results/latency_throughput.csv` |
| Formal | PASS by k-induction at reduced single-router parameterization, depth-6 basecase | `results/formal_summary.txt`, `results/formal_basecase.log`, `results/formal_induction.log` |
| CDG tool | self-test accepts acyclic sample and rejects cyclic sample | `results/cdg_test.txt` |
| Generic synthesis | Yosys mapped generic cell count only; no physical area/timing/power | `results/ppa.json`, `results/ppa_summary.txt` |

**Important boundaries:** the formal assertions cover FIFO and credit counter upper bounds plus grant/output consistency. They do not prove end-to-end exact packet conservation, bounded round-robin fairness, or whole-mesh deadlock freedom. The current network result is one directed smoke packet; no random/hotspot/bursty injection-rate or saturation sweep has been performed. The CSV's reciprocal latency is not saturated throughput. The CDG self-test is not a proof for arbitrary routing tables. No OpenROAD/OpenSTA or commercial UVM run is reported. Keep these limitations attached to any claims.

## Verification flows

- **Track B (implemented):** cocotb + Verilator, Yosys generic synthesis, SymbiYosys/z3 on reduced single-router safety properties.
- **Track A (documented porting plan):** `tb_uvm/README.md`; no UVM testbench execution claimed.

## License

Apache-2.0. See [LICENSE](LICENSE).
