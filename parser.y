%{
/* ============================================================
   parser.y  -  Mini Compiler grammar (simple style)
   Supports int, float, char declarations + assignment + print.

   Design choice: every expression is computed in plain `double`
   (like bis_pb_2.y does for NUM). We don't carry a runtime type
   tag through the expression tree at all, so the %union only
   ever needs built-in types (double / char* / int) -- exactly
   like the reference examples. The variable's *declared* type
   (int/float/char), stored in the symbol table, is what decides
   how a value gets truncated on assignment and formatted on
   print.
   ============================================================ */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void yyerror(const char *s);
int yylex(void);
extern int yylineno;
extern FILE *yyin;

/* ---------------- Type tags (bookkeeping only, in the .c file) ---------------- */
#define TYPE_INT   0
#define TYPE_FLOAT 1
#define TYPE_CHAR  2

/* ---------------- Shadow "type stack" ----------------
   Bison's own value stack only holds `double` for expr (see %union
   below -- deliberately just built-in types, no custom struct).
   To still know whether an expr was int/float/char (for correct
   integer-division and accurate narrowing warnings), we keep a
   second, hand-rolled stack of type tags that we push/pop in
   lock-step with every expr-producing rule. It never needs to be
   seen by lexer.l, so it causes zero header-sharing headaches. */
#define MAX_STACK 256
int typeStack[MAX_STACK];
int typeTop = 0;

void pushType(int t) {
    if (typeTop < MAX_STACK) typeStack[typeTop++] = t;
}
int popType(void) {
    if (typeTop <= 0) return TYPE_INT;
    return typeStack[--typeTop];
}

/* ---------------- Symbol table ---------------- */
#define MAX_VARS 100

typedef struct {
    char   name[64];
    int    type;    /* TYPE_INT / TYPE_FLOAT / TYPE_CHAR */
    double value;    /* always stored as double; type says how to read it */
} Symbol;

Symbol symtab[MAX_VARS];
int    symcount = 0;

const char *typeName(int type) {
    switch (type) {
        case TYPE_INT:   return "int";
        case TYPE_FLOAT: return "float";
        case TYPE_CHAR:  return "char";
    }
    return "unknown";
}

int lookup(const char *name) {
    int i;
    for (i = 0; i < symcount; i++)
        if (strcmp(symtab[i].name, name) == 0)
            return i;
    return -1;
}

void declare(const char *name, int type) {
    if (lookup(name) != -1) {
        printf("Semantic Error (line %d): variable '%s' already declared\n",
               yylineno, name);
        return;
    }
    if (symcount >= MAX_VARS) {
        printf("Error: symbol table full\n");
        return;
    }
    strncpy(symtab[symcount].name, name, sizeof(symtab[symcount].name) - 1);
    symtab[symcount].type  = type;
    symtab[symcount].value = 0.0;
    symcount++;
}

void assign(const char *name, double val, int srcType) {
    int idx = lookup(name);
    if (idx == -1) {
        printf("Semantic Error (line %d): variable '%s' not declared\n",
               yylineno, name);
        return;
    }

    /* Warn on lossy narrowing (float -> int/char), same rule as before,
       but now based on the SOURCE expr's real type, not a value guess. */
    if (symtab[idx].type != TYPE_FLOAT && srcType == TYPE_FLOAT) {
        printf("Warning (line %d): assigning float to %s '%s' truncates the value\n",
               yylineno, typeName(symtab[idx].type), name);
    }

    switch (symtab[idx].type) {
        case TYPE_INT:   symtab[idx].value = (double)(long)val;        break;
        case TYPE_FLOAT: symtab[idx].value = val;                      break;
        case TYPE_CHAR:  symtab[idx].value = (double)(char)(long)val;  break;
    }
}

double getValue(const char *name) {
    int idx = lookup(name);
    if (idx == -1) {
        printf("Semantic Error (line %d): variable '%s' not declared\n",
               yylineno, name);
        pushType(TYPE_INT);
        return 0.0;
    }
    pushType(symtab[idx].type);
    return symtab[idx].value;
}

void printVar(const char *name) {
    int idx = lookup(name);
    if (idx == -1) {
        printf("Semantic Error (line %d): variable '%s' not declared\n",
               yylineno, name);
        return;
    }
    switch (symtab[idx].type) {
        case TYPE_INT:   printf("%d\n", (int)symtab[idx].value);   break;
        case TYPE_FLOAT: printf("%g\n", symtab[idx].value);        break;
        case TYPE_CHAR:  printf("%c\n", (char)symtab[idx].value);  break;
    }
}
%}

