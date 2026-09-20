///| Black-box tests for strict JSON parsing.

///|
fn json_ok(text : String) -> String {
  match parse_json(text) {
    Ok(v) => v.to_json_string()
    Err(e) => "ERR:" + e.render()
  }
}

///|
test "json: scalars" {
  assert_eq(json_ok("null"), "null")
  assert_eq(json_ok("true"), "true")
  assert_eq(json_ok("false"), "false")
  assert_eq(json_ok("42"), "42")
  assert_eq(json_ok("-7"), "-7")
  assert_eq(json_ok("1.5"), "1.5")
  assert_eq(json_ok("1e3"), "1000")
  assert_eq(json_ok("1.5e2"), "150")
  assert_eq(json_ok("-2.5e-2"), "-0.025")
}

///|
test "json: strings and escapes" {
  assert_eq(json_ok("\"hi\""), "\"hi\"")
  assert_eq(json_ok("\"a\\nb\""), "\"a\\nb\"")
  assert_eq(json_ok("\"\\u0041\""), "\"A\"")
  assert_eq(json_ok("\"quote\\\"end\""), "\"quote\\\"end\"")
  assert_eq(json_ok("\"back\\\\slash\""), "\"back\\\\slash\"")
}

///|
test "json: arrays preserve order" {
  assert_eq(json_ok("[3,1,2]"), "[3,1,2]")
  assert_eq(json_ok("[]"), "[]")
  assert_eq(json_ok("[1,[2,[3]]]"), "[1,[2,[3]]]")
}

///|
test "json: objects are canonically ordered by key" {
  assert_eq(json_ok("{\"b\":2,\"a\":1}"), "{\"a\":1,\"b\":2}")
  assert_eq(json_ok("{}"), "{}")
  assert_eq(json_ok("{\"a\":{\"z\":1,\"y\":2}}"), "{\"a\":{\"y\":2,\"z\":1}}")
}

///|
test "json: duplicate keys, last write wins" {
  assert_eq(json_ok("{\"a\":1,\"a\":2}"), "{\"a\":2}")
}

///|
test "json: whitespace is insignificant" {
  assert_eq(json_ok("  {\n  \"a\" : [ 1 , 2 ]\n}  "), "{\"a\":[1,2]}")
}

///|
test "json: rejects malformed input" {
  assert_true(parse_json("{") is Err(_))
  assert_true(parse_json("[1,]") is Err(_))
  assert_true(parse_json("{\"a\":1,}") is Err(_))
  assert_true(parse_json("\"unterminated") is Err(_))
  assert_true(parse_json("") is Err(_))
  assert_true(parse_json("nul") is Err(_))
  assert_true(parse_json("{} extra") is Err(_))
  // strict RFC 8259: leading zeros are not allowed
  assert_true(parse_json("01") is Err(_))
  assert_true(parse_json("-01") is Err(_))
  // but a lone zero and a zero fraction are fine
  assert_eq(json_ok("0"), "0")
  assert_eq(json_ok("0.5"), "0.5")
}

///|
test "json: errors report a position" {
  match parse_json("{\"a\" 1}") {
    Ok(_) => assert_true(false)
    Err(e) => {
      assert_eq(e.kind.label(), "json")
      assert_true(e.line >= 1)
      assert_true(e.column >= 1)
    }
  }
}

///|
test "json: decimal parsing" {
  let one = match parse_decimal("1") {
    Some(d) => d == 1.0
    None => false
  }
  assert_true(one)
  let bad = parse_decimal("abc")
  assert_true(bad is None)
  let empty = parse_decimal("")
  assert_true(empty is None)
  let minus = parse_decimal("-0")
  assert_true(minus is Some(_))
}
