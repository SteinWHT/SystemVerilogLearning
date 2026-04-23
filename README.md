# SystemVerilogLearning

| # | Module                                      | Key Concepts                      | What to Implement                                 | Verification Focus                                  | Interview Value     |
| - | ------------------------------------------- | --------------------------------- | ------------------------------------------------- | --------------------------------------------------- | ------------------- |
| 1 | **Arbiter (Fixed + Round-Robin)**           | Priority, fairness, starvation    | Parametrized N-request arbiter, RR pointer logic  | One-hot grant, no lost requests, fairness over time | ⭐⭐⭐⭐⭐ (very common) |
| 2 | **Valid-Ready Pipeline + Skid Buffer**      | Backpressure, throughput, latency | 1-stage + multi-stage pipeline, skid buffer       | No data loss, proper stall/flow behavior            | ⭐⭐⭐⭐⭐               |
| 3 | **Synchronizers (CDC basics)**              | Metastability, CDC safety         | 2-flop sync, pulse sync, toggle sync              | No glitches, correct pulse transfer                 | ⭐⭐⭐⭐                |
| 4 | **Synchronous FIFO (Enhanced)**             | Queues, flow control              | Param depth/width, almost_full/empty              | Overflow/underflow protection                       | ⭐⭐⭐⭐                |
| 5 | **FSM-Based Design (e.g., UART RX/TX)**     | State machines, timing            | Clean enum-based FSM, datapath separation         | State coverage, edge cases                          | ⭐⭐⭐⭐                |
| 6 | **Simple Cache (Direct-Mapped)**            | Memory hierarchy                  | Tag compare, valid bits, hit/miss logic           | Correct hits/misses, write behavior                 | ⭐⭐⭐⭐                |
| 7 | **Assertions Layer (applied to all above)** | Formal thinking                   | Add SVA to each module                            | Protocol correctness, invariants                    | ⭐⭐⭐⭐⭐               |
| 8 | **Mini Integration (Optional)**             | System thinking                   | Connect modules (e.g., pipeline + FIFO + arbiter) | End-to-end data correctness                         | ⭐⭐⭐⭐                |
