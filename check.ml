(* 
 * Authors:
 * Chris D'Angelo
 * Kira Whitehouse
 * Special thanks to Dara Hazeghi's strlang which provided background knowledge.
 *)

open Ast

let fst_of_three (t, _, _) = t
let snd_of_three (_, t, _) = t
let fst_of_four (t, _, _, _) = t

(*expressions from Ast but with typing added*)
type c_expr =
    C_Int_Literal of int
  | C_Float_Literal of float
  | C_String_Literal of string
  | C_Char_Literal of char
  | C_Bool_Literal of bool
  | C_Null_Literal
  | C_Id of var_type * string * int
  | C_Binop of var_type * c_expr * op * c_expr
  | C_Unop of var_type * c_expr * uop
  | C_Tree of var_type * int * c_expr * c_expr list
  | C_Assign of var_type * c_expr * c_expr
  | C_Call of scope_func_decl * c_expr list
  | C_Noexpr

(*statements from Ast but with typing added*)
type c_stmt =
    C_CodeBlock of c_block
  | C_Expr of c_expr
  | C_Return of c_expr
  | C_If of c_expr * c_block * c_block
  | C_For of c_expr * c_expr * c_expr * c_block
  | C_While of c_expr * c_block
  | C_Continue
  | C_Break

(* tree declaration from Ast but with typing added *)
and c_tree_decl = {
    c_datatype: atom_type;
    c_degree: c_expr;
} 

and c_block = {
    c_locals : scope_var_decl list;
    c_statements: c_stmt list;
    c_block_id: int;
}

type c_func = { 
    c_fname : string;
    c_ret_type : var_type;
    c_formals : scope_var_decl list;
    c_fblock : c_block;
}

type c_program = scope_var_decl list * c_func list

(* structures the 'main' function *)
let main_fdecl (f:c_func) =
  if f.c_fname = "main" && f.c_ret_type = Lrx_Atom(Lrx_Int) && f.c_formals = [] 
        then true else false

(*called to get the Atom/Tree type of an expresion*)
let type_of_expr = function
    C_Int_Literal(i) -> Lrx_Atom(Lrx_Int)
  | C_Float_Literal(f) -> Lrx_Atom(Lrx_Float)
  | C_String_Literal(s) -> Lrx_Tree({datatype = Lrx_Char; degree = Int_Literal(1)})
  | C_Char_Literal(c) -> Lrx_Atom(Lrx_Char)
  | C_Bool_Literal(b) -> Lrx_Atom(Lrx_Bool)
  | C_Binop(t,_,_,_) -> t
  | C_Unop(t,_,_) -> t 
  | C_Id(t,_,_) -> t
  | C_Assign(t,_,_) -> t
  | C_Tree(t, d, _, _) -> 
    (match t with
        Lrx_Atom(t) -> Lrx_Tree({datatype = t; degree = Int_Literal(d)})
      | _ -> raise (Failure "Tree type must be Lrx_atom"))
  | C_Call(f,_) -> let (_,r,_,_) = f in r
  | (C_Noexpr | C_Null_Literal) -> raise (Failure("Type of expression called on Null_Literal or Noexpr"))

(* error raised for improper binary operation *)
let binop_error (t1:var_type) (t2:var_type) (op:op) =
  raise(Failure("operator " ^ (string_of_binop op) ^ " not compatible with expressions of type " ^
    (string_of_var_type t1) ^ " and " ^ (string_of_var_type t2)))


