{
(*
 * qtest: quick unit tests: extract oUnit tests from OCaml components
 *
 *
 * Copyright 2012 Vincent Hugot and the "OCaml Batteries Included" team
 *
 *  vhugot.com ; batteries.forge.ocamlcore.org
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 *)

open Core;;
open Qparse;;

module B = Buffer;;
(** the do-it-all buffer; always clear *after* use *)
let buffy = B.create 80

(** register a raw metatest from the lexing buffer *)
let register_mtest lexbuf lexhead lexbod line kind =
  let header = metaheader_ lexhead lexbuf in
  let statements = lexbod lexbuf in
  Lexing.(
    register @@ Meta_test { kind; line ; header ;
    source = lexbuf.lex_curr_p.pos_fname; statements ;
  })

let lnumof lexbuf = Lexing.(lexbuf.lex_curr_p.pos_lnum)
let fileof lexbuf = Lexing.(lexbuf.lex_curr_p.pos_fname)
let info lb = fileof lb, lnumof lb

(** --shuffle option *)
let _shuffle = ref false
} (****************************************************************************)

let blank = [' ' '\t']
let lowercase = ['a'-'z' '\223'-'\246' '\248'-'\255' '_']
let uppercase = ['A'-'Z' '\192'-'\214' '\216'-'\222']
let identchar =
  ['A'-'Z' 'a'-'z' '_' '\192'-'\214' '\216'-'\246' '\248'-'\255' '\'' '0'-'9']
let symbolchar =
  ['!' '$' '%' '&' '*' '+' '-' '.' '/' ':' '<' '=' '>' '?' '@' '^' '|' '~']
let lident = lowercase identchar* | '(' blank* symbolchar+ blank* ')'
let uident = uppercase identchar*

(** extract tests from ml file *)
rule lexml t = parse
  (* test pragmas *)
  (****************)
| "(*$Q"  { (* quickcheck (random) test *)
  let lnum = lnumof lexbuf in
  register_mtest lexbuf lexheader (lexbody (succ lnum) buffy []) lnum Random  }
| "(*$T"  { (* simple test *)
  let lnum = lnumof lexbuf in
  register_mtest lexbuf lexheader (lexbody (succ lnum) buffy []) lnum Simple }
| "(*$="  { (* equality test *)
  let lnum = lnumof lexbuf in
  register_mtest lexbuf lexheader (lexbody (succ lnum) buffy []) lnum Equal }
| "(*$R"  { (* raw test *)
  let lnum = lnumof lexbuf in
  register_mtest lexbuf lexheader (lexbody_raw (succ lnum) buffy) lnum Raw }
  (* manipulation pragmas *)
  (************************)
| "(*$<" | "(*$begin:open" { (* local open *)
  let ctx = snip lexbuf (* save context for error reporting *)
  and modules = modules_ lexmodules lexbuf
  and loc_register m = register Env_begin; register @@ Open m
  in if (List.length modules > 1) then
    failwith @@ "\n" ^ ctx ^ "\nLocal open cannot take more than one module.";
  List.iter loc_register modules }
| "(*$>*)" | "(*$end:open*)" { register Env_close }
| "(*$open" { (* global open *)
  let modules = modules_ lexmodules lexbuf
  and glo_register m = register @@ Open m
  in List.iter glo_register modules }
| "(*${*)" | "(*$begin:inject*)" (* copy injection *)
  { lexinjectcp buffy lexbuf }
| "(*$inject" (* pure injection *)
  { lexinjectmv buffy lexbuf }
  (* error cases *)
  (***************)
| "(*$" { raise @@ Invalid_pragma (snip lexbuf) }
| "(*" (blank | '*')+ "$" [^'\n']* as y {
  let f,n = info lexbuf in
  epf "\nWarning: likely qtest syntax error: `%s' at %s:%d. " y f n }
| "(*"   { lexcomment 0 lexbuf }
| "\\\"" { }
| "'" "\\" _ "'" { }
| "'" _ "'" { }
| "\""   { lexstring lexbuf }
| '\n'   { eol lexbuf }
  (* others *)
| _ { } | eof {t()}

(** body of a test: simply extract lines *)
and lexbody ln b acc = parse
| "\\\n"  { eol lexbuf ; B.add_char b '\n'; lexbody ln b acc lexbuf  }
| [^'\n'] as c { B.add_char b c; lexbody ln b acc lexbuf }
| blank* '\n' {
  eol lexbuf; let code = B.contents b in B.clear b;
  lexbody Lexing.(lexbuf.lex_curr_p.pos_lnum) b ({ln ; code} :: acc) lexbuf }
