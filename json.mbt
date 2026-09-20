///| JSON parsing into [Value], used to load `data` documents and `input`.
///
/// The grammar is strict RFC 8259: no trailing commas, no comments, no
/// `NaN`/`Infinity`, and control characters must be escaped.

///|
/// Mutable reader state over a character array.
priv struct JsonReader {
  chars : Array[Char]
  mut pos : Int
  mut line : Int
  mut column : Int
}

///|
fn JsonReader::err(self : JsonReader, message : String) -> RegoError {
  RegoError::at(RegoErrorKind::JsonError, message, self.line, self.column)
}

///|
fn JsonReader::peek_code(self : JsonReader) -> Int? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos].to_int())
  } else {
    None
  }
}

///|
fn JsonReader::advance(self : JsonReader) -> Unit {
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
fn JsonReader::skip_ws(self : JsonReader) -> Unit {
  let mut going = true
  while going {
    match self.peek_code() {
      Some(32) | Some(9) | Some(10) | Some(13) => self.advance()
      _ => going = false
    }
  }
}

///|
fn JsonReader::expect_literal(
  self : JsonReader,
  text : String,
  value : Value,
) -> Result[Value, RegoError] {
  for c in text {
    match self.peek_code() {
      Some(n) =>
        if n == c.to_int() {
          self.advance()
        } else {
          return Err(self.err("invalid literal, expected `" + text + "`"))
        }
      None =>
        return Err(
          self.err("unexpected end of input in literal `" + text + "`"),
        )
    }
  }
  Ok(value)
}

///|
/// Parse a complete JSON document.
pub fn parse_json(text : String) -> Result[Value, RegoError] {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let reader : JsonReader = { chars, pos: 0, line: 1, column: 1 }
  reader.skip_ws()
  match reader.parse_value() {
    Err(e) => Err(e)
    Ok(v) => {
      reader.skip_ws()
      if reader.pos < reader.chars.length() {
        Err(reader.err("trailing content after JSON value"))
      } else {
        Ok(v)
      }
    }
  }
}

///|
fn JsonReader::parse_value(self : JsonReader) -> Result[Value, RegoError] {
  match self.peek_code() {
    None => Err(self.err("unexpected end of input, expected a JSON value"))
    Some(123) => self.parse_object()
    Some(91) => self.parse_array()
    Some(34) => self.parse_string_value()
    Some(116) => self.expect_literal("true", Value::Bool(true))
    Some(102) => self.expect_literal("false", Value::Bool(false))
    Some(110) => self.expect_literal("null", Value::Null)
    Some(n) =>
      if n == 45 || (n >= 48 && n <= 57) {
        self.parse_number()
      } else {
        Err(self.err("unexpected character, expected a JSON value"))
      }
  }
}

///|
fn JsonReader::parse_array(self : JsonReader) -> Result[Value, RegoError] {
  self.advance()
  let items : Array[Value] = []
  self.skip_ws()
  match self.peek_code() {
    Some(93) => {
      self.advance()
      return Ok(Value::Array(items))
    }
    _ => ()
  }
  let mut going = true
  while going {
    self.skip_ws()
    match self.parse_value() {
      Err(e) => return Err(e)
      Ok(v) => items.push(v)
    }
    self.skip_ws()
    match self.peek_code() {
      Some(44) => self.advance()
      Some(93) => {
        self.advance()
        going = false
      }
      None => return Err(self.err("unterminated array"))
      Some(_) => return Err(self.err("expected `,` or `]` in array"))
    }
  }
  Ok(Value::Array(items))
}

///|
fn JsonReader::parse_object(self : JsonReader) -> Result[Value, RegoError] {
  self.advance()
  let pairs : Array[(String, Value)] = []
  self.skip_ws()
  match self.peek_code() {
    Some(125) => {
      self.advance()
      return Ok(make_object(pairs))
    }
    _ => ()
  }
  let mut going = true
  while going {
    self.skip_ws()
    match self.peek_code() {
      Some(34) => ()
      None => return Err(self.err("unterminated object"))
      Some(_) => return Err(self.err("expected a string key in object"))
    }
    let key = match self.parse_string_raw() {
      Err(e) => return Err(e)
      Ok(k) => k
    }
    self.skip_ws()
    match self.peek_code() {
      Some(58) => self.advance()
      None => return Err(self.err("unterminated object"))
      Some(_) => return Err(self.err("expected `:` after object key"))
    }
    self.skip_ws()
    let value = match self.parse_value() {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    pairs.push((key, value))
    self.skip_ws()
    match self.peek_code() {
      Some(44) => self.advance()
      Some(125) => {
        self.advance()
        going = false
      }
      None => return Err(self.err("unterminated object"))
      Some(_) => return Err(self.err("expected `,` or `}` in object"))
    }
  }
  Ok(make_object(pairs))
}

///|
fn JsonReader::parse_string_value(
  self : JsonReader,
) -> Result[Value, RegoError] {
  match self.parse_string_raw() {
    Err(e) => Err(e)
    Ok(s) => Ok(Value::String(s))
  }
}

///|
fn JsonReader::parse_hex4(self : JsonReader) -> Result[Int, RegoError] {
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
/// Parse a string body, assuming the reader is positioned on the opening `"`.
fn JsonReader::parse_string_raw(self : JsonReader) -> Result[String, RegoError] {
  self.advance()
  let sb = StringBuilder::new()
  while true {
    match self.peek_code() {
      None => return Err(self.err("unterminated string"))
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
              sb.write_char((34).unsafe_to_char())
            } else if n == 92 {
              sb.write_char((92).unsafe_to_char())
            } else if n == 47 {
              sb.write_char((47).unsafe_to_char())
            } else if n == 98 {
              sb.write_char((8).unsafe_to_char())
            } else if n == 102 {
              sb.write_char((12).unsafe_to_char())
            } else if n == 110 {
              sb.write_char((10).unsafe_to_char())
            } else if n == 114 {
              sb.write_char((13).unsafe_to_char())
            } else if n == 116 {
              sb.write_char((9).unsafe_to_char())
            } else if n == 117 {
              match self.parse_hex4() {
                Err(e) => return Err(e)
                Ok(cp) => if cp >= 0 { sb.write_char(cp.unsafe_to_char()) }
              }
            } else {
              return Err(self.err("invalid escape sequence in string"))
            }
          }
        }
      }
      Some(n) =>
        if n < 32 {
          return Err(self.err("unescaped control character in string"))
        } else {
          match self.peek_code() {
            Some(_) => {
              sb.write_char(self.chars[self.pos])
              self.advance()
            }
            None => return Err(self.err("unterminated string"))
          }
        }
    }
  }
  Err(self.err("unterminated string"))
}

