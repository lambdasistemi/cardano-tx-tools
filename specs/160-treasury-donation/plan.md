# Treasury donation implementation plan

As a library maintainer, I want donation construction to share the existing
assembly and balancing owners, so every build path observes the same field.

Add a Coin-valued instruction and public helper to Cardano.Tx.Build, carry it
in the interpreter state with zero default and last-write semantics, and set
Conway's treasuryDonationTxBodyL during assembly. Account for the field in
both change calculations in Cardano.Tx.Balance. Keep collateral and fee
allocation separate from the donation.

Use the existing unit suite for executable conservation, fee and evaluation
controls. No new dependency or runtime effect is needed. No mutable cell or
worker is introduced.

The alternative of patching a completed transaction is rejected: it changes
balance, size and script context after evaluation.
