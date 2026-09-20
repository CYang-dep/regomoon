///| The Rego lexer.
///
/// Keywords are deliberately **not** distinct token kinds: Rego keywords such
/// as `if`, `contains`, `some` and `in` are recognised contextually by the
/// parser from the identifier text. This keeps the token set small and lets
/// the parser decide, for example, whether `if` introduces a rule body or
/// whether `contains` is a rule-head operator.

///|
/// A token kind.
pub(all) enum TokenKind {
  TokIdent(String)
  TokNumber(Double)
  TokString(String)
  TokLParen
  TokRParen
  TokLBrace
  TokRBrace
  TokLBracket
  TokRBracket
  TokComma
  TokColon
  TokSemicolon
  TokDot
  TokPipe
  TokAmp
  TokAssign
  TokUnify
  TokEq
  TokNeq
  TokLt
  TokLe
  TokGt
  TokGe
  TokPlus
  TokMinus
  TokStar
  TokSlash
  TokPercent
  TokEof
}

///|
/// A token with source position.
pub(all) struct Token {
  kind : TokenKind
  line : Int
  column : Int
}

///|
/// A short description of a token kind, for error messages.
pub fn TokenKind::describe(self : TokenKind) -> String {
  match self {
    TokenKind::TokIdent(s) => "identifier `" + s + "`"
    TokenKind::TokNumber(_) => "number"
    TokenKind::TokString(_) => "string"
    TokenKind::TokLParen => "`(`"
    TokenKind::TokRParen => "`)`"
    TokenKind::TokLBrace => "`{`"
    TokenKind::TokRBrace => "`}`"
    TokenKind::TokLBracket => "`[`"
    TokenKind::TokRBracket => "`]`"
    TokenKind::TokComma => "`,`"
    TokenKind::TokColon => "`:`"
    TokenKind::TokSemicolon => "`;`"
    TokenKind::TokDot => "`.`"
    TokenKind::TokPipe => "`|`"
    TokenKind::TokAmp => "`&`"
    TokenKind::TokAssign => "`:=`"
    TokenKind::TokUnify => "`=`"
    TokenKind::TokEq => "`==`"
    TokenKind::TokNeq => "`!=`"
    TokenKind::TokLt => "`<`"
    TokenKind::TokLe => "`<=`"
    TokenKind::TokGt => "`>`"
    TokenKind::TokGe => "`>=`"
    TokenKind::TokPlus => "`+`"
    TokenKind::TokMinus => "`-`"
    TokenKind::TokStar => "`*`"
    TokenKind::TokSlash => "`/`"
    TokenKind::TokPercent => "`%`"
    TokenKind::TokEof => "end of input"
  }
}

///|
/// Join strings with a separator.
pub fn join_strings(parts : Array[String], sep : String) -> String {
  let sb = StringBuilder::new()
  let mut i = 0
  for p in parts {
    if i > 0 {
      sb.write_string(sep)
    }
    sb.write_string(p)
    i = i + 1
  }
  sb.to_string()
}

///|
/// A compact, stable rendering of a token, useful for tests and debugging.
pub fn Token::render(self : Token) -> String {
  match self.kind {
    TokenKind::TokIdent(s) => "ident:" + s
    TokenKind::TokNumber(d) => "num:" + format_number(d)
    TokenKind::TokString(s) => "str:" + s
    TokenKind::TokLParen => "("
    TokenKind::TokRParen => ")"
    TokenKind::TokLBrace => "{"
    TokenKind::TokRBrace => "}"
    TokenKind::TokLBracket => "["
    TokenKind::TokRBracket => "]"
    TokenKind::TokComma => ","
    TokenKind::TokColon => ":"
    TokenKind::TokSemicolon => ";"
    TokenKind::TokDot => "."
    TokenKind::TokPipe => "|"
    TokenKind::TokAmp => "&"
    TokenKind::TokAssign => ":="
    TokenKind::TokUnify => "="
    TokenKind::TokEq => "=="
    TokenKind::TokNeq => "!="
    TokenKind::TokLt => "<"
    TokenKind::TokLe => "<="
    TokenKind::TokGt => ">"
    TokenKind::TokGe => ">="
    TokenKind::TokPlus => "+"
    TokenKind::TokMinus => "-"
    TokenKind::TokStar => "*"
    TokenKind::TokSlash => "/"
    TokenKind::TokPercent => "%"
    TokenKind::TokEof => "eof"
  }
}

