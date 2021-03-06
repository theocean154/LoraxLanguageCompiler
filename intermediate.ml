(* 
 * Authors:
 * Kira Whithouse
 * Chris D'Angelo
 * Special thanks to Dara Hazeghi's strlang and Stephen Edward's MicroC
 * which provided background knowledge.
 *)

open Ast
open Check

let tmp_reg_id = ref 0
let label_id = ref 0

let string_of_tmp_var_type  = function
    Lrx_Atom(t) -> string_of_atom_type t
  | Lrx_Tree(t) -> "tree_datatype_" ^ string_of_atom_type t.datatype ^ "_degree_" ^ string_of_expr t.degree 

let gen_tmp_var t u =
  let x = tmp_reg_id.contents in 
  let prefix = "__tmp_" ^ string_of_tmp_var_type t in 
  tmp_reg_id := x + 1; (prefix, t, x, u)


let gen_tmp_label (s:unit) =
  let x = label_id.contents in
  label_id := x + 1; "__LABEL_" ^ (string_of_int x)

(* == scope_var_decl * int *)
type ir_var_decl = string * var_type * int * int

(* Ir_String_Literal unecessary. Converted to Ir_Tree_Literal here. *)
type ir_expr =
    Ir_Int_Literal of ir_var_decl * int
  | Ir_Float_Literal of ir_var_decl * float
  | Ir_Char_Literal of ir_var_decl * char
  | Ir_Bool_Literal of ir_var_decl * bool
  | Ir_Unop of ir_var_decl * uop * ir_var_decl
  | Ir_Binop of ir_var_decl * op * ir_var_decl * ir_var_decl
  | Ir_Id of ir_var_decl * ir_var_decl
  | Ir_Assign of ir_var_decl * ir_var_decl
  | Ir_Tree_Literal of ir_var_decl * ir_var_decl * ir_var_decl (* 4[3, 2[]]*)
  | Ir_Call of ir_var_decl * scope_func_decl * ir_var_decl list
  | Ir_Null_Literal of ir_var_decl
  | Ir_Noexpr 

type ir_stmt =
  | Ir_If of ir_var_decl * string
  | Ir_Jmp of string
  | Ir_Label of string
  | Ir_Decl of ir_var_decl
  | Ir_Null_Decl of ir_var_decl
  | Ir_Tree_Destroy of ir_var_decl
  | Ir_Tree_Add_Destroy of ir_var_decl
  | Ir_Ret of ir_var_decl * string * string
  | Ir_Expr of ir_expr
  | Ir_Ptr of ir_var_decl * ir_var_decl
  | Ir_At_Ptr of ir_var_decl
  | Ir_Leaf of ir_var_decl * int
  | Ir_Internal of ir_var_decl * int * ir_var_decl
  | Ir_Child_Array of ir_var_decl * int
  | Ir_Decl_Umbilical of ir_var_decl

type ir_func = {
  ir_header: var_type * string * scope_var_decl list;
  ir_vdecls: ir_stmt list;
  ir_stmts: ir_stmt list;
  ir_destroys: ir_stmt list;
}

type ir_fheader = {
  ir_name: string;
  ir_ret_type: var_type;
  ir_formals: var_type list;
}

type ir_program = {
  ir_globals: scope_var_decl list;
  ir_headers: ir_fheader list;
  ir_bodies: ir_func list;
}

let is_destroy (s: ir_stmt) =
  match s with
     (Ir_Tree_Destroy(_) | Ir_Tree_Add_Destroy(_))-> true
   | _ -> false

let is_not_destroy (s:ir_stmt) =
  not (is_destroy s)

let is_decl (s: ir_stmt) =
  match s with
    ( Ir_Decl(_) | Ir_At_Ptr(_) | Ir_Null_Decl(_)) -> true
   | _ -> false

let is_not_decl (s:ir_stmt) =
  not (is_decl s)

let gen_ir_default_ret (t: var_type) =
  let tmp = (gen_tmp_var t 0) in
  let start_cleanup = gen_tmp_label () in 
  let end_cleanup = gen_tmp_label () in 
  [Ir_Decl(tmp); Ir_Ret(tmp, start_cleanup, end_cleanup)]

let is_atom t =
   let (_, t2, _, _) = t in
   match t2 with
      Lrx_Tree(_) -> false
    | _ -> true

let is_tree t = 
    not (is_atom t)

let gen_tmp_internal child tree_type child_number child_array =
  [Ir_Internal(child_array, child_number, child)]

