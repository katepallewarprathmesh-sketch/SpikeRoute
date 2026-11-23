# ADR-0004: Route lookup and channel dependency analysis

Status: Accepted with verification limits.

Use an 8-entry masked-key table with lowest-index priority, default opposite-port forwarding for transit inputs, and local no-match drop. A static channel-dependency graph (CDG) checker flags cycles: deadlock requires a cycle of resources waiting on one another. Its self-test establishes that the graph algorithm accepts an acyclic sample and rejects a constructed cyclic sample. It is not a dynamic proof for every possible table/traffic combination; XY unicast route discipline and valid multicast trees remain configuration obligations. Do not claim full-mesh deadlock freedom based on the current evidence.
