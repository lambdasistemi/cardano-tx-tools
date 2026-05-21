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
    RulesLoadWarning (..),
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
    , entitySourceFile :: !FilePath
    -- ^ The path of the file this declaration was parsed from. The
    -- in-memory parser entry points use the placeholder
    -- @\<in-memory\>@; the file-aware entry points used by the
    -- imports resolver thread the real path through. Consumed by
    -- 'Cardano.Tx.Graph.Rules.Load.Resolve.Imports' to detect
    -- duplicate entity slugs that originate from two different
    -- imported files (spec FR-011 / US6) — first-wins,
    -- 'Cardano.Tx.Graph.Rules.Load.RulesLoadWarning' emitted.
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

{- | The role-class enum the loader supports.

The first nine values (PaymentKey ... DRepScript) are the
operator-declarable entity-credential leaf types pinned in spec
FR-013 and the @roleSuffix@ table in plan D2 — they appear in
operator rules files and the entity-overlay path.

The remaining five (TxId, DatumHash, ScriptHash, ScriptDataHash,
AuxiliaryDataHash) are body-walker-only leaf types introduced by
T122c / S22 for the literal-vs-node consistency audit (A-007):
any hash with independent identity (txid, datum hash, script
hash, script-data hash, auxiliary-data hash) emits as a
@cardano:Identifier@-typed bnode under the @_:hash_*@ raw-bytes
naming prefix, so cross-position bnode joins in SPARQL views
work without literal-string surgery.
-}
data LeafType
    = -- Operator-declarable credential leaves (FR-013 / plan D2).
      PaymentKey
    | PaymentScript
    | StakeKey
    | StakeScript
    | AssetClass
    | Policy
    | PoolId
    | DRepKey
    | DRepScript
    | -- Body-walker hash leaves (T122c / S22).
      -- 'Lt' prefix avoids name clashes with the ledger's
      -- 'Cardano.Ledger.Hashes.ScriptHash',
      -- 'Cardano.Ledger.Api.Scripts.Data.DatumHash',
      -- 'Cardano.Ledger.TxIn.TxId', etc. The cardano:leafType
      -- literals these emit ("ScriptHash" / "DatumHash" /
      -- "TxId" / …) match A-007's wire-shape directly via the
      -- 'leafTypeText' / 'renderLeafType' tables, not the
      -- constructor name.
      LtTxId
    | LtDatumHash
    | LtScriptHash
    | LtScriptDataHash
    | LtAuxiliaryDataHash
    deriving stock (Eq, Ord, Show)

