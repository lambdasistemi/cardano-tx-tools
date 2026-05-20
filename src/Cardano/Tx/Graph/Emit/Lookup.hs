{- |
Module      : Cardano.Tx.Graph.Emit.Lookup
Description : Credential lookup table + raw-bytes bnode naming (private).
License     : Apache-2.0

Private submodule of 'Cardano.Tx.Graph.Emit'. The projection
walker (T005, @Cardano.Tx.Graph.Emit.Project@) consults this
module to translate every @(LeafType, raw bytes)@ pair it
encounters while walking a Conway transaction into a stable
blank-node name:

* if the operator's rules file declares an entity covering the
  pair, the bnode is @_:\<entitySlug\>_\<roleSuffix\>@ — the
  same name the rules loader's overlay serializer emits, via the
  shared 'Cardano.Tx.Graph.Rules.Load.Naming.roleSuffix' table
  (spec FR-013);
* otherwise the bnode is @_:cred_\<rolePrefix\>_\<bytes-prefix\>@
  where @bytes-prefix@ is the first 'rawBytesPrefixLength' hex
  characters of the lowercase base16 encoding of the raw bytes
  (spec FR-005, plan D4, research R3).

The module is internal: callers outside @Cardano.Tx.Graph.Emit.*@
should not depend on its surface. T005 wires the lookup into the
projection walker.
-}
module Cardano.Tx.Graph.Emit.Lookup (
    -- * Names
    BnodeName (..),

    -- * Table
    LookupTable,
    buildLookup,
    resolveCredential,

    -- * Per-pair bnode constructors
    entityBnodeName,
    rawBytesBnodeName,

    -- * Constants
    rawBytesPrefixLength,
) where

import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding

import Cardano.Tx.Graph.Rules.Load (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
 )
import Cardano.Tx.Graph.Rules.Load.Naming (roleSuffix)

{- | A blank-node local name. The wrapped 'Text' is the bare
local part — e.g. @"alice_paymentKey"@ or
@"cred_paymentkey_8bd03209d227956a"@; the @_:@ sigil is added by
the serializer (T005) at emit time.

A newtype (rather than a 'Text' alias) so the type system
distinguishes a bnode name from arbitrary text values that flow
through the emitter.
-}
newtype BnodeName = BnodeName {unBnodeName :: Text}
    deriving stock (Eq, Ord, Show)

{- | The credential resolution table. Built once at the start of
'Cardano.Tx.Graph.Emit.emit' from the operator-declared
@['EntityDecl']@; consulted on every leaf the projection walker
visits.

Keyed on @(LeafType, raw bytes)@ — bytes are the decoded ledger
form, not the hex text the loader stores. Misses fall through to
'rawBytesBnodeName' via 'resolveCredential'.
-}
type LookupTable = Map (LeafType, ByteString) BnodeName

{- | Hex-prefix length used in raw-bytes bnode names — 16
hex chars (8 bytes) per research R3.

R3's empirical floor across the 11 rewrite-redesign fixtures is
small (single-digit collisions disappear by @N = 12@); 16 adds
~4 chars of safety margin so future fixtures with closely-spaced
key prefixes don't immediately tip the property over. T004's
injectivity property locks the invariant; any future collision
surfaces as a Q-file to the orchestrator (per research R3 — N is
a global pin, not a local knob).
-}
rawBytesPrefixLength :: Int
rawBytesPrefixLength = 16

{- | Build the first-entity-wins credential table from a list of
'EntityDecl' values in document order.

Mirrors the loader's @buildNamingTable@ semantics
('Cardano.Tx.Graph.Rules.Load.Naming') but keys on the decoded
ByteString rather than the hex 'Text', so the projection walker
can look up directly with the bytes it pulls out of the ledger
'Cardano.Ledger.TxIn.TxIn' / 'Cardano.Ledger.Address.Addr'
shapes.

Hex decode failures are invariant violations — the loader
('Cardano.Tx.Graph.Rules.Load.Parse.Yaml' /
'…Load.Parse.Turtle') rejects malformed @bytesHex@ values at
load time. If one slips through here the module errors loudly
with a clear message.
-}
buildLookup :: [EntityDecl] -> LookupTable
buildLookup entities =
    Map.fromListWith
        (\_new old -> old)
        [ ( (entityIdLeafType i, decodeHexOrInvariant (entityIdBytesHex i))
          , entityBnodeName e i
          )
        | e <- entities
        , i <- entityIdentifiers e
        ]

