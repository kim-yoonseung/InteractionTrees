(** * Monadic interpretations of interaction trees *)

(** We can derive semantics for an interaction tree [itree E ~> M]
    from semantics given for every individual event [E ~> M],
    when [M] is a monad (actually, with some more structure).

    We define the following terminology for this library.
    Other sources may have different usages for the same or related
    words.

    The notation [E ~> F] stands for [forall T, E T -> F T]
    (in [ITree.Basics]).
    It can mean many things, including the following:

    - The semantics of itrees are given as monad morphisms
      [itree E ~> M], also called "interpreters".

    - "ITree interpreters" (or "itree morphisms") are monad morphisms
      where the codomain is made of ITrees: [itree E ~> itree F].

    Interpreters can be obtained from handlers:

    - In general, "event handlers" are functions [E ~> M] where
      [M] is a monad.

    - "ITree event handlers" are functions [E ~> itree F].

    Categorically, this boils down to saying that [itree] is a free
    monad (not quite, but close enough).
 *)

(* begin hide *)
From ExtLib Require Import
     Structures.Functor
     EitherMonad
     Structures.Monad.

From ITree Require Import
     Basics.Basics
     Core.ITreeDefinition
     Indexed.Relation.
(* end hide *)

(** ** Translate *)

(** An event morphism [E ~> F] lifts to an itree morphism [itree E ~> itree F]
    by applying the event morphism to every visible event.  We call this
    process _event translation_.

    Translation is a special case of interpretation:
[[
    translate h t ≈ interp (trigger ∘ h) t
]]
    However this definition of [translate] yields strong bisimulations
    more often than [interp].
    For example, [translate (id_ E) t ≅ id_ (itree E)].
*)

(** A plain event morphism [E ~> F] defines an itree morphism
    [itree E ~> itree F]. *)
(* Definition translateF {E F R} (h : E ~> F) (rec: itree E R -> itree F R) (t : itreeF E R _) : itree F R  := *)
(*   match t with *)
(*   | RetF x => Ret x *)
(*   | TauF t => Tau (rec t) *)
(*   | VisF e k => Vis (h _ e) (fun x => rec (k x)) *)
(*   end. *)

(* Definition translate {E F} (h : E ~> F) *)
(*   : itree E ~> itree F *)
(*   := fun R => cofix translate_ t := translateF h translate_ (observe t). *)

(* Arguments translate {E F} h [T]. *)

(** ** Interpret *)

(** An event handler [E ~> M] defines a monad morphism
    [itree E ~> M] for any monad [M] with a loop operator. *)

Definition interp_either {E M : Type -> Type} {A: Type}
           {FM : Functor M} {MM : Monad M} {IM : MonadIter M}
           (h : E ~> eitherT A M) :
  eitherT A (itree E) ~> eitherT A M :=
  fun R => iter (fun t =>
                match observe (unEitherT t) with
                | RetF (inl a) => mkEitherT (ret (inl a))
                | RetF (inr r) => ret (inr r)
                | TauF t => ret (inl (mkEitherT t))
                | VisF e k => fmap (fun x => inl (mkEitherT (k x))) (h _ e)
                end).

Definition interp_either' {E M : Type -> Type} {A: Type}
           {FM : Functor M} {MM : Monad M} {IM : MonadIter M}
           (h : E ~> M) :
  eitherT A (itree E) ~> eitherT A M :=
  fun R => iter (fun t =>
                match observe (unEitherT t) with
                | RetF (inl a) => mkEitherT (ret (inl a))
                | RetF (inr r) => ret (inr r)
                | TauF t => ret (inl (mkEitherT t))
                | VisF e k => fmap (fun x => inl (mkEitherT (k x))) (MonadTrans.lift (h _ e))
                end).

Arguments interp_either {E M A FM MM IM} h [T].
