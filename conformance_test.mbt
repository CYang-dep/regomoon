///| A language-conformance suite.
///
/// Each case is a whole policy plus a query and the value the engine must
/// return. The cases follow the shapes documented by OPA's Rego reference and
/// builtin docs, so a behavioural drift from the upstream language shows up as
/// a failing row rather than as a surprise in someone's policy.

///|
fn conform(
  policy : String,
  data : String,
  input : String,
  query : String,
) -> String {
  run_data(policy, data, input, query)
}

///|
test "conformance: arithmetic, precedence and comparison" {
  assert_eq(conform("package t\np if { 1 + 1 == 2 }", "{}", "{}", "p"), "true")
  assert_eq(conform("package t\np := 2 * 3 + 4", "{}", "{}", "p"), "10")
  assert_eq(conform("package t\np := 10 / 4", "{}", "{}", "p"), "2.5")
  assert_eq(conform("package t\np := 10 % 3", "{}", "{}", "p"), "1")
  assert_eq(conform("package t\np := -(3 + 4)", "{}", "{}", "p"), "-7")
  assert_eq(
    conform("package t\np if { 1 < 2; 2 <= 2; 3 > 2; 3 >= 3 }", "{}", "{}", "p"),
    "true",
  )
  assert_eq(conform("package t\np if { 1 != 2 }", "{}", "{}", "p"), "true")
}

///|
test "conformance: references into nested documents" {
  assert_eq(
    conform("package t\np := input.a.b", "{}", "{\"a\":{\"b\":\"x\"}}", "p"),
    "\"x\"",
  )
  assert_eq(conform("package t\np := [1, 2, 3][1]", "{}", "{}", "p"), "2")
  assert_eq(
    conform(
      "package t\np := data.items[0].name", "{\"items\":[{\"name\":\"n\"}]}", "{}",
      "p",
    ),
    "\"n\"",
  )
  assert_eq(
    conform("package t\np := data.missing", "{}", "{}", "p"),
    "undefined",
  )
}

///|
test "conformance: membership, sets and operators" {
  assert_eq(
    conform(
      "package t\np if { \"b\" in input.keys }", "{}", "{\"keys\":[\"a\",\"b\"]}",
      "p",
    ),
    "true",
  )
  assert_eq(conform("package t\np := {1, 2} & {2, 3}", "{}", "{}", "p"), "{2}")
  assert_eq(
    conform("package t\np := {1, 2} | {2, 3}", "{}", "{}", "p"),
    "{1, 2, 3}",
  )
  assert_eq(
    conform("package t\np := {1, 2, 3} - {2}", "{}", "{}", "p"),
    "{1, 3}",
  )
}

///|
test "conformance: aggregation and string builtins" {
  assert_eq(conform("package t\np := count([1, 2, 3])", "{}", "{}", "p"), "3")
  assert_eq(conform("package t\np := sum([1, 2, 3])", "{}", "{}", "p"), "6")
  assert_eq(conform("package t\np := max([3, 1, 2])", "{}", "{}", "p"), "3")
  assert_eq(
    conform("package t\np := sort([3, 1, 2])", "{}", "{}", "p"),
    "[1, 2, 3]",
  )
  assert_eq(
    conform("package t\np := upper(\"abc\")", "{}", "{}", "p"),
    "\"ABC\"",
  )
  assert_eq(
    conform("package t\np := concat(\"-\", [\"a\", \"b\"])", "{}", "{}", "p"),
    "\"a-b\"",
  )
  assert_eq(
    conform("package t\np := split(\"a,b\", \",\")", "{}", "{}", "p"),
    "[\"a\", \"b\"]",
  )
  assert_eq(
    conform(
      "package t\np := startswith(\"/api/v1\", \"/api\")", "{}", "{}", "p",
    ),
    "true",
  )
  assert_eq(
    conform(
      "package t\np := object.get(input, \"missing\", \"dflt\")", "{}", "{}", "p",
    ),
    "\"dflt\"",
  )
  assert_eq(
    conform("package t\np := numbers.range(1, 3)", "{}", "{}", "p"),
    "[1, 2, 3]",
  )
}

///|
test "conformance: comprehensions" {
  assert_eq(
    conform("package t\np := [x | some x in [1, 2, 3]; x > 1]", "{}", "{}", "p"),
    "[2, 3]",
  )
  assert_eq(
    conform("package t\np := {x | some x in [1, 2, 2, 3]}", "{}", "{}", "p"),
    "{1, 2, 3}",
  )
  assert_eq(
    conform(
      "package t\np := {k: v | some k, v in input.obj}", "{}", "{\"obj\":{\"x\":1}}",
      "p",
    ),
    "{\"x\": 1}",
  )
}

///|
test "conformance: quantifiers, partial rules and defaults" {
  assert_eq(
    conform(
      "package t\np contains n if {\n  some n in data.nums\n}", "{\"nums\":[1,2]}",
      "{}", "p",
    ),
    "{1, 2}",
  )
  assert_eq(
    conform(
      "package t\np if {\n  every x in input.nums {\n    x > 0\n  }\n}", "{}", "{\"nums\":[1,2]}",
      "p",
    ),
    "true",
  )
  assert_eq(
    conform(
      "package t\ndefault p := false\n\np if {\n  input.ok\n}", "{}", "{}", "p",
    ),
    "false",
  )
  assert_eq(
    conform(
      "package t\np if {\n  not input.blocked\n}", "{}", "{\"blocked\":false}", "p",
    ),
    "true",
  )
}

///|
test "conformance: rules referencing rules, and with" {
  assert_eq(
    conform(
      "package t\nbase := 10\n\ndoubled := base * 2\n\np := doubled + 1", "{}", "{}",
      "p",
    ),
    "21",
  )
  assert_eq(
    conform(
      "package t\nq if {\n  input.a == 1\n}\n\np if {\n  q with input as {\"a\": 1}\n}",
      "{}", "{}", "p",
    ),
    "true",
  )
  assert_eq(
    conform(
      "package t\ndeny contains m if {\n  input.a == \"x\"\n  m := \"matched x\"\n}\n\nhas_x if {\n  count(deny) == 1\n}\n\np if {\n  has_x with input as {\"a\": \"x\"}\n}",
      "{}", "{}", "p",
    ),
    "true",
  )
}

///|
test "conformance: regex and json round-trip" {
  assert_eq(
    conform(
      "package t\np if {\n  regex.match(\"^a+$\", \"aaa\")\n}", "{}", "{}", "p",
    ),
    "true",
  )
  assert_eq(
    conform(
      "package t\np := json.unmarshal(json.marshal(input))", "{}", "{\"a\":[1,2]}",
      "p",
    ),
    "{\"a\": [1, 2]}",
  )
}