///|
/// Render a whole token stream, space separated.
pub fn render_tokens(tokens : Array[Token]) -> String {
  let parts : Array[String] = []
  for t in tokens {
    parts.push(t.render())
  }
  join_strings(parts, " ")
}

///|
/// Mutable lexer state.
priv struct Lexer {
  chars : Array[Char]
  mut pos : Int
  mut line : Int
  mut column : Int
}

///|
fn code_of(n : Int) -> Char {
  n.unsafe_to_char()
}

///|
fn is_digit(n : Int) -> Bool {
  n >= 48 && n <= 57
}

///|
fn is_ident_start(n : Int) -> Bool {
  (n >= 97 && n <= 122) || (n >= 65 && n <= 90) || n == 95 || n > 127
}

///|
fn is_ident_continue(n : Int) -> Bool {
  is_ident_start(n) || is_digit(n)
}

///|
fn Lexer::err(self : Lexer, message : String) -> RegoError {
  RegoError::at(RegoErrorKind::LexError, message, self.line, self.column)
}

///|
fn Lexer::peek_code(self : Lexer) -> Int? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos].to_int())
  } else {
    None
  }
}

///|
fn Lexer::peek_next_code(self : Lexer) -> Int? {
  if self.pos + 1 < self.chars.length() {
    Some(self.chars[self.pos + 1].to_int())
  } else {
    None
  }
}

///|
fn Lexer::current_is(self : Lexer, n : Int) -> Bool {
  match self.peek_code() {
    Some(m) => m == n
    None => false
  }
}

///|
fn Lexer::next_is(self : Lexer, n : Int) -> Bool {
  match self.peek_next_code() {
    Some(m) => m == n
    None => false
  }
}

///|
/// Whether the character `offset` positions ahead of the cursor is a digit.
fn Lexer::digit_at(self : Lexer, offset : Int) -> Bool {
  let i = self.pos + offset
  if i < self.chars.length() {
    is_digit(self.chars[i].to_int())
  } else {
    false
  }
}

///|
fn Lexer::advance(self : Lexer) -> Unit {
  match self.peek_code() {
    None => ()
    Some(10) => {
      self.pos = self.pos + 1
      self.line = self.line + 1
      self.column = 1
    }
    Some(_) => {
      self.pos = self.pos + 1
      self.column = self.column + 1
    }
  }
}

///|
/// Tokenize a Rego module.
pub fn tokenize(text : String) -> Result[Array[Token], RegoError] {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let lexer : Lexer = { chars, pos: 0, line: 1, column: 1 }
  lexer.run()
}

///|
fn Lexer::run(self : Lexer) -> Result[Array[Token], RegoError] {
  let out : Array[Token] = []
  let mut going = true
  while going {
    self.skip_trivia()
    let line = self.line
    let column = self.column
    let code = self.peek_code()
    if code is None {
      out.push({ kind: TokenKind::TokEof, line, column })
      going = false
    } else {
      let n = match code {
        Some(n) => n
        None => -1
      }
      if is_ident_start(n) {
        out.push({ kind: TokenKind::TokIdent(self.read_ident()), line, column })
      } else if is_digit(n) {
        match self.read_number() {
          Err(e) => return Err(e)
          Ok(d) => out.push({ kind: TokenKind::TokNumber(d), line, column })
        }
      } else if n == 34 {
        match self.read_string() {
          Err(e) => return Err(e)
          Ok(s) => out.push({ kind: TokenKind::TokString(s), line, column })
        }
      } else if n == 96 {
        match self.read_raw_string() {
          Err(e) => return Err(e)
          Ok(s) => out.push({ kind: TokenKind::TokString(s), line, column })
        }
      } else {
        match self.read_symbol() {
          Err(e) => return Err(e)
          Ok(kind) => out.push({ kind, line, column })
        }
      }
    }
  }
  Ok(out)
}

