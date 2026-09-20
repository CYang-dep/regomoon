///| The Rego evaluator.
///
/// ## Evaluation model
///
/// A rule body is a conjunction of statements. Statements can introduce
/// bindings (`x := 1`, `some x in xs`, `x = f(y)`), so evaluating a body yields
/// a **set of binding environments** rather than a single one. Rule bodies are
/// therefore evaluated by [eval_body], which returns every environment that
/// satisfies the remaining statements.
///
/// ## Iteration
///
/// Iteration is explicit, through `some ... in ...`, comprehensions, and
/// `every`. An index expression whose index is an unbound variable is an error
/// rather than an implicit iteration; this is the one place where the engine is
/// deliberately stricter than OPA. See the README.

///|
/// The maximum rule-reference recursion depth before the engine gives up.
/// Guards against cyclic definitions such as `p := p`.
const MAX_DEPTH : Int = 100

///|
/// Variable bindings for one evaluation branch.
///
/// A small association list is used instead of a hash map because scopes are
/// tiny, frequently copied during search, and need deterministic iteration.
priv struct Scope {
  vars : Array[(String, Value)]
}

///|
fn Scope::empty() -> Scope {
  { vars: [] }
}

///|
fn Scope::clone(self : Scope) -> Scope {
  { vars: self.vars.copy() }
}

///|
fn Scope::get(self : Scope, name : String) -> Value? {
  let mut found : Value? = None
  for kv in self.vars {
    if kv.0 == name {
      found = Some(kv.1)
    }
  }
  found
}

///|
fn Scope::is_bound(self : Scope, name : String) -> Bool {
  self.get(name) is Some(_)
}

///|
fn Scope::set(self : Scope, name : String, value : Value) -> Unit {
  let mut replaced = false
  for i = 0; i < self.vars.length(); i = i + 1 {
    if self.vars[i].0 == name {
      self.vars[i] = (name, value)
      replaced = true
    }
  }
  if !replaced {
    self.vars.push((name, value))
  }
}

///|
/// Everything an evaluation needs besides the expression itself.
priv struct Env {
  md : Module
  /// The root `data` document, with package results layered on top on demand.
  data : Value
  input : Value
  /// Memoisation of argless rules for this evaluation. Rules are pure — they
  /// read only the module, `data` and `input` — so a result computed once is
  /// valid for every reference inside the same query. `with` creates a child
  /// environment with fresh maps, so an overridden input never pollutes it.
  done : Map[String, Bool]
  result : Map[String, Value]
}

///|
fn Env::make(md : Module, data : Value, input : Value) -> Env {
  { md, data, input, done: Map([]), result: Map([]) }
}

// ---------------------------------------------------------------------------
// Small value helpers
// ---------------------------------------------------------------------------

///|
/// The value of `x in collection`.
fn contains_value(collection : Value, item : Value) -> Bool? {
  match collection {
    Value::Array(items) => {
      let mut hit = false
      for v in items {
        if v.equals(item) {
          hit = true
        }
      }
      Some(hit)
    }
    Value::Set(items) => {
      let mut hit = false
      for v in items {
        if v.equals(item) {
          hit = true
        }
      }
      Some(hit)
    }
    Value::Object(pairs) =>
      match item {
        Value::String(key) => {
          let mut hit = false
          for kv in pairs {
            if kv.0 == key {
              hit = true
            }
          }
          Some(hit)
        }
        _ => None
      }
    _ => None
  }
}

///|
/// Look up a field on a value, returning `None` when absent or not an object.
fn index_value(base : Value, key : Value) -> Value? {
  match base {
    Value::Object(pairs) =>
      match key {
        Value::String(name) => {
          let mut found : Value? = None
          for kv in pairs {
            if kv.0 == name {
              found = Some(kv.1)
            }
          }
          found
        }
        _ => None
      }
    Value::Array(items) =>
      match key {
        Value::Number(d) => {
          let i = d.to_int()
          if i >= 0 && i < items.length() {
            Some(items[i])
          } else {
            None
          }
        }
        _ => None
      }
    _ => None
  }
}

///|
/// Interpret an expression as a plain dotted identifier path, if it is one.
/// `data.a.b`, `input.x.y` and bare names all qualify; anything with an index,
/// call or literal does not.
fn flatten_path(e : Expr) -> Array[String]? {
  match e {
    Expr::EVar(name) => Some([name])
    Expr::EField(base, field) =>
      match flatten_path(base) {
        None => None
        Some(segments) => {
          let out : Array[String] = []
          for s in segments {
            out.push(s)
          }
          out.push(field)
          Some(out)
        }
      }
    _ => None
  }
}

