%glr-parser
%pure-parser
%locations
%error-verbose
%defines
/* %no-lines */
%parse-param { yyscan_t scanner }
%parse-param { ParseData * data }
%lex-param { yyscan_t scanner }


%{
/* Newer versions of Bison copy the declarations below to
   parser-tab.hh, which sucks bigtime since lexer.l doesn't want that
   stuff.  So allow it to be excluded. */
#ifndef BISON_HEADER_HACK
#define BISON_HEADER_HACK
    
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "aterm.hh"
#include "util.hh"
    
#include "nixexpr.hh"

#include "parser-tab.hh"
#include "lexer-tab.hh"
#define YYSTYPE YYSTYPE // workaround a bug in Bison 2.4


using namespace nix;


namespace nix {

    
struct ParseData 
{
    Expr * result;
    Path basePath;
    Path path;
    string error;
};


#if 0
static string showAttrPath(ATermList attrPath)
{
    string s;
    for (ATermIterator i(attrPath); i; ++i) {
        if (!s.empty()) s += '.';
        s += aterm2String(*i);
    }
    return s;
}
 

struct Tree
{
    Expr leaf; ATerm pos; bool recursive;
    typedef std::map<ATerm, Tree> Children;
    Children children;
    Tree() { leaf = 0; recursive = true; }
};


static ATermList buildAttrs(const Tree & t, ATermList & nonrec)
{
    ATermList res = ATempty;
    for (Tree::Children::const_reverse_iterator i = t.children.rbegin();
         i != t.children.rend(); ++i)
        if (!i->second.recursive)
            nonrec = ATinsert(nonrec, makeBind(i->first, i->second.leaf, i->second.pos));
        else
            res = ATinsert(res, i->second.leaf
                ? makeBind(i->first, i->second.leaf, i->second.pos)
                : makeBind(i->first, makeAttrs(buildAttrs(i->second, nonrec)), makeNoPos()));
    return res;
}
#endif
 

static void fixAttrs(ExprAttrs & attrs)
{
#if 0
    Tree attrs;

    /* This ATermMap is needed to ensure that the `leaf' fields in the
       Tree nodes are not garbage collected. */
    ATermMap gcRoots;

    for (ATermIterator i(as); i; ++i) {
        ATermList names, attrPath; Expr src, e; ATerm name, pos;

        if (matchInherit(*i, src, names, pos)) {
            bool fromScope = matchScope(src);
            for (ATermIterator j(names); j; ++j) {
                if (attrs.children.find(*j) != attrs.children.end()) 
                    throw ParseError(format("duplicate definition of attribute `%1%' at %2%")
                        % showAttrPath(ATmakeList1(*j)) % showPos(pos));
                Tree & t(attrs.children[*j]);
                Expr leaf = fromScope ? makeVar(*j) : makeSelect(src, *j);
                gcRoots.set(leaf, leaf);
                t.leaf = leaf;
                t.pos = pos;
                if (recursive && fromScope) t.recursive = false;
            }
        }

        else if (matchBindAttrPath(*i, attrPath, e, pos)) {

            Tree * t(&attrs);
            
            for (ATermIterator j(attrPath); j; ) {
                name = *j; ++j;
                if (t->leaf) throw ParseError(format("attribute set containing `%1%' at %2% already defined at %3%")
                    % showAttrPath(attrPath) % showPos(pos) % showPos (t->pos));
                t = &(t->children[name]);
            }

            if (t->leaf)
                throw ParseError(format("duplicate definition of attribute `%1%' at %2% and %3%")
                    % showAttrPath(attrPath) % showPos(pos) % showPos (t->pos));
            if (!t->children.empty())
                throw ParseError(format("duplicate definition of attribute `%1%' at %2%")
                    % showAttrPath(attrPath) % showPos(pos));

            t->leaf = e; t->pos = pos;
        }

        else abort(); /* can't happen */
    }

    ATermList nonrec = ATempty;
    ATermList rec = buildAttrs(attrs, nonrec);
        
    return recursive ? makeRec(rec, nonrec) : makeAttrs(rec);
#endif
}


#if 0
static void checkPatternVars(ATerm pos, ATermMap & map, Pattern pat)
{
    ATerm name = sNoAlias;
    ATermList formals;
    ATermBool ellipsis;
    
    if (matchAttrsPat(pat, formals, ellipsis, name)) { 
        for (ATermIterator i(formals); i; ++i) {
            ATerm d1, name2;
            if (!matchFormal(*i, name2, d1)) abort();
            if (map.get(name2))
                throw ParseError(format("duplicate formal function argument `%1%' at %2%")
                    % aterm2String(name2) % showPos(pos));
            map.set(name2, name2);
        }
    }

    else matchVarPat(pat, name);

    if (name != sNoAlias) {
        if (map.get(name))
            throw ParseError(format("duplicate formal function argument `%1%' at %2%")
                % aterm2String(name) % showPos(pos));
        map.set(name, name);
    }
}


static void checkPatternVars(ATerm pos, Pattern pat)
{
    ATermMap map;
    checkPatternVars(pos, map, pat);
}


static Expr stripIndentation(ATermList es)
{
    if (es == ATempty) return makeStr("");
    
    /* Figure out the minimum indentation.  Note that by design
       whitespace-only final lines are not taken into account.  (So
       the " " in "\n ''" is ignored, but the " " in "\n foo''" is.) */
    bool atStartOfLine = true; /* = seen only whitespace in the current line */
    unsigned int minIndent = 1000000;
    unsigned int curIndent = 0;
    ATerm e;
    for (ATermIterator i(es); i; ++i) {
        if (!matchIndStr(*i, e)) {
            /* Anti-quotations end the current start-of-line whitespace. */
            if (atStartOfLine) {
                atStartOfLine = false;
                if (curIndent < minIndent) minIndent = curIndent;
            }
            continue;
        }
        string s = aterm2String(e);
        for (unsigned int j = 0; j < s.size(); ++j) {
            if (atStartOfLine) {
                if (s[j] == ' ')
                    curIndent++;
                else if (s[j] == '\n') {
                    /* Empty line, doesn't influence minimum
                       indentation. */
                    curIndent = 0;
                } else {
                    atStartOfLine = false;
                    if (curIndent < minIndent) minIndent = curIndent;
                }
            } else if (s[j] == '\n') {
                atStartOfLine = true;
                curIndent = 0;
            }
        }
    }

    /* Strip spaces from each line. */
    ATermList es2 = ATempty;
    atStartOfLine = true;
    unsigned int curDropped = 0;
    unsigned int n = ATgetLength(es);
    for (ATermIterator i(es); i; ++i, --n) {
        if (!matchIndStr(*i, e)) {
            atStartOfLine = false;
            curDropped = 0;
            es2 = ATinsert(es2, *i);
            continue;
        }
        
        string s = aterm2String(e);
        string s2;
        for (unsigned int j = 0; j < s.size(); ++j) {
            if (atStartOfLine) {
                if (s[j] == ' ') {
                    if (curDropped++ >= minIndent)
                        s2 += s[j];
                }
                else if (s[j] == '\n') {
                    curDropped = 0;
                    s2 += s[j];
                } else {
                    atStartOfLine = false;
                    curDropped = 0;
                    s2 += s[j];
                }
            } else {
                s2 += s[j];
                if (s[j] == '\n') atStartOfLine = true;
            }
        }

        /* Remove the last line if it is empty and consists only of
           spaces. */
        if (n == 1) {
            string::size_type p = s2.find_last_of('\n');
            if (p != string::npos && s2.find_first_not_of(' ', p + 1) == string::npos)
                s2 = string(s2, 0, p + 1);
        }
            
        es2 = ATinsert(es2, makeStr(s2));
    }

    return makeConcatStrings(ATreverse(es2));
}
#endif


void backToString(yyscan_t scanner);
void backToIndString(yyscan_t scanner);


static Pos makeCurPos(YYLTYPE * loc, ParseData * data)
{
    Pos pos;
    pos.file = data->path;
    pos.line = loc->first_line;
    pos.column = loc->first_column;
    return pos;
}

#define CUR_POS makeCurPos(yylocp, data)


}


void yyerror(YYLTYPE * loc, yyscan_t scanner, ParseData * data, const char * error)
{
    data->error = (format("%1%, at `%2%':%3%:%4%")
        % error % data->path % loc->first_line % loc->first_column).str();
}


/* Make sure that the parse stack is scanned by the ATerm garbage
   collector. */
static void * mallocAndProtect(size_t size)
{
    void * p = malloc(size);
    if (p) ATprotectMemory(p, size);
    return p;
}

static void freeAndUnprotect(void * p)
{
    ATunprotectMemory(p);
    free(p);
}

#define YYMALLOC mallocAndProtect
#define YYFREE freeAndUnprotect


#endif


%}

