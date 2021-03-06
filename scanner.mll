(* 
 * Authors:
 * Chris D'Angelo
 *)

{ 
	open Parser 
	exception LexError of string

	let verify_escape s =
		if String.length s = 1 then (String.get s 0)
		else 
		match s with
		   "\\n" -> '\n'
		 | "\\t" -> '\t'
		 | "\\\\" -> '\\'
		 | c -> raise (Failure("unsupported character " ^ c))
}

(* Regular Definitions *)

let digit = ['0'-'9']
let decimal = ((digit+ '.' digit*) | ('.' digit+))

(* Regular Rules *)

(* 
 * built-in functions handled as keywords in semantic checking
 * print, root, degree
 *)

rule token = parse
  [' ' '\t' '\r' '\n'] { token lexbuf } 
| "/*"       { block_comment lexbuf } 
| "//"	     { line_comment lexbuf }
| '('        { LPAREN }
| ')'        { RPAREN }
| '{'        { LBRACE }
| '}'        { RBRACE }
| ']'        { RBRACKET }
| '['        { LBRACKET }
| ';'        { SEMI }
| ','        { COMMA }
| '+'        { PLUS }
| '-'        { MINUS }
| "--"       { POP }
| '*'        { TIMES }
| "mod"      { MOD } 
| '/'        { DIVIDE }
| '='        { ASSIGN }
| "=="       { EQ }
| "!="       { NEQ }
| '<'        { LT }
| "<="       { LEQ }
| ">"        { GT }
| ">="       { GEQ }
| "if"       { IF }
| "else"     { ELSE }
| "for"      { FOR }
| "while"    { WHILE }
| "return"   { RETURN }
| "int"      { INT }
| "float"    { FLOAT }	
| "string"   { STRING }
| "bool"     { BOOL } 
| "tree"     { TREE } 
| "break"    { BREAK }
| "continue" { CONTINUE }
| "null"     { NULL } 
| "char"	 { CHAR }
| "!"		 { NOT } 
| "&&"		 { AND }
| "||"		 { OR }	
| '@'	     { AT }
| '%'		 { CHILD }
| digit+ as lxm 				{ INT_LITERAL(int_of_string lxm) }
| decimal as lxm 				{ FLOAT_LITERAL(float_of_string lxm) }
| '\"' ([^'\"']* as lxm) '\"'   { STRING_LITERAL(lxm) }
| '\'' ([^'\'']* as lxm ) '\'' 	{ CHAR_LITERAL((verify_escape lxm)) }
| ("true" | "false") as lxm		{ BOOL_LITERAL(bool_of_string lxm) }
| ['a'-'z' 'A'-'Z']['a'-'z' 'A'-'Z' '0'-'9' '_']* as lxm { ID(lxm) }
| eof { EOF }
| _ as char { raise (Failure("illegal character " ^ Char.escaped char)) }

and block_comment = parse
  "*/" { token lexbuf }
| eof  { raise (LexError("unterminated block_comment!")) }
| _    { block_comment lexbuf }

and line_comment = parse
| ['\n' '\r'] { token lexbuf }
| _           { line_comment lexbuf }
