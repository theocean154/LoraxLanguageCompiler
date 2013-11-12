(* checking pass
 	-perform semantic checks on all expressions
	-annotate expressions in AST with type information
	-resolve identifier names
*)

open Ast

(* checked c_expression *)
type c_expr =
	StrLiteral of string
	| NumLiteral of int
	| Binop of var_type * c_expr * bop * c_expr
	| Unop of var_type * c_expr * uop
	| Assign of var_type * c_lvalue * c_expr (* lvalue and right side *)
	| FuncCall of func_decl * c_expr list
	| Rvalue of var_type * c_lvalue (* variable (on the right side) *)
	| NoExpr

and c_lvalue = var_decl * c_expr

type c_stmt =
	CodeBlock of c_block
	| Loop of c_expr * c_block
	| Conditional of c_expr * c_block * c_block
	| Return of c_expr
	| Expression of c_expr

and c_block = {
	c_locals: var_decl list;
	c_statements: c_stmt list;
	c_block_id: int;
}

and c_func = {
	c_formals: var_decl list;
	c_header: func_decl;
	c_body: c_block;
}

type c_program = {
	c_globals: var_decl list;
	c_functions: c_func list;
	c_block_count: int
}

let build_fdecl (name:string) (ret:var_type) (args:var_type list) =
	(name, ret, args, 0)

let get_ret_of_fdecl (f:func_decl) =
	let (_,t,_,_) = f in
	t

let main_fdecl (f:c_func) =
	let fdecl = f.c_header in
	let (name, t, formals, _) = fdecl in
	if name = "main" && t = Simple(Num) && formals = [] then true
	else false

let type_of_expr = function
	StrLiteral(s) -> Simple(Str)
	| NumLiteral(n) -> Simple(Num)
	| NoExpr -> Simple(None)
	| Binop(t,_,_,_) -> t
	| Unop(t,_,_) -> t
	| Rvalue(t,_) -> t
	| Assign(t,_,_) -> t
	| FuncCall(fdecl,_) -> let (_,t,_,_) = fdecl in t

let binop_error (t1:var_type) (t2:var_type) (op:Ast.bop) =
	raise(Failure("operator " ^ (string_of_binop op) ^ " not compatible with expressions of type " ^
		(string_of_type t1) ^ " and " ^ (string_of_type t2)))

let unop_error (t:var_type) (op:Ast.uop) =
	raise(Failure("operator " ^ (string_of_unop op) ^ " not compatible with expression of type " ^
		(string_of_type t)))

let check_binop (c1:c_expr) (c2:c_expr) (op:Ast.bop) =
	let (t1, t2) = (type_of_expr c1, type_of_expr c2) in
	match(t1, t2) with
		(Simple(Num), Simple(Num)) -> Binop(Simple(Num), c1, op, c2) (* standard arithmetic binops *)
		| (Simple(Str), Simple(Str)) -> (* string binops with 2 string operands *)
			let f = (match op with
			Less -> build_fdecl "__str_less" (Simple(Num)) [t1; t2]
			| Leq -> build_fdecl "__str_lessequal" (Simple(Num)) [t1; t2]
			| Greater -> build_fdecl "__str_greater" (Simple(Num)) [t1; t2]
			| Geq -> build_fdecl "__str_greaterequal" (Simple(Num)) [t1; t2]
			| Eq -> build_fdecl "__str_equal" (Simple(Num)) [t1; t2]
			| Neq -> build_fdecl "__str_notequal" (Simple(Num)) [t1; t2]
			| Plus -> build_fdecl "__str_concat" t1 [t1; t2]
			| Divide ->build_fdecl "__str_match" t1 [t1; t2]
			| Mod -> build_fdecl "__str_index" (Simple(Num)) [t1; t2]
			| _ -> binop_error t1 t2 op) in
			FuncCall(f, [c1; c2])
		| (Simple(Str), Simple(Num)) -> (* string binops with 1 string operand *)
			(match op with
			Minus -> let f = build_fdecl "__str_substr" t1 [t1; t2] in
				FuncCall(f, [c1; c2])
			| _ -> binop_error t1 t2 op)
		| (Map(k1,v1), Map(k2,v2)) -> (* map binops *)
			if k1 = k2 && v1 = v2 then
			let f = (match op with
				Eq -> build_fdecl "__map_equal" (Simple(Num)) [t1; t2]
				| Neq -> build_fdecl "__map_notequal" (Simple(Num)) [t1; t2]
				| _ -> binop_error t1 t2 op) in
			FuncCall(f, [c1; c2])
			else binop_error t1 t2 op
		| (Map(k, v), Simple(l)) ->
			if k = l then
				let f = (match op with
					Minus -> build_fdecl "__map_remove" (Simple(v)) [t1; t2]
					| Mod -> build_fdecl "__map_exists" (Simple(Num)) [t1; t2]
					| _ -> binop_error t1 t2 op) in
				FuncCall(f, [c1; c2])
			else binop_error t1 t2 op
		| _ -> binop_error t1 t2 op