let rec gen_tmp_internals children tree_type array_access child_array = 
 match children with 
    [] -> []
  | head :: tail -> gen_tmp_internal head tree_type array_access child_array @ gen_tmp_internals tail tree_type (array_access + 1) child_array

let gen_tmp_child child tree_type tree_degree =
  if (is_atom child) then 
    let tmp_root_data = (gen_tmp_var tree_type 0) in
    let d = 
    (match tree_type with
        Lrx_Atom(a) -> a
      | Lrx_Tree(t) -> raise(Failure "Tree type as tree data item. (Error 3)")) in 
    let tmp_leaf_children = (gen_tmp_var (Lrx_Tree({datatype = d; degree = Int_Literal(tree_degree)})) 0) in  
    let tmp_leaf_root = (gen_tmp_var (Lrx_Tree({datatype = d; degree = Int_Literal(tree_degree)})) 0) in  
    ([Ir_At_Ptr(tmp_root_data);
      Ir_Ptr(tmp_root_data, child); 
      Ir_Leaf(tmp_leaf_children, tree_degree); 
      Ir_Decl(tmp_leaf_root); 
      Ir_Tree_Destroy(tmp_leaf_root);
      Ir_Expr(Ir_Tree_Literal(tmp_leaf_root, tmp_root_data, tmp_leaf_children))], tmp_leaf_root)
  else
    ([], child)

let rec gen_tmp_children children tree_type tree_degree =
  match children with 
  [] -> []
 | head :: tail -> gen_tmp_child head tree_type tree_degree :: gen_tmp_children tail tree_type tree_degree

let gen_tmp_tree tree_type tree_degree root children_list tmp_tree =
  let children = gen_tmp_children children_list tree_type tree_degree in
  let (decls, tmp_children) = (List.fold_left (fun (a, b) (c, d) -> ((c @ a), (d :: b))) ([],[]) (List.rev children)) in
  let d = 
  (match tree_type with
      Lrx_Atom(a) -> a
    | Lrx_Tree(t) -> raise(Failure "Tree type as tree data item. (Error 1)")) in 
  let child_array = gen_tmp_var (Lrx_Tree({datatype = d; degree = Int_Literal(tree_degree)})) 0 in  
  let internals = gen_tmp_internals tmp_children tree_type 0 child_array in
  let tmp_root_ptr = gen_tmp_var tree_type 0 in
  decls @ [Ir_Child_Array(child_array, tree_degree)] @ internals @ [Ir_At_Ptr(tmp_root_ptr); Ir_Ptr(tmp_root_ptr, root)] @ [Ir_Expr(Ir_Tree_Literal(tmp_tree, tmp_root_ptr, child_array))]

let rec char_list_to_c_tree cl =
    match cl with
       [t] -> C_Tree(Lrx_Atom(Lrx_Char), 1, C_Char_Literal(t), []) 
     | h :: t -> 
       if h = '\\' then
          let h2 = (List.hd t) in
          let escape_char = 
          match h2 with
             'n' -> '\n'
           | 't' -> '\t'
           | '\\' -> '\\'
           | _ -> raise (Failure "Invalid escape sequence used in string literal") in
          if (List.length (List.tl t)) = 0 then C_Tree(Lrx_Atom(Lrx_Char), 1, C_Char_Literal(escape_char), [])
          else C_Tree(Lrx_Atom(Lrx_Char), 1, C_Char_Literal(escape_char), [(char_list_to_c_tree (List.tl t))])
       else
          C_Tree(Lrx_Atom(Lrx_Char), 1, C_Char_Literal(h), [(char_list_to_c_tree t)])
     | _ -> raise (Failure "Cannot create an empty string literal")

let string_to_char_list s =
  let rec exp i l = if i < 0 then l else exp (i - 1) (s.[i] :: l) in
  exp (String.length s - 1) []

let rec gen_ir_expr_list (el:c_expr list) (args:scope_var_decl list) =
  match el with 
  [] -> []
  | head :: tail -> gen_ir_expr head args :: gen_ir_expr_list tail args

