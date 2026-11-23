# ADR-0002: Atomic multicast grant

Status: Accepted.

A head flit targeting multiple outputs advances only when all target arbiters select its input and every target has a credit and is ready in that cycle. This avoids partial delivery and hold-and-wait resource retention. Trade-off: a busy target blocks all branches; throughput/fairness under contention remains to be characterized.
