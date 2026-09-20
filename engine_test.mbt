///| End-to-end tests for the engine, shaped like real policies.

///|
fn run(source : String, input : String, query : String) -> String {
  let policy = match Policy::compile(source) {
    Err(e) => return "COMPILE:" + e.render()
    Ok(p) => p
  }
  let bound = match policy.with_input_json(input) {
    Err(e) => return "COMPILE:" + e.render()
    Ok(p) => p
  }
  match bound.query(query) {
    Err(e) => "ERR:" + e.kind.label()
    Ok(None) => "undefined"
    Ok(Some(v)) => v.to_rego_string()
  }
}

///|
fn run_data(source : String, data : String, input : String, query : String) -> String {
  let policy = match Policy::compile(source) {
    Err(e) => return "COMPILE:" + e.render()
    Ok(p) => p
  }
  let with_data = match policy.with_data_json(data) {
    Err(e) => return "COMPILE:" + e.render()
    Ok(p) => p
  }
  let bound = match with_data.with_input_json(input) {
    Err(e) => return "COMPILE:" + e.render()
    Ok(p) => p
  }
  match bound.query(query) {
    Err(e) => "ERR:" + e.kind.label()
    Ok(None) => "undefined"
    Ok(Some(v)) => v.to_rego_string()
  }
}

// ---------------------------------------------------------------------------
// ACL
// ---------------------------------------------------------------------------

const ACL : String =
  #|package authz
  #|
  #|default allow := false
  #|
  #|allow if {
  #|  input.action == "read"
  #|  input.object == "data1"
  #|}

///|
test "engine: ACL allows the matching request" {
  assert_eq(run(ACL, "{\"action\":\"read\",\"object\":\"data1\"}", "allow"), "true")
}

///|
test "engine: ACL denies other requests via the default rule" {
  assert_eq(run(ACL, "{\"action\":\"write\",\"object\":\"data1\"}", "allow"), "false")
  assert_eq(run(ACL, "{\"action\":\"read\",\"object\":\"data2\"}", "allow"), "false")
  assert_eq(run(ACL, "{}", "allow"), "false")
}

// ---------------------------------------------------------------------------
// RBAC
// ---------------------------------------------------------------------------

const RBAC : String =
  #|package authz
  #|
  #|default allow := false
  #|
  #|allow if {
  #|  is_admin(input.user)
  #|}
  #|
  #|is_admin(user) if {
  #|  some role in roles_for(user)
  #|  role == "admin"
  #|}
  #|
  #|roles_for(user) := roles if {
  #|  some name, roles in data.roles
  #|  name == user
  #|}

const ROLES : String = "{\"roles\":{\"alice\":[\"admin\"],\"bob\":[\"dev\"]}}"

///|
test "engine: RBAC resolves a role through data" {
  assert_eq(run_data(RBAC, ROLES, "{\"user\":\"alice\"}", "allow"), "true")
  assert_eq(run_data(RBAC, ROLES, "{\"user\":\"bob\"}", "allow"), "false")
  assert_eq(run_data(RBAC, ROLES, "{\"user\":\"carol\"}", "allow"), "false")
}

///|
test "engine: a parameterised rule is callable directly" {
  assert_eq(run_data(RBAC, ROLES, "{}", "is_admin(\"alice\")"), "true")
  assert_eq(run_data(RBAC, ROLES, "{}", "is_admin(\"bob\")"), "undefined")
  assert_eq(run_data(RBAC, ROLES, "{}", "roles_for(\"alice\")"), "[\"admin\"]")
}

// ---------------------------------------------------------------------------
// Partial rules
// ---------------------------------------------------------------------------

const DENY_LIST : String =
  #|package authz
  #|
  #|deny contains reason if {
  #|  not input.authenticated
  #|  reason := "not authenticated"
  #|}
  #|
  #|deny contains reason if {
  #|  input.user == ""
  #|  reason := "no user"
  #|}

///|
test "engine: partial set rules accumulate across clauses" {
  assert_eq(
    run(DENY_LIST, "{\"authenticated\":false,\"user\":\"x\"}", "deny"),
    "{\"not authenticated\"}",
  )
  assert_eq(run(DENY_LIST, "{\"authenticated\":true,\"user\":\"\"}", "deny"), "{\"no user\"}")
  assert_eq(run(DENY_LIST, "{\"authenticated\":true,\"user\":\"x\"}", "deny"), "set()")
}

