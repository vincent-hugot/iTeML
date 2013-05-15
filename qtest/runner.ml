open OUnit;;

let ps,pl = print_string,print_endline
let va = Printf.sprintf
let pf = Printf.printf

let separator1 = String.make 79 '\\'
let separator2 = String.make 79 '/'

let string_of_path path =
  let path = List.filter (function Label _ -> true | _ -> false) path in
  String.concat ">" (List.rev_map string_of_node path)

let result_path = function
    | RSuccess path
    | RError (path, _)
    | RFailure (path, _)
    | RSkip (path, _)
    | RTodo (path, _) -> path

let result_msg = function
    | RSuccess _ -> "Success"
    | RError (_, msg)
    | RFailure (_, msg)
    | RSkip (_, msg)
    | RTodo (_, msg) -> msg

let result_flavour = function
    | RError _ -> "Error"
    | RFailure _ -> "Failure"
    | RSuccess _ -> "Success"
    | RSkip _ -> "Skip"
    | RTodo _ -> "Todo"

let not_success = function RSuccess _ -> false | _ -> true

let print_result_list =
  List.iter (fun result -> pf "%s\n%s: %s\n\n%s\n%s\n"
    separator1 (result_flavour result)
    (string_of_path (result_path result))
    (result_msg result) separator2)

(* Function which runs the given function and returns the running time
   of the function, and the original result in a tuple *)
let time_fun f x y =
  let begin_time = Unix.gettimeofday () in
    (Unix.gettimeofday () -. begin_time, f x y)

let run test =
  let _counter = ref (0,0,0) in (* Success, Failure, Other *)
  let total_tests = test_case_count test in
  let update = function
    | RSuccess _ -> let (s,f,o) = !_counter in _counter := (succ s,f,o)
    | RFailure _ -> let (s,f,o) = !_counter in _counter := (s,succ f,o)
    | _ -> let (s,f,o) = !_counter in _counter := (s,f, succ o)
  in
  let display_test ?(ended=false) p  = ps "\r";
    let (s,f,o) = !_counter in
    let cartouche = va " [%d%s%s / %d] " s
      (if f=0 then "" else va "+%d" f)
      (if o=0 then "" else va " %d!" o) total_tests
    and path = string_of_path p in
    let line = cartouche ^ path ^ (if ended then " *" else "") in
    let remaining = 79 - String.length line in
    let cover = if remaining > 0 then String.make remaining ' ' else "" in
    pf "%s%s%!" line cover;
  in
  let hdl_event = function
  | EStart p -> display_test p
  | EEnd p  -> display_test p ~ended:true
  | EResult result -> update result
  in
  ps "Running tests...";
  let running_time, results = time_fun perform_test hdl_event test in
  let (_s, f, o) = !_counter in
  let failures = List.filter not_success results in
(*  assert (List.length failures = f);*)
  ps "\r";
  print_result_list failures;
  assert (List.length results = total_tests);
  pf "Ran: %d tests in: %.2f seconds.%s\n"
    total_tests running_time (String.make 40 ' ');
  if failures = [] then pl "SUCCESS";
  if o <> 0 then pl "WARNING! SOME TESTS ARE NEITHER SUCCESSES NOR FAILURES!";
  (* create a meaningful return code for the process running the tests *)
  match f, o with
    | 0, 0 -> 0
    | _ -> 1

(* TAP-compatible test runner, in case we want to use a test harness *)

let run_tap test =
  let test_number = ref 0 in
  let handle_event = function
    | EStart _ | EEnd _ -> incr test_number
    | EResult (RSuccess p) ->
      pf "ok %d - %s\n%!" !test_number (string_of_path p)
    | EResult (RFailure (p,m)) ->
      pf "not ok %d - %s # %s\n%!" !test_number (string_of_path p) m
    | EResult (RError (p,m)) ->
      pf "not ok %d - %s # ERROR:%s\n%!" !test_number (string_of_path p) m
    | EResult (RSkip (p,m)) ->
      pf "not ok %d - %s # skip %s\n%!" !test_number (string_of_path p) m
    | EResult (RTodo (p,m)) ->
      pf "not ok %d - %s # todo %s\n%!" !test_number (string_of_path p) m
  in
  let total_tests = test_case_count test in
  pf "TAP version 13\n1..%d\n" total_tests;
  perform_test handle_event test