///|
/// Walk a path of string keys into a value.
fn walk_path(base : Value, segments : Array[String]) -> Value? {
  let mut current = base
  for segment in segments {
    match index_value(current, Value::String(segment)) {
      None => return None
      Some(next) => current = next
    }
  }
  Some(current)
}

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

///|
fn eval_expr(
  env : Env,
  scope : Scope,
  depth : Int,
  e : Expr,
) -> Result[Value?, RegoError] {
  match e {
    Expr::ENull => Ok(Some(Value::Null))
    Expr::EBool(b) => Ok(Some(Value::Bool(b)))
    Expr::ENumber(d) => Ok(Some(Value::Number(d)))
    Expr::EString(s) => Ok(Some(Value::String(s)))
    Expr::EArray(items) => {
      let out : Array[Value] = []
      for item in items {
        let v = match eval_expr(env, scope, depth, item) {
          Err(err) => return Err(err)
          Ok(v) => v
        }
        match v {
          None => return Ok(None)
          Some(x) => out.push(x)
        }
      }
      Ok(Some(Value::Array(out)))
    }
    Expr::ESet(items) => {
      let out : Array[Value] = []
      for item in items {
        let v = match eval_expr(env, scope, depth, item) {
          Err(err) => return Err(err)
          Ok(v) => v
        }
        match v {
          None => return Ok(None)
          Some(x) => out.push(x)
        }
      }
      Ok(Some(make_set(out)))
    }
    Expr::EObject(pairs) => {
      let out : Array[(String, Value)] = []
      for kv in pairs {
        let k = match eval_expr(env, scope, depth, kv.0) {
          Err(err) => return Err(err)
          Ok(v) => v
        }
        let v = match eval_expr(env, scope, depth, kv.1) {
          Err(err) => return Err(err)
          Ok(v) => v
        }
        match (k, v) {
          (Some(Value::String(key)), Some(value)) => out.push((key, value))
          (Some(other), _) =>
            return Err(
              RegoError::make(
                RegoErrorKind::TypeError,
                "object keys must be strings, got " + other.type_name(),
              ),
            )
          _ => return Ok(None)
        }
      }
      Ok(Some(make_object(out)))
    }
    Expr::EVar(_) | Expr::EField(_, _) =>
      match flatten_path(e) {
        Some(path) => eval_path(env, scope, depth, path)
        None =>
          match e {
            Expr::EField(base, field) => {
              let b = match eval_expr(env, scope, depth, base) {
                Err(err) => return Err(err)
                Ok(v) => v
              }
              match b {
                None => Ok(None)
                Some(value) => Ok(index_value(value, Value::String(field)))
              }
            }
            _ => Ok(None)
          }
      }
    Expr::EIndex(base, index) => {
      let b = match eval_expr(env, scope, depth, base) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      let i = match eval_expr(env, scope, depth, index) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      match (b, i) {
        (Some(base_value), Some(key)) => Ok(index_value(base_value, key))
        _ => Ok(None)
      }
    }
    Expr::ENegate(inner) => {
      let v = match eval_expr(env, scope, depth, inner) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      match v {
        Some(Value::Number(d)) => Ok(Some(Value::Number(-d)))
        Some(other) =>
          Err(
            RegoError::make(
              RegoErrorKind::TypeError,
              "unary `-` requires a number, got " + other.type_name(),
            ),
          )
        None => Ok(None)
      }
    }
    Expr::ECall(name, args) => eval_call(env, scope, depth, name, args)
    Expr::EBinary(op, left, right) => {
      let l = match eval_expr(env, scope, depth, left) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      let r = match eval_expr(env, scope, depth, right) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      match (l, r) {
        (Some(lv), Some(rv)) => eval_binary(op, lv, rv)
        _ => Ok(None)
      }
    }
    Expr::EArrayComprehension(head, body) => {
      let scopes = match eval_body(env, depth, body, 0, scope) {
        Err(err) => return Err(err)
        Ok(s) => s
      }
      let out : Array[Value] = []
      for s in scopes {
        match eval_expr(env, s, depth, head) {
          Err(err) => return Err(err)
          Ok(Some(v)) => out.push(v)
          Ok(None) => ()
        }
      }
      Ok(Some(Value::Array(out)))
    }
    Expr::ESetComprehension(head, body) => {
      let scopes = match eval_body(env, depth, body, 0, scope) {
        Err(err) => return Err(err)
        Ok(s) => s
      }
      let out : Array[Value] = []
      for s in scopes {
        match eval_expr(env, s, depth, head) {
          Err(err) => return Err(err)
          Ok(Some(v)) => out.push(v)
          Ok(None) => ()
        }
      }
      Ok(Some(make_set(out)))
    }
    Expr::EObjectComprehension(key, value, body) => {
      let scopes = match eval_body(env, depth, body, 0, scope) {
        Err(err) => return Err(err)
        Ok(s) => s
      }
      let out : Array[(String, Value)] = []
      for s in scopes {
        let k = match eval_expr(env, s, depth, key) {
          Err(err) => return Err(err)
          Ok(v) => v
        }
        let v = match eval_expr(env, s, depth, value) {
          Err(err) => return Err(err)
          Ok(v) => v
        }
        match (k, v) {
          (Some(Value::String(name)), Some(item)) => out.push((name, item))
          (Some(other), _) =>
            return Err(
              RegoError::make(
                RegoErrorKind::TypeError,
                "object comprehension keys must be strings, got " +
                other.type_name(),
              ),
            )
          _ => ()
        }
      }
      Ok(Some(make_object(out)))
    }
  }
}

