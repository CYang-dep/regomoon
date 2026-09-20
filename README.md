# regomoon

A Rego policy-language engine for MoonBit: a lexer, parser and evaluator for
`.rego` modules over JSON documents, with a builtin library and a documented
error model.

> **Module**: `CYang-dep/regomoon`
> **Repository**: https://github.com/CYang-dep/regomoon
> **Version**: 0.1.0
> **License**: Apache-2.0

```moonbit
let policy = match @regomoon.Policy::compile(source) {
  Err(e) => return Err(e)
  Ok(p) => p
}
let bound = match policy.with_input_json("{\"user\":\"alice\",\"action\":\"read\"}") {
  Err(e) => return Err(e)
  Ok(p) => p
}
let allowed = bound.allow("allow")          // Bool
let reasons = bound.query("deny")           // set of denial reasons
```

## 中文项目介绍

`regomoon` 是用 MoonBit 实现的 **Rego 策略语言引擎**。它解析并求值
`.rego` 模块文本，把策略语言本身完整搬进 MoonBit：词法分析、递归下降语法
分析、表达式求值、规则语义、内置函数库与结构化错误，全部从零实现，不依赖
任何宿主运行时。

一句话：**让 MoonBit 应用能直接读懂并执行 OPA/Rego 策略文件。**

### 为什么是「语言引擎」而不是「策略库」

策略是**数据**，不是代码。使用方把 `.rego` 文本（来自配置中心、Git 仓库、
运维下发的文件）交给 `regomoon`，引擎在运行时解析并求值——不需要重新编译
应用，也不需要为每条新策略写一个 MoonBit 函数。

### 已实现

- **模型与模块**：`package`、`import`（含 `as` 别名）、`default` 规则；
- **规则**：完整规则、部分集合规则（`contains`）、部分对象规则（`p[k] := v`）、
  带参数规则（`is_admin(user)`）；同时接受 Rego v1 的 `if` 写法与旧的
  `rule { ... }` 写法；
- **表达式**：`null` / 布尔 / 数字 / 字符串 / 数组 / 集合 / 对象字面量、
  引用路径（`.field` / `[expr]`）、函数调用、一元负号、算术
  `+ - * / %`、比较 `== != < <= > >=`、赋值 `:=` `=`、集合运算 `| & -`、
  成员判断 `in`；
- **语句**：裸表达式测试、`not`（否定即失败）、`some x, y`、
  `some x in xs`、`every x in xs { ... }`；
- **推导式**：数组 `[x | ...]`、集合 `{x | ...}`、对象 `{k: v | ...}`；
- **内置函数**：46 个，覆盖聚合、算术、字符串、正则、JSON、集合、对象与
  类型判断（见下表）；
- **结构化错误**：10 类错误（词法 / 语法 / JSON / 类型 / 未定义 / 参数个数 /
  除零 / 冲突 / 安全性 / 编译），词法与语法错误带行列号。

### 验证情况

- `wasm`、`wasm-gc`、`js` 三个目标在本机实跑 `moon test`，各 **75/75 通过**；
- `native` 目标的测试运行由 CI 在 ubuntu-latest 上执行，同样 **75/75 通过**
  （本机未安装 C 编译器，无法运行 native 测试，只做了 `moon check --target all` 的类型检查）；
- CI 运行记录：<https://github.com/CYang-dep/regomoon/actions/runs/35490606996>。

## What this is not

- **Not a port of the OPA Go source.** The grammar, evaluator and builtin
  library were written from the published Rego documentation. No Go code was
  copied or translated. See `THIRD_PARTY_NOTICES.md`.
- **Not a policy *library* in the "write policies as MoonBit functions" sense.**
  Policies are Rego text, not compiled code.
- **Not a control plane.** There is no server, no HTTP API, no Kubernetes
  admission webhook, and no Ceph/S3 integration. It is a library you embed.

## Quick start

```sh
moon add CYang-dep/regomoon
```