%union {
  nix::Expr * e;
  nix::ExprList * list;
  nix::ExprAttrs * attrs;
  nix::Formals * formals;
  nix::Formal * formal;
  int n;
  char * id;
  char * path;
  char * uri;
  std::list<std::string> * ids;
}

%type <e> start expr expr_function expr_if expr_op
%type <e> expr_app expr_select expr_simple
%type <list> expr_list
%type <attrs> binds
%type <ts> attrpath string_parts ind_string_parts
%type <formals> formals
%type <formal> formal
%type <ids> ids
%token <id> ID ATTRPATH
%token <t> STR IND_STR
%token <n> INT
%token <path> PATH
%token <uri> URI
%token IF THEN ELSE ASSERT WITH LET IN REC INHERIT EQ NEQ AND OR IMPL
%token DOLLAR_CURLY /* == ${ */
%token IND_STRING_OPEN IND_STRING_CLOSE
%token ELLIPSIS

%nonassoc IMPL
%left OR
%left AND
%nonassoc EQ NEQ
%right UPDATE
%left NEG
%left '+'
%right CONCAT
%nonassoc '?'
%nonassoc '~'

%%

start: expr { data->result = $1; };

expr: expr_function;

expr_function
  : ID ':' expr_function
    { $$ = new ExprLambda(CUR_POS, $1, false, 0, $3); /* checkPatternVars(CUR_POS, $1); $$ = makeFunction($1, $3, CUR_POS); */ }
  | '{' formals '}' ':' expr_function
    { $$ = new ExprLambda(CUR_POS, "", true, $2, $5); }
  | '{' formals '}' '@' ID ':' expr_function
    { $$ = new ExprLambda(CUR_POS, $5, true, $2, $7); }
  | ID '@' '{' formals '}' ':' expr_function
    { $$ = new ExprLambda(CUR_POS, $1, true, $4, $7); }
  /* | ASSERT expr ';' expr_function
    { $$ = makeAssert($2, $4, CUR_POS); }
    */
  | WITH expr ';' expr_function
    { $$ = new ExprWith(CUR_POS, $2, $4); }
  | LET binds IN expr_function
    { $2->attrs["<let-body>"] = $4; $2->recursive = true; fixAttrs(*$2); $$ = new ExprSelect($2, "<let-body>"); }
  | expr_if
  ;

