"""Channel-Dependency Graph (CDG) checker for SpikeRoute tables.

Deadlock needs a cycle of channels each waiting on the next. If every
packet's route uses channels in an order that never loops back, no cycle
can form. This tool builds the CDG from loaded routing tables and
verifies acyclicity; table sets that fail must be rejected.

Nodes: mesh channels (router, out_port), port in 0..3.
Edge c1 -> c2: a packet traversing c1 can next traverse c2, i.e. c2 is
a target output of the router that c1 feeds, for some input/route.
"""
import os
import sys
from collections import defaultdict, deque

# Mesh links: (router, out_port) -> (router, in_port)
LINKS = {
    (0, 0): (2, 2), (2, 2): (0, 0),  # R0.N <-> R2.S
    (0, 1): (1, 3), (1, 3): (0, 1),  # R0.E <-> R1.W
    (1, 0): (3, 2), (3, 2): (1, 0),  # R1.N <-> R3.S
    (2, 1): (3, 3), (3, 3): (2, 1),  # R2.E <-> R3.W
}
OPPOSITE = {0: 2, 1: 3, 2: 0, 3: 1}
LOCAL = 4


def build_cdg(tables):
    """tables: {router: [(key, mask, port_mask), ...]} -> adjacency dict."""
    adj = defaultdict(set)
    nodes = set()
    for r in range(4):
        entries = tables.get(r, [])
        # Routes per input port: table entries + default.
        for p in range(5):
            routes = []
            for (key, mask, pm) in entries:
                routes.append(pm)
            if p != LOCAL:
                routes.append(1 << OPPOSITE[p])  # default straight-through
            # Local input with no match drops: no outgoing edge.
            for pm in routes:
                for t in range(4):  # mesh targets only
                    if (pm >> t) & 1:
                        nodes.add((r, t))
                        if p != LOCAL:
                            # Incoming channel feeding input p of router r.
                            for (rr, pp), (rr2, pp2) in LINKS.items():
                                if rr2 == r and pp2 == p:
                                    adj[(rr, pp)].add((r, t))
                                    nodes.add((rr, pp))
    return adj, nodes


def is_acyclic(adj, nodes):
    """Kahn's algorithm. Returns (acyclic, cycle_nodes)."""
    indeg = {n: 0 for n in nodes}
    for u in adj:
        for v in adj[u]:
            indeg[v] = indeg.get(v, 0) + 1
    q = deque([n for n, d in indeg.items() if d == 0])
    seen = 0
    while q:
        u = q.popleft()
        seen += 1
        for v in adj.get(u, ()):
            indeg[v] -= 1
            if indeg[v] == 0:
                q.append(v)
    cycle = [n for n, d in indeg.items() if d > 0]
    return (len(cycle) == 0), cycle


def check(tables):
    adj, nodes = build_cdg(tables)
    return is_acyclic(adj, nodes)


if __name__ == "__main__":
    # Acyclic: XY-style unicast + multicast (the mesh test tables).
    acyclic_tables = {
        0: [(0x0003, 0xFFFF, 1 << 1),   # dest3 -> E
            (0x00AA, 0xFFFF, (1 << 1) | (1 << 0))],  # MC -> E+N
        1: [(0x0003, 0xFFFF, 1 << 0),   # dest3 -> N
            (0x00AA, 0xFFFF, 1 << LOCAL)],
        2: [(0x00AA, 0xFFFF, 1 << LOCAL)],
        3: [(0x0003, 0xFFFF, 1 << LOCAL)],
    }
    ok, cycle = check(acyclic_tables)
    print(f"acyclic tables: acyclic={ok} (expected True)")

    # Cyclic: R0 sends keyX east, R1 sends keyX west -> cycle.
    cyclic_tables = {
        0: [(0x00BB, 0xFFFF, 1 << 1)],
        1: [(0x00BB, 0xFFFF, 1 << 3)],
        2: [], 3: [],
    }
    ok2, cycle2 = check(cyclic_tables)
    print(f"cyclic tables: acyclic={ok2} (expected False), cycle={cycle2}")

    assert ok and not ok2 and cycle2, "CDG checker self-test FAILED"
    out = os.path.join(os.path.dirname(__file__), "..", "results",
                       "cdg_test.txt")
    with open(out, "w") as f:
        f.write("CDG checker self-test: acyclic tables PASS, "
                "cyclic tables correctly REJECTED.\n")
        f.write(f"cyclic example cycle nodes: {cycle2}\n")
    print("CDG self-test PASSED")