///|
fn Lexer::skip_trivia(self : Lexer) -> Unit {
  let mut going = true
  while going {
    if self.current_is(35) {
      let mut in_comment = true
      while in_comment {
        if self.current_is(10) || self.peek_code() is None {
          in_comment = false
        } else {
          self.advance()
        }
      }
    } else if self.current_is(32) ||
      self.current_is(9) ||
      self.current_is(10) ||
      self.current_is(13) {
      self.advance()
    } else {
      going = false
    }
  }
}

///|
fn Lexer::consume_digits(self : Lexer) -> Int {
  let mut count = 0
  let mut going = true
  while going {
    match self.peek_code() {
      Some(n) =>
        if is_digit(n) {
          count = count + 1
          self.advance()
        } else {
          going = false
        }
      None => going = false
    }
  }
  count
}

///|
fn Lexer::read_ident(self : Lexer) -> String {
  let sb = StringBuilder::new()
  let mut going = true
  while going {
    match self.peek_code() {
      Some(n) =>
        if is_ident_continue(n) {
          sb.write_char(code_of(n))
          self.advance()
        } else {
          going = false
        }
      None => going = false
    }
  }
  sb.to_string()
}

///|
/// Read a numeric literal.
///
/// A `.` is only consumed when a digit follows, so `a[0].b` lexes as
/// `a`, `[`, `0`, `]`, `.`, `b` rather than swallowing the field access.
fn Lexer::read_number(self : Lexer) -> Result[Double, RegoError] {
  let start = self.pos
  ignore(self.consume_digits())
  if self.current_is(46) && self.digit_at(1) {
    self.advance()
    ignore(self.consume_digits())
  }
  if self.current_is(101) || self.current_is(69) {
    let exponent_ok = self.digit_at(1) ||
      ((self.next_is(43) || self.next_is(45)) && self.digit_at(2))
    if exponent_ok {
      self.advance()
      if self.current_is(43) || self.current_is(45) {
        self.advance()
      }
      ignore(self.consume_digits())
    }
  }
  let chars : Array[Char] = []
  let mut i = start
  while i < self.pos {
    chars.push(self.chars[i])
    i = i + 1
  }
  let text = String::from_array(chars)
  match parse_decimal(text) {
    None => Err(self.err("invalid number literal `" + text + "`"))
    Some(d) => Ok(d)
  }
}

///|
fn Lexer::read_string(self : Lexer) -> Result[String, RegoError] {
  self.advance()
  let sb = StringBuilder::new()
  while true {
    match self.peek_code() {
      None => return Err(self.err("unterminated string literal"))
      Some(34) => {
        self.advance()
        return Ok(sb.to_string())
      }
      Some(92) => {
        self.advance()
        match self.peek_code() {
          None => return Err(self.err("unterminated escape sequence"))
          Some(n) => {
            self.advance()
            if n == 34 {
              sb.write_char(code_of(34))
            } else if n == 92 {
              sb.write_char(code_of(92))
            } else if n == 47 {
              sb.write_char(code_of(47))
            } else if n == 98 {
              sb.write_char(code_of(8))
            } else if n == 102 {
              sb.write_char(code_of(12))
            } else if n == 110 {
              sb.write_char(code_of(10))
            } else if n == 114 {
              sb.write_char(code_of(13))
            } else if n == 116 {
              sb.write_char(code_of(9))
            } else if n == 117 {
              match self.read_hex4() {
                Err(e) => return Err(e)
                Ok(cp) => sb.write_char(code_of(cp))
              }
            } else {
              return Err(self.err("invalid escape sequence in string literal"))
            }
          }
        }
      }
      Some(n) =>
        if n == 10 {
          return Err(self.err("unterminated string literal"))
        } else {
          sb.write_char(code_of(n))
          self.advance()
        }
    }
  }
  Err(self.err("unterminated string literal"))
}