(* check binary operators *)
let check_binop (c1:c_expr) (c2:c_expr) (op:op) =
  match (c1, c2) with
      (C_Null_Literal, C_Null_Literal) -> 
      (match op with
          (Equal | Neq) -> C_Binop(Lrx_Atom(Lrx_Bool), c1, op, c2)
        | _ -> raise (Failure ("operator " ^ string_of_binop op ^ " not compatible with types null and null")))
    | ((C_Null_Literal, t) | (t, C_Null_Literal)) ->
      (match (type_of_expr t) with
          Lrx_Tree(l) ->
          (match op with
              (Equal | Neq) -> C_Binop(Lrx_Atom(Lrx_Bool), c1, op, c2)
            | _ -> raise (Failure ("operator " ^ string_of_binop op ^ " not compatible with types null and tree")))
        | _ -> raise (Failure ("null cannot be compared with non-tree type")))
    | _ ->
    let (t1, t2) = (type_of_expr c1, type_of_expr c2) in
    match (t1, t2) with 
       (Lrx_Atom(Lrx_Int), Lrx_Atom(Lrx_Int)) ->
       (match op with
           (Add | Sub | Mult | Div | Mod) -> C_Binop(Lrx_Atom(Lrx_Int), c1, op, c2)
         | (Equal | Neq | Less | Leq | Greater | Geq) -> C_Binop(Lrx_Atom(Lrx_Bool), c1, op, c2)
         | _ -> binop_error t1 t2 op)
     | (Lrx_Atom(Lrx_Float), Lrx_Atom(Lrx_Float)) ->
       (match op with
           (Add | Sub | Mult | Div) ->   C_Binop(Lrx_Atom(Lrx_Float), c1, op, c2)
         | (Equal | Neq | Less | Leq | Greater | Geq) -> C_Binop(Lrx_Atom(Lrx_Bool), c1, op, c2)
         | _ -> binop_error t1 t2 op)
     | (Lrx_Atom(Lrx_Bool), Lrx_Atom(Lrx_Bool)) ->
       (match op with
           (And | Or | Equal | Neq) -> 
               C_Binop(Lrx_Atom(Lrx_Bool), c1, op, c2)
             | _ -> binop_error t1 t2 op)
     | (Lrx_Atom(Lrx_Char), Lrx_Atom(Lrx_Char)) ->
       (match op with
           (Add | Sub) -> C_Binop(Lrx_Atom(Lrx_Char), c1, op, c2)
         | (Equal | Neq | Less | Leq | Greater | Geq) -> C_Binop(Lrx_Atom(Lrx_Bool), c1, op, c2)
         | _ -> binop_error t1 t2 op)
     | (Lrx_Tree(t), Lrx_Atom(Lrx_Int)) ->
          (if op = Child then
            C_Binop(Lrx_Tree(t), c1, op, c2)
          else binop_error t1 t2 op) 
     | (Lrx_Tree(l1), Lrx_Tree(l2)) ->
          (match op with
              Add -> if l1.datatype = l2.datatype then C_Binop(Lrx_Tree(l1), c1, op, c2)
              else raise (Failure ("Cannot add type " ^ string_of_var_type t1 ^ " with type " ^ string_of_var_type t2))
            | (Equal | Neq) -> if l1.datatype = l2.datatype then C_Binop(Lrx_Atom(Lrx_Bool), c1, op, c2) 
              else ((prerr_string ("Warning: comparison of " ^ string_of_var_type t1 ^ " with type " ^ string_of_var_type t2))
                ; C_Binop(Lrx_Atom(Lrx_Bool), c1, op, c2))
            | (Less | Greater | Leq | Geq) -> C_Binop(Lrx_Atom(Lrx_Bool), c1, op, c2)
            | _ -> binop_error t1 t2 op)
     | _ -> binop_error t1 t2 op 

                

let unop_error (t:var_type) (op:Ast.uop) =
  raise(Failure("operator " ^ (string_of_unop op) ^ " not compatible with expression of type " ^ (string_of_var_type t)))
                 
let check_unop (c:c_expr) (op:Ast.uop) = 
  let te = type_of_expr c in
  match te with
     Lrx_Atom(Lrx_Int) ->
     (match op with
         Neg -> C_Unop(Lrx_Atom(Lrx_Int), c, op)
       | _ -> unop_error te op)
   | Lrx_Atom(Lrx_Float) ->
     (match op with
         Neg -> C_Unop(Lrx_Atom(Lrx_Float), c, op)
       | _ -> unop_error te op)
   | Lrx_Atom(Lrx_Bool) ->
     (match op with
         Not -> C_Unop(Lrx_Atom(Lrx_Bool), c, op)
       | _ -> unop_error te op)
   | Lrx_Tree(t) ->
     (match op with
         Pop -> C_Unop(Lrx_Tree(t), c, op)
       | At -> C_Unop(Lrx_Atom(t.datatype), c, op)
       | _ -> unop_error te op)
   | _ -> unop_error te op  
                      
