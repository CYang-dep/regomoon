///| Black-box tests for the Rego value model.

///|
test "value: set is sorted and deduplicated" {
  let s = make_set([
    Value::Number(3.0),
    Value::Number(1.0),
    Value::Number(2.0),
    Value::Number(1.0),
  ])
  assert_eq(s.to_rego_string(), "{1, 2, 3}")
}

///|
test "value: empty set renders as set()" {
  let s = make_set([])
  assert_eq(s.to_rego_string(), "set()")
}

///|
test "value: object is sorted by key and last write wins" {
  let o = make_object([
    ("b", Value::Number(2.0)),
    ("a", Value::Number(1.0)),
    ("b", Value::Number(9.0)),
  ])
  assert_eq(o.to_rego_string(), "{\"a\": 1, \"b\": 9}")
}

///|
test "value: type ordering follows OPA" {
  let ordered = [
    Value::Null,
    Value::Bool(false),
    Value::Bool(true),
    Value::Number(0.0),
    Value::String(""),
    Value::Array([]),
    make_object([]),
    make_set([]),
  ]
  let mut i = 0
  while i + 1 < ordered.length() {
    assert_true(ordered[i].compare(ordered[i + 1]) < 0)
    i = i + 1
  }
}

///|
test "value: structural equality" {
  assert_true(Value::Number(1.0).equals(Value::Number(1.0)))
  assert_false(Value::Number(1.0).equals(Value::String("1")))
  assert_true(make_set([Value::Number(1.0)]).equals(make_set([Value::Number(1.0)])))
  assert_false(
    make_set([Value::Number(1.0)]).equals(Value::Array([Value::Number(1.0)])),
  )
}

///|
test "value: field access and set membership" {
  let o = make_object([("user", Value::String("alice"))])
  let got = match o.get_field("user") {
    Some(v) => v.to_rego_string()
    None => "<none>"
  }
  assert_eq(got, "\"alice\"")
  assert_true(o.get_field("missing") is None)
  assert_true(make_set([Value::String("admin")]).set_contains(Value::String("admin")))
  assert_false(make_set([Value::String("admin")]).set_contains(Value::String("dev")))
}

///|
test "value: json rendering" {
  let o = make_object([
    ("n", Value::Number(2.0)),
    ("s", Value::String("he said \"hi\"\n")),
    ("a", Value::Array([Value::Bool(true), Value::Null])),
  ])
  assert_eq(
    o.to_json_string(),
    "{\"a\":[true,null],\"n\":2,\"s\":\"he said \\\"hi\\\"\\n\"}",
  )
}

///|
test "value: integral numbers have no fractional part" {
  assert_eq(Value::Number(3.0).to_rego_string(), "3")
  assert_eq(Value::Number(3.5).to_rego_string(), "3.5")
}

///|
test "value: type names" {
  assert_eq(Value::Null.type_name(), "null")
  assert_eq(Value::Bool(true).type_name(), "boolean")
  assert_eq(make_set([]).type_name(), "set")
  assert_eq(make_object([]).type_name(), "object")
}
