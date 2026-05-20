{- |
Module      : Cardano.Tx.Graph.Emit.Monad
Description : Body-walker monad seam for the joint Turtle emitter (private).
License     : Apache-2.0

Private submodule of 'Cardano.Tx.Graph.Emit'. Introduces the
typed monadic seam @Emit = WriterT [Triple] (State (Set Subject))@
that future per-Conway-field projection slices (T103+) lower into
'Cardano.Tx.Graph.Emit.Triple.Triple' values via 'tellTriple', and
that hosts the 'introduce' helper used to dedup subjects reached
more than once during the walk (shared addresses, asset classes,
DReps).

The monad is intentionally non-class — it does not derive
@MonadWriter@ or @MonadState@ — so no @mtl@ dependency is needed;
the package's existing @transformers@ dep covers 'WriterT' and
'State'. Callers operate exclusively through the four exported
helpers ('tellTriple', 'introduce', 'runEmit', 'groupBySubject'),
keeping the seam closed so the writer/state layers can be swapped
later without touching call sites.

== Order invariants

* 'tellTriple' accumulates triples in call order. The Writer
  payload is a plain @[Triple]@; in practice we accept the
  @O(n)@ append cost because @T102@ uses @runEmit@ once per
  cluster and the per-cluster triple counts are small (\<20
  typical, \<200 worst-case T010 fixture 11).
* 'introduce' runs its body @Emit ()@ argument the first time
  a subject is seen and is a no-op on every later visit. The
  seen set is keyed on 'Subject' (which is 'Ord' as of T102)
  so both bnode and IRI subjects dedup uniformly.
* 'groupBySubject' walks the flat triple stream from left to
  right, accumulating per-subject @(Predicate, Object)@ pairs
  in insertion order, and emits the resulting 'SubjectBlock'
  list in order of first-seen subjects. This preserves the
  byte-equality property the Turtle serializer pins on the
  pre-refactor walker output.

== Why no @mtl@

Every call site stays inside this module's exports — the
projection walker (T103+) never directly lifts into the
@WriterT@ or @State@ transformer constructors. The monad
boundary is sharp enough that adding @mtl@ would buy nothing.
Should a later slice want polymorphic @MonadWriter (Set Foo) m@
constraints, that's the moment to add @mtl@; until then we
stay on @transformers@ and keep the closed-monad invariant
explicit.
-}
module Cardano.Tx.Graph.Emit.Monad (
    -- * The body-walker monad
    Emit,

    -- * Primitives
    tellTriple,
    introduce,

    -- * Runners
    runEmit,

    -- * Grouping
    groupBySubject,
) where

import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.State.Strict (State, get, put, runState)
import Control.Monad.Trans.Writer.Strict (WriterT, runWriterT, tell)
import Data.Set (Set)
import Data.Set qualified as Set

import Cardano.Tx.Graph.Emit.Triple (
    Object,
    Predicate,
    Subject,
    SubjectBlock (..),
    Triple (..),
 )

{- | The body-emitter monad. A 'WriterT' of 'Triple' accumulators
on top of a 'State' threading the seen-subject set used by
'introduce'.

The constructor is intentionally not exported: every caller
stays within the @tellTriple@ \/ @introduce@ \/ @runEmit@
surface so the writer/state implementation can evolve (e.g.
swap @[Triple]@ for a difference list) without touching call
sites.
-}
newtype Emit a
    = Emit (WriterT [Triple] (State (Set Subject)) a)
    deriving newtype (Functor, Applicative, Monad)

{- | Emit a single 'Triple' into the writer accumulator.

Triples are appended in call order; 'runEmit' returns them as
a flat @[Triple]@ in that same order. The accompanying state —
the seen-subject 'Set' used by 'introduce' — is unchanged by
'tellTriple' alone: subject membership is tracked by
'introduce', not by raw emission.
-}
tellTriple :: Triple -> Emit ()
tellTriple t = Emit (tell [t])

{- | Run the @Emit ()@ body the first time @subject@ is seen;
return @()@ without running the body on every later visit.

This is the dedup primitive: future slices wrap each
address-decomposition block, each asset-class block, each
DRep block (any subject reachable from more than one walker
path) in @introduce@ so the block emits exactly once.

The 'Set' state lives across the entire 'runEmit' computation,
so two @introduce subj action@ calls in separate sub-actions
sequenced inside the same 'Emit' computation share the same
seen-set.
-}
introduce :: Subject -> Emit () -> Emit ()
introduce subject (Emit body) = Emit $ do
    seen <- lift get
    if Set.member subject seen
        then pure ()
        else do
            lift (put (Set.insert subject seen))
            body

{- | Project the writer accumulator and the final seen-set out
of an 'Emit' computation.

The returned @[Triple]@ is in call order (the writer is
append-based; 'tellTriple' appends to the right). The
returned 'Set' is the union of every subject 'introduce' has
let through — useful for tests that want to assert dedup
coverage without inspecting the triple stream.
-}
runEmit :: Emit a -> ([Triple], Set Subject)
runEmit (Emit w) =
    let ((_a, triples), seen) =
            runState (runWriterT w) Set.empty
     in (triples, seen)

{- | Re-shape a flat @[Triple]@ stream into the 'SubjectBlock'
list the Turtle serializer consumes.

The walker scans left-to-right, accumulating per-subject
@(Predicate, Object)@ pairs in insertion order, and emits one
'SubjectBlock' per first-seen subject — also in order of
first appearance. The Turtle byte layout is sensitive to both:

* the order subjects appear (sections are organised by the
  walker; within each section the per-subject blocks must
  appear in walk order to match the pre-T102 byte output);
* the order predicate-object pairs appear inside a block (the
  serializer joins them with @;@ and rejects no permutations,
  so a re-shuffle would diff against the artisan fixtures).

For T102's fixture sizes (\<200 triples per cluster), the
linear lookup is fine.
-}
groupBySubject :: [Triple] -> [SubjectBlock]
groupBySubject = finish . foldl step (Set.empty, [], [])
  where
    -- step (seen, order, acc) t — see comments in 'finish'.
    step ::
        (Set Subject, [Subject], [(Subject, [(Predicate, Object)])]) ->
        Triple ->
        (Set Subject, [Subject], [(Subject, [(Predicate, Object)])])
    step (seen, order, acc) (Triple subj p o) =
        let (seen', order')
                | Set.member subj seen = (seen, order)
                | otherwise = (Set.insert subj seen, subj : order)
            acc' =
                case lookup subj acc of
                    Nothing -> (subj, [(p, o)]) : acc
                    Just pairs ->
                        (subj, (p, o) : pairs)
                            : filter ((/= subj) . fst) acc
         in (seen', order', acc')

    -- 'order' is in REVERSE first-appearance order; 'acc' is a
    -- list of (subject, REVERSED predicate-object pairs).
    -- 'finish' un-reverses both to recover insertion order.
    finish ::
        (Set Subject, [Subject], [(Subject, [(Predicate, Object)])]) ->
        [SubjectBlock]
    finish (_seen, order, acc) =
        [ SubjectBlock subj (reverse pairs)
        | subj <- reverse order
        , Just pairs <- [lookup subj acc]
        ]