///|
fn JsonReader::take_digits(self : JsonReader) -> Int {
  let mut count = 0
  let mut going = true
  while going {
    match self.peek_code() {
      Some(n) =>
        if n >= 48 && n <= 57 {
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
fn JsonReader::parse_number(self : JsonReader) -> Result[Value, RegoError] {
  let start = self.pos
  match self.peek_code() {
    Some(45) => self.advance()
    _ => ()
  }
  let int_start = self.pos
  let int_count = self.take_digits()
  if int_count == 0 {
    return Err(self.err("expected a digit in number"))
  }
  if int_count > 1 && self.chars[int_start].to_int() == 48 {
    return Err(self.err("numbers may not have leading zeros"))
  }
  match self.peek_code() {
    Some(46) => {
      self.advance()
      if self.take_digits() == 0 {
        return Err(self.err("expected a digit after the decimal point"))
      }
    }
    _ => ()
  }
  match self.peek_code() {
    Some(101) | Some(69) => {
      self.advance()
      match self.peek_code() {
        Some(43) | Some(45) => self.advance()
        _ => ()
      }
      if self.take_digits() == 0 {
        return Err(self.err("expected a digit in the exponent"))
      }
    }
    _ => ()
  }
  let chars : Array[Char] = []
  let mut i = start
  while i < self.pos {
    chars.push(self.chars[i])
    i = i + 1
  }
  let text = String::from_array(chars)
  match parse_decimal(text) {
    None => Err(self.err("invalid number literal"))
    Some(d) => Ok(Value::Number(d))
  }
}

///|
/// Convert a strict JSON decimal literal to a `Double`.
pub fn parse_decimal(s : String) -> Double? {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  if chars.length() == 0 {
    return None
  }
  let mut i = 0
  let mut negative = false
  if chars[0].to_int() == 45 {
    negative = true
    i = 1
  }
  let mut mantissa = 0.0
  let mut seen_dot = false
  let mut scale = 1.0
  let mut exponent = 0
  let mut has_digit = false
  while i < chars.length() {
    let n = chars[i].to_int()
    if n == 46 {
      if seen_dot {
        return None
      }
      seen_dot = true
      i = i + 1
    } else if n == 101 || n == 69 {
      break
    } else if n >= 48 && n <= 57 {
      has_digit = true
      let d = (n - 48).to_double()
      if seen_dot {
        scale = scale * 10.0
        mantissa = mantissa + d / scale
      } else {
        mantissa = mantissa * 10.0 + d
      }
      i = i + 1
    } else {
      return None
    }
  }
  if !has_digit {
    return None
  }
  if i < chars.length() {
    i = i + 1
    let mut exp_negative = false
    if i < chars.length() && chars[i].to_int() == 45 {
      exp_negative = true
      i = i + 1
    } else if i < chars.length() && chars[i].to_int() == 43 {
      i = i + 1
    }
    let mut exp_digits = 0
    while i < chars.length() {
      let n = chars[i].to_int()
      if n < 48 || n > 57 {
        return None
      }
      exponent = exponent * 10 + (n - 48)
      exp_digits = exp_digits + 1
      i = i + 1
    }
    if exp_digits == 0 {
      return None
    }
    if exp_negative {
      exponent = -exponent
    }
  }
  let mut result = mantissa
  let magnitude = if exponent < 0 { -exponent } else { exponent }
  let mut k = 0
  while k < magnitude {
    if exponent < 0 {
      result = result / 10.0
    } else {
      result = result * 10.0
    }
    k = k + 1
  }
  if negative {
    result = -result
  }
  Some(result)
}
