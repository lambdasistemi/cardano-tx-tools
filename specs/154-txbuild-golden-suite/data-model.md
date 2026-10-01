# Data model — 154

- **D-1** Golden case (M1): a fixture transaction id plus a display
  name. The case set equals the set of `<txid>.cbor.hex` files directly
  under `test/fixtures/mainnet-txbuild/` (I1).
- **D-2** Input-coin fixture (M1): `inputs/<txid>.inputs`, one
  `<txhash>#<ix> <lovelace>` line per spent input; an unparsable line
  fails the example (never skipped).
