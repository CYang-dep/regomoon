///| The Rego abstract syntax tree.
///
/// The grammar implemented here is **Rego v1**: rule bodies are introduced by
/// `if`, partial set rules use `contains`, and `:=` introduces rule values.
/// The pre-v1 spelling without `if` is also accepted when a `{` follows the
/// rule head, so most existing policy text parses unchanged.

///|
/// One element of a reference path, as produced by `.name` or `[expr]`.
pub(all) enum RefArg {
  Field(String)
  Index(Expr)
}

///|
/// A Rego expression.
pub(all) enum Expr {
  ENull
  EBool(Bool)
  ENumber(Double)
  EString(String)
  EVar(String)
  EArray(Array[Expr])
  ESet(Array[Expr])
  EObject(Array[(Expr, Expr)])
  EArrayComprehension(Expr, Array[Stmt])
  ESetComprehension(Expr, Array[Stmt])
  EObjectComprehension(Expr, Expr, Array[Stmt])
  ECall(String, Array[Expr])
  EField(Expr, String)
  EIndex(Expr, Expr)
  ENegate(Expr)
  EBinary(String, Expr, Expr)
}

///|
/// A statement inside a rule body, comprehension body, or `every` body.
pub(all) enum Stmt {
  /// A bare expression: a test, a unification, or an assignment.
  Test(Expr)
  /// `not <expr>` — negation as failure.
  Negate(Expr)
  /// `some x, y` — declare local variables.
  SomeVars(Array[String])
  /// `some x, y in <collection>` — iterate a collection.
  SomeIn(Array[String], Expr)
  /// `every x, y in <collection> { ... }` — universal quantification.
  Every(Array[String], Expr, Array[Stmt])
}

///|
/// The shape of a rule head.
pub(all) enum RuleKind {
  /// `allow if { ... }` or `allow := value if { ... }`
  CompleteRule
  /// `deny contains msg if { ... }`
  PartialSetRule
  /// `counts[k] := v if { ... }`
  PartialObjectRule
} derive(Eq)

///|
/// A rule definition.
pub(all) struct Rule {
  /// The rule's name, e.g. `allow`. Dotted head names are not supported.
  name : String
  /// Parameter names for a parameterised rule such as `is_member(user)`.
  args : Array[String]
  /// The key expression of a partial object or partial set rule head.
  key : Expr?
  /// The head value: `:= v` for complete/partial-object, `contains v` for sets.
  value : Expr?
  kind : RuleKind
  body : Array[Stmt]
  /// Whether this rule was introduced with `default`.
  is_default : Bool
  line : Int
  column : Int
}

///|
/// An `import` declaration.
pub(all) struct ImportDecl {
  path : Array[String]
  /// The local name the import is bound to.
  local_name : String
}

///|
/// A parsed Rego module.
pub(all) struct Module {
  package_path : Array[String]
  imports : Array[ImportDecl]
  rules : Array[Rule]
}

///|
/// The last segment of a path, used as the default import alias.
pub fn path_last(path : Array[String]) -> String {
  if path.length() == 0 {
    ""
  } else {
    path[path.length() - 1]
  }
}

///|
/// Render a dotted path.
pub fn render_path(path : Array[String]) -> String {
  join_strings(path, ".")
}

// ---------------------------------------------------------------------------
// Rendering, used by tests and by `regomoon`'s error messages
// ---------------------------------------------------------------------------

///|
/// Render an expression back to a compact Rego-like form.
pub fn Expr::render(self : Expr) -> String {
  match self {
    Expr::ENull => "null"
    Expr::EBool(b) => if b { "true" } else { "false" }
    Expr::ENumber(d) => format_number(d)
    Expr::EString(s) => "\"" + s + "\""
    Expr::EVar(name) => name
    Expr::EArray(items) => "[" + render_exprs(items) + "]"
    Expr::ESet(items) => "{" + render_exprs(items) + "}"
    Expr::EObject(pairs) => {
      let parts : Array[String] = []
      for kv in pairs {
        parts.push(kv.0.render() + ": " + kv.1.render())
      }
      "{" + join_strings(parts, ", ") + "}"
    }
    Expr::EArrayComprehension(head, body) =>
      "[" + head.render() + " | " + render_stmts(body) + "]"
    Expr::ESetComprehension(head, body) =>
      "{" + head.render() + " | " + render_stmts(body) + "}"
    Expr::EObjectComprehension(key, value, body) =>
      "{" +
      key.render() +
      ": " +
      value.render() +
      " | " +
      render_stmts(body) +
      "}"
    Expr::ECall(name, args) => name + "(" + render_exprs(args) + ")"
    Expr::EField(base, name) => base.render() + "." + name
    Expr::EIndex(base, index) => base.render() + "[" + index.render() + "]"
    Expr::ENegate(inner) => "-" + inner.render()
    Expr::EBinary(op, left, right) =>
      "(" + left.render() + " " + op + " " + right.render() + ")"
  }
}

///|
fn render_exprs(items : Array[Expr]) -> String {
  let parts : Array[String] = []
  for e in items {
    parts.push(e.render())
  }
  join_strings(parts, ", ")
}

///|
/// Render a statement list, as it would appear in a rule body.
pub fn render_stmts(stmts : Array[Stmt]) -> String {
  let parts : Array[String] = []
  for s in stmts {
    parts.push(s.render())
  }
  join_strings(parts, "; ")
}

///|
/// Render a statement.
pub fn Stmt::render(self : Stmt) -> String {
  match self {
    Stmt::Test(e) => e.render()
    Stmt::Negate(e) => "not " + e.render()
    Stmt::SomeVars(names) => "some " + join_strings(names, ", ")
    Stmt::SomeIn(names, collection) =>
      "some " + join_strings(names, ", ") + " in " + collection.render()
    Stmt::Every(names, collection, body) =>
      "every " +
      join_strings(names, ", ") +
      " in " +
      collection.render() +
      " { " +
      render_stmts(body) +
      " }"
  }
}

///|
/// Render a rule head and body.
pub fn Rule::render(self : Rule) -> String {
  let base = if self.args.length() == 0 {
    self.name
  } else {
    self.name + "(" + join_strings(self.args, ", ") + ")"
  }
  let head = if self.is_default {
    "default " + base + " := " + render_value(self.value)
  } else {
    match self.kind {
      RuleKind::CompleteRule =>
        match self.value {
          Some(v) => base + " := " + v.render()
          None => base
        }
      RuleKind::PartialSetRule => base + " contains " + render_value(self.value)
      RuleKind::PartialObjectRule =>
        base + "[" + render_value(self.key) + "] := " + render_value(self.value)
    }
  }
  if self.body.length() == 0 {
    head
  } else {
    head + " if { " + render_stmts(self.body) + " }"
  }
}

///|
fn render_value(e : Expr?) -> String {
  match e {
    Some(v) => v.render()
    None => "_"
  }
}
