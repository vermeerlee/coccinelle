open Ast_ctl

module type SUBST =
  sig
    type value
    type mvar
    val eq_mvar : mvar -> mvar -> bool
    val eq_val : value -> value -> bool
    val merge_val : value -> value -> value
    val print_mvar : mvar -> unit
    val print_value : value -> unit
  end

module type GRAPH =
  sig 
    type node 
    type cfg 
    val predecessors:     cfg -> node -> node list
    val successors:       cfg -> node -> node list
    val extract_is_loop : cfg -> node -> bool
    val print_node :      node -> unit
    val size :            cfg -> int
  end

module OGRAPHEXT_GRAPH :
  sig
    type node = int
    type cfg = (string, unit) Ograph_extended.ograph_mutable
    val predecessors :
      < predecessors : 'a -> < tolist : ('b * 'c) list; .. >; .. > ->
      'a -> 'b list
    val print_node : node -> unit
  end

module type PREDICATE =
sig
  type t
  val print_predicate : t -> unit
end

module CTL_ENGINE :
  functor (SUB : SUBST) ->
    functor (G : GRAPH) ->
      functor (P : PREDICATE) ->
      sig

	type substitution = (SUB.mvar, SUB.value) Ast_ctl.generic_subst list

	type ('pred,'anno) witness =
	    (G.node, substitution,
	     ('pred, SUB.mvar, 'anno) Ast_ctl.generic_ctl list)
	      Ast_ctl.generic_witnesstree

	type ('pred,'anno) triples =
	    (G.node * substitution * ('pred,'anno) witness list) list

        val sat :
          G.cfg * (P.t -> (P.t,'anno) triples) * G.node list ->
            (P.t, SUB.mvar, 'c) Ast_ctl.generic_ctl ->
	      (P.t list list (* optional and required things *)) ->
		(P.t,'anno) triples

	val print_bench : unit -> unit
      end
