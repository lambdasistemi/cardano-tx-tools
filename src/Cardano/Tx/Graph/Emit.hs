{- |
Module      : Cardano.Tx.Graph.Emit
Description : Body emitter for Cardano (Conway) transactions — public surface (scaffold).
License     : Apache-2.0

Public surface of the joint-graph body emitter introduced by
@specs\/058-body-emitter@. The emitter walks a 'ConwayTx' via
@Cardano.Tx.Diff.conwayDiffProjection@, dispatches on the leaves
to vocab-typed RDF triples, looks up entity-named blank-nodes
against an operator-declared @[EntityDecl]@, and renders the
result as canonical Turtle (T005) or JSON-LD (T011).

This module is the **scaffold** slice (T002, plan slice 2 /
FR-001 + FR-003). It ships the public types and the top-level
'emit' entry-point. The projection walker
(@Cardano.Tx.Graph.Emit.Project@), credential lookup table
(@Cardano.Tx.Graph.Emit.Lookup@), Turtle / JSON-LD serializers
(@Cardano.Tx.Graph.Emit.Serialize.*@), and vocab registry
(@Cardano.Tx.Graph.Emit.Vocab@) land in T004 + T005 + T011 as
private modules under the @Cardano.Tx.Graph.Emit.*@ subtree.

The scaffold's 'emit' returns the empty 'EmittedGraph' on any
input. T005 wires the real projection walk + serializer; the
smoke test (@Cardano.Tx.Graph.EmitSmokeSpec@) is the pre-T005
regression guard on this public surface.

The 'EmittedGraph' value carries the prefix declarations, the
operator-entity overlay bytes (passed through verbatim from the
loader's @rulesOverlayTurtle@), and the body-section triples in
deterministic emit order. T005's projection walker populates
'graphBodyTriples'; T011's JSON-LD serializer consumes the same
value.
-}
module Cardano.Tx.Graph.Emit (
    -- * Entry point
    emit,

    -- * Result
    EmittedGraph (..),
    Triple (..),

    -- * Inputs
    ResolvedUTxO,

    -- * Output format
    EmitFormat (..),

    -- * Errors
    EmitError (..),
) where

import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Text (Text)

import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.TxIn (TxIn)

import Cardano.Tx.Graph.Rules.Load (EntityDecl)
import Cardano.Tx.Ledger (ConwayTx)

{- | The resolved-input map the emitter consumes alongside a
'ConwayTx'.

This alias names the shape the rest of the repo spells out inline
(see 'Cardano.Tx.Diff.TxDiffOptions.txDiffResolvedInputs' and
'Cardano.Tx.Diff.Resolver.resolveChain'). Named here so the
emitter's public signature reads as a single typed input rather
than a raw container.
-}
type ResolvedUTxO = Map TxIn (TxOut ConwayEra)

{- | One RDF triple in the emitted graph.

The placeholder constructor carries subject + predicate + object
as text. T005 may refine this representation once the
projection-walker / Turtle serializer settle on a concrete shape
for blank-node references and typed literals; this slice ships
the minimum the smoke test needs to construct an empty triple
list.
-}
data Triple = Triple !Text !Text !Text
    deriving stock (Eq, Show)

{- | The in-memory graph the body emitter produces.

Carries three pieces of state:

* 'graphPrefixes' — prefix declarations in canonical emit order
  (T005 fixes the order; this scaffold ships an empty list).
* 'graphOverlayTurtle' — operator-entity overlay bytes (verbatim
  from 'Cardano.Tx.Graph.Rules.Load.rulesOverlayTurtle' when an
  overlay is in scope; empty for body-only mode).
* 'graphBodyTriples' — body-section triples in deterministic
  emit order. Empty in this scaffold; populated by T005's
  projection walker.
-}
data EmittedGraph = EmittedGraph
    { graphPrefixes :: ![(Text, Text)]
    -- ^ Prefix declarations in canonical emit order
    -- (e.g. @[("cardano", "https://…"), ("rdfs", "http://…")]@).
    , graphOverlayTurtle :: !ByteString
    -- ^ Operator-entity overlay bytes (verbatim passthrough
    -- from the rules loader). Empty for body-only mode.
    , graphBodyTriples :: ![Triple]
    -- ^ Body-section triples in deterministic emit order.
    }
    deriving stock (Eq, Show)

{- | Which serializer to dispatch in
@Cardano.Tx.Graph.Emit.Serialize@.

Turtle is the byte-diff anchor (plan D5); JSON-LD is acceptance-tested
on set-equal triple sets, not byte-equality (plan D6 / spec
FR-007 + SC-003).
-}
data EmitFormat
    = -- | Canonical Turtle output (plan D5; T005 owns the serializer).
      Turtle
    | -- | JSON-LD output (plan D6; T011 owns the serializer).
      JsonLd
    deriving stock (Eq, Show)

{- | Failure modes the emitter can surface to a caller.

Constructors:

* 'UtxoRequired' — the transaction has @N@ inputs but no resolved
  UTxO map was provided.
* 'UtxoMissing' — a specific @TxIn@ (rendered as hex + index) is
  not present in the resolved UTxO map.
* 'MalformedTxCbor' — the executable could not decode the Conway
  tx CBOR at the given path; the inner 'Text' is the underlying
  ledger decoder's message.
* 'MalformedUtxoJson' — the executable could not decode the
  resolved-UTxO JSON at the given path; the inner 'Text' is the
  aeson parser's message.
* 'UnknownFormat' — the @--format@ CLI argument did not match any
  known 'EmitFormat' value.
* 'UnsupportedLeafType' — a 'Cardano.Tx.Diff.conwayDiffProjection'
  leaf appeared that the projection walker does not yet handle;
  T010 closes the last residual leaves.

The @NoSerializerYet@ variant lands in T003 (the executable slice
adds it to bridge the pre-T005 gap where the dispatcher is wired
but the Turtle serializer doesn't exist yet); T005 removes it.
-}
data EmitError
    = UtxoRequired !Int
    | UtxoMissing !Text
    | MalformedTxCbor !FilePath !Text
    | MalformedUtxoJson !FilePath !Text
    | UnknownFormat !Text
    | UnsupportedLeafType !Text
    deriving stock (Eq, Show)

{- | Walk a 'ConwayTx' against a resolved-UTxO map and an
operator-declared entity list, producing an 'EmittedGraph'.

Scaffold stub: returns 'Right' of the empty 'EmittedGraph' on any
input. T004 wires the credential lookup table; T005 wires the
projection walker + Turtle serializer; T011 wires the JSON-LD
serializer. Callers may rely on the public signature shape from
this slice forward.
-}
emit ::
    ConwayTx ->
    ResolvedUTxO ->
    [EntityDecl] ->
    Either EmitError EmittedGraph
emit _ _ _ = Right (EmittedGraph [] mempty [])
