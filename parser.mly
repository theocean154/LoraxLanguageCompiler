%token LBRACKET RBRACKET SEMI COMMA 
%token <string> ID

%start expr

%%
/* Here's what I got. I'm pretty positive on the actual CFG. Not so sure 
about what we actually want to pass in the Ocaml literal part.. but we
can change that when we have a better idea of how that next step works. */

tree:
	expr LBRACKET RBRACKET SEMI { $1 }
	| expr LBRACKET nodes RBRACKET SEMI { Tree( $1, $3 ) }
	
nodes:
	expr COMMA nodes   { $3::$1 }
	| expr { [$1] }

expr:
	ID	{ $1 }
	| tree	{ $1 }