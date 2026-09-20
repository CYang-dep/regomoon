# regomoon

MoonBit 的 Rego 策略语言引擎：解析并求值 `.rego` 策略文本，对 JSON 文档做判定。

| 项 | 内容 |
| --- | --- |
| 模块名 | `CYang-dep/regomoon` |
| 上游 | Open Policy Agent（OPA）的 Rego 语言，对标 v1.20.2 |
| 许可证 | Apache-2.0（与上游一致） |
| 运行时依赖 | 仅 `moonbitlang/regexp@0.3.5` |
| 仓库 | https://github.com/CYang-dep/regomoon |

```sh
moon add CYang-dep/regomoon
```

本项目移植的是 **Rego 这门语言**，不是 OPA 的 Go 源码。词法器、解析器、求值器和内置函数
库依据 Rego 官方语言文档的语义从零实现，代码与 OPA 仓库没有派生关系，仅在语言行为上对齐。

## 为什么需要它

策略和业务代码混在一起，是后端开发里反复出现的麻烦。鉴权逻辑散落在各个 handler 里，
`if user.role == "admin"` 这类判断写了十几处；要新增一种角色，得改代码、重新编译、重新发版；
运维想在出口处统一拦一道，只能再写一个中间件。Rego 的思路是把"谁能在什么条件下对什么做
什么"抽成独立的策略文件——策略是数据，改策略不用改程序。

这套做法在 Go 生态里已经很成熟，但要用它，前提是宿主环境里有一个能读懂 `.rego` 文本的
求值器。MoonBit 目前没有，所以 MoonBit 应用想用声明式策略，只能用代码把规则硬编码一遍。

regomoon 补的就是这一块：给定一段 Rego 文本和一个 JSON 输入，返回判定结果。它是纯库，
没有服务器、没有网络依赖、不绑定具体业务。Web 框架的鉴权中间件、网关的过滤规则、CI 里的
配置检查、边缘函数里的轻量判定，都可以直接嵌。

## 核心模块

```
value.mbt    值模型：null/bool/number/string/array/set/object
json.mbt     严格 RFC 8259 JSON 读取，供 data 与 input 使用
error.mbt    结构化错误类型
lexer.mbt    词法分析，输出带行列号的 token
ast.mbt      语法树及其回显
parser.mbt   递归下降 + 优先级爬升
builtins.mbt 内置函数库
eval.mbt     规则体求值、规则语义、推导式、运算符
engine.mbt   对外 API
```

数据流是一条线：策略文本经 `lexer` 变成 token 流，`parser` 生成语法树，`engine` 把语法树
连同 `data` / `input` 两份 JSON 文档交给 `eval` 求值，算出的值仍是 `value` 里的 Rego 值，
可以原样序列化回 JSON。

三处设计与上游实现思路不同，都是因为宿主语言不同：

- **值模型用代数数据类型。** Rego 的值比 JSON 多一个集合类型，这里用 `enum` 表达七种值，
  并保证集合与对象始终处于排序去重的规范形态，于是相等判断、排序和输出都是确定性的。
- **规则体求值用回溯搜索。** Rego 的规则体是合取式，`some x in xs` 会引入多条可行绑定，
  所以求值一个规则体得到的是"所有满足约束的变量环境"的集合，而不是单个布尔值。
- **错误用统一的 `RegoError` 结构。** 十类错误（词法、语法、JSON、类型、未定义、参数个数、
  除零、冲突、安全性、编译），词法与语法错误带行列号，调用方按类别处理而不是解析错误字符串。

依赖只有一个 `moonbitlang/regexp`（Apache-2.0），用于 `regex.match`，其余全部基于 MoonBit
标准库，因此 `wasm`、`wasm-gc`、`js`、`native` 四个后端都能编译。

## 兼容边界

与上游一致的部分：规则四种形态（完整、部分集合、部分对象、带参函数规则）、`default`、
三种推导式、`some` / `every` / `not`、集合代数与 `in`、六档运算符优先级，以及 undefined
与 false 的区分。同时兼容 Rego v1 的 `if` / `contains` 写法和旧的 `rule { }` 写法。

子集实现的部分：内置函数做了 52 个常用的（`object.remove` / `object.filter` /
`array.slice` / `trim_prefix` / `trim_suffix` / `numbers.range_step` 是 0.2.0 新增的；
OPA 的内置函数集远大于此，还包含时间、加密、HTTP 调用、图遍历等类别）；数字用 `Double`，
不是 OPA 的任意精度十进制，超过 2^53 会丢精度；正则改用 `moonbitlang/regexp`，语法是其子集。

部分支持的部分：`with input as ...` 可以出现在规则体语句和查询里，让一条策略对多个
输入复用同一个规则；但它只能修饰整条语句或整个查询，不能嵌在更大的表达式里，也只
支持覆盖 `input`（覆盖 `data` 的路径会报编译错误）。

