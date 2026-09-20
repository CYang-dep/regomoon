///| Black-box tests for the builtin function library.

///|
fn jv(text : String) -> Value {
  match parse_json(text) {
    Ok(v) => v
    Err(_) => Value::Null
  }
}

///|
fn call(name : String, args : Array[Value]) -> String {
  match call_builtin(name, args) {
    None => "NOT_A_BUILTIN"
    Some(Ok(v)) => v.to_rego_string()
    Some(Err(e)) => "ERR:" + e.kind.label()
  }
}

///|
fn call1(name : String, text : String) -> String {
  call(name, [jv(text)])
}

///|
test "builtins: count over each collection type" {
  assert_eq(call1("count", "[1,2,3]"), "3")
  assert_eq(call1("count", "{\"a\":1,\"b\":2}"), "2")
  assert_eq(call1("count", "\"abc\""), "3")
  assert_eq(call1("count", "\"\""), "0")
  assert_eq(call("count", [make_set([])]), "0")
  assert_eq(call("count", [make_set([Value::Number(1.0)])]), "1")
}

///|
test "builtins: aggregation" {
  assert_eq(call1("sum", "[1,2,3]"), "6")
  assert_eq(call1("product", "[2,3,4]"), "24")
  assert_eq(call1("sum", "[]"), "0")
  assert_eq(call1("product", "[]"), "1")
  assert_eq(call1("max", "[3,1,2]"), "3")
  assert_eq(call1("min", "[3,1,2]"), "1")
  assert_eq(call1("sort", "[3,1,2]"), "[1, 2, 3]")
  assert_eq(
    call("sort", [make_set([Value::Number(3.0), Value::Number(1.0)])]),
    "[1, 3]",
  )
  assert_eq(call1("all", "[true,true]"), "true")
  assert_eq(call1("all", "[true,false]"), "false")
  assert_eq(call1("any", "[false,true]"), "true")
  assert_eq(call1("any", "[false]"), "false")
}

///|
test "builtins: aggregation type errors" {
  assert_eq(call1("sum", "[\"a\"]"), "ERR:type")
  assert_eq(call1("all", "[1]"), "ERR:type")
  assert_eq(call1("max", "[]"), "ERR:type")
}

///|
test "builtins: arithmetic rounding" {
  assert_eq(call1("abs", "-3"), "3")
  assert_eq(call1("abs", "3"), "3")
  assert_eq(call1("ceil", "1.2"), "2")
  assert_eq(call1("floor", "1.8"), "1")
  assert_eq(call1("round", "1.5"), "2")
}

///|
test "builtins: string functions" {
  assert_eq(call1("lower", "\"AB\""), "\"ab\"")
  assert_eq(call1("upper", "\"ab\""), "\"AB\"")
  assert_eq(call1("trim_space", "\"  a b  \""), "\"a b\"")
  assert_eq(call("trim", [jv("\"xxaxx\""), jv("\"x\"")]), "\"a\"")
  assert_eq(call("startswith", [jv("\"hello\""), jv("\"he\"")]), "true")
  assert_eq(call("endswith", [jv("\"hello\""), jv("\"lo\"")]), "true")
  assert_eq(call("contains", [jv("\"hello\""), jv("\"ell\"")]), "true")
  assert_eq(call("contains", [jv("\"hello\""), jv("\"zz\"")]), "false")
  assert_eq(
    call("split", [jv("\"a,b,c\""), jv("\",\"")]),
    "[\"a\", \"b\", \"c\"]",
  )
  assert_eq(call("concat", [jv("\"-\""), jv("[\"a\",\"b\"]")]), "\"a-b\"")
  assert_eq(
    call("replace", [jv("\"a-b\""), jv("\"-\""), jv("\"+\"")]),
    "\"a+b\"",
  )
  assert_eq(call("substring", [jv("\"hello\""), jv("1"), jv("3")]), "\"ell\"")
  assert_eq(call("substring", [jv("\"hello\""), jv("2"), jv("-1")]), "\"llo\"")
  assert_eq(call("indexof", [jv("\"hello\""), jv("\"l\"")]), "2")
  assert_eq(call("indexof", [jv("\"hello\""), jv("\"z\"")]), "-1")
}

///|
test "builtins: replace with an empty needle" {
  assert_eq(
    call("replace", [jv("\"ab\""), jv("\"\""), jv("\"-\"")]),
    "\"-a-b-\"",
  )
}

///|
test "builtins: sprintf" {
  assert_eq(call("sprintf", [jv("\"%v-%v\""), jv("[\"a\",3]")]), "\"a-3\"")
  assert_eq(call("sprintf", [jv("\"%d\""), jv("[7]")]), "\"7\"")
  assert_eq(call("sprintf", [jv("\"%.2f\""), jv("[1.5]")]), "\"1.50\"")
  assert_eq(call("sprintf", [jv("\"100%%\""), jv("[]")]), "\"100%\"")
}

///|
test "builtins: type predicates" {
  assert_eq(call1("type_name", "1"), "\"number\"")
  assert_eq(call1("type_name", "\"s\""), "\"string\"")
  assert_eq(call1("is_number", "1"), "true")
  assert_eq(call1("is_number", "\"1\""), "false")
  assert_eq(call1("is_string", "\"1\""), "true")
  assert_eq(call1("is_boolean", "true"), "true")
  assert_eq(call1("is_array", "[]"), "true")
  assert_eq(call1("is_object", "{}"), "true")
  assert_eq(call1("is_null", "null"), "true")
  assert_eq(call("is_set", [make_set([])]), "true")
}

///|
test "builtins: to_number" {
  assert_eq(call1("to_number", "\"42\""), "42")
  assert_eq(call1("to_number", "42"), "42")
  assert_eq(call1("to_number", "\"nope\""), "ERR:type")
}

