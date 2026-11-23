# ADR-0005: Formal and simulation scope

Status: Accepted.

SymbiYosys targets a reduced single router to keep the proof tractable. Current properties establish FIFO/credit upper bounds and that every granted target output is valid, arbiter-selected, credit-backed, and carries the source head data. The depth-6 basecase and induction pass. Exact end-to-end no-loss/no-duplicate, RR bounded fairness, and mesh deadlock liveness are explicitly not claimed. Cocotb directed tests cover critical behaviors; broader traffic sweeps are future work.