暂不支持的部分：未绑定下标变量的隐式迭代（需要显式写 `some x in data.arr`）、非字符串
对象键、`walk`、点号规则头名（`a.b := 1`）。

## 三个可运行的示例

都在 `examples/` 下，可直接 `moon run` 运行，下列输出均为实际运行结果。

### 示例一：接口鉴权（`examples/quickstart`）

Web 框架作者想在中间件里做一次"这个请求放不放行"的判断，策略放在配置里。

```rego
package authz

default allow := false

allow if {
  input.action == "read"
  input.object == "data1"
}
```

```moonbit
let policy = @regomoon.Policy::compile(SOURCE)
let bound = policy.with_input_json("{\"action\":\"read\",\"object\":\"data1\"}")
bound.allow("allow")   // true
```

`action` 换成 `write` 则返回 `false`（走 `default` 规则）。放行条件写在策略文本里，
改规则不用改代码、不用重新编译。

### 示例二：数据驱动角色（`examples/rbac`）

多租户系统里角色和权限存在数据库里，希望授权逻辑只依赖数据、不依赖代码。

```json
{"roles": {"alice": ["admin"], "bob": ["viewer"]},
 "grants": {"admin": [{"action": "read", "resource": "data1"},
                      {"action": "write", "resource": "data1"}]}}
```

```moonbit
bound.query("roles_for(\"alice\")")                      // ["admin"]
bound.query("granted(\"admin\", \"write\", \"data1\")")   // true
bound.allow("allow")                                     // 按请求判定
```

实际运行输出：

```
ALLOW  {"user":"alice","authenticated":true,"action":"write","resource":"data1"}   deny=set()
DENY   {"user":"carol","authenticated":true,"action":"read","resource":"data1"}    deny={"user has no roles"}
ALLOW  {"user":"alice","authenticated":false,"action":"read","resource":"data1"}   deny={"request is not authenticated"}
```

角色与权限全在 `data` 文档里，加一个角色只改数据。`deny` 是部分集合规则，多个原因会自动
累积成一个集合，适合直接返回给前端。

### 示例三：配置审计（`examples/audit`）

平台方要批量检查一批服务账号的权限是否符合规范，并输出每个账号的问题数。

```json
{"accounts": [
  {"name": "ci-bot",     "permissions": ["read", "list"]},
  {"name": "deploy-bot", "permissions": ["read", "secret:rotate"]},
  {"name": "legacy-job", "permissions": ["read", "write", "delete"]}]}
```

```moonbit
bound.query("violations")   // 所有越权项
bound.query("report")       // 每个账号的越权计数
bound.allow("compliant")
```

实际运行输出：

```
compliant      = false
violations     = {{"account": "deploy-bot", "permission": "secret:rotate"},
                  {"account": "legacy-job", "permission": "delete"},
                  {"account": "legacy-job", "permission": "write"}}
needs_approval = {"deploy-bot"}
report         = {"ci-bot": 0, "deploy-bot": 1, "legacy-job": 2}
```

一个策略文件同时给出明细和汇总。这里用到了推导式捕获外层绑定、`not ... in ...`、
正则匹配和部分对象规则，是三个示例里语言特性最全的一个。

## 与 OPA 的能力对照

| 能力 | OPA / Rego | 本项目 | 说明 |
|---|---|---|---|
| 模块结构 `package` / `import as` / `default` | 支持 | 已实现 | 同时兼容 v1 的 `if`/`contains` 与旧版 `rule { }` 写法 |
| 完整 / 部分集合 / 部分对象规则 | 支持 | 已实现 | |
| 带参规则（函数规则） | 支持 | 已实现 | |
| 数组 / 集合 / 对象推导式 | 支持 | 已实现 | 推导式捕获外层绑定 |
| `some` / `every` / `not` | 支持 | 已实现 | |
| 集合代数 `\|` `&` `-` 与 `in` | 支持 | 已实现 | |
| 内置函数 | 全量（含时间、加密、HTTP、图遍历等） | 52 个 | 聚合、算术、字符串、正则、JSON、集合、对象、类型判断 |
| 正则 | Go `regexp` 语法 | 已实现 | 改用 `moonbitlang/regexp`，语法子集 |
| 数字 | 任意精度十进制 | `Double` | 超过 2^53 丢精度 |
| `with` 修饰符 | 支持 | 部分支持 | 可覆盖 `input`；不能嵌在更大的表达式里，覆盖 `data` 尚未实现 |
| 隐式迭代 | 支持 | 未实现 | 需显式写 `some x in xs` |
| 非字符串对象键 | 支持 | 未实现 | 对象键限定为字符串 |
| `walk`、`http.send`、`opa.runtime` 等宿主内置 | 支持 | 未实现 | 需要宿主能力 |
| 部分求值等编译期优化 | 支持 | 未实现 | |