///|
test "engine: two reasons land in the same set" {
  assert_eq(
    run(DENY_LIST, "{\"authenticated\":false,\"user\":\"\"}", "deny"),
    "{\"no user\", \"not authenticated\"}",
  )
}

const TOTALS : String =
  #|package authz
  #|
  #|counts[name] := total if {
  #|  some name, total in data.totals
  #|}

///|
test "engine: partial object rules build a mapping" {
  assert_eq(
    run_data(TOTALS, "{\"totals\":{\"a\":1,\"b\":2}}", "{}", "counts"),
    "{\"a\": 1, \"b\": 2}",
  )
  assert_eq(
    run_data(TOTALS, "{\"totals\":{\"b\":2,\"a\":1}}", "{}", "counts.a"),
    "1",
  )
}

// ---------------------------------------------------------------------------
// Comprehensions and quantifiers
// ---------------------------------------------------------------------------

const AGGREGATES : String =
  #|package authz
  #|
  #|names := [n.name | some n in data.items]
  #|
  #|adults contains n.name if {
  #|  some n in data.items
  #|  n.age >= 18
  #|}
  #|
  #|by_name := {n.name: n.age | some n in data.items}
  #|
  #|all_adults if {
  #|  every n in data.items { n.age >= 18 }
  #|}
  #|
  #|any_adult if {
  #|  some n in data.items
  #|  n.age >= 18
  #|}

const ITEMS : String =
  "{\"items\":[{\"name\":\"a\",\"age\":20},{\"name\":\"b\",\"age\":10}]}"

///|
test "engine: array, set and object comprehensions" {
  assert_eq(run_data(AGGREGATES, ITEMS, "{}", "names"), "[\"a\", \"b\"]")
  assert_eq(run_data(AGGREGATES, ITEMS, "{}", "adults"), "{\"a\"}")
  assert_eq(run_data(AGGREGATES, ITEMS, "{}", "by_name"), "{\"a\": 20, \"b\": 10}")
}

///|
test "engine: every is universal, some is existential" {
  assert_eq(run_data(AGGREGATES, ITEMS, "{}", "all_adults"), "undefined")
  assert_eq(run_data(AGGREGATES, ITEMS, "{}", "any_adult"), "true")
  let all_grown =
    "{\"items\":[{\"name\":\"a\",\"age\":20},{\"name\":\"b\",\"age\":30}]}"
  assert_eq(run_data(AGGREGATES, all_grown, "{}", "all_adults"), "true")
}

// ---------------------------------------------------------------------------
// Matching helpers
// ---------------------------------------------------------------------------

const PREFIX_MATCH : String =
  #|package authz
  #|
  #|allow if {
  #|  some prefix in data.prefixes
  #|  startswith(input.path, prefix)
  #|}
  #|
  #|allow if {
  #|  regex.match(data.pattern, input.path)
  #|}

const PREFIX_DATA : String =
  "{\"prefixes\":[\"/public/\",\"/shared/\"],\"pattern\":\"^/public/.*$\"}"

///|
test "engine: startswith-based path matching" {
  assert_eq(
    run_data(PREFIX_MATCH, PREFIX_DATA, "{\"path\":\"/public/x\"}", "allow"),
    "true",
  )
  assert_eq(
    run_data(PREFIX_MATCH, PREFIX_DATA, "{\"path\":\"/shared/y\"}", "allow"),
    "true",
  )
  assert_eq(
    run_data(PREFIX_MATCH, PREFIX_DATA, "{\"path\":\"/private/x\"}", "allow"),
    "undefined",
  )
}

// ---------------------------------------------------------------------------
// Undefined vs false
// ---------------------------------------------------------------------------

const SPARSE : String =
  #|package authz
  #|
  #|a := 1
  #|
  #|b if {
  #|  a == 2
  #|}

///|
test "engine: undefined is distinct from false" {
  assert_eq(run(SPARSE, "{}", "a"), "1")
  assert_eq(run(SPARSE, "{}", "b"), "undefined")
  assert_eq(run(SPARSE, "{}", "nosuchrule"), "undefined")
  assert_eq(run(SPARSE, "{}", "data.authz.missing"), "undefined")
  assert_eq(run(SPARSE, "{}", "a == 1"), "true")
  assert_eq(run(SPARSE, "{}", "a == 2"), "false")
}

