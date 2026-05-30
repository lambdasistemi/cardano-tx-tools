{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.Tx.Diff
Description : Structural transaction diff primitives.

This module contains the render-independent diff core used by the transaction
diff feature. The central rule is equality first: paired values are compared
before any child projection is requested.
-}
module Cardano.Tx.Diff (
    AddressMatch (..),
    AddressTarget (..),
    CollapseRawView (..),
    CollapseRule (..),
    CollapseRules (..),
    ConwayDiffValue (..),
    DiffChange (..),
    DiffNode (..),
    DiffPlan (..),
    DiffPath (..),
    DiffProjection (..),
    HumanRenderOptions (..),
    LeafLinker,
    OpenValue (..),
    RenameRule (..),
    RenameRules (..),
    RenderShape (..),
    RewriteRules (..),
    TxDiffDataDecoder,
    TxDiffDataKind (..),
    TxDiffDataSelector (..),
    TxDiffOptions (..),
    TxInputDecodeError (..),
    TreeArt (..),
    Url (..),
    defaultHumanRenderOptions,
    defaultRewriteRules,
    defaultTxDiffOptions,
    decodeBech32Address,
    decodeConwayTxInput,
    diffConwayTxInput,
    diffConwayTxInputWith,
    diffConwayTx,
    diffConwayTxWith,
    diffNodeHasChanges,
    diffOpenValue,
    diffWith,
    emptyRenameRules,
    parseCollapseRulesYaml,
    parseRewriteRulesYaml,
    renderConwayDiffValueHuman,
    renderConwayTxHuman,
    renderConwayTxInputDiff,
    renderDiffNodeHuman,
    renderDiffNodeHumanWith,
    renderOpenValueHuman,
    renderOpenValueHumanWith,
) where

