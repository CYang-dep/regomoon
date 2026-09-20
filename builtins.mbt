///| The Rego builtin function library.
///
/// Builtins are pure. The dispatcher returns `None` for an unknown name, which
/// lets the evaluator fall back to user-defined rules; a known name with the
/// wrong argument count is an arity error.

///| The number of arguments a builtin takes, or `None` if it is not a builtin.
pub fn builtin_arity(name : String) -> Int? {
  match name {
    "count" => Some(1)
    "sum" => Some(1)
    "product" => Some(1)
    "max" => Some(1)
    "min" => Some(1)
    "sort" => Some(1)
    "all" => Some(1)
    "any" => Some(1)
    "abs" => Some(1)
    "round" => Some(1)
    "ceil" => Some(1)
    "floor" => Some(1)
    "lower" => Some(1)
    "upper" => Some(1)
    "trim_space" => Some(1)
    "trim" => Some(2)
    "startswith" => Some(2)
    "endswith" => Some(2)
    "contains" => Some(2)
    "split" => Some(2)
    "concat" => Some(2)
    "replace" => Some(3)
    "substring" => Some(3)
    "indexof" => Some(2)
    "sprintf" => Some(2)
    "is_number" => Some(1)
    "is_string" => Some(1)
    "is_boolean" => Some(1)
    "is_array" => Some(1)
    "is_object" => Some(1)
    "is_set" => Some(1)
    "is_null" => Some(1)
    "type_name" => Some(1)
    "to_number" => Some(1)
    "set" => Some(0)
    "union" => Some(1)
    "intersection" => Some(1)
    "array.concat" => Some(2)
    "object.get" => Some(3)
    "object.keys" => Some(1)
    "object.union" => Some(2)
    "json.marshal" => Some(1)
    "json.unmarshal" => Some(1)
    "regex.match" => Some(2)
    "regex.is_valid" => Some(1)
    "numbers.range" => Some(2)
    _ => None
  }
}

///| Whether `name` refers to a builtin.
pub fn is_builtin(name : String) -> Bool {
  builtin_arity(name) is Some(_)
}

// ---------------------------------------------------------------------------
// Argument helpers
// ---------------------------------------------------------------------------

///|
fn type_error(name : String, arg_index : Int, expected : String, got : Value) -> RegoError {
  RegoError::make(
    RegoErrorKind::TypeError,
    "builtin `" +
    name +
    "` argument " +
    (arg_index + 1).to_string() +
    " must be " +
    expected +
    ", got " +
    got.type_name(),
  )
}

///|
fn want_number(name : String, args : Array[Value], i : Int) -> Result[Double, RegoError] {
  match args[i] {
    Value::Number(d) => Ok(d)
    other => Err(type_error(name, i, "a number", other))
  }
}

///|
fn want_string(name : String, args : Array[Value], i : Int) -> Result[String, RegoError] {
  match args[i] {
    Value::String(s) => Ok(s)
    other => Err(type_error(name, i, "a string", other))
  }
}

///| The elements of an array or set.
fn want_items(name : String, args : Array[Value], i : Int) -> Result[Array[Value], RegoError] {
  match args[i] {
    Value::Array(items) => Ok(items)
    Value::Set(items) => Ok(items)
    other => Err(type_error(name, i, "an array or set", other))
  }
}

///|
fn want_object(
  name : String,
  args : Array[Value],
  i : Int
) -> Result[Array[(String, Value)], RegoError] {
  match args[i] {
    Value::Object(pairs) => Ok(pairs)
    other => Err(type_error(name, i, "an object", other))
  }
}

///|
fn as_number_list(name : String, items : Array[Value]) -> Result[Array[Double], RegoError] {
  let out : Array[Double] = []
  for v in items {
    match v {
      Value::Number(d) => out.push(d)
      other =>
        return Err(
          RegoError::make(
            RegoErrorKind::TypeError,
            "builtin `" +
            name +
            "` requires numbers, got " +
            other.type_name(),
          ),
        )
    }
  }
  Ok(out)
}

///| Split a string into its Unicode code points.
fn chars_of(s : String) -> Array[Char] {
  let out : Array[Char] = []
  for c in s {
    out.push(c)
  }
  out
}

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

