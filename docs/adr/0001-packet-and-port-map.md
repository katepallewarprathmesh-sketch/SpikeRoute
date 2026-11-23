# ADR-0001: Packet format and port numbering

Status: Accepted.

Packet is one 32-bit flit `{key[31:16], payload[15:0]}`; five ports are N,E,S,W,Local numbered 0..4. This keeps the testbench and table fields compact and deterministic. Multi-flit packets and variable-width payloads are out of scope.