///|
fn eval_path(
  env : Env,
  scope : Scope,
  depth : Int,
  path : Array[String],
) -> Result[Value?, RegoError] {
  if path.length() == 0 {
    return Ok(None)
  }
  let head = path[0]
  let rest : Array[String] = []
  for i = 1; i < path.length(); i = i + 1 {
    rest.push(path[i])
  }
  if head == "input" {
    return Ok(walk_path(env.input, rest))
  }
  if head == "data" {
    return resolve_data_path(env, depth, rest)
  }
  // a bound variable
  match scope.get(head) {
    Some(v) => return Ok(walk_path(v, rest))
    None => ()
  }
  // an import alias
  for decl in env.md.imports {
    if decl.local_name == head {
      let combined : Array[String] = []
      // an import path such as `data.roles` is spelled below `data`
      let mut start = 0
      if decl.path.length() > 0 && decl.path[0] == "data" {
        start = 1
      }
      for i = start; i < decl.path.length(); i = i + 1 {
        combined.push(decl.path[i])
      }
      for s in rest {
        combined.push(s)
      }
      let resolved = match resolve_data_path(env, depth, combined) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      if resolved is Some(_) {
        return Ok(resolved)
      }
    }
  }
  // a rule in this module
  if is_rule_name(env.md, head) {
    let value = match eval_rule_group(env, depth + 1, head) {
      Err(err) => return Err(err)
      Ok(v) => v
    }
    return Ok(walk_path_opt(value, rest))
  }
  Ok(None)
}

///|
fn walk_path_opt(value : Value?, segments : Array[String]) -> Value? {
  match value {
    None => None
    Some(v) => walk_path(v, segments)
  }
}

///|
/// Resolve a path below `data`, preferring this module's own rules.
fn resolve_data_path(
  env : Env,
  depth : Int,
  segments : Array[String],
) -> Result[Value?, RegoError] {
  let pkg = env.md.package_path
  if segments.length() > pkg.length() {
    let mut matches = true
    for i = 0; i < pkg.length(); i = i + 1 {
      if segments[i] != pkg[i] {
        matches = false
      }
    }
    if matches {
      let rule_name = segments[pkg.length()]
      if is_rule_name(env.md, rule_name) {
        let value = match eval_rule_group(env, depth + 1, rule_name) {
          Err(err) => return Err(err)
          Ok(v) => v
        }
        let tail : Array[String] = []
        for i = pkg.length() + 1; i < segments.length(); i = i + 1 {
          tail.push(segments[i])
        }
        return Ok(walk_path_opt(value, tail))
      }
    }
  }
  Ok(walk_path(env.data, segments))
}

///|
fn is_rule_name(md : Module, name : String) -> Bool {
  let mut found = false
  for r in md.rules {
    if r.name == name && r.args.length() == 0 {
      found = true
    }
  }
  found
}