///|
test "engine: package_value collects every defined rule" {
  let policy = match Policy::compile(SPARSE) {
    Err(e) => return assert_eq(e.render(), "unexpected")
    Ok(p) => p
  }
  assert_true(policy.rule_names().length() == 2)
  let value = match policy.package_value() {
    Err(e) => return assert_eq(e.render(), "unexpected")
    Ok(v) => v
  }
  assert_eq(value.to_rego_string(), "{\"a\": 1}")
}

// ---------------------------------------------------------------------------
// Operators
// ---------------------------------------------------------------------------

const OPERATORS : String =
  #|package authz
  #|
  #|inter := {1, 2, 3} & {2, 3, 4}
  #|uni := {1, 2} | {3}
  #|diff := {1, 2, 3} - {2}
  #|concat := "a" + "b"
  #|arith := 2 + 3 * 4
  #|member if { 2 in [1, 2, 3] }
  #|key_member if { "a" in data.obj }
  #|nested := input.a.b[0]

///|
test "engine: set and string operators" {
  assert_eq(run(OPERATORS, "{\"a\":{\"b\":[\"x\"]}}", "inter"), "{2, 3}")
  assert_eq(run(OPERATORS, "{\"a\":{\"b\":[\"x\"]}}", "uni"), "{1, 2, 3}")
  assert_eq(run(OPERATORS, "{\"a\":{\"b\":[\"x\"]}}", "diff"), "{1, 3}")
  assert_eq(run(OPERATORS, "{\"a\":{\"b\":[\"x\"]}}", "concat"), "\"ab\"")
  assert_eq(run(OPERATORS, "{\"a\":{\"b\":[\"x\"]}}", "arith"), "14")
  assert_eq(run(OPERATORS, "{\"a\":{\"b\":[\"x\"]}}", "member"), "true")
  assert_eq(run(OPERATORS, "{\"a\":{\"b\":[\"x\"]}}", "nested"), "\"x\"")
}

///|
test "engine: matching on an object key uses data" {
  let policy = match Policy::compile(OPERATORS) {
    Err(e) => return assert_eq(e.render(), "unexpected")
    Ok(p) => p
  }
  let with_data = match policy.with_data_json("{\"obj\":{\"a\":1}}") {
    Err(e) => return assert_eq(e.render(), "unexpected")
    Ok(p) => p
  }
  assert_eq(
    match with_data.query("key_member") {
      Err(e) => "ERR:" + e.kind.label()
      Ok(None) => "undefined"
      Ok(Some(v)) => v.to_rego_string()
    },
    "true",
  )
}

// ---------------------------------------------------------------------------
// Error surfaces
// ---------------------------------------------------------------------------

///|
test "engine: rule conflicts are reported" {
  assert_eq(run("package a\np := 1\np := 2", "{}", "p"), "ERR:conflict")
}

///|
test "engine: division by zero is reported" {
  assert_eq(run("package a\np := 1 / 0", "{}", "p"), "ERR:divide-by-zero")
}

///|
test "engine: cyclic rules stop at the recursion limit" {
  assert_eq(run("package a\np := p", "{}", "p"), "ERR:safety")
}

///|
test "engine: type errors are reported" {
  assert_eq(run("package a\np := 1 + \"x\"", "{}", "p"), "ERR:type")
  assert_eq(run("package a\np if { true }", "{}", "count(p)"), "ERR:type")
}

///|
test "engine: parse errors carry positions" {
  let out = run("package a\nallow if {", "{}", "allow")
  assert_true(out.has_prefix("COMPILE:[parse]"))
  let bad = run("allow if { true }", "{}", "allow")
  assert_true(bad.has_prefix("COMPILE:[parse]"))
}

///|
test "engine: import aliases resolve into data" {
  let source =
    #|package authz
    #|
    #|import data.roles
    #|
    #|allow if {
    #|  some role in roles.alice
    #|  role == "admin"
    #|}
  assert_eq(run_data(source, ROLES, "{}", "allow"), "true")
}

///|
test "engine: methods on a rule that returns an object" {
  let source =
    #|package authz
    #|
    #|limits := {"read": 10}
    #|
    #|allow if {
    #|  input.n <= limits[input.action]
    #|}
  assert_eq(run(source, "{\"action\":\"read\",\"n\":5}", "allow"), "true")
  assert_eq(run(source, "{\"action\":\"read\",\"n\":50}", "allow"), "undefined")
}