expr_if
  : IF expr THEN expr ELSE expr { $$ = new ExprIf($2, $4, $6); }
  | expr_op
  ;

expr_op
  : /* '!' expr_op %prec NEG { $$ = makeOpNot($2); }
       | */
    expr_op EQ expr_op { $$ = new ExprOpEq($1, $3); }
  | expr_op NEQ expr_op { $$ = new ExprOpNEq($1, $3); }
  | expr_op AND expr_op { $$ = new ExprOpAnd($1, $3); }
  | expr_op OR expr_op { $$ = new ExprOpOr($1, $3); }
  | expr_op IMPL expr_op { $$ = new ExprOpImpl($1, $3); }
  | expr_op UPDATE expr_op { $$ = new ExprOpUpdate($1, $3); }
  /*
  | expr_op '?' ID { $$ = makeOpHasAttr($1, $3); }
  */
  | expr_op '+' expr_op { $$ = new ExprOpConcatStrings($1, $3); }
  | expr_op CONCAT expr_op { $$ = new ExprOpConcatLists($1, $3); }
  | expr_app
  ;

expr_app
  : expr_app expr_select
    { $$ = new ExprApp($1, $2); }
  | expr_select { $$ = $1; }
  ;

expr_select
  : expr_select '.' ID
    { $$ = new ExprSelect($1, $3); }
  | expr_simple { $$ = $1; }
  ;

expr_simple
  : ID { $$ = new ExprVar($1); }
  | INT { $$ = new ExprInt($1); } /*
  | '"' string_parts '"' {
      /* For efficiency, and to simplify parse trees a bit. * /
      if ($2 == ATempty) $$ = makeStr(toATerm(""), ATempty);
      else if (ATgetNext($2) == ATempty) $$ = ATgetFirst($2);
      else $$ = makeConcatStrings(ATreverse($2));
  }
  | IND_STRING_OPEN ind_string_parts IND_STRING_CLOSE {
      $$ = stripIndentation(ATreverse($2));
  }
                                  */
  | PATH { $$ = new ExprPath(absPath($1, data->basePath)); }
  | URI { $$ = new ExprString($1); }
  | '(' expr ')' { $$ = $2; }
