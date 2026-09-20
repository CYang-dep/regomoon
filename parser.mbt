///| The Rego parser: a recursive-descent parser with precedence climbing for
/// binary operators.
///
/// Operator precedence, lowest to highest, follows OPA:
///
/// | level | operators |
/// | --- | --- |
/// | 1 | `:=`, `=` |
/// | 2 | `\|` (set union) |
/// | 3 | `&` (set intersection) |
/// | 4 | `==`, `!=`, `<`, `<=`, `>`, `>=`, `in` |
/// | 5 | `+`, `-` |
/// | 6 | `*`, `/`, `%` |

///|
/// Punctuation classes, used so the parser can test for a symbol without
/// having to match a payload-carrying [TokenKind] every time.
priv enum Punct {
  LParen
  RParen
  LBrace
  RBrace
  LBracket
  RBracket
  Comma
  Colon
  Semicolon
  Dot
  Pipe
  Amp
  Assign
  Unify
  Eq
  Neq
  Lt
  Le
  Gt
  Ge
  Plus
  Minus
  Star
  Slash
  Percent
  Eof
  Other
} derive(Eq)

///|
fn punct_of(k : TokenKind) -> Punct {
  match k {
    TokenKind::TokIdent(_) => Punct::Other
    TokenKind::TokNumber(_) => Punct::Other
    TokenKind::TokString(_) => Punct::Other
    TokenKind::TokLParen => Punct::LParen
    TokenKind::TokRParen => Punct::RParen
    TokenKind::TokLBrace => Punct::LBrace
    TokenKind::TokRBrace => Punct::RBrace
    TokenKind::TokLBracket => Punct::LBracket
    TokenKind::TokRBracket => Punct::RBracket
    TokenKind::TokComma => Punct::Comma
    TokenKind::TokColon => Punct::Colon
    TokenKind::TokSemicolon => Punct::Semicolon
    TokenKind::TokDot => Punct::Dot
    TokenKind::TokPipe => Punct::Pipe
    TokenKind::TokAmp => Punct::Amp
    TokenKind::TokAssign => Punct::Assign
    TokenKind::TokUnify => Punct::Unify
    TokenKind::TokEq => Punct::Eq
    TokenKind::TokNeq => Punct::Neq
    TokenKind::TokLt => Punct::Lt
    TokenKind::TokLe => Punct::Le
    TokenKind::TokGt => Punct::Gt
    TokenKind::TokGe => Punct::Ge
    TokenKind::TokPlus => Punct::Plus
    TokenKind::TokMinus => Punct::Minus
    TokenKind::TokStar => Punct::Star
    TokenKind::TokSlash => Punct::Slash
    TokenKind::TokPercent => Punct::Percent
    TokenKind::TokEof => Punct::Eof
  }
}

///|
priv struct Parser {
  tokens : Array[Token]
  mut pos : Int
}

///|
/// Parse a complete Rego module.
pub fn parse_module(text : String) -> Result[Module, RegoError] {
  match tokenize(text) {
    Err(e) => Err(e)
    Ok(tokens) => {
      let parser : Parser = { tokens, pos: 0 }
      parser.parse_module()
    }
  }
}

///|

///|
/// Parse a top-level query, optionally carrying a `with input as ...` modifier.
pub fn parse_query(text : String) -> Result[Query, RegoError] {
  match tokenize(text) {
    Err(e) => Err(e)
    Ok(tokens) => {
      let parser : Parser = { tokens, pos: 0 }
      parser.parse_query()
    }
  }
}

///|
/// The method body of [parse_query].
fn Parser::parse_query(self : Parser) -> Result[Query, RegoError] {
  let expr = match self.parse_expr(0) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if !self.at_ident("with") {
    if !self.at(Punct::Eof) {
      return Err(self.err("unexpected trailing content after expression"))
    }
    return Ok(Query::Plain(expr))
  }
  let mods = match self.parse_with_mods() {
    Err(e) => return Err(e)
    Ok(m) => m
  }
  if mods.length() != 1 {
    return Err(self.compile_error("chained `with` modifiers are not supported"))
  }
  let only = mods[0]
  if only.0.length() != 1 || only.0[0] != "input" {
    return Err(
      self.compile_error(
        "only `with input as ...` is supported, not `with " +
        render_path(only.0) +
        " as ...`",
      ),
    )
  }
  if !self.at(Punct::Eof) {
    return Err(self.err("unexpected trailing content after expression"))
  }
  Ok(Query::WithInput(expr, only.1))
}