///|
/// Evaluate a binary operator over two defined values.
fn eval_binary(op : String, l : Value, r : Value) -> Result[Value?, RegoError] {
  if op == "==" {
    return Ok(Some(Value::Bool(l.equals(r))))
  }
  if op == "!=" {
    return Ok(Some(Value::Bool(!l.equals(r))))
  }
  if op == "=" || op == ":=" {
    return Ok(Some(Value::Bool(l.equals(r))))
  }
  if op == "<" || op == "<=" || op == ">" || op == ">=" {
    let c = l.compare(r)
    let result = if op == "<" {
      c < 0
    } else if op == "<=" {
      c <= 0
    } else if op == ">" {
      c > 0
    } else {
      c >= 0
    }
    return Ok(Some(Value::Bool(result)))
  }
  if op == "in" {
    return match contains_value(r, l) {
      None =>
        Err(
          RegoError::make(
            RegoErrorKind::TypeError,
            "`in` requires a collection on the right-hand side, got " +
            r.type_name(),
          ),
        )
      Some(hit) => Ok(Some(Value::Bool(hit)))
    }
  }
  if op == "+" {
    match (l, r) {
      (Value::Number(a), Value::Number(b)) =>
        return Ok(Some(Value::Number(a + b)))
      (Value::String(a), Value::String(b)) =>
        return Ok(Some(Value::String(a + b)))
      (Value::Set(a), Value::Set(b)) => {
        let merged : Array[Value] = []
        for v in a {
          merged.push(v)
        }
        for v in b {
          merged.push(v)
        }
        return Ok(Some(make_set(merged)))
      }
      (Value::Array(a), Value::Array(b)) => {
        let merged : Array[Value] = []
        for v in a {
          merged.push(v)
        }
        for v in b {
          merged.push(v)
        }
        return Ok(Some(Value::Array(merged)))
      }
      _ =>
        return Err(
          RegoError::make(
            RegoErrorKind::TypeError,
            "`+` is not defined for " + l.type_name() + " and " + r.type_name(),
          ),
        )
    }
  }
  if op == "-" {
    match (l, r) {
      (Value::Number(a), Value::Number(b)) =>
        return Ok(Some(Value::Number(a - b)))
      (Value::Set(a), Value::Set(_)) => {
        let out : Array[Value] = []
        for v in a {
          if !r.set_contains(v) {
            out.push(v)
          }
        }
        return Ok(Some(make_set(out)))
      }
      _ =>
        return Err(
          RegoError::make(
            RegoErrorKind::TypeError,
            "`-` is not defined for " + l.type_name() + " and " + r.type_name(),
          ),
        )
    }
  }
  if op == "&" {
    match (l, r) {
      (Value::Set(a), Value::Set(_)) => {
        let out : Array[Value] = []
        for v in a {
          if r.set_contains(v) {
            out.push(v)
          }
        }
        return Ok(Some(make_set(out)))
      }
      _ =>
        return Err(
          RegoError::make(
            RegoErrorKind::TypeError,
            "`&` requires sets, got " + l.type_name() + " and " + r.type_name(),
          ),
        )
    }
  }
  if op == "|" {
    match (l, r) {
      (Value::Set(a), Value::Set(b)) => {
        let out : Array[Value] = []
        for v in a {
          out.push(v)
        }
        for v in b {
          out.push(v)
        }
        return Ok(Some(make_set(out)))
      }
      _ =>
        return Err(
          RegoError::make(
            RegoErrorKind::TypeError,
            "`|` requires sets, got " + l.type_name() + " and " + r.type_name(),
          ),
        )
    }
  }
  // remaining operators are arithmetic on numbers
  match (l, r) {
    (Value::Number(a), Value::Number(b)) => {
      if op == "*" {
        return Ok(Some(Value::Number(a * b)))
      }
      if op == "%" {
        if b == 0.0 {
          return Err(
            RegoError::make(RegoErrorKind::DivideByZero, "modulo by zero"),
          )
        }
        return Ok(Some(Value::Number(a % b)))
      }
      if op == "/" {
        if b == 0.0 {
          return Err(
            RegoError::make(RegoErrorKind::DivideByZero, "division by zero"),
          )
        }
        return Ok(Some(Value::Number(a / b)))
      }
      Err(
        RegoError::make(
          RegoErrorKind::TypeError,
          "unknown operator `" + op + "`",
        ),
      )
    }
    _ =>
      Err(
        RegoError::make(
          RegoErrorKind::TypeError,
          "operator `" +
          op +
          "` requires numbers, got " +
          l.type_name() +
          " and " +
          r.type_name(),
        ),
      )
  }
}

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------

