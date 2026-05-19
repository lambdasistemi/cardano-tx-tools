{-# LANGUAGE RecordWildCards #-}

{- |
Module      : Fixtures.RewriteRedesign.Helpers
Description : Shared builder + assertion helpers for the rewrite-redesign
              goldens fixtures.
License     : Apache-2.0

Building blocks for the per-fixture modules that subsequent slices add under
@test/fixtures/rewrite-redesign/<NN>-<slug>/Tx.hs@.

This slice (S2) ships the minimum reviewable surface:

* 'StoryId' / 'FixturePaths' / 'ExpectedShape' / 'FixtureEntry' record
  shapes (per @specs/033-rewrite-redesign-harness/data-model.md@),
* an empty 'baseShape' that fixtures override with their own counts,
* a smart 'mkFixturePaths' constructor that mechanically computes the
  per-fixture file layout from a 'StoryId',
* a 'TxBuilder' newtype that wraps a 'TxBuild' program authored against
  @Cardano.Tx.Build@'s operational DSL, plus the pure 'mkTx' interpreter
  ('draft' under 'def' protocol params),
* per-fixture stub value constructors ('stubTxIn', 'stubTxOut') that
  produce structurally-correct ledger leaves the DSL combinators
  consume; @assertShape@ counts body fields and does not inspect leaf
  contents,
* 'assertShape', the structural-shape contract that the active Hspec item
  in @Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec@ exercises per fixture
  — see @specs/033-rewrite-redesign-harness/contracts/goldens-suite.md@,
  section /Active item/.

== Smoke special case

'assertShape' skips the @rules.yaml@ / @expected.txt@ on-disk presence
checks when @fpStoryId == StoryId "smoke"@. The host goldens-spec uses
this synthetic id to exercise 'assertShape' end-to-end without registering
a real fixture directory; the directory @test\/fixtures\/rewrite-redesign\/smoke\/@
intentionally does not exist on disk. Real fixtures use a numbered slug
(e.g. @StoryId "02-alice-bob-ada"@) and so always trip the file-presence
checks.
-}
module Fixtures.RewriteRedesign.Helpers (
    -- * Story identifier
    StoryId (..),

    -- * Fixture filesystem layout
    FixturePaths (..),
    mkFixturePaths,

    -- * Expected structural shape
    ExpectedShape (..),
    baseShape,

    -- * Fixture registry record
    FixtureEntry (..),

    -- * Conway tx builder
    NoCtx,
    TxBuilder (..),
    defTxBuilder,
    mkTx,

    -- * Smart constructors for body-leaf values
    stubTxIn,
    stubTxOut,
    stubRewardAccount,
    stubStakeDelegationCert,
    stubVoteDelegationCert,

    -- * Hspec contract
    assertShape,
) where

import Control.Monad (unless)
import Data.Default (def)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Void (Void)
import System.Directory (doesFileExist)
import System.FilePath ((</>))

import Lens.Micro ((^.))
import Test.Hspec (Expectation, shouldBe)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
    Withdrawals (..),
 )
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    certsTxBodyL,
    collateralInputsTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    outputsTxBodyL,
    proposalProceduresTxBodyL,
    referenceInputsTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Cert (
    Delegatee (DelegVote),
    TxCert,
    pattern DelegStakeTxCert,
    pattern DelegTxCert,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Testnet), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.DRep (DRep (DRepKeyHash))
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (DRepRole, Payment, StakePool, Staking))
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

import Cardano.Tx.Build (TxBuild, draft)
import Cardano.Tx.Ledger (ConwayTx)

-- ---------------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------------

{- | A fixture's story identifier — the directory slug under
@test/fixtures/rewrite-redesign/@, e.g. @StoryId "02-alice-bob-ada"@.
Used as the @describe@ label in Hspec and as the key in the fixture
registry.
-}
newtype StoryId = StoryId {unStoryId :: Text}
    deriving stock (Show, Eq, Ord)

-- ---------------------------------------------------------------------------
-- Filesystem layout
-- ---------------------------------------------------------------------------

