{- |
Module      : Cardano.Tx.Graph.Emit.Blueprint
Description : Pure CIP-57 blueprint decoder + predicate-IRI minter (T101).
License     : Apache-2.0

T101 / S1 of feature 050 (blueprint-decode typed triples). This module
introduces the pure surface the projection walker
('Cardano.Tx.Graph.Emit.Project' / @.Witness@) will consult in T102
when emitting per-output datum and per-purpose redeemer sub-blocks.

Three families of API:

* 'BlueprintDecodeResult' — the three-way ADT
  ('NoBlueprintRegistered', 'Decoded', 'DecodeFailed') the walker
  branches on per FR-002 / FR-004.

* 'decodeDatumForOutput' / 'decodeRedeemerForPurpose' — pure decoders
  that consult the @[(ScriptHash, Blueprint, Text)]@ index threaded
  through 'Cardano.Tx.Graph.Rules.Load.RulesLoadResult'. The triple's
  third element is the blueprint preamble title, kept for diagnostic
  messages; both decoders ignore it (the constructor + field titles
  driving the IRI minter come from the matched validator's argument
  schema, not the preamble).

* 'blueprintFieldPredicate' — the lowest-level IRI minter pinned to
  pure concatenation of the form @':\<a\>_\<b\>'@. The FR-008
  title-missing fallbacks (@'_'\<constructor-index\>@ for the
  constructor part, @'field'\<position\>@ for the field part) are the
  caller's responsibility — T102's walker substitutes them before
  calling this function (see NAV-PIN-IRI-MINTER on the T101 STATUS
  log).

No 'Cardano.Tx.Graph.Emit.Project' / @.Witness@ / @.Emit@ wiring lands
in this slice; that is T102's domain. Callers passing an empty index
get 'NoBlueprintRegistered' for every position, so threading the new
parameter through 'Cardano.Tx.Graph.Emit.emit' is byte-stable on the
existing 11 fixtures (FR-003 spec contract).
-}
module Cardano.Tx.Graph.Emit.Blueprint (
    -- * Result ADT
    BlueprintDecodeResult (..),

    -- * Redeemer purpose
    RdmrPurpose (..),

    -- * Decoders (pure)
    decodeDatumForOutput,
    decodeRedeemerForPurpose,

    -- * IRI minter (pure)
    blueprintFieldPredicate,
) where

import Data.Text (Text)
import Lens.Micro ((^.))

import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Scripts.Data (Data)
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (
    Credential (ScriptHashObj),
 )
import Cardano.Ledger.Hashes (ScriptHash)

import Cardano.Tx.Blueprint (
    Blueprint,
    BlueprintArgument (argumentSchema),
    BlueprintArgumentKind (BlueprintDatum, BlueprintRedeemer),
    BlueprintDataError,
    BlueprintValidator (validatorDatum, validatorRedeemer),
    blueprintValidators,
    decodeBlueprintData,
 )
import Cardano.Tx.Diff (OpenValue)
import Cardano.Tx.Graph.Emit.Triple (Predicate (PIri))

{- | Three-way result of consulting the blueprint index at a single
datum or redeemer position.

* 'NoBlueprintRegistered' — the position's script hash has no
  blueprint registered, or the matched blueprint declares no
  argument of the requested kind. T102 preserves the pre-#50
  @cardano:hasRawBytes@ shape on this branch (FR-004 / FR-007).

* 'Decoded' — the structural decode produced a typed 'OpenValue'
  AST. The 'Blueprint' value rides along so the walker can mint
  per-field predicates from the matched validator's schema
  (FR-004 / FR-008) without re-walking the index.

* 'DecodeFailed' — the script hash matched but
  'decodeBlueprintData' rejected the 'Data' structurally. T102
  emits the existing @cardano:hasRawBytes@ triple plus a single
  @cardano:decodeError@ literal naming this error (FR-005 /
  D-001d).
-}
data BlueprintDecodeResult
    = NoBlueprintRegistered
    | Decoded !OpenValue !Blueprint
    | DecodeFailed !BlueprintDataError
    deriving stock (Eq, Show)

{- | Redeemer purpose tag mirroring the six Conway-era purposes
('Cardano.Ledger.Conway.Scripts.ConwayPlutusPurpose'). Used only
as a callable-side disambiguator; the resolved 'ScriptHash' is
the key 'decodeRedeemerForPurpose' looks up in the index.

T102 maps each @ConwayPlutusPurpose AsIx ConwayEra@ variant to
the matching constructor here when threading per-redeemer
decodes through the emitter.
-}
data RdmrPurpose
    = Spend
    | Mint
    | Cert
    | Reward
    | Propose
    | Vote
    deriving stock (Eq, Show)

{- | Consult the blueprint index for a spending output's datum.

If the output's address carries a script-hash payment credential and
that hash is registered in the index, the matched blueprint's first
declared @datum:@ argument is fed to 'decodeBlueprintData' against
the supplied 'Data'. Returns 'NoBlueprintRegistered' when the address
has no script credential, when the index has no entry for the
credential's hash, or when the matched blueprint has no @datum:@
argument declared on any of its validators.

The 'Text' third tuple element on the index entries is the blueprint
preamble title; it is kept for diagnostic messages downstream and is
not consulted by this decoder.
-}
decodeDatumForOutput ::
    [(ScriptHash, Blueprint, Text)] ->
    TxOut ConwayEra ->
    Data ConwayEra ->
    BlueprintDecodeResult