| blank* "*)" { List.rev acc }
| "(*" { lexcomment 0 lexbuf ; lexbody ln b acc lexbuf }
| ([^'\n']#blank)* blank* '*'+ ")" as x
  { failwith ("runaway test body terminator: " ^ x) }
| eof { raise @@ Unterminated_test acc }

(** evacuate OCaml comments... *)
and lexcomment n  = parse
| "(*" { lexcomment (succ n) lexbuf }
| "\n" { eol lexbuf; lexcomment n lexbuf }
| "*)" { if n <= 0 then () else lexcomment (pred n) lexbuf }
| _    { lexcomment n lexbuf }
| eof  { epf "Warning: unterminated comment" }
(** ... and strings *)
and lexstring = parse
| "\\\"" { lexstring lexbuf }
| "\""   { }
| _      { lexstring lexbuf }
| eof    { epf "Warning: unterminated string" }

(** body of a raw test... everything until end comment *)
and lexbody_raw ln b = parse
| _ as c {
  if c = '\n' then eol lexbuf;
  B.add_char b c; lexbody_raw ln b lexbuf }
| '\n' blank* "*)" {
  eol lexbuf;
  let s = B.contents b in B.clear b; [{ln; code=s}]}

(** body of an injection pragma: copy *)
and lexinjectcp b = parse
| _ as c {
  if c = '\n' then eol lexbuf;
  B.add_char b c; lexinjectcp b lexbuf }
| "(*$}*)" | "(*$end:inject*)" {
   let code = B.contents b in B.clear b;
   register @@ Inject (info lexbuf,code) }

(** body of an injection pragma: move *)
and lexinjectmv b = parse
| _ as c {
  if c = '\n' then eol lexbuf;
  B.add_char b c; lexinjectmv b lexbuf }
| "*)" { (* note: the 2 spaces are for column numbers reporting *)
   let code = "  " ^ B.contents b in B.clear b;
   register @@ Inject (info lexbuf,code) }


(** prepare to parse test header *)
and lexheader = parse
| blank { lexheader lexbuf }
| ";" { SEMI }
| "[" { LBRACKET }
| "]" { RBRACKET }
| "as" { AS }
| "in" { IN }
| "forall" { FORALL }
| lident as x { ID x }
| "\\\n" { eol lexbuf ; lexheader lexbuf }
| "&"  ("" | [^'\n']*[^'\\' '\n'] as x) { PARAM (trim x) }
| '\n'   { eol lexbuf; EOF }
| eof  { failwith "unterminated header at end of file" }
| _ as c { raise @@ Bad_header_char((soc c), snip lexbuf) }

(** parse list of modules *)
and lexmodules = parse
| blank { lexmodules lexbuf }
| "," { COMMA }
| "*)"  { EOF  }  (* local open, closed later *)
| uident as x { UID x }
| _ as c { raise @@ Bad_modules_open_char (soc c) }

(**TODO: deal with strings and nested comments *)

{ (****************************************************************************)

(** register all the tests in source file, and register them in the suite *)
let extract_from pathin = Lexing.(
  epf "`%s' %!" pathin;
  let chanin = open_in pathin in
  let lexbuf = from_channel chanin in
  lexbuf.lex_curr_p <- {lexbuf.lex_curr_p with
    pos_fname = pathin; pos_lnum = 1;
  };
  (* getting the module *)
  let mod_name = Filename.(
    let fn_base = basename pathin in
    if not (check_suffix fn_base ".ml" || check_suffix fn_base ".mli") then
      (Printf.eprintf "File %S is not a ML module!\n%!" pathin ; exit 2);
    String.capitalize (chop_extension fn_base)
  ) in
  (* adding the file's pragmas to the suite *)
  register Env_begin; register (Open mod_name);
  exhaust lexml lexbuf; register Env_close;
  close_in chanin
)


(** Generate the test suite from files list on currently selected output *)
let generate paths =
  eps "Extraction : "; List.iter extract_from paths;
  out "let ___tests = ref []\nlet ___add test = ___tests := test::!___tests\n";
  out hard_coded_preamble;
  out (Buffer.contents global_preamble);
  suite := List.rev !suite; (* correct order (suite is built in reverse order) *)
  if !_shuffle then Shuffle.exec suite;
  listiteri process (preprocess !suite);
  out "let _ = exit (Runner.run (\"\" >::: List.rev !___tests))\n";
  eps "Done.\n"

(** Parse command line *)

let add_preamble code =
  Buffer.add_string global_preamble code;
  Buffer.add_string global_preamble "\n"  
let add_preamble_file path =
  let input = open_in path in
  Buffer.add_channel global_preamble input (in_channel_length input);
  close_in input
let set_output path =
  epf "Target file: `%s'. " path; outc := open_out path

let options = [
"-o",               Arg.String set_output, "";
"--output",         Arg.String set_output,
"<path>     (default: standard output)
Open or create a file for output; the resulting file will be an OCaml source file containing all the tests
";

"-p",               Arg.String add_preamble, "";
"--preamble",       Arg.String add_preamble,
"<string>   (default: empty)
Add code to the tests preamble; typically this will be an instruction of the form 'open Module;;'
";

"--preamble-file",  Arg.String add_preamble_file,
"<path>
Add the contents of the given file to the tests preamble
";

"--run-only",       Arg.String (fun s->Core._run_only := Some s),
"<function name>
Only generate tests pertaining to this function, as indicated by the test header
";

"--shuffle",        Arg.Unit (fun ()->toggle _shuffle; if !_shuffle then epf "!!! SHUFFLE is ON !!!\n"),
"           (default: turned off)
Toggle test execution order randomisation; submodules using injection are not shuffled";
]

let usage_msg =
(* OPTIONS: is here to mimick the pre-Arg behavior *)
"USAGE: qtest [options] extract <file.mli?>...

OPTIONS:"

let () =
  Random.self_init();
  let rev_anon_args = ref [] in
  let push_anon arg = (rev_anon_args := arg :: !rev_anon_args) in
  Arg.parse options push_anon usage_msg;
  match List.rev !rev_anon_args with
    | [] -> pl "qtest: use --help for usage notes."
    | "extract" :: paths -> generate paths
    | arg :: _ ->
      failwith @@ "bad arg: " ^ arg
}
