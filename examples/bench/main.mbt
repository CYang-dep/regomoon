///| A throughput benchmark.
///
/// It builds a policy whose rule graph is a chain of diamonds — each rule
/// references its predecessor twice — so evaluating the top rule touches the
/// base rule 2^depth times without memoisation and only `depth` times with it.
/// That makes the effect of the rule cache visible in a single number.
///
/// The program prints how many queries it ran and a checksum of the results,
/// so the work cannot be optimised away. Wall time is measured from outside:
///
/// ```sh
/// time moon run examples/bench
/// ```

///|
const QUERIES : Int = 500

///|
const DEPTH : Int = 12

///|
/// Build the diamond-chain policy source.
fn policy_source(depth : Int) -> String {
  let sb = StringBuilder()
  sb.write_string("package bench\n\nbase := 1\n\n")
  let mut prev = "base"
  let mut i = 0
  while i < depth {
    sb.write_string("n" + i.to_string() + " := " + prev + " + " + prev + "\n")
    prev = "n" + i.to_string()
    i = i + 1
  }
  sb.write_string("sum := " + prev + "\n")
  sb.to_string()
}

///|
fn main {
  let source = policy_source(DEPTH)
  let policy = match @regomoon.Policy::compile(source) {
    Err(e) => {
      println("compile failed: " + e.render())
      return
    }
    Ok(p) => p
  }
  let mut checksum = 0
  let mut undefined = 0
  let mut i = 0
  while i < QUERIES {
    match policy.query("sum") {
      Err(e) => {
        println("query failed: " + e.render())
        return
      }
      Ok(None) => undefined = undefined + 1
      Ok(Some(v)) =>
        match v {
          @regomoon.Value::Number(d) => checksum = checksum + d.to_int()
          _ => undefined = undefined + 1
        }
    }
    i = i + 1
  }
  println("queries=" + QUERIES.to_string() + " depth=" + DEPTH.to_string())
  println(
    "checksum=" + checksum.to_string() + " undefined=" + undefined.to_string(),
  )
}
