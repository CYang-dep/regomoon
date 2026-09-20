///| A role-based access-control example.
///
/// It shows the pieces that make Rego more than an expression evaluator:
/// data-driven roles, a parameterised helper rule, a partial set rule that
/// accumulates denial reasons, and queries against the resulting package.
///
/// Run with:
///
/// ```sh
/// moon run examples/rbac
/// ```

///|
const SOURCE : String =
  #|package authz
  #|
  #|import data.roles
  #|
  #|default allow := false
  #|
  #|# Allow when the caller holds a role that grants the requested action
  #|# on the requested resource.
  #|allow if {
  #|  some role in roles_for(input.user)
  #|  granted(role, input.action, input.resource)
  #|}
  #|
  #|# Denial reasons accumulate into a set.
  #|deny contains reason if {
  #|  not input.authenticated
  #|  reason := "request is not authenticated"
  #|}
  #|
  #|# `roles_for` is undefined for an unknown user, so test it with a helper
  #|# rule rather than `count(...)`, which would itself be undefined.
  #|deny contains reason if {
  #|  not has_roles(input.user)
  #|  reason := "user has no roles"
  #|}
  #|
  #|has_roles(user) if {
  #|  some role in roles_for(user)
  #|}
  #|
  #|# The roles held by a user, read out of the data document.
  #|roles_for(user) := held if {
  #|  some name, held in data.roles
  #|  name == user
  #|}
  #|
  #|# Whether a role grants an action on a resource.
  #|granted(role, action, resource) if {
  #|  some name, grants in data.grants
  #|  name == role
  #|  some grant in grants
  #|  grant.action == action
  #|  grant.resource == resource
  #|}

///|
const DATA : String =
  #|{
  #|  "roles": {
  #|    "alice": ["admin"],
  #|    "bob": ["viewer"]
  #|  },
  #|  "grants": {
  #|    "admin": [
  #|      {"action": "read",  "resource": "data1"},
  #|      {"action": "write", "resource": "data1"}
  #|    ],
  #|    "viewer": [
  #|      {"action": "read", "resource": "data1"}
  #|    ]
  #|  }
  #|}

///|
fn show(bound : @regomoon.Policy, input : String) -> String {
  let decided = match bound.with_input_json(input) {
    Err(e) => return "bad input: " + e.render()
    Ok(p) => p
  }
  let verdict = match decided.allow("allow") {
    Err(e) => "error: " + e.render()
    Ok(true) => "ALLOW"
    Ok(false) => "DENY "
  }
  let reasons = match decided.query("deny") {
    Err(e) => "error: " + e.render()
    Ok(None) => "undefined"
    Ok(Some(v)) => v.to_rego_string()
  }
  verdict + "  " + input + "   deny=" + reasons
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
  println("package: " + bound.package_name())
  let requests = [
    "{\"user\":\"alice\",\"authenticated\":true,\"action\":\"write\",\"resource\":\"data1\"}",
    "{\"user\":\"alice\",\"authenticated\":true,\"action\":\"read\",\"resource\":\"data2\"}",
    "{\"user\":\"bob\",\"authenticated\":true,\"action\":\"read\",\"resource\":\"data1\"}",
    "{\"user\":\"carol\",\"authenticated\":true,\"action\":\"read\",\"resource\":\"data1\"}",
    "{\"user\":\"alice\",\"authenticated\":false,\"action\":\"read\",\"resource\":\"data1\"}",
  ]
  for input in requests {
    println(show(bound, input))
  }
  println("")
  println(
    "helper query  roles_for(\"alice\") = " +
    show_query(bound, "roles_for(\"alice\")"),
  )
  println(
    "helper query  granted(\"admin\", \"write\", \"data1\") = " +
    show_query(bound, "granted(\"admin\", \"write\", \"data1\")"),
  )
}

///|
fn show_query(bound : @regomoon.Policy, query : String) -> String {
  match bound.query(query) {
    Err(e) => "error: " + e.render()
    Ok(None) => "undefined"
    Ok(Some(v)) => v.to_rego_string()
  }
}
