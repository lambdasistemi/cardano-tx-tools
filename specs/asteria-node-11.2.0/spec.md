As an Asteria workload operator, I want transaction tools on the node 11.2.0 package set so that the game builder can use the repaired node clients with consistent ledger types.

Part of cardano-foundation/cardano-node-antithesis#299 and lambdasistemi/cardano-node-clients#223. Operator approved a full ecosystem bump following cardano-foundation/cardano-balance-transaction#51 rather than an old-version backport.

Advance the dependency set from the actual node 11.2.0 resolved plan, update client and ledger-read source pins, adapt changed APIs, and preserve Conway transaction behavior. Run build/unit/integration/lint gates with exact evidence. Asteria will then consume the current Cardano.Tx.Build module namespace.
