# SpikeRoute — Multicast-Capable Spike-Packet Router Mesh

[![CI](https://github.com/katepallewarprathmesh-sketch/SpikeRoute/actions/workflows/ci.yml/badge.svg)](https://github.com/katepallewarprathmesh-sketch/SpikeRoute/actions/workflows/ci.yml)

A four-router 2×2 mesh for event-driven systems. Each router provides five-port masked-key lookup, per-output round-robin arbitration, credit flow control, and atomic multicast grants.

## Design highlights

- 32-bit spike flit: `{key[15:0], payload[15:0]}`.
- Ports: N, E, S, W, Local; transit default route forwards to the opposite port.
- Table-driven fan-out with all-selected-outputs grant as one atomic action.
- Credit return follows downstream FIFO pops on internal mesh links.
- CDG utility accepts an acyclic sample and rejects a deliberately cyclic sample.

## Verified results

| Area | Result | Evidence |
|---|---|---|
| Verilator lint | PASS | `make lint` |
| Single-router cocotb | PASS: table/default route, local drop, fan-out 2/4, credit stall and recovery | `results/router_coverage.txt` |
| 2×2 mesh integration | PASS: directed R0-local → R1-local transfer | `results/mesh_smoke.txt` |
| Directed transfer latency | 2 cycles for the measured single-packet smoke | `results/latency_throughput.csv` |
| Reduced-router safety proof | PASS by k-induction, depth-6 basecase | `results/formal_summary.txt`, `results/formal_*.log` |
| Generic Yosys synthesis | 8,898 generic cells | `results/ppa.json`, `results/ppa_summary.txt` |

The formal assertions cover FIFO and credit upper bounds plus grant/output consistency in the reduced single-router instance. The current latency point is a directed smoke measurement; offered-load saturation and traffic-pattern curves are the next characterization milestone. The generic cell count is a structural synthesis result.

## Reproduce

```sh
make lint
make test       # router + mesh cocotb, CDG self-test, formal
make results    # refresh smoke latency table/plot and generic synthesis count
make clean
```

Requirements: Verilator, cocotb 1.9.2, Python 3; `make test` additionally uses Yosys, SymbiYosys and z3. `make smoke` runs the simulation and CDG checks without formal.

## Roadmap

Extend the traffic bench with uniform, hotspot and bursty patterns; add fan-out and injection-rate sweeps; and measure contention fairness and destination-set delivery under multi-packet traffic.

## License

Apache-2.0. See [LICENSE](LICENSE).