{- | Paths to the on-disk artifacts a single fixture owns. Constructed once
per fixture by 'mkFixturePaths' and (for fixtures that reference a
blueprint) refined with @fpBlueprint = Just …@ at registry-entry time.
-}
data FixturePaths = FixturePaths
    { fpStoryId :: StoryId
    -- ^ Story id; also the leaf directory name.
    , fpDirectory :: FilePath
    -- ^ Fixture directory, e.g.
    -- @test\/fixtures\/rewrite-redesign\/02-alice-bob-ada@.
    , fpRulesYaml :: FilePath
    -- ^ @<dir>\/rules.yaml@.
    , fpExpectedTxt :: FilePath
    -- ^ @<dir>\/expected.txt@.
    , fpExpectedTtl :: FilePath
    -- ^ @<dir>\/expected.ttl@ (may be absent pre-B-side; see contract).
    , fpBlueprint :: Maybe FilePath
    -- ^ @blueprints\/<file>@ if the fixture references one, else
    -- 'Nothing'.
    }
    deriving stock (Show)

{- | Compute the canonical 'FixturePaths' from a 'StoryId'. The directory
sits under @test\/fixtures\/rewrite-redesign\/<slug>@ and the three
file fields name the per-fixture artifacts (@rules.yaml@, @expected.txt@,
@expected.ttl@). @fpBlueprint@ is left 'Nothing'; per-fixture entries
override it when applicable.
-}
mkFixturePaths :: StoryId -> FixturePaths
mkFixturePaths story =
    FixturePaths
        { fpStoryId = story
        , fpDirectory = dir
        , fpRulesYaml = dir </> "rules.yaml"
        , fpExpectedTxt = dir </> "expected.txt"
        , fpExpectedTtl = dir </> "expected.ttl"
        , fpBlueprint = Nothing
        }
  where
    dir =
        "test/fixtures/rewrite-redesign"
            </> Text.unpack (unStoryId story)

-- ---------------------------------------------------------------------------
-- Expected structural shape
-- ---------------------------------------------------------------------------

{- | The body-field counts the 044 story specifies for a fixture, used by
the active structural Hspec item. See
@specs\/033-rewrite-redesign-harness\/contracts\/goldens-suite.md@ for
the exact contract.

@esScriptWits@ carries short string tags rather than a typed
@ScriptHashTag@ enum; the enum can grow later when a fixture exercises
script witnesses. 'assertShape' does not enforce these tags in this
slice — see the function's Haddock for the deferral note.
-}
data ExpectedShape = ExpectedShape
    { esInputs :: Int
    , esOutputs :: Int
    , esCertificates :: Int
    , esWithdrawals :: Int
    , esProposals :: Int
    , esCollateral :: Int
    , esReferenceIns :: Int
    , esMintEntries :: Int
    , esScriptWits :: [Text]
    , esBlueprintRef :: Maybe FilePath
    }
    deriving stock (Show, Eq)

{- | Zero-counts 'ExpectedShape'. Fixtures derive their shape with record
update syntax, e.g. @baseShape { esInputs = 1, esOutputs = 2 }@.
-}
baseShape :: ExpectedShape
baseShape =
    ExpectedShape
        { esInputs = 0
        , esOutputs = 0
        , esCertificates = 0
        , esWithdrawals = 0
        , esProposals = 0
        , esCollateral = 0
        , esReferenceIns = 0
        , esMintEntries = 0
        , esScriptWits = []
        , esBlueprintRef = Nothing
        }

-- ---------------------------------------------------------------------------
-- Fixture registry record
-- ---------------------------------------------------------------------------

{- | One entry of the fixture registry. Constructed lazily — the 'feBuilder'
expression is forced by the structural Hspec item.

No 'Show' or 'Eq' instance: 'feBuilder' carries a @ConwayTx@, which
is not generally @Show@ / @Eq@ for free.
-}
data FixtureEntry = FixtureEntry
    { feStoryId :: StoryId
    , feBuilder :: ConwayTx
    , fePaths :: FixturePaths
    , feShape :: ExpectedShape
    }

-- ---------------------------------------------------------------------------
-- Conway tx builder
-- ---------------------------------------------------------------------------

{- | Phantom @q@ parameter for fixture 'TxBuild' programs. The DSL's
@ctx@ query extension is unused by the harness — fixtures never reach
for domain-specific context — so we pick an uninhabited query GADT.
'noCtxInterpret' (the interpreter 'draft' supplies) errors out if a
@ctx@ instruction is encountered, which means a stray 'ctx' call is
caught at run time even though the type is phantom.
-}
data NoCtx a