and gen_ir_expr (e:c_expr) (args:scope_var_decl list) =
  match e with
     C_Int_Literal(i) ->
     let tmp = gen_tmp_var (Lrx_Atom(Lrx_Int)) 0 in
     ([Ir_Decl(tmp); Ir_Expr(Ir_Int_Literal(tmp, i))], tmp)
   | C_Float_Literal(f) -> 
     let tmp = gen_tmp_var (Lrx_Atom(Lrx_Float)) 0 in
     ([Ir_Decl(tmp); Ir_Expr(Ir_Float_Literal(tmp, f))], tmp)
   | C_Char_Literal(c) ->
     let tmp = gen_tmp_var (Lrx_Atom(Lrx_Char)) 0 in
     ([Ir_Decl(tmp); Ir_Expr(Ir_Char_Literal(tmp, c))], tmp) 
   | C_Bool_Literal(b) -> 
     let tmp = gen_tmp_var (Lrx_Atom(Lrx_Bool)) 0 in
     ([Ir_Decl(tmp); Ir_Expr(Ir_Bool_Literal(tmp, b))], tmp)
   | C_Unop(v, e, o) ->
     let (s, r) = gen_ir_expr e args in
     (match o with
         Pop -> raise (Failure "TEMPORARY: Pop not implemented.")
       | At -> let tmp = gen_tmp_var v 1 in ([Ir_At_Ptr(tmp)] @ s @ [Ir_Expr(Ir_Unop(tmp, o, r))], tmp)
       | _ -> let tmp = gen_tmp_var v 0 in ([Ir_Decl(tmp)] @ s @ [Ir_Expr(Ir_Unop(tmp, o, r))], tmp))
   | C_Binop(v, e1, o, e2) -> 
     let (s1, r1) = gen_ir_expr e1 args in
     let (s2, r2) = gen_ir_expr e2 args in
    let tmp = 
       (match o with 
           Child -> gen_tmp_var v 1 
         | _ -> gen_tmp_var v 0 ) 
     in (match (v, o) with 
            (Lrx_Tree(t), Add) -> ([Ir_Decl(tmp); Ir_Tree_Add_Destroy(tmp)] @ s1 @ s2 @ [Ir_Expr(Ir_Binop(tmp, o, r1, r2))], tmp)
          | _ -> ([Ir_Decl(tmp)] @ s1 @ s2 @ [Ir_Expr(Ir_Binop(tmp, o, r1, r2))], tmp))
   | C_Id(t, s, i) -> 
      (match t with
      Lrx_Tree(_) -> if (List.exists (fun (s1, t1, i1) -> (s1 = s && t1 = t && i1 = i)) args) then ([], (s, t, i, 3)) else ([], (s, t, i, 0))
      | _ -> ([], (s, t, i, 0)))
   | C_Assign(t, l, r) ->
     let (s1, r1) = gen_ir_expr l args in
     let (s2, r2) = gen_ir_expr r args in
     (s1 @ s2 @ [Ir_Expr(Ir_Assign(r1, r2))], r2)
   | C_Tree(t, d, e, el) -> 
     let (s, r) = gen_ir_expr e args in
     let ir_el = gen_ir_expr_list el args in
     let (sl, rl) = (List.fold_left (fun (sl_ir, rl_ir) (s_ir, r_ir) -> (sl_ir @ s_ir, rl_ir@[r_ir])) ([],[]) ir_el) in 
     let i  =
     (match t with
         Lrx_Atom(a) -> a
       | Lrx_Tree(t) -> raise (Failure "Tree type as tree data item. (Error 2)")) in 
     let tmp = (gen_tmp_var (Lrx_Tree({datatype = i; degree = Int_Literal(d)})) 0) in
     let tmp_tree =  gen_tmp_tree t d r rl tmp in 
     ([Ir_Decl(tmp); Ir_Tree_Destroy(tmp)] @ sl @ s @ tmp_tree, tmp)
   | C_Call(fd, el) ->
     let (n, rt, fm, s) = fd in 
     let ir_el = gen_ir_expr_list el args in 
     let tmp = 
     (match n with 
         ("parent" | "root") -> gen_tmp_var rt 1
       | _ -> gen_tmp_var rt 0) 
     in
     let (sl, rl) = (List.fold_left (fun (sl_ir, rl_ir) (s_ir, r_ir) -> (sl_ir @ s_ir, rl_ir@[r_ir])) ([],[]) ir_el) in 
     (Ir_Decl(tmp) :: sl @ [Ir_Expr(Ir_Call(tmp, fd, rl))], tmp)
   | C_String_Literal(s) -> let result = (char_list_to_c_tree (string_to_char_list s)) in
     gen_ir_expr result args
   | C_Null_Literal -> let tmp = (gen_tmp_var (Lrx_Tree({datatype = Lrx_Int; degree = Int_Literal(1)})) 2) in 
     ([Ir_Null_Decl(tmp); Ir_Expr(Ir_Null_Literal(tmp))], tmp)
   | C_Noexpr -> ([Ir_Expr(Ir_Noexpr)], ("void_tmp_unused", Lrx_Atom(Lrx_Int), -1, -1))