///| Evaluate a builtin call. Returns `None` when `name` is not a builtin.
pub fn call_builtin(
  name : String,
  args : Array[Value]
) -> Result[Value, RegoError]? {
  let arity = match builtin_arity(name) {
    None => return None
    Some(n) => n
  }
  if args.length() != arity {
    return Some(
      Err(
        RegoError::make(
          RegoErrorKind::ArityError,
          "builtin `" +
          name +
          "` expects " +
          arity.to_string() +
          " argument(s), got " +
          args.length().to_string(),
        ),
      ),
    )
  }
  Some(eval_builtin(name, args))
}

///|
fn eval_builtin(name : String, args : Array[Value]) -> Result[Value, RegoError] {
  // --- aggregation -------------------------------------------------------
  if name == "count" {
    return match args[0] {
      Value::Array(items) => Ok(Value::Number(items.length().to_double()))
      Value::Set(items) => Ok(Value::Number(items.length().to_double()))
      Value::Object(pairs) => Ok(Value::Number(pairs.length().to_double()))
      Value::String(s) => Ok(Value::Number(chars_of(s).length().to_double()))
      other => Err(type_error(name, 0, "an array, set, object or string", other))
    }
  }
  if name == "sum" || name == "product" {
    let items = match want_items(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let numbers = match as_number_list(name, items) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let mut acc = if name == "sum" { 0.0 } else { 1.0 }
    for d in numbers {
      if name == "sum" {
        acc = acc + d
      } else {
        acc = acc * d
      }
    }
    return Ok(Value::Number(acc))
  }
  if name == "max" || name == "min" {
    let items = match want_items(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    if items.length() == 0 {
      return Err(
        RegoError::make(
          RegoErrorKind::TypeError,
          "builtin `" + name + "` requires a non-empty collection",
        ),
      )
    }
    let mut best = items[0]
    for v in items {
      let c = v.compare(best)
      if (name == "max" && c > 0) || (name == "min" && c < 0) {
        best = v
      }
    }
    return Ok(best)
  }
  if name == "sort" {
    let items = match want_items(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    return Ok(Value::Array(sorted_values(items)))
  }
  if name == "all" || name == "any" {
    let items = match want_items(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let mut seen_true = false
    let mut all_true = true
    for v in items {
      match v {
        Value::Bool(true) => seen_true = true
        Value::Bool(false) => all_true = false
        other => return Err(type_error(name, 0, "a collection of booleans", other))
      }
    }
    if name == "all" {
      return Ok(Value::Bool(all_true))
    }
    return Ok(Value::Bool(seen_true))
  }
  // --- arithmetic --------------------------------------------------------
  if name == "abs" || name == "round" || name == "ceil" || name == "floor" {
    let d = match want_number(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    if name == "abs" {
      return Ok(Value::Number(if d < 0.0 { -d } else { d }))
    }
    if name == "round" {
      return Ok(Value::Number(d.round()))
    }
    if name == "ceil" {
      return Ok(Value::Number(d.ceil()))
    }
    return Ok(Value::Number(d.floor()))
  }
  // --- strings -----------------------------------------------------------
  if name == "lower" || name == "upper" || name == "trim_space" {
    let s = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    if name == "lower" {
      return Ok(Value::String(s.to_lower()))
    }
    if name == "upper" {
      return Ok(Value::String(s.to_upper()))
    }
    return Ok(Value::String(trim_whitespace(s)))
  }
  if name == "trim" {
    let s = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let cutset = match want_string(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let src = chars_of(s)
    let cut = chars_of(cutset)
    let in_cut : (Char) -> Bool = fn(c) {
      let mut found = false
      for x in cut {
        if x.to_int() == c.to_int() {
          found = true
        }
      }
      found
    }
    let mut start = 0
    while start < src.length() && in_cut(src[start]) {
      start = start + 1
    }
    let mut stop = src.length()
    while stop > start && in_cut(src[stop - 1]) {
      stop = stop - 1
    }
    return Ok(Value::String(slice_chars(src, start, stop - start)))
  }
  if name == "startswith" || name == "endswith" || name == "contains" {
    let s = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let t = match want_string(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    if name == "startswith" {
      return Ok(Value::Bool(s.has_prefix(t)))
    }
    if name == "endswith" {
      return Ok(Value::Bool(s.has_suffix(t)))
    }
    return Ok(Value::Bool(s.contains(t)))
  }
  if name == "split" {
    let s = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let delim = match want_string(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let parts = s.split(delim).to_array().map(fn(v) { Value::String(v.to_owned()) })
    return Ok(Value::Array(parts))
  }
  if name == "concat" {
    let delim = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let items = match want_items(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let parts : Array[String] = []
    for v in items {
      match v {
        Value::String(s) => parts.push(s)
        other => return Err(type_error(name, 1, "an array or set of strings", other))
      }
    }
    return Ok(Value::String(join_strings(parts, delim)))
  }
  if name == "replace" {
    let s = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let old = match want_string(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let replacement = match want_string(name, args, 2) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    return Ok(Value::String(replace_all(s, old, replacement)))
  }
  if name == "substring" {
    let s = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let start_d = match want_number(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let len_d = match want_number(name, args, 2) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let src = chars_of(s)
    let start = start_d.to_int()
    let len = len_d.to_int()
    if start < 0 || start > src.length() {
      return Err(
        RegoError::make(
          RegoErrorKind::TypeError,
          "builtin `substring` start index " +
          start.to_string() +
          " is outside the string of length " +
          src.length().to_string(),
        ),
      )
    }
    let available = src.length() - start
    let take = if len < 0 {
      available
    } else if len > available {
      available
    } else {
      len
    }
    return Ok(Value::String(slice_chars(src, start, take)))
  }
  if name == "indexof" {
    let s = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let sub = match want_string(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    return Ok(Value::Number(index_of(s, sub).to_double()))
  }
  if name == "sprintf" {
    let fmt = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let items = match want_items(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    return Ok(Value::String(sprintf(fmt, items)))
  }
  // --- types -------------------------------------------------------------
  if name == "type_name" {
    return Ok(Value::String(args[0].type_name()))
  }
  if name.has_prefix("is_") {
    let ok = if name == "is_number" {
      args[0] is Value::Number(_)
    } else if name == "is_string" {
      args[0] is Value::String(_)
    } else if name == "is_boolean" {
      args[0] is Value::Bool(_)
    } else if name == "is_array" {
      args[0] is Value::Array(_)
    } else if name == "is_object" {
      args[0] is Value::Object(_)
    } else if name == "is_set" {
      args[0] is Value::Set(_)
    } else if name == "is_null" {
      args[0] is Value::Null
    } else {
      return Err(
        RegoError::make(RegoErrorKind::TypeError, "unknown builtin `" + name + "`"),
      )
    }
    return Ok(Value::Bool(ok))
  }
  if name == "to_number" {
    return match args[0] {
      Value::Number(d) => Ok(Value::Number(d))
      Value::String(s) =>
        match parse_decimal(s) {
          None =>
            Err(
              RegoError::make(
                RegoErrorKind::TypeError,
                "builtin `to_number` cannot parse `" + s + "`",
              ),
            )
          Some(d) => Ok(Value::Number(d))
        }
      other => Err(type_error(name, 0, "a number or numeric string", other))
    }
  }
  // --- sets --------------------------------------------------------------
  if name == "set" {
    return Ok(make_set([]))
  }
  if name == "union" || name == "intersection" {
    let outer = match want_items(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let sets : Array[Array[Value]] = []
    for v in outer {
      match v {
        Value::Set(items) => sets.push(items)
        other => return Err(type_error(name, 0, "a set of sets", other))
      }
    }
    if sets.length() == 0 {
      return Ok(make_set([]))
    }
    if name == "union" {
      let acc : Array[Value] = []
      for s in sets {
        for v in s {
          acc.push(v)
        }
      }
      return Ok(make_set(acc))
    }
    let acc : Array[Value] = []
    for v in sets[0] {
      let mut in_all = true
      for i = 1; i < sets.length(); i = i + 1 {
        let mut hit = false
        for w in sets[i] {
          if w.equals(v) {
            hit = true
          }
        }
        if !hit {
          in_all = false
        }
      }
      if in_all {
        acc.push(v)
      }
    }
    return Ok(make_set(acc))
  }
  // --- arrays and objects ------------------------------------------------
  if name == "array.concat" {
    let a = match want_items(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let b = match want_items(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let out : Array[Value] = []
    for v in a {
      out.push(v)
    }
    for v in b {
      out.push(v)
    }
    return Ok(Value::Array(out))
  }
  if name == "object.get" {
    let pairs = match want_object(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let key = match want_string(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let mut found = false
    let mut result = args[2]
    for kv in pairs {
      if kv.0 == key {
        found = true
        result = kv.1
      }
    }
    if found {
      return Ok(result)
    }
    return Ok(args[2])
  }
  if name == "object.keys" {
    let pairs = match want_object(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let keys : Array[Value] = []
    for kv in pairs {
      keys.push(Value::String(kv.0))
    }
    return Ok(make_set(keys))
  }
  if name == "object.union" {
    let a = match want_object(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let b = match want_object(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let merged : Array[(String, Value)] = []
    for kv in a {
      merged.push(kv)
    }
    for kv in b {
      merged.push(kv)
    }
    return Ok(make_object(merged))
  }
  // --- json --------------------------------------------------------------
  if name == "json.marshal" {
    return Ok(Value::String(args[0].to_json_string()))
  }
  if name == "json.unmarshal" {
    let s = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    return parse_json(s)
  }
  // --- regex -------------------------------------------------------------
  if name == "regex.is_valid" {
    let pattern = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    return Ok(Value::Bool(compile_regex(pattern) is Some(_)))
  }
  if name == "regex.match" {
    let pattern = match want_string(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let text = match want_string(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    return match compile_regex(pattern) {
      None =>
        Err(
          RegoError::make(
            RegoErrorKind::TypeError,
            "builtin `regex.match` received an invalid pattern `" + pattern + "`",
          ),
        )
      Some(r) =>
        match r.match_(text) {
          Some(m) => Ok(Value::Bool(m.matched()))
          None => Ok(Value::Bool(false))
        }
    }
  }
  // --- numbers -----------------------------------------------------------
  if name == "numbers.range" {
    let a = match want_number(name, args, 0) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let b = match want_number(name, args, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let from = a.to_int()
    let to = b.to_int()
    let out : Array[Value] = []
    if from <= to {
      let mut i = from
      while i <= to {
        out.push(Value::Number(i.to_double()))
        i = i + 1
      }
    } else {
      let mut i = from
      while i >= to {
        out.push(Value::Number(i.to_double()))
        i = i - 1
      }
    }
    return Ok(Value::Array(out))
  }
  Err(
    RegoError::make(
      RegoErrorKind::TypeError,
      "builtin `" + name + "` is declared but not implemented",
    ),
  )
}

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

///|
fn slice_chars(src : Array[Char], start : Int, count : Int) -> String {
  let out : Array[Char] = []
  let mut i = 0
  while i < count && start + i < src.length() {
    out.push(src[start + i])
    i = i + 1
  }
  String::from_array(out)
}

///| Whether a character is ASCII whitespace, matching Go's `strings.TrimSpace`
/// for the common cases.
fn is_space_char(c : Char) -> Bool {
  let n = c.to_int()
  n == 32 || n == 9 || n == 10 || n == 13 || n == 11 || n == 12
}

///|
fn trim_whitespace(s : String) -> String {
  let src = chars_of(s)
  let mut start = 0
  while start < src.length() && is_space_char(src[start]) {
    start = start + 1
  }
  let mut stop = src.length()
  while stop > start && is_space_char(src[stop - 1]) {
    stop = stop - 1
  }
  slice_chars(src, start, stop - start)
}

///| Index of the first occurrence of `sub` in `s` by code point, or `-1`.
fn index_of(s : String, sub : String) -> Int {
  let src = chars_of(s)
  let needle = chars_of(sub)
  if needle.length() == 0 {
    return 0
  }
  if needle.length() > src.length() {
    return -1
  }
  let mut i = 0
  while i + needle.length() <= src.length() {
    let mut matched = true
    let mut j = 0
    while j < needle.length() {
      if src[i + j].to_int() != needle[j].to_int() {
        matched = false
      }
      j = j + 1
    }
    if matched {
      return i
    }
    i = i + 1
  }
  -1
}

///| Replace every occurrence of `old` with `replacement`.
///
/// An empty `old` inserts `replacement` between every pair of code points and
/// at both ends, matching OPA's `strings.Replace(..., -1)` behaviour.
fn replace_all(s : String, old : String, replacement : String) -> String {
  if old.length() == 0 {
    let src = chars_of(s)
    let parts : Array[String] = [replacement]
    for c in src {
      parts.push(String::from_array([c]))
      parts.push(replacement)
    }
    return join_strings(parts, "")
  }
  let sb = StringBuilder::new()
  let src = chars_of(s)
  let needle = chars_of(old)
  let mut i = 0
  while i < src.length() {
    if i + needle.length() <= src.length() {
      let mut matched = true
      let mut j = 0
      while j < needle.length() {
        if src[i + j].to_int() != needle[j].to_int() {
          matched = false
        }
        j = j + 1
      }
      if matched {
        sb.write_string(replacement)
        i = i + needle.length()
        continue
      }
    }
    sb.write_char(src[i])
    i = i + 1
  }
  sb.to_string()
}

///| Compile a regular expression, returning `None` on a malformed pattern.
fn compile_regex(pattern : String) -> @regexp.Regexp? {
  try {
    Some(@regexp.compile(pattern))
  } catch {
    _ => None
  }
}

///| A pragmatic subset of Go's `sprintf`.
///
/// Supported verbs: `%v`, `%s`, `%d`, `%f`, `%q`, and `%%`. Width and
/// precision are honoured for `%f`; other flags are accepted and ignored.
fn sprintf(fmt : String, args : Array[Value]) -> String {
  let src = chars_of(fmt)
  let sb = StringBuilder::new()
  let mut i = 0
  let mut next_arg = 0
  while i < src.length() {
    if src[i].to_int() != 37 {
      sb.write_char(src[i])
      i = i + 1
      continue
    }
    // at '%'
    i = i + 1
    if i >= src.length() {
      sb.write_char((37).unsafe_to_char())
      break
    }
    if src[i].to_int() == 37 {
      sb.write_char((37).unsafe_to_char())
      i = i + 1
      continue
    }
    // skip flags and width
    while i < src.length() &&
      (src[i].to_int() == 43 ||
        src[i].to_int() == 45 ||
        src[i].to_int() == 32 ||
        src[i].to_int() == 48 ||
        (src[i].to_int() >= 48 && src[i].to_int() <= 57)) {
      i = i + 1
    }
    // precision
    let mut precision = 6
    if i < src.length() && src[i].to_int() == 46 {
      i = i + 1
      let mut digits = 0
      while i < src.length() && src[i].to_int() >= 48 && src[i].to_int() <= 57 {
        digits = digits * 10 + (src[i].to_int() - 48)
        i = i + 1
      }
      precision = digits
    }
    if i >= src.length() {
      break
    }
    let verb = src[i].to_int()
    i = i + 1
    let arg = if next_arg < args.length() {
      args[next_arg]
    } else {
      Value::Null
    }
    next_arg = next_arg + 1
    if verb == 118 || verb == 115 {
      // %v, %s
      match arg {
        Value::String(s) => sb.write_string(s)
        other => sb.write_string(other.to_rego_string())
      }
    } else if verb == 113 {
      // %q
      match arg {
        Value::String(s) => sb.write_string("\"" + s + "\"")
        other => sb.write_string(other.to_rego_string())
      }
    } else if verb == 100 {
      // %d
      match arg {
        Value::Number(d) => sb.write_string(d.to_int().to_string())
        other => sb.write_string(other.to_rego_string())
      }
    } else if verb == 102 {
      // %f
      match arg {
        Value::Number(d) => sb.write_string(format_fixed(d, precision))
        other => sb.write_string(other.to_rego_string())
      }
    } else {
      sb.write_char((37).unsafe_to_char())
      sb.write_char(src[i - 1])
    }
  }
  sb.to_string()
}

///| Fixed-point formatting with `precision` digits after the decimal point.
fn format_fixed(d : Double, precision : Int) -> String {
  if precision <= 0 {
    return d.round().to_int().to_string()
  }
  let mut scale = 1.0
  let mut k = 0
  while k < precision {
    scale = scale * 10.0
    k = k + 1
  }
  let negative = d < 0.0
  let magnitude = if negative { -d } else { d }
  let scaled = (magnitude * scale).round()
  let whole = (scaled / scale).to_int()
  let frac = (scaled - (whole.to_double() * scale)).to_int()
  let frac_text = frac.to_string()
  let padding = StringBuilder::new()
  let mut pad = precision - frac_text.length()
  while pad > 0 {
    padding.write_string("0")
    pad = pad - 1
  }
  let sign = if negative { "-" } else { "" }
  sign + whole.to_string() + "." + padding.to_string() + frac_text
}