```moonbit
///|
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
fn main {
  let policy = match @regomoon.Policy::compile(SOURCE) {
    Err(e) => {
      println("compile failed: " + e.render())
      return
    }
    Ok(p) => p
  }
  let bound = match policy.with_input_json("{\"action\":\"read\",\"object\":\"data1\"}") {
    Err(e) => {
      println("bad input: " + e.render())
      return
    }
    Ok(p) => p
  }
  println(bound.allow("allow").to_string())   // true
}
```

Two runnable examples live under `examples/`:

```sh
moon run examples/quickstart   # a single ACL rule
moon run examples/rbac         # roles from data, a helper rule, deny reasons
moon run examples/audit        # comprehensions, regex, set algebra, a per-subject report
```

## API

| Function | Purpose |
| --- | --- |
| `Policy::compile(source)` | Parse and compile Rego text. |
| `Policy::with_data(value)` / `with_data_json(text)` | Bind the `data` document. |
| `Policy::with_input(value)` / `with_input_json(text)` | Bind the `input` document. |
| `Policy::eval(name)` | Evaluate a rule; `None` when it is undefined. |
| `Policy::allow(name)` | Evaluate a boolean rule, treating undefined as `false`. |
| `Policy::query(text)` | Evaluate an arbitrary expression such as `data.authz.allow`. |
| `Policy::package_value()` | Every defined rule in the module, as one object. |
| `Policy::rule_names()` | The names of all value-producing rules. |
| `Policy::package_path()` / `package_name()` | The module's `package` path. |
| `evaluate(source, query, input)` | One-shot convenience helper. |

`undefined` is deliberately distinct from `false`: a rule with no matching
clause produces `None`, and `Policy::allow` is the one place that collapses the
two. Rego makes this distinction and so does this engine.

## Language surface

| Feature | Status |
| --- | --- |
| `package`, `import ... as ...` | Supported |
| `default` rules | Supported |
| Complete rules (`allow if { }`, `allow := v if { }`) | Supported |
| Partial set rules (`deny contains msg if { }`) | Supported |
| Partial object rules (`counts[k] := v if { }`) | Supported |
| Parameterised (function) rules | Supported |
| Pre-v1 spellings (`allow { }`, `p[x] { }`) | Supported |
| Array / set / object comprehensions | Supported |
| `some x in xs`, `some k, v in obj` | Supported |
| `every x in xs { }` | Supported |
| `not` (negation as failure) | Supported |
| Set algebra (union `\|`, intersection `&`, difference `-`) | Supported |
| `in` membership, including binding form | Supported |
| `regex.match`, `regex.is_valid` | Supported |
| `future.keywords` / `rego.v1` imports | Parsed and ignored — keywords are always enabled |

### Deliberate limits

| Not supported | Why, and what to write instead |
| --- | --- |
| The `with` modifier | Rejected with a `compile` error rather than a confusing parse error. Override `input` at the call site instead. |
| Implicit iteration over unbound index variables | `p[x] if { data.arr[x] == 1 }` is an error. Write `some x in data.arr` explicitly. This is the one place the engine is deliberately stricter than OPA; explicit iteration is also what Rego v1 pushes towards. |
| Non-string object keys | Objects are the JSON document model, so keys are strings. `{1: "a"}` is a type error. |
| Arbitrary-precision numbers | Numbers are `Double`. Values beyond 2^53 lose precision. |
| Host-dependent builtins | `http.send`, `opa.runtime`, `trace`, `time.now_ns` and friends need a host and are absent. `walk` is not implemented. |
| Dotted rule-head names | `a.b := 1` is not accepted; declare `b` in `package a` instead. |

## Builtins

| Group | Functions |
| --- | --- |
| Aggregation | `count` `sum` `product` `max` `min` `sort` `all` `any` |
| Arithmetic | `abs` `round` `ceil` `floor` |
| Strings | `lower` `upper` `trim_space` `trim` `startswith` `endswith` `contains` `split` `concat` `replace` `substring` `indexof` `sprintf` |
| Types | `is_number` `is_string` `is_boolean` `is_array` `is_object` `is_set` `is_null` `type_name` `to_number` |
| Sets | `set` `union` `intersection` |
| Arrays / objects | `array.concat` `object.get` `object.keys` `object.union` |
| JSON | `json.marshal` `json.unmarshal` |
| Regex | `regex.match` `regex.is_valid` |
| Numbers | `numbers.range` |

