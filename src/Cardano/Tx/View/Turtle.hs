{- |
Module      : Cardano.Tx.View.Turtle
Description : Canonical Turtle subset reader for the tx-view runner.
License     : Apache-2.0

A small reader for the subset of Turtle that
'Cardano.Tx.Graph.Emit.Serialize.Turtle' emits: a fixed prefix block,
section-header comments, and per-subject statement blocks of the form

@
_:subject a cardano:Type ;
  cardano:pred1 _:object1 ;
  cardano:pred2 \"string literal\" ;
  cardano:pred3 12345 .
@

The reader is intentionally narrow:

* It does not implement collections, RDF/XML, or full Turtle syntax.
* It only handles ASCII identifiers, double-quoted string literals
  without escape sequences, and integer literals.
* It accepts the @\@prefix@ / @\@base@ directives but does not resolve
  prefixes against absolute IRIs; predicate and object IRIs are kept
  in their source form (@cardano:hasInput@, @rdf:first@, @\<full-iri\>@,
  @:slug@, etc.).

The reader is part of the in-repo view runner (see plan D-002 and the
no-stub-triples precedent in 'Cardano.Tx.Graph.Emit.NoStubViewSpec');
no SPARQL runtime is required. If the runner ever needs richer Turtle
support, this module should grow rather than be replaced.
-}
module Cardano.Tx.View.Turtle (
    -- * Triple shape
    Subject (..),
    Predicate (..),
    Object (..),

    -- * Graph index
    Graph,
    parseTurtle,
    lookupPreds,
    findFirstObject,
    findAllObjects,
) where

import Data.ByteString (ByteString)
import Data.Char (isAlphaNum, isDigit)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Text.Read (readMaybe)

----------------------------------------------------------------------
-- Triple shape
----------------------------------------------------------------------

-- | Subject of a statement block.
data Subject
    = -- | @_:foo@ — a blank-node-labelled subject.
      SBnode !Text
    | -- | @:slug@, @cardano:Foo@, or @\<full-iri\>@.
      SIri !Text
    deriving stock (Eq, Ord, Show)

-- | Predicate of one statement line.
data Predicate
    = -- | @a@ — Turtle's @rdf:type@ shorthand.
      PA
    | -- | A prefixed name (@cardano:hasInput@) or full IRI surface form.
      PIri !Text
    deriving stock (Eq, Ord, Show)

-- | Object of one statement line.
data Object
    = -- | @_:foo@.
      OBnode !Text
    | -- | @:slug@, @cardano:Type@, @rdf:nil@, @\<full-iri\>@.
      OIri !Text
    | -- | A double-quoted string literal.
      OStringLit !Text
    | -- | A bare integer literal.
      OIntLit !Integer
    deriving stock (Eq, Ord, Show)

{- | The graph as a subject-keyed index into its predicate-object
pairs. Same subject appearing in multiple statement blocks merges
predicate lists in source order (first-seen first).
-}
type Graph = Map Subject [(Predicate, Object)]

----------------------------------------------------------------------
-- Lookup helpers
----------------------------------------------------------------------

-- | All predicate-object pairs for a subject, in source order.
lookupPreds :: Subject -> Graph -> [(Predicate, Object)]
lookupPreds = Map.findWithDefault []