/* ---------------- Semantic value type: only built-ins, no custom struct ---------------- */
%union {
    double  num;
    char   *id;
    int     type;
}

/* ---------------- Token declarations ---------------- */
%token INT FLOAT CHAR PRINT
%token ASSIGN PLUS MINUS TIMES DIVIDE
%token LPAREN RPAREN SEMI
%token <num> NUMBER FNUMBER CHARLIT
%token <id>  ID

/* ---------------- Nonterminal types ---------------- */
%type <num>  expr
%type <type> type_spec

/* ---------------- Operator precedence ---------------- */
%left PLUS MINUS
%left TIMES DIVIDE
%right UMINUS

%%

/* ================= Grammar Rules ================= */

program:
      stmt_list
    ;

stmt_list:
      /* empty */
    | stmt_list stmt
    ;

type_spec:
      INT    { $$ = TYPE_INT; }
    | FLOAT  { $$ = TYPE_FLOAT; }
    | CHAR   { $$ = TYPE_CHAR; }
    ;

stmt:
      type_spec ID SEMI
        {
            declare($2, $1);
            free($2);
        }
    | ID ASSIGN expr SEMI
        {
            int srcType = popType();
            assign($1, $3, srcType);
            free($1);
        }
    | PRINT ID SEMI
        {
            printVar($2);
            free($2);
        }
    | error SEMI
        {
            yyerrok;   /* basic error recovery: resync on next ';' */
        }
    ;

expr:
      expr PLUS expr
        {
            int t2 = popType(), t1 = popType();
            int rt = (t1 == TYPE_FLOAT || t2 == TYPE_FLOAT) ? TYPE_FLOAT : TYPE_INT;
            pushType(rt);
            $$ = (rt == TYPE_FLOAT) ? ($1 + $3) : (double)((long)$1 + (long)$3);
        }
    | expr MINUS expr
        {
            int t2 = popType(), t1 = popType();
            int rt = (t1 == TYPE_FLOAT || t2 == TYPE_FLOAT) ? TYPE_FLOAT : TYPE_INT;
            pushType(rt);
            $$ = (rt == TYPE_FLOAT) ? ($1 - $3) : (double)((long)$1 - (long)$3);
        }
    | expr TIMES expr
        {
            int t2 = popType(), t1 = popType();
            int rt = (t1 == TYPE_FLOAT || t2 == TYPE_FLOAT) ? TYPE_FLOAT : TYPE_INT;
            pushType(rt);
            $$ = (rt == TYPE_FLOAT) ? ($1 * $3) : (double)((long)$1 * (long)$3);
        }
    | expr DIVIDE expr
        {
            int t2 = popType(), t1 = popType();
            int rt = (t1 == TYPE_FLOAT || t2 == TYPE_FLOAT) ? TYPE_FLOAT : TYPE_INT;
            pushType(rt);
            if ($3 == 0.0) {
                printf("Runtime Error (line %d): division by zero\n", yylineno);
                $$ = 0.0;
            } else if (rt == TYPE_FLOAT) {
                $$ = $1 / $3;
            } else {
                $$ = (double)((long)$1 / (long)$3);   /* integer division */
            }
        }
    | MINUS expr %prec UMINUS
        {
            /* type is unchanged by unary minus -- leave typeStack as-is */
            $$ = -$2;
        }
    | LPAREN expr RPAREN
        {
            /* type is unchanged -- leave typeStack as-is */
            $$ = $2;
        }
    | NUMBER   { pushType(TYPE_INT);   $$ = $1; }
    | FNUMBER  { pushType(TYPE_FLOAT); $$ = $1; }
    | CHARLIT  { pushType(TYPE_CHAR);  $$ = $1; }
    | ID       { $$ = getValue($1); free($1); }
    ;

%%

/* ================= Support Functions ================= */

void yyerror(const char *s) {
    fprintf(stderr, "Syntax Error (line %d): %s\n", yylineno, s);
}

int main(int argc, char **argv) {
    if (argc > 1) {
        FILE *f = fopen(argv[1], "r");
        if (!f) {
            fprintf(stderr, "Could not open file: %s\n", argv[1]);
            return 1;
        }
        yyin = f;
    }

    printf("---- Program Output ----\n");
    yyparse();
    printf("-------------------------\n");

    return 0;
}
