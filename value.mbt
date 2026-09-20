///| The Rego value model.
///
/// Rego values are the JSON document model extended with sets:
/// `null`, booleans, numbers, strings, arrays, objects, and sets.
///
/// Two invariants are maintained for every value produced by this module:
///
/// - `Set` payloads are **sorted and deduplicated** under [Value::compare];
/// - `Object` payloads are **sorted by key and deduplicated** (last write wins).
///
/// Rego treats sets and objects as unordered; keeping a canonical order makes
/// equality, hashing and output deterministic.
///
/// Numbers are represented as `Double`. OPA itself uses arbitrary-precision
/// decimals; see the README for what that means in practice.
pub(all) enum Value {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[Value])
  Set(Array[Value])
  Object(Array[(String, Value)])
}

///| The Rego type-ordering rank of a value.
///
/// OPA orders values across types as
/// `null < boolean < number < string < array < object < set`.
fn type_rank(v : Value) -> Int {
  match v {
    Value::Null => 0
    Value::Bool(_) => 1
    Value::Number(_) => 2
    Value::String(_) => 3
    Value::Array(_) => 4
    Value::Object(_) => 5
    Value::Set(_) => 6
  }
}

///| A stable name for the value's type, used in error messages.
pub fn Value::type_name(self : Value) -> String {
  match self {
    Value::Null => "null"
    Value::Bool(_) => "boolean"
    Value::Number(_) => "number"
    Value::String(_) => "string"
    Value::Array(_) => "array"
    Value::Object(_) => "object"
    Value::Set(_) => "set"
  }
}

///| Rego truthiness: booleans are the only booleans.
///
/// Rego has no truthiness coercion, so a non-boolean used in a boolean
/// position is a type error, not a falsy value. This returns `None` for
/// non-booleans so callers can raise a proper error.
pub fn Value::as_bool(self : Value) -> Bool? {
  match self {
    Value::Bool(b) => Some(b)
    _ => None
  }
}

///| Structural equality.
pub fn Value::equals(self : Value, other : Value) -> Bool {
  if type_rank(self) != type_rank(other) {
    return false
  }
  match (self, other) {
    (Value::Null, Value::Null) => true
    (Value::Bool(a), Value::Bool(b)) => a == b
    (Value::Number(a), Value::Number(b)) => a == b
    (Value::String(a), Value::String(b)) => a == b
    (Value::Array(a), Value::Array(b)) | (Value::Set(a), Value::Set(b)) => {
      if a.length() != b.length() {
        false
      } else {
        let mut same = true
        for i = 0; i < a.length(); i = i + 1 {
          if !(a[i].equals(b[i])) {
            same = false
          }
        }
        same
      }
    }
    (Value::Object(a), Value::Object(b)) => {
      if a.length() != b.length() {
        false
      } else {
        let mut same = true
        for i = 0; i < a.length(); i = i + 1 {
          if a[i].0 != b[i].0 || !(a[i].1.equals(b[i].1)) {
            same = false
          }
        }
        same
      }
    }
    _ => false
  }
}

///| Total ordering across all Rego values, matching OPA's `ast.Compare`.
///
/// Returns a negative integer, zero, or a positive integer.
pub fn Value::compare(self : Value, other : Value) -> Int {
  let ra = type_rank(self)
  let rb = type_rank(other)
  if ra != rb {
    return ra - rb
  }
  match (self, other) {
    (Value::Null, Value::Null) => 0
    (Value::Bool(a), Value::Bool(b)) => {
      if a == b { 0 } else if a { 1 } else { -1 }
    }
    (Value::Number(a), Value::Number(b)) => {
      if a < b { -1 } else if a > b { 1 } else { 0 }
    }
    (Value::String(a), Value::String(b)) => compare_string(a, b)
    (Value::Array(a), Value::Array(b)) | (Value::Set(a), Value::Set(b)) => {
      compare_seq(a, b)
    }
    (Value::Object(a), Value::Object(b)) => {
      let n = if a.length() < b.length() { a.length() } else { b.length() }
      let mut i = 0
      while i < n {
        let kc = compare_string(a[i].0, b[i].0)
        if kc != 0 {
          return kc
        }
        let vc = a[i].1.compare(b[i].1)
        if vc != 0 {
          return vc
        }
        i = i + 1
      }
      a.length() - b.length()
    }
    _ => 0
  }
}