(*compares argument list*)
let rec compare_arglists formals actuals =
	match (formals,actuals) with
	   ([],[]) -> true
	 | (head1::tail1, head2::tail2) -> 
     (match (head1, head2) with
         (Lrx_Tree(t1), Lrx_Tree(t2)) -> (t1.datatype = t2.datatype) && compare_arglists tail1 tail2
       | _ -> (head1 = head2) && compare_arglists tail1 tail2)
	 | _ -> false

(*checks that a function declaration and calling is proper, such that a function is called with the proper number and type of arguments*)
and check_fun_call (name:string) (cl:c_expr list) env =
  (*if name == print, match type with symtab print_type*)
	let decl = Symtab.symtab_find name env in
	let fdecl = 
  (match decl with 
      SymTab_FuncDecl(f) -> f
		| _ -> raise(Failure("symbol " ^ name ^ " is not a function"))) in
      let (fname,ret_type,formals,id) = fdecl in
      let actuals = List.map type_of_expr cl in
      match name with
         "print" -> C_Call((fname, ret_type, actuals, id), cl)
       | ("degree" | "root" | "parent") -> 
         if ((List.length actuals) = 1) then
           let tree_arg = List.hd actuals in 
           match tree_arg with
              Lrx_Tree(t) -> 
              if name = "degree" then C_Call((fname, ret_type, actuals, id), cl)
              else C_Call((fname, tree_arg, actuals, id), cl)
            | _ -> raise(Failure("function degree expects tree"))
        else raise(Failure("function " ^ name ^ " expects a single tree as an argument"))
      | _ ->
  	    if (List.length formals) = (List.length actuals) then
		      if compare_arglists formals actuals then C_Call(fdecl, cl)
		      else raise(Failure("function " ^ name ^ "'s argument types don't match its formals"))
	      else raise(Failure("function " ^ name ^ " expected " ^ (string_of_int (List.length actuals)) ^
		    " arguments but called with " ^ (string_of_int (List.length formals)))) 

let rec check_id_is_valid (id_name:string) env = 
     let decl = Symtab.symtab_find id_name env in
     let id = Symtab.symtab_get_id id_name env in
     (match decl with 
         SymTab_VarDecl(v) -> (snd_of_three v, fst_of_three v, id)
       | _ -> raise (Failure("symbol " ^ id_name ^ " is not a variable")))

and extract_l_value (l:c_expr) env =
    match l with
       C_Id(t,s,_) -> s
     | C_Binop(t,l,o,r) -> extract_l_value l env 
     | C_Unop(t,l,o) -> extract_l_value l env
     | _ -> raise (Failure ("Cannot dereference expression without id"))

and check_l_value (l:expr) env =
    match l with
       Id(s) -> let (t, e, id) = check_id_is_valid s env in C_Id(t,e, id)
     | _ -> let ce = (check_expr l env) in
       match ce with 
          C_Binop(_,_,op,_) -> 
          (if op = Child then
            (let s = (extract_l_value ce env) in 
            let (t, e, _) = check_id_is_valid s env in
            ignore t; ignore e; ce)
           else raise (Failure ("Left hand side of assignment operator is improper type")))
         | C_Unop(_,_,op) -> 
           (if op = At then
              (let s = (extract_l_value ce env) in 
              ignore (check_id_is_valid s env); ce)
           else raise (Failure ("Left hand side of assignment operator is improper type")))
         | _ -> raise (Failure ("Left hand side of assignment operator is improper type"))

 and check_tree_literal_is_valid (d:int) (t:var_type) (el:expr list) env =
     match el with
        [] -> []
      | head :: tail -> 
        let checked_expr = check_expr head env in
        match checked_expr with
           C_Tree(tree_type, tree_degree, child_e, child_el) -> 
           if (tree_degree = d || tree_degree = 0) && tree_type = t then
             C_Tree(tree_type, d, child_e, child_el) :: check_tree_literal_is_valid d t tail env
           else raise (Failure ("Tree type is not consistent: expected <" ^ string_of_var_type t ^ ">(" ^ string_of_int d ^ ") but received <" ^ string_of_var_type tree_type ^ ">(" ^ string_of_int tree_degree ^ ")"))  
         | _ ->
           let child_type = (type_of_expr checked_expr) in
           if child_type = t then
             checked_expr :: check_tree_literal_is_valid d t tail env
           else raise (Failure ("Tree literal type is not consistent: expected <" ^ string_of_var_type t ^ "> but received <" ^ string_of_var_type child_type ^">"))

