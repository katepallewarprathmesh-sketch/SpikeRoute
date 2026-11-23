# Toolchain (reproduced environment)

| Tool | Version | Use |
|---|---:|---|
| Verilator | 5.032 | lint and cocotb simulation |
| Icarus Verilog | 12.0 | installed; alternate simulator, not exercised in current regression |
| Yosys | 0.52 | generic synthesis statistics |
| SymbiYosys | source checkout, installed locally | bounded basecase + k-induction |
| SMT solver | z3 5.4.1 | formal backend |
| cocotb | 1.9.2 | Track B testbench |
| Python | 3.13.18 | scripts and tests |
| NumPy | 2.3.5 | available; not required by SpikeRoute RTL test |
| matplotlib | 3.11.2 | results plot |

Versions describe the verified workspace, not a machine-independent lockfile. No OpenROAD/OpenSTA timing or power flow is run; no PPA/signoff claim is made. VCS/Questa and UVM are not available in this environment.
