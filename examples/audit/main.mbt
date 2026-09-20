///| An configuration-audit example.
///
/// This one leans on the parts of the language that the other two examples do
/// not touch: comprehensions that close over the enclosing bindings, set
/// algebra, `not ... in ...`, regex matching, and a partial object rule that
/// builds a per-subject report.
///
/// Run with:
///
/// ```sh
/// moon run examples/audit
/// ```

///|
const SOURCE : String =
  #|package audit
  #|
  #|# The only permissions a service account may hold.
  #|allowed := {"read", "list", "describe"}
  #|
  #|# Anything outside `allowed`, across every account.
  #|violations contains violation if {
  #|  some account in data.accounts
  #|  some perm in account.permissions
  #|  not perm in allowed
  #|  violation := {"account": account.name, "permission": perm}
  #|}
  #|
  #|# Accounts holding a `secret:*` permission, which always needs sign-off.
  #|needs_approval contains account.name if {
  #|  some account in data.accounts
  #|  some perm in account.permissions
  #|  regex.match("^secret:", perm)
  #|}
  #|
  #|# How many out-of-policy permissions each account holds.
  #|report[name] := n if {
  #|  some account in data.accounts
  #|  name := account.name
  #|  n := count([p | some p in account.permissions; not p in allowed])
  #|}
  #|
  #|# Clean bill of health only when nothing is out of policy.
  #|default compliant := false
  #|
  #|compliant if {
  #|  count(violations) == 0
  #|}

///|
const DATA : String =
  #|{
  #|  "accounts": [
  #|    {"name": "ci-bot",     "permissions": ["read", "list"]},
  #|    {"name": "deploy-bot", "permissions": ["read", "secret:rotate"]},
  #|    {"name": "legacy-job", "permissions": ["read", "write", "delete"]}
  #|  ]
  #|}

///|
fn ask(bound : @regomoon.Policy, query : String) -> String {
  match bound.query(query) {
    Err(e) => "error: " + e.render()
    Ok(None) => "undefined"
    Ok(Some(v)) => v.to_rego_string()
  }
}

///|
fn main {
  let policy = match @regomoon.Policy::compile(SOURCE) {
    Err(e) => {
      println("compile failed: " + e.render())
      return
    }
    Ok(p) => p
  }
  let bound = match policy.with_data_json(DATA) {
    Err(e) => {
      println("bad data: " + e.render())
      return
    }
    Ok(p) => p
  }
  println("compliant      = " + ask(bound, "compliant"))
  println("violations     = " + ask(bound, "violations"))
  println("needs_approval = " + ask(bound, "needs_approval"))
  println("report         = " + ask(bound, "report"))
  println("report[\"legacy-job\"] = " + ask(bound, "report[\"legacy-job\"]"))
}