and check_tree_literal_root_is_valid (e:expr) (el: expr list) env =
  let checked_root = check_expr e env in
  let type_root = type_of_expr checked_root in
  match type_root with
     (Lrx_Atom(Lrx_Int) | Lrx_Atom(Lrx_Float) | Lrx_Atom(Lrx_Char) | Lrx_Atom(Lrx_Bool)) ->
     let degree_root = List.length el in
     let checked_tree = check_tree_literal_is_valid degree_root type_root el env in
     (type_root, degree_root, checked_root, checked_tree)
   | _ -> raise (Failure ("Tree root cannot be of non-atom type: " ^ string_of_var_type type_root))

and check_expr (e:expr) env =
	  match e with
       Int_Literal(i) -> C_Int_Literal(i)
     | Float_Literal(f) -> C_Float_Literal(f)
     | String_Literal(s) -> C_String_Literal(s)
     | Char_Literal(c) -> C_Char_Literal(c)
     | Bool_Literal(b) -> C_Bool_Literal(b)
     | Tree(e, el) -> let (t, d, e, el) = check_tree_literal_root_is_valid e el env in 
          C_Tree(t, d, e, el)
     | Id(s) -> let (t, e, id) = check_id_is_valid s env in
          C_Id(t,e, id)
     | Binop(e1, op, e2) ->
       let (c1, c2) = (check_expr e1 env, check_expr e2 env) in
        check_binop c1 c2 op (* returns C_Binop *)
     | Assign(l, r) ->
       let checked_r = check_expr r env in
       let checked_l = check_l_value l env in
       let t_r = type_of_expr checked_r in
       let t_l =  type_of_expr checked_l in
       (match (t_l, t_r) with
       | (Lrx_Atom(a1), Lrx_Atom(a2)) ->
          if t_r = t_l then C_Assign(t_l, checked_l, checked_r) else 
            raise(Failure("assignment not compatible with expressions of type " ^ string_of_var_type t_l ^ " and " ^ string_of_var_type t_r))  
       | (Lrx_Tree(t1), Lrx_Tree(t2)) -> 
         if t1.datatype = t2.datatype then C_Assign(t_l, checked_l, checked_r) else
         raise(Failure("assignment not compatible with expressions of type " ^ string_of_var_type t_l ^ " and " ^ string_of_var_type t_r))   
       | _ -> raise(Failure("assignment not compatible with expressions of type " ^ string_of_var_type t_l ^ " and " ^ string_of_var_type t_r)) ) 
     | Unop(e, op) ->
          let checked = check_expr e env in
          check_unop checked op (* returns C_Unop *)
     | Null_Literal -> C_Null_Literal
     | Call(n, el) -> 
          let checked = check_exprlist el env in
          check_fun_call n checked env
     | Noexpr -> C_Noexpr
		
and check_exprlist (el:expr list) env =
	  match el with
	     [] -> []
	   | head :: tail -> (check_expr head env) :: (check_exprlist tail env)


