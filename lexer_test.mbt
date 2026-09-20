///| Black-box tests for the Rego lexer.

///|
fn lex_of(text : String) -> String {
  match tokenize(text) {
    Ok(tokens) => render_tokens(tokens)
    Err(e) => "ERR:" + e.render()
  }
}

///|
test "lexer: identifiers, keywords and numbers" {
  assert_eq(lex_of("allow"), "ident:allow eof")
  assert_eq(
    lex_of("package authz\nimport data.roles"),
    "ident:package ident:authz ident:import ident:data . ident:roles eof",
  )
  assert_eq(lex_of("1"), "num:1 eof")
  assert_eq(lex_of("1.5"), "num:1.5 eof")
  assert_eq(lex_of("1e3"), "num:1000 eof")
  assert_eq(lex_of("2.5e-2"), "num:0.025 eof")
}

///|
test "lexer: field access after an index keeps the dot" {
  // Regression guard: `0.field` must not be swallowed as the number `0.`
  assert_eq(lex_of("a[0].b"), "ident:a [ num:0 ] . ident:b eof")
  assert_eq(lex_of("1.foo"), "num:1 . ident:foo eof")
  assert_eq(lex_of("x.0"), "ident:x . num:0 eof")
}

///|
test "lexer: all operator tokens" {
  assert_eq(
    lex_of(":= = == != < <= > >= + - * / % & |"),
    ":= = == != < <= > >= + - * / % & | eof",
  )
}

///|
test "lexer: punctuation" {
  assert_eq(lex_of("( ) [ ] { } , : ;"), "( ) [ ] { } , : ; eof")
}

///|
test "lexer: strings with escapes" {
  assert_eq(lex_of("\"hi\""), "str:hi eof")
  assert_eq(lex_of("\"a\\nb\""), "str:a\nb eof")
  assert_eq(lex_of("\"\\u0041\""), "str:A eof")
  assert_eq(lex_of("\"q\\\"e\""), "str:q\"e eof")
}

///|
test "lexer: raw strings" {
  assert_eq(lex_of("`^a.*b$`"), "str:^a.*b$ eof")
  assert_eq(lex_of("`back\\slash`"), "str:back\\slash eof")
}

///|
test "lexer: comments are skipped" {
  assert_eq(
    lex_of("# leading\nallow # trailing\n  if {\n}"),
    "ident:allow ident:if { } eof",
  )
}

///|
test "lexer: tracks line and column" {
  match tokenize("allow\n  deny") {
    Ok(tokens) => {
      assert_eq(tokens[0].line, 1)
      assert_eq(tokens[0].column, 1)
      assert_eq(tokens[1].line, 2)
      assert_eq(tokens[1].column, 3)
    }
    Err(e) => assert_eq(e.render(), "expected tokens")
  }
}

///|
test "lexer: errors carry positions" {
  match tokenize("allow @ deny") {
    Ok(_) => assert_true(false)
    Err(e) => {
      assert_eq(e.kind.label(), "lex")
      assert_eq(e.line, 1)
      assert_eq(e.column, 7)
    }
  }
  match tokenize("\"unterminated") {
    Ok(_) => assert_true(false)
    Err(e) => assert_eq(e.kind.label(), "lex")
  }
  match tokenize("!") {
    Ok(_) => assert_true(false)
    Err(e) => assert_true(e.message.contains("!="))
  }
}
