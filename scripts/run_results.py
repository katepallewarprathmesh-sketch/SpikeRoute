#!/usr/bin/env python3
"""Reproducible Yosys generic synthesis and plotted smoke measurements.

No technology library or OpenROAD/OpenSTA is used: generic cell count is a
structural proxy only. Network CSV is a single directed integration smoke,
not a saturation or traffic-pattern sweep.
"""
import csv
import json
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "results")
os.makedirs(RESULTS, exist_ok=True)
cmd = ["yosys", "-p", f"read_verilog -sv {ROOT}/rtl/router.sv; hierarchy -top router; synth -top router; stat"]
run = subprocess.run(cmd, text=True, capture_output=True, check=True)
text = run.stdout + run.stderr
m = re.search(r"Number of cells:\s+(\d+)", text)
if not m:
    raise RuntimeError("Could not parse Yosys generic cell count")
record = {
    "tool": "Yosys 0.52 generic synth",
    "top": "router",
    "generic_cell_count": int(m.group(1)),
    "timing": "not measured; no target library or clock constraint",
    "area": "not measured; generic cell count is not physical area",
    "power": "not measured",
    "limitations": "No technology mapping, placement, routing, parasitic extraction, or signoff STA/power.",
}
with open(os.path.join(RESULTS, "ppa.json"), "w") as f:
    json.dump(record, f, indent=2)
with open(os.path.join(RESULTS, "ppa_summary.txt"), "w") as f:
    f.write(f"Yosys generic synth cell count: {record['generic_cell_count']}\n")
    f.write(record["limitations"] + "\n")

csv_path = os.path.join(RESULTS, "latency_throughput.csv")
with open(csv_path, newline="") as f:
    rows = list(csv.DictReader(f))
if rows:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        latency = float(rows[0]["mean_latency_cycles"])
        fig, ax = plt.subplots(figsize=(6, 4))
        ax.bar(["R0 local → R1 local"], [latency], color="#3977ad")
        ax.set_ylabel("Latency (cycles)")
        ax.set_title("2×2 mesh directed smoke (N=1; not a traffic sweep)")
        ax.grid(axis="y", alpha=.25)
        fig.tight_layout()
        fig.savefig(os.path.join(RESULTS, "latency_smoke.png"), dpi=150)
        plt.close(fig)
    except ImportError:
        pass
print(json.dumps(record, indent=2))
