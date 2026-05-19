{- |
Module      : Cardano.Tx.Graph.Rules.Load.Types
Description : Shared types for the operator-authored rules loader.
License     : Apache-2.0

Defines the in-memory representation of an operator-authored rules file
('EntityDecl' + 'EntityIdentifier' + 'LeafType') and the structured
error variants the loader can return ('RulesLoadError'). Lives in a
separate module so the parser modules under
@Cardano.Tx.Graph.Rules.Load.*@ can refer to them without an import
cycle through the public @Cardano.Tx.Graph.Rules.Load@ module that
re-exports them.
-}
module Cardano.Tx.Graph.Rules.Load.Types (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
) where

import Data.Text (Text)

{- | An entity declaration after YAML parsing and bech32 decomposition.

The slug is computed via the loader's @slugify@ algorithm from the
entity's @name:@ field and serves as both the entity IRI local part
(per spec FR-013 / Q-001/A-001 Option A) and the bnode prefix for
each of the entity's identifiers.

@'entityIdentifiers'@ is produced in source order from the YAML shape:

* @from-address: \<bech32\>@ → 1 identifier for the payment half and
  optionally 1 identifier for the stake half (enterprise addresses
  have no stake half).
* @script: \<hex\>@ → 1 'PaymentScript' identifier.
* @asset: { policy, name }@ → 1 'AssetClass' identifier with
  @bytesHex = policy ++ hex(ascii(name))@.
* @pool: \<bech32\>@ → 1 'PoolId' identifier.
* @drep: \<CIP-129 bech32\>@ → 1 'DRepKey' or 'DRepScript' identifier.
* @keys: [LeafType, …] + bytes: \<hex\>@ → N identifiers (one per
  @keys:@ leafType) that all share the same 28-byte @bytes:@ payload
  — the cross-leaf identity surface used by fixture-04's
  @usdm-control@ entity.
-}
data EntityDecl = EntityDecl
    { entityName :: !Text
    -- ^ Original operator-typed name (preserved for @rdfs:label@).
    , entitySlug :: !Text
    -- ^ Slugified form for IRI local-part and bnode-prefix use.
    , entityIdentifiers :: ![EntityIdentifier]
    -- ^ Identifiers in source order. At least one (zero-identifier
    -- entities are rejected at parse).
    }
    deriving stock (Eq, Show)

-- | A single (leafType, bytesHex) identifier carried by an 'EntityDecl'.
data EntityIdentifier = EntityIdentifier
    { entityIdLeafType :: !LeafType
    -- ^ The role-class the bytes belong to (one of the nine fixed
    -- values pinned by FR-013).
    , entityIdBytesHex :: !Text
    -- ^ Lowercase hex string. 56 chars for 28-byte hashes;
    -- @policy ++ hex(ascii(name))@ for an 'AssetClass'.
    }
    deriving stock (Eq, Ord, Show)

{- | The role-class enum the loader supports. The nine values used by
the 11 rewrite-redesign fixtures are pinned in spec FR-013 and the
@roleSuffix@ table in plan D2.
-}
data LeafType
    = PaymentKey
    | PaymentScript
    | StakeKey
    | StakeScript
    | AssetClass
    | Policy
    | PoolId
    | DRepKey
    | DRepScript
    deriving stock (Eq, Ord, Show)

{- | Structured errors the loader returns via 'Left'. Each constructor
carries enough provenance (file path, line number, offending string)
that the @tx-graph@ CLI and a future LSP can render a hyperlinked
diagnostic.

The T002 in-memory YAML parser uses @\<in-memory\>@ as the file path
and @0@ as the line number — proper file/line tracking lands with the
file-loader and validation slices (T003 / T009).
-}
data RulesLoadError
    = -- | The file's extension is not @.ttl@, @.yaml@, or @.yml@.
      UnsupportedExtension !FilePath
    | -- | Scaffold-only sentinel. Later slices replace this with concrete
      -- error variants per spec FR-018 / Key Entities.
      NotImplemented !Text
    | -- | Generic YAML/JSON-shape error not covered by a more specific
      -- variant. Carries the underlying parser's message.
      ParserError !FilePath !Int !Text
    | -- | The entity declares no identifier shapes (no @from-address@,
      -- @script@, @asset@, @keys: + bytes:@, @pool:@, or @drep:@).
      EntityZeroIdentifiers !Text
    | -- | A @from-address@ bech32 string failed to decode (bech32
      -- framing, ledger decode, or it is a Byron bootstrap address —
      -- Conway-only per constitution).
      BadBech32 !FilePath !Int !Text
    | -- | A 56-character hex policy/script value failed to parse.
      BadPolicyHex !FilePath !Int !Text
    | -- | The entity @name:@ slugifies to the empty string.
      EntityNameSlugEmpty !FilePath !Int !Text
    | -- | The entity @name:@ slugifies to a value whose first character
      -- is a digit.
      EntityNameSlugLeadingDigit !FilePath !Int !Text
    deriving stock (Eq, Show)
