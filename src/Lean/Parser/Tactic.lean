/-
Copyright (c) 2020 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Leonardo de Moura, Sebastian Ullrich
-/
prelude
import Lean.Parser.Term

namespace Lean
namespace Parser
namespace Tactic

builtin_initialize
  register_parser_alias tacticSeq
  register_parser_alias tacticSeqIndentGt

/- This is a fallback tactic parser for any identifier which exists only
to improve syntax error messages.
```
example : True := by foo -- unknown tactic
```
-/
@[builtin_tactic_parser] def «unknown»    := leading_parser
  withPosition (ident >> errorAtSavedPos "unknown tactic" true)

@[builtin_tactic_parser] def nestedTactic := tacticSeqBracketed

def matchRhs  := Term.hole <|> Term.syntheticHole <|> tacticSeq
def matchAlts := Term.matchAlts (rhsParser := matchRhs)

/-- `match` performs case analysis on one or more expressions.
See [Induction and Recursion][tpil4].
The syntax for the `match` tactic is the same as term-mode `match`, except that
the match arms are tactics instead of expressions.
```
example (n : Nat) : n = n := by
  match n with
  | 0 => rfl
  | i+1 => simp
```

[tpil4]: https://lean-lang.org/theorem_proving_in_lean4/induction_and_recursion.html
-/
@[builtin_tactic_parser] def «match» := leading_parser:leadPrec
  "match " >> optional Term.generalizingParam >>
  optional Term.motive >> sepBy1 Term.matchDiscr ", " >>
  " with " >> ppDedent matchAlts

/--
The tactic
```
intro
| pat1 => tac1
| pat2 => tac2
```
is the same as:
```
intro x
match x with
| pat1 => tac1
| pat2 => tac2
```
That is, `intro` can be followed by match arms and it introduces the values while
doing a pattern match. This is equivalent to `fun` with match arms in term mode.
-/
@[builtin_tactic_parser] def introMatch := leading_parser
  nonReservedSymbol "intro" >> matchAlts

/--
`decide` attempts to prove a goal of type `p` by synthesizing an instance
of `Decidable p` and then reducing that instance. If it reduces to `isTrue h`,
then `h` is used to close the goal.

Limitations:
- The goal is not allowed to have local variables or metavariables.
  If there are local variables, you can try to `revert` them first.
- Because this uses kernel reduction to evaluate the term, it may not work in the
  presence of definitions by well founded recursion, since this requires reducing proofs.

## Examples

Proving inequalities:
```lean
example : 2 + 2 ≠ 5 := by decide
```

Trying to prove a false proposition:
```lean
example : 1 ≠ 1 := by decide
/-
tactic 'decide' proved that the proposition
  1 ≠ 1
is false
-/
```

Trying to prove a proposition whose `Decidable` instance fails to reduce
```lean
opaque unknownProp : Prop

open scoped Classical in
example : unknownProp := by decide
/-
tactic 'decide' failed for proposition
  unknownProp
since its 'Decidable' instance did not reduce to the 'isTrue' constructor:
  Classical.choice ⋯
-/
```

## Properties and relations

For equality goals for types with decidable equality, usually `rfl` can be used in place of `decide`.
```lean
example : 1 + 1 = 2 := by decide
example : 1 + 1 = 2 := by rfl
```
-/
@[builtin_tactic_parser] def decide := leading_parser
  nonReservedSymbol "decide"

/-- `native_decide` will attempt to prove a goal of type `p` by synthesizing an instance
of `Decidable p` and then evaluating it to `isTrue ..`. Unlike `decide`, this
uses `#eval` to evaluate the decidability instance.

This should be used with care because it adds the entire lean compiler to the trusted
part, and the axiom `ofReduceBool` will show up in `#print axioms` for theorems using
this method or anything that transitively depends on them. Nevertheless, because it is
compiled, this can be significantly more efficient than using `decide`, and for very
large computations this is one way to run external programs and trust the result.
```
example : (List.range 1000).length = 1000 := by native_decide
```
-/
@[builtin_tactic_parser] def nativeDecide := leading_parser
  nonReservedSymbol "native_decide"

builtin_initialize
  register_parser_alias "matchRhsTacticSeq" matchRhs

end Tactic
end Parser
end Lean
