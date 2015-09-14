(** Adapted from the Jane Street Capital Core quickcheck.ml,
    licensed as LGPL + linking exception *)
(** Module for easily generating unit tests.  Based on code posted by
    padiolea\@irisa.fr to the caml mailing list. *)

open Printf

module RS = Random.State

let rec foldn ~f ~init:acc i =
  if i = 0 then acc else foldn ~f ~init:(f acc i) (i-1)

let _opt_or ~d ~f = function
  | None -> d
  | Some x -> f x

let _opt_map ~f = function
  | None -> None
  | Some x -> Some (f x)

let _opt_map_2 ~f a b = match a, b with
  | Some x, Some y -> Some (f x y)
  | _ -> None

let _opt_map_3 ~f a b c = match a, b, c with
  | Some x, Some y, Some z -> Some (f x y z)
  | _ -> None

let sum_int = List.fold_left (+) 0

let (==>) b1 b2 = if b1 then b2 else true (* could use too => *)

module Gen = struct
  type 'a t = RS.t -> 'a

  let return x _st = x

  let (>>=) gen f st =
    f (gen st) st
end

let ug _st = ()

let bg st = RS.bool st

let fg st =
  exp (RS.float st 15. *. (if RS.float st 1. < 0.5 then 1. else -1.))
  *. (if RS.float st 1. < 0.5 then 1. else -1.)

let pfg st = abs_float (fg st)
let nfg st = -.(pfg st)

(* natural number generator *)
let nng st =
  let p = RS.float st 1. in
  if p < 0.5 then RS.int st 10
  else if p < 0.75 then RS.int st 100
  else if p < 0.95 then RS.int st 1_000
  else RS.int st 10_000

let neg_ig st = -(nng st)

(* Uniform random int generator *)
let upos =
  if Sys.word_size = 32 then
    fun st -> RS.bits st
  else (* word size = 64 *)
    fun st ->
      RS.bits st                        (* Bottom 30 bits *)
      lor (RS.bits st lsl 30)           (* Middle 30 bits *)
      lor ((RS.bits st land 3) lsl 60)  (* Top 2 bits *)  (* top bit = 0 *)

let uig st = if RS.bool st then - (upos st) - 1 else upos st

let random_binary_string st length =
  (* 0b011101... *)
  let s = Bytes.create (length + 2) in
  Bytes.set s 0 '0';
  Bytes.set s 1 'b';
  for i = 0 to length - 1 do
    Bytes.set s (i+2) (if RS.bool st then '0' else '1')
  done;
  Bytes.unsafe_to_string s

let ui32g st = Int32.of_string (random_binary_string st 32)
let ui64g st = Int64.of_string (random_binary_string st 64)

let lg_size size gen st =
  foldn ~f:(fun acc _ -> (gen st)::acc) ~init:[] (size st)
let lg gen st = lg_size nng gen st

let ag_size size gen st =
  Array.init (size st) (fun _ -> gen st)
let ag gen st = ag_size nng gen st

let pg gen1 gen2 st = (gen1 st, gen2 st)

let tg g1 g2 g3 st = (g1 st,g2 st, g3 st)


let cg st = char_of_int (RS.int st 255)

let printable_chars =
  let l = 126-32+1 in
  let s = Bytes.create l in
  for i = 0 to l-2 do
    Bytes.set s i (char_of_int (32+i))
  done;
  Bytes.set s (l-1) '\n';
  Bytes.unsafe_to_string s

let printable st = printable_chars.[RS.int st (String.length printable_chars)]
let numeral st = char_of_int (48 + RS.int st 10)

let sg_size ?(gen = cg) size st =
  let s = Bytes.create (size st) in
  for i = 0 to String.length s - 1 do
    Bytes.set s i (gen st)
  done;
  Bytes.unsafe_to_string s
let sg ?gen st = sg_size ?gen nng st


(* corner cases *)

let graft_corners gen corners () =
  let cors = ref corners in fun st ->
    match !cors with [] -> gen st
    | e::l -> cors := l; e

let nng_corners () = graft_corners nng [0;1;2;max_int] ()

(* Additional pretty-printers *)