/*
  /* Let expressions `let {..., body = ...}' are just desugared
     into `(rec {..., body = ...}).body'. * /
  | LET '{' binds '}'
    { $$ = makeSelect(fixAttrs(true, $3), toATerm("body")); }
  */
  | REC '{' binds '}'
    { fixAttrs(*$3); $3->recursive = true; $$ = $3; }
  | '{' binds '}'
    { fixAttrs(*$2); $$ = $2; }
  | '[' expr_list ']' { $$ = $2; }
  ;

string_parts
  : string_parts STR { $$ = ATinsert($1, $2); }
  | string_parts DOLLAR_CURLY expr '}' { backToString(scanner); $$ = ATinsert($1, $3); }
  | { $$ = ATempty; }
  ;

ind_string_parts
  : ind_string_parts IND_STR { $$ = ATinsert($1, $2); }
  | ind_string_parts DOLLAR_CURLY expr '}' { backToIndString(scanner); $$ = ATinsert($1, $3); }
  | { $$ = ATempty; }
  ;

binds
  : binds ID '=' expr ';' { $$ = $1; $$->attrs[$2] = $4; }
  | binds INHERIT ids ';'
    { $$ = $1;
      foreach (list<string>::iterator, i, *$3)
        $$->inherited.push_back(*i);
    }
  | binds INHERIT '(' expr ')' ids ';'
    { $$ = $1;
      /* !!! Should ensure sharing of the expression in $4. */
      foreach (list<string>::iterator, i, *$6)
        $$->attrs[*i] = new ExprSelect($4, *i);
    }
  | { $$ = new ExprAttrs; }
  ;

ids
  : ids ID { $$ = $1; $1->push_back($2); /* !!! dangerous */ }
  | { $$ = new list<string>; }
  ;

attrpath
  : attrpath '.' ID { $$ = ATinsert($1, $3); }
  | ID { $$ = ATmakeList1($1); }
  ;

expr_list
  : expr_list expr_select { $$ = $1; $1->elems.push_back($2); /* !!! dangerous */ }
  | { $$ = new ExprList; }
  ;

formals
  : formal ',' formals
    { $$ = $3; $$->formals.push_front(*$1); /* !!! dangerous */ }
  | formal
    { $$ = new Formals; $$->formals.push_back(*$1); $$->ellipsis = false; }
  |
    { $$ = new Formals; $$->ellipsis = false; }
  | ELLIPSIS
    { $$ = new Formals; $$->ellipsis = true; }
  ;

formal
  : ID { $$ = new Formal($1, 0); }
  | ID '?' expr { $$ = new Formal($1, $3); }
  ;
  
%%


#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>


namespace nix {
      

static Expr * parse(const char * text, const Path & path, const Path & basePath)
{
    yyscan_t scanner;
    ParseData data;
    data.basePath = basePath;
    data.path = path;

    yylex_init(&scanner);
    yy_scan_string(text, scanner);
    int res = yyparse(scanner, &data);
    yylex_destroy(scanner);
    
    if (res) throw ParseError(data.error);

    try {
        // !!! checkVarDefs(state.primOps, data.result);
    } catch (Error & e) {
        throw ParseError(format("%1%, in `%2%'") % e.msg() % path);
    }
    
    return data.result;
}


Expr * parseExprFromFile(Path path)
{
    assert(path[0] == '/');

    /* If `path' is a symlink, follow it.  This is so that relative
       path references work. */
    struct stat st;
    while (true) {
        if (lstat(path.c_str(), &st))
            throw SysError(format("getting status of `%1%'") % path);
        if (!S_ISLNK(st.st_mode)) break;
        path = absPath(readLink(path), dirOf(path));
    }

    /* If `path' refers to a directory, append `/default.nix'. */
    if (stat(path.c_str(), &st))
        throw SysError(format("getting status of `%1%'") % path);
    if (S_ISDIR(st.st_mode))
        path = canonPath(path + "/default.nix");

    /* Read and parse the input file. */
    return parse(readFile(path).c_str(), path, dirOf(path));
}


Expr * parseExprFromString(const string & s, const Path & basePath)
{
    return parse(s.c_str(), "(string)", basePath);
}

 
}
