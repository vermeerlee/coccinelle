open Common open Commonop

open Ograph_extended

let (-->) x v = Ast_ctl.Subst (x,v);;


(*****************************************************************************)

(* Take list of pred  and for each pred return where in control flow
 * it matches (and the set of subsitutions for this match). 
 *)
let (labels_for_ctl: 
 (nodei * Control_flow_c.node) list -> Lib_engine.metavars_binding -> 
 Lib_engine.label_ctlcocci) =
  fun nodes binding ->

   (fun pred -> 

     if !Flag_engine.debug_engine
     then begin 
       pp_init (fun () -> 
         pp "labeling: pred =";
         Format.print_space ();
         Pretty_print_engine.pp_predicate pred;
         );
     end;

     let nodes' = nodes +> map (fun (nodei, node) -> 
      (* todo? put part of this code in pattern ? *)
      (match pred, Control_flow_c.unwrap node with
      | Lib_engine.Paren s,  (Control_flow_c.SeqStart (_, bracelevel, _)) -> 
         [(nodei,     [(s --> (Lib_engine.ParenVal (i_to_s bracelevel)))])]
      | Lib_engine.Paren s,  (Control_flow_c.SeqEnd (bracelevel, _)) -> 
          [(nodei,    [(s --> (Lib_engine.ParenVal (i_to_s bracelevel)))])]
      | Lib_engine.Paren _, _ -> []

      | Lib_engine.Label s, _ -> 
          let labels = Control_flow_c.extract_labels node in
          [(nodei, [(s --> (Lib_engine.LabelVal labels))])]
      | Lib_engine.PrefixLabel s, _ -> 
          let labels = Control_flow_c.extract_labels node in
          let prefixes = Common.inits labels +> Common.tail in
          prefixes +> List.map (fun prefixlabels -> 
            (nodei, [(s --> (Lib_engine.LabelVal prefixlabels))])
          )
          

      | Lib_engine.Match (re), _unwrapnode -> 
          let substs = Pattern.match_re_node re node binding
              (* old: Ast_c.emptyMetavarsBinding *)
          in
          if substs <> []
          then
            substs +> List.map (fun subst -> 
              (nodei, 
               subst +> List.map (fun (s, meta) -> 
                 s --> Lib_engine.NormalMetaVal meta
                 )
              )
             )
          else []

      | Lib_engine.TrueBranch , Control_flow_c.TrueNode ->  [nodei, []]
      | Lib_engine.FalseBranch, Control_flow_c.FalseNode -> [nodei, []]
      | Lib_engine.After,       Control_flow_c.AfterNode -> [nodei, []]
      | Lib_engine.FallThrough, Control_flow_c.FallThroughNode -> [nodei, []]
      | Lib_engine.Exit,        Control_flow_c.Exit ->      [nodei, []]
      | Lib_engine.ErrorExit,   Control_flow_c.ErrorExit -> [nodei, []]

      | Lib_engine.TrueBranch , _ -> []
      | Lib_engine.FalseBranch, _ -> []
      | Lib_engine.After, _ -> []
      | Lib_engine.FallThrough, _ -> []
      | Lib_engine.Exit, _  -> []
      | Lib_engine.ErrorExit, _  -> []

      | Lib_engine.Include _, _  -> failwith "include should not be checked"

      | Lib_engine.Return, node -> 
          (match node with
            (* todo? should match the Exit code ? 
             * todo: one day try also to match the special function
             * such as panic(); 
             *)
          | Control_flow_c.Return _ ->  [nodei, []]
          | Control_flow_c.ReturnExpr _ -> [nodei, []]
          | _ -> []
          )
      )
                               ) +> List.concat
     in
     if !Flag_engine.debug_engine
     then begin 
       pp_init (fun () -> 
         pp "labeling: result =";
         Format.print_space ();
         
         pp_do_in_box (fun () -> 
           pp "{";
           Common.print_between 
             (fun () -> pp ";"; Format.print_cut())
             (fun (nodei, subst) -> 
               Format.print_int nodei;
               pp_do_in_box (fun () -> 
                 Pretty_print_engine.pp_binding2_ctlsubst subst
                 )
             ) nodes';
           pp "}";
                      );
               )
     end;
     nodes'
   ) 