///|
fn eval_call(
  env : Env,
  scope : Scope,
  depth : Int,
  name : String,
  args : Array[Expr],
) -> Result[Value?, RegoError] {
  let values : Array[Value] = []
  for a in args {
    let v = match eval_expr(env, scope, depth, a) {
      Err(err) => return Err(err)
      Ok(v) => v
    }
    match v {
      None => return Ok(None)
      Some(x) => values.push(x)
    }
  }
  if is_builtin(name) {
    return match call_builtin(name, values) {
      None => Ok(None)
      Some(Ok(v)) => Ok(Some(v))
      Some(Err(e)) => Err(e)
    }
  }
  // a parameterised rule
  eval_rule_call(env, depth, name, values)
}

///|
fn eval_rule_call(
  env : Env,
  depth : Int,
  name : String,
  args : Array[Value],
) -> Result[Value?, RegoError] {
  let clauses : Array[Rule] = []
  for r in env.md.rules {
    if r.name == name && r.args.length() == args.length() && !r.is_default {
      clauses.push(r)
    }
  }
  if clauses.length() == 0 {
    return Ok(None)
  }
  let values : Array[Value] = []
  let scores : Array[Scope] = []
  let owners : Array[Rule] = []
  for clause in clauses {
    let inner = Scope::empty()
    for i = 0; i < clause.args.length(); i = i + 1 {
      inner.set(clause.args[i], args[i])
    }
    let scopes = match eval_body(env, depth, clause.body, 0, inner) {
      Err(err) => return Err(err)
      Ok(s) => s
    }
    for s in scopes {
      let v = match rule_head_value(env, depth, clause, s) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      match v {
        None => ()
        Some(value) => {
          values.push(value)
          scores.push(s)
          owners.push(clause)
        }
      }
    }
  }
  match clause_kind(clauses) {
    RuleKind::PartialSetRule => Ok(Some(make_set(values)))
    RuleKind::PartialObjectRule => {
      let pairs : Array[(String, Value)] = []
      for i = 0; i < values.length(); i = i + 1 {
        let key = match rule_key_value(env, depth, owners[i], scores[i]) {
          Err(err) => return Err(err)
          Ok(v) => v
        }
        match key {
          Some(Value::String(k)) => pairs.push((k, values[i]))
          Some(other) =>
            return Err(
              RegoError::make(
                RegoErrorKind::TypeError,
                "partial object keys must be strings, got " + other.type_name(),
              ),
            )
          None => ()
        }
      }
      Ok(Some(make_object(pairs)))
    }
    RuleKind::CompleteRule =>
      match single_value("rule `" + name + "`", values) {
        Err(e) => Err(e)
        Ok(v) => Ok(v)
      }
  }
}

// ---------------------------------------------------------------------------
// Rules
// ---------------------------------------------------------------------------

///|
fn clause_kind(clauses : Array[Rule]) -> RuleKind {
  if clauses.length() == 0 {
    RuleKind::CompleteRule
  } else {
    clauses[0].kind
  }
}

///|
/// Collapse the values produced by a complete rule: `None` when there are no
/// results, the value when all results agree, and a conflict error otherwise.
fn single_value(
  what : String,
  values : Array[Value],
) -> Result[Value?, RegoError] {
  if values.length() == 0 {
    return Ok(None)
  }
  let first = values[0]
  for v in values {
    if !v.equals(first) {
      return Err(
        RegoError::make(
          RegoErrorKind::ConflictError,
          what +
          " produced conflicting values " +
          first.to_rego_string() +
          " and " +
          v.to_rego_string(),
        ),
      )
    }
  }
  Ok(Some(first))
}

///|
fn rule_head_value(
  env : Env,
  depth : Int,
  rule : Rule,
  scope : Scope,
) -> Result[Value?, RegoError] {
  match rule.value {
    None => Ok(Some(Value::Bool(true)))
    Some(v) => eval_expr(env, scope, depth, v)
  }
}