///| Lexicographic comparison of two strings by Unicode code point.
fn compare_string(a : String, b : String) -> Int {
  let ca : Array[Char] = []
  for c in a {
    ca.push(c)
  }
  let cb : Array[Char] = []
  for c in b {
    cb.push(c)
  }
  let n = if ca.length() < cb.length() { ca.length() } else { cb.length() }
  let mut i = 0
  while i < n {
    let x = ca[i].to_int()
    let y = cb[i].to_int()
    if x != y {
      return x - y
    }
    i = i + 1
  }
  ca.length() - cb.length()
}

///| Lexicographic comparison of two value sequences.
fn compare_seq(a : Array[Value], b : Array[Value]) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let mut i = 0
  while i < n {
    let c = a[i].compare(b[i])
    if c != 0 {
      return c
    }
    i = i + 1
  }
  a.length() - b.length()
}

///| In-place insertion sort. Used instead of a generic sort so the canonical
/// ordering of sets and objects does not depend on trait resolution.
fn sort_values(items : Array[Value]) -> Unit {
  let n = items.length()
  let mut i = 1
  while i < n {
    let key = items[i]
    let mut j = i - 1
    while j >= 0 && items[j].compare(key) > 0 {
      items[j + 1] = items[j]
      j = j - 1
    }
    items[j + 1] = key
    i = i + 1
  }
}

///| A copy of `items` sorted by the Rego total order.
pub fn sorted_values(items : Array[Value]) -> Array[Value] {
  let out = items.copy()
  sort_values(out)
  out
}

///| Build a canonical set from arbitrary items: sorted and deduplicated.
pub fn make_set(items : Array[Value]) -> Value {
  let sorted = items.copy()
  sort_values(sorted)
  let out : Array[Value] = []
  for v in sorted {
    let last = out.length() - 1
    if last < 0 || !(out[last].equals(v)) {
      out.push(v)
    }
  }
  Value::Set(out)
}

///| Build a canonical object from key/value pairs: sorted by key, last write wins.
pub fn make_object(pairs : Array[(String, Value)]) -> Value {
  let sorted = pairs.copy()
  let n = sorted.length()
  let mut i = 1
  while i < n {
    let key = sorted[i]
    let mut j = i - 1
    while j >= 0 && compare_string(sorted[j].0, key.0) > 0 {
      sorted[j + 1] = sorted[j]
      j = j - 1
    }
    sorted[j + 1] = key
    i = i + 1
  }
  let out : Array[(String, Value)] = []
  for kv in sorted {
    let last = out.length() - 1
    if last >= 0 && out[last].0 == kv.0 {
      out[last] = kv
    } else {
      out.push(kv)
    }
  }
  Value::Object(out)
}

///| Look up a key in an object.
pub fn Value::get_field(self : Value, key : String) -> Value? {
  match self {
    Value::Object(pairs) => {
      let mut found : Value? = None
      for kv in pairs {
        if kv.0 == key {
          found = Some(kv.1)
        }
      }
      found
    }
    _ => None
  }
}

///| Whether a set contains a value.
pub fn Value::set_contains(self : Value, item : Value) -> Bool {
  match self {
    Value::Set(items) => {
      let mut hit = false
      for v in items {
        if v.equals(item) {
          hit = true
        }
      }
      hit
    }
    _ => false
  }
}

