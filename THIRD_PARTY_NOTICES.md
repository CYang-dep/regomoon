# Third-party notices

`regomoon` is an independent implementation of the Rego policy language for
MoonBit. It is licensed under the Apache License, Version 2.0 (see `LICENSE`).

## Runtime dependencies

| Package | Version | License | Use |
| --- | --- | --- | --- |
| [`moonbitlang/regexp`](https://mooncakes.io/docs/#/moonbitlang/regexp) | `0.3.5` | Apache-2.0 | Backs the `regex.match` and `regex.is_valid` builtins. |

No other packages are required at runtime.

## Language reference

The Rego language, its evaluation semantics and its builtin function names are
specified by the [Open Policy Agent](https://github.com/open-policy-agent/opa)
project, which is licensed under the Apache License, Version 2.0.

**No Go source code from OPA is copied, ported or translated in this
repository.** The grammar, evaluator and builtin library here were written from
the published language documentation, and the implementation strategy is
different in several respects (see the "How this differs from OPA" section of
the README).

The names of builtin functions such as `count`, `split` and `regex.match`, and
the Casbin/OPA-style model vocabulary, are used descriptively so that policy
text written for OPA is recognisable here.
