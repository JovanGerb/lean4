/-
Copyright (c) 2020 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Leonardo de Moura
-/
import Lean.Elab.Term

namespace Lean
namespace Elab
namespace Term

/- This modules assumes "match"-expressions use the following syntax.

```lean
def matchAlt : Parser :=
nodeWithAntiquot "matchAlt" `Lean.Parser.Term.matchAlt $
  sepBy1 termParser ", " >> darrow >> termParser

def matchAlts (optionalFirstBar := true) : Parser :=
withPosition $ fun pos =>
  (if optionalFirstBar then optional "| " else "| ") >>
  sepBy1 matchAlt (checkColGe pos.column "alternatives must be indented" >> "|")

def matchDiscr := optIdent >> termParser

def «match» := parser!:leadPrec "match " >> sepBy1 matchDiscr ", " >> optType >> " with " >> matchAlts
```
-/

structure MatchAltView :=
(patterns : Array Syntax)
(rhs      : Syntax)

def mkMatchAltView (matchAlt : Syntax) : MatchAltView :=
{ patterns := (matchAlt.getArg 0).getArgs.getSepElems, rhs := matchAlt.getArg 2 }

private def expandSimpleMatch (stx discr lhsVar rhs : Syntax) (expectedType? : Option Expr) : TermElabM Expr := do
newStx ← `(let $lhsVar := $discr; $rhs);
withMacroExpansion stx newStx $ elabTerm newStx expectedType?

private def expandSimpleMatchWithType (stx discr lhsVar type rhs : Syntax) (expectedType? : Option Expr) : TermElabM Expr := do
newStx ← `(let $lhsVar : $type := $discr; $rhs);
withMacroExpansion stx newStx $ elabTerm newStx expectedType?

private def expandMatchOptTypeAux (ref : Syntax) : Nat → MacroM Syntax
| 0   => pure $ mkHole ref
| n+1 => do t ← expandMatchOptTypeAux n; r ← `(forall _, $t); pure (r.copyInfo ref)

private def expandMatchOptType (ref : Syntax) (optType : Syntax) (numDiscrs : Nat) : MacroM Syntax :=
if optType.isNone then
  expandMatchOptTypeAux ref numDiscrs
else
  pure $ (optType.getArg 0).getArg 1

private def elabMatchOptType (matchStx : Syntax) (numDiscrs : Nat) : TermElabM Expr := do
typeStx ← liftMacroM $ expandMatchOptType matchStx (matchStx.getArg 2) numDiscrs;
elabType typeStx

private partial def elabDiscrsAux (ref : Syntax) (discrStxs : Array Syntax) (expectedType : Expr) : Nat → Expr → Array Expr → TermElabM (Array Expr)
| i, matchType, discrs =>
  if h : i < discrStxs.size then do
    let discrStx := discrStxs.get ⟨i, h⟩;
    matchType ← whnf ref matchType;
    match matchType with
    | Expr.forallE _ d b _ => do
      discr ← elabTerm discrStx d;
      discr ← ensureHasType discrStx d discr;
      elabDiscrsAux (i+1) (b.instantiate1 discr) (discrs.push discr)
    | _ => throwError ref ("invalid type provided to match-expression, function type with arity #" ++ toString discrStxs ++ " expected")
  else do
    unlessM (isDefEq ref matchType expectedType) $
      throwError ref ("invalid result type provided to match-expression" ++ indentExpr matchType ++ Format.line ++ "expected type" ++ indentExpr expectedType);
    pure discrs

private def elabDiscrs (ref : Syntax) (discrStxs : Array Syntax) (matchType : Expr) (expectedType : Expr) : TermElabM (Array Expr) :=
elabDiscrsAux ref discrStxs expectedType 0 matchType #[]

/-
nodeWithAntiquot "matchAlt" `Lean.Parser.Term.matchAlt $ sepBy1 termParser ", " >> darrow >> termParser
-/
def expandMacrosInPatterns (matchAlts : Array MatchAltView) : TermElabM (Array MatchAltView) := do
env ← getEnv;
matchAlts.mapM fun matchAlt => do
  patterns ← liftMacroM $ matchAlt.patterns.mapM $ expandMacros env;
  pure $ { matchAlt with patterns := patterns }

/- Given `stx` a match-expression, return its alternatives. -/
private def getMatchAlts (stx : Syntax) : Array MatchAltView :=
let alts : Array Syntax := (stx.getArg 5).getArgs.filter fun alt => alt.getKind == `Lean.Parser.Term.matchAlt;
alts.map mkMatchAltView

/-
```
parser!:leadPrec "match " >> sepBy1 matchDiscr ", " >> optType >> " with " >> matchAlts
```
Remark the `optIdent` must be `none` at `matchDiscr`. They are expanded by `expandMatchDiscr?`.
-/
private def elabMatchCore (stx : Syntax) (expectedType? : Option Expr) : TermElabM Expr := do
tryPostponeIfNoneOrMVar expectedType?;
expectedType ← match expectedType? with
  | some expectedType => pure expectedType
  | none              => mkFreshTypeMVar stx;
let discrStxs := (stx.getArg 1).getArgs.getSepElems.map fun d => d.getArg 1;
matchType ← elabMatchOptType stx discrStxs.size;
matchAlts ← expandMacrosInPatterns $ getMatchAlts stx;
discrs ← elabDiscrs stx discrStxs matchType expectedType;
throwError stx ("WIP type: " ++ matchType ++ "\n" ++ discrs ++ "\n" ++ toString (matchAlts.map fun alt => toString alt.patterns))

/-- Expand discriminants of the form `h : t` -/
private def expandMatchDiscr? (stx : Syntax) : MacroM (Option Syntax) := do
pure none -- TODO

-- parser! "match " >> sepBy1 termParser ", " >> optType >> " with " >> matchAlts
@[builtinTermElab «match»] def elabMatch : TermElab :=
fun stx expectedType? => match_syntax stx with
  | `(match $discr:term with $y:ident => $rhs:term)           => expandSimpleMatch stx discr y rhs expectedType?
  | `(match $discr:term with | $y:ident => $rhs:term)         => expandSimpleMatch stx discr y rhs expectedType?
  | `(match $discr:term : $type with $y:ident => $rhs:term)   => expandSimpleMatchWithType stx discr y type rhs expectedType?
  | `(match $discr:term : $type with | $y:ident => $rhs:term) => expandSimpleMatchWithType stx discr y type rhs expectedType?
  | _ => do
    stxNew? ← liftMacroM $ expandMatchDiscr? stx;
    match stxNew? with
    | some stxNew => withMacroExpansion stx stxNew $ elabTerm stxNew expectedType?
    | none        => elabMatchCore stx expectedType?

end Term
end Elab
end Lean