let pp_list pp l = "[" ^ (String.concat "; " (List.map pp l)) ^ "]"
let pp_array pp l = "[|" ^ (String.concat "; " (Array.to_list (Array.map pp l))) ^ "|]"
let pp_pair p1 p2 (t1,t2) = "(" ^ p1 t1 ^ ", " ^ p2 t2 ^ ")"
let pp_triple p1 p2 p3 (t1,t2,t3) = "(" ^ p1 t1 ^ ", " ^ p2 t2 ^ ", " ^ p3 t3 ^ ")"



(* arbitrary instances *)

type 'a arbitrary = <
  gen: 'a Gen.t;
  print: ('a -> string) option; (** print values *)
  small: ('a -> int) option;  (** size of example *)
  shrink: ('a -> 'a list) option;  (** shrink to smaller examples *)
  collect: ('a -> string) option;  (** map value to tag, and group by tag *)

  set_print: ('a -> string) -> 'a arbitrary;
  set_small: ('a -> int) -> 'a arbitrary;
  set_shrink: ('a -> 'a list) -> 'a arbitrary;
  set_collect: ('a -> string) -> 'a arbitrary;
>

class ['a] base_arbitrary ?print ?small ?shrink ?collect gen = object
  method gen: 'a Gen.t = gen
  val _print : ('a -> string) option = print
  val _small : ('a -> int) option = small
  val _shrink : ('a -> 'a list) option = shrink
  val _collect : ('a -> string) option = collect
  method print = _print
  method small = _small
  method shrink = _shrink
  method collect = _collect

  method set_print f = {< _print = Some f >}
  method set_small f = {< _small = Some f >}
  method set_shrink f = {< _shrink = Some f >}
  method set_collect f = {< _collect = Some f >}
end

let set_small f o = o#set_small f
let set_print f o = o#set_print f
let set_shrink f o = o#set_shrink f
let set_collect f o = o#set_collect f


let small1 _ = 1
let shrink_nil _ = []

let make ?print ?small ?shrink ?collect gen =
  new base_arbitrary ?print ?small ?shrink ?collect gen

let make_scalar ?print ?collect gen =
  make ~shrink:shrink_nil ~small:small1 ?print ?collect gen

let adapt_ o gen =
  make ?print:o#print ?small:o#small ?shrink:o#shrink ?collect:o#collect gen

let choose l = match l with
  | [] -> raise (Invalid_argument "quickcheck.choose")
  | l ->
      let a = Array.of_list l in
      adapt_ a.(0)
        (fun st ->
          let arb = a.(RS.int st (Array.length a)) in
          arb#gen st)

let unit : unit arbitrary =
  make ~small:small1 ~shrink:shrink_nil ~print:(fun _ -> "()") ug

let bool = make_scalar ~print:string_of_bool bg
let float = make_scalar ~print:string_of_float fg
let pos_float = make_scalar ~print:string_of_float pfg
let neg_float = make_scalar ~print:string_of_float nfg

let int = make_scalar ~print:string_of_int uig
let pos_int = make_scalar ~print:string_of_int upos
let small_int = make_scalar ~print:string_of_int nng
let small_int_corners () = make_scalar ~print:string_of_int (nng_corners ())
let neg_int = make_scalar ~print:string_of_int neg_ig

let int32 = make_scalar ~print:(fun i -> Int32.to_string i ^ "l") ui32g
let int64 = make_scalar ~print:(fun i -> Int64.to_string i ^ "L") ui64g

let char = make_scalar ~print:(sprintf "%C") cg
let printable_char = make_scalar ~print:(sprintf "%C") printable
let numeral_char = make_scalar ~print:(sprintf "%C") numeral

let string_gen_of_size size gen =
  make ~small:String.length ~print:(sprintf "%S") (sg_size ~gen size)
let string_gen gen =
  make ~small:String.length ~print:(sprintf "%S") (sg ~gen)

let string = string_gen cg
let string_of_size size = string_gen_of_size size cg

let printable_string = string_gen printable
let printable_string_of_size size = string_gen_of_size size printable

let numeral_string = string_gen numeral
let numeral_string_of_size size = string_gen_of_size size numeral

let shrink_list_ l =
  let rec remove_one l r = match r with
    | [] -> []
    | x :: tail -> (List.rev_append l r) :: remove_one (x :: l) tail
  in
  remove_one [] l

let list_sum_ f l = List.fold_left (fun acc x-> f x+acc) 0 l

let list a =
  (* small sums sub-sizes if present, otherwise just length *)
  let small = _opt_or a#small ~f:list_sum_ ~d:List.length in
  let print = _opt_map a#print ~f:pp_list in
  make
    ~small
    ~shrink:shrink_list_
    ?print
    (lg a#gen)

let list_of_size size a =
  let small = _opt_or a#small ~f:list_sum_ ~d:List.length in
  let print = _opt_map a#print ~f:pp_list in
  make
    ~small
    ~shrink:shrink_list_
    ?print
    (lg_size size a#gen)

let array_sum_ f a = Array.fold_left (fun acc x -> f x+acc) 0 a

let shrink_array_ a =
  let b = Array.init (Array.length a)
    (fun i ->
      Array.init (Array.length a-1)
        (fun j -> if j<i then a.(j) else a.(j-1))
    ) in
  Array.to_list b

let array a =
  let small = _opt_or ~d:Array.length ~f:array_sum_ a#small in
  make
    ~small
    ~shrink:shrink_array_
    ?print:(_opt_map ~f:pp_array a#print)
    (ag a#gen)

let array_of_size size a =
  let small = _opt_or ~d:Array.length ~f:array_sum_ a#small in
  make
    ~small
    ~shrink:shrink_array_
    ?print:(_opt_map ~f:pp_array a#print)
    (ag_size size a#gen)

(* TODO: add shrinking *)

let pair a b =
  make
    ?small:(_opt_map_2 ~f:(fun f g (x,y) -> f x+g y) a#small b#small)
    ?print:(_opt_map_2 ~f:pp_pair a#print b#print)
    (pg a#gen b#gen)

let triple a b c =
  make
    ?small:(_opt_map_3 ~f:(fun f g h (x,y,z) -> f x+g y+h z) a#small b#small c#small)
    ?print:(_opt_map_3 ~f:pp_triple a#print b#print c#print)
    (tg a#gen b#gen c#gen)

let option a =
  let some_ x = Some x in
  let g f st =
    let p = RS.float st 1. in
    if p < 0.15 then None
    else Some (f st)
  and p f = function
    | None -> "None"
    | Some x -> "Some " ^ f x
  and small =
    _opt_or a#small ~d:(function None -> 0 | Some _ -> 1)
      ~f:(fun f o -> match o with None -> 0 | Some x -> f x)
  and shrink =
    _opt_map a#shrink
    ~f:(fun f o -> match o with None -> [] | Some x -> List.map some_ (f x))
  in
  make
    ~small
    ?shrink
    ?print:(_opt_map ~f:p a#print)
    (g a#gen)

(* TODO: explain black magic in this!! *)
let fun1 : 'a arbitrary -> 'b arbitrary -> ('a -> 'b) arbitrary =
  fun a1 a2 ->
    let magic_object = Obj.magic (object end) in
    let gen : ('a -> 'b) Gen.t = fun st ->
      let h = Hashtbl.create 10 in
      fun x ->
        if x == magic_object then
          Obj.magic h
        else
          try Hashtbl.find h x
          with Not_found ->
            let b = a2#gen st in
            Hashtbl.add h x b;
            b in
    let pp : (('a -> 'b) -> string) option = _opt_map_2 a1#print a2#print ~f:(fun p1 p2 f ->
      let h : ('a, 'b) Hashtbl.t = Obj.magic (f magic_object) in
      let b = Buffer.create 20 in
      Hashtbl.iter (fun key value -> Printf.bprintf b "%s -> %s; " (p1 key) (p2 value)) h;
      "{" ^ Buffer.contents b ^ "}"
    ) in
    make
      ?print:pp
      gen

let fun2 gp1 gp2 gp3 = fun1 gp1 (fun1 gp2 gp3)

(* Generator combinators *)

(** given a list, returns generator that picks at random from list *)
let oneofl ?print ?collect xs =
  let gen st = List.nth xs (Random.State.int st (List.length xs)) in
  make ?print ?collect gen

(** Given a list of generators, returns generator that randomly uses one of the generators
    from the list *)
let oneof l =
  let gens = List.map (fun a->a#gen) l in
  let gen st = List.nth gens (Random.State.int st (List.length gens)) st in
  let first = List.hd l in
  let print = first#print
  and small = first#small
  and collect = first#collect
  and shrink = first#shrink in
  make ?print ?small ?collect ?shrink gen

(** Generator that always returns given value *)
let always ?print x =
  let gen _st = x in
  make ?print gen

let gfreq l st =
  let sums = sum_int (List.map fst l) in
  let i = Random.State.int st sums in
  let rec aux acc = function
    | ((x,g)::xs) -> if i < acc+x then g else aux (acc+x) xs
    | _ -> failwith "frequency"
  in
  aux 0 l

(** Given list of [(frequency,value)] pairs, returns value with probability proportional
    to given frequency *)
let frequency ?print ?collect l =
  make ?print ?collect (gfreq l)

(** like frequency, but returns generator *)
let frequencyl l =
  let gen st = let a = gfreq l st in a#gen st in
  let first = snd (List.hd l) in
  make ?print:first#print ?collect:first#collect
    ?small:first#small ?shrink:first#shrink gen

let map ?rev f a =
  make
    ?print:(_opt_map_2 rev a#print ~f:(fun r p x -> p (r x)))
    ?small:(_opt_map_2 rev a#small ~f:(fun r s x -> s (r x)))
    ?shrink:(_opt_map_2 rev a#shrink ~f:(fun r g x -> List.map f @@ g (r x)))
    ?collect:(_opt_map_2 rev a#collect ~f:(fun r f x -> f (r x)))
    (fun st -> f (a#gen st))

let map_same_type f a =
  adapt_ a (fun st -> f (a#gen st))

(* Laws *)


(** [laws iter gen func] applies [func] repeatedly ([iter] times) on output of [gen], and
    if [func] ever returns false, then the input that caused the failure is returned
    optionally.  *)
let rec laws iter gen func st =
  if iter <= 0 then None
  else
    let input = gen st in
    try
      if not (func input) then Some input
      else laws (iter-1) gen func st
    with _ -> Some input

(** like [laws], but executes all tests anyway and returns optionally the
  smallest failure-causing input, wrt. some measure *)
let laws_smallest measure iter gen func st =
  let return = ref None in
  let register input =
    match !return with
    | None ->
      return := Some input
    | Some x ->
      if measure input < measure x then
      return := Some input
  in
  for _i = 1 to iter do
    let input = gen st in
    try if not (func input) then register input
    with _ -> register input
  done;
  !return

(* TODO: redefine [==>]; if assumption failed, try to generate new one
   but set limit to, say, 1000 *)

(* TODO: shrinking if available; otherwise use smallest if small defined *)

let default_count = 100

exception LawFailed of string

let no_print_ _ = "<no printer>"

(** Like laws, but throws an exception instead of returning an option.  *)
let laws_exn ?(count=default_count) name a func st =
  let result = match a#small with
  | None -> laws count a#gen func st
  | Some measure -> laws_smallest measure count a#gen func st
  in match result with
    | None -> ()
    | Some i ->
        let pp = match a#print with None -> no_print_ | Some x -> x in
        let msg = Printf.sprintf "law %s failed for %s" name (pp i) in
        raise (LawFailed msg)

let rec statistic_number = function
  | []    -> []
  | x::xs -> let (splitg, splitd) = List.partition (fun y -> y = x) xs in
    (1 + List.length splitg, x) :: statistic_number splitd

(* in percentage *)
let statistic xs =
  let stat_num = statistic_number xs in
  let totals = sum_int (List.map fst stat_num) in
  List.map (fun (i, v) -> ((i * 100) / totals), v) stat_num

(* TODO: expose in .mli? document *)
let laws2 iter func gen =
  let res = foldn ~init:[] iter
    ~f:(fun acc _ -> let n = gen () in (n, func n) :: acc)
  in
  let stat = statistic (List.map (fun (_, (_, v)) -> v) res) in
  let res = List.filter (fun (_, (b, _)) -> not b) res in
  if res = [] then (None, stat) else (Some (fst (List.hd res)), stat)
