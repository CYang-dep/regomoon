///| The public API of the engine.
///
/// ```moonbit
/// let policy = match @regomoon.Policy::compile(source) {
///   Err(e) => return Err(e)
///   Ok(p) =>
///     match p.with_input_json(input) {
///       Err(e) => return Err(e)
///       Ok(p) => p
///     }
/// }
/// let allowed = policy.allow("allow")?
/// ```
///
/// A [Policy] bundles a compiled module with the `data` and `input` documents
/// it is evaluated against. Every evaluation entry point returns the value the
/// rule produced, or `None` when the rule is undefined — Rego distinguishes
/// "undefined" from "false", and so does this engine.

///| A compiled Rego module plus the documents it is evaluated against.
pub(all) struct Policy {
  md : Module
  data : Value
  input : Value
}

///| Compile Rego source text into a policy.
pub fn Policy::compile(source : String) -> Result[Policy, RegoError] {
  match parse_module(source) {
    Err(e) => Err(e)
    Ok(md) => Ok({ md: md, data: make_object([]), input: Value::Null })
  }
}

///| The `package` path this policy declares.
pub fn Policy::package_path(self : Policy) -> Array[String] {
  self.md.package_path
}

///| The `package` path rendered as a dotted string.
pub fn Policy::package_name(self : Policy) -> String {
  render_path(self.md.package_path)
}

///|
fn Policy::env(self : Policy) -> Env {
  { md: self.md, data: self.data, input: self.input }
}

///| Replace the `data` document.
pub fn Policy::with_data(self : Policy, data : Value) -> Policy {
  { md: self.md, data: data, input: self.input }
}

///| Replace the `input` document.
pub fn Policy::with_input(self : Policy, input : Value) -> Policy {
  { md: self.md, data: self.data, input: input }
}

///| Replace the `data` document from a JSON string.
pub fn Policy::with_data_json(self : Policy, text : String) -> Result[Policy, RegoError] {
  match parse_json(text) {
    Err(e) => Err(e)
    Ok(v) => Ok(self.with_data(v))
  }
}

///| Replace the `input` document from a JSON string.
pub fn Policy::with_input_json(self : Policy, text : String) -> Result[Policy, RegoError] {
  match parse_json(text) {
    Err(e) => Err(e)
    Ok(v) => Ok(self.with_input(v))
  }
}

///| The names of every value-producing rule in the module, in declaration order
/// without duplicates. Parameterised rules are functions rather than values and
/// are not listed.
pub fn Policy::rule_names(self : Policy) -> Array[String] {
  let names : Array[String] = []
  for r in self.md.rules {
    if r.args.length() == 0 {
      let mut seen = false
      for n in names {
        if n == r.name {
          seen = true
        }
      }
      if !seen {
        names.push(r.name)
      }
    }
  }
  names
}

///| Evaluate a rule by name.
///
/// Returns `None` when the rule is undefined, which is what Rego means by an
/// undefined rule — it is not the same as `false`.
pub fn Policy::eval(self : Policy, name : String) -> Result[Value?, RegoError] {
  eval_rule_group(self.env(), 0, name)
}

///| Evaluate a boolean-valued rule, treating an undefined rule as `false`.
///
/// This is the usual shape of a policy decision, so it has its own entry point.
pub fn Policy::allow(self : Policy, name : String) -> Result[Bool, RegoError] {
  match self.eval(name) {
    Err(e) => Err(e)
    Ok(None) => Ok(false)
    Ok(Some(Value::Bool(b))) => Ok(b)
    Ok(Some(other)) =>
      Err(
        RegoError::make(
          RegoErrorKind::TypeError,
          "rule `" + name + "` is not a boolean, it is " + other.type_name(),
        ),
      )
  }
}

///| Evaluate an arbitrary query expression against the current documents.
///
/// The query is parsed with the same expression grammar as a rule body, so
/// `data.authz.allow`, `input.user`, or `count(data.items)` all work.
pub fn Policy::query(self : Policy, text : String) -> Result[Value?, RegoError] {
  match parse_expression(text) {
    Err(e) => Err(e)
    Ok(expr) => eval_expr(self.env(), Scope::empty(), 0, expr)
  }
}

///| Evaluate every rule in the module into a single object, the way OPA
/// exposes a package under `data.<package>`.
pub fn Policy::package_value(self : Policy) -> Result[Value, RegoError] {
  let pairs : Array[(String, Value)] = []
  for name in self.rule_names() {
    let v = match self.eval(name) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    match v {
      None => ()
      Some(value) => pairs.push((name, value))
    }
  }
  Ok(make_object(pairs))
}

///| Compile Rego source, run a query, and return the result.
pub fn evaluate(
  source : String,
  query : String,
  input : Value
) -> Result[Value?, RegoError] {
  let policy = match Policy::compile(source) {
    Err(e) => return Err(e)
    Ok(p) => p
  }
  policy.with_input(input).query(query)
}