import Codec.Binary.Bech32 qualified as Bech32
import Control.Applicative ((<|>))
import Control.Monad (when)
import Data.Aeson (FromJSON (..), (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser, parseEither, (.!=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as LBS
import Data.ByteString.Short qualified as SBS
import Data.Char (isDigit, isHexDigit, isSpace)
import Data.Foldable (toList)
import Data.List qualified as List
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Tree qualified as Tree
import Data.Tree.View qualified as TreeView
import Data.Yaml qualified as Yaml
import Lens.Micro ((^.))
import Text.Read (readMaybe)

import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.Ledger.Address (
    AccountAddress,
    Addr (..),
    Withdrawals (..),
    decodeAddrEither,
    serialiseAddr,
 )
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..), TxDats (..))
import Cardano.Ledger.Api.Scripts.Data (
    Data (..),
    Datum (..),
    binaryDataToData,
 )
import Cardano.Ledger.Api.Tx (
    addrTxWitsL,
    bodyTxL,
    bootAddrTxWitsL,
    witsTxL,
 )
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    reqSignerHashesTxBodyL,
    totalCollateralTxBodyL,
    vldtTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    addrTxOutL,
    coinTxOutL,
    datumTxOutL,
    referenceScriptTxOutL,
    valueTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (
    datsTxWitsL,
    rdmrsTxWitsL,
    scriptTxWitsL,
    witVKeyHash,
 )
import Cardano.Ledger.BaseTypes (StrictMaybe (..), TxIx (..))
import Cardano.Ledger.Binary (
    Annotator,
    Decoder,
    decCBOR,
    decodeFullAnnotator,
    decodeFullAnnotatorFromHexText,
    natVersion,
    serialize',
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (Script, eraProtVerLow, hashScript)
import Cardano.Ledger.Credential (Credential)
import Cardano.Ledger.Hashes (DataHash, ScriptHash (..), extractHash)
import Cardano.Ledger.Keys (
    KeyHash (..),
    KeyRole (..),
    WitVKey,
    hashKey,
 )
import Cardano.Ledger.Keys.Bootstrap (BootstrapWitness (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Slotting.Slot (SlotNo (..))
import Cardano.Tx.Ledger (ConwayTx)
import PlutusCore.Data qualified as PLC

newtype DiffPath = DiffPath [Text]
    deriving stock (Eq, Ord, Show)

data DiffNode = DiffNode DiffPath DiffChange
    deriving stock (Eq, Show)

data DiffChange
    = DiffSame (Maybe Aeson.Value)
    | DiffChanged Aeson.Value Aeson.Value
    | DiffObject
        (Map Text (Maybe Aeson.Value))
        (Map Text DiffNode)
        (Map Text Aeson.Value)
        (Map Text Aeson.Value)
    | DiffArray
        [(Int, Maybe Aeson.Value)]
        [(Int, DiffNode)]
        [(Int, Aeson.Value)]
        [(Int, Aeson.Value)]
    deriving stock (Eq, Show)

data DiffPlan a = DiffPlan
    { diffEqual :: a -> a -> Bool
    , diffSummary :: a -> Maybe Aeson.Value
    , diffProject :: a -> DiffProjection a
    }

data DiffProjection a
    = DiffAtomic Aeson.Value
    | DiffObjectChildren (Map Text a)
    | DiffArrayChildren [a]

data OpenValue
    = OpenObject (Map Text OpenValue)
    | OpenArray [OpenValue]
    | OpenInteger Integer
    | OpenText Text
    | OpenBytes Text
    deriving stock (Eq, Show)

newtype TxInputDecodeError = TxInputDecodeError Text
    deriving stock (Eq, Show)

type TxDiffDataDecoder =
    TxDiffDataSelector -> Data ConwayEra -> Either Text OpenValue

data TxDiffDataKind
    = TxDiffDatum
    | TxDiffRedeemer
    deriving stock (Eq, Show)

data TxDiffDataSelector = TxDiffDataSelector
    { txDiffDataValidatorTitle :: Maybe Text
    , txDiffDataKind :: TxDiffDataKind
    }
    deriving stock (Eq, Show)

data TxDiffOptions = TxDiffOptions
    { txDiffIncludeWitnesses :: Bool
    , txDiffDecodeData :: Maybe TxDiffDataDecoder
    , txDiffResolvedInputs :: Maybe (Map TxIn (TxOut ConwayEra))
    -- ^ When 'Nothing' (default), every 'TxIn' renders as today: an atomic
    -- @{txId, index}@ leaf. When 'Just', resolution is treated as enabled;
    -- each 'TxIn' renders as an object with a @txIn@ child and, only if
    -- present in the map, a @resolved@ child reusing the body-output
    -- projection.
    }

instance Show TxDiffOptions where
    show options =
        "TxDiffOptions {txDiffIncludeWitnesses = "
            <> show (txDiffIncludeWitnesses options)
            <> ", txDiffDecodeData = "
            <> maybe "Nothing" (const "Just <decoder>") (txDiffDecodeData options)
            <> ", txDiffResolvedInputs = "
            <> maybe
                "Nothing"
                (\m -> "Just <" <> show (Map.size m) <> " resolved>")
                (txDiffResolvedInputs options)
            <> "}"

defaultTxDiffOptions :: TxDiffOptions
defaultTxDiffOptions =
    TxDiffOptions
        { txDiffIncludeWitnesses = False
        , txDiffDecodeData = Nothing
        , txDiffResolvedInputs = Nothing
        }

-- | Human diff render shape.
data RenderShape
    = RenderTree
    | RenderPaths
    deriving stock (Eq, Show)

-- | Tree connector style for tree-shaped human output.
data TreeArt
    = TreeArtAscii
    | TreeArtUnicode
    deriving stock (Eq, Show)

{- | A URL emitted by a 'LeafLinker' (issue #88). Renderered alongside
the matched leaf in tree- and path-shaped output when
'humanLeafLinker' is set. See "Cardano.Tx.Diff.Scan" for the
Cardanoscan linker that ships with the library.
-}
newtype Url = Url {getUrl :: Text}
    deriving stock (Eq, Show)

{- | Render-time hook from leaf substrate value to an optional URL.
When set on 'HumanRenderOptions', the renderer consults it at every
atomic-leaf insertion site; a 'Just' result appends @ [url]@ to the
node label, a 'Nothing' result is a no-op.
-}
type LeafLinker = ConwayDiffValue -> Maybe Url

-- | Options for human-oriented diff rendering.
data HumanRenderOptions = HumanRenderOptions
    { humanRenderShape :: RenderShape
    , humanTreeArt :: TreeArt
    , humanCollapseRules :: Maybe CollapseRules
    , humanRenameRules :: Maybe RenameRules
    -- ^ Stage 2 rename rules to apply to leaf identifiers (payment
    -- addresses, script hashes) before rendering. 'Nothing' (the
    -- default) leaves every leaf verbatim. Wired by S3 of
    -- @specs\/032-tx-inspect@; the S1 renderer reads the field but
    -- does not apply it.
    , humanHideEmpty :: Bool
    -- ^ When 'True', suppress the @datum@ leaf for
    -- 'Cardano.Ledger.Api.Scripts.Data.NoDatum' and the
    -- @referenceScript@ leaf for
    -- 'Cardano.Ledger.BaseTypes.SNothing' at every body-output site.
    -- Default 'False' — the diff renderer keeps showing empty
    -- markers so a diff can surface "datum disappeared".
    -- @tx-inspect@ flips this to 'True' so single-tx renders are
    -- not visually swamped by @cbor: (0 bytes)@ and @null@ leaves.
    , humanLeafLinker :: Maybe LeafLinker
    -- ^ Optional render-time URL emitter (issue #88). When 'Just',
    -- the trie walker consults it at every atomic-leaf insertion
    -- site (both the renamed-leaf branch and the verbatim-leaf
    -- branch) and appends @ [url]@ to the node label on a 'Just'
    -- result. Default 'Nothing' — the renderer is byte-stable
    -- against pre-#88 output when the field is left unset. Wired
    -- by @tx-inspect@'s @--links=cardanoscan@ flag.
    }

-- 'humanLeafLinker' carries a function, so 'HumanRenderOptions' no
-- longer derives 'Eq' or 'Show' automatically. The hand-written
-- instances below compare and print every field except the linker;
-- the linker is presence-only (Nothing vs Just) for 'Eq' and prints
-- as @<fn>@ for 'Show'. Two configurations are considered
-- "equivalent options" if everything except the link function
-- agrees; this matches how 'TxDiffCliOptions' tests use
-- 'shouldBe' to compare parsed configurations structurally.
instance Eq HumanRenderOptions where
    a == b =
        humanRenderShape a == humanRenderShape b
            && humanTreeArt a == humanTreeArt b
            && humanCollapseRules a == humanCollapseRules b
            && humanRenameRules a == humanRenameRules b
            && humanHideEmpty a == humanHideEmpty b
            && isJust (humanLeafLinker a) == isJust (humanLeafLinker b)

instance Show HumanRenderOptions where
    show opts =
        "HumanRenderOptions { humanRenderShape = "
            <> show (humanRenderShape opts)
            <> ", humanTreeArt = "
            <> show (humanTreeArt opts)
            <> ", humanCollapseRules = "
            <> show (humanCollapseRules opts)
            <> ", humanRenameRules = "
            <> show (humanRenameRules opts)
            <> ", humanHideEmpty = "
            <> show (humanHideEmpty opts)
            <> ", humanLeafLinker = "
            <> maybe "Nothing" (const "Just <fn>") (humanLeafLinker opts)
            <> " }"

-- | Default human renderer: grouped tree output with portable ASCII art.
defaultHumanRenderOptions :: HumanRenderOptions
defaultHumanRenderOptions =
    HumanRenderOptions
        { humanRenderShape = RenderTree
        , humanTreeArt = TreeArtAscii
        , humanCollapseRules = Nothing
        , humanRenameRules = Nothing
        , humanHideEmpty = False
        , humanLeafLinker = Nothing
        }

data CollapseRawView
    = CollapseRawShow
    | CollapseRawHide
    deriving stock (Eq, Show)

data CollapseRules = CollapseRules
    { collapseRawView :: CollapseRawView
    , collapseRules :: [CollapseRule]
    }
    deriving stock (Eq, Show)

data CollapseRule = CollapseRule
    { collapseRuleName :: Text
    , collapseRuleAt :: DiffPath
    , collapseRuleRequired :: [DiffPath]
    }
    deriving stock (Eq, Show)

newtype CollapseRuleMatch = CollapseRuleMatch [DiffPath]

newtype CollapseViews = CollapseViews CollapseRawView

{- | Top-level rewriting wrapper carrying both stages of the
@tx-inspect@ pipeline.

The on-disk YAML grammar that maps to this type is documented in
@specs\/032-tx-inspect\/contracts\/rules-yaml-grammar.md@; the parser
('Cardano.Tx.Rewrite.parseRewriteRulesYaml') and the FromJSON
instances for the rename half live in 'Cardano.Tx.Rewrite' to keep the
new module addressable independently of the diff core. The types live
here so 'HumanRenderOptions' can refer to them without an import cycle.

Stage order is engine-enforced (collapse first, rename second) and is
independent of the document's key order.
-}
data RewriteRules = RewriteRules
    { rewriteCollapse :: CollapseRules
    -- ^ Stage 1 rules — reuses 'CollapseRules' unchanged.
    , rewriteRename :: RenameRules
    -- ^ Stage 2 rules — payment-address and script-hash substitutions.
    }
    deriving stock (Eq, Show)

{- | Defaults: empty collapse with the canonical raw-view setting, and
empty rename. This is what a @{}@ document parses to.
-}
defaultRewriteRules :: RewriteRules
defaultRewriteRules =
    RewriteRules
        { rewriteCollapse =
            CollapseRules
                { collapseRawView = CollapseRawShow
                , collapseRules = []
                }
        , rewriteRename = emptyRenameRules
        }

-- | Ordered collection of 'RenameRule' values.
newtype RenameRules = RenameRules
    { renameEntries :: [RenameRule]
    }
    deriving stock (Eq, Show)

{- | Empty list of rename rules — the parse result when the YAML
document has no @rename:@ key.
-}
emptyRenameRules :: RenameRules
emptyRenameRules = RenameRules []

{- | One rename rule. 'RenameAddress' targets payment-address sites in
body inputs (after resolution), body outputs, withdrawals, and
certificates. 'RenameScript' targets script-hash sites in body, witness
set, and reference scripts.
-}
data RenameRule
    = RenameAddress
        { renameAddressKey :: Text
        -- ^ The bech32 string as it appeared in the YAML, preserved
        -- verbatim for round-trip + error messages.
        , renameAddressMatch :: AddressMatch
        , renameAddressTarget :: AddressTarget
        -- ^ Pre-computed lookup key set by the YAML loader so the apply
        -- path is a constant-time lookup per site.
        , renameName :: Text
        }
    | RenameScript
        { renameScriptHash :: ScriptHash
        , renameName :: Text
        }
    deriving stock (Eq, Show)

{- | YAML @match:@ field for address rules.

* 'MatchFull' matches the entire 'Addr' byte-for-byte.
* 'MatchPayment' (the default) matches the payment credential only and
  so covers every stake variant of the same payment script.

For 'RenameScript' rules @match:@ is parsed (and validated) but
discarded — script hashes have no sub-structure to vary over.
-}
data AddressMatch
    = MatchFull
    | MatchPayment
    deriving stock (Eq, Show)

-- | Pre-computed lookup key for an address rename rule.
data AddressTarget
    = -- | Built from the bech32 when @match: full@ is requested.
      TargetFullAddress Addr
    | -- | Extracted from the bech32 when @match: payment@ is requested.
      TargetPaymentCredential (Credential Payment)
    deriving stock (Eq, Show)

parseCollapseRulesYaml :: BS.ByteString -> Either String CollapseRules
parseCollapseRulesYaml input =
    case Yaml.decodeEither' input of
        Left err ->
            Left (Yaml.prettyPrintParseException err)
        Right rules ->
            Right rules

{- | Parse a unified rewriting-rules YAML document.

The accepted grammar is documented in
@specs\/032-tx-inspect\/contracts\/rules-yaml-grammar.md@. Briefly:

@
version: 1                          # optional, defaults to 1
views:                              # optional
  raw: show | hide                  # optional, defaults to show
collapse:                           # optional, defaults to []
  - \<CollapseRule\>
rename:                             # optional, defaults to []
  - \<RenameRule\>
@

Backwards-compatible: every YAML document that 'parseCollapseRulesYaml'
accepts today parses to a 'RewriteRules' whose 'rewriteCollapse' equals
the legacy parser's result and whose 'rewriteRename' is
'emptyRenameRules'. The user-facing API for this parser is
'Cardano.Tx.Rewrite.parseRewriteRulesYaml', which re-exports this
binding; defining it here keeps the rewriting-rules 'FromJSON'
instances co-located with their types and avoids the orphan-instance
warning.

Returns @Left@ on YAML decode failure, an unsupported @version:@, a
malformed rename entry (unknown @kind:@, invalid @match:@, invalid
bech32 in a @kind: address@ rule, non-28-byte hex in a @kind: script@
rule, or an empty @name:@), or any other constraint failure.
-}
parseRewriteRulesYaml :: BS.ByteString -> Either String RewriteRules
parseRewriteRulesYaml input =
    case Yaml.decodeEither' input :: Either Yaml.ParseException Aeson.Value of
        Left err ->
            Left (Yaml.prettyPrintParseException err)
        Right value -> do
            collapse <- parseCollapseRulesYaml input
            rename <- parseEither parseRenameSection value
            pure
                RewriteRules
                    { rewriteCollapse = collapse
                    , rewriteRename = rename
                    }
  where
    parseRenameSection =
        Aeson.withObject "RewriteRules" $ \obj -> do
            version <- obj .:? "version" .!= (1 :: Int)
            when (version /= 1) $
                fail ("unsupported rewriting rules version: " <> show version)
            obj .:? "rename" .!= emptyRenameRules

instance FromJSON RenameRules where
    parseJSON value = do
        entries <- parseJSON value
        pure (RenameRules entries)

instance FromJSON RenameRule where
    parseJSON =
        Aeson.withObject "RenameRule" $ \obj -> do
            kind <- obj .: "kind" :: Parser Text
            name <- obj .: "name"
            when (Text.null name) $
                fail "rename rule name must not be empty"
            case kind of
                "address" -> do
                    keyText <- obj .: "key"
                    match <- obj .:? "match" .!= MatchPayment
                    target <- parseAddressTarget keyText match
                    pure
                        RenameAddress
                            { renameAddressKey = keyText
                            , renameAddressMatch = match
                            , renameAddressTarget = target
                            , renameName = name
                            }
                "script" -> do
                    -- `match:` on a script rule is accepted and ignored
                    -- (validated for predictable error messages but never
                    -- consulted).
                    _ <- obj .:? "match" :: Parser (Maybe AddressMatch)
                    keyText <- obj .: "key"
                    hash <- parseScriptHash keyText
                    pure
                        RenameScript
                            { renameScriptHash = hash
                            , renameName = name
                            }
                other ->
                    fail $
                        "unsupported rename rule kind: "
                            <> Text.unpack other
                            <> " (expected: address | script)"

instance FromJSON AddressMatch where
    parseJSON =
        Aeson.withText "AddressMatch" $ \case
            "full" -> pure MatchFull
            "payment" -> pure MatchPayment
            other ->
                fail $
                    "unsupported address match: "
                        <> Text.unpack other
                        <> " (expected: full | payment)"

{- | Decode a bech32 address into the lookup target the apply path
needs. The bech32 itself is validated (data-part bytes are decoded
and run through the ledger decoder); a failure at any step surfaces
as a parser error so the rule never reaches the apply path in an
ambiguous state.
-}
parseAddressTarget :: Text -> AddressMatch -> Parser AddressTarget
parseAddressTarget keyText match =
    case decodeBech32Address keyText of
        Left err ->
            fail $
                "invalid bech32 address in rename rule: "
                    <> Text.unpack keyText
                    <> " ("
                    <> err
                    <> ")"
        Right addr ->
            case match of
                MatchFull ->
                    pure (TargetFullAddress addr)
                MatchPayment ->
                    case paymentCredentialFromAddr addr of
                        Just credential ->
                            pure (TargetPaymentCredential credential)
                        Nothing ->
                            fail $
                                "rename rule with match: payment requires a"
                                    <> " base or enterprise address; got a"
                                    <> " Byron bootstrap address: "
                                    <> Text.unpack keyText

{- | Decode a bech32-encoded Cardano address to its ledger 'Addr'.

Returns @Left@ on any bech32 framing error, an unrecoverable
data-part, or a ledger decode failure. Mainnet (@addr1@) and testnet
(@addr_test1@) prefixes are both accepted; the loader does not pin
a network.
-}
decodeBech32Address :: Text -> Either String Addr
decodeBech32Address keyText =
    case Bech32.decodeLenient keyText of
        Left err ->
            Left ("bech32 decode failed: " <> show err)
        Right (_hrp, dataPart) ->
            case Bech32.dataPartToBytes dataPart of
                Nothing ->
                    Left "bech32 data-part not byte-aligned"
                Just bytes ->
                    case decodeAddrEither bytes of
                        Left err ->
                            Left ("ledger address decode failed: " <> err)
                        Right addr ->
                            Right addr

{- | Extract the payment credential from a Shelley-era 'Addr'. Byron
bootstrap addresses have no separable payment credential, so they
yield 'Nothing' (the parser then rejects @match: payment@ on them).
-}
paymentCredentialFromAddr :: Addr -> Maybe (Credential Payment)
paymentCredentialFromAddr (Addr _network payment _stake) =
    Just payment
paymentCredentialFromAddr (AddrBootstrap _) =
    Nothing

{- | Parse a 28-byte (56 hex-character) script hash. Case is
canonicalised to lowercase before decoding.
-}
parseScriptHash :: Text -> Parser ScriptHash
parseScriptHash keyText = do
    let lowered = Text.toLower keyText
    when (Text.length lowered /= 56) $
        fail $
            "invalid script hash in rename rule: expected 56 hex"
                <> " characters, got "
                <> show (Text.length lowered)
                <> ": "
                <> Text.unpack keyText
    bytes <- case Base16.decode (TextEncoding.encodeUtf8 lowered) of
        Left err ->
            fail $
                "invalid hex in script hash: "
                    <> Text.unpack keyText
                    <> " ("
                    <> err
                    <> ")"
        Right bs -> pure bs
    when (BS.length bytes /= 28) $
        fail $
            "invalid script hash byte length: expected 28, got "
                <> show (BS.length bytes)
    case hashFromBytes bytes of
        Nothing ->
            fail $
                "invalid script hash bytes: "
                    <> Text.unpack keyText
        Just hash ->
            pure (ScriptHash hash)

instance FromJSON CollapseRules where
    parseJSON =
        Aeson.withObject "CollapseRules" $ \value -> do
            version <- value .:? "version" .!= (1 :: Int)
            when (version /= 1) $
                fail ("unsupported collapse rules version: " <> show version)
            CollapseViews rawView <- value .:? "views" .!= CollapseViews CollapseRawShow
            rules <- value .:? "collapse" .!= []
            pure
                CollapseRules
                    { collapseRawView = rawView
                    , collapseRules = rules
                    }

instance FromJSON CollapseViews where
    parseJSON =
        Aeson.withObject "CollapseViews" $ \value ->
            CollapseViews <$> value .:? "raw" .!= CollapseRawShow

instance FromJSON CollapseRawView where
    parseJSON =
        Aeson.withText "CollapseRawView" $ \value ->
            case value of
                "show" ->
                    pure CollapseRawShow
                "hide" ->
                    pure CollapseRawHide
                _ ->
                    fail ("unsupported raw collapse view: " <> Text.unpack value)

instance FromJSON CollapseRule where
    parseJSON =
        Aeson.withObject "CollapseRule" $ \value -> do
            name <- value .: "name"
            at <- value .: "at"
            CollapseRuleMatch required <- value .: "match"
            when (null required) $
                fail "collapse rule match.required must not be empty"
            pure
                CollapseRule
                    { collapseRuleName = name
                    , collapseRuleAt = at
                    , collapseRuleRequired = required
                    }

instance FromJSON CollapseRuleMatch where
    parseJSON =
        Aeson.withObject "CollapseRuleMatch" $ \value ->
            CollapseRuleMatch <$> value .: "required"

instance FromJSON DiffPath where
    parseJSON =
        Aeson.withText "DiffPath" (pure . textDiffPath)

data ConwayDiffValue
    = ConwayTxValue ConwayTx
    | ConwayBodyValue ConwayTx
    | ConwayCoinValue Coin
    | ConwayStrictMaybeCoinValue (StrictMaybe Coin)
    | ConwayInputsValue [TxIn]
    | ConwayTxInValue TxIn
    | ConwayTxInIdValue TxIn
    | ConwayKeyHashesValue [KeyHash Guard]
    | ConwayKeyHashValue (KeyHash Guard)
    | ConwayMintValue MultiAsset
    | ConwayAssetQuantitiesValue (Map AssetName Integer)
    | ConwayIntegerValue Integer
    | ConwayWithdrawalsValue Withdrawals
    | ConwayValidityIntervalValue ValidityInterval
    | ConwaySlotBoundValue (StrictMaybe SlotNo)
    | ConwayOutputsValue [TxOut ConwayEra]
    | ConwayTxOutValue (TxOut ConwayEra)
    | ConwayTxOutAssetsValue MultiAsset
    | ConwayAddressValue Addr
    | ConwayDatumValue (Datum ConwayEra)
    | ConwayReferenceScriptValue (StrictMaybe (Script ConwayEra))
    | ConwayWitnessesValue ConwayTx
    | ConwayBootstrapWitnessesValue [BootstrapWitness]
    | ConwayBootstrapWitnessValue BootstrapWitness
    | ConwayVKeyWitnessesValue [WitVKey Witness]
    | ConwayVKeyWitnessValue (WitVKey Witness)
    | ConwayDatumWitnessesValue (TxDats ConwayEra)
    | ConwayDataValue TxDiffDataSelector (Data ConwayEra)
    | ConwayRedeemersValue (Redeemers ConwayEra)
    | ConwayRedeemerValue (Data ConwayEra, ExUnits)
    | ConwayExUnitsValue ExUnits
    | ConwayScriptsValue (Map ScriptHash (Script ConwayEra))
    | ConwayScriptValue (Script ConwayEra)
    | ConwayOpenValue OpenValue

diffConwayTx :: ConwayTx -> ConwayTx -> DiffNode
diffConwayTx =
    diffConwayTxWith defaultTxDiffOptions

diffConwayTxWith :: TxDiffOptions -> ConwayTx -> ConwayTx -> DiffNode
diffConwayTxWith options left right =
    diffWith (conwayDiffPlan options) (ConwayTxValue left) (ConwayTxValue right)

diffConwayTxInput ::
    ByteString -> ByteString -> Either TxInputDecodeError DiffNode
diffConwayTxInput =
    diffConwayTxInputWith defaultTxDiffOptions

diffConwayTxInputWith ::
    TxDiffOptions -> ByteString -> ByteString -> Either TxInputDecodeError DiffNode
diffConwayTxInputWith options leftInput rightInput = do
    left <- decodeConwayTxInput leftInput
    right <- decodeConwayTxInput rightInput
    pure (diffConwayTxWith options left right)

renderConwayTxInputDiff ::
    ByteString -> ByteString -> Either TxInputDecodeError Text
renderConwayTxInputDiff leftInput rightInput =
    renderDiffNodeHuman <$> diffConwayTxInput leftInput rightInput

decodeConwayTxInput :: ByteString -> Either TxInputDecodeError ConwayTx
decodeConwayTxInput input =
    case Aeson.eitherDecodeStrict' input of
        Right envelope ->
            decodeConwayTxHex (txTextEnvelopeCborHex envelope)
        Left _
            | isHexInput input ->
                decodeConwayTxHex
                    (TextEncoding.decodeUtf8 (strippedHexInput input))
            | otherwise ->
                decodeConwayTxRaw input

newtype TxTextEnvelope = TxTextEnvelope
    { txTextEnvelopeCborHex :: Text
    }

instance Aeson.FromJSON TxTextEnvelope where
    parseJSON =
        Aeson.withObject "cardano-cli transaction text envelope" $ \value ->
            TxTextEnvelope <$> value .: "cborHex"

decodeConwayTxHex :: Text -> Either TxInputDecodeError ConwayTx
decodeConwayTxHex hex =
    case decodeFullAnnotatorFromHexText
        (natVersion @11)
        "Conway transaction"
        conwayTxDecoder
        (Text.strip hex) of
        Right tx ->
            Right tx
        Left err ->
            Left (TxInputDecodeError (Text.pack (show err)))

decodeConwayTxRaw :: ByteString -> Either TxInputDecodeError ConwayTx
decodeConwayTxRaw raw =
    case decodeFullAnnotator
        (natVersion @11)
        "Conway transaction"
        conwayTxDecoder
        (LBS.fromStrict raw) of
        Right tx ->
            Right tx
        Left err ->
            Left (TxInputDecodeError (Text.pack (show err)))

conwayTxDecoder :: forall s. Decoder s (Annotator ConwayTx)
conwayTxDecoder =
    decCBOR

isHexInput :: ByteString -> Bool
isHexInput input =
    let stripped = strippedHexInput input
     in not (BS.null stripped) && BS8.all isHexDigit stripped

strippedHexInput :: ByteString -> ByteString
strippedHexInput =
    BS8.filter (not . isSpace)

diffOpenValue :: OpenValue -> OpenValue -> DiffNode
diffOpenValue =
    diffWith openValuePlan

diffWith :: DiffPlan a -> a -> a -> DiffNode
diffWith plan =
    diffAt plan (DiffPath [])

diffNodeHasChanges :: DiffNode -> Bool
diffNodeHasChanges (DiffNode _ change) =
    case change of
        DiffSame _ ->
            False
        DiffChanged _ _ ->
            True
        DiffObject _ changed onlyA onlyB ->
            any diffNodeHasChanges changed
                || not (Map.null onlyA)
                || not (Map.null onlyB)
        DiffArray _ changed onlyA onlyB ->
            any (diffNodeHasChanges . snd) changed
                || not (null onlyA)
                || not (null onlyB)

diffAt :: DiffPlan a -> DiffPath -> a -> a -> DiffNode
diffAt plan path left right
    | diffEqual plan left right = DiffNode path (DiffSame (diffSummary plan left))
    | otherwise =
        case (diffProject plan left, diffProject plan right) of
            (DiffObjectChildren leftChildren, DiffObjectChildren rightChildren) ->
                diffObjectChildren plan path leftChildren rightChildren
            (DiffArrayChildren leftChildren, DiffArrayChildren rightChildren) ->
                diffArrayChildren plan path leftChildren rightChildren
            (leftProjection, rightProjection) ->
                DiffNode path $
                    DiffChanged
                        (projectionValue plan leftProjection)
                        (projectionValue plan rightProjection)

diffObjectChildren ::
    DiffPlan a ->
    DiffPath ->
    Map Text a ->
    Map Text a ->
    DiffNode
diffObjectChildren plan path leftChildren rightChildren =
    DiffNode path (DiffObject common changed onlyA onlyB)
  where
    keys =
        Map.keysSet leftChildren <> Map.keysSet rightChildren
    (common, changed, onlyA, onlyB) =
        foldr classify (Map.empty, Map.empty, Map.empty, Map.empty) keys

    classify key (commonAcc, changedAcc, onlyAAcc, onlyBAcc) =
        case (Map.lookup key leftChildren, Map.lookup key rightChildren) of
            (Just left, Just right)
                | diffEqual plan left right ->
                    ( Map.insert key (diffSummary plan left) commonAcc
                    , changedAcc
                    , onlyAAcc
                    , onlyBAcc
                    )
                | otherwise ->
                    ( commonAcc
                    , Map.insert key (diffAt plan (path </> key) left right) changedAcc
                    , onlyAAcc
                    , onlyBAcc
                    )
            (Just left, Nothing) ->
                ( commonAcc
                , changedAcc
                , Map.insert key (valueOf plan left) onlyAAcc
                , onlyBAcc
                )
            (Nothing, Just right) ->
                ( commonAcc
                , changedAcc
                , onlyAAcc
                , Map.insert key (valueOf plan right) onlyBAcc
                )
            (Nothing, Nothing) ->
                (commonAcc, changedAcc, onlyAAcc, onlyBAcc)

diffArrayChildren :: DiffPlan a -> DiffPath -> [a] -> [a] -> DiffNode
diffArrayChildren plan path leftChildren rightChildren =
    DiffNode path (DiffArray common changed onlyA onlyB)
  where
    paired =
        zip [0 :: Int ..] (zip leftChildren rightChildren)
    common =
        [ (index, diffSummary plan left)
        | (index, (left, right)) <- paired
        , diffEqual plan left right
        ]
    changed =
        [ (index, diffAt plan (path </> Text.pack (show index)) left right)
        | (index, (left, right)) <- paired
        , not (diffEqual plan left right)
        ]
    onlyA =
        [ (index, valueOf plan left)
        | (index, left) <-
            drop (length rightChildren) (zip [0 :: Int ..] leftChildren)
        ]
    onlyB =
        [ (index, valueOf plan right)
        | (index, right) <-
            drop (length leftChildren) (zip [0 :: Int ..] rightChildren)
        ]

valueOf :: DiffPlan a -> a -> Aeson.Value
valueOf plan =
    projectionValue plan . diffProject plan

projectionValue :: DiffPlan a -> DiffProjection a -> Aeson.Value
projectionValue _ (DiffAtomic value) =
    value
projectionValue plan (DiffObjectChildren children) =
    objectValue
        [ (key, valueOf plan child)
        | (key, child) <- Map.toAscList children
        ]
projectionValue plan (DiffArrayChildren children) =
    Aeson.toJSON (map (valueOf plan) children)

objectValue :: [(Text, Aeson.Value)] -> Aeson.Value
objectValue fields =
    Aeson.Object $
        KeyMap.fromList
            [ (Key.fromText key, value)
            | (key, value) <- fields
            ]

renderDiffNodeHuman :: DiffNode -> Text
renderDiffNodeHuman =
    renderDiffNodeHumanWith defaultHumanRenderOptions

renderDiffNodeHumanWith :: HumanRenderOptions -> DiffNode -> Text
renderDiffNodeHumanWith options diff =
    case humanRenderShape options of
        RenderPaths ->
            Text.unlines (renderDiffNodeLines diff)
        RenderTree ->
            renderDiffNodeTree options diff

{- | Render a single Conway transaction as a human-readable structural
tree. This is the @tx-inspect@ entry point: it walks the same
'conwayDiffProjection' the diff renderer walks and feeds the resulting
leaves through the same 'renderJsonValue' / 'renderForest' primitives,
so a single transaction renders identically here and on one side of
'renderDiffNodeHumanWith' against itself.

The 'TxDiffOptions' argument is the same record 'diffConwayTxWith'
accepts: in particular 'txDiffResolvedInputs' enables the @resolved@
sub-tree under each input. 'txDiffIncludeWitnesses' selects whether
the @witnesses@ branch is emitted alongside @body@. 'txDiffDecodeData'
controls blueprint-aware datum decoding.

The 'humanCollapseRules' field is consulted by the 'RenderTree' walker
exactly as it is by the diff renderer: at every array site whose
'DiffPath' matches a rule's @at:@, the matching rule emits one or more
named-shape view entries grouping array indices that share the same
required-leaf values, and the surrounding raw subtree is rendered
under @\<path\>\/raw@ (when @views.raw == show@) or pruned of covered
leaves (when @views.raw == hide@). For 'RenderPaths' the collapse
field is ignored; the path-shape output is a flat verbatim listing.

The 'humanRenameRules' field, when 'Just', substitutes every
payment-address ('ConwayAddressValue') and script leaf
('ConwayScriptValue', 'ConwayReferenceScriptValue') in the projection
that matches a rule under the rule's @name:@ string. Substitution is
best-effort: an unknown identifier renders verbatim. The site list is
defined by FR-009 of @specs\/032-tx-inspect@: payment addresses in
body inputs (after resolution), body outputs, and the leaves of the
witness / reference-script projections. Rename does NOT descend into
datum subtrees ('ConwayDatumValue' / 'ConwayDataValue' /
'ConwayOpenValue') in this slice — those follow-ups are tracked in
follow-up tickets per the spec's site-list note.

For the 'RenderPaths' shape collapse and rename are both ignored; the
path-shape output is a flat verbatim listing.
-}
renderConwayTxHuman :: HumanRenderOptions -> TxDiffOptions -> ConwayTx -> Text
renderConwayTxHuman options diffOptions tx =
    renderConwayDiffValueHuman options diffOptions (ConwayTxValue tx)

{- | Render any 'ConwayDiffValue' subtree using the same shared trie
walker 'renderConwayTxHuman' uses. The 'humanCollapseRules' and
'humanRenameRules' fields are both consulted; both can be 'Nothing'
for a verbatim render. Useful for downstream consumers that hold a
projection-level value (e.g., a single body output) and want the
exact bytes a top-level render would emit for that subtree, with no
@body@ / @witnesses@ wrapping.
-}
renderConwayDiffValueHuman ::
    HumanRenderOptions -> TxDiffOptions -> ConwayDiffValue -> Text
renderConwayDiffValueHuman options diffOptions root =
    case humanRenderShape options of
        RenderPaths ->
            Text.unlines (renderValueLines (collectValueLines diffOptions (DiffPath []) root))
        RenderTree ->
            renderForest (humanTreeArt options) $
                renderTrieForest $
                    collectValueTrie
                        diffOptions
                        (humanCollapseRules options)
                        (humanRenameRules options)
                        (humanLeafLinker options)
                        (humanHideEmpty options)
                        (DiffPath [])
                        emptyRenderTrie
                        root

{- | Render an 'OpenValue' subtree as a human-readable structural tree
using the default 'HumanRenderOptions'. Convenience wrapper over
'renderOpenValueHumanWith'.
-}
renderOpenValueHuman :: OpenValue -> Text
renderOpenValueHuman =
    renderOpenValueHumanWith defaultHumanRenderOptions

{- | Render an 'OpenValue' subtree directly, sharing the same render
primitives the rest of the human renderer uses. 'humanCollapseRules'
and 'humanRenameRules' are read but NOT applied in slice S1 (S3 wires
the rename layer against datum / redeemer subtrees).
-}
renderOpenValueHumanWith :: HumanRenderOptions -> OpenValue -> Text
renderOpenValueHumanWith options value =
    case humanRenderShape options of
        RenderPaths ->
            Text.unlines $
                renderValueLines $
                    collectOpenValueLines (DiffPath []) value
        RenderTree ->
            renderForest (humanTreeArt options) $
                renderTrieForest $
                    collectOpenValueTrie
                        (DiffPath [])
                        emptyRenderTrie
                        value

{- | Walk a 'ConwayDiffValue' projection into a 'RenderTrie', sharing
the same trie primitives the diff renderer uses. The /atomic/ branch
emits the leaf via 'renderJsonValue' so the per-leaf bytes match the
diff path exactly.

When 'humanCollapseRules' is 'Just', every array site whose 'DiffPath'
matches a 'CollapseRule''s @at:@ field is rewritten in the same shape
the diff renderer emits: one named-shape view per matching rule,
grouping the array indices that share the same required-leaf
'Aeson.Value', plus the raw subtree gated by 'collapseRawView'. The
semantics mirror 'collectDiffArray' so a one-side rendering of an
\"unchanged\" diff equals 'renderConwayTxHuman' on the same input.
-}
collectValueTrie ::
    TxDiffOptions ->
    Maybe CollapseRules ->
    Maybe RenameRules ->
    Maybe LeafLinker ->
    -- | 'humanHideEmpty' — skip 'NoDatum' / 'SNothing' leaves.
    Bool ->
    DiffPath ->
    RenderTrie ->
    ConwayDiffValue ->
    RenderTrie
collectValueTrie options collapseConfig renameConfig linker hideEmpty path trie value
    | hideEmpty && isEmptyOptionalLeaf value = trie
    | otherwise =
        case renameValue renameConfig value of
            Just renamed ->
                insertPath
                    (renderValuePathSegments path)
                    [Tree.Node (annotateLeaf linker value (renderJsonValue (renameLeafValue renamed))) []]
                    trie
            Nothing ->
                case conwayDiffProjection options value of
                    DiffAtomic atomic ->
                        insertPath
                            (renderValuePathSegments path)
                            [Tree.Node (annotateLeaf linker value (renderJsonValue atomic)) []]
                            trie
                    DiffObjectChildren children ->
                        List.foldl'
                            ( \acc (key, child) ->
                                collectValueTrie
                                    options
                                    collapseConfig
                                    renameConfig
                                    linker
                                    hideEmpty
                                    (path </> key)
                                    acc
                                    child
                            )
                            trie
                            (Map.toAscList children)
                    DiffArrayChildren children ->
                        collectValueArray
                            options
                            collapseConfig
                            renameConfig
                            linker
                            hideEmpty
                            path
                            trie
                            (zip [0 :: Int ..] children)

{- | Append @ [url]@ to a rendered leaf label when the linker matches.
A 'Nothing' linker (the default) is a no-op so renders stay
byte-stable. The space + bracket framing matches the @[name]@
convention rename uses, so a renamed-then-linked leaf reads
@<rename> [https://...]@. Used at every atomic-leaf insertion in
'collectValueTrie' and 'collectValueTriePruned'.
-}
annotateLeaf :: Maybe LeafLinker -> ConwayDiffValue -> Text -> Text
annotateLeaf Nothing _ rendered = rendered
annotateLeaf (Just linker) value rendered =
    case linker value of
        Nothing -> rendered
        Just (Url url) -> rendered <> " [" <> url <> "]"

{- | Identify a 'ConwayDiffValue' whose render is a structurally-empty
optional leaf (the @TxOut@'s @datum@ when no datum is attached, and the
@TxOut@'s @referenceScript@ when no reference script is attached).
Used by 'collectValueTrie' / 'collectValueTriePruned' to suppress
the @cbor: (0 bytes)@ / @null@ noise when 'humanHideEmpty' is set.
-}
isEmptyOptionalLeaf :: ConwayDiffValue -> Bool
isEmptyOptionalLeaf (ConwayDatumValue NoDatum) = True
isEmptyOptionalLeaf (ConwayReferenceScriptValue SNothing) = True
isEmptyOptionalLeaf _ = False

{- | Intercept a 'ConwayDiffValue' that carries a rename-target leaf
(payment address, script, reference script). Returns 'Just' the rename
name to render in place of the raw bytes; returns 'Nothing' when the
value is not a rename site OR no rule matches. Rename is best-effort:
the absence of a matching rule is a non-event, not a failure.
-}
renameValue :: Maybe RenameRules -> ConwayDiffValue -> Maybe Text
renameValue Nothing _ = Nothing
renameValue (Just rules) value =
    case value of
        ConwayAddressValue addr ->
            lookupAddressRename rules addr
        ConwayScriptValue script ->
            lookupScriptRename rules (hashScript script)
        ConwayReferenceScriptValue (SJust script) ->
            lookupScriptRename rules (hashScript script)
        _ -> Nothing

{- | Look up an 'Addr' against the rename rule list. Address rules with
'MatchFull' compare the entire 'Addr' byte-for-byte; rules with
'MatchPayment' compare the payment credential only (one rule covers
every stake variant of the same payment script — the dominant
treasury-work case). Script rules are skipped. First match wins.
-}
lookupAddressRename :: RenameRules -> Addr -> Maybe Text
lookupAddressRename (RenameRules entries) addr =
    let paymentCred = paymentCredentialFromAddr addr
        matchRule (RenameScript _ _) = Nothing
        matchRule
            RenameAddress
                { renameAddressMatch = MatchFull
                , renameAddressTarget = TargetFullAddress target
                , renameName = name
                }
                | target == addr = Just name
                | otherwise = Nothing
        matchRule
            RenameAddress
                { renameAddressMatch = MatchPayment
                , renameAddressTarget = TargetPaymentCredential target
                , renameName = name
                } =
                case paymentCred of
                    Just pc | pc == target -> Just name
                    _ -> Nothing
        matchRule _ = Nothing
     in firstJust (map matchRule entries)

{- | Look up a 'ScriptHash' against the rename rule list. Address rules
are skipped. First match wins.
-}
lookupScriptRename :: RenameRules -> ScriptHash -> Maybe Text
lookupScriptRename (RenameRules entries) hash =
    let matchRule (RenameAddress{}) = Nothing
        matchRule (RenameScript ruleHash name)
            | ruleHash == hash = Just name
            | otherwise = Nothing
     in firstJust (map matchRule entries)

firstJust :: [Maybe a] -> Maybe a
firstJust = List.foldl' (<|>) Nothing

{- | Render a renamed leaf as a JSON string so the existing
'renderJsonValue' / 'collapseRawView' / leaf-rendering primitives can
emit it without a new branch.
-}
renameLeafValue :: Text -> Aeson.Value
renameLeafValue = Aeson.String

{- | Apply collapse rules (if any) at an array site, mirroring the
diff-renderer's 'collectDiffArray'. The decision tree is:

* No matching rule emits a view: walk the array verbatim, one trie
  child per index.
* At least one rule emitted a view AND @views.raw == show@: emit the
  view(s) AND walk the raw array under @\<path\>\/raw@.
* At least one rule emitted a view AND @views.raw == hide@: emit the
  view(s) AND walk only the leaves that NO rule covered, under
  @\<path\>@ (no @raw@ infix). If every leaf is covered, the raw
  branch is dropped entirely.
-}
collectValueArray ::
    TxDiffOptions ->
    Maybe CollapseRules ->
    Maybe RenameRules ->
    Maybe LeafLinker ->
    Bool ->
    DiffPath ->
    RenderTrie ->
    [(Int, ConwayDiffValue)] ->
    RenderTrie
collectValueArray options collapseConfig renameConfig linker hideEmpty path trie indexedChildren =
    let matchingRules =
            collapseRulesAt collapseConfig path
        (withViews, hasView) =
            List.foldl'
                (insertValueCollapseView options path indexedChildren)
                (trie, False)
                matchingRules
        coveredLeaves =
            collapseCoveredValueLeafPaths options matchingRules indexedChildren
        walkRaw basePath acc =
            List.foldl'
                ( \innerAcc (idx, child) ->
                    collectValueTrie
                        options
                        collapseConfig
                        renameConfig
                        linker
                        hideEmpty
                        (basePath </> Text.pack (show idx))
                        innerAcc
                        child
                )
                acc
                indexedChildren
        walkPruned basePath acc =
            List.foldl'
                ( \innerAcc (idx, child) ->
                    let covered =
                            Map.findWithDefault Set.empty idx coveredLeaves
                     in collectValueTriePruned
                            options
                            collapseConfig
                            renameConfig
                            linker
                            hideEmpty
                            covered
                            (DiffPath [])
                            (basePath </> Text.pack (show idx))
                            innerAcc
                            child
                )
                acc
                indexedChildren
     in case (hasView, collapseRawViewEnabled collapseConfig) of
            (False, _) ->
                walkRaw path trie
            (True, CollapseRawShow) ->
                walkRaw (path </> "raw") withViews
            (True, CollapseRawHide) ->
                walkPruned path withViews

{- | Build (and emit into the trie) the view entries for one
'CollapseRule' applied to one array site. Returns @(trie', True)@ if
the rule matched any item; otherwise @(trie, hasView)@ unchanged.
-}
insertValueCollapseView ::
    TxDiffOptions ->
    DiffPath ->
    [(Int, ConwayDiffValue)] ->
    (RenderTrie, Bool) ->
    CollapseRule ->
    (RenderTrie, Bool)
insertValueCollapseView options listPath indexedChildren (trie, hasView) rule =
    case matchingItems of
        [] ->
            (trie, hasView)
        _ ->
            ( List.foldl'
                insertRequiredPath
                trie
                (collapseRuleRequired rule)
            , True
            )
  where
    matchingItems =
        [ (index, leaves)
        | (index, item) <- indexedChildren
        , Just leaves <- [collectValueRequiredLeaves options rule item]
        ]
    viewPath =
        listPath </> collapseRuleName rule
    insertRequiredPath currentTrie requiredPath =
        let grouped =
                groupValueLeaves
                    [ (index, leaf)
                    | (index, leaves) <- matchingItems
                    , Just leaf <- [lookup requiredPath leaves]
                    ]
         in List.foldl'
                (insertLeafGroup requiredPath)
                currentTrie
                grouped
    insertLeafGroup requiredPath currentTrie (indices, leaf) =
        insertPath
            ( diffPathSegments (viewPath </!> requiredPath)
                <> [renderIndexRanges indices]
            )
            [Tree.Node (renderJsonValue leaf) []]
            currentTrie

{- | Group array indices that share the same required-leaf 'Aeson.Value'
into contiguous-range buckets. Same shape as 'groupLeafDiffs' but
keyed on a single value, not a 'LeafDiff' pair.
-}
groupValueLeaves :: [(Int, Aeson.Value)] -> [([Int], Aeson.Value)]
groupValueLeaves =
    List.foldl' step []
  where
    step [] (index, leaf) =
        [([index], leaf)]
    step ((indices, leaf) : rest) (index, newLeaf)
        | leaf == newLeaf =
            (indices <> [index], leaf) : rest
    step (group : rest) indexedLeaf =
        group : step rest indexedLeaf

{- | For each 'CollapseRule' that matches an item, record the set of
required leaf paths it covered. Indexed by item index so the
'CollapseRawHide' branch can prune those exact leaves.
-}
collapseCoveredValueLeafPaths ::
    TxDiffOptions ->
    [CollapseRule] ->
    [(Int, ConwayDiffValue)] ->
    Map Int (Set.Set DiffPath)
collapseCoveredValueLeafPaths options rules indexedChildren =
    List.foldl' coverRule Map.empty rules
  where
    coverRule covered rule =
        List.foldl' (coverItem rule) covered indexedChildren
    coverItem rule covered (index, item) =
        case collectValueRequiredLeaves options rule item of
            Nothing ->
                covered
            Just _ ->
                Map.insertWith
                    Set.union
                    index
                    (Set.fromList (collapseRuleRequired rule))
                    covered

{- | Return the @Just leaves@ list iff every required path of the rule
resolves to a 'DiffAtomic' under the item's projection. The returned
list maps each required path to the looked-up leaf value.
-}
collectValueRequiredLeaves ::
    TxDiffOptions ->
    CollapseRule ->
    ConwayDiffValue ->
    Maybe [(DiffPath, Aeson.Value)]
collectValueRequiredLeaves options rule item =
    traverse
        ( \requiredPath -> do
            leaf <- lookupValueAtPath options requiredPath item
            pure (requiredPath, leaf)
        )
        (collapseRuleRequired rule)

{- | Walk @requiredPath@ inside @item@'s projection; return the leaf's
'Aeson.Value' iff every step lands on a child key (for objects) or
within array bounds (for arrays) and the final step lands on a
'DiffAtomic'. Anything else returns 'Nothing'.
-}
lookupValueAtPath ::
    TxDiffOptions -> DiffPath -> ConwayDiffValue -> Maybe Aeson.Value
lookupValueAtPath options (DiffPath segments) =
    go segments
  where
    go [] current =
        case conwayDiffProjection options current of
            DiffAtomic value -> Just value
            _ -> Nothing
    go (segment : rest) current =
        case conwayDiffProjection options current of
            DiffObjectChildren children -> do
                child <- Map.lookup segment children
                go rest child
            DiffArrayChildren children -> do
                index <- readDecimal segment
                child <- safeIndex children index
                go rest child
            DiffAtomic _ -> Nothing

    readDecimal :: Text -> Maybe Int
    readDecimal t = case reads (Text.unpack t) of
        [(n, "")] | n >= 0 -> Just n
        _ -> Nothing

    safeIndex :: [a] -> Int -> Maybe a
    safeIndex xs n
        | n < 0 = Nothing
        | otherwise = case drop n xs of
            (x : _) -> Just x
            [] -> Nothing

{- | A variant of 'collectValueTrie' that suppresses leaves whose
*relative* path (from the supplied @itemBase@) is in the @covered@
set. Used only by the @CollapseRawHide@ branch of 'collectValueArray'
to mirror the diff renderer's 'pruneCoveredLeaves'.
-}
collectValueTriePruned ::
    TxDiffOptions ->
    Maybe CollapseRules ->
    Maybe RenameRules ->
    Maybe LeafLinker ->
    Bool ->
    Set.Set DiffPath ->
    -- | relative path inside the current item (initially empty)
    DiffPath ->
    -- | absolute trie path
    DiffPath ->
    RenderTrie ->
    ConwayDiffValue ->
    RenderTrie
collectValueTriePruned options collapseConfig renameConfig linker hideEmpty covered relPath absPath trie value
    | relPath `Set.member` covered =
        trie
    | hideEmpty && isEmptyOptionalLeaf value =
        trie
    | otherwise =
        case renameValue renameConfig value of
            Just renamed ->
                insertPath
                    (renderValuePathSegments absPath)
                    [Tree.Node (annotateLeaf linker value (renderJsonValue (renameLeafValue renamed))) []]
                    trie
            Nothing ->
                case conwayDiffProjection options value of
                    DiffAtomic atomic ->
                        insertPath
                            (renderValuePathSegments absPath)
                            [Tree.Node (annotateLeaf linker value (renderJsonValue atomic)) []]
                            trie
                    DiffObjectChildren children ->
                        List.foldl'
                            ( \acc (key, child) ->
                                collectValueTriePruned
                                    options
                                    collapseConfig
                                    renameConfig
                                    linker
                                    hideEmpty
                                    covered
                                    (relPath </> key)
                                    (absPath </> key)
                                    acc
                                    child
                            )
                            trie
                            (Map.toAscList children)
                    DiffArrayChildren children ->
                        -- Nested arrays inside the item are walked
                        -- verbatim with the surrounding collapse /
                        -- rename config still active; the @covered@
                        -- set is described in terms of leaf paths from
                        -- the item root, so it never matches a nested
                        -- array prefix.
                        collectValueArray
                            options
                            collapseConfig
                            renameConfig
                            linker
                            hideEmpty
                            absPath
                            trie
                            (zip [0 :: Int ..] children)

{- | Walk an 'OpenValue' projection into a 'RenderTrie'. Mirrors
'collectValueTrie' but for the user-data substrate; the rename layer
(S3) will use this when descending into datum subtrees.
-}
collectOpenValueTrie ::
    DiffPath -> RenderTrie -> OpenValue -> RenderTrie
collectOpenValueTrie path trie value =
    case openValueProjection value of
        DiffAtomic atomic ->
            insertPath
                (renderValuePathSegments path)
                [Tree.Node (renderJsonValue atomic) []]
                trie
        DiffObjectChildren children ->
            List.foldl'
                ( \acc (key, child) ->
                    collectOpenValueTrie (path </> key) acc child
                )
                trie
                (Map.toAscList children)
        DiffArrayChildren children ->
            List.foldl'
                ( \acc (idx, child) ->
                    collectOpenValueTrie (path </> Text.pack (show idx)) acc child
                )
                trie
                (zip [0 :: Int ..] children)

{- | One value-rendering line: a path and the JSON-leaf rendering. The
'RenderPaths' shape emits one of these per leaf, formatted as
@<path>: <value>@.
-}
data ValueLine = ValueLine DiffPath Text

{- | Walk a 'ConwayDiffValue' into the flat ValueLine list 'RenderPaths'
consumes.
-}
collectValueLines ::
    TxDiffOptions -> DiffPath -> ConwayDiffValue -> [ValueLine]
collectValueLines options path value =
    case conwayDiffProjection options value of
        DiffAtomic atomic ->
            [ValueLine path (renderJsonValue atomic)]
        DiffObjectChildren children ->
            concatMap
                (\(key, child) -> collectValueLines options (path </> key) child)
                (Map.toAscList children)
        DiffArrayChildren children ->
            concat
                [ collectValueLines options (path </> Text.pack (show idx)) child
                | (idx, child) <- zip [0 :: Int ..] children
                ]

{- | Walk an 'OpenValue' into the flat 'ValueLine' list 'RenderPaths'
consumes.
-}
collectOpenValueLines :: DiffPath -> OpenValue -> [ValueLine]
collectOpenValueLines path value =
    case openValueProjection value of
        DiffAtomic atomic ->
            [ValueLine path (renderJsonValue atomic)]
        DiffObjectChildren children ->
            concatMap
                (\(key, child) -> collectOpenValueLines (path </> key) child)
                (Map.toAscList children)
        DiffArrayChildren children ->
            concat
                [ collectOpenValueLines (path </> Text.pack (show idx)) child
                | (idx, child) <- zip [0 :: Int ..] children
                ]

renderValueLines :: [ValueLine] -> [Text]
renderValueLines =
    map (\(ValueLine path value) -> renderPath path <> ": " <> value)

{- | Render-trie path segments for a value-walk leaf. Mirrors the
'renderedPathSegments' helper used by the diff renderer so empty
paths render under the canonical @<root>@ key.
-}
renderValuePathSegments :: DiffPath -> [Text]
renderValuePathSegments (DiffPath []) =
    ["<root>"]
renderValuePathSegments (DiffPath segments) =
    segments

data RenderTrie = RenderTrie
    { renderTrieLeaves :: [Tree.Tree Text]
    , renderTrieChildren :: Map Text RenderTrie
    }

data RenderSegmentSortKey
    = RenderSegmentText Text
    | RenderSegmentNumber Integer Text
    deriving stock (Eq, Ord, Show)

data LeafDiff = LeafDiff Aeson.Value Aeson.Value
    deriving stock (Eq, Show)

emptyRenderTrie :: RenderTrie
emptyRenderTrie =
    RenderTrie
        { renderTrieLeaves = []
        , renderTrieChildren = Map.empty
        }

renderDiffNodeTree :: HumanRenderOptions -> DiffNode -> Text
renderDiffNodeTree options diff@(DiffNode _ change) =
    case change of
        DiffSame _ ->
            Text.unlines (renderDiffNodeLines diff)
        _ ->
            renderForest (humanTreeArt options) $
                renderTrieForest $
                    collectDiffTree
                        (humanCollapseRules options)
                        emptyRenderTrie
                        diff

collectDiffTree :: Maybe CollapseRules -> RenderTrie -> DiffNode -> RenderTrie
collectDiffTree collapseRules trie node@(DiffNode path change) =
    case change of
        DiffSame _ ->
            trie
        DiffChanged left right ->
            insertPath
                (renderChangedPathSegments path)
                (renderChangedValueLeaves left right)
                trie
        DiffObject _ changed onlyA onlyB ->
            let withChanged =
                    List.foldl'
                        (collectDiffTree collapseRules)
                        trie
                        (Map.elems changed)
                withOnlyA =
                    List.foldl'
                        (insertObjectOnly "-" path)
                        withChanged
                        (Map.toAscList onlyA)
             in List.foldl'
                    (insertObjectOnly "+" path)
                    withOnlyA
                    (Map.toAscList onlyB)
        DiffArray common changed onlyA onlyB ->
            collectDiffArray collapseRules trie node path common changed onlyA onlyB

collectDiffArray ::
    Maybe CollapseRules ->
    RenderTrie ->
    DiffNode ->
    DiffPath ->
    [(Int, Maybe Aeson.Value)] ->
    [(Int, DiffNode)] ->
    [(Int, Aeson.Value)] ->
    [(Int, Aeson.Value)] ->
    RenderTrie
collectDiffArray collapseConfig trie node path common changed onlyA onlyB =
    let matchingRules =
            collapseRulesAt collapseConfig path
        (withViews, hasView) =
            List.foldl'
                (insertCollapseView path changed)
                (trie, False)
                matchingRules
        coveredLeaves =
            collapseCoveredLeafPaths matchingRules changed
        remainderChanged =
            [ (index, remainderItem)
            | (index, item) <- changed
            , Just remainderItem <-
                [ pruneCoveredLeaves
                    (Map.findWithDefault Set.empty index coveredLeaves)
                    item
                ]
            ]
        remainderNode =
            DiffNode path (DiffArray common remainderChanged onlyA onlyB)
     in case (hasView, collapseRawViewEnabled collapseConfig) of
            (False, _) ->
                collectRawDiffArray collapseConfig trie node
            (True, CollapseRawShow) ->
                collectRawDiffArray
                    collapseConfig
                    withViews
                    (rebaseDiffNode path (path </> "raw") node)
            (True, CollapseRawHide)
                | diffNodeHasChanges remainderNode ->
                    collectRawDiffArray
                        collapseConfig
                        withViews
                        remainderNode
                | otherwise ->
                    withViews

collectRawDiffArray :: Maybe CollapseRules -> RenderTrie -> DiffNode -> RenderTrie
collectRawDiffArray collapseRules trie (DiffNode path change) =
    case change of
        DiffArray _ changed onlyA onlyB ->
            let withChanged =
                    List.foldl'
                        (collectDiffTree collapseRules)
                        trie
                        (map snd changed)
                withOnlyA =
                    List.foldl'
                        (insertArrayOnly "-" path)
                        withChanged
                        onlyA
             in List.foldl'
                    (insertArrayOnly "+" path)
                    withOnlyA
                    onlyB
        _ ->
            collectDiffTree collapseRules trie (DiffNode path change)

collapseRulesAt :: Maybe CollapseRules -> DiffPath -> [CollapseRule]
collapseRulesAt Nothing _ =
    []
collapseRulesAt (Just rules) path =
    [ rule
    | rule <- collapseRules rules
    , collapseRuleAt rule == path
    ]

collapseRawViewEnabled :: Maybe CollapseRules -> CollapseRawView
collapseRawViewEnabled Nothing =
    CollapseRawShow
collapseRawViewEnabled (Just rules) =
    collapseRawView rules

collapseCoveredLeafPaths ::
    [CollapseRule] ->
    [(Int, DiffNode)] ->
    Map Int (Set.Set DiffPath)
collapseCoveredLeafPaths rules changed =
    List.foldl' coverRule Map.empty rules
  where
    coverRule covered rule =
        List.foldl' (coverItem rule) covered changed
    coverItem rule covered (index, item)
        | ruleMatchesItem rule item =
            Map.insertWith
                Set.union
                index
                (Set.fromList (collapseRuleRequired rule))
                covered
        | otherwise =
            covered

pruneCoveredLeaves :: Set.Set DiffPath -> DiffNode -> Maybe DiffNode
pruneCoveredLeaves covered node@(DiffNode rootPath _) =
    prune node
  where
    prune current@(DiffNode path change) =
        case change of
            DiffSame _ ->
                Nothing
            DiffChanged _ _
                | leafCovered path ->
                    Nothing
                | otherwise ->
                    Just current
            DiffObject common changed onlyA onlyB ->
                keepIfChanged $
                    DiffNode
                        path
                        ( DiffObject
                            common
                            (Map.mapMaybe prune changed)
                            onlyA
                            onlyB
                        )
            DiffArray common changed onlyA onlyB ->
                keepIfChanged $
                    DiffNode
                        path
                        ( DiffArray
                            common
                            [ (index, pruned)
                            | (index, item) <- changed
                            , Just pruned <- [prune item]
                            ]
                            onlyA
                            onlyB
                        )
    keepIfChanged pruned
        | diffNodeHasChanges pruned =
            Just pruned
        | otherwise =
            Nothing
    leafCovered path =
        case stripDiffPathPrefix rootPath path of
            Just relativePath ->
                relativePath `Set.member` covered
            Nothing ->
                False

insertCollapseView ::
    DiffPath ->
    [(Int, DiffNode)] ->
    (RenderTrie, Bool) ->
    CollapseRule ->
    (RenderTrie, Bool)
insertCollapseView listPath changed (trie, hasView) rule =
    case matchingItems of
        [] ->
            (trie, hasView)
        _ ->
            ( List.foldl'
                insertRequiredPath
                trie
                (collapseRuleRequired rule)
            , True
            )
  where
    matchingItems =
        [ (index, item, changedLeavesFromItem item)
        | (index, item) <- changed
        , ruleMatchesItem rule item
        ]
    viewPath =
        listPath </> collapseRuleName rule
    insertRequiredPath currentTrie requiredPath =
        let grouped =
                groupLeafDiffs
                    [ (index, leaf)
                    | (index, _, leaves) <- matchingItems
                    , Just leaf <- [lookup requiredPath leaves]
                    ]
         in List.foldl'
                (insertLeafGroup requiredPath)
                currentTrie
                grouped
    insertLeafGroup requiredPath currentTrie (indices, LeafDiff left right) =
        insertPath
            ( diffPathSegments (viewPath </!> requiredPath)
                <> [renderIndexRanges indices]
            )
            (renderChangedValueLeaves left right)
            currentTrie

ruleMatchesItem :: CollapseRule -> DiffNode -> Bool
ruleMatchesItem rule item =
    all
        (`elem` map fst leaves)
        (collapseRuleRequired rule)
  where
    leaves =
        changedLeavesFromItem item

changedLeavesFromItem :: DiffNode -> [(DiffPath, LeafDiff)]
changedLeavesFromItem item@(DiffNode rootPath _) =
    [ (relativePath, leaf)
    | (absolutePath, leaf) <- changedLeaves item
    , Just relativePath <- [stripDiffPathPrefix rootPath absolutePath]
    ]

changedLeaves :: DiffNode -> [(DiffPath, LeafDiff)]
changedLeaves (DiffNode path change) =
    case change of
        DiffSame _ ->
            []
        DiffChanged left right ->
            [(path, LeafDiff left right)]
        DiffObject _ changed _ _ ->
            concatMap changedLeaves (Map.elems changed)
        DiffArray _ changed _ _ ->
            concatMap (changedLeaves . snd) changed

groupLeafDiffs :: [(Int, LeafDiff)] -> [([Int], LeafDiff)]
groupLeafDiffs =
    List.foldl' addLeafDiffGroup []
  where
    addLeafDiffGroup [] (index, leaf) =
        [([index], leaf)]
    addLeafDiffGroup ((indices, leaf) : rest) (index, newLeaf)
        | leaf == newLeaf =
            (indices <> [index], leaf) : rest
    addLeafDiffGroup (group : rest) indexedLeaf =
        group : addLeafDiffGroup rest indexedLeaf

renderIndexRanges :: [Int] -> Text
renderIndexRanges indices =
    Text.intercalate "," $
        map renderRange $
            contiguousRanges (List.sort indices)
  where
    renderRange (start, end)
        | start == end =
            Text.pack (show start)
        | otherwise =
            Text.pack (show start) <> ".." <> Text.pack (show end)

contiguousRanges :: [Int] -> [(Int, Int)]
contiguousRanges [] =
    []
contiguousRanges (firstIndex : rest) =
    reverse (List.foldl' step [(firstIndex, firstIndex)] rest)
  where
    step [] index =
        [(index, index)]
    step ((start, end) : ranges) index
        | index == end + 1 =
            (start, index) : ranges
        | otherwise =
            (index, index) : (start, end) : ranges

rebaseDiffNode :: DiffPath -> DiffPath -> DiffNode -> DiffNode
rebaseDiffNode oldPath newPath (DiffNode path change) =
    DiffNode (replaceDiffPathPrefix oldPath newPath path) $
        case change of
            DiffSame value ->
                DiffSame value
            DiffChanged left right ->
                DiffChanged left right
            DiffObject common changed onlyA onlyB ->
                DiffObject
                    common
                    (Map.map (rebaseDiffNode oldPath newPath) changed)
                    onlyA
                    onlyB
            DiffArray common changed onlyA onlyB ->
                DiffArray
                    common
                    [ ( index
                      , rebaseDiffNode oldPath newPath child
                      )
                    | (index, child) <- changed
                    ]
                    onlyA
                    onlyB

stripDiffPathPrefix :: DiffPath -> DiffPath -> Maybe DiffPath
stripDiffPathPrefix (DiffPath prefix) (DiffPath path)
    | prefix `List.isPrefixOf` path =
        Just (DiffPath (drop (length prefix) path))
    | otherwise =
        Nothing

replaceDiffPathPrefix :: DiffPath -> DiffPath -> DiffPath -> DiffPath
replaceDiffPathPrefix oldPath newPath path =
    case stripDiffPathPrefix oldPath path of
        Just relativePath ->
            newPath </!> relativePath
        Nothing ->
            path

insertObjectOnly ::
    Text ->
    DiffPath ->
    RenderTrie ->
    (Text, Aeson.Value) ->
    RenderTrie
insertObjectOnly prefix path trie (key, value) =
    insertOnlyValue prefix (path </> key) value trie

insertArrayOnly ::
    Text ->
    DiffPath ->
    RenderTrie ->
    (Int, Aeson.Value) ->
    RenderTrie
insertArrayOnly prefix path trie (index, value) =
    insertOnlyValue prefix (path </> Text.pack (show index)) value trie

insertOnlyValue :: Text -> DiffPath -> Aeson.Value -> RenderTrie -> RenderTrie
insertOnlyValue prefix (DiffPath segments) value =
    case reverse segments of
        [] ->
            insertPath
                ["<root>"]
                [Tree.Node (prefix <> " " <> renderJsonValue value) []]
        key : parentSegments ->
            insertPath
                (reverse parentSegments)
                [ Tree.Node
                    ( prefix
                        <> " "
                        <> key
                        <> ": "
                        <> renderJsonValue value
                    )
                    []
                ]

insertPath :: [Text] -> [Tree.Tree Text] -> RenderTrie -> RenderTrie
insertPath [] leaves trie =
    trie
        { renderTrieLeaves = renderTrieLeaves trie <> leaves
        }
insertPath (segment : segments) leaves trie =
    let children =
            renderTrieChildren trie
        child =
            Map.findWithDefault emptyRenderTrie segment children
     in trie
            { renderTrieChildren =
                Map.insert segment (insertPath segments leaves child) children
            }

renderedPathSegments :: DiffPath -> [Text]
renderedPathSegments (DiffPath []) =
    ["<root>"]
renderedPathSegments (DiffPath segments) =
    segments

renderTrieForest :: RenderTrie -> [Tree.Tree Text]
renderTrieForest trie =
    renderTrieLeaves trie
        <> [ Tree.Node label (renderTrieForest child)
           | (label, child) <-
                List.sortOn
                    (renderSegmentSortKey . fst)
                    (Map.toList (renderTrieChildren trie))
           ]

renderForest :: TreeArt -> [Tree.Tree Text] -> Text
renderForest treeArt forest =
    case treeArt of
        TreeArtAscii ->
            Text.unlines (concatMap renderAsciiTree forest)
        TreeArtUnicode ->
            Text.pack $
                concatMap (TreeView.showTree . fmap Text.unpack) forest

renderAsciiTree :: Tree.Tree Text -> [Text]
renderAsciiTree (Tree.Node label children) =
    label : renderAsciiChildren "" children

renderAsciiChildren :: Text -> [Tree.Tree Text] -> [Text]
renderAsciiChildren prefix children =
    concat
        [ (prefix <> connector <> label)
            : renderAsciiChildren (prefix <> extension) grandchildren
        | (index, Tree.Node label grandchildren) <- zip [0 :: Int ..] children
        , let isLast = index == length children - 1
              connector =
                if isLast then "`- " else "+- "
              extension =
                if isLast then "   " else "|  "
        ]

renderChangedPathSegments :: DiffPath -> [Text]
renderChangedPathSegments path =
    case reverse (renderedPathSegments path) of
        [] ->
            ["<root>"]
        key : parentSegments ->
            reverse parentSegments <> [key]

renderChangedValueLeaves :: Aeson.Value -> Aeson.Value -> [Tree.Tree Text]
renderChangedValueLeaves left right =
    [ Tree.Node ("A: " <> rightAlignRenderedValue width leftText) []
    , Tree.Node ("B: " <> rightAlignRenderedValue width rightText) []
    ]
  where
    leftText =
        renderJsonValue left
    rightText =
        renderJsonValue right
    width =
        max (Text.length leftText) (Text.length rightText)

rightAlignRenderedValue :: Int -> Text -> Text
rightAlignRenderedValue width value =
    Text.replicate (width - Text.length value) " " <> value

renderSegmentSortKey :: Text -> RenderSegmentSortKey
renderSegmentSortKey label =
    case readMaybe (Text.unpack numericSortPrefix) of
        Just number
            | not (Text.null numericSortPrefix) ->
                RenderSegmentNumber number label
        _ ->
            RenderSegmentText label
  where
    sortText =
        Text.takeWhile (/= ':') label
    numericSortPrefix =
        Text.takeWhile isDigit sortText

renderDiffNodeLines :: DiffNode -> [Text]
renderDiffNodeLines (DiffNode path change) =
    case change of
        DiffSame value ->
            [renderSameLine path value]
        DiffChanged left right ->
            [ "~ " <> renderPath path
            , "  A: " <> renderJsonValue left
            , "  B: " <> renderJsonValue right
            ]
        DiffObject _ changed onlyA onlyB ->
            concat
                [ concatMap renderDiffNodeLines (Map.elems changed)
                , renderObjectOnly "-" path onlyA
                , renderObjectOnly "+" path onlyB
                ]
        DiffArray _ changed onlyA onlyB ->
            concat
                [ concatMap (renderDiffNodeLines . snd) changed
                , renderArrayOnly "-" path onlyA
                , renderArrayOnly "+" path onlyB
                ]

renderObjectOnly :: Text -> DiffPath -> Map Text Aeson.Value -> [Text]
renderObjectOnly prefix path values =
    [ prefix <> " " <> renderPath (path </> key) <> ": " <> renderJsonValue value
    | (key, value) <- Map.toAscList values
    ]

renderArrayOnly :: Text -> DiffPath -> [(Int, Aeson.Value)] -> [Text]
renderArrayOnly prefix path values =
    [ prefix
        <> " "
        <> renderPath (path </> Text.pack (show index))
        <> ": "
        <> renderJsonValue value
    | (index, value) <- values
    ]

renderSameLine :: DiffPath -> Maybe Aeson.Value -> Text
renderSameLine path Nothing =
    "= " <> renderPath path
renderSameLine path (Just value) =
    "= " <> renderPath path <> ": " <> renderJsonValue value

renderPath :: DiffPath -> Text
renderPath (DiffPath []) =
    "<root>"
renderPath (DiffPath segments) =
    Text.intercalate "." segments

renderJsonValue :: Aeson.Value -> Text
renderJsonValue value =
    case lovelaceValue value of
        Just lovelace ->
            renderLovelace lovelace
        Nothing ->
            case cborValue value of
                Just cbor ->
                    renderCborValue cbor
                Nothing ->
                    renderEncodedJsonValue value

cborValue :: Aeson.Value -> Maybe Text
cborValue (Aeson.Object value) =
    case KeyMap.toList value of
        [(key, Aeson.String cbor)]
            | key == Key.fromText "cbor" ->
                Just cbor
        _ ->
            Nothing
cborValue _ =
    Nothing

renderCborValue :: Text -> Text
renderCborValue cbor =
    "cbor:"
        <> cborSummary cbor
        <> " ("
        <> Text.pack (show (Text.length cbor `div` 2))
        <> " bytes)"

cborSummary :: Text -> Text
cborSummary cbor
    | Text.length cbor > 64 =
        Text.take 32 cbor <> "..."
    | otherwise =
        cbor

renderEncodedJsonValue :: Aeson.Value -> Text
renderEncodedJsonValue =
    TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode

lovelaceValue :: Aeson.Value -> Maybe Integer
lovelaceValue (Aeson.Object value) =
    case KeyMap.toList value of
        [(key, numberValue)]
            | key == Key.fromText "lovelace" ->
                integerJsonValue numberValue
        _ ->
            Nothing
lovelaceValue _ =
    Nothing

integerJsonValue :: Aeson.Value -> Maybe Integer
integerJsonValue numberValue@(Aeson.Number _) =
    readMaybe (Text.unpack (renderEncodedJsonValue numberValue))
integerJsonValue _ =
    Nothing

renderLovelace :: Integer -> Text
renderLovelace lovelace =
    sign
        <> Text.pack (show ada)
        <> "."
        <> Text.justifyRight 6 '0' (Text.pack (show rest))
        <> " ADA ("
        <> Text.pack (show lovelace)
        <> " lovelace)"
  where
    sign =
        if lovelace < 0 then "-" else ""
    absoluteLovelace =
        abs lovelace
    (ada, rest) =
        absoluteLovelace `quotRem` 1000000

(</>) :: DiffPath -> Text -> DiffPath
DiffPath segments </> segment =
    DiffPath (segments <> [segment])

(</!>) :: DiffPath -> DiffPath -> DiffPath
DiffPath left </!> DiffPath right =
    DiffPath (left <> right)

diffPathSegments :: DiffPath -> [Text]
diffPathSegments (DiffPath segments) =
    segments

textDiffPath :: Text -> DiffPath
textDiffPath text =
    DiffPath $
        filter (not . Text.null) $
            Text.splitOn "." text

openValuePlan :: DiffPlan OpenValue
openValuePlan =
    DiffPlan
        { diffEqual = (==)
        , diffSummary = openValueSummary
        , diffProject = openValueProjection
        }

conwayDiffPlan :: TxDiffOptions -> DiffPlan ConwayDiffValue
conwayDiffPlan options =
    DiffPlan
        { diffEqual = conwayDiffEqual
        , diffSummary = conwayDiffSummary
        , diffProject = conwayDiffProjection options
        }

conwayDiffEqual :: ConwayDiffValue -> ConwayDiffValue -> Bool
conwayDiffEqual (ConwayTxValue left) (ConwayTxValue right) =
    left == right
conwayDiffEqual (ConwayBodyValue left) (ConwayBodyValue right) =
    left ^. bodyTxL == right ^. bodyTxL
conwayDiffEqual (ConwayCoinValue left) (ConwayCoinValue right) =
    left == right
conwayDiffEqual
    (ConwayStrictMaybeCoinValue left)
    (ConwayStrictMaybeCoinValue right) =
        left == right
conwayDiffEqual (ConwayInputsValue left) (ConwayInputsValue right) =
    left == right
conwayDiffEqual (ConwayTxInValue left) (ConwayTxInValue right) =
    left == right
conwayDiffEqual (ConwayTxInIdValue left) (ConwayTxInIdValue right) =
    left == right
conwayDiffEqual (ConwayKeyHashesValue left) (ConwayKeyHashesValue right) =
    left == right
conwayDiffEqual (ConwayKeyHashValue left) (ConwayKeyHashValue right) =
    left == right
conwayDiffEqual (ConwayMintValue left) (ConwayMintValue right) =
    left == right
conwayDiffEqual
    (ConwayAssetQuantitiesValue left)
    (ConwayAssetQuantitiesValue right) =
        left == right
conwayDiffEqual (ConwayIntegerValue left) (ConwayIntegerValue right) =
    left == right
conwayDiffEqual (ConwayWithdrawalsValue left) (ConwayWithdrawalsValue right) =
    left == right
conwayDiffEqual (ConwayValidityIntervalValue left) (ConwayValidityIntervalValue right) =
    left == right
conwayDiffEqual (ConwaySlotBoundValue left) (ConwaySlotBoundValue right) =
    left == right
conwayDiffEqual (ConwayOutputsValue left) (ConwayOutputsValue right) =
    left == right
conwayDiffEqual (ConwayTxOutValue left) (ConwayTxOutValue right) =
    left == right
conwayDiffEqual
    (ConwayTxOutAssetsValue left)
    (ConwayTxOutAssetsValue right) =
        left == right
conwayDiffEqual (ConwayAddressValue left) (ConwayAddressValue right) =
    left == right
conwayDiffEqual (ConwayDatumValue left) (ConwayDatumValue right) =
    left == right
conwayDiffEqual
    (ConwayReferenceScriptValue left)
    (ConwayReferenceScriptValue right) =
        left == right
conwayDiffEqual (ConwayWitnessesValue left) (ConwayWitnessesValue right) =
    left ^. witsTxL == right ^. witsTxL
conwayDiffEqual
    (ConwayBootstrapWitnessesValue left)
    (ConwayBootstrapWitnessesValue right) =
        left == right
conwayDiffEqual
    (ConwayBootstrapWitnessValue left)
    (ConwayBootstrapWitnessValue right) =
        left == right
conwayDiffEqual
    (ConwayVKeyWitnessesValue left)
    (ConwayVKeyWitnessesValue right) =
        left == right
conwayDiffEqual
    (ConwayVKeyWitnessValue left)
    (ConwayVKeyWitnessValue right) =
        left == right
conwayDiffEqual
    (ConwayDatumWitnessesValue left)
    (ConwayDatumWitnessesValue right) =
        left == right
conwayDiffEqual (ConwayDataValue _ left) (ConwayDataValue _ right) =
    left == right
conwayDiffEqual (ConwayRedeemersValue left) (ConwayRedeemersValue right) =
    left == right
conwayDiffEqual (ConwayRedeemerValue left) (ConwayRedeemerValue right) =
    left == right
conwayDiffEqual (ConwayExUnitsValue left) (ConwayExUnitsValue right) =
    left == right
conwayDiffEqual (ConwayScriptsValue left) (ConwayScriptsValue right) =
    left == right
conwayDiffEqual (ConwayScriptValue left) (ConwayScriptValue right) =
    left == right
conwayDiffEqual (ConwayOpenValue left) (ConwayOpenValue right) =
    left == right
conwayDiffEqual _ _ =
    False

conwayDiffSummary :: ConwayDiffValue -> Maybe Aeson.Value
conwayDiffSummary (ConwayCoinValue coin) =
    Just (coinValue coin)
conwayDiffSummary (ConwayStrictMaybeCoinValue coin) =
    Just (strictMaybeCoinValue coin)
conwayDiffSummary (ConwayInputsValue inputs) =
    Just (inputsValue inputs)
conwayDiffSummary (ConwayTxInValue txIn) =
    Just (txInValue txIn)
conwayDiffSummary (ConwayTxInIdValue txIn) =
    Just (txInValue txIn)
conwayDiffSummary (ConwayKeyHashesValue keyHashes) =
    Just (keyHashesValue keyHashes)
conwayDiffSummary (ConwayKeyHashValue keyHash) =
    Just (keyHashValue keyHash)
conwayDiffSummary (ConwayMintValue mint) =
    Just (mintValue mint)
conwayDiffSummary (ConwayAssetQuantitiesValue assets) =
    Just (assetQuantitiesValue assets)
conwayDiffSummary (ConwayIntegerValue quantity) =
    Just (Aeson.toJSON quantity)
conwayDiffSummary (ConwayWithdrawalsValue withdrawals) =
    Just (withdrawalsValue withdrawals)
conwayDiffSummary (ConwayValidityIntervalValue validity) =
    Just (validityIntervalValue validity)
conwayDiffSummary (ConwaySlotBoundValue slotBound) =
    Just (slotBoundValue slotBound)
conwayDiffSummary (ConwayOutputsValue outputs) =
    Just (Aeson.toJSON (map txOutValue outputs))
conwayDiffSummary (ConwayTxOutValue output) =
    Just (txOutValue output)
conwayDiffSummary (ConwayTxOutAssetsValue assets) =
    Just (mintValue assets)
conwayDiffSummary (ConwayAddressValue address) =
    Just (addressValue address)
conwayDiffSummary (ConwayDatumValue datum) =
    Just (datumValue datum)
conwayDiffSummary (ConwayReferenceScriptValue referenceScript) =
    Just (referenceScriptValue referenceScript)
conwayDiffSummary (ConwayBootstrapWitnessesValue witnesses) =
    Just (bootstrapWitnessesValue witnesses)
conwayDiffSummary (ConwayBootstrapWitnessValue witness) =
    Just (bootstrapWitnessValue witness)
conwayDiffSummary (ConwayVKeyWitnessesValue witnesses) =
    Just (vkeyWitnessesValue witnesses)
conwayDiffSummary (ConwayVKeyWitnessValue witness) =
    Just (vkeyWitnessValue witness)
conwayDiffSummary (ConwayDatumWitnessesValue datums) =
    Just (datumWitnessesValue datums)
conwayDiffSummary (ConwayDataValue _ datum) =
    Just (dataValue datum)
conwayDiffSummary (ConwayRedeemersValue redeemers) =
    Just (redeemersValue redeemers)
conwayDiffSummary (ConwayRedeemerValue redeemer) =
    Just (redeemerValue redeemer)
conwayDiffSummary (ConwayExUnitsValue exUnits) =
    Just (exUnitsValue exUnits)
conwayDiffSummary (ConwayScriptsValue scripts) =
    Just (scriptsValue scripts)
conwayDiffSummary (ConwayScriptValue script) =
    Just (scriptValue script)
conwayDiffSummary (ConwayOpenValue value) =
    openValueSummary value
conwayDiffSummary (ConwayTxValue _) =
    Nothing
conwayDiffSummary (ConwayBodyValue _) =
    Nothing
conwayDiffSummary (ConwayWitnessesValue _) =
    Nothing

conwayDiffProjection ::
    TxDiffOptions -> ConwayDiffValue -> DiffProjection ConwayDiffValue
conwayDiffProjection options (ConwayTxValue tx) =
    DiffObjectChildren $
        if txDiffIncludeWitnesses options
            then
                Map.fromList
                    [
                        ( "body"
                        , ConwayBodyValue tx
                        )
                    ,
                        ( "witnesses"
                        , ConwayWitnessesValue tx
                        )
                    ]
            else Map.singleton "body" (ConwayBodyValue tx)
conwayDiffProjection _ (ConwayBodyValue tx) =
    DiffObjectChildren $
        Map.fromList
            [
                ( "collateralInputs"
                , ConwayInputsValue $
                    Set.toAscList (tx ^. bodyTxL . collateralInputsTxBodyL)
                )
            ,
                ( "fee"
                , ConwayCoinValue (tx ^. bodyTxL . feeTxBodyL)
                )
            ,
                ( "inputs"
                , ConwayInputsValue $
                    Set.toAscList (tx ^. bodyTxL . inputsTxBodyL)
                )
            ,
                ( "mint"
                , ConwayMintValue (tx ^. bodyTxL . mintTxBodyL)
                )
            ,
                ( "referenceInputs"
                , ConwayInputsValue $
                    Set.toAscList (tx ^. bodyTxL . referenceInputsTxBodyL)
                )
            ,
                ( "requiredSigners"
                , ConwayKeyHashesValue $
                    Set.toAscList (tx ^. bodyTxL . reqSignerHashesTxBodyL)
                )
            ,
                ( "totalCollateral"
                , ConwayStrictMaybeCoinValue $
                    tx ^. bodyTxL . totalCollateralTxBodyL
                )
            ,
                ( "validityInterval"
                , ConwayValidityIntervalValue (tx ^. bodyTxL . vldtTxBodyL)
                )
            ,
                ( "withdrawals"
                , ConwayWithdrawalsValue (tx ^. bodyTxL . withdrawalsTxBodyL)
                )
            ,
                ( "outputs"
                , ConwayOutputsValue (toList (tx ^. bodyTxL . outputsTxBodyL))
                )
            ]
conwayDiffProjection _ (ConwayCoinValue coin) =
    DiffAtomic (coinValue coin)
conwayDiffProjection _ (ConwayStrictMaybeCoinValue coin) =
    DiffAtomic (strictMaybeCoinValue coin)
conwayDiffProjection _ (ConwayInputsValue inputs) =
    DiffArrayChildren (map ConwayTxInValue inputs)
conwayDiffProjection options (ConwayTxInValue txIn) =
    case txDiffResolvedInputs options of
        Nothing ->
            DiffAtomic (txInValue txIn)
        Just resolutionMap ->
            DiffObjectChildren $
                Map.fromList $
                    ("txIn", ConwayTxInIdValue txIn)
                        : [ ("resolved", ConwayTxOutValue resolved)
                          | Just resolved <- [Map.lookup txIn resolutionMap]
                          ]
conwayDiffProjection _ (ConwayTxInIdValue txIn) =
    DiffAtomic (txInValue txIn)
conwayDiffProjection _ (ConwayKeyHashesValue keyHashes) =
    DiffArrayChildren (map ConwayKeyHashValue keyHashes)
conwayDiffProjection _ (ConwayKeyHashValue keyHash) =
    DiffAtomic (keyHashValue keyHash)
conwayDiffProjection _ (ConwayMintValue mint) =
    DiffObjectChildren (mintChildren mint)
conwayDiffProjection _ (ConwayAssetQuantitiesValue assets) =
    DiffObjectChildren (assetQuantityChildren assets)
conwayDiffProjection _ (ConwayIntegerValue quantity) =
    DiffAtomic (Aeson.toJSON quantity)
conwayDiffProjection _ (ConwayWithdrawalsValue withdrawals) =
    DiffObjectChildren (withdrawalChildren withdrawals)
conwayDiffProjection _ (ConwayValidityIntervalValue validity) =
    DiffObjectChildren $
        Map.fromList
            [
                ( "invalidBefore"
                , ConwaySlotBoundValue (invalidBefore validity)
                )
            ,
                ( "invalidHereafter"
                , ConwaySlotBoundValue (invalidHereafter validity)
                )
            ]
conwayDiffProjection _ (ConwaySlotBoundValue slotBound) =
    DiffAtomic (slotBoundValue slotBound)
conwayDiffProjection _ (ConwayOutputsValue outputs) =
    DiffArrayChildren (map ConwayTxOutValue outputs)
conwayDiffProjection _ (ConwayTxOutValue output) =
    DiffObjectChildren $
        Map.fromList
            [
                ( "address"
                , ConwayAddressValue (output ^. addrTxOutL)
                )
            ,
                ( "assets"
                , ConwayTxOutAssetsValue (txOutAssets output)
                )
            ,
                ( "coin"
                , ConwayCoinValue (output ^. coinTxOutL)
                )
            ,
                ( "datum"
                , ConwayDatumValue (output ^. datumTxOutL)
                )
            ,
                ( "referenceScript"
                , ConwayReferenceScriptValue (output ^. referenceScriptTxOutL)
                )
            ]
conwayDiffProjection _ (ConwayTxOutAssetsValue assets)
    | multiAssetEmpty assets =
        DiffAtomic noNativeAssetsValue
    | otherwise =
        DiffObjectChildren (mintChildren assets)
conwayDiffProjection _ (ConwayAddressValue address) =
    DiffAtomic (addressValue address)
conwayDiffProjection options (ConwayDatumValue datum) =
    datumDiffProjection options datum
conwayDiffProjection _ (ConwayReferenceScriptValue referenceScript) =
    DiffAtomic (referenceScriptValue referenceScript)
conwayDiffProjection _ (ConwayWitnessesValue tx) =
    DiffObjectChildren $
        Map.fromList
            [
                ( "bootstraps"
                , ConwayBootstrapWitnessesValue $
                    Set.toAscList (tx ^. witsTxL . bootAddrTxWitsL)
                )
            ,
                ( "datums"
                , ConwayDatumWitnessesValue (tx ^. witsTxL . datsTxWitsL)
                )
            ,
                ( "redeemers"
                , ConwayRedeemersValue (tx ^. witsTxL . rdmrsTxWitsL)
                )
            ,
                ( "scripts"
                , ConwayScriptsValue (tx ^. witsTxL . scriptTxWitsL)
                )
            ,
                ( "vkeys"
                , ConwayVKeyWitnessesValue $
                    Set.toAscList (tx ^. witsTxL . addrTxWitsL)
                )
            ]
conwayDiffProjection _ (ConwayBootstrapWitnessesValue witnesses) =
    DiffObjectChildren (bootstrapWitnessChildren witnesses)
conwayDiffProjection _ (ConwayBootstrapWitnessValue witness) =
    DiffAtomic (bootstrapWitnessValue witness)
conwayDiffProjection _ (ConwayVKeyWitnessesValue witnesses) =
    DiffObjectChildren (vkeyWitnessChildren witnesses)
conwayDiffProjection _ (ConwayVKeyWitnessValue witness) =
    DiffAtomic (vkeyWitnessValue witness)
conwayDiffProjection _ (ConwayDatumWitnessesValue datums) =
    DiffObjectChildren (datumWitnessChildren datums)
conwayDiffProjection options (ConwayDataValue selector datum) =
    dataDiffProjection options selector datum
conwayDiffProjection _ (ConwayRedeemersValue redeemers) =
    DiffObjectChildren (redeemerChildren redeemers)
conwayDiffProjection _ (ConwayRedeemerValue redeemer) =
    DiffObjectChildren (redeemerFieldChildren redeemer)
conwayDiffProjection _ (ConwayExUnitsValue exUnits) =
    DiffAtomic (exUnitsValue exUnits)
conwayDiffProjection _ (ConwayScriptsValue scripts) =
    DiffObjectChildren (scriptChildren scripts)
conwayDiffProjection _ (ConwayScriptValue script) =
    DiffAtomic (scriptValue script)
conwayDiffProjection _ (ConwayOpenValue value) =
    openValueDiffProjection value

dataDiffProjection ::
    TxDiffOptions ->
    TxDiffDataSelector ->
    Data ConwayEra ->
    DiffProjection ConwayDiffValue
dataDiffProjection options selector datum =
    case txDiffDecodeData options of
        Nothing ->
            openValueDiffProjection (dataOpenValue datum)
        Just decodeData ->
            case decodeData selector datum of
                Right value ->
                    openValueDiffProjection value
                Left _ ->
                    openValueDiffProjection (dataOpenValue datum)

datumDiffProjection ::
    TxDiffOptions -> Datum ConwayEra -> DiffProjection ConwayDiffValue
datumDiffProjection options datum =
    case inlineDatumData datum of
        Just datumData ->
            dataDiffProjection options datumDataSelector datumData
        Nothing ->
            DiffAtomic (datumValue datum)

inlineDatumData :: Datum ConwayEra -> Maybe (Data ConwayEra)
inlineDatumData (Datum datum) =
    Just (binaryDataToData datum)
inlineDatumData _ =
    Nothing

openValueDiffProjection :: OpenValue -> DiffProjection ConwayDiffValue
openValueDiffProjection value =
    case openValueProjection value of
        DiffAtomic atomic ->
            DiffAtomic atomic
        DiffObjectChildren fields ->
            DiffObjectChildren (Map.map ConwayOpenValue fields)
        DiffArrayChildren values ->
            DiffArrayChildren (map ConwayOpenValue values)

dataOpenValue :: Data ConwayEra -> OpenValue
dataOpenValue (Data value) =
    plutusDataOpenValue value

plutusDataOpenValue :: PLC.Data -> OpenValue
plutusDataOpenValue (PLC.I integer) =
    OpenInteger integer
plutusDataOpenValue (PLC.B bytes) =
    OpenBytes (hexText bytes)
plutusDataOpenValue (PLC.List values) =
    OpenArray (map plutusDataOpenValue values)
plutusDataOpenValue (PLC.Map entries) =
    OpenArray
        [ OpenObject $
            Map.fromList
                [ ("key", plutusDataOpenValue key)
                , ("value", plutusDataOpenValue itemValue)
                ]
        | (key, itemValue) <- entries
        ]
plutusDataOpenValue (PLC.Constr index fields) =
    OpenObject $
        Map.fromList
            [ ("constructor", OpenInteger index)
            , ("fields", OpenArray (map plutusDataOpenValue fields))
            ]

coinValue :: Coin -> Aeson.Value
coinValue (Coin lovelace) =
    Aeson.object ["lovelace" .= lovelace]

strictMaybeCoinValue :: StrictMaybe Coin -> Aeson.Value
strictMaybeCoinValue SNothing =
    Aeson.Null
strictMaybeCoinValue (SJust coin) =
    coinValue coin

inputsValue :: [TxIn] -> Aeson.Value
inputsValue inputs =
    Aeson.toJSON (map txInValue inputs)

txInValue :: TxIn -> Aeson.Value
txInValue (TxIn (TxId safeHash) (TxIx index)) =
    Aeson.object
        [ "txId" .= hexText (hashToBytes (extractHash safeHash))
        , "index" .= index
        ]

keyHashesValue :: [KeyHash Guard] -> Aeson.Value
keyHashesValue keyHashes =
    Aeson.toJSON (map keyHashValue keyHashes)

keyHashValue :: KeyHash Guard -> Aeson.Value
keyHashValue keyHash =
    Aeson.String (keyHashKey keyHash)

keyHashKey :: KeyHash kr -> Text
keyHashKey (KeyHash keyHash) =
    hexText (hashToBytes keyHash)

mintValue :: MultiAsset -> Aeson.Value
mintValue mint =
    objectValue
        [ (policyIdKey policyId, assetQuantitiesValue assets)
        | (policyId, assets) <- mintEntries mint
        ]

mintChildren :: MultiAsset -> Map Text ConwayDiffValue
mintChildren mint =
    Map.fromList
        [ (policyIdKey policyId, ConwayAssetQuantitiesValue assets)
        | (policyId, assets) <- mintEntries mint
        ]

mintEntries :: MultiAsset -> [(PolicyID, Map AssetName Integer)]
mintEntries (MultiAsset policies) =
    Map.toAscList policies

assetQuantitiesValue :: Map AssetName Integer -> Aeson.Value
assetQuantitiesValue assets =
    objectValue
        [ (assetNameKey assetName, Aeson.toJSON quantity)
        | (assetName, quantity) <- Map.toAscList assets
        ]

assetQuantityChildren :: Map AssetName Integer -> Map Text ConwayDiffValue
assetQuantityChildren assets =
    Map.fromList
        [ (assetNameKey assetName, ConwayIntegerValue quantity)
        | (assetName, quantity) <- Map.toAscList assets
        ]

policyIdKey :: PolicyID -> Text
policyIdKey (PolicyID scriptHash) =
    scriptHashKey scriptHash

assetNameKey :: AssetName -> Text
assetNameKey (AssetName bytes) =
    hexText (SBS.fromShort bytes)

withdrawalsValue :: Withdrawals -> Aeson.Value
withdrawalsValue withdrawals =
    objectValue
        [ (rewardAccountKey rewardAccount, coinValue coin)
        | (rewardAccount, coin) <- withdrawalEntries withdrawals
        ]

withdrawalChildren :: Withdrawals -> Map Text ConwayDiffValue
withdrawalChildren withdrawals =
    Map.fromList
        [ (rewardAccountKey rewardAccount, ConwayCoinValue coin)
        | (rewardAccount, coin) <- withdrawalEntries withdrawals
        ]

withdrawalEntries :: Withdrawals -> [(AccountAddress, Coin)]
withdrawalEntries (Withdrawals withdrawals) =
    Map.toAscList withdrawals

rewardAccountKey :: AccountAddress -> Text
rewardAccountKey rewardAccount =
    hexText (serialize' (eraProtVerLow @ConwayEra) rewardAccount)

validityIntervalValue :: ValidityInterval -> Aeson.Value
validityIntervalValue validity =
    Aeson.object
        [ "invalidBefore" .= slotBoundValue (invalidBefore validity)
        , "invalidHereafter" .= slotBoundValue (invalidHereafter validity)
        ]

slotBoundValue :: StrictMaybe SlotNo -> Aeson.Value
slotBoundValue SNothing =
    Aeson.Null
slotBoundValue (SJust (SlotNo slot)) =
    Aeson.toJSON slot

txOutValue :: TxOut ConwayEra -> Aeson.Value
txOutValue output =
    Aeson.object
        [ "address" .= addressValue (output ^. addrTxOutL)
        , "assets" .= mintValue (txOutAssets output)
        , "coin" .= coinValue (output ^. coinTxOutL)
        , "datum" .= datumValue (output ^. datumTxOutL)
        , "referenceScript"
            .= referenceScriptValue (output ^. referenceScriptTxOutL)
        ]

txOutAssets :: TxOut ConwayEra -> MultiAsset
txOutAssets output =
    case output ^. valueTxOutL of
        MaryValue _ assets ->
            assets

multiAssetEmpty :: MultiAsset -> Bool
multiAssetEmpty (MultiAsset policies) =
    Map.null policies

noNativeAssetsValue :: Aeson.Value
noNativeAssetsValue =
    Aeson.String "no native assets"

addressValue :: Addr -> Aeson.Value
addressValue address =
    Aeson.object ["bytes" .= hexText (serialiseAddr address)]

datumValue :: Datum ConwayEra -> Aeson.Value
datumValue datum =
    Aeson.object
        [ "cbor" .= hexText (serialize' (eraProtVerLow @ConwayEra) datum)
        ]

referenceScriptValue :: StrictMaybe (Script ConwayEra) -> Aeson.Value
referenceScriptValue SNothing =
    Aeson.Null
referenceScriptValue (SJust script) =
    scriptValue script

scriptValue :: Script ConwayEra -> Aeson.Value
scriptValue script =
    Aeson.object
        [ "cbor" .= hexText (serialize' (eraProtVerLow @ConwayEra) script)
        ]

datumWitnessesValue :: TxDats ConwayEra -> Aeson.Value
datumWitnessesValue datums =
    objectValue
        [ (dataHashKey dataHash, dataValue datum)
        | (dataHash, datum) <- datumWitnessEntries datums
        ]

datumWitnessChildren :: TxDats ConwayEra -> Map Text ConwayDiffValue
datumWitnessChildren datums =
    Map.fromList
        [ (dataHashKey dataHash, ConwayDataValue datumDataSelector datum)
        | (dataHash, datum) <- datumWitnessEntries datums
        ]

datumWitnessEntries :: TxDats ConwayEra -> [(DataHash, Data ConwayEra)]
datumWitnessEntries (TxDats datums) =
    Map.toAscList datums

dataHashKey :: DataHash -> Text
dataHashKey dataHash =
    hexText (hashToBytes (extractHash dataHash))

dataValue :: Data ConwayEra -> Aeson.Value
dataValue datum =
    Aeson.object
        [ "cbor" .= hexText (serialize' (eraProtVerLow @ConwayEra) datum)
        ]

bootstrapWitnessesValue :: [BootstrapWitness] -> Aeson.Value
bootstrapWitnessesValue witnesses =
    objectValue
        [ (bootstrapWitnessKeyHashKey witness, bootstrapWitnessValue witness)
        | witness <- witnesses
        ]

bootstrapWitnessChildren ::
    [BootstrapWitness] -> Map Text ConwayDiffValue
bootstrapWitnessChildren witnesses =
    Map.fromList
        [ ( bootstrapWitnessKeyHashKey witness
          , ConwayBootstrapWitnessValue witness
          )
        | witness <- witnesses
        ]

bootstrapWitnessValue :: BootstrapWitness -> Aeson.Value
bootstrapWitnessValue witness =
    Aeson.object
        [ "cbor" .= hexText (serialize' (eraProtVerLow @ConwayEra) witness)
        ]

bootstrapWitnessKeyHashKey :: BootstrapWitness -> Text
bootstrapWitnessKeyHashKey witness =
    keyHashKey (hashKey (bwKey witness))

vkeyWitnessesValue :: [WitVKey Witness] -> Aeson.Value
vkeyWitnessesValue witnesses =
    objectValue
        [ (witnessKeyHashKey witness, vkeyWitnessValue witness)
        | witness <- witnesses
        ]

vkeyWitnessChildren :: [WitVKey Witness] -> Map Text ConwayDiffValue
vkeyWitnessChildren witnesses =
    Map.fromList
        [ (witnessKeyHashKey witness, ConwayVKeyWitnessValue witness)
        | witness <- witnesses
        ]

vkeyWitnessValue :: WitVKey Witness -> Aeson.Value
vkeyWitnessValue witness =
    Aeson.object
        [ "cbor" .= hexText (serialize' (eraProtVerLow @ConwayEra) witness)
        ]

witnessKeyHashKey :: WitVKey Witness -> Text
witnessKeyHashKey witness =
    keyHashKey (witVKeyHash witness)

redeemersValue :: Redeemers ConwayEra -> Aeson.Value
redeemersValue redeemers =
    objectValue
        [ (redeemerPurposeKey purpose, redeemerValue redeemer)
        | (purpose, redeemer) <- redeemerEntries redeemers
        ]

redeemerChildren :: Redeemers ConwayEra -> Map Text ConwayDiffValue
redeemerChildren redeemers =
    Map.fromList
        [ (redeemerPurposeKey purpose, ConwayRedeemerValue redeemer)
        | (purpose, redeemer) <- redeemerEntries redeemers
        ]

redeemerEntries ::
    Redeemers ConwayEra ->
    [(ConwayPlutusPurpose AsIx ConwayEra, (Data ConwayEra, ExUnits))]
redeemerEntries (Redeemers redeemers) =
    Map.toAscList redeemers

redeemerPurposeKey :: ConwayPlutusPurpose AsIx ConwayEra -> Text
redeemerPurposeKey (ConwaySpending (AsIx index)) =
    indexedRedeemerPurposeKey "spending" index
redeemerPurposeKey (ConwayMinting (AsIx index)) =
    indexedRedeemerPurposeKey "minting" index
redeemerPurposeKey (ConwayCertifying (AsIx index)) =
    indexedRedeemerPurposeKey "certifying" index
redeemerPurposeKey (ConwayRewarding (AsIx index)) =
    indexedRedeemerPurposeKey "rewarding" index
redeemerPurposeKey (ConwayVoting (AsIx index)) =
    indexedRedeemerPurposeKey "voting" index
redeemerPurposeKey (ConwayProposing (AsIx index)) =
    indexedRedeemerPurposeKey "proposing" index

indexedRedeemerPurposeKey :: (Show index) => Text -> index -> Text
indexedRedeemerPurposeKey label index =
    label <> "." <> Text.pack (show index)

redeemerValue :: (Data ConwayEra, ExUnits) -> Aeson.Value
redeemerValue (redeemerData, exUnits) =
    Aeson.object
        [ "data" .= dataValue redeemerData
        , "exUnits" .= exUnitsValue exUnits
        ]

redeemerFieldChildren ::
    (Data ConwayEra, ExUnits) -> Map Text ConwayDiffValue
redeemerFieldChildren (redeemerData, exUnits) =
    Map.fromList
        [
            ( "data"
            , ConwayDataValue redeemerDataSelector redeemerData
            )
        ,
            ( "exUnits"
            , ConwayExUnitsValue exUnits
            )
        ]

datumDataSelector :: TxDiffDataSelector
datumDataSelector =
    TxDiffDataSelector
        { txDiffDataValidatorTitle = Nothing
        , txDiffDataKind = TxDiffDatum
        }

redeemerDataSelector :: TxDiffDataSelector
redeemerDataSelector =
    TxDiffDataSelector
        { txDiffDataValidatorTitle = Nothing
        , txDiffDataKind = TxDiffRedeemer
        }

exUnitsValue :: ExUnits -> Aeson.Value
exUnitsValue (ExUnits memory steps) =
    Aeson.object
        [ "memory" .= memory
        , "steps" .= steps
        ]

scriptsValue :: Map ScriptHash (Script ConwayEra) -> Aeson.Value
scriptsValue scripts =
    objectValue
        [ (scriptHashKey scriptHash, scriptValue script)
        | (scriptHash, script) <- Map.toAscList scripts
        ]

scriptChildren :: Map ScriptHash (Script ConwayEra) -> Map Text ConwayDiffValue
scriptChildren scripts =
    Map.fromList
        [ (scriptHashKey scriptHash, ConwayScriptValue script)
        | (scriptHash, script) <- Map.toAscList scripts
        ]

scriptHashKey :: ScriptHash -> Text
scriptHashKey (ScriptHash scriptHash) =
    hexText (hashToBytes scriptHash)

hexText :: ByteString -> Text
hexText =
    TextEncoding.decodeUtf8 . Base16.encode

openValueSummary :: OpenValue -> Maybe Aeson.Value
openValueSummary (OpenInteger value) =
    Just (Aeson.Number (fromInteger value))
openValueSummary (OpenText value) =
    Just (Aeson.String value)
openValueSummary (OpenBytes value) =
    Just (Aeson.object ["bytes" .= value])
openValueSummary (OpenObject _) =
    Nothing
openValueSummary (OpenArray _) =
    Nothing

openValueProjection :: OpenValue -> DiffProjection OpenValue
openValueProjection (OpenObject fields) =
    DiffObjectChildren fields
openValueProjection (OpenArray values) =
    DiffArrayChildren values
openValueProjection (OpenInteger value) =
    DiffAtomic (Aeson.Number (fromInteger value))
openValueProjection (OpenText value) =
    DiffAtomic (Aeson.String value)
openValueProjection (OpenBytes value) =
    DiffAtomic (Aeson.object ["bytes" .= value])