{- | Structured errors the loader returns via 'Left'. Each constructor
carries enough provenance (file path, line number, offending string)
that the @tx-graph@ CLI and a future LSP can render a hyperlinked
diagnostic.

The in-memory @parseRulesYamlText@ / @parseRulesTurtleText@ entry
points (which take a 'ByteString' but no 'FilePath') use
@\<in-memory\>@ as the source file. When a rules file is loaded via
'Cardano.Tx.Graph.Rules.Load.loadRulesFile', the imports resolver
threads the absolute file path through every parser error so the
@tx-graph@ CLI and a future LSP can render hyperlinked diagnostics.

Line numbers are 1-based, matching the convention every editor and
LSP uses. The YAML parser extracts decode-failure lines from
libyaml's 'Text.Libyaml.YamlMark' (whose @yamlLine@ field is 0-based
and is incremented to 1-based at the producer site). For
post-decode entity-level errors, the YAML parser pre-scans the raw
text for each entity's @- name:@ line. The Turtle lexer tracks line
numbers as it advances through the input and emits @(Token,
lineNumber)@ pairs that the structural parser threads through to
each error site.
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
      -- Carries the source file path and the 1-based line of the
      -- offending entity's @- name:@ key so diagnostics can hyperlink
      -- back to the YAML source (spec FR-009 + Q-001/A-001 extension:
      -- name + line, not just name).
      EntityZeroIdentifiers !FilePath !Int !Text
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
    | -- | A top-level @blueprints:@ entry's @script: \<name\>@ field
      -- references an entity that is not declared in the same file or
      -- that is declared but does not use the @script:@ shape (i.e.
      -- has no 'PaymentScript' identifier). The 'Text' payload is the
      -- offending entity name.
      BlueprintRefsUnknownScript !FilePath !Int !Text
    | -- | An @owl:imports@ / @imports:@ entry references a file the
      -- resolver could not stat. The first 'FilePath' is the importer
      -- (the file containing the bad reference); the second is the
      -- resolved-relative path the resolver attempted to load.
      MissingImport !FilePath !FilePath
    | -- | An @owl:imports@ / @imports:@ entry is an absolute filesystem
      -- path or a @file://@ URI. The constitution's
      -- Default-Offline / Filesystem-Only Imports rule forbids
      -- absolute imports: every relative path is resolved against
      -- the importer's directory, so the loader stays within the
      -- worktree by construction. The 'Text' payload is the raw
      -- import string the operator authored.
      AbsoluteImport !FilePath !Text
    | -- | An @owl:imports@ entry targets an @http://@ or @https://@
      -- IRI. The loader is default-offline (FR-017 / analyzer N4)
      -- and never fetches network resources. The 'Text' payload is
      -- the raw URI.
      HttpsImport !FilePath !Text
    | -- | The import graph contains a cycle. The payload is the cycle
      -- path in DFS-entry order with the revisited node appended at
      -- the end so the cycle reads naturally: e.g. when @a@ imports
      -- @b@ and @b@ imports @a@, the payload is
      -- @[a-path, b-path, a-path]@. A self-import yields
      -- @[a-path, a-path]@. The loader detects cycles via a Grey
      -- (in-progress) state on the DFS frontier and aborts on the
      -- first back-edge.
      RulesImportCycle ![FilePath]
    | -- | A @blueprints:@ entry's @datum: \<path\>@ resolves to a file
      -- the loader could not stat. Payload = rules.yaml path +
      -- 1-based line of the offending @- script:@ key + the raw
      -- @datum:@ path string the operator authored. Renders as
      -- @\<rules-yaml\>:\<line\>: BlueprintFileMissing: \<path\>@
      -- (spec FR-011 / Edge Case 6).
      BlueprintFileMissing !FilePath !Int !Text
    | -- | A @blueprints:@ entry's @datum:@ file failed CIP-57 JSON
      -- decoding. Payload = rules.yaml path + 1-based line of the
      -- @- script:@ key + the raw @datum:@ path + the underlying
      -- aeson error message (spec FR-011 / Edge Case 7).
      BlueprintParseError !FilePath !Int !Text !Text
    | -- | A @blueprints:@ entry's @datum: \<path\>@ is an absolute
      -- filesystem path or a @file://@ URI. The loader mirrors the
      -- filesystem-only @owl:imports@ policy: every relative path is
      -- resolved against the rules.yaml's directory, so the loader
      -- stays within the worktree by construction. Payload = the
      -- raw operator-authored string (spec FR-011 / Edge Case 8).
      AbsoluteBlueprintPath !FilePath !Int !Text
    | -- | A @blueprints:@ entry's @datum:@ targets an @http://@ or
      -- @https://@ IRI. The loader is default-offline (FR-017) and
      -- never fetches network resources. Payload = the raw URI
      -- (spec FR-011 / Edge Case 8).
      HttpsBlueprintPath !FilePath !Int !Text
    | -- | Two blueprints in the loaded index would mint the same
      -- @:\<ConstructorTitle\>_\<FieldTitle\>@ predicate (the
      -- naming pinned in spec FR-008). The loader rejects rather
      -- than silently picking a winner: predicate collisions are an
      -- operator-side config bug surfaced at load time, before the
      -- emitter runs (D-001b / A-001). Payload = rules.yaml path +
      -- 1-based line of the second @- script:@ declaration + the
      -- conflicting predicate name.
      DuplicateBlueprintPredicate !FilePath !Int !Text
    deriving stock (Eq, Show)

{- | Non-fatal warnings the loader emits while still returning a 'Right'
'Cardano.Tx.Graph.Rules.Load.RulesLoadResult'. The CLI surfaces these
on @stderr@; a future LSP can render them as squiggly underlines.

The only variant today is 'DuplicateEntityAcrossFiles' (spec FR-011 /
US6): when two imported files declare the same entity slug, the first
declaration wins, the second is silently dropped from the overlay,
and this warning names both file paths so the operator can locate
the duplicate. Same-file dups remain a hard 'RulesLoadError' surfaced
by the per-file parsers — this warning is the cross-file relaxation
only.
-}
data RulesLoadWarning
    = -- | The same entity slug was declared in two imported files.
      -- The first declaration is kept; the second is dropped (per spec
      -- US6). Carries the entity slug, the path of the kept file, and
      -- the path of the dropped file (both canonical absolute paths
      -- after the resolver's 'canonicalizePath' pass).
      DuplicateEntityAcrossFiles !Text !FilePath !FilePath
    | -- | Two @blueprints:@ entries register against the same script
      -- entity (spec Edge Case 5 / D-001f / A-001). The first
      -- declaration wins; the second is dropped from the loaded
      -- index. The warning carries the rules.yaml file path, the
      -- 1-based source line of the second @- script:@ declaration,
      -- and the offending entity name verbatim (the same string the
      -- operator typed in the @script:@ key — not the slug).
      DuplicateBlueprintForScript !FilePath !Int !Text
    deriving stock (Eq, Show)
