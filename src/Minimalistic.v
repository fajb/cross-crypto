Require Import FCF.
Require Import Asymptotic.
Require Import Admissibility.
Require Import Tactics.
Require Import FrapTactics.
Require Import splitVector.
Require Import Coq.Classes.Morphisms.

Section TODO.
  Lemma maxRat_eq : forall r, maxRat r r = r.
    intros.
    unfold maxRat.
    cases (bleRat r r); trivial.
  Qed.

  Lemma minRat_eq : forall r, minRat r r = r.
    intros.
    unfold minRat.
    cases (bleRat r r); trivial.
  Qed.

  Lemma ratDistance_0 : forall r, ratDistance r r == 0.
    intros.
    unfold ratDistance.
    rewrite maxRat_eq.
    rewrite minRat_eq.
    apply ratSubtract_0.
    reflexivity.
  Qed.

  Global Instance Proper_negligible : Proper (pointwise_relation nat eqRat ==> iff) negligible.
  Proof.
    cbv [pointwise_relation Proper respectful].
    intros.
    split; eauto 10 using negligible_eq.
    intro.
    eapply negligible_eq.
    eassumption.
    symmetry.
    eauto.
  Qed.

  Global Instance Proper_negligible_le : Proper (pointwise_relation nat leRat ==> Basics.flip Basics.impl) negligible.
  Proof.
    cbv [pointwise_relation Proper respectful].
    intros.
    intro.
    eauto using negligible_le.
  Qed.

  Lemma negligible_0 : negligible (fun _ => 0).
    eapply negligible_le with (f1 := fun n => 0 / expnat 2 n).
    reflexivity.
    apply negligible_const_num.
  Qed.
End TODO.

Section Language.
  Context {base_type : Set} {interp_base_type:base_type->Set}.

  Inductive type := Type_base (t:base_type) | Type_arrow (dom:type) (cod:type).
  Global Coercion Type_base : base_type >-> type.
  Fixpoint interp_type (t:type) : Set :=
    match t with
    | Type_base t => interp_base_type t
    | Type_arrow dom cod => interp_type dom -> interp_type cod
    end.

  (* interp term takes in eta, comp_interp_term passes in eta , term should include nat -> *)

  Context {message list_message rand : base_type}.
  Inductive term : type -> Type :=
  | Term_const {t} (_:interp_type t) : term t
  | Term_random (_:nat) : term rand
  | Term_adversarial (_:term list_message) : term message
  | Term_app {dom cod} (_:term (Type_arrow dom cod)) (_:term dom) : term cod.

  (* the first natural number that is not a valid randomness index *)
  Fixpoint rand_end {t:type} (e:term t) : nat :=
    match e with
    | Term_random n => S n
    | Term_app f x => max (rand_end f) (rand_end x)
    | _ => 0
    end.

  Context (interp_random : nat -> interp_type rand).
  Context (interp_adversarial : interp_type list_message -> interp_type message).
  Fixpoint interp_term
           {t} (e:term t) : interp_type t :=
    match e with
    | Term_const c => c
    | Term_random n => interp_random n
    | Term_adversarial ctx => interp_adversarial (interp_term ctx)
    | Term_app f x => (interp_term f) (interp_term x)
    end.
End Language.
Arguments type : clear implicits.
Arguments interp_type {_} _ _.
Arguments term {_} _ _ _ _ _.
Arguments rand_end [_ _ _ _ _ _] _.