-- | First object on @subject pred@, if any.
findFirstObject :: Subject -> Predicate -> Graph -> Maybe Object
findFirstObject s p g =
    listToMaybe [o | (p', o) <- lookupPreds s g, p == p']

-- | All objects on @subject pred@, in source order.
findAllObjects :: Subject -> Predicate -> Graph -> [Object]
findAllObjects s p g = [o | (p', o) <- lookupPreds s g, p == p']

----------------------------------------------------------------------
-- Top-level parser
----------------------------------------------------------------------

{- | Parse the canonical Turtle subset emitted by the cardano-tx-tools
graph emitter into a subject-keyed graph index.
-}
parseTurtle :: ByteString -> Either Text Graph
parseTurtle bs = do
    let txt = TextEncoding.decodeUtf8 bs
    stmts <- splitStatements (Text.lines txt)
    pairs <- traverse parseStatement stmts
    pure $
        foldl
            (\m (s, ps) -> Map.insertWith (flip (<>)) s ps m)
            Map.empty
            pairs

----------------------------------------------------------------------
-- Statement splitting
----------------------------------------------------------------------

{- | Walk the file's lines and group them into statement blocks. A
statement starts at a non-blank, non-comment, non-directive,
non-indented line and ends at the first line whose stripped-right
last character is @.@ — the Turtle statement terminator.
-}
splitStatements :: [Text] -> Either Text [Text]
splitStatements = go [] []
  where
    go acc [] [] = Right (reverse acc)
    go _ buf [] =
        Left $
            "unterminated Turtle statement at end of input: "
                <> Text.unlines (reverse buf)
    go acc [] (line : rest)
        | isSkippable line = go acc [] rest
        | endsWithPeriod line = go (line : acc) [] rest
        | otherwise = go acc [line] rest
    go acc buf (line : rest)
        | endsWithPeriod line =
            let stmt = Text.unlines (reverse (line : buf))
             in go (stmt : acc) [] rest
        | otherwise = go acc (line : buf) rest

    isSkippable l =
        let stripped = Text.strip l
         in Text.null stripped
                || Text.isPrefixOf "#" stripped
                || Text.isPrefixOf "@" stripped

    endsWithPeriod t =
        case Text.unsnoc (Text.stripEnd t) of
            Just (_, '.') -> True
            _ -> False

----------------------------------------------------------------------
-- Per-statement parser
----------------------------------------------------------------------

{- | Tokenize a statement and parse it as a subject followed by one or
more semicolon-separated predicate-object pairs terminated by @.@.
-}
parseStatement :: Text -> Either Text (Subject, [(Predicate, Object)])
parseStatement stmt = do
    toks <- tokenize stmt
    case toks of
        (subTok : predToks) -> do
            subj <- toSubject subTok
            preds <- parsePreds predToks
            pure (subj, preds)
        [] -> Left "empty statement"

parsePreds :: [Tok] -> Either Text [(Predicate, Object)]
parsePreds = go
  where
    go [TDot] = Right []
    go (pT : oT : rest) = do
        p <- toPredicate pT
        o <- toObject oT
        case rest of
            (TSemi : more) -> ((p, o) :) <$> go more
            [TDot] -> Right [(p, o)]
            _ -> Left "expected ';' or '.' after predicate-object pair"
    go _ = Left "predicate-object pairs must terminate with '.'"

toSubject :: Tok -> Either Text Subject
toSubject = \case
    TBnode n -> Right (SBnode n)
    TIri n -> Right (SIri n)
    TA -> Left "subject position cannot be the 'a' keyword"
    TStringLit _ -> Left "subject position cannot be a string literal"
    TIntLit _ -> Left "subject position cannot be an integer literal"
    TSemi -> Left "unexpected ';' in subject position"
    TDot -> Left "unexpected '.' in subject position"

toPredicate :: Tok -> Either Text Predicate
toPredicate = \case
    TA -> Right PA
    TIri n -> Right (PIri n)
    TBnode _ -> Left "blank node is not a valid predicate"
    TStringLit _ -> Left "string literal is not a valid predicate"
    TIntLit _ -> Left "integer literal is not a valid predicate"
    TSemi -> Left "unexpected ';' in predicate position"
    TDot -> Left "unexpected '.' in predicate position"

toObject :: Tok -> Either Text Object
toObject = \case
    TBnode n -> Right (OBnode n)
    TIri n -> Right (OIri n)
    TStringLit s -> Right (OStringLit s)
    TIntLit i -> Right (OIntLit i)
    TA -> Left "'a' keyword is not a valid object"
    TSemi -> Left "unexpected ';' in object position"
    TDot -> Left "unexpected '.' in object position"

----------------------------------------------------------------------
-- Lexer
----------------------------------------------------------------------

data Tok
    = TBnode !Text
    | TIri !Text
    | TA
    | TStringLit !Text
    | TIntLit !Integer
    | TSemi
    | TDot
    deriving stock (Eq, Show)

-- | Tokenize a Turtle statement (one logical statement, multi-line allowed).
tokenize :: Text -> Either Text [Tok]
tokenize = go . dropWhitespace
  where
    go t
        | Text.null t = Right []
        | otherwise =
            case Text.uncons t of
                Nothing -> Right []
                Just (c, rest)
                    | c == ';' -> prepend TSemi (dropWhitespace rest)
                    | c == '.' -> prepend TDot (dropWhitespace rest)
                    | c == '"' -> readString rest
                    | c == '<' -> readAbsIri rest
                    | c == '_' && Text.take 1 rest == ":" ->
                        let nameStart = Text.drop 1 rest
                            (name, r) = Text.span isNameChar nameStart
                         in if Text.null name
                                then Left "empty blank-node label"
                                else prepend (TBnode name) (dropWhitespace r)
                    | c == ':' ->
                        -- ':slug' — prefixed name with empty prefix.
                        let (suffix, r) = Text.span isNameChar rest
                         in prepend (TIri (Text.cons ':' suffix)) (dropWhitespace r)
                    | isDigit c || c == '-' || c == '+' ->
                        let (numTxt, r) = Text.span numChar t
                         in case readMaybe (Text.unpack numTxt) :: Maybe Integer of
                                Just i -> prepend (TIntLit i) (dropWhitespace r)
                                Nothing -> Left $ "bad number: " <> numTxt
                    | isNameStart c ->
                        let (word, r) = Text.span isNameChar t
                         in if word == "a"
                                then prepend TA (dropWhitespace r)
                                else
                                    if Text.take 1 r == ":"
                                        then
                                            let r2 = Text.drop 1 r
                                                (local, r3) = Text.span isNameChar r2
                                                qname = word <> Text.cons ':' local
                                             in prepend (TIri qname) (dropWhitespace r3)
                                        else prepend (TIri word) (dropWhitespace r)
                    | otherwise -> Left $ "unexpected character: " <> Text.singleton c

    prepend tok r = (tok :) <$> go r

    readString rest = case findUnescapedQuote rest of
        Nothing -> Left "unterminated string literal"
        Just i ->
            let lit = Text.take i rest
                r = Text.drop (i + 1) rest
             in prepend (TStringLit lit) (dropWhitespace r)

    findUnescapedQuote = Text.findIndex (== '"')

    readAbsIri rest = case Text.findIndex (== '>') rest of
        Nothing -> Left "unterminated absolute IRI"
        Just i ->
            let iri = Text.take i rest
                r = Text.drop (i + 1) rest
             in prepend (TIri ("<" <> iri <> ">")) (dropWhitespace r)

    dropWhitespace = Text.dropWhile (\c -> c == ' ' || c == '\t' || c == '\n' || c == '\r')

    isNameStart c = isAlphaNum c || c == '_'
    isNameChar c = isAlphaNum c || c == '_' || c == '-' || c == '.'
    numChar c = isDigit c || c == '-' || c == '+'