let (control_flow_for_ctl: Control_flow_c.cflow -> ('a, 'b) ograph_extended) = 
 fun cflow ->
 (* could erase info on nodes, and edge,  because they are not used by rene *)
  cflow



(* Just make the final node of the control flow loop over itself. 
 * It seems that one hypothesis of the SAT algorithm is that each node as at
 * least a successor.
 * update: do same for errorexit node.
 * 
 * Addon: also erase the fake nodes (and adjust the edges accordingly), so that
 * AX in CTL can now work.
 * Indeed, � la fin de la branche then (et else), on devrait aller directement
 * au suivant du endif, sinon si ecrit if(1) { foo(); }; bar();
 * sans '...' entre le if et bar(), alors ca matchera pas car le CTL
 * generera un AX bar()  qui il tombera d'abord sur le [endif] :( 
 * Mais chiant de changer l'algo de generation, marche pas tres bien avec 
 * ma facon de faire recursive et compositionnel.
 * => faire une fonction qui applique des fixes autour de ce control flow,
 * comme ca passe un bon flow a rene, mais garde un flow a moi pour pouvoir 
 * facilement generate back the ast.
 *
 * alt: faire un wrapper autourde mon graphe pour lui passer dans le module CFG
 * une fonction qui passe a travers les Fake, mais bof.
 *)