///|
/// A backtick-delimited raw string: no escapes, newlines allowed.
fn Lexer::read_raw_string(self : Lexer) -> Result[String, RegoError] {
  self.advance()
  let sb = StringBuilder::new()
  while true {
    match self.peek_code() {
      None => return Err(self.err("unterminated raw string literal"))
      Some(96) => {
        self.advance()
        return Ok(sb.to_string())
      }
      Some(n) => {
        sb.write_char(code_of(n))
        self.advance()
      }
    }
  }
  Err(self.err("unterminated raw string literal"))
}

///|
fn Lexer::read_hex4(self : Lexer) -> Result[Int, RegoError] {
  let mut value = 0
  let mut i = 0
  while i < 4 {
    match self.peek_code() {
      None => return Err(self.err("unterminated \\u escape"))
      Some(n) => {
        let digit = if n >= 48 && n <= 57 {
          n - 48
        } else if n >= 97 && n <= 102 {
          n - 87
        } else if n >= 65 && n <= 70 {
          n - 55
        } else {
          return Err(self.err("invalid hex digit in \\u escape"))
        }
        value = value * 16 + digit
        self.advance()
      }
    }
    i = i + 1
  }
  Ok(value)
}

///|
fn Lexer::read_symbol(self : Lexer) -> Result[TokenKind, RegoError] {
  let n = match self.peek_code() {
    None => return Err(self.err("unexpected end of input"))
    Some(n) => n
  }
  if n == 40 {
    self.advance()
    return Ok(TokenKind::TokLParen)
  }
  if n == 41 {
    self.advance()
    return Ok(TokenKind::TokRParen)
  }
  if n == 123 {
    self.advance()
    return Ok(TokenKind::TokLBrace)
  }
  if n == 125 {
    self.advance()
    return Ok(TokenKind::TokRBrace)
  }
  if n == 91 {
    self.advance()
    return Ok(TokenKind::TokLBracket)
  }
  if n == 93 {
    self.advance()
    return Ok(TokenKind::TokRBracket)
  }
  if n == 44 {
    self.advance()
    return Ok(TokenKind::TokComma)
  }
  if n == 58 {
    if self.next_is(61) {
      self.advance()
      self.advance()
      return Ok(TokenKind::TokAssign)
    }
    self.advance()
    return Ok(TokenKind::TokColon)
  }
  if n == 59 {
    self.advance()
    return Ok(TokenKind::TokSemicolon)
  }
  if n == 46 {
    self.advance()
    return Ok(TokenKind::TokDot)
  }
  if n == 124 {
    self.advance()
    return Ok(TokenKind::TokPipe)
  }
  if n == 38 {
    self.advance()
    return Ok(TokenKind::TokAmp)
  }
  if n == 61 {
    if self.next_is(61) {
      self.advance()
      self.advance()
      return Ok(TokenKind::TokEq)
    }
    self.advance()
    return Ok(TokenKind::TokUnify)
  }
  if n == 33 {
    if self.next_is(61) {
      self.advance()
      self.advance()
      return Ok(TokenKind::TokNeq)
    }
    return Err(self.err("unexpected character `!`, did you mean `!=`?"))
  }
  if n == 60 {
    if self.next_is(61) {
      self.advance()
      self.advance()
      return Ok(TokenKind::TokLe)
    }
    self.advance()
    return Ok(TokenKind::TokLt)
  }
  if n == 62 {
    if self.next_is(61) {
      self.advance()
      self.advance()
      return Ok(TokenKind::TokGe)
    }
    self.advance()
    return Ok(TokenKind::TokGt)
  }
  if n == 43 {
    self.advance()
    return Ok(TokenKind::TokPlus)
  }
  if n == 45 {
    self.advance()
    return Ok(TokenKind::TokMinus)
  }
  if n == 42 {
    self.advance()
    return Ok(TokenKind::TokStar)
  }
  if n == 47 {
    self.advance()
    return Ok(TokenKind::TokSlash)
  }
  if n == 37 {
    self.advance()
    return Ok(TokenKind::TokPercent)
  }
  Err(self.err("unexpected character `" + code_of(n).to_string() + "`"))
}
