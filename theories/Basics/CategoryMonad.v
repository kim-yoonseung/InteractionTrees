From Coq Require Import
     Setoid
     Morphisms.

From ITree Require Import
     CategoryOps
     CategoryFunctor.

Import Carrier.
Import CatNotations.
Local Open Scope cat_scope.

(* Monads are monoid in the category of endofunctors.
 * For ease of use, we define a monad using programmatic convention of "ret" and
 * "bind", and the monad laws are Haskell-like (bind unit and composition laws). *)
Section Monad.

  Context {obj : Type} {C : obj -> obj -> Type}
          {M : obj -> obj} (* An endofunctor. *)
          {ret : forall a, C a (M a)}
          {bind : forall a b (f : C a (M b)), C (M a) (M b)}
          `{Eq2 _ C} `{Id_ _ C} `{Cat _ C}

(* IY: Do we want to show that a monad is a monoid in the category of endofunctors?        We don't *need* these definitions here for stating the monad laws. *)
          {bif : binop obj}
          {fmap : forall a b, C a b -> C (M a) (M b)}
          {endofunctor : Functor C C M (@fmap)}
          .

  Arguments fmap {a b}.
  Arguments ret {a}.
  Arguments bind {a b}.

  (* Monad laws, annotated with equivalent Haskell-like monad laws in comments. *)
  Class Monad : Prop :=
  {
    (* bind (ret x) f = f a *)
    bind_ret_l {a b} (f : C a (M b)): ret >>> bind f ⩯ f;

    (* bind ma (fun x => ret x) = ret x *)
    bind_ret_r {a} : bind ret ⩯ id_ (M a);

    (* bind (bind ma f) g = bind ma (fun y => bind (f y) g) *)
    bind_bind {a b c} (f : C a (M b)) (g : C b (M c)) :
      bind f >>> bind g ⩯ bind (f >>> bind g);

    bind_proper {a b} : Proper (eq2 ==> eq2) (@bind a b)
  }.

  Notation "m >>= f" := (bind f m) (at level 42, right associativity).

End Monad.

Arguments Monad : clear implicits.
Arguments Monad {_} C M ret bind {_ _ _}.
