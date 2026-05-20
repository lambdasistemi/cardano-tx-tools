{- |
Module      : Cardano.Tx.Graph.Emit
Description : Body emitter for Cardano (Conway) transactions — public surface.
License     : Apache-2.0

Public surface of the joint-graph body emitter introduced by
@specs\/058-body-emitter@. The emitter walks a 'ConwayTx' via
@Cardano.Tx.Diff.conwayDiffProjection@, dispatches on the leaves
to vocab-typed RDF triples, looks up entity-named blank-nodes
against an operator-declared @[EntityDecl]@, and renders the
result as canonical Turtle (T005) or JSON-LD (T011).

T005 ships the projection walker + Turtle serializer for the
fixture-02 leaf coverage (@Transaction@, @Input@, @Output@,
@Address@, payment / stake credentials, fee). Future slices
(T006-T010) extend the walker to mint entries, certificates,
datums, redeemers, withdrawals, governance proposals, and
collateral inputs without changing this public surface.

The 'EmittedGraph' value carries the prefix declarations, the
operator-entity overlay bytes (passed through verbatim from the
loader's @rulesOverlayTurtle@), and the body-section structure in
deterministic emit order. 'serialize' renders the value to the
requested 'EmitFormat'.
-}
module Cardano.Tx.Graph.Emit (
    -- * Entry point
    emit,
    serialize,

    -- * Result
    EmittedGraph (..),

    -- * Triple IR (T005)
    Triple (..),
    Subject (..),
    Predicate (..),
    Object (..),
    SubjectBlock (..),
    BodySection (..),

    -- * Body-walker monad (T102)
    -- $monadSurface
    Emit,
    tellTriple,
    introduce,
    runEmit,
    groupBySubject,

    -- * Inputs
    ResolvedUTxO,

    -- * Output format
    EmitFormat (..),

    -- * Errors
    EmitError (..),
    renderEmitError,

    -- * Credential lookup (T004)
    -- $lookupSurface
    BnodeName (..),
    LookupTable,
    buildLookup,
    resolveCredential,
    entityBnodeName,
    rawBytesBnodeName,
    rawBytesPrefixLength,
) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Text qualified as Text

import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.TxIn (TxIn)

import Cardano.Tx.Graph.Emit.Lookup (
    BnodeName (..),
    LookupTable,
    buildLookup,
    entityBnodeName,
    rawBytesBnodeName,
    rawBytesPrefixLength,
    resolveCredential,
 )
import Cardano.Tx.Graph.Emit.Monad (
    Emit,
    groupBySubject,
    introduce,
    runEmit,
    tellTriple,
 )
import Cardano.Tx.Graph.Emit.Project (
    ProjectError (..),
    projectBody,
 )
import Cardano.Tx.Graph.Emit.Serialize.JsonLd (renderJsonLd)
import Cardano.Tx.Graph.Emit.Serialize.Turtle (renderTurtle)
import Cardano.Tx.Graph.Emit.Triple (
    BodySection (..),
    Object (..),
    Predicate (..),
    Subject (..),
    SubjectBlock (..),
    Triple (..),
 )
import Cardano.Tx.Graph.Rules.Load (EntityDecl)
import Cardano.Tx.Ledger (ConwayTx)

{- $lookupSurface
The credential-lookup machinery introduced by T004. The submodule
@Cardano.Tx.Graph.Emit.Lookup@ is private to the library; this
re-export block exposes its types and functions to in-package
test suites and to the projection walker without publishing the
module path itself.
-}

{- $monadSurface
The body-walker monad seam introduced by T102. The submodule
@Cardano.Tx.Graph.Emit.Monad@ is private to the library; this
re-export block exposes the @Emit@ monad alongside the
@tellTriple@ / @introduce@ / @runEmit@ / @groupBySubject@
helpers so in-package test suites and the projection walker can
use them without publishing the module path itself.

The seam is @WriterT [Triple] (State (Set Subject))@ — a writer
over the typed triple stream plus a state-tracked seen-subject
set used by @introduce@ to dedup subjects reached more than once
during the walk (shared addresses, asset classes, DReps).
@groupBySubject@ rebuilds the @[SubjectBlock]@ list from the
flat triple stream preserving first-occurrence order so the
Turtle serializer's byte layout stays byte-identical to the
pre-T102 walker.
-}

{- | The resolved-input map the emitter consumes alongside a
'ConwayTx'.

This alias names the shape the rest of the repo spells out inline
(see 'Cardano.Tx.Diff.TxDiffOptions.txDiffResolvedInputs' and
'Cardano.Tx.Diff.Resolver.resolveChain'). Named here so the
emitter's public signature reads as a single typed input rather
than a raw container.
-}
type ResolvedUTxO = Map TxIn (TxOut ConwayEra)

{- | The in-memory graph the body emitter produces.

Carries three pieces of state:

* 'graphPrefixes' — prefix declarations in canonical emit order
  (T005 fixes the order; the serializer can also derive the
  default block from the fixture slug, so the field is left
  empty in the T005 emit path and used only by downstream
  consumers that want to override).
* 'graphOverlayTurtle' — operator-entity overlay bytes (verbatim
  passthrough from 'Cardano.Tx.Graph.Rules.Load.rulesOverlayTurtle'
  when an overlay is in scope; empty for body-only mode).
* 'graphBody' — the structured body sections in deterministic
  emit order produced by the projection walker.
-}
data EmittedGraph = EmittedGraph
    { graphPrefixes :: ![(Text, Text)]
    -- ^ Prefix declarations in canonical emit order; empty when
    -- the serializer derives them from the fixture slug.
    , graphOverlayTurtle :: !ByteString
    -- ^ Operator-entity overlay bytes (verbatim passthrough from
    -- the rules loader). Empty for body-only mode.
    , graphBody :: ![BodySection]
    -- ^ Body sections in deterministic emit order, each
    -- introduced by a uniform comment header research R4 pins.
    }
    deriving stock (Eq, Show)

{- | Which serializer to dispatch in 'serialize'.

Turtle is the byte-diff anchor (plan D5); JSON-LD is
acceptance-tested on set-equal triple sets, not byte-equality
(plan D6 / spec FR-007 + SC-003 — landing in T011).
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
  T006-T010 close the last residual leaves.
-}
data EmitError
    = UtxoRequired !Int
    | UtxoMissing !Text
    | MalformedTxCbor !FilePath !Text
    | MalformedUtxoJson !FilePath !Text
    | UnknownFormat !Text
    | UnsupportedLeafType !Text
    deriving stock (Eq, Show)

{- | Single-line human-readable rendering of an 'EmitError'.

Shape matches 'Cardano.Tx.Graph.Rules.Load.renderRulesLoadError':
every variant produces exactly one line, leading with the
constructor tag so operators can grep stderr for a specific
failure class.
-}
renderEmitError :: EmitError -> String
renderEmitError = \case
    UtxoRequired n ->
        "UtxoRequired: transaction has "
            <> show n
            <> " input(s) but no resolved UTxO map was provided"
    UtxoMissing k ->
        "UtxoMissing: " <> Text.unpack k
    MalformedTxCbor path msg ->
        "MalformedTxCbor: " <> path <> ": " <> Text.unpack msg
    MalformedUtxoJson path msg ->
        "MalformedUtxoJson: " <> path <> ": " <> Text.unpack msg
    UnknownFormat fmt ->
        "UnknownFormat: " <> Text.unpack fmt
    UnsupportedLeafType leaf ->
        "UnsupportedLeafType: " <> Text.unpack leaf

{- | Walk a 'ConwayTx' against a resolved-UTxO map and an
operator-declared entity list, producing an 'EmittedGraph'.

T005 wires the credential lookup (T004) + projection walker
(@Cardano.Tx.Graph.Emit.Project@). On a non-fixture-02 leaf the
walker raises @UnsupportedLeafType@; T006-T010 add coverage as
each leaf class lands.

The returned 'EmittedGraph' has an empty 'graphPrefixes' field
(the serializer derives the prefix block from the fixture slug
it's called with) and 'graphOverlayTurtle' populated by the
caller via 'rulesOverlayTurtle' if joint emission is desired —
the public 'emit' entry leaves the overlay bytes empty so the
projection-only contract stays orthogonal to the rules loader.
Callers that want the joint Turtle output ('serialize' Turtle)
should populate 'graphOverlayTurtle' via
'Cardano.Tx.Graph.Rules.Load.rulesOverlayTurtle' before calling
'serialize'.
-}
emit ::
    ConwayTx ->
    ResolvedUTxO ->
    [EntityDecl] ->
    Either EmitError EmittedGraph
emit tx utxo entities =
    case projectBody entities (buildLookup entities) tx utxo of
        Left (PUnsupportedLeafType leaf) ->
            Left (UnsupportedLeafType leaf)
        Right body ->
            Right
                EmittedGraph
                    { graphPrefixes = []
                    , graphOverlayTurtle = BS.empty
                    , graphBody = body
                    }

{- | Render an 'EmittedGraph' to a 'ByteString' in the requested
'EmitFormat'.

The fixture slug is the directory name under
@test\/fixtures\/rewrite-redesign\/@ (e.g. @"02-alice-bob-ada"@);
the serializer uses it as the local part of the @\@prefix :@
declaration (Turtle) or the empty default in @\@context@
(JSON-LD). For the Turtle path 'serialize' is byte-stable; for
the JSON-LD path the acceptance contract is set-equality on the
parsed triple set (spec FR-007 + SC-003), not byte-equality —
the 'Cardano.Tx.Graph.Emit.JsonLdEquivalenceSpec' (T011) anchors
this invariant.

T005 implemented the Turtle path; T011 wires the JSON-LD path
through 'Cardano.Tx.Graph.Emit.Serialize.JsonLd.renderJsonLd'.
The 'EmitFormat' value distinguishes the two at the type level
so the executable's @--format@ flag routes here without a string
match.
-}
serialize :: EmitFormat -> FilePath -> EmittedGraph -> ByteString
serialize fmt slug EmittedGraph{graphPrefixes, graphOverlayTurtle, graphBody} =
    case fmt of
        Turtle ->
            renderTurtle
                (Text.pack slug)
                graphPrefixes
                graphOverlayTurtle
                graphBody
        JsonLd ->
            renderJsonLd
                (Text.pack slug)
                graphPrefixes
                graphOverlayTurtle
                graphBody