let (fix_flow_ctl: Control_flow_c.cflow -> Control_flow_c.cflow) = fun  flow ->
  let g = ref flow in

  let adjust_g (newg)        = begin  g := newg;    end in
  let adjust_g_i (newg,newi) = begin  g := newg;   newi end in

  let find_node f = 
    !g#nodes#tolist 
     +> List.find (fun (nodei, node) -> f (Control_flow_c.unwrap node)) 
     +> fst
  in

  (* note that must choose a kind that will not be deleted after *)
  let topi = !g#add_node ((Control_flow_c.Fake, []), "start") +> adjust_g_i
  in
  let enteri = 
    find_node (function Control_flow_c.FunHeader _ -> true | _ -> false)
  in
  let exitnodei  = find_node (fun x -> x = Control_flow_c.Exit) in
  let errornodei = find_node (fun x -> x = Control_flow_c.ErrorExit) in


  !g#add_arc ((topi, topi), Control_flow_c.Direct) +> adjust_g;
  !g#add_arc ((topi, enteri), Control_flow_c.Direct) +> adjust_g;
  !g#add_arc ((exitnodei, exitnodei), Control_flow_c.Direct) +> adjust_g;

  if null ((!g#successors   errornodei)#tolist) &&
     null ((!g#predecessors errornodei)#tolist)
  then
    !g#del_node errornodei +> adjust_g
  else 
    !g#add_arc ((errornodei, errornodei), Control_flow_c.Direct) +> adjust_g;

  let remove_one_node nodei = 
    let preds = (!g#predecessors nodei)#tolist in
    let succs = (!g#successors nodei)#tolist in

    assert (not (null preds));

    preds +> List.iter (fun (predi, Control_flow_c.Direct) -> 
      !g#del_arc ((predi, nodei), Control_flow_c.Direct) +> adjust_g;
      );

    succs +> List.iter (fun (succi, Control_flow_c.Direct) -> 
      !g#del_arc ((nodei, succi), Control_flow_c.Direct) +> adjust_g;
      );
    
    !g#del_node nodei +> adjust_g;

    preds +> List.iter (fun (pred, Control_flow_c.Direct) -> 
      succs +> List.iter (fun (succ, Control_flow_c.Direct) -> 
        !g#add_arc ((pred, succ), Control_flow_c.Direct) +> adjust_g;
        );
      );
    
  in
  let fake_nodes = !g#nodes#tolist +> List.filter (fun (nodei, node) -> 
    match Control_flow_c.unwrap node with
    | Control_flow_c.CaseNode _ 
    | Control_flow_c.Enter
    (*| Control_flow_c.Fake*) (* [endif], [endswitch], ... *)
      -> true
    | _ -> false 
    ) in
  
  fake_nodes +> List.iter (fun (nodei, node) -> remove_one_node nodei);


  !g#nodes#tolist +> List.iter (fun (nodei, node) -> 
    assert (List.length ((!g#successors nodei)#tolist) >= 1); 
    (* no:  && List.length ((!g#predecessors nodei)#tolist) >= 1  
       because    the enter node at least have no predecessors *)
    );

  !g



let model_for_ctl  cflow binding = 
 let newflow = fix_flow_ctl (control_flow_for_ctl cflow) in
 (* subtil: the label must operate on newflow, not (old) cflow. *)
 let labels = labels_for_ctl (newflow#nodes#tolist) binding  in
 let states = List.map fst  newflow#nodes#tolist  in
 newflow, labels, states
 

(******************************************************************************)
module PRED = 
  struct
    type t = Lib_engine.predicate
    let print_predicate x = 
      Pretty_print_cocci.print_plus_flag := false;
      Pretty_print_cocci.print_minus_flag := false;
      Pretty_print_engine.pp_predicate x
  end

module ENV =
  struct
    type value = Lib_engine.metavar_binding_kind2
    type mvar = string
    let eq_mvar x x' = x = x'
    let eq_val v v' = v = v'
    let merge_val v v' = v	       

    let print_mvar s = Format.print_string s
    let print_value x = Pretty_print_engine.pp_binding_kind2 x
  end


module CFG = 
  struct
    type node = int
    type cfg = 
        (Control_flow_c.node, Control_flow_c.edge) 
        Ograph_extended.ograph_extended
    let predecessors cfg n = List.map fst ((cfg#predecessors n)#tolist)
    let successors   cfg n = List.map fst ((cfg#successors n)#tolist)
    let print_node i = Format.print_string (i_to_s i)
  end


module WRAPPED_ENGINE = Wrapper_ctl.CTL_ENGINE_BIS (ENV) (CFG) (PRED)


(*****************************************************************************)

let print_bench _ = WRAPPED_ENGINE.print_bench()

type pred = Lib_engine.predicate * string Ast_ctl.modif

let (mysat:
       (Control_flow_c.cflow *
        Lib_engine.label_ctlcocci *
        nodei list) -> 
       (Lib_engine.ctlcocci * (pred list * pred list)) -> 
       (Lib_engine.mvar list * Lib_engine.metavars_binding2) ->
	 ((nodei * Lib_engine.metavars_binding2 * Lib_engine.predicate) list *
	    bool *
	    Lib_engine.metavars_binding2,
	  string) either) = 
  fun (flow, label, states) ctl (used_after, binding2) -> 
    WRAPPED_ENGINE.satbis (flow, label, states) ctl (used_after, binding2)


let (satbis_to_trans_info: 
  (nodei * 
   (Lib_engine.mvar * Lib_engine.metavar_binding_kind2) list *  
   Lib_engine.predicate) 
  list -> 
  (nodei * Lib_engine.metavars_binding * Ast_cocci.rule_elem) list) = 
  fun xs -> 
    xs +> List.map (fun (nodei, binding, pred) -> 
         let binding' = binding +> map_filter (fun (s, kind2) -> 
             (match kind2 with
             | Lib_engine.NormalMetaVal kind -> Some (s, kind)
             (* I thought it was Impossible, but it does not seems so *)
             | Lib_engine.ParenVal _ -> None
             | Lib_engine.LabelVal _ -> None
             )
           ) in
         let pred' = 
           (match pred with
           | Lib_engine.Match rule_elem -> rule_elem
           | _ -> raise Impossible
           ) in
         
         nodei, binding', pred'
         )


let metavars_binding2_to_binding   binding2 = 
  binding2 +> map_filter (fun (s, kind2) -> 
    match kind2 with
    | Lib_engine.NormalMetaVal kind -> Some (s, kind)
    | Lib_engine.ParenVal _ -> None
    | Lib_engine.LabelVal _ -> None
   )

let metavars_binding_to_binding2 binding = 
  binding +> List.map (fun (s, kind) -> s, Lib_engine.NormalMetaVal kind)

