%{
/* ============================================================
   lexer.l  -  Mini Compiler lexer (simple style, like the
   keyword/arithmetic/boolean demo files)
   ============================================================ */
#include "parser.tab.h"
#include <string.h>
#include <stdlib.h>
%}

%option noyywrap
%option yylineno

DIGIT   [0-9]
LETTER  [a-zA-Z_]

%%

"int"                   { return INT; }
"float"                 { return FLOAT; }
"char"                  { return CHAR; }
"print"                 { return PRINT; }

{DIGIT}+"."{DIGIT}+     { yylval.num = atof(yytext); return FNUMBER; }
{DIGIT}+                { yylval.num = atof(yytext); return NUMBER; }

\'(\\.|[^\\'])\'        {
                            /* character literal: 'a', '\n', '\t', etc.
                               stored straight away as its double (ASCII) value */
                            char c;
                            if (yytext[1] == '\\') {
                                switch (yytext[2]) {
                                    case 'n':  c = '\n'; break;
                                    case 't':  c = '\t'; break;
                                    case '0':  c = '\0'; break;
                                    case '\\': c = '\\'; break;
                                    case '\'': c = '\''; break;
                                    default:   c = yytext[2]; break;
                                }
                            } else {
                                c = yytext[1];
                            }
                            yylval.num = (double)c;
                            return CHARLIT;
                        }

{LETTER}({LETTER}|{DIGIT})*  { yylval.id = strdup(yytext); return ID; }

"="                     { return ASSIGN; }
"+"                     { return PLUS; }
"-"                     { return MINUS; }
"*"                     { return TIMES; }
"/"                     { return DIVIDE; }
"("                     { return LPAREN; }
")"                     { return RPAREN; }
";"                     { return SEMI; }

[ \t]+                  { /* skip whitespace */ }
\n                      { /* line counter handled by yylineno */ }
"//".*                  { /* skip single-line comments */ }
"/*"([^*]|\*+[^*/])*\*+"/"   { /* skip multi-line comments */ }

.                       {
                            fprintf(stderr,
                                "Lexical Error: unexpected character '%s' at line %d\n",
                                yytext, yylineno);
                        }

%%