let decl_and_destroy_local (v:scope_var_decl) =
  let (n, t, s) = v in 
  (match t with
      Lrx_Tree(_) -> [Ir_Tree_Destroy(n, t, s, 0); Ir_Decl(n, t, s, 0)]
    | _ -> [Ir_Decl(n, t, s, 0)])

let rec decl_and_destroy_locals (vl:scope_var_decl list) =
  match vl with
     [] -> []
   | head :: tail -> decl_and_destroy_local head @ decl_and_destroy_locals tail 

let rec gen_ir_block (b: c_block) (args:scope_var_decl list) =
  let decls = decl_and_destroy_locals b.c_locals in
  decls @ (gen_ir_stmtlist b.c_statements args)

and gen_ir_stmt (s: c_stmt) (args:scope_var_decl list) =
   match s with
      C_CodeBlock(b) -> gen_ir_block b args
    | C_Return(e) -> 
      let (s, r) = gen_ir_expr e args in 
      let start_cleanup = gen_tmp_label () in 
      let end_cleanup = gen_tmp_label () in 
    s @ [Ir_Ret(r, start_cleanup, end_cleanup)]
    | C_Expr(e) -> fst (gen_ir_expr e args)
    | C_If(e, b1, b2) -> 
      let (s, r) = gen_ir_expr e args in 
      let irb1 = gen_ir_block b1 args in
      let irb2 = gen_ir_block b2 args in
      let startlabel = gen_tmp_label () in
      let endlabel = gen_tmp_label () in
      s @ [Ir_If(r, startlabel)] @ irb2 @ [Ir_Jmp(endlabel); Ir_Label(startlabel)] @ irb1 @ [Ir_Label(endlabel)]
    | C_For(e1, e2, e3, b) -> 
      let (s1, r1) = gen_ir_expr e1 args in 
      let (s2, r2) = gen_ir_expr e2 args in 
      let (s3, r3) = gen_ir_expr e3 args in 
      let irb = gen_ir_block b args in
      let startlabel = gen_tmp_label () in
      let endlabel = gen_tmp_label () in
      s1 @ [Ir_Jmp(endlabel); Ir_Label(startlabel)] @ irb @ s3 @ [Ir_Label(endlabel)] @ s2 @ [Ir_If(r2, startlabel)]
    | C_While(e, b) -> 
      let (s, r) = gen_ir_expr e args in 
      let irb = gen_ir_block b args in
      let startlabel = gen_tmp_label () in
      let endlabel = gen_tmp_label () in
      [Ir_Jmp(endlabel); Ir_Label(startlabel)] @ irb @ [Ir_Label(endlabel)] @ s @ [Ir_If(r, startlabel)]
    | C_Continue -> raise (Failure "TEMPORARY: Continue not implemented.")
    | C_Break -> raise (Failure "TEMPORARY: Break not implemented.")

and gen_ir_stmtlist (slist: c_stmt list) (args:scope_var_decl list) = 
  match slist with
     [] -> []
   | head :: tail -> gen_ir_stmt head args @ gen_ir_stmtlist tail args

and gen_ir_body (f: c_func) =
  let header = (f.c_ret_type, f.c_fname, f.c_formals) in
  let default_ret = gen_ir_default_ret f.c_ret_type in
  let body = gen_ir_block f.c_fblock f.c_formals @ default_ret in
  let decls = List.filter is_decl body in
  let stmts = List.filter is_not_decl body in
  let destroys = List.filter is_destroy stmts in
  let stmts = List.filter is_not_destroy stmts in 
  {ir_header = header; ir_vdecls = decls; ir_stmts = stmts; ir_destroys = destroys}

and gen_ir_fbodys (flist:c_func list) =
  match flist with
     [] -> []
   | head :: tail -> gen_ir_body head :: gen_ir_fbodys tail

and gen_ir_fdecls (flist:c_func list) = 
  match flist with
     [] -> []
   | head :: tail -> 
  {ir_name = head.c_fname; ir_ret_type = head.c_ret_type; ir_formals = List.map snd_of_three head.c_formals} :: gen_ir_fdecls tail

let rec intermediate_rep_program (p:c_program) =
  let ir_fdecls = gen_ir_fdecls (snd p) in 
  let ir_fbodys = gen_ir_fbodys (snd p) in 
  {ir_globals = fst p; ir_headers = ir_fdecls; ir_bodies = ir_fbodys}