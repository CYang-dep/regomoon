///| Quickstart: compile a Rego policy, bind an input document, and decide.
///
/// Run with:
///
/// ```sh
/// moon run examples/quickstart
/// ```

///|
/// The policy: a plain ACL in Rego v1 syntax.
const SOURCE : String =
  #|package authz
  #|
  #|default allow := false
  #|
  #|allow if {
  #|  input.action == "read"
  #|  input.object == "data1"
  #|}

///|
fn decide(policy : @regomoon.Policy, input : String) -> String {
  let bound = match policy.with_input_json(input) {
    Err(e) => return "bad input: " + e.render()
    Ok(p) => p
  }
  match bound.allow("allow") {
    Err(e) => "error: " + e.render()
    Ok(true) => "allow"
    Ok(false) => "deny"
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
  println("package: " + policy.package_name())
  for
    input in [
      "{\"action\":\"read\",\"object\":\"data1\"}", "{\"action\":\"write\",\"object\":\"data1\"}",
      "{\"action\":\"read\",\"object\":\"data2\"}",
    ] {
    println("  " + input + " -> " + decide(policy, input))
  }
}