(* check a single statement *)
let rec check_statement (s:stmt) ret_type env (in_loop:int) = 
	  match s with
	     CodeBlock(b) ->
       let checked_block = check_block b ret_type env in_loop in
       C_CodeBlock(checked_block)
     | Return(e) -> 
       let checked = check_expr e env in
       let t = type_of_expr checked in
       if t = ret_type then C_Return(checked) else
       raise (Failure("function return type " ^ string_of_var_type t ^ "; type " ^ string_of_var_type ret_type ^ "expected"))
     | Expr(e) -> C_Expr(check_expr e env) 
     | If(e, b1, b2) -> 
        let c = check_expr e env in
        let t = type_of_expr c in
        (match t with
          Lrx_Atom(Lrx_Bool) -> C_If(c, check_block b1 ret_type env in_loop, check_block b2 ret_type env in_loop)
        | _ -> raise (Failure "If statement must evaluate on boolean expression"))
     | For(e1, e2, e3, b) -> 
       let (c1, c2, c3) = (check_expr e1 env, check_expr e2 env, check_expr e3 env) in
       if(type_of_expr c2 = Lrx_Atom(Lrx_Bool)) then
       C_For(c1, c2, c3, check_block b ret_type env (in_loop + 1))
		   else raise(Failure("for loop condition must evaluate on boolean expressions"))
	   | While(e, b) -> 
       let c = check_expr e env in
		   if type_of_expr c = Lrx_Atom(Lrx_Bool) then 
       C_While(c, check_block b ret_type env (in_loop + 1))
		   else raise(Failure("while loop must evaluate on boolean expression"))
    | Continue ->
       if in_loop = 0 then raise (Failure "continue statement not within for or while loop")
       else C_Continue
    | Break ->
       if in_loop = 0 then raise (Failure "break statement not within for or while loop")
       else C_Break

and check_is_fdecl (f:string) env =
    let fd = Symtab.symtab_find f env in
	  match fd with
		   SymTab_VarDecl(v) -> raise(Failure("symbol is not a function"))
	   | SymTab_FuncDecl(f) -> f 

(* returns a verified statement list *)
and check_statement_list (s:stmt list) (ret_type:var_type) env (in_loop:int)=
    match s with
       [] -> []
     | head :: tail -> check_statement head ret_type env in_loop :: check_statement_list tail ret_type env in_loop

(* returns verified c_block record *)
and check_block (b:block) (ret_type:var_type) env (in_loop:int) =
    let vars = check_is_vardecls b.locals (fst env, b.block_id) in
    let stmts = check_statement_list b.statements ret_type (fst env, b.block_id) in_loop in
    { c_locals = vars; c_statements = stmts; c_block_id = b.block_id }

(* returns c_func record *)
and check_function (f:func) env =
    let checked_block = check_block f.fblock f.ret_type env 0 in
    let checked_formals = check_is_vardecls f.formals (fst env, f.fblock.block_id) in	
    let checked_scope_func_decl = check_is_fdecl f.fname env in
    { c_fname = fst_of_four checked_scope_func_decl; c_ret_type = f.ret_type; c_formals = checked_formals; c_fblock = checked_block }

(* returns list of verified function declarations *)
and check_functions (funcs:func list) env =
	  match funcs with
	     [] -> []
	   | head :: tail -> check_function head env :: check_functions tail env 

and check_main_exists (f:c_func list) =
	  if (List.filter main_fdecl f) = [] then false else true

(* returns list of verified global variable declarations *)
and check_is_vardecls (vars: var list) env =
    match vars with
       [] -> []
     | head :: tail -> 
       let decl = Symtab.symtab_find (fst head) env in
       let id = Symtab.symtab_get_id (fst head) env in 
       match decl with 
        	SymTab_FuncDecl(f) -> raise(Failure("symbol is not a variable"))
	      | SymTab_VarDecl(v) -> 
          let var = snd_of_three v in
          match var with
             Lrx_Tree(t) -> 
             let checked_degree = check_expr t.degree env in
             let type_of_degree = type_of_expr checked_degree in
             (match type_of_degree with
                 Lrx_Atom(Lrx_Int) -> (fst_of_three v, snd_of_three v, id) :: check_is_vardecls tail env
               | _ -> raise (Failure ("Tree degree must be of type int")))
        | Lrx_Atom(a) -> (fst_of_three v, snd_of_three v, id) :: check_is_vardecls tail env


(* 
 * returns (<<verified list of global variable declarations>>, <<verified list of function declarations>>) 
 *)
let check_program (p:program) env =
    let gs = fst p in
    let fs = snd p in
	  let vdecllst = check_is_vardecls gs env in
	  let fdecllst = check_functions fs env in
	  if (check_main_exists fdecllst) then (vdecllst, fdecllst)
	  else raise (Failure("function main not found"))

