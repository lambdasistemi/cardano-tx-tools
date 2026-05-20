{- |
Module      : Cardano.Tx.Graph.Emit.Triple
Description : Typed in-memory IR for the body emitter (private).
License     : Apache-2.0

Private submodule of 'Cardano.Tx.Graph.Emit'. Defines the typed
intermediate representation the projection walker
('Cardano.Tx.Graph.Emit.Project') produces and the serializers
('Cardano.Tx.Graph.Emit.Serialize.*') consume — closes
Q-001 / A-001 (Option B with the @PRdfType@ distinguished
constructor).

The IR distinguishes the four roles a Turtle token can play —
blank-node reference, prefixed IRI, string literal, integer
literal — so the serializer never re-parses the text payloads.
Subjects and objects share most of the constructor space; the
@rdf:type@ predicate has its own constructor so the Turtle
serializer can render the Turtle @a@ keyword without
string-matching.

The IR is re-exported from the public 'Cardano.Tx.Graph.Emit'
module; T005's 'Cardano.Tx.Graph.EmitGoldenSpec' /
'Cardano.Tx.Graph.Emit.VocabTraceabilitySpec' construct values
indirectly (via @emit@ + @serialize@), but
'Cardano.Tx.Graph.EmitSmokeSpec' references the constructors
directly as compile-only assertions.
-}
module Cardano.Tx.Graph.Emit.Triple (
    -- * Triples
    Triple (..),
    Subject (..),
    Predicate (..),
    Object (..),

    -- * Subject blocks + body sections
    SubjectBlock (..),
    BodySection (..),
) where

import Data.Text (Text)

import Cardano.Tx.Graph.Emit.Lookup (BnodeName)

{- | The subject position of a Turtle statement.

* 'SBnode' — a blank-node reference (@_:foo@).
* 'SIri' — a prefixed CURIE (@\<prefix\>:\<local\>@); the text
  payload carries the full @prefix:local@ form (e.g.
  @"cardano:Transaction"@, @":alice"@).
-}
data Subject
    = SBnode !BnodeName
    | SIri !Text
    deriving stock (Eq, Show)

{- | The predicate position of a Turtle statement.

Predicates are always IRIs in Turtle; the body emitter only ever
writes prefixed CURIEs ('PIri') plus the special @rdf:type@
case rendered with the Turtle @a@ keyword ('PRdfType').
-}
data Predicate
    = PIri !Text
    | -- | The @rdf:type@ predicate; always renders as the
      -- Turtle @a@ keyword without a @rdf:@ prefix declaration.
      PRdfType
    deriving stock (Eq, Show)

{- | The object position of a Turtle statement.

Fixture 02's emitter coverage uses only 'OBnode', 'OIri',
'OStringLit', 'OIntLit'. T006-T010 may add cases (e.g.
@OHexLit@ for inline-datum hex strings); @-Wincomplete-patterns@
catches gaps at compile time.
-}
data Object
    = OBnode !BnodeName
    | OIri !Text
    | OStringLit !Text
    | OIntLit !Integer
    deriving stock (Eq, Show)

{- | A single Turtle triple — @Subject Predicate Object@.

Triple is kept as a wrapper rather than a tuple so its public
re-export from 'Cardano.Tx.Graph.Emit' carries a stable nominal
identity across slices.
-}
data Triple = Triple !Subject !Predicate !Object
    deriving stock (Eq, Show)

{- | One subject with all its predicate/object pairs. The Turtle
serializer renders a 'SubjectBlock' as a single @subject ;\n
  predicate object ;\n  ...\n  predicate object .@ block.

The order of predicates inside the block matters for byte
equality; the projection walker emits them in the fixed order
research R4 pins.
-}
data SubjectBlock = SubjectBlock
    { subjectBlockSubject :: !Subject
    , subjectBlockPredicates :: ![(Predicate, Object)]
    }
    deriving stock (Eq, Show)

{- | A body section — a uniform comment header plus the
'SubjectBlock' values that follow it.

Research R4 enumerates the section breaks: @Transaction body.@,
@Input N@, @Output N@, @Address decompositions — …@, etc. The
header text omits the trailing period (e.g. @"Transaction body"@,
@"Input 1"@); the serializer wraps it in @# …\\n@ with the
@\#\\n\# header\\n\#\\n@ three-line frame research R4 pins.
-}
data BodySection = BodySection
    { sectionHeader :: !Text
    , sectionBlocks :: ![SubjectBlock]
    }
    deriving stock (Eq, Show)