## 实测数据

- **代码量**：引擎 9 个文件共 5,496 行（剔除空行与注释后 4,750 行），不含测试、示例与生成
  文件；测试 7 个文件 1,467 行；示例 4 个共 352 行。
- **测试**：`moon test --target wasm` / `wasm-gc` / `js` / `native` 四个后端各
  **91 通过 / 0 失败**。前三个在本机验证，`native` 由 CI 在 ubuntu-latest 上执行
  （本机未装 C 编译器，无法运行 native 测试）。
  CI 运行记录：<https://github.com/CYang-dep/regomoon/actions/runs/35490606996>
- **严格检查**：`moon check --target all --deny-warn` 在四个后端全部通过（零警告）。
  工具链 moon 0.1.20260713 / moonc v0.10.4+2cc641edf（本地），CI 使用最新版。
- **覆盖率**：`moon coverage` 实测，引擎 9 个源码文件合计 **2553 / 3225 行（约 79%）**；
  计入四个示例后为 2553 / 3359（约 76%）。逐文件看，parser.mbt 523/649、json.mbt 265/324、
  lexer.mbt 324/398，最低的是 eval.mbt 484/687——未覆盖的主要是错误分支与部分罕见运算路径。
- **性能**：`examples/bench` 在 500 次查询、深度 12 的菱形规则链上实测（同一台机器、
  两次运行的校验和完全一致）：开启规则缓存约 128 ms，绕过缓存约 833 ms，差约 6.5 倍。
  尚未与 OPA 或其它实现做同输入对比，不下"更快"的结论。
- **上游对照测试**：未系统性移植 OPA 官方测试集。现有 75 个用例为手工编写，语义对照官方
  文档与常见策略写法，其中 ACL、RBAC、配置审计三类按真实策略形态组织。

## 当前状态与计划

已完成：语言核心（词法、语法、求值）、52 个内置函数、`with input as ...`、按查询缓存
规则求值、公共 API、四个可运行示例（含基准）、91 个测试用例、CI。

尚未完成：隐式迭代、任意精度数字、剩余内置函数（时间、编码、图遍历等类别）、`with`
对 `data` 路径的覆盖、覆盖率数据，以及与 OPA 的同输入性能对比。

后续按优先级：

1. 扩充一致性测试集，覆盖 `with` 与剩余内置函数；
2. 支持 `with` 对 `data` 路径的覆盖；
3. 补齐字符串与编解码类内置函数；
4. 用 `moon coverage` 取得覆盖率数据，并做一次与 OPA 的同输入耗时对比；
5. 视需求决定是否发布到 mooncakes.io。

## 项目价值

对写 MoonBit 应用的人来说，接入声明式策略通常意味着自己实现一套规则解析加求值，这是一大块
与业务无关的工作。regomoon 把这件事做成一个依赖：策略文本进、判定结果出，应用只需要决定
策略放在哪里。

能直接复用的场景包括 Web 框架的鉴权中间件、API 网关的过滤规则、CI 里的配置合规检查，以及
多租户系统里按租户下发策略。这些场景的共同点是规则经常变、且希望由非写代码的人维护，正是
声明式策略的适用范围。

它是一个通用的语言求值器，不依赖任何具体框架或业务模型，`wasm` 目标也让它可以在浏览器或
边缘环境里跑。当前的主要限制是内置函数只有 52 个、`with` 不能嵌在更大的表达式里、不支持
隐式迭代、数字精度受
`Double` 限制。维护方向以补齐内置函数和移植上游测试集为主，这两项都不改变现有 API。

## 构建

```sh
moon check --target all --deny-warn
moon test  --target all --deny-warn
moon run examples/quickstart
moon run examples/rbac
moon run examples/audit
```

## API 一览

| 函数 | 用途 |
| --- | --- |
| `Policy::compile(source)` | 解析并编译 Rego 文本 |
| `Policy::with_data(value)` / `with_data_json(text)` | 绑定 `data` 文档 |
| `Policy::with_input(value)` / `with_input_json(text)` | 绑定 `input` 文档 |
| `Policy::eval(name)` | 求值一条规则；未定义时返回 `None` |
| `Policy::allow(name)` | 求值布尔规则，未定义按 `false` 处理 |
| `Policy::query(text)` | 求值任意表达式，如 `data.authz.allow` |
| `Policy::package_value()` | 模块内所有已定义规则合成一个对象 |
| `Policy::rule_names()` | 所有产出值的规则名 |
| `evaluate(source, query, input)` | 一次性便捷入口 |

`undefined` 与 `false` 是两回事：没有子句命中的规则返回 `None`，只有 `Policy::allow`
会把两者合并。这是 Rego 的语义，本引擎保持一致。

## 许可证

Apache-2.0。见 `LICENSE` 与 `THIRD_PARTY_NOTICES.md`。