///|
/// Parse a standalone expression, useful for testing and for `input`-only use.
pub fn parse_expression(text : String) -> Result[Expr, RegoError] {
  match tokenize(text) {
    Err(e) => Err(e)
    Ok(tokens) => {
      let parser : Parser = { tokens, pos: 0 }
      let expr = match parser.parse_expr(0) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      if !parser.at(Punct::Eof) {
        return Err(parser.err("unexpected trailing content after expression"))
      }
      Ok(expr)
    }
  }
}

///|
fn Parser::cur(self : Parser) -> Token {
  if self.pos < self.tokens.length() {
    self.tokens[self.pos]
  } else {
    { kind: TokenKind::TokEof, line: 0, column: 0 }
  }
}

///|
fn Parser::at(self : Parser, p : Punct) -> Bool {
  punct_of(self.cur().kind) == p
}

///|
fn Parser::at_ident(self : Parser, name : String) -> Bool {
  match self.cur().kind {
    TokenKind::TokIdent(s) => s == name
    _ => false
  }
}

///|
fn Parser::err(self : Parser, message : String) -> RegoError {
  let t = self.cur()
  RegoError::at(RegoErrorKind::ParseError, message, t.line, t.column)
}

///|
fn Parser::advance(self : Parser) -> Unit {
  if self.pos < self.tokens.length() {
    self.pos = self.pos + 1
  }
}

///|
fn Parser::expect(
  self : Parser,
  p : Punct,
  what : String,
) -> Result[Unit, RegoError] {
  if self.at(p) {
    self.advance()
    Ok(())
  } else {
    Err(
      self.err("expected " + what + " but found " + self.cur().kind.describe()),
    )
  }
}

///|
fn Parser::expect_ident(
  self : Parser,
  what : String,
) -> Result[String, RegoError] {
  match self.cur().kind {
    TokenKind::TokIdent(s) => {
      self.advance()
      Ok(s)
    }
    _ =>
      Err(
        self.err(
          "expected " + what + " but found " + self.cur().kind.describe(),
        ),
      )
  }
}

// ---------------------------------------------------------------------------
// Module structure
// ---------------------------------------------------------------------------

///|
fn Parser::parse_module(self : Parser) -> Result[Module, RegoError] {
  if !self.at_ident("package") {
    return Err(self.err("a module must start with a `package` declaration"))
  }
  self.advance()
  let package_path = match self.parse_path() {
    Err(e) => return Err(e)
    Ok(p) => p
  }
  let imports : Array[ImportDecl] = []
  while self.at_ident("import") {
    match self.parse_import() {
      Err(e) => return Err(e)
      Ok(i) => imports.push(i)
    }
  }
  let rules : Array[Rule] = []
  while !self.at(Punct::Eof) {
    match self.parse_rule() {
      Err(e) => return Err(e)
      Ok(r) => rules.push(r)
    }
  }
  Ok({ package_path, imports, rules })
}

