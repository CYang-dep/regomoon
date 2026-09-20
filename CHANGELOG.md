# Changelog

## 0.2.0

New language features:

- `with input as ...` on rule-body statements and on queries, so one policy
  can exercise a rule against several inputs. Only the `input` document can be
  replaced; `with data.x as ...` and chained modifiers are compile errors.
  A `with`-modified expression must be the whole statement or query.

New builtins:

- `object.remove`, `object.filter`
- `array.slice` (OPA semantics for non-positive indices)
- `trim_prefix`, `trim_suffix`
- `numbers.range_step`

Performance:

- Argless rules are memoised per query. Rules are pure — they read only the
  module, `data` and `input` — so a diamond-shaped rule graph now evaluates
  each rule once instead of once per path. Measured on the new
  `examples/bench` (500 queries, depth 12, identical checksum):
  ~128 ms with the cache against ~833 ms with it bypassed.

Tests and tooling:

- A 40-case language-conformance suite modelled on OPA's documented shapes.
- CI now runs all four examples, so they cannot silently break.

## 0.1.0

Initial release: Rego v1 lexer, parser and evaluator over the JSON document
model, 46 builtins, structured errors with source positions, and four runnable
examples. Tests pass on the wasm, wasm-gc, js and native backends.