///|
fn rule_key_value(
  env : Env,
  depth : Int,
  rule : Rule,
  scope : Scope,
) -> Result[Value?, RegoError] {
  match rule.key {
    None => Ok(None)
    Some(k) => eval_expr(env, scope, depth, k)
  }
}

///|
/// Evaluate every rule with the given name, memoised per query.
///
/// A diamond-shaped rule graph would otherwise evaluate the same rule once per
/// path; the cache turns that into once per query. Errors are never cached.
fn eval_rule_group(
  env : Env,
  depth : Int,
  name : String,
) -> Result[Value?, RegoError] {
  match env.done.get(name) {
    Some(true) => return Ok(env.result.get(name))
    Some(false) => return Ok(None)
    None => ()
  }
  match eval_rule_group_uncached(env, depth, name) {
    Err(e) => Err(e)
    Ok(res) => {
      match res {
        Some(v) => {
          env.done.set(name, true)
          env.result.set(name, v)
        }
        None => env.done.set(name, false)
      }
      Ok(res)
    }
  }
}

///|
/// Evaluate every rule with the given name, applying `default` rules only
/// when no other clause produces a value.
fn eval_rule_group_uncached(
  env : Env,
  depth : Int,
  name : String,
) -> Result[Value?, RegoError] {
  if depth > MAX_DEPTH {
    return Err(
      RegoError::make(
        RegoErrorKind::SafetyError,
        "rule `" +
        name +
        "` exceeded the recursion limit of " +
        MAX_DEPTH.to_string(),
      ),
    )
  }
  let clauses : Array[Rule] = []
  let defaults : Array[Rule] = []
  for r in env.md.rules {
    if r.name == name && r.args.length() == 0 {
      if r.is_default {
        defaults.push(r)
      } else {
        clauses.push(r)
      }
    }
  }
  if clauses.length() > 0 {
    // all non-default clauses of a name must agree on the rule kind
    let kind = clause_kind(clauses)
    for c in clauses {
      if c.kind != kind {
        return Err(
          RegoError::make(
            RegoErrorKind::CompileError,
            "rule `" +
            name +
            "` mixes complete, partial set and partial object clauses",
          ),
        )
      }
    }
    let values : Array[Value] = []
    let scopes : Array[Scope] = []
    let owners : Array[Rule] = []
    for clause in clauses {
      let start = match
        eval_body(env, depth + 1, clause.body, 0, Scope::empty()) {
        Err(err) => return Err(err)
        Ok(s) => s
      }
      for s in start {
        let v = match rule_head_value(env, depth + 1, clause, s) {
          Err(err) => return Err(err)
          Ok(v) => v
        }
        match v {
          None => ()
          Some(value) => {
            values.push(value)
            scopes.push(s)
            owners.push(clause)
          }
        }
      }
    }
    if kind == RuleKind::PartialSetRule {
      return Ok(Some(make_set(values)))
    }
    if kind == RuleKind::PartialObjectRule {
      let pairs : Array[(String, Value)] = []
      let seen : Array[(String, Value)] = []
      for i = 0; i < values.length(); i = i + 1 {
        let key = match rule_key_value(env, depth + 1, owners[i], scopes[i]) {
          Err(err) => return Err(err)
          Ok(v) => v
        }
        match key {
          None => ()
          Some(Value::String(k)) => {
            for earlier in seen {
              if earlier.0 == k && !earlier.1.equals(values[i]) {
                return Err(
                  RegoError::make(
                    RegoErrorKind::ConflictError,
                    "partial object rule `" +
                    name +
                    "` produced conflicting values for key `" +
                    k +
                    "`",
                  ),
                )
              }
            }
            seen.push((k, values[i]))
            pairs.push((k, values[i]))
          }
          Some(other) =>
            return Err(
              RegoError::make(
                RegoErrorKind::TypeError,
                "partial object keys must be strings, got " + other.type_name(),
              ),
            )
        }
      }
      return Ok(Some(make_object(pairs)))
    }
    let complete = match single_value("rule `" + name + "`", values) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    if complete is Some(_) {
      return Ok(complete)
    }
  }
  // no clause produced a value: fall back to `default`
  for d in defaults {
    let s = match eval_body(env, depth + 1, d.body, 0, Scope::empty()) {
      Err(err) => return Err(err)
      Ok(s) => s
    }
    for scope in s {
      let v = match rule_head_value(env, depth + 1, d, scope) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      if v is Some(_) {
        return Ok(v)
      }
    }
  }
  Ok(None)
}