Every builtin checks its argument count and argument types, and reports a
structured error rather than aborting.

## Errors

All failures are a `RegoError` with a `kind`, a message, and — for lexer and
parser errors — a source position:

| Kind | Raised when |
| --- | --- |
| `lex` | An invalid character, unterminated string, malformed number. |
| `parse` | An unexpected token, a missing `package`, a malformed rule head. |
| `json` | A malformed `data` or `input` document. |
| `type` | A builtin or operator received the wrong value type. |
| `undefined` | A variable was assigned an undefined value. |
| `arity` | A builtin was called with the wrong number of arguments. |
| `divide-by-zero` | `/` or `%` with a zero divisor. |
| `conflict` | A complete rule or partial object rule produced disagreeing values. |
| `safety` | The rule-reference recursion limit was exceeded. |
| `compile` | A construct this engine does not implement, such as `with`. |

## How this differs from neighbouring MoonBit work

Two existing MoonBit projects sit near this one. Neither implements the Rego
language, and this section states the difference explicitly so the boundary is
not left to guesswork.

| Project | What it is | How `regomoon` differs |
| --- | --- | --- |
| [`chnlkw/kunloria`](https://github.com/chnlkw/kunloria) — "an OPA/Rego alternative written in MoonBit" | A **combinator library plus a native service**: a policy is a MoonBit function `pub type Policy = (Query) -> Decision` assembled from combinators such as `otherwise`, `and_` and `scoped`. It ships a Kubernetes admission webhook and Ceph RGW authorization server, depends on `moonbitlang/async` and `moonbitlang/moonback`, and targets `native` only. | `regomoon` **implements the Rego language**: it lexes, parses and evaluates `.rego` **text** at run time, so policies are data rather than compiled code. It has no server, no Kubernetes or Ceph coupling, and no `async` dependency; it compiles for `wasm`, `wasm-gc`, `js` and `native`. The two projects share a goal (policy decisions) and no implementation path. |
| [`haol-05/moondatalog`](https://github.com/haol-05/moondatalog) | A pure MoonBit **Datalog query engine** (stratified negation, aggregation, static checks). | Rego descends from Datalog, so this is the closest theoretical neighbour — but a Datalog engine is not a policy language. `regomoon` evaluates the Rego language against the **JSON document model** (objects, sets, and reference paths like `data.roles[user]`), implements Rego's rule forms (complete / partial set / partial object / function rules, `default`, rule-head values), Rego's own operator and statement surface, and the Rego builtin library. It is not a general Datalog solver. |

Neither project occupies "a Rego language implementation in MoonBit", which is
what this repository provides.

## Layout

```
regomoon/
  value.mbt      the Rego value model: null, bool, number, string, array, set, object
  json.mbt       strict RFC 8259 JSON reader feeding the same value model
  error.mbt      the structured error type
  lexer.mbt      tokens, comments, raw strings, positions
  ast.mbt        the syntax tree and its renderer
  parser.mbt     recursive descent + precedence climbing
  builtins.mbt   the builtin function library
  eval.mbt       search, rule semantics, comprehensions, operators
  engine.mbt     the public API
  examples/      quickstart and rbac runnable examples
```

About 5,100 lines of engine code and 1,100 lines of tests, with 75 tests. There is also a Chinese project write-up in `申报书.md`.

## Build and test

```sh
moon check --target all --deny-warn
moon test  --target all --deny-warn
moon fmt   --check
```

## References

- [Open Policy Agent](https://github.com/open-policy-agent/opa) — the Rego
  language and its official test cases, used as the semantic reference.
- [`moonbitlang/regexp`](https://mooncakes.io/docs/#/moonbitlang/regexp) — the
  regular-expression engine behind `regex.match`.

## License

Apache-2.0. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.