///|
test "builtins: sets" {
  assert_eq(call("set", []), "set()")
  let a = make_set([Value::Number(1.0), Value::Number(2.0)])
  let b = make_set([Value::Number(2.0), Value::Number(3.0)])
  assert_eq(call("union", [Value::Array([a, b])]), "{1, 2, 3}")
  assert_eq(call("intersection", [Value::Array([a, b])]), "{2}")
  assert_eq(call("intersection", [Value::Array([a])]), "{1, 2}")
}

///|
test "builtins: arrays and objects" {
  assert_eq(call("array.concat", [jv("[1,2]"), jv("[3]")]), "[1, 2, 3]")
  assert_eq(call("object.get", [jv("{\"a\":1}"), jv("\"a\""), jv("0")]), "1")
  assert_eq(call("object.get", [jv("{\"a\":1}"), jv("\"z\""), jv("0")]), "0")
  assert_eq(call("object.keys", [jv("{\"b\":2,\"a\":1}")]), "{\"a\", \"b\"}")
  assert_eq(
    call("object.union", [jv("{\"a\":1}"), jv("{\"b\":2}")]),
    "{\"a\": 1, \"b\": 2}",
  )
}

///|
test "builtins: json codec" {
  assert_eq(
    call("json.marshal", [jv("{\"b\":2,\"a\":1}")]),
    "\"{\\\"a\\\":1,\\\"b\\\":2}\"",
  )
  assert_eq(call("json.unmarshal", [jv("\"[1,2]\"")]), "[1, 2]")
  assert_eq(call("json.unmarshal", [jv("\"not json\"")]), "ERR:json")
}

///|
test "builtins: regex" {
  assert_eq(call("regex.match", [jv("\"^a.*b$\""), jv("\"axxb\"")]), "true")
  assert_eq(call("regex.match", [jv("\"^a.*b$\""), jv("\"xaxx\"")]), "false")
  assert_eq(call("regex.is_valid", [jv("\"[a-z]+\"")]), "true")
  assert_eq(call("regex.is_valid", [jv("\"[\"")]), "false")
  assert_eq(call("regex.match", [jv("\"[\""), jv("\"x\"")]), "ERR:type")
}

///|
test "builtins: numbers.range" {
  assert_eq(call("numbers.range", [jv("1"), jv("3")]), "[1, 2, 3]")
  assert_eq(call("numbers.range", [jv("3"), jv("1")]), "[3, 2, 1]")
  assert_eq(call("numbers.range", [jv("1"), jv("1")]), "[1]")
}

///|
test "builtins: dispatch errors" {
  assert_eq(call("no_such_builtin", []), "NOT_A_BUILTIN")
  assert_eq(call1("count", "[]"), "0")
  // wrong arity
  assert_eq(call("count", []), "ERR:arity")
  // wrong argument type
  assert_eq(call1("lower", "1"), "ERR:type")
}

///|
test "builtins: is_builtin and arity table" {
  assert_true(is_builtin("count"))
  assert_true(is_builtin("regex.match"))
  assert_false(is_builtin("nope"))
  assert_true(builtin_arity("replace") is Some(3))
  assert_true(builtin_arity("set") is Some(0))
  assert_true(builtin_arity("nope") is None)
}

///|
test "builtins: object.remove and object.filter" {
  assert_eq(
    call("object.remove", [jv("{\"a\":1,\"b\":2,\"c\":3}"), jv("[\"b\"]")]),
    "{\"a\": 1, \"c\": 3}",
  )
  let keep = make_set([Value::String("a"), Value::String("c")])
  assert_eq(
    call("object.filter", [jv("{\"a\":1,\"b\":2,\"c\":3}"), keep]),
    "{\"a\": 1, \"c\": 3}",
  )
  assert_eq(call("object.remove", [jv("{\"a\":1}"), jv("[]")]), "{\"a\": 1}")
}

///|
test "builtins: array.slice follows OPA's negative-index rules" {
  assert_eq(call("array.slice", [jv("[1,2,3,4]"), jv("1"), jv("3")]), "[2, 3]")
  assert_eq(call("array.slice", [jv("[1,2,3,4]"), jv("-2"), jv("-1")]), "[3]")
  // stop is exclusive and a non-positive stop counts back from the end, so
  // slice(arr, 0, -1) drops the last element
  assert_eq(
    call("array.slice", [jv("[1,2,3,4]"), jv("0"), jv("-1")]),
    "[1, 2, 3]",
  )
  assert_eq(call("array.slice", [jv("[1,2,3]"), jv("2"), jv("1")]), "[]")
}

///|
test "builtins: trim_prefix and trim_suffix" {
  assert_eq(
    call("trim_prefix", [jv("\"/api/v1/x\""), jv("\"/api/v1\"")]),
    "\"/x\"",
  )
  assert_eq(call("trim_prefix", [jv("\"other\""), jv("\"/api\"")]), "\"other\"")
  assert_eq(
    call("trim_suffix", [jv("\"file.txt\""), jv("\".txt\"")]),
    "\"file\"",
  )
  assert_eq(call("trim_suffix", [jv("\"file\""), jv("\".txt\"")]), "\"file\"")
}

///|
test "builtins: numbers.range_step" {
  assert_eq(
    call("numbers.range_step", [jv("0"), jv("10"), jv("3")]),
    "[0, 3, 6, 9]",
  )
  assert_eq(
    call("numbers.range_step", [jv("10"), jv("0"), jv("-4")]),
    "[10, 6, 2]",
  )
  assert_eq(call("numbers.range_step", [jv("1"), jv("1"), jv("5")]), "[1]")
  assert_eq(call("numbers.range_step", [jv("0"), jv("1"), jv("0")]), "ERR:type")
}