// ---------------------------------------------------------------------------
// Bodies
// ---------------------------------------------------------------------------

///|
/// Evaluate `stmts[start..]`, returning every binding environment that
/// satisfies all of them.
fn eval_body(
  env : Env,
  depth : Int,
  stmts : Array[Stmt],
  start : Int,
  scope : Scope,
) -> Result[Array[Scope], RegoError] {
  if start >= stmts.length() {
    return Ok([scope])
  }
  let stmt = stmts[start]
  match stmt {
    Stmt::SomeVars(names) => {
      // Declaring locals has no effect on our binding model.
      let _ = names
      eval_body(env, depth, stmts, start + 1, scope)
    }
    Stmt::Negate(expr) => {
      let v = match eval_expr(env, scope, depth, expr) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      let satisfied = match v {
        Some(Value::Bool(true)) => true
        Some(Value::Bool(false)) => false
        Some(other) =>
          return Err(
            RegoError::make(
              RegoErrorKind::TypeError,
              "`not` requires a boolean, got " + other.type_name(),
            ),
          )
        // an undefined expression is not satisfied, so `not` succeeds
        None => false
      }
      if satisfied {
        Ok([])
      } else {
        eval_body(env, depth, stmts, start + 1, scope)
      }
    }
    Stmt::SomeIn(names, collection) => {
      let value = match eval_expr(env, scope, depth, collection) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      let entries = match value {
        None => return Ok([])
        Some(v) => enumerate(v)
      }
      let results : Array[Scope] = []
      for entry in entries {
        let next = scope.clone()
        if names.length() == 1 {
          next.set(names[0], entry.1)
        } else {
          next.set(names[0], entry.0)
          next.set(names[1], entry.1)
        }
        let branch = match eval_body(env, depth, stmts, start + 1, next) {
          Err(err) => return Err(err)
          Ok(s) => s
        }
        for s in branch {
          results.push(s)
        }
      }
      Ok(results)
    }
    Stmt::Every(names, collection, body) => {
      let value = match eval_expr(env, scope, depth, collection) {
        Err(err) => return Err(err)
        Ok(v) => v
      }
      let entries = match value {
        None => return Ok([])
        Some(v) => enumerate(v)
      }
      for entry in entries {
        let inner = scope.clone()
        if names.length() == 1 {
          inner.set(names[0], entry.1)
        } else {
          inner.set(names[0], entry.0)
          inner.set(names[1], entry.1)
        }
        let branch = match eval_body(env, depth, body, 0, inner) {
          Err(err) => return Err(err)
          Ok(s) => s
        }
        if branch.length() == 0 {
          return Ok([])
        }
      }
      eval_body(env, depth, stmts, start + 1, scope)
    }
    Stmt::WithInput(expr, replacement) =>
      eval_with(env, depth, stmts, start, scope, expr, replacement, false)
    Stmt::NegateWithInput(expr, replacement) =>
      eval_with(env, depth, stmts, start, scope, expr, replacement, true)
    Stmt::Test(expr) => eval_test(env, depth, stmts, start, scope, expr)
  }
}

///|
/// Evaluate `<expr> with input as <replacement>`.
///
/// The replacement document is evaluated in the enclosing scope, then `expr`
/// runs against a child environment whose `input` is that document. Bindings
/// made inside do not leak out, matching Rego.
fn eval_with(
  env : Env,
  depth : Int,
  stmts : Array[Stmt],
  start : Int,
  scope : Scope,
  expr : Expr,
  replacement : Expr,
  negate : Bool,
) -> Result[Array[Scope], RegoError] {
  let v = match eval_expr(env, scope, depth, replacement) {
    Err(err) => return Err(err)
    Ok(v) => v
  }
  let child : Env = match v {
    // overriding with an undefined document leaves the statement unsatisfied
    None => return Ok([])
    Some(x) => Env::make(env.md, env.data, x)
  }
  let inner = match eval_expr(child, scope, depth, expr) {
    Err(err) => return Err(err)
    Ok(v) => v
  }
  let ok = match inner {
    Some(Value::Bool(b)) => if negate { !b } else { b }
    Some(other) =>
      return Err(
        RegoError::make(
          RegoErrorKind::TypeError,
          "`with` requires a boolean expression, got " + other.type_name(),
        ),
      )
    // an undefined expression is unsatisfied, so `not` succeeds
    None => negate
  }
  if ok {
    eval_body(env, depth, stmts, start + 1, scope)
  } else {
    Ok([])
  }
}