let check_unop (c:c_expr) (op:Ast.uop) =
	let t = type_of_expr c in
	match t with
		Simple(Num) ->
			(match op with
				(Neg | Not) -> Unop(Simple(Num), c, op)
				| _ -> unop_error t op)
		| Simple(Str) ->
			(match op with
				Len -> let f = build_fdecl "__str_len" (Simple(Num)) [t] in
					FuncCall(f, [c])
				| _ -> unop_error t op)
		| Map(k, v) ->
			let f = (match op with
				Len -> build_fdecl "__map_len" (Simple(Num)) [t]
				| Keys -> build_fdecl "__map_keys" (Map(Num, k)) [t]
				| Vals -> build_fdecl "__map_vals" (Map(Num, v)) [t]
				| _ -> unop_error t op) in
				FuncCall(f, [c])
		| _ -> unop_error t op
	
let rec compare_arglists formals actuals =
	match (formals,actuals) with
	([],[]) -> true
	| (head1::tail1, head2::tail2)
		-> (head1 = head2) && compare_arglists tail1 tail2
	| _ -> false

and check_func (name:string) (cl:c_expr list) env =
	let decl = Symtab.symtab_find name env in
	let func = (match decl with FuncDecl(f) -> f
		| _ -> raise(Failure("symbol " ^ name ^ " is not a function"))) in
	let (_,t,formals,_) = func in
	let actuals = List.map type_of_expr cl in
	if (List.length formals) = (List.length actuals) then
		if compare_arglists formals actuals then
			FuncCall(func, cl)
		else
			raise(Failure("function " ^ name ^ "'s argument types don't match its formals"))
	else raise(Failure("function " ^ name ^ " expected " ^ (string_of_int (List.length actuals)) ^
		" arguments but called with " ^ (string_of_int (List.length formals))))

and check_lvalue (lv:lvalue) (checked:c_expr) env =
	let (name,e) = lv in
	let decl = Symtab.symtab_find name env in
	let var = (match decl with VarDecl(v) -> v
			| _ -> raise(Failure("symbol " ^ name ^ " is not a variable"))) in
	let (_,base_t,_) = var in
	let t = type_of_expr checked in
	match t with
		Simple(None) -> (base_t, (var, checked))
		| _ ->
			match base_t with
				Map(k, v) ->
					if t = Simple(k) then (Simple(v), (var, checked))
					else raise(Failure("map type does not match accessor type"))
				| _ -> raise(Failure("cannot apply accessor to non-map"))