///|
fn Parser::parse_path(self : Parser) -> Result[Array[String], RegoError] {
  let segments : Array[String] = []
  let first = match self.expect_ident("a path segment") {
    Err(e) => return Err(e)
    Ok(s) => s
  }
  segments.push(first)
  while self.at(Punct::Dot) {
    self.advance()
    let next = match self.expect_ident("a path segment after `.`") {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    segments.push(next)
  }
  Ok(segments)
}

///|
fn Parser::parse_import(self : Parser) -> Result[ImportDecl, RegoError] {
  self.advance()
  let path = match self.parse_path() {
    Err(e) => return Err(e)
    Ok(p) => p
  }
  let local_name = if self.at_ident("as") {
    self.advance()
    match self.expect_ident("an import alias") {
      Err(e) => return Err(e)
      Ok(s) => s
    }
  } else {
    path_last(path)
  }
  Ok({ path, local_name })
}

// ---------------------------------------------------------------------------
// Rules
// ---------------------------------------------------------------------------

///|
fn Parser::parse_rule(self : Parser) -> Result[Rule, RegoError] {
  let start = self.cur()
  let is_default = self.at_ident("default")
  if is_default {
    self.advance()
  }
  let name = match self.expect_ident("a rule name") {
    Err(e) => return Err(e)
    Ok(s) => s
  }
  // A parameterised rule head, e.g. `is_member(user) if { ... }`.
  let args : Array[String] = []
  if self.at(Punct::LParen) {
    self.advance()
    while !self.at(Punct::RParen) && !self.at(Punct::Eof) {
      let param = match self.expect_ident("a rule parameter name") {
        Err(e) => return Err(e)
        Ok(s) => s
      }
      args.push(param)
      if self.at(Punct::Comma) {
        self.advance()
      }
    }
    match self.expect(Punct::RParen, "`)` to close the rule parameters") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  let mut kind = RuleKind::CompleteRule
  let mut key : Expr? = None
  let mut value : Expr? = None
  if is_default {
    match self.expect(Punct::Assign, "`:=` after `default`") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let v = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    value = Some(v)
  } else if self.at_ident("contains") {
    self.advance()
    kind = RuleKind::PartialSetRule
    let v = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    value = Some(v)
  } else if self.at(Punct::Assign) {
    self.advance()
    let v = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    value = Some(v)
  } else if self.at(Punct::Unify) {
    // Pre-v1 spelling: `allow = true { ... }`
    self.advance()
    let v = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    value = Some(v)
  } else if self.at(Punct::LBracket) {
    self.advance()
    let k = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    key = Some(k)
    match self.expect(Punct::RBracket, "`]` after a rule key") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    if self.at(Punct::Assign) {
      self.advance()
      kind = RuleKind::PartialObjectRule
      let v = match self.parse_expr(0) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      value = Some(v)
    } else {
      // Pre-v1 partial set rule: `roles[user] { ... }`. The key doubles as the
      // set element, so the head value is the key expression.
      kind = RuleKind::PartialSetRule
      value = Some(k)
    }
  }
  let body = match self.parse_optional_body() {
    Err(e) => return Err(e)
    Ok(b) => b
  }
  Ok({
    name,
    args,
    key,
    value,
    kind,
    body,
    is_default,
    line: start.line,
    column: start.column,
  })
}

///|
/// Parse a rule body. Rego v1 introduces it with `if`; the pre-v1 spelling
/// is a bare `{` block. A rule with neither has an empty body.
fn Parser::parse_optional_body(self : Parser) -> Result[Array[Stmt], RegoError] {
  if self.at_ident("if") {
    self.advance()
    match self.expect(Punct::LBrace, "`{` after `if`") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let body = match self.parse_body(Punct::RBrace) {
      Err(e) => return Err(e)
      Ok(b) => b
    }
    match self.expect(Punct::RBrace, "`}` to close the rule body") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    Ok(body)
  } else if self.at(Punct::LBrace) {
    self.advance()
    let body = match self.parse_body(Punct::RBrace) {
      Err(e) => return Err(e)
      Ok(b) => b
    }
    match self.expect(Punct::RBrace, "`}` to close the rule body") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    Ok(body)
  } else {
    Ok([])
  }
}

// ---------------------------------------------------------------------------
// Bodies and statements
// ---------------------------------------------------------------------------

///|
fn Parser::parse_body(
  self : Parser,
  closer : Punct,
) -> Result[Array[Stmt], RegoError] {
  let stmts : Array[Stmt] = []
  while !self.at(closer) && !self.at(Punct::Eof) {
    let before = self.pos
    match self.parse_stmt() {
      Err(e) => return Err(e)
      Ok(s) => stmts.push(s)
    }
    if self.at(Punct::Semicolon) {
      self.advance()
    }
    if self.pos == before {
      return Err(self.err("could not parse a statement here"))
    }
  }
  Ok(stmts)
}

///|
fn Parser::parse_stmt(self : Parser) -> Result[Stmt, RegoError] {
  if self.at_ident("some") {
    self.advance()
    let names : Array[String] = []
    let first = match self.expect_ident("a variable name after `some`") {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    names.push(first)
    while self.at(Punct::Comma) {
      self.advance()
      let next = match self.expect_ident("a variable name after `,`") {
        Err(e) => return Err(e)
        Ok(s) => s
      }
      names.push(next)
    }
    if self.at_ident("in") {
      self.advance()
      let collection = match self.parse_expr(0) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      return self.finish_stmt(Stmt::SomeIn(names, collection))
    }
    return self.finish_stmt(Stmt::SomeVars(names))
  }
  if self.at_ident("every") {
    self.advance()
    let names : Array[String] = []
    let first = match self.expect_ident("a variable name after `every`") {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    names.push(first)
    while self.at(Punct::Comma) {
      self.advance()
      let next = match self.expect_ident("a variable name after `,`") {
        Err(e) => return Err(e)
        Ok(s) => s
      }
      names.push(next)
    }
    if !self.at_ident("in") {
      return Err(self.err("expected `in` after the `every` variables"))
    }
    self.advance()
    let collection = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    match self.expect(Punct::LBrace, "`{` to open the `every` body") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let body = match self.parse_body(Punct::RBrace) {
      Err(e) => return Err(e)
      Ok(b) => b
    }
    match self.expect(Punct::RBrace, "`}` to close the `every` body") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    return self.finish_stmt(Stmt::Every(names, collection, body))
  }
  if self.at_ident("not") {
    self.advance()
    let inner = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    return self.finish_expr_stmt(inner, true)
  }
  let expr = match self.parse_expr(0) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  self.finish_expr_stmt(expr, false)
}

///|
/// Assemble a statement from a parsed expression, attaching `with` modifiers.
///
/// Only the `input` document can be replaced, and a statement may carry at most
/// one modifier. `with data.x as ...` and chained modifiers are compile errors
/// rather than silent misbehaviour.
fn Parser::finish_expr_stmt(
  self : Parser,
  expr : Expr,
  negate : Bool,
) -> Result[Stmt, RegoError] {
  if !self.at_ident("with") {
    return Ok(if negate { Stmt::Negate(expr) } else { Stmt::Test(expr) })
  }
  let mods = match self.parse_with_mods() {
    Err(e) => return Err(e)
    Ok(m) => m
  }
  if mods.length() != 1 {
    return Err(self.compile_error("chained `with` modifiers are not supported"))
  }
  let only = mods[0]
  if only.0.length() != 1 || only.0[0] != "input" {
    return Err(
      self.compile_error(
        "only `with input as ...` is supported, not `with " +
        render_path(only.0) +
        " as ...`",
      ),
    )
  }
  Ok(
    if negate {
      Stmt::NegateWithInput(expr, only.1)
    } else {
      Stmt::WithInput(expr, only.1)
    },
  )
}

///|
/// Parse one or more `with <path> as <expr>` modifiers.
fn Parser::parse_with_mods(
  self : Parser,
) -> Result[Array[(Array[String], Expr)], RegoError] {
  let mods : Array[(Array[String], Expr)] = []
  while self.at_ident("with") {
    self.advance()
    let path = match self.parse_path() {
      Err(e) => return Err(e)
      Ok(p) => p
    }
    if !self.at_ident("as") {
      return Err(self.err("expected `as` after the `with` target"))
    }
    self.advance()
    let value = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    mods.push((path, value))
  }
  Ok(mods)
}

///|
/// A compile error located at the current token.
fn Parser::compile_error(self : Parser, message : String) -> RegoError {
  RegoError::at(
    RegoErrorKind::CompileError,
    message,
    self.cur().line,
    self.cur().column,
  )
}

///|
/// Reject the one statement modifier this engine does not implement, so that
/// the failure is a clear compile error rather than a confusing parse error.
fn Parser::finish_stmt(self : Parser, stmt : Stmt) -> Result[Stmt, RegoError] {
  if self.at_ident("with") {
    return Err(
      RegoError::at(
        RegoErrorKind::CompileError,
        "`with` after `some` or `every` is not supported",
        self.cur().line,
        self.cur().column,
      ),
    )
  }
  Ok(stmt)
}

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

///|
/// The binary operator at the cursor, if any, with its precedence level.
fn Parser::binary_op(self : Parser) -> (String, Int)? {
  if self.at_ident("in") {
    return Some(("in", 4))
  }
  match punct_of(self.cur().kind) {
    Punct::Assign => Some((":=", 1))
    Punct::Unify => Some(("=", 1))
    Punct::Pipe => Some(("|", 2))
    Punct::Amp => Some(("&", 3))
    Punct::Eq => Some(("==", 4))
    Punct::Neq => Some(("!=", 4))
    Punct::Lt => Some(("<", 4))
    Punct::Le => Some(("<=", 4))
    Punct::Gt => Some((">", 4))
    Punct::Ge => Some((">=", 4))
    Punct::Plus => Some(("+", 5))
    Punct::Minus => Some(("-", 5))
    Punct::Star => Some(("*", 6))
    Punct::Slash => Some(("/", 6))
    Punct::Percent => Some(("%", 6))
    _ => None
  }
}

///|
fn Parser::parse_expr(self : Parser, min_prec : Int) -> Result[Expr, RegoError] {
  let mut left = match self.parse_unary() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let mut going = true
  while going {
    match self.binary_op() {
      None => going = false
      Some(info) => {
        let op = info.0
        let prec = info.1
        if prec < min_prec {
          going = false
        } else {
          self.advance()
          let right = match self.parse_expr(prec + 1) {
            Err(e) => return Err(e)
            Ok(v) => v
          }
          left = Expr::EBinary(op, left, right)
        }
      }
    }
  }
  Ok(left)
}

///|
fn Parser::parse_unary(self : Parser) -> Result[Expr, RegoError] {
  if self.at(Punct::Minus) {
    self.advance()
    let inner = match self.parse_unary() {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    return Ok(Expr::ENegate(inner))
  }
  self.parse_postfix()
}

///|
fn Parser::parse_postfix(self : Parser) -> Result[Expr, RegoError] {
  let mut base = match self.parse_primary() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let mut going = true
  while going {
    if self.at(Punct::Dot) {
      self.advance()
      let name = match self.expect_ident("a field name after `.`") {
        Err(e) => return Err(e)
        Ok(s) => s
      }
      base = Expr::EField(base, name)
    } else if self.at(Punct::LBracket) {
      self.advance()
      let index = match self.parse_expr(0) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      match self.expect(Punct::RBracket, "`]` to close the index") {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      base = Expr::EIndex(base, index)
    } else {
      going = false
    }
  }
  Ok(base)
}

///|
fn Parser::parse_primary(self : Parser) -> Result[Expr, RegoError] {
  let token = self.cur()
  match token.kind {
    TokenKind::TokNumber(d) => {
      self.advance()
      Ok(Expr::ENumber(d))
    }
    TokenKind::TokString(s) => {
      self.advance()
      Ok(Expr::EString(s))
    }
    TokenKind::TokIdent(name) => {
      self.advance()
      if name == "true" {
        return Ok(Expr::EBool(true))
      }
      if name == "false" {
        return Ok(Expr::EBool(false))
      }
      if name == "null" {
        return Ok(Expr::ENull)
      }
      // A dotted function name such as `regex.match` or `json.marshal`. Only a
      // chain immediately followed by `(` is a call; otherwise these are
      // ordinary reference steps and the postfix loop re-reads them.
      let after_name = self.pos
      let segments : Array[String] = [name]
      let mut chained = true
      while chained && self.at(Punct::Dot) {
        self.advance()
        match self.cur().kind {
          TokenKind::TokIdent(field) => {
            segments.push(field)
            self.advance()
          }
          _ => chained = false
        }
      }
      if chained && self.at(Punct::LParen) {
        self.advance()
        let args = match self.parse_expr_list(Punct::RParen) {
          Err(e) => return Err(e)
          Ok(a) => a
        }
        match self.expect(Punct::RParen, "`)` to close the call") {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
        return Ok(Expr::ECall(join_strings(segments, "."), args))
      }
      self.pos = after_name
      Ok(Expr::EVar(name))
    }
    TokenKind::TokLParen => {
      self.advance()
      let inner = match self.parse_expr(0) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      match self.expect(Punct::RParen, "`)`") {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      Ok(inner)
    }
    TokenKind::TokLBracket => self.parse_bracket_expr()
    TokenKind::TokLBrace => self.parse_brace_expr()
    _ =>
      Err(self.err("expected an expression but found " + token.kind.describe()))
  }
}

///|
/// Parse a comma-separated expression list up to (but not consuming) `closer`.
fn Parser::parse_expr_list(
  self : Parser,
  closer : Punct,
) -> Result[Array[Expr], RegoError] {
  let items : Array[Expr] = []
  if self.at(closer) {
    return Ok(items)
  }
  let first = match self.parse_expr(0) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  items.push(first)
  while self.at(Punct::Comma) {
    self.advance()
    let next = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    items.push(next)
  }
  Ok(items)
}

///|
/// Parse an array literal, array comprehension, or array-indexed set.
fn Parser::parse_bracket_expr(self : Parser) -> Result[Expr, RegoError] {
  self.advance()
  if self.at(Punct::RBracket) {
    self.advance()
    return Ok(Expr::EArray([]))
  }
  let first = match self.parse_expr(3) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if self.at(Punct::Pipe) {
    self.advance()
    let body = match self.parse_body(Punct::RBracket) {
      Err(e) => return Err(e)
      Ok(b) => b
    }
    match self.expect(Punct::RBracket, "`]` to close the comprehension") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    return Ok(Expr::EArrayComprehension(first, body))
  }
  let items : Array[Expr] = [first]
  while self.at(Punct::Comma) {
    self.advance()
    let next = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    items.push(next)
  }
  match self.expect(Punct::RBracket, "`]` to close the array") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(Expr::EArray(items))
}

///|
/// Parse a set literal, object literal, or one of the two comprehensions.
///
/// An empty `{}` is an empty **object**, matching Rego; the empty set is
/// written `set()`.
fn Parser::parse_brace_expr(self : Parser) -> Result[Expr, RegoError] {
  self.advance()
  if self.at(Punct::RBrace) {
    self.advance()
    return Ok(Expr::EObject([]))
  }
  let first = match self.parse_expr(3) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if self.at(Punct::Colon) {
    self.advance()
    let value = match self.parse_expr(3) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    if self.at(Punct::Pipe) {
      self.advance()
      let body = match self.parse_body(Punct::RBrace) {
        Err(e) => return Err(e)
        Ok(b) => b
      }
      match self.expect(Punct::RBrace, "`}` to close the comprehension") {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      return Ok(Expr::EObjectComprehension(first, value, body))
    }
    let pairs : Array[(Expr, Expr)] = [(first, value)]
    while self.at(Punct::Comma) {
      self.advance()
      let k = match self.parse_expr(0) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      match self.expect(Punct::Colon, "`:` between an object key and value") {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      let v = match self.parse_expr(0) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      pairs.push((k, v))
    }
    match self.expect(Punct::RBrace, "`}` to close the object") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    return Ok(Expr::EObject(pairs))
  }
  if self.at(Punct::Pipe) {
    self.advance()
    let body = match self.parse_body(Punct::RBrace) {
      Err(e) => return Err(e)
      Ok(b) => b
    }
    match self.expect(Punct::RBrace, "`}` to close the comprehension") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    return Ok(Expr::ESetComprehension(first, body))
  }
  let items : Array[Expr] = [first]
  while self.at(Punct::Comma) {
    self.advance()
    let next = match self.parse_expr(0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    items.push(next)
  }
  match self.expect(Punct::RBrace, "`}` to close the set") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(Expr::ESet(items))
}
