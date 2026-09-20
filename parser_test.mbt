///| Black-box tests for the Rego parser.

///|
fn show_module(text : String) -> String {
  match parse_module(text) {
    Ok(m) => {
      let parts : Array[String] = []
      parts.push("package " + render_path(m.package_path))
      for i in m.imports {
        parts.push("import " + render_path(i.path) + " as " + i.local_name)
      }
      for r in m.rules {
        parts.push(r.render())
      }
      join_strings(parts, " | ")
    }
    Err(e) => "ERR:" + e.render()
  }
}

///|
fn show_expr(text : String) -> String {
  match parse_expression(text) {
    Ok(e) => e.render()
    Err(err) => "ERR:" + err.render()
  }
}

///|
test "parser: package and imports" {
  assert_eq(show_module("package authz"), "package authz")
  assert_eq(show_module("package a.b.c"), "package a.b.c")
  assert_eq(
    show_module("package a\nimport data.roles\nimport data.users as u"),
    "package a | import data.roles as roles | import data.users as u",
  )
}

///|
test "parser: complete rules in both spellings" {
  assert_eq(
    show_module("package a\nallow if { true }"),
    "package a | allow if { true }",
  )
  assert_eq(
    show_module("package a\nallow { true }"),
    "package a | allow if { true }",
  )
  assert_eq(
    show_module("package a\nallow := true"),
    "package a | allow := true",
  )
  assert_eq(
    show_module("package a\ndefault allow := false"),
    "package a | default allow := false",
  )
}

///|
test "parser: partial set and partial object rules" {
  assert_eq(show_module("package a\np contains 1"), "package a | p contains 1")
  assert_eq(
    show_module("package a\np[x] := 1 if { x := 1 }"),
    "package a | p[x] := 1 if { (x := 1) }",
  )
  // pre-v1 partial set spelling
  assert_eq(
    show_module("package a\np[x] { x := 1 }"),
    "package a | p contains x if { (x := 1) }",
  )
}

///|
test "parser: multi-statement bodies" {
  assert_eq(
    show_module("package a\nallow if {\n  x := 1\n  y := 2\n  x < y\n}"),
    "package a | allow if { (x := 1); (y := 2); (x < y) }",
  )
  assert_eq(
    show_module("package a\nallow if { x := 1; y := 2 }"),
    "package a | allow if { (x := 1); (y := 2) }",
  )
}

///|
test "parser: operator precedence" {
  assert_eq(show_expr("1 + 2 * 3"), "(1 + (2 * 3))")
  assert_eq(show_expr("(1 + 2) * 3"), "((1 + 2) * 3)")
  assert_eq(show_expr("1 - 2 - 3"), "((1 - 2) - 3)")
  assert_eq(show_expr("a == b"), "(a == b)")
  assert_eq(show_expr("a = b"), "(a = b)")
  assert_eq(show_expr("a := b"), "(a := b)")
  assert_eq(show_expr("x in [1,2]"), "(x in [1, 2])")
  assert_eq(show_expr("a | b & c"), "(a | (b & c))")
  assert_eq(show_expr("1 + 2 == 3"), "((1 + 2) == 3)")
  assert_eq(show_expr("-x"), "-x")
  assert_eq(show_expr("-x + 1"), "(-x + 1)")
}

///|
test "parser: refs, fields, calls, literals" {
  assert_eq(show_expr("input.user"), "input.user")
  assert_eq(show_expr("data.roles[input.user]"), "data.roles[input.user]")
  assert_eq(show_expr("count(xs)"), "count(xs)")
  assert_eq(show_expr("split(s, \",\")"), "split(s, \",\")")
  assert_eq(show_expr("[1, 2, 3]"), "[1, 2, 3]")
  assert_eq(show_expr("[]"), "[]")
  assert_eq(show_expr("{}"), "{}")
  assert_eq(show_expr("{1, 2}"), "{1, 2}")
  assert_eq(show_expr("{\"a\": 1}"), "{\"a\": 1}")
  assert_eq(show_expr("null"), "null")
  assert_eq(show_expr("true"), "true")
  assert_eq(show_expr("1.5"), "1.5")
  assert_eq(show_expr("\"hi\""), "\"hi\"")
}

///|
test "parser: comprehensions" {
  assert_eq(show_expr("[x | x := 1]"), "[x | (x := 1)]")
  assert_eq(show_expr("{x | x := 1}"), "{x | (x := 1)}")
  assert_eq(show_expr("{k: v | k := 1; v := 2}"), "{k: v | (k := 1); (v := 2)}")
}

///|
test "parser: some, every, not" {
  assert_eq(
    show_module("package a\nallow if { some x, y }"),
    "package a | allow if { some x, y }",
  )
  assert_eq(
    show_module("package a\nallow if { some x in [1] }"),
    "package a | allow if { some x in [1] }",
  )
  assert_eq(
    show_module("package a\nallow if { every x in [1] { x > 0 } }"),
    "package a | allow if { every x in [1] { (x > 0) } }",
  )
  assert_eq(
    show_module("package a\nallow if { not false }"),
    "package a | allow if { not false }",
  )
}

///|
test "parser: comments and blank lines" {
  assert_eq(
    show_module(
      "# header\npackage a\n\n# a rule\nallow if { true } # trailing\n",
    ),
    "package a | allow if { true }",
  )
}

///|
test "parser: real-world shaped policy" {
  let policy =
    #|package authz
    #|
    #|import data.roles
    #|
    #|default allow := false
    #|
    #|allow if {
    #|  input.action == "read"
    #|  is_member(input.user)
    #|}
    #|
    #|is_member(user) if {
    #|  some role in roles_for(user)
    #|  role == "admin"
    #|}
    #|
    #|roles_for(user) := roles if {
    #|  some user, roles in data.roles
    #|}
    #|
    #|deny contains msg if {
    #|  not is_member(input.user)
    #|  msg := "not a member"
    #|}
  let shown = show_module(policy)
  assert_true(shown.contains("default allow := false"))
  assert_true(shown.contains("allow if {"))
  assert_true(shown.contains("is_member(user)"))
  assert_true(shown.contains("deny contains msg if {"))
  assert_false(shown.has_prefix("ERR"))
}

///|
test "parser: errors" {
  // a module must declare a package
  assert_true(show_module("allow if { true }").has_prefix("ERR:["))
  // unsupported statement modifier gets a compile error, not a parse error
  match parse_module("package a\nallow if { true with input as {} }") {
    Ok(_) => assert_true(false)
    Err(e) => {
      assert_eq(e.kind.label(), "compile")
      assert_true(e.message.contains("with"))
    }
  }
  // structural errors carry positions
  match parse_module("package a\nallow if {") {
    Ok(_) => assert_true(false)
    Err(e) => {
      assert_eq(e.kind.label(), "parse")
      assert_true(e.line > 0)
    }
  }
}