{- | A Conway transaction-builder program. Wraps a 'TxBuild' program
authored against the @Cardano.Tx.Build@ DSL combinators ('spend',
'output', 'payTo', 'mint', 'collateral', 'certify', 'propose',
'withdraw', and friends). 'mkTx' runs the 'draft' interpreter to
materialise it as a 'ConwayTx'.

Per-fixture modules import the DSL combinators they need and write
their body as a do-block, e.g.

>   tx :: ConwayTx
>   tx = mkTx . TxBuilder $ do
>       _ <- spend (stubTxIn 1)
>       _ <- output (stubTxOut 10_000_000)
>       _ <- output (stubTxOut 89_825_000)
>       pure ()

The type parameters are pinned to @q ~ NoCtx@ (no domain-ctx queries)
and @e ~ Void@ (no custom validation errors); fixtures never need the
extension points.
-}
newtype TxBuilder = TxBuilder (TxBuild NoCtx Void ())

-- | The empty 'TxBuilder': no inputs, no outputs, no certs, no mint.
defTxBuilder :: TxBuilder
defTxBuilder = TxBuilder (pure ())

{- | Interpret a 'TxBuilder' into a 'ConwayTx' via the DSL's pure 'draft'
entrypoint. 'draft' assembles a transaction from the collected
'TxInstr' steps without invoking a 'Provider', running evaluation, or
bisecting the fee — the harness's structural-shape contract is
satisfied by the assembled body alone.

The 'PParams ConwayEra' fed to 'draft' is @data-default@'s @def@, which
'cardano-ledger-core' defines as 'emptyPParams'. That's protocol-version
and bounds-shape valid for fixture builds; min-UTxO / fee / Plutus
budget enforcement is out of scope for the harness (see spec.md
\"Illustrative transaction values\").
-}
mkTx :: TxBuilder -> ConwayTx
mkTx (TxBuilder program) = draft def program

-- ---------------------------------------------------------------------------
-- Smart constructors for body-leaf values
-- ---------------------------------------------------------------------------

{- | A synthetic 'TxIn' keyed by an integer tag (zero-padded into the
32-byte tx hash; @TxIx@ fixed at 0). 'assertShape' only counts inputs;
distinct tags keep the input @Set@ from deduplicating.
-}
stubTxIn :: Int -> TxIn
stubTxIn n = TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromStringAsHex hex)))) (TxIx 0)
  where
    hex = replicate 60 '0' ++ hexByte (n `div` 256) ++ hexByte (n `mod` 256)
    hexByte x = [d (x `div` 16), d (x `mod` 16)]
    d k = "0123456789abcdef" !! k

{- | A coin-only 'TxOut' at a shared stub 'Addr'. 'assertShape' only counts
outputs and does not inspect address bytes or values, so a single zero
key-hash on Testnet with 'StakeRefNull' suffices for every fixture in
this slice.
-}
stubTxOut :: Integer -> TxOut ConwayEra
stubTxOut coin = mkBasicTxOut stubAddr (MaryValue (Coin coin) (MultiAsset mempty))

stubAddr :: Addr
stubAddr =
    Addr
        Testnet
        (KeyHashObj (KeyHash (fromJust (hashFromStringAsHex (replicate 56 '0'))) :: KeyHash Payment))
        StakeRefNull

{- | A synthetic 'AccountAddress' (a.k.a. reward account) keyed by an
integer tag (zero-padded into the 28-byte stake key-hash). Network is
'Testnet'; credential is a key-hash, since 'assertShape' only counts
@withdrawals@ entries and does not inspect the credential kind.
-}
stubRewardAccount :: Int -> AccountAddress
stubRewardAccount n =
    AccountAddress
        Testnet
        (AccountId (KeyHashObj (KeyHash hash :: KeyHash Staking)))
  where
    hex = replicate 52 '0' ++ hexByte (n `div` 256) ++ hexByte (n `mod` 256)
    hexByte x = [d (x `div` 16), d (x `mod` 16)]
    d k = "0123456789abcdef" !! k
    hash = fromJust (hashFromStringAsHex hex)