and check_expr (e:expr) env =
	match e with
	Ast.StrLiteral(s) -> StrLiteral(s)
	| Ast.NumLiteral(n) -> NumLiteral(n)
	| Ast.NoExpr -> NoExpr
	| Ast.Replace(e1, e2, e3) ->
		let c1, c2 = (check_expr e1 env, check_expr e2 env) in
		let c3 = check_expr e3 env in
		let (t1, t2, t3) = (type_of_expr c1, type_of_expr c2, type_of_expr c3) in
		if(t1 = t2 && t2 = t3 && t3 = Simple(Str)) then
			let f = build_fdecl "__str_replace" t1 [t1; t2; t3] in
			FuncCall(f, [c1; c2; c3])
		else raise(Failure("operator ~ requires 3 string expressions"))
	| Ast.Binop(e1, op, e2) ->
		let (c1, c2) = (check_expr e1 env, check_expr e2 env) in
		check_binop c1 c2 op
	| Ast.Unop(e1, op) ->
		let checked = check_expr e1 env in
		check_unop checked op
	| Ast.Rvalue(l) ->
		let checked = check_expr (snd l) env in
		let (result_t, lv) = check_lvalue l checked env in
		Rvalue(result_t, lv)
	| Ast.Assign(l, ae) ->
		let checked = check_expr ae env in
		let deref = check_expr (snd l) env in
		let (result_t, lv) = check_lvalue l deref env in
		let t = type_of_expr checked in
		if t = result_t then Assign(t, lv, checked)
		else 
			(match (checked, result_t) with
				(NumLiteral(0), Map(_,_)) -> let f = build_fdecl "__map_empty" result_t [result_t] in
				FuncCall(f, [Rvalue(result_t, lv)])
			| _ -> raise(Failure("assignment not compatible with expressions of type " ^
			string_of_type result_t ^ " and " ^ string_of_type t)))
	| Ast.FuncCall(name, el) ->
		let checked = check_exprlist el env in
		check_func name checked env
		
and check_exprlist (el:expr list) env =
	match el with
	[] -> []
	| head :: tail -> (check_expr head env) :: (check_exprlist tail env)

(* check a single statement *)
let rec check_stmt (s:stmt) ret_type env =
	match s with
	Ast.CodeBlock(b) -> CodeBlock(check_block b ret_type env)
	| Ast.Loop(e, b) -> let checked = check_expr e env in
		if type_of_expr checked = Simple(Num) then Loop(checked, check_block b ret_type env)
		else raise(Failure("loop condition expression must be numeric"))
	| Ast.Conditional(e, b1, b2) -> let checked = check_expr e env in
		if type_of_expr checked = Simple(Num) then Conditional(checked, check_block b1 ret_type env, check_block b2 ret_type env)
		else raise(Failure("if condition expression must be numeric"))
	| Ast.Return(e) -> let checked = check_expr e env in
		let t = type_of_expr checked in
		if t = ret_type then Return(checked) else
			raise(Failure("function return type " ^ string_of_type ret_type ^ " not compatible with expression of type " ^ string_of_type t))
	| Ast.Expression(e) -> Expression(check_expr e env)

(* check a list of statements *)
and check_stmtlist (s:stmt list) (ret_type:var_type) env =
	match s with
	[] -> []
	| head :: tail -> check_stmt head ret_type env :: check_stmtlist tail ret_type env

and check_vdecllist (v:var list) env =
	match v with
	[] -> []
	| head :: tail ->
		let decl = Symtab.symtab_find (fst head) env in
		match decl with
			FuncDecl(f) -> raise(Failure("symbol is not a variable"))
			| VarDecl(v) -> v :: check_vdecllist tail env

and check_fdecl (f:string) env =
	let decl = Symtab.symtab_find f env in
	match decl with
		VarDecl(v) -> raise(Failure("symbol is not a function"))
		| FuncDecl(f) -> f

(* check a block *)
and check_block (b:block) (ret_type:var_type) env =
	let vars = check_vdecllist b.locals (fst env, b.block_id) in
	{ c_locals = vars;
		c_statements = check_stmtlist b.statements ret_type (fst env, b.block_id);
		c_block_id = b.block_id}

(* check a function *)
and check_func (f:func) env =
	let checked = check_block f.body f.ret_type env in
	let formals = check_vdecllist f.formals (fst env, f.body.block_id) in
	{ c_header = check_fdecl f.name env; c_body = checked; c_formals = formals }

(* check a function list *)
and check_funclist (funcs:func list) env =
	match funcs with
	[] -> []
	| head :: tail -> check_func head env :: check_funclist tail env

and check_main (f:c_func list) =
	if (List.filter main_fdecl f) = [] then false
	else true

let check_program (p:program) env =
	let vars = check_vdecllist p.globals env in
	let checked = check_funclist p.functions env in
	if (check_main checked) then {c_globals = vars; c_functions = checked; c_block_count = p.block_count}
	else raise(Failure("function main(^) -> # not found"))
