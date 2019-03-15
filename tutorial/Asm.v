(** We now consider as a target a simple control-flow-graph language,
    so-called _Asm_.
    Computations are represented as a collection of basic blocks
    linked by jumps.
 *)

(* begin hide *)
From Coq Require Import
     Strings.String
     Program.Basics
     ZArith.ZArith.

From ITree Require Import
     Basics.Function
     ITree
     OpenSum
     KTree.

From ExtLib Require Structures.Monad.

Require Import Imp.

Typeclasses eauto := 5.

(* end hide *)

(* ================================================================= *)
(** ** Syntax *)

(** Once again, a countable set of variables represented as [string]s: *)
Definition var : Set := string.
(** For simplicity, _Asm_ manipulates [nat]s as values too. *)
Definition value : Set := nat. 

(** We consider constants and variables as operands. *)
Variant operand : Set :=
| Oimm (_ : value)
| Ovar (_ : var).

(** The instruction set covers moves and arithmetic operations,
    as well as load and stores to the heap.
 *)
Variant instr : Set :=
| Imov (dest : var) (src : operand)
| Iadd (dest : var) (src : var) (o : operand)
| Isub (dest : var) (src : var) (o : operand)
| Imul (dest : var) (src : var) (o : operand)
| Iload (dest : var) (addr : operand)
| Istore (addr : var) (val : operand).

(** We consider both direct and conditional jumps *)
Variant branch {label : Type} : Type :=
| Bjmp (_ : label) (* jump to label *)
| Bbrz (_ : var) (yes no : label) (* conditional jump *)
| Bhalt
.
Global Arguments branch _ : clear implicits.

(** A basic [block] is a sequence of straightline instructions
    followed by a branch that either halts the execution,
    or transfers control to another [block]. *)
Inductive block {label : Type} : Type :=
| bbi (_ : instr) (_ : block)
| bbb (_ : branch label).
Global Arguments block _ : clear implicits.

(** A piece of code should expose the set of labels allowing
    to enter into it, as well as the set of outer labels it might
    jump to.
    To this end, [bks] represents a collection of blocks labeled
    by [A], with branches in [B]. *)
Definition bks A B := A -> block B.

(** An [asm] program represents the control flow of the computation.
    It is a collection of labelled [blocks] such that its labels are
    classified into three categories:
    - [A]: (visible) entry points
    - [B]: (visible) exit points
    - [internal]: (hidden) internal linked labels
    Note that they uniformely represent open and closed programs,
    the latter corresponding to an [asm] program with a unique entry
    point and always halting, i.e. a [asm unit void].
 *)
Record asm A B : Type :=
  {
    internal : Type;
    code : bks (internal + A) (internal + B)
  }.

Arguments internal {A B}.
Arguments code {A B}.

(* ================================================================= *)
(** ** Semantics *)

(** _Asm_ produces two kind of effects: through manipulation of the store
    and of the heap.
    We therefore reuse _Imp_'s [Locals], and define an additional pair of
    effects [Memory].
*)
Import Imp.

Inductive Memory : Type -> Type :=
| Load (addr : value) : Memory value
| Store (addr val : value) : Memory unit.

