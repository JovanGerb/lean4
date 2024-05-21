/-
Copyright (c) 2022 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Lake.Util.DRBMap
import Lake.Util.RBArray
import Lake.Util.Store

open Lean
namespace Lake

instance [Monad m] [EqOfCmpWrt κ β cmp] : MonadDStore κ β (StateT (DRBMap κ β cmp) m) where
  fetch? k := return (← get).find? k
  store k a :=  modify (·.insert k a)

instance [Monad m] : MonadStore κ α (StateT (RBMap κ α cmp) m) where
  fetch? k := return (← get).find? k
  store k a := modify (·.insert k a)

instance [Monad m] : MonadStore κ α (StateT (RBArray κ α cmp) m) where
  fetch? k := return (← get).find? k
  store k a :=  modify (·.insert k a)

instance [Monad m] : MonadStore Name α (StateT (NameMap α) m) :=
  inferInstanceAs (MonadStore _ _ (StateT (RBMap ..) _))