///| Elements of an array, or of a set in canonical order.
pub fn Value::elements(self : Value) -> Array[Value]? {
  match self {
    Value::Array(items) => Some(items)
    Value::Set(items) => Some(items)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

///| Format a number the way OPA does: integral values have no fractional part.
pub fn format_number(d : Double) -> String {
  let s = d.to_string()
  s
}

///| Append `\uXXXX`-style escaping of a string body.
fn write_escaped(sb : StringBuilder, s : String) -> Unit {
  for c in s {
    let n = c.to_int()
    if n == 34 {
      sb.write_string("\\\"")
    } else if n == 92 {
      sb.write_string("\\\\")
    } else if n == 10 {
      sb.write_string("\\n")
    } else if n == 13 {
      sb.write_string("\\r")
    } else if n == 9 {
      sb.write_string("\\t")
    } else if n == 8 {
      sb.write_string("\\b")
    } else if n == 12 {
      sb.write_string("\\f")
    } else if n < 32 {
      sb.write_string("\\u")
      sb.write_string(hex4(n))
    } else {
      sb.write_char(c)
    }
  }
}

///| Four-digit lowercase hex, for `\u` escapes.
fn hex4(n : Int) -> String {
  let digits = "0123456789abcdef"
  let d : Array[Char] = []
  for c in digits {
    d.push(c)
  }
  let out : Array[Char] = []
  let mut v = n
  let mut i = 0
  while i < 4 {
    out.push(d[v % 16])
    v = v / 16
    i = i + 1
  }
  let rev : Array[Char] = []
  let mut k = out.length() - 1
  while k >= 0 {
    rev.push(out[k])
    k = k - 1
  }
  String::from_array(rev)
}

///| Render a value as Rego source (strings quoted, sets as `{...}`).
pub fn Value::to_rego_string(self : Value) -> String {
  let sb = StringBuilder::new()
  write_rego(sb, self)
  sb.to_string()
}

///|
fn write_rego(sb : StringBuilder, v : Value) -> Unit {
  match v {
    Value::Null => sb.write_string("null")
    Value::Bool(b) => sb.write_string(if b { "true" } else { "false" })
    Value::Number(d) => sb.write_string(format_number(d))
    Value::String(s) => {
      sb.write_char('"')
      write_escaped(sb, s)
      sb.write_char('"')
    }
    Value::Array(items) => {
      sb.write_char('[')
      let mut i = 0
      for item in items {
        if i > 0 {
          sb.write_string(", ")
        }
        write_rego(sb, item)
        i = i + 1
      }
      sb.write_char(']')
    }
    Value::Set(items) => {
      if items.length() == 0 {
        sb.write_string("set()")
      } else {
        sb.write_char('{')
        let mut i = 0
        for item in items {
          if i > 0 {
            sb.write_string(", ")
          }
          write_rego(sb, item)
          i = i + 1
        }
        sb.write_char('}')
      }
    }
    Value::Object(pairs) => {
      sb.write_char('{')
      let mut i = 0
      for kv in pairs {
        if i > 0 {
          sb.write_string(", ")
        }
        sb.write_char('"')
        write_escaped(sb, kv.0)
        sb.write_string("\": ")
        write_rego(sb, kv.1)
        i = i + 1
      }
      sb.write_char('}')
    }
  }
}

///| Render a value as JSON. Sets are emitted as arrays, matching OPA's
/// `json.marshal` behaviour for set-valued results.
pub fn Value::to_json_string(self : Value) -> String {
  let sb = StringBuilder::new()
  write_json(sb, self)
  sb.to_string()
}

///|
fn write_json(sb : StringBuilder, v : Value) -> Unit {
  match v {
    Value::Null => sb.write_string("null")
    Value::Bool(b) => sb.write_string(if b { "true" } else { "false" })
    Value::Number(d) => sb.write_string(format_number(d))
    Value::String(s) => {
      sb.write_char('"')
      write_escaped(sb, s)
      sb.write_char('"')
    }
    Value::Array(items) | Value::Set(items) => {
      sb.write_char('[')
      let mut i = 0
      for item in items {
        if i > 0 {
          sb.write_string(",")
        }
        write_json(sb, item)
        i = i + 1
      }
      sb.write_char(']')
    }
    Value::Object(pairs) => {
      sb.write_char('{')
      let mut i = 0
      for kv in pairs {
        if i > 0 {
          sb.write_string(",")
        }
        sb.write_char('"')
        write_escaped(sb, kv.0)
        sb.write_string("\":")
        write_json(sb, kv.1)
        i = i + 1
      }
      sb.write_char('}')
    }
  }
}