///|
/// Evaluate a `Test` statement, handling binding forms.
fn eval_test(
  env : Env,
  depth : Int,
  stmts : Array[Stmt],
  start : Int,
  scope : Scope,
  expr : Expr,
) -> Result[Array[Scope], RegoError] {
  let as_binary = match expr {
    Expr::EBinary(op, left, right) => Some((op, left, right))
    _ => None
  }
  match as_binary {
    None => fallthrough_test(env, depth, stmts, start, scope, expr)
    Some(parts) => {
      let op = parts.0
      let left = parts.1
      let right = parts.2
      if op == ":=" || op == "=" {
        match left {
          Expr::EVar(name) =>
            if !scope.is_bound(name) {
              let v = match eval_expr(env, scope, depth, right) {
                Err(err) => return Err(err)
                Ok(v) => v
              }
              return match v {
                None =>
                  Err(
                    RegoError::make(
                      RegoErrorKind::UndefinedError,
                      "variable `" + name + "` was assigned an undefined value",
                    ),
                  )
                Some(value) => {
                  let next = scope.clone()
                  next.set(name, value)
                  eval_body(env, depth, stmts, start + 1, next)
                }
              }
            }
          _ => ()
        }
        return test_pair(env, depth, stmts, start, scope, left, right)
      }
      if op == "in" {
        match left {
          Expr::EVar(name) =>
            if !scope.is_bound(name) {
              let v = match eval_expr(env, scope, depth, right) {
                Err(err) => return Err(err)
                Ok(v) => v
              }
              let entries = match v {
                None => return Ok([])
                Some(collection) => enumerate(collection)
              }
              let results : Array[Scope] = []
              for entry in entries {
                let next = scope.clone()
                next.set(name, entry.1)
                let branch = match
                  eval_body(env, depth, stmts, start + 1, next) {
                  Err(err) => return Err(err)
                  Ok(s) => s
                }
                for s in branch {
                  results.push(s)
                }
              }
              return Ok(results)
            }
          _ => ()
        }
      }
      fallthrough_test(env, depth, stmts, start, scope, expr)
    }
  }
}

///|
/// Test two expressions for equality of their evaluated values.
fn test_pair(
  env : Env,
  depth : Int,
  stmts : Array[Stmt],
  start : Int,
  scope : Scope,
  left : Expr,
  right : Expr,
) -> Result[Array[Scope], RegoError] {
  let lv = match eval_expr(env, scope, depth, left) {
    Err(err) => return Err(err)
    Ok(v) => v
  }
  let rv = match eval_expr(env, scope, depth, right) {
    Err(err) => return Err(err)
    Ok(v) => v
  }
  match (lv, rv) {
    (Some(a), Some(b)) =>
      if a.equals(b) {
        eval_body(env, depth, stmts, start + 1, scope)
      } else {
        Ok([])
      }
    _ => Ok([])
  }
}

///|
/// The fallback case: a body expression that must evaluate to `true`.
fn fallthrough_test(
  env : Env,
  depth : Int,
  stmts : Array[Stmt],
  start : Int,
  scope : Scope,
  expr : Expr,
) -> Result[Array[Scope], RegoError] {
  let v = match eval_expr(env, scope, depth, expr) {
    Err(err) => return Err(err)
    Ok(v) => v
  }
  match v {
    None => Ok([])
    Some(Value::Bool(true)) => eval_body(env, depth, stmts, start + 1, scope)
    Some(Value::Bool(false)) => Ok([])
    Some(other) =>
      Err(
        RegoError::make(
          RegoErrorKind::TypeError,
          "a rule body expression must be a boolean, got " + other.type_name(),
        ),
      )
  }
}

///|
fn enumerate(collection : Value) -> Array[(Value, Value)] {
  let out : Array[(Value, Value)] = []
  match collection {
    Value::Array(items) =>
      for i = 0; i < items.length(); i = i + 1 {
        out.push((Value::Number(i.to_double()), items[i]))
      }
    Value::Set(items) =>
      for item in items {
        out.push((item, item))
      }
    Value::Object(pairs) =>
      for kv in pairs {
        out.push((Value::String(kv.0), kv.1))
      }
    _ => ()
  }
  out
}