Section CompInterp.
  Inductive base_type := BaseType_bool | BaseType_message | BaseType_list_message.
  Definition interp_base_type t :=
    match t with
    | BaseType_bool => bool
    | BaseType_message => list bool
    | BaseType_list_message => list (list bool)
    end.
  Let term := (term interp_base_type BaseType_message BaseType_list_message BaseType_message).

  (* different protocols may use different amounts of randomness at the same security level. this is an awkward and boring parameter *)
  Context (rand_size : nat -> nat).

  Section WithAdversary.
    (* the adversary is split into three parts for no particular reason. It first decides how much randomness it will need, then interacts with the protocol (repeated calls to [adverary] with all messages up to now as input), and then tries to claim victory ([distinguisher]). There is no explicit sharing of state between these procedures, but all of them get the same random inputs in the security game. The handling of state is a major difference between FCF [OracleComp] and this framework *)
    Context (evil_rand_tape_len : nat -> nat).
    Context (adversary:nat -> list bool -> list (list bool) -> list bool).
    Context (distinguisher: forall {t}, nat -> list bool -> interp_type interp_base_type t -> bool).

    Definition comp_interp_term (good_rand_tape evil_rand_tape:list bool) eta {t} (e:term t) :=
      let interp_random (n:nat) : interp_type interp_base_type (Type_base BaseType_message)
          := List.firstn (rand_size eta) (List.skipn (n * rand_size eta) good_rand_tape) in
      let interp_adversarial : interp_type interp_base_type (Type_arrow (Type_base BaseType_list_message) (Type_base BaseType_message))
          := adversary eta evil_rand_tape in
      interp_term interp_random interp_adversarial e.

    Definition universal_security_game eta {t:type base_type} (e:term t) : Comp bool :=
      good_rand_tape' <-$ {0,1}^(rand_end e * rand_size eta);
        evil_rand_tape' <-$ {0,1}^(evil_rand_tape_len eta);
        let good_rand_tape := Vector.to_list good_rand_tape' in
        let evil_rand_tape := Vector.to_list evil_rand_tape' in
        let out := comp_interp_term good_rand_tape evil_rand_tape eta e in
        ret (distinguisher _ eta evil_rand_tape out).
  End WithAdversary.

  Definition indist {t:type base_type} (a b:term t) : Prop :=  forall l adv dst,
      (* TODO: insert bounds on coputational complexity of [adv] and [dst] here *)
      let game eta e := universal_security_game l adv dst eta e in
      negligible (fun eta => | Pr[game eta a] -  Pr[game eta b] | ).

  Global Instance Reflexive_indist {t} : Reflexive (@indist t).
  Proof.
    cbv [Reflexive indist]; setoid_rewrite ratDistance_0; eauto using negligible_0.
  Qed.

  Print Reflexive.
  Print Symmetric.

  Global Instance Symmetric_indist {t} : Symmetric (@indist t).
  Proof.
    cbv [Symmetric indist]; intros; setoid_rewrite ratDistance_comm; eauto.
  Qed.

  Global Instance Transitive_indist {t} : Transitive (@indist t).
  Proof.
    cbv [Transitive indist]; intros; setoid_rewrite ratTriangleInequality; eauto using negligible_plus.
  Qed.

        (* dst : forall t : type base_type, nat -> list bool -> interp_type interp_base_type t -> bool, *)

  Lemma not_indist_const {t} (x y : interp_type interp_base_type t) (tEqDec:forall x y : interp_type interp_base_type t, {x=y}+{x<>y}) (typeDec : forall x y : type base_type, {x=y}+{x<>y}) (H:x <> y) : ~indist (Term_const x) (Term_const y).
  Proof.
    cbv [indist].
    intro X.
    specialize (X id (fun _ _ _ => nil)
                  ((fun t' => match typeDec t t' with
                           | left pfeq => fun _ _ x' => ltac:(
                                                      rewrite <- pfeq in x'; exact (if tEqDec x x' then true else false))
                           | right pfne => fun _ _ _ => false
                           end))).

    cbv [universal_security_game comp_interp_term interp_term] in X.
    destruct (typeDec t t) in X; [|congruence].
    cbv [eq_rec_r eq_rec eq_rect eq_sym] in X.
    replace e with (eq_refl:t=t) in X by admit.

    destruct (tEqDec x x) in X; [|congruence].
    destruct (tEqDec x y) in X; [congruence|].
    cbv[negligible] in X.
    specialize (X 1%nat).
    destruct X as [n' X].
    specialize (X (1+n')%nat).
    assert (nz (1+n')) by (constructor; omega).
    specialize (X H0).
    assert (1 + n' > n') by omega.
    specialize (X H1).
    apply X; clear X.

    lazymatch goal with
      |- context [ Pr [?C] ] =>
      let H := fresh "H" in
      assert (Pr [C] == 1) as H;
        [|rewrite H; clear H]
    end.
    {
      fcf_irr_l; fcf_well_formed; fcf_irr_l; fcf_well_formed; fcf_compute.
    }

  lazymatch goal with
    |- context [ Pr [?C] ] =>
    let H := fresh "H" in
    assert (Pr [C] == 0) as H;
    [|rewrite H; clear H]
  end.
    {
      fcf_irr_l; fcf_well_formed; fcf_irr_l; fcf_well_formed; fcf_compute.
    }
    {
      lazymatch goal with |- ?a <= ?b => change (a <= 1) end.
      apply rat_le_1.
      apply expnat_ge_1.
      omega.
    }
  Admitted.
    (* fcf_compute. *)
    (* Unset Printing Notations. *)
    (* Show. *)

    (* fcf_simp. *)

    (* SearchAbout Rat. *)

    (* SearchAbout Rat refl. *)

    (* fcf_irr_r. *)
    (* Print RatRel. *)
    (* constructor; eauto. *)
  (* Context (KeyGen : forall n, term rand -> Key n). *)
  (* Context (Encrypt : forall n, Key n -> Plaintext n -> term rand -> Ciphertext n). *)
  (* Context (Decrypt : forall n, Key n -> Ciphertext n -> Plaintext n). *)

  (* Context (admissible_A1: pred_oc_fam). *)
  (* Context (admissible_A2: pred_oc_func_2_fam). *)

  (* Lemma indist_encrypt : *)
  (*   forall n (p0 p1 : term Plaintext n) (n0 n1 : nat), *)
  (*     n0 <> n1 -> *)
  (*     indist (Term_app (Term_const (Encrypt n)) ((Term_const (KeyGen n))  p0) *)
  (* Lemma indist_refl {t} (x:term t) : indist x x. *)
(* End SymbolicProof. *)


(** proving soundness of symbolic axioms *)
  End CompInterp.

Section SymbolicProof.
  Context {base_type : Set} {interp_base_type : base_type -> Set}.
  Local Coercion type_base (t:base_type) : type base_type := Type_base t.
  Context {message list_message rand bool : base_type}.
  Local Notation term := (term interp_base_type message list_message rand).
  Context (indist : forall {t : type base_type}, term t -> term t -> Prop). Arguments indist {_} _ _.

  Context (if_then_else : forall {t}, term (Type_arrow bool (Type_arrow t (Type_arrow t t)))). Arguments if_then_else {_}.
  Context (indist_rand: forall x y, indist (Term_random x) (Term_random y)).
  Context (indist_if_then_else_irrelevant_l : forall t (x y:term t),
              indist x y -> forall b:term bool, indist (Term_app (Term_app (Term_app if_then_else b) x) y) x).

  Lemma indist_if_then_else_rand_l (b:term bool) (x y:nat) :
    indist (Term_app (Term_app (Term_app if_then_else b) (Term_random x)) (Term_random y)) (Term_random x).
  Proof. exact (indist_if_then_else_irrelevant_l _ _ _ (indist_rand x y) _). Qed.
End SymbolicProof.

Definition if_then_else {t : type base_type}
  : interp_type interp_base_type (Type_arrow (type_base BaseType_bool) (Type_arrow t (Type_arrow t t)))
  := fun (b : bool) (x y : interp_type interp_base_type t) => if b then x else y.

Definition image_relation {T} (R:T->T->Prop) {A} (f:A->T) := fun x y => R (f x) (f y).
Global Instance Equivalence_image_relation {T R} {Equivalence_R:Equivalence R} {A} (f:A->T) :
  Equivalence (image_relation R f).
Admitted.

Definition Distribution_eq {A} := pointwise_relation A eqRat.
Global Instance Equivalence_Distribution_eq {A} : Equivalence (@Distribution_eq A).
Admitted.

Definition Comp_eq {A} := image_relation Distribution_eq (@evalDist A).
Check (_:Equivalence Comp_eq).

Global Instance Proper_evalDist {A} : Proper (Comp_eq ==> Distribution_eq) (@evalDist A).
Proof. exact (fun _ _ => id). Qed.

Global Instance Proper_getSupport {A} : Proper (Comp_eq ==> (@Permutation.Permutation _)) (@getSupport A).
Proof. intros ???; eapply evalDist_getSupport_perm_id; assumption. Qed.

Global Instance Proper_sumList {A:Set} : Proper ((@Permutation.Permutation A) ==> (Logic.eq ==> eqRat) ==> eqRat) (@sumList A).
Proof.
Admitted.

Global Instance Proper_Bind {A B} : Proper (Comp_eq ==> (Logic.eq==>Comp_eq) ==> Comp_eq) (@Bind A B).
Proof.
  intros ?? H ?? G ?. simpl evalDist.

  (* TODO: find out why setoid rewrite does not do this *)
  etransitivity; [|reflexivity].
  eapply Proper_sumList.
  eapply Proper_getSupport.
  eassumption.
  intros ? ? ?; subst.
  f_equiv.
  { eapply Proper_evalDist. assumption. }
  { eapply Proper_evalDist. eapply G. reflexivity. }
Qed.


Lemma Rnd_split_equiv n1 n2 : Comp_eq
    (x <-$ { 0 , 1 }^ n1 + n2; ret splitVector n1 n2 x)
    (x1 <-$ { 0 , 1 }^ n1; x2 <-$ { 0 , 1 }^ n2; ret (x1, x2)).
Proof. intro z. eapply Rnd_split_equiv. Qed.

Lemma eq_impl_negligible : forall A (x y : nat -> Comp A), pointwise_relation _ Comp_eq x y -> forall t, negligible (fun eta : nat => | evalDist (x eta) t - evalDist (y eta) t|).
  Admitted.

Lemma Comp_eq_bool (x y:Comp bool) :
 well_formed_comp x
 -> well_formed_comp y
  -> Pr [x] == Pr[y]
  -> Comp_eq x y.
  intros.
  intro b.
  destruct b; trivial.
  rewrite !evalDist_complement; trivial.
  f_equiv; trivial.
Qed.

Lemma Comp_eq_evalDist A (x y:Comp A) :
 well_formed_comp x
 -> well_formed_comp y
  -> (forall c, evalDist x c == evalDist y c)
  -> Comp_eq x y.
  intros.
  intro b.
  apply H1.
Qed.
(* Lemma Comp_eq_impl_evalDist A (x y : Comp A): *)
(*   Comp_eq x y -> *)
(*   evalDist *)
Print Distribution.

Axiom random_size : nat -> nat.
Goal False.

  (* pose_proof (forall t (x : term t), indist x x) as H. *)

  (* pose proof (fun A B => indist_if_then_else_rand_l (bool:=BaseType_bool) (@indist random_size) (fun _ => Term_const if_then_else) A B) as H. *)

  pose proof (fun A B => indist_if_then_else_rand_l (bool:=BaseType_bool) (@indist random_size) (fun _ => Term_const if_then_else) A B) as H.
  match type of H with ?A -> ?C => assert A as HA; [clear H|specialize(H HA);clear HA] end.

(* 2 subgoals, subgoal 1 (ID 30) *)
  
(*   ============================ *)
(*   forall x y : nat, x <> y -> indist id (Term_random x) (Term_random y) *)

  cbv [rand_end indist universal_security_game comp_interp_term interp_term]. (* to monadic probability notation *)
  intros.
  pose proof negligible_const_num 1.
  apply eq_impl_negligible.
  intros eta.
  apply Comp_eq_bool.
  fcf_well_formed.
  fcf_well_formed.
  dist_swap_l.
  dist_swap_r.
  fcf_skip.
  generalize (random_size eta) as D; intro D.

  assert (Pr [c <-$ (d <-$ (a <-$ { 0 , 1 }^ x * D + D; ret (splitVector (x * D) D a)); ret snd d);
              ret dst (Type_base BaseType_message) eta (Vector.to_list x0) (Vector.to_list c) ] ==
          Pr [c <-$ (d <-$ (a <-$ { 0 , 1 }^ y * D + D; ret (splitVector (y * D) D a)); ret snd d);
              ret dst (Type_base BaseType_message) eta (Vector.to_list x0) (Vector.to_list c) ] ).
  {
    fcf_skip.
    match goal with |- evalDist ?C1 ?x == evalDist ?C2 ?x => generalize x; change (Comp_eq C1 C2) end.
    setoid_rewrite Rnd_split_equiv.
    apply Comp_eq_evalDist.
    {
      fcf_well_formed.
    }
    {
      fcf_well_formed.
    }
    {
      intros.
      fcf_inline_first.
      fcf_at fcf_inline fcf_left 1%nat.
      fcf_at fcf_inline fcf_right 1%nat.
      fcf_swap fcf_left.
      fcf_swap fcf_right.
      fcf_skip.
      fcf_at fcf_ret fcf_left 1%nat.
      fcf_at fcf_ret fcf_right 1%nat.
      cbv [snd].
      fcf_irr_l.
      {
        fcf_well_formed.
      }
      fcf_irr_r.
      {
        fcf_well_formed.
      }
    }
  }
  Admitted.


(* 2 subgoals, subgoal 1 (ID 34) *)
  
(*   ============================ *)
(*   forall x y : nat, *)
(*   x <> y -> *)
(*   forall (l : nat -> nat) (adv : nat -> list bool -> list (list bool) -> list bool) *)
(*     (dst : forall t : type base_type, nat -> list bool -> interp_type interp_base_type t -> bool), *)
(*   negligible *)
(*     (fun eta : nat => *)
(*      | *)
(*      Pr [good_rand_tape' <-$ { 0 , 1 }^ S x * id eta; *)
(*          evil_rand_tape' <-$ { 0 , 1 }^ l eta; *)
(*          ret dst (Type_base BaseType_message) eta (Vector.to_list evil_rand_tape') *)
(*                (interp_term *)
(*                   (fun n : nat => firstn (id eta) (skipn (n * id eta) (Vector.to_list good_rand_tape'))) *)
(*                   (adv eta (Vector.to_list evil_rand_tape')) (Term_random x)) ] - *)
(*      Pr [good_rand_tape' <-$ { 0 , 1 }^ S y * id eta; *)
(*          evil_rand_tape' <-$ { 0 , 1 }^ l eta; *)
(*          ret dst (Type_base BaseType_message) eta (Vector.to_list evil_rand_tape') *)
(*                (interp_term *)
(*                   (fun n : nat => firstn (id eta) (skipn (n * id eta) (Vector.to_list good_rand_tape'))) *)
(*                   (adv eta (Vector.to_list evil_rand_tape')) (Term_random y)) ] |) *)

  (* This probably could be proven in this form -- the argument is that the two subsequences of the good random tape that are given to [dst] are non-overlapping. *)

  
  (* simpl. (* to raw probability equations *) *)
  
(* 2 subgoals, subgoal 1 (ID 141) *)
  
(*   ============================ *)
(*   forall x y : nat, *)
(*   x <> y -> *)
(*   forall l : nat -> nat, *)
(*   (nat -> list bool -> list (list bool) -> list bool) -> *)
(*   forall dst : forall t : type base_type, nat -> list bool -> interp_type interp_base_type t -> bool, *)
(*   negligible *)
(*     (fun eta : nat => *)
(*      | *)
(*      sumList (getAllBvectors (id eta + x * id eta)) *)
(*        (fun b : Bvector (id eta + x * id eta) => *)
(*         1 / expnat 2 (id eta + x * id eta) * *)
(*         sumList (getAllBvectors (l eta)) *)
(*           (fun b0 : Bvector (l eta) => *)
(*            1 / expnat 2 (l eta) * *)
(*            (if *)
(*              EqDec_dec bool_EqDec *)
(*                (dst (Type_base BaseType_message) eta (Vector.to_list b0) *)
(*                   (firstn (id eta) (skipn (x * id eta) (Vector.to_list b)))) true *)
(*             then 1 *)
(*             else 0))) - *)
(*      sumList (getAllBvectors (id eta + y * id eta)) *)
(*        (fun b : Bvector (id eta + y * id eta) => *)
(*         1 / expnat 2 (id eta + y * id eta) * *)
(*         sumList (getAllBvectors (l eta)) *)
(*           (fun b0 : Bvector (l eta) => *)
(*            1 / expnat 2 (l eta) * *)
(*            (if *)
(*              EqDec_dec bool_EqDec *)
(*                (dst (Type_base BaseType_message) eta (Vector.to_list b0) *)
(*                   (firstn (id eta) (skipn (y * id eta) (Vector.to_list b)))) true *)
(*             then 1 *)
(*             else 0))) |) *)