{- | Look up a @(LeafType, raw bytes)@ pair against the entity
table; fall through to the raw-bytes bnode if no entity declared
it.
-}
resolveCredential ::
    LookupTable ->
    LeafType ->
    ByteString ->
    BnodeName
resolveCredential tbl lt bytes =
    case Map.lookup (lt, bytes) tbl of
        Just bn -> bn
        Nothing -> rawBytesBnodeName lt bytes

{- | The bnode name an 'EntityDecl' contributes for one of its
'EntityIdentifier' values — @\<entitySlug\>_\<roleSuffix
leafType\>@. Wraps 'Cardano.Tx.Graph.Rules.Load.Naming.roleSuffix'
so the entity-named branch of this lookup stays byte-equal to the
overlay serializer's output (spec FR-013).
-}
entityBnodeName :: EntityDecl -> EntityIdentifier -> BnodeName
entityBnodeName EntityDecl{entitySlug} EntityIdentifier{entityIdLeafType} =
    BnodeName (entitySlug <> "_" <> roleSuffix entityIdLeafType)

{- | The fallback bnode name for an unknown credential —
@cred_\<rolePrefix\>_\<bytes-prefix\>@, where @bytes-prefix@ is
the first 'rawBytesPrefixLength' hex characters of the lowercase
base16 encoding of @bytes@ (spec FR-005, plan D4).

The role-prefix table is exhaustive over the nine 'LeafType'
values pinned by spec FR-013; an unhandled leaf surfaces as a
@-Wincomplete-patterns@ failure when a new variant is added.
-}
rawBytesBnodeName :: LeafType -> ByteString -> BnodeName
rawBytesBnodeName lt bytes =
    BnodeName $
        "cred_"
            <> rolePrefix lt
            <> "_"
            <> Text.take rawBytesPrefixLength hex
  where
    hex =
        TextEncoding.decodeLatin1 (Base16.encode bytes)

{- | Lowercased role-class prefix used in raw-bytes bnodes.

Distinct from 'roleSuffix' (which is camelCase, e.g.
@paymentKey@) — bnode local parts are syntactically the same
between the two paths but the convention differs: entity names
preserve the operator-facing camelCase, raw-bytes names use a
lowercase deterministic class slug. Pinned by spec FR-005 / plan
D4 examples.
-}
rolePrefix :: LeafType -> Text
rolePrefix = \case
    PaymentKey -> "paymentkey"
    PaymentScript -> "paymentscript"
    StakeKey -> "stakekey"
    StakeScript -> "stakescript"
    AssetClass -> "assetclass"
    Policy -> "policy"
    PoolId -> "poolid"
    DRepKey -> "drepkey"
    DRepScript -> "drepscript"

{- | Decode a hex 'Text' to a 'ByteString'; @error@ on failure.

The loader guarantees every 'entityIdBytesHex' value is
well-formed lowercase hex (the @.yaml@ / @.ttl@ parsers reject
malformed inputs at load time, per spec FR-013). Reaching the
'Left' branch here is an invariant violation, not a runtime
condition.
-}
decodeHexOrInvariant :: Text -> ByteString
decodeHexOrInvariant t =
    case Base16.decode (TextEncoding.encodeUtf8 t) of
        Right bs -> bs
        Left err ->
            error $
                "Cardano.Tx.Graph.Emit.Lookup: unexpected non-hex"
                    <> " bytesHex from rules loader: "
                    <> Text.unpack t
                    <> ": "
                    <> err