Section Denote.

  (** Once again, [asm] programs shall be deonted as [itree]s. *)

  (* begin hide *)
  Import ExtLib.Structures.Monad.
  Import MonadNotation.
  Local Open Scope monad_scope.
  (* end hide *)

  (** We introduce a special effect to model termination of the computation.
      Note that it expects _actively_ no answer from the environment: 
      [Done] is of type [Exit void].
      We can therefore use it to close a [itree E A] no matter what the expected
      return type [A] is, as witnessed by the [done] computation.
   *)
  Inductive Exit : Type -> Type :=
  | Done : Exit void.

  Definition done {E A} `{Exit -< E} : itree E A :=
    vis Done (fun v => match v : void with end).

  Section with_effect.

    (** As with _Imp_, we parameterize our semantics by a universe of effects
        that shall encompass all the required ones.
     *)
    Context {E : Type -> Type}.
    Context {HasLocals : Locals -< E}.
    Context {HasMemory : Memory -< E}.
    Context {HasExit : Exit -< E}.

    (** Operands are trivially denoted as [itree]s returning values *)
    Definition denote_operand (o : operand) : itree E value :=
      match o with
      | Oimm v => Ret v
      | Ovar v => lift (GetVar v)
      end.

    (** Instructions offer no suprises either. *)
    Definition denote_instr (i : instr) : itree E unit :=
      match i with
      | Imov d s =>
        v <- denote_operand s ;;
        lift (SetVar d v)
      | Iadd d l r =>
        lv <- lift (GetVar l) ;;
        rv <- denote_operand r ;;
        lift (SetVar d (lv + rv))
      | Isub d l r =>
        lv <- lift (GetVar l) ;;
        rv <- denote_operand r ;;
        lift (SetVar d (lv - rv))
      | Imul d l r =>
        lv <- lift (GetVar l) ;;
        rv <- denote_operand r ;;
        lift (SetVar d (lv * rv))
      | Iload d a =>
        addr <- denote_operand a ;;
        val <- lift (Load addr) ;;
        lift (SetVar d val)
      | Istore a v =>
        addr <- lift (GetVar a) ;;
        val <- denote_operand v ;;
        lift (Store addr val)
      end.

    Section with_labels.
      Context {A B : Type}.

      (** A [branch] returns the computed label whose set of possible
          values [B] is carried by the type of the branch.
          If the computation halts instead of branching,
          we return the [done] tree.
       *)
      Definition denote_branch (b : branch B) : itree E B :=
        match b with
        | Bjmp l => ret l
        | Bbrz v y n =>
          val <- lift (GetVar v) ;;
          if val:nat then ret y else ret n
        | Bhalt => done
        end.

      (** The denotation of a basic [block] shares the same type,
          returning the [label] of the next [block] it shall jump to.
          It recursively denote its instruction before that.
       *)
      Fixpoint denote_block (b : block B) : itree E B :=
        match b with
        | bbi i b =>
          denote_instr i ;; denote_block b
        | bbb b =>
          denote_branch b
        end.

      (** A labelled collection of blocks, [bks], is simply the pointwise
          application of [denote_block].
          However, its denotation is therefore crucially a [ktree],
          whose structure will be heavily taken profit of in the proof
          of the compiler.
       *)
      Definition denote_b (bs: bks A B): ktree E A B :=
        fun a => denote_block (bs a).

    End with_labels.

  (** One can think of an asm program as a circuit/diagram where wires
      correspond to jumps/program links.
      [denote_b] computes the meaning of each basic block as an [itree] that
      returns the label of the next block to jump to, laying down all our
      elementary wires. 
      In order to denote an [asm A B] program as a [ktree E A B], it therefore
      remains to wire all those denoted blocks together while hiding the
      internal lables.
      We accomplish this with the same [loop] combinator we used to denote
      _Imp_'s [while] loop.
      It directly takes our [denote_b (code s): ktree E (I + A) (I + B)] and
      hides [I] as desired.
   *)

    (* Denotation of [asm] *)
    Definition denote_asm {A B} : asm A B -> ktree E A B :=
      fun s => loop (denote_b (code s)).

  End with_effect.
End Denote.

(* ================================================================= *)
(** ** Interpretation *)

From ITree Require Import
     Effects.Env.

From ExtLib Require Import
     Core.RelDec
     Structures.Maps
     Data.Map.FMapAList.

(** Both environments and memory effects can be interpreted as "map" effects,
    exactly as we did for _Imp_. *)

Definition interpret_Locals {E : Type -> Type} `{envE var value -< E} :
  Locals ~> itree E :=
  fun _ e =>
    match e with
    | GetVar x => env_lookupDefault x 0
    | SetVar x v => env_add x v
    end.

Definition interpret_Memory {E : Type -> Type} `{envE value value -< E} :
  Memory ~> itree E :=
  fun _ e =>
    match e with
    | Load x => env_lookupDefault x 0
    | Store x v => env_add x v
    end.

(** Once again, we implement our Maps with a simple association list *)
Definition env := alist var value.
Definition memory := alist value value.

(* Enable typeclass instances for Maps keyed by strings and values *)
Instance RelDec_string : RelDec (@eq string) :=
  { rel_dec := fun s1 s2 => if String.string_dec s1 s2 then true else false}.

Instance RelDec_value : RelDec (@eq value) := { rel_dec := Nat.eqb }.

(* TODO: redefine the interpreter *)
(* Definition AsmEval (p: asm unit void): itree void1 (env * unit) := *)
(*   let p := interp evalLocals _ (denoteStmt s) in *)
(*   run_env _ p empty. *)
(* Definition run (p: asm unit done) : itree emptyE (env * (memory * unit)) := *)
(*   let eval := Sum1.elim interpret_Locals interpret_Memory in *)
(*   run_env _ (run_env _ (interp eval _ (denote_asm p tt)) empty) empty. *)


(**  *)