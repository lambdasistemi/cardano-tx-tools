#!/usr/bin/env bash
set -euo pipefail

# --8<-- [start:paths]
ROOT="${CARDANO_TX_TOOLS_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REPORT_DIR="${MAY_2026_REPORT_DIR:-$ROOT/docs/may-2026-amaru-lattice}"
WORK_DIR="${MAY_2026_WORK_DIR:-${TMPDIR:-/tmp}/cardano-tx-tools-may-2026-lattice}"
NETWORK="${CARDANO_NETWORK:-mainnet}"
# --8<-- [end:paths]

# --8<-- [start:preflight]
if [[ -z "${BLOCKFROST_PROJECT_ID:-}" ]]; then
  echo "BLOCKFROST_PROJECT_ID is required for tx-fetch" >&2
  exit 2
fi

if [[ ! -f "$REPORT_DIR/network-txs.txt" ]]; then
  echo "missing report boundary file: $REPORT_DIR/network-txs.txt" >&2
  exit 2
fi
# --8<-- [end:preflight]

# --8<-- [start:fetch]
mapfile -t TXIDS <"$REPORT_DIR/network-txs.txt"
mkdir -p "$WORK_DIR/ttl"

nix run "$ROOT#tx-fetch" -- \
  --out-dir "$WORK_DIR" \
  --network "$NETWORK" \
  --depth 0 \
  "${TXIDS[@]}"
# --8<-- [end:fetch]

# --8<-- [start:graph]
rm -f "$WORK_DIR"/ttl/*.ttl
nix run "$ROOT#tx-graph" -- \
  --rules "$REPORT_DIR/rules.yaml" \
  --in-dir "$WORK_DIR/cbor" \
  --out-dir "$WORK_DIR/ttl"
# --8<-- [end:graph]

# --8<-- [start:data]
DATA_ARGS=()
for ttl in "$WORK_DIR"/ttl/*.ttl; do
  [[ -e "$ttl" ]] || {
    echo "tx-graph produced no Turtle files in $WORK_DIR/ttl" >&2
    exit 1
  }
  DATA_ARGS+=(--data "$ttl")
done
DATA_ARGS+=(--data "$REPORT_DIR/live-utxos.ttl")
# --8<-- [end:data]

# --8<-- [start:select]
if (($#)); then
  QUERIES=("$@")
else
  mapfile -t QUERIES < <(find "$REPORT_DIR" -mindepth 2 -maxdepth 2 -name '*.rq' | sort)
fi
# --8<-- [end:select]

# --8<-- [start:run]
run_query() {
  local query="$1"
  if [[ "$query" != /* ]]; then
    query="$ROOT/$query"
  fi

  echo
  echo "== ${query#$ROOT/}"

  local cmd=(sparql "${DATA_ARGS[@]}" --query "$query")
  if command -v sparql >/dev/null 2>&1; then
    "${cmd[@]}"
  else
    local quoted
    printf -v quoted '%q ' "${cmd[@]}"
    nix-shell -p apache-jena --run "$quoted"
  fi
}

for query in "${QUERIES[@]}"; do
  run_query "$query"
done
# --8<-- [end:run]