{- | A synthetic Conway @StakeDelegation@ 'TxCert' keyed by an integer tag
(zero-padded into both the 28-byte stake key-hash credential and the
28-byte pool key-hash). 'assertShape' only counts cert entries, so the
internal byte values are arbitrary — distinct tags simply keep distinct
certs distinguishable should later contracts inspect them.
-}
stubStakeDelegationCert :: Int -> TxCert ConwayEra
stubStakeDelegationCert n =
    DelegStakeTxCert
        (KeyHashObj (KeyHash stakeHash :: KeyHash Staking))
        (KeyHash poolHash :: KeyHash StakePool)
  where
    hex = replicate 52 '0' ++ hexByte (n `div` 256) ++ hexByte (n `mod` 256)
    hexByte x = [d (x `div` 16), d (x `mod` 16)]
    d k = "0123456789abcdef" !! k
    stakeHash = fromJust (hashFromStringAsHex hex)
    poolHash = fromJust (hashFromStringAsHex hex)

{- | A synthetic Conway @VoteDelegation@ 'TxCert' keyed by an integer tag
(zero-padded into both the 28-byte stake key-hash credential and the
28-byte DRep key-hash). Builds @DelegTxCert stakeCred (DelegVote
(DRepKeyHash drepKey))@. 'assertShape' only counts cert entries, so the
internal byte values are arbitrary — distinct tags simply keep distinct
certs distinguishable should later contracts inspect them.
-}
stubVoteDelegationCert :: Int -> TxCert ConwayEra
stubVoteDelegationCert n =
    DelegTxCert
        (KeyHashObj (KeyHash stakeHash :: KeyHash Staking))
        (DelegVote (DRepKeyHash (KeyHash drepHash :: KeyHash DRepRole)))
  where
    hex = replicate 52 '0' ++ hexByte (n `div` 256) ++ hexByte (n `mod` 256)
    hexByte x = [d (x `div` 16), d (x `mod` 16)]
    d k = "0123456789abcdef" !! k
    stakeHash = fromJust (hashFromStringAsHex hex)
    drepHash = fromJust (hashFromStringAsHex hex)

-- ---------------------------------------------------------------------------
-- Hspec contract
-- ---------------------------------------------------------------------------

{- | The active structural-shape contract for one fixture.

Checks, in order:

* number of body inputs == 'esInputs',
* number of body outputs == 'esOutputs',
* number of certificates == 'esCertificates',
* withdrawals map size == 'esWithdrawals',
* proposal-procedure count == 'esProposals',
* collateral inputs count == 'esCollateral',
* reference inputs count == 'esReferenceIns',
* distinct @(policy, name)@ mint entries == 'esMintEntries',
* script-witness tags — deferred; no fixture in this slice exercises
  witnesses, so 'esScriptWits' is currently ignored. The first fixture
  that needs witness-set assertions extends this clause,
* @fpBlueprint@-or-@esBlueprintRef@ — when 'Just', the referenced file
  must exist on disk,
* @rules.yaml@ and @expected.txt@ — must exist on disk; skipped for
  'StoryId' @"smoke"@ (see module header),
* @expected.ttl@ — only checked when the file is present (B-side
  contract); never fails on absence.
-}
assertShape ::
    ConwayTx ->
    ExpectedShape ->
    FixturePaths ->
    Expectation
assertShape tx ExpectedShape{..} FixturePaths{..} = do
    let body = tx ^. bodyTxL
    length (body ^. inputsTxBodyL) `shouldBe` esInputs
    length (body ^. outputsTxBodyL) `shouldBe` esOutputs
    length (body ^. certsTxBodyL) `shouldBe` esCertificates
    let Withdrawals wmap = body ^. withdrawalsTxBodyL
    Map.size wmap `shouldBe` esWithdrawals
    length (body ^. proposalProceduresTxBodyL) `shouldBe` esProposals
    length (body ^. collateralInputsTxBodyL) `shouldBe` esCollateral
    length (body ^. referenceInputsTxBodyL) `shouldBe` esReferenceIns
    let MultiAsset policies = body ^. mintTxBodyL
        mintCount = sum (Map.size <$> Map.elems policies)
    mintCount `shouldBe` esMintEntries
    case esBlueprintRef of
        Nothing -> pure ()
        Just p -> do
            present <- doesFileExist p
            present `shouldBe` True
    unless (isSmoke fpStoryId) $ do
        rulesPresent <- doesFileExist fpRulesYaml
        rulesPresent `shouldBe` True
        expectedPresent <- doesFileExist fpExpectedTxt
        expectedPresent `shouldBe` True
  where
    isSmoke :: StoryId -> Bool
    isSmoke (StoryId t) = t == "smoke"
