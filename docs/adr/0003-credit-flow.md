# ADR-0003: Credit-based output flow control

Status: Accepted.

Credits initialize to FIFO depth and bound outstanding transfers. The 2×2 wrapper returns a credit when the downstream input FIFO pops a flit. Boundary and local sinks expose explicit credit-return signals. The counter saturates at capacity to remain safe under excess returns; the environment is still responsible for exactly one return per consumed beat.