decodeDatumForOutput index txOut datum =
    case paymentScriptHash (txOut ^. addrTxOutL) of
        Nothing -> NoBlueprintRegistered
        Just sh -> case lookupBlueprint sh index of
            Nothing -> NoBlueprintRegistered
            Just blueprint -> tryDecode BlueprintDatum blueprint datum

{- | Consult the blueprint index for a redeemer at a given purpose.

The redeemer purpose is supplied for context (T102's walker tags
emitted triples per purpose). Lookup is keyed by the purpose's
resolved 'ScriptHash' — T102's caller computes that hash from the
purpose's witness slot before invoking this function:

* 'Spend' — the resolved input's payment-credential script hash.
* 'Mint' — the policy id (already a script hash).
* 'Cert' / 'Reward' / 'Propose' / 'Vote' — the script hash carried
  by the corresponding certificate / withdrawal / proposal / vote
  witness slot.

On a match the blueprint's first declared @redeemer:@ argument is
fed to 'decodeBlueprintData'. Returns 'NoBlueprintRegistered' when
the script hash is not in the index or when the matched blueprint
declares no @redeemer:@ argument on any of its validators.
-}
decodeRedeemerForPurpose ::
    [(ScriptHash, Blueprint, Text)] ->
    RdmrPurpose ->
    ScriptHash ->
    Data ConwayEra ->
    BlueprintDecodeResult
decodeRedeemerForPurpose index _purpose sh datum =
    case lookupBlueprint sh index of
        Nothing -> NoBlueprintRegistered
        Just blueprint -> tryDecode BlueprintRedeemer blueprint datum

{- | Mint the fixture-scoped predicate IRI for a blueprint-decoded
field. The result is a 'PIri' carrying @':\<constructor\>_\<field\>'@,
where both components are passed in pre-resolved by the caller.

Per FR-008 / D-001b the title-missing fallbacks are the caller's
responsibility — pass @"_\<index\>"@ when the constructor schema has
no @title@ and @"field\<n\>"@ when the field schema has no @title@.
The minter does no fallback substitution because its signature has
no access to the constructor index or field position; carrying those
indices through the IR is a T102 concern.

Example:

>>> blueprintFieldPredicate "SwapOrder" "recipient"
PIri ":SwapOrder_recipient"

>>> blueprintFieldPredicate "_0" "field0"
PIri ":_0_field0"
-}
blueprintFieldPredicate :: Text -> Text -> Predicate
blueprintFieldPredicate ctor field =
    PIri (":" <> ctor <> "_" <> field)

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

{- | Extract the payment-credential 'ScriptHash' from an 'Addr', if any.
Returns 'Nothing' for byron-bootstrap addresses or for addresses
whose payment credential is a key-hash (the blueprint index only
keys on script hashes).
-}
paymentScriptHash :: Addr -> Maybe ScriptHash
paymentScriptHash (Addr _network (ScriptHashObj sh) _stake) = Just sh
paymentScriptHash _ = Nothing

{- | First blueprint in the index registered under the given script
hash. Mirrors the loader's first-wins dedup convention on
'ScriptHash' collisions (spec FR-001 / Edge Case 5).
-}
lookupBlueprint ::
    ScriptHash -> [(ScriptHash, Blueprint, Text)] -> Maybe Blueprint
lookupBlueprint sh = go
  where
    go [] = Nothing
    go ((h, bp, _) : rest)
        | h == sh = Just bp
        | otherwise = go rest

{- | Run 'decodeBlueprintData' against the first argument of the
requested kind found on any of the blueprint's validators. Returns
'NoBlueprintRegistered' if the blueprint declares no argument of
that kind anywhere; otherwise lifts the decoder's 'Either' into
'BlueprintDecodeResult'.
-}
tryDecode ::
    BlueprintArgumentKind ->
    Blueprint ->
    Data ConwayEra ->
    BlueprintDecodeResult
tryDecode kind blueprint datum =
    case firstArgumentOfKind kind blueprint of
        Nothing -> NoBlueprintRegistered
        Just argument ->
            case decodeBlueprintData (argumentSchema argument) datum of
                Left err -> DecodeFailed err
                Right openValue -> Decoded openValue blueprint

{- | The first @datum:@ (or @redeemer:@) argument declared by any
validator on the blueprint, in source order. The CIP-57 grammar
allows multiple validators per blueprint, each with optional datum
and redeemer slots; the T101 decoder picks the first non-'Nothing'
slot it encounters.
-}
firstArgumentOfKind ::
    BlueprintArgumentKind -> Blueprint -> Maybe BlueprintArgument
firstArgumentOfKind kind blueprint =
    case [arg | v <- blueprintValidators blueprint, Just arg <- [pick v]] of
        [] -> Nothing
        (a : _) -> Just a
  where
    pick = case kind of
        BlueprintDatum -> validatorDatum
        BlueprintRedeemer -> validatorRedeemer
