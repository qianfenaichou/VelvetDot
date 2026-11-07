# vdot.vv 代码编写规范（CODING-STD）

> 文档地位：**本文档集（SPEC/ARCHITECTURE/ALGORITHM/CODING-STD）为设计与实现的依据，与其他材料冲突时以本文档集为准**。本文只陈述现行规范，不叙述纠错史。
> 适用：**写或改任何 Scala/Chisel 代码（香山 `src/`、`yunsuan/`）或 C 代码（NEMU `src/isa/riscv64/instr/rvv/`）、新建源文件、拆分任务、跑校验、写 commit message** 时必读。
> 关联文档：语义与编码见 `design/SPEC.md`；改动编号与端口改动见 `design/ARCHITECTURE.md` §4/§5；验证算法与可复现要求见 `design/ALGORITHM.md` §3。
> 说明：本文件是对既有设计决策的展开，只把它写成可执行判据，不新增设计决策。
> 当前为设计阶段：**尚未进入编码阶段**，凡依赖实测/团队裁决的细则一律以 TBD 标记留空并写明原因（共 12 处，上限 15）。

---

## 0. 速查

| 项 | 裁决 |
|---|---|
| Scala/Chisel 格式 | 香山 `repos/XiangShan/scalastyle-config.xml` + `.scalafmt.conf`（maxColumn 120） |
| C 格式 | 沿用 NEMU 内核风格：2 空格缩进、K&R 花括号、`pkg/file.h` 式 include |
| 代码注释语言 | **英文**（三棵树内中文注释实测计数见 §10 A-1） |
| 模块头注释 | 必写：语义出处（SPEC 小节 / 指令名）+ 位宽推导（19 位来源） |
| 断言 | 非法输出挂 `XSError`；「高 96 位恒零」进测试；`fireS1` 约束进 RTL |
| 提交 | 一处改动一个 commit，message 带改动编号（X1/N1…）+ 验证命令 |
| 留痕 | 命令 + commit hash + 配置 + 日志/波形/输入输出 六件套 |
| 自动化改动 | 先 grep 后改；只在改动位置表内改；改后按 §7.3 分级校验 |

---

## 1. 适用范围与优先级

### 1.1 适用范围

| 树 | 路径 | 本规范适用章节 |
|---|---|---|
| 香山主仓 | `repos/XiangShan/src/main/scala/` | §3、§5、§6、§7 |
| yunsuan 子模块 | `repos/XiangShan/yunsuan/src/main/scala/` | §3、§5、§6、§7 |
| yunsuan 单元测试 | `repos/XiangShan/yunsuan/src/test/scala/` | §5、§6、§7 |
| NEMU | `repos/NEMU/src/isa/riscv64/instr/rvv/`、`repos/NEMU/src/isa/riscv64/include/` | §4、§5、§6、§7 |
| 校验脚本 | `design/verify/`、`scripts/` | §7 |

`repos/YunSuan/`（@ `267ff7`，kunminghu-v3）**不在适用范围**，禁止参照（`design/ARCHITECTURE.md` §5.1）。

### 1.2 冲突裁决顺序

1. `design/SPEC.md`（语义/编码）——与任何风格问题无关时以此为准；
2. 目标仓自带的机械配置（`repos/XiangShan/scalastyle-config.xml`、`.scalafmt.conf`）——格式类冲突以工具行为为准；
3. 本文件；
4. 相邻同目录文件的历史写法——仅在本文件未覆盖时参考，且优先抄**同一 FU 家族**（`backend/fu/wrapper/`、`vector/vectorIMAC/`、`rvv/`）。

> 只有语义问题回落到 SPEC；纯格式问题不允许以「SPEC 没写」为由自创风格。

---

## 2. 目录与文件组织

### 2.1 工作区目录（交付物与证据）

编码时只用以下目录：

| 目录 | 放什么 | 不放什么 |
|---|---|---|
| `rtl/` | 改动 patch / `CHANGES.md` / 集成脚本 | 整份源码副本 |
| `nemu/` | NEMU 侧改动说明与配置 | 编译产物 |
| `test/` | 定向用例 `.S`、随机用例生成脚本、链接脚本、trap handler | 手工粘贴的日志 |
| `scripts/` | 一键复现（build/run/verify） | 交互式临时命令 |
| `results/` | **结果数据来源**：`*.json` / 日志 / 波形 | 手改的结论表格 |

### 2.2 香山/yunsuan 改动位置（按改动性质决定）

| 改动 | 放置位置 | 依据 |
|---|---|---|
| 新归约数据模块（X-new） | `yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/`，`package yunsuan.vector.mac` | 与 `VIMac64b.scala` 同包同目录，便于复用 `CSA3to2/CSA4to2` 与既有位宽工具 |
| 新 FU wrapper | `src/main/scala/xiangshan/backend/fu/wrapper/`，`package xiangshan.backend.fu.wrapper` | `VIMacU.scala` 所在目录 |
| 译码表项（X1/X2/X14） | 既有文件内就地追加，**不新建文件** | `VecDecoder.scala` 的 `opmvv` 表、`VecExceptionGen.scala` |
| 编码常量（X6/X7） | `yunsuan/src/main/scala/yunsuan/`（`package.scala` 的 `VimacType`、`encoding/Opcode/VimacOpcode.scala`） | 既有编码对象 |

- **禁止**新建与既有文件同职责的平行文件（例如再造一个 `VIMac64b2.scala`）；新增模块必须是**新增职责**。
- 死代码文件（`fu/vector/VIMacU.scala`，全文注释）**不改**（`design/ARCHITECTURE.md` §4.3 X9）。
- 新模块文件名 `[TBD: X-new 的具体模块名与文件名未在 ARCHITECTURE §4.1 冻结，需在任务记录中定名后再写入文件]`。

### 2.3 NEMU 改动位置

| 改动 | 文件 | 约束 |
|---|---|---|
| 新指令表项（N1） | `src/isa/riscv64/instr/rvv/decode.h` 的 `def_THelper(vopmvv)` 内（`:314`起） | 插在 `return EXEC_ID_inv;`（`:372`）之前 |
| 执行体（N2） | `src/isa/riscv64/instr/rvv/vcompute.h` | 就地追加 `def_EHelper(vdot)`，不新建 `vdot.c` |
| 指令枚举（N3） | `src/isa/riscv64/include/isa-all-instr.h` 的 `VECTOR_INSTR_TERNARY(f)`（`:157-204`） | 加 `f(vdot)`，否则 `EXEC_ID_vdot` 不存在、编译不过 |

- **`vreg.h` 有两份同 include guard 文件**（`local-include/vreg.h:17` 与 `instr/rvv/vreg.h:19` 都定义 `__RISCV64_VREG_H__`），改动前必须先确认实际生效的是哪一份。
- 新指令不新增独立源文件，**除非**实现体超过既有单文件量级；`[TBD: NEMU 是否要为 vdot 允许新增独立 .c 文件，取决于实现体规模，需在任务记录中裁决]`。

### 2.4 文件命名

- Scala：`UpperCamelCase.scala`，文件名 = 主类名（`VIMac64b.scala` → `class VIMac64b`）。
- Scala 测试：`XxxSpec.scala`（`VIMac64bSpec.scala`）。
- C：`snake_case.c` / `snake_case.h`；RVV 侧约定为 `<域>.h`（分派，可 inline）+ `<域>_impl.c`（实现体）。
- 禁止用指令名以外的缩写造词；`vdot` 全小写、无分隔。

---

## 3. Chisel / Scala 规范（香山 + yunsuan）

### 3.1 格式化：以工具为准

| 工具 | 配置 | 现状（实测） |
|---|---|---|
| scalafmt | `repos/XiangShan/.scalafmt.conf`：`version = 3.8.1`、`maxColumn = 120`、`runner.dialect = scala213`、`preset = defaultWithAlign` | `make check-format` → `mill xiangshan.checkFormat`（`Makefile:344-348`）；CI job `scalafmt` 跑同一命令（`.github/workflows/emu.yml:619-638`） |
| reformat | 同上 | `make reformat` → `mill xiangshan.reformat`（`Makefile:347-348`） |
| scalastyle | `repos/XiangShan/scalastyle-config.xml`；测试树用 `scalastyle-test-config.xml`（实测 `diff` 仅 `<name>` 行不同） | 跑 `grep -rn 'scalastyle' repos/XiangShan/ --exclude-dir=.git` 只命中配置文件自身与 `.scalafmt.conf` 的 `rewrite.imports.sort = scalastyle`（`:21`）；构建脚本与 `.github/workflows/` 内**无调用点**，当前属「配置存在、未接线」 |

必须遵守的硬指标（来自 `scalastyle-config.xml`）：

| 项 | 值 | 配置行 |
|---|---|---|
| 单文件行数 | ≤ 800 | `:27-31` |
| 单文件类型数 | ≤ 20 | `:32-36` |
| 行宽 | ≤ 120（与 `maxColumn` 一致） | `:38-44` |
| 单类型方法数 | ≤ 30 | `:46-50` |
| 单方法参数 | ≤ 8 | `:52-56` |
| 单方法长度 | ≤ 50 行（忽略注释） | `:57-62` |
| Tab | 禁止 | `:66` |
| 文件尾换行 | 必须有 | `:68` |
| 行尾空格 | 禁止 | `:70` |
| 注释起始 `//` 后空格 | 必须有 | `:72` |
| block import / 通配 import | 禁止（`chisel3._`、`chisel3.util._` 例外） | `:115-122` |
| 行尾分号 | 禁止 | `:174-179` |
| `TODO`/`FIXME` | 会告警，应尽快修 | `:170` |

- **对齐惯例**：连续声明按列对齐。配置层面 `.scalafmt.conf:4` 用 `preset = defaultWithAlign`，并在 `:6-8` 额外把 `:` 加入对齐 token；实践中 `VIMacU.scala:20-29` 把一组 `private val x  = …` 的 `=` 手工对齐。照抄所在文件的对齐方式；**不要**只对齐自己新加的行而破坏整块。
- **yunsuan 子模块没有自己的 `.scalafmt.conf`**，顶层 `.scalafmt.conf` 的 `project.includePaths` 只声明 `src/main/scala/xiangshan/frontend/**.scala`（`.scalafmt.conf:26`）——即格式作用域在配置层面仅限 frontend，`backend/` 与 `yunsuan/` 不在其中。**该结论来自读配置，未执行 `make check-format` 验证**（本机 `mill` 不在 PATH）。`[TBD: yunsuan 子模块是否强制 scalafmt-clean（以及是否补一份独立 .scalafmt.conf）未裁决；当前校验不覆盖该树]`
- `[TBD: scalastyle 是否接入本地/CI 校验（配置已在仓内但无调用点），接入方式与阈值未定]`

### 3.2 命名

| 类别 | 规则 | 正则/例 |
|---|---|---|
| 包 | 全小写、无下划线、无大写 | `^[a-z0-9]*$`（`scalastyle:159-163`）；例 `yunsuan.vector.mac` |
| class / object | UpperCamelCase | `^[A-Z][A-Za-z0-9]*$`（`:126-136`）；例 `VIMac64b`、`VimacOpcode` |
| 字段 / `val` | lowerCamelCase；允许 `sx_` 前缀表示流水级 | `^(([a-z][0-9]\|perf\|debug)_)?[a-z][A-Za-z0-9]*$`（`:138-144`）；例 `sum_wo`、`walOut`、`sewS1` |
| object 内常量 | UpperCamelCase | `objectFieldRegex = ^[A-Z][A-Za-z0-9]*$`（`:142`） |
| 方法参数 | lowerCamelCase | `^[a-z][A-Za-z0-9]*$`（`:146-150`） |
| 方法名 | 类型可大写（当常量用） | `^[A-Za-z0-9]*$`（`:152-157`）；例 `def vdot = ...`、`def S = "b1".U` |
| 流水级后缀 | `S1`/`S2` 表示第 1/2 级寄存 | `sewS1`、`walOut`/`isFixPS2`（`VIMac64b.scala:209-215`） |

- 新指令的编码常量命名恒为 `vdot`（`VimacType.vdot`、`VimacOpcode.vdot`），与指令名一致，不加 `Vec`/`Vd` 前缀。
- 位宽常量写成 `N.W` 字面量并在需要时 `def width = N`（`VimacOpcode.scala:6`）。
- 布尔信号用 `is`/`has`/`need` 前缀（`isMacc`、`isFixP`、`wideInsts`），不在名字里写否定（不用 `notXxx`）。

### 3.3 文件结构

```scala
package <小写包名>            // 1. package 第一行

import chisel3._             // 2. import：chisel3 家族在前，仓内次之；禁止通配（两条例外）
import chisel3.util._
import yunsuan.vector._

/** 模块头注释：语义出处 + 位宽推导（见 §3.6） */
class Xxx extends Module {   // 3. 类
  val io = IO(new Bundle { … })
  …                          // 4. 常量 → 组合逻辑 → 寄存 → 输出赋值
}
```

- **license 头**：`scalastyle-config.xml:8-23` 只对**匹配到的文件**检查 Mulan PSL v2 头（`level="warning"`）。实测（`head -5 | grep Copyright`）覆盖率并不均匀：`backend/fu/vector/` 8/14、`backend/fu/wrapper/` 1/20、`yunsuan/vector/vectorIMAC/` 0/3。因此裁决是 **与所在目录的邻居保持一致**——同目录多数文件无头就不加；同一目录内既有有头文件也有无头文件时，**新文件中不加**（避免制造「只有新文件有头」的差异噪声）。`[TBD: 是否借当前改动给目标目录统一补 license 头（会放大 diff 面，与「最小改动面」冲突），未裁决]`
- 一个文件一个主类；辅助 `private[<pkg>] class`（如 `CSA3to2`）可同文件（`VectorFloatFMA.scala:1581,1596`），但受 `maxTypes = 20` 约束。
- 公开方法必须有返回类型标注（`PublicMethodsHaveTypeChecker`，`:166`）。

### 3.4 模块接口约定

**IO 定义**（照 `VIMac64b.scala:13-30`）：

1. 一律 `val io = IO(new Bundle { … })`，端口用 `Input(...)` / `Output(...)`；不用 `DecoupledIO` 描述 FU 数据模块的内部接口。
2. 端口宽度必须显式 `UInt(N.W)`；向量端口用 `Vec(n, UInt(m.W))` 或整体 `UInt((n*m).W)`，**同一模块内只用一种**并写注释说明。
3. 方向与命名：输入 `val vs1/vs2/oldVd`，输出 `val vd/vxsat`；控制位用独立 `Bool` 端口（`isMacc`、`isSub`、`widen`、`isFixP`），不用打包成 `UInt` 的隐式位域。
4. 每端口一行注释仅在语义不显然时写（例 `:23 // (w)macc(nmsac)/madd(nmsub)`）。

**Fire / 流水约束（硬约束）**：

- `fireS1` **由 X15 显式导出**：`VIMac64b` 端口表（`VIMac64b.scala:11-30`）新增 `Output(Bool()) fireS1`，其值即 `:33` 的 `GatedValidRegNext(fire)`；`sum_wo`（`:187`）同时导出为 `Output(Vec(8, UInt(16.W)))`。新归约模块的输出寄存使能**必须消费该端口**：`RegEnable(reduction, io.fireS1)`，与 `walOut`（`:208`）同拍（`design/ARCHITECTURE.md` §2.2 第 7 条、§5.3）。
- **单一来源 + 端口连接（机械判据）**：`grep -c 'vimacs(0).io.fireS1' VIMacU.scala` **恰为 1** 且该行是端口连接；**禁止 wrapper/新模块内本地重建使能**（含 `io.in.valid`、`RegNext(...)`、`GatedValidRegNext(...)`）——`VIMacU.scala:101` 的 `mod.io.fire := io.in.valid` 只是 `VIMac64b` 的输入 fire，不是 `fireS1`。（旧条款「禁止 `GatedValidRegNext(valid)`/`RegNext(valid)`」**不再采用**：对 Bool 二者等价于 `RegNext`，禁令与必须项同电路、不可判别。）
- **反压**：wrapper 加 `assert(!io.out.valid || io.out.ready)`；仅当断言失败时才允许把 `mod.io.fire` 改为 `valid && ready`，改后跑 vmac 回归（裁决 D05）。
- 第二级只允许组合逻辑 + 一次寄存；不得在归约后再插一级寄存（会变第 3 拍，违反 `VimacCfg.latency = 2`）。注：引 `walOut` 落 S3 组合拍**不增加 latency**（勘误见 `design/ARCHITECTURE.md` §2.2），但须先测 S3 深度。

**wrapper 与数据模块的分工**（照 `VIMacU.scala:45-150`）：

| 层 | 职责 | 禁止 |
|---|---|---|
| `VIMacU`（wrapper） | 拆分/拼接数据、接 `Mgu`、修正异常位、输出 Mux | 实现算术算法 |
| `VIMac64b` / 新数据模块 | 纯组合/流水算术，**不感知 `vl`/`vta`/`vma`** | 读 `ctrl`、判非法 |
| `Mgu` | tail/agnostic 掩码与字节合并 | 生成 0 以外的清零语义 |

- vdot 的「其余位清零」由数据模块输出端 `Cat(96'b0, sext32(S))` 完成，wrapper 用 `Mux(outIsVdot, vdotVd, mgu.io.out.vd)` 旁路 Mgu；**不得**改 `Mgu`（`design/ARCHITECTURE.md` §2.5、§4.3 X12）。
- 非法判定必须在译码层（`DecodeUnit`/`VecExceptionGen`），不依赖 FU 的 `illegal` 输出（`Mgu.scala:131` 恒 `false.B`）。

### 3.5 位宽与符号扩展

- 每个 `Cat`/切片都要能回答「这是多少位」；跨位宽赋值必须显式扩展：
  - 有符号：`sext19(sum_wo(i))`，**严禁零扩展**（差 `n×2^16`，模 2^19，见 `design/ALGORITHM.md` §1.4）；
  - 无符号：`0.U(N.W) ++ x` 或 `x.pad(N)`。
- 内部归约位宽固定 **19 位**（`S`），写回 `sext32(S)`；不得为省面积改 18 位（`design/SPEC.md` §1.4）。
- 位宽字面量统一 `N.W`；禁止 `UInt()` 无宽度推断后再靠隐式截断。
- 位宽推导必须写进模块头注释（§3.6）。

### 3.6 注释

- **模块头注释**（`scalastyle` 只要求有 docstring 风格即可，内容由本规范约束）：

  ```scala
  /** vdot cross-lane reduction tree (X-new)
    *
    * Semantics: S = Σ_{i=0..7} sext19(vs1[i] * vs2[i])   (SPEC §1.1)
    * Width: 19-bit signed; worst case 8*(-128)^2 = 131072 > 2^17-1 (ALGORITHM §1.3)
    * Latency: combinational, registered with fireS1 (ARCHITECTURE §2.2)
    */
  ```

- 内部注释：**解释为什么，不解释是什么**。位宽魔法数字（`16`、`19`、`96`）必须给出来源。
- 语言：**英文**（三棵树中文注释实测为 0/0/1 个文件，见 §10 A-1）。
- 不用 `TODO`/`FIXME` 长期挂着（`scalastyle:170` 会告警）；未定项写进任务记录并以 TBD 标记。
- 禁止注释掉的代码块；要删就删（既有 `:15 // val opcode = …` 属历史遗留，不新增同类）。

---

## 4. C 规范（NEMU）

### 4.1 格式化

- NEMU **没有 `.clang-format` / `.editorconfig`**（实测 find 无结果）。风格由既有代码约定：

| 项 | 约定 | 实证 |
|---|---|---|
| 缩进 | 2 空格，不用 Tab | `vcompute.h:868-874` |
| 花括号 | K&R（`func() {` 同行） | `vcommon.c:20` |
| 单行 if | 允许 `if (cond) stmt;` | `vcommon.c:30` |
| 指针声明 | **两种写法并存**：`Decode *s`（星号靠变量，`vcommon.c:8,20`）与 `rtlreg_t* fpreg`（星号靠类型，`vcommon.c:51`）——按新文件所在目录的多数派选择，不混用 | 同左 |
| 空行 | 函数间一空行 | `vcompute.h:866-871` |
| 行宽 | 无强制配置；相邻行普遍在 100 列上下（目测，非测量） | — |

- `[TBD: 是否引入 .clang-format 及具体 style 未裁决（仓库当前无配置，贸然引入会造成全文件重排）]`
- 单文件行数上限：`[TBD: scalastyle 的 800 行上限只覆盖 Scala；C 侧是否沿用同一阈值未定]`

### 4.2 命名

| 类别 | 规则 | 例 |
|---|---|---|
| 函数 / 变量 | `snake_case` | `check_vstart_exception`、`get_vlmax`、`byte1s` |
| 类型名 | 保留既有（`Decode`、`rtlreg_t`、`vtype_t`） | `vcommon.c:26-28` |
| 宏 | 全大写 + 下划线 | `ARITH`、`ARITH_WIDE`、`VECTOR_INSTR_TERNARY` |
| 指令执行体 | `def_EHelper(<指令名>)` | `vcompute.h:868` |
| 指令分派 | `def_THelper(<表名>)` | `decode.h:314` |
| 指令表项 | `def_INSTR_TAB("<pattern>", <name>)` | `decode.h:203` 宏定义 |

- 新指令的 C 侧标识符恒为 `vdot`：`def_EHelper(vdot)`、表项第二参数 `vdot`、枚举 `f(vdot)`——三处必须同名，否则 `EXEC_ID_vdot`/`exec_vdot` 无法拼出（`exec.h:30`、`decode.h:117-122` 的 `concat` 机制）。

### 4.3 文件与 include

- license 头：RVV 目录下**大部分**文件有 Mulan PSL v2 头，但不全（实测 11/15：`vcommon.c`、`vcommon.h`、`vfexp2.c`、`vfexp2.h` 无）。新增 `.c/.h` **带同款头**（多数派做法），年份沿用 `2020-2022` 或按实际年份。
- include guard 形如 `__RISCV64_<FILE>_H__`（`vcompute_impl.h:20`）。
- 整文件用 `#ifdef CONFIG_RVV … #endif // CONFIG_RVV` 包裹（`vcompute.h:17`、`vcommon.c:2`）。
- `#include <common.h>` 在首行（对外头），本地头用 `"…"`。
- 分派层（`.h`，`def_EHelper` 直接把实现放进去）与实现层（`_impl.c`）分离：**纯控制流/单条指令走 `.h`**，需要循环或多指令共享的大函数走 `_impl.c`（`vcompute_impl.c:332` 的 `require_vm`）。
- **重复 guard 陷阱**：`local-include/vreg.h:17` 与 `instr/rvv/vreg.h:19` 都用 `__RISCV64_VREG_H__`，改 NEMU 向量状态前先 `grep -rn '__RISCV64_VREG_H__'` 确认生效文件。

### 4.4 错误与异常

- 非法指令统一 `longjmp_exception(EX_II)`（`vcommon.c:22`、`vcompute.h:68`）；`EX_II` 来自 `src/isa/riscv64/local-include/intr.h:26`（`EX_II, // illegal instruction`），`longjmp_exception` 声明在 `include/cpu/cpu.h:52`、实现于 `src/cpu/cpu-exec.c:245`。
- **不要写 `isa_raise_intr(INTR_II, …)`**：本仓库的 RVV 代码路径不存在该 API（全仓 grep 命中 0；`isa_raise_intr` 只出现在 `tools/qemu-dl-diff/` 的 x86 桩里，`INTR_II` 全仓无定义）。`design/SPEC.md` §1.3、`design/ARCHITECTURE.md` §4.2 N2、`design/ALGORITHM.md` §3.3 只给语义判据，实现一律按本节的 API 写。
- `vstart` 检查统一调用 `check_vstart_exception(s)`（`vcommon.c:20-24`），不自己写 `if (vstart->val > 0)`。
- 不变量检查用 `Assert(cond, msg)`（`debug.h:53`，例 `vreg_impl.c:136-137`）；不可恢复用 `panic(...)`（`vreg_impl.c:89`）。
- 运行期告警用 `Loge(...)`（`vcompute_impl.c:1209`），不要用 `printf`。

### 4.5 注释

- 与 C 一致性：英文；模块内分节注释保持既有风格（`vcompute_impl.c` 用 `// ---- xxx ----`）。
- 语义出处写清（`/* vdot.vv: SPEC §1.1 */`），位宽推导指向 `design/ALGORITHM.md` §1.3，不复制推导过程。

---

## 5. 测试与断言要求

### 5.1 Chisel 单元测试

- 框架：`AnyFlatSpec with ChiselScalatestTester`（`VIMac64bSpec.scala:326`）。
- 组织形式：`trait XxxBehavior` 承载用例函数 → 顶层 `class XxxSpec` 用 `behavior of "…"` + `it should behave like …`（`VIMac64bSpec.scala:326-330`）。
- 每个用例必须有**期望值来源**：不允许「用被测公式重算期望」（tautological 禁令）；金标准为 `design/ALGORITHM.md` §3.1 的算法 A/A-B。
- 波形：需要时用 `withAnnotations(Seq(WriteVcdAnnotation))`（`VIMac64bSpec.scala:70`）。
- 运行：`cd repos/XiangShan/yunsuan && mill YunSuan.test.test`（`yunsuan/Makefile:80-81`）。
- 测试文件命名与目录归属：`[TBD: 项目级 test/ 目录尚未建立，RTL 定向用例是留在 yunsuan/src/test/scala 还是放 test/ 未定]`

### 5.2 必须覆盖的用例（映射 `design/ALGORITHM.md` §3.2）

| 组 | 硬要求 |
|---|---|
| 混合符号奇数负 lane | 负 lane 数 = 1/3/5/7；专抓零扩展 bug |
| 19 位边界 | 全 −128（`S=131072`）、全 +127（`129032`）、最小负和（`−130048`） |
| lane 选择 | 高 64 位填干扰值，结果不变 |
| 高位清零 | **每例**断言 `vd[127:32] == 0` |
| vl / vta / vma | `vl=0/1/4/7` 结果不变；vta/vma 四组合结果不变 |
| vstart | `vstart=1` → 非法 |
| vxsat | 断言不被修改（`VIMac64b.scala:295` 保证恒 0） |
| 旧 vd | 预填非零，输出不依赖旧值 |
| 重叠 / RAW / 背靠背 | `vd==vs1`、`vd==vs2`；vdot→`vmv.x.s`；N 条连续发射测 `T_steady` |

### 5.3 断言（RTL 内建）

- **非法/不支持的 opType**：与相邻 FU 一致用 `XSError`，首参为条件、次参为字符串：

  ```scala
  XSError(io.in.valid && io.in.bits.ctrl.fuOpType === VimacType.dummy, "VialuF OpType not supported")
  ```

  （`VIMacU.scala:46`；同类见 `VFMA.scala:17`、`VIDiv.scala:16`。`XSError` 定义于 `utility/src/main/scala/utility/LogUtils.scala:196`，签名为 `apply(cond: Bool, fmt: String, data: Bits*)`，`:177`。）
- **使能约束的可执行断言（2026-11-01 定稿）**：① 静态判据 `grep -c 'vimacs(0).io.fireS1' VIMacU.scala` 恰为 1 且为端口连接行；② 仿真期 `assert(!io.out.valid || io.out.ready)`（反压哨兵）；③ wrapper 输出 `assert(PopCount(res.data(VLEN-1, 32)) === 0)`（高 96 位恒零，Mux 后）。拍对齐用「背靠背 `vdot → vmacc → vdot`（含 bubble）」用例判，不靠静态推断。
- 断言消息用英文并带模块名。注意既有 message 与实际模块**并不同步**（`VIMacU.scala:46` 写的是 `"VialuF OpType not supported"`，`VIDiv.scala:16` 写的是 `"Vfdiv OpType not supported"`）——这是既有拷贝痕迹；**新增消息用本模块名**，不要继续复制。
- 断言只用于「不该发生」的条件，不用于校验计算结果（结果校验在测试里做）。

---

## 6. 提交与可复现要求

### 6.1 Commit 规范

- **一处改动一个 commit**：一次 commit 只含一个改动编号（X1/X2/X6/X7/X8/X14/X15/X-new/N1/N2/N3）。
- **成对改动不拆**（`design/ARCHITECTURE.md` §5.4）：X1+X2、X6+X7、N1+N2+N3、X15+X8/X-new 各自至少要在**同一次提交或相邻且可编译的提交序列**里；不允许中间态编译不过。
- **X15（`VIMac64b` 端口）单独 commit**，且必须附 vmac 回归结果（`design/ARCHITECTURE.md` §5.3）。
- message 格式（照仓内历史：`a4eeaab fix(frontend): …`、`a683e0b feat(configs): …`）：

  ```
  <type>(<scope>): <改动编号> <一句话>

  <正文：改了什么、为什么；语义来源 SPEC 小节>

  Verified:
    <命令1>   -> <期望/实际>
    <命令2>   -> <期望/实际>
  Commit: <被修改仓的 commit hash>
  ```

  - `type` ∈ `feat|fix|refactor|test|docs|build|chore`；`scope` 为模块/目录（`vdot`、`nemu`、`decode`）。
  - subject 用英文；正文中英文均可。
  - **`Verified:` 段是硬要求**：没有「命令 + 结果」的提交视为未验证。

### 6.2 留痕六件套（`design/ALGORITHM.md` §3.6）

每次产生证据的跑动，必须在 `results/` 留：

| # | 件 | 形式 |
|---|---|---|
| 1 | 命令 | 原样可复制（含 `make`/`mill`/`node`/`python3` 参数） |
| 2 | commit hash | 被改仓 `git rev-parse --short HEAD`；NEMU 与 yunsuan 各自单独记 |
| 3 | 配置 | NEMU defconfig 名、香山 `JVM_XMX`、difftest `DIFFTEST_REG_SIZE` |
| 4 | 波形 | `.vcd`/`.fst` 路径（需要时） |
| 5 | 日志 | stdout/stderr 原文件，不改写 |
| 6 | 测试输入/输出 | 用例 `.S`/向量与期望值 |

- `results/*.json` 为**结果数据来源**；结论表格由脚本生成，不手写。
- 每条结果显式记录 `通过/失败/未运行`；**「未运行」不是通过**。
- `[TBD: results/*.json 的 schema 字段未定稿（ALGORITHM §3.6 只要求「定 schema」），需在 S2 基线任务记录里固化]`
- `[TBD: 波形与日志的存放路径与命名规则未定（results/ 目录尚未建立），需与任务记录一并确定]`

### 6.3 版本锁定 preflight（每次改动前执行）

```sh
# 1) 双副本约束：只改 XiangShan 内的 yunsuan
test "$(git -C repos/XiangShan/yunsuan rev-parse --short HEAD)" = 9559211 || echo "STOP: yunsuan 版本不符"

# 2) 确认没有误改另一副本
diff -q repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VIMac64b.scala \
        repos/YunSuan/src/main/scala/yunsuan/vector/vectorIMAC/VIMac64b.scala   # 预期：文件不同

# 3) 记录三仓基线
git -C repos/XiangShan rev-parse --short HEAD        # 预期 a4eeaab
git -C repos/NEMU rev-parse --short HEAD             # 预期 a683e0b
git -C repos/XiangShan/yunsuan rev-parse --short HEAD # 预期 9559211
```

第一条断言失败即停止（`design/ARCHITECTURE.md` §5.1）。三条 hash 与预期不符时，先更新 `versions.env` 与文档，再动代码。

---

## 7. 自动化改动约定

### 7.1 开工前（按序，不可跳）

1. 先读设计文档集对应小节，取「当前状态、当前阻塞、下一步」。
2. 按任务类型取最小必读集，**禁止漫游式阅读**。
3. **先 grep 后改**：改任何符号前先定位全部命中，并把命中清单写进任务记录。

### 7.2 先 grep 后改（可执行清单）

改代码前的**强制 grep**（命中为空也要记录「0 命中」）：

```sh
# 新指令名是否已被占用（应全部 0 命中，若命中说明编码撞车）
grep -rn 'vdot' repos/XiangShan/src/main/scala/ repos/NEMU/src/ repos/NEMU/include/
grep -rn 'VDOT_VV' repos/XiangShan/
grep -rn '0011101??????????010?????1010111' repos/XiangShan/
grep -rn '001110 1 ' repos/NEMU/src/isa/riscv64/instr/rvv/decode.h

# 改动位置是否仍然存在（行号漂移时以符号为准）
grep -n 'class VIMac64b' repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VIMac64b.scala
grep -n 'def vmul' repos/XiangShan/yunsuan/src/main/scala/yunsuan/encoding/Opcode/VimacOpcode.scala
grep -n 'val opmvv' repos/XiangShan/src/main/scala/xiangshan/backend/decode/VecDecoder.scala
grep -n 'def_THelper(vopmvv)' repos/NEMU/src/isa/riscv64/instr/rvv/decode.h
grep -n 'VECTOR_INSTR_TERNARY' repos/NEMU/src/isa/riscv64/include/isa-all-instr.h

# 死代码 / 重复文件陷阱
grep -rn 'class VIMacU' repos/XiangShan/src/main/scala/xiangshan/backend/fu/   # 命中 2 处：fu/vector/ 是死代码
grep -rn '__RISCV64_VREG_H__' repos/NEMU/src/
```

- `ARCHITECTURE.md` 里给的是「文件:行」锚点；**行号可能漂移**，改代码时以 grep 到的符号为准，并把新行号写回任务记录。
- 只改 grep 命中的位置；未命中的文件不碰。

### 7.3 改动最小面 + 改后校验（分级）

**最小面**：只改 `design/ARCHITECTURE.md` §4 改动位置表内的文件；表外文件（X3/X4/X5/X9/X10/X11/X12/X13）默认不动。任何表外改动必须在任务记录里写明理由并在 commit body 说明。

改后按改动类型执行校验（**逐级，前一级不过不进下一级**）：

| 级别 | 触发 | 命令 | 通过判据 |
|---|---|---|---|
| L0 版本 | 每次 | §6.3 的三条 hash | 与锁定值一致 |
| L2 格式 | 改了 Scala | `cd repos/XiangShan && make check-format` | 退出码 0 |
| L3 单元 | 改了 yunsuan 模块 | `cd repos/XiangShan/yunsuan && mill YunSuan.test.test` | 全部用例通过 |
| L4 编译 | 改了香山/NEMU | `cd repos/XiangShan && make sim-verilog`；`cd repos/NEMU && make -j`（kmhv2 defconfig） | 退出码 0 |
| L5 模块仿真 | 改了数据通路 | Verilator `--lint-only` / `--binary`（Docker 5.052） | 无 lint error，定向用例通过 |
| L6 全核 difftest | 改了 RTL 且要证据 | `cd repos/XiangShan && make emu` 后 `./build/emu -b 0 -i <elf>` | `HIT GOOD TRAP` 且 0 次 ABORT |
| L7 回归 | X15 / 端口类改动 | `scripts/check_results.py` 对比 `results/regression_baseline.json` | `regression_delta == 0` |
| L8 NEMU 协同 | 改了 N1/N2/N3 | `nm build/riscv64-nemu-interpreter-so \| grep exec_vdot` | 命中 1 行；`.so` 已重编 |

- **本机内存 15.3 GiB**，`make emu` 默认 `JVM_XMX=40G`（`Makefile:81`）必挂；本机只能走 `make emu JVM_XMX=8G JVM_XSS=256m`，或放到远程（`design/ALGORITHM.md` §3.7）。
- **校验脚本现状**：`design/verify/vdot_model_test.py` 已就位（2026-10-30 实测 `ALL TESTS PASSED (1132 cases)`、EXIT=0）；`scripts/check_results.py` 与 `results/` 目录仍未创建。L7 依赖 `scripts/check_results.py`，L8 依赖 NEMU 改动与 `.so` 重编；两者在条件满足前只能记「未运行」，不得记为通过。
- **本机 `mill` 不在 PATH**（实测 `which mill` → 未找到），L2/L3 必须先按 xs-env 装 mill，否则只能记为「未运行」。
- L6/L7 未执行时必须写「未运行」，**不得**用「代码看起来对」代替。
- RTL 侧 Verible `lint/format` 是否作为强制校验：`[TBD: 本机仅有 Verible 静态包（v0.0-4298），尚未接入 CI 与校验流程]`

### 7.4 自动化改动禁止事项

1. **不猜**：语义/编码/位宽有疑问时回 `design/SPEC.md`；文档没写就停下来记 TBD 标记或提问，不自行发明规则。
2. **不扩散**：一次只改一个位置；不顺手重排格式、不改无关行、不升级依赖。
3. **不重生**：不新建与既有文件同职责的平行实现；不重写整文件只为「更清晰」。
4. **不动死代码**：`fu/vector/VIMacU.scala` 全文注释，改了无效。
5. **不碰共享配置**：不改 `VimacCfg` 的 `latency`（会让所有 vimac 指令一起变慢，`design/ARCHITECTURE.md` §3.2）；不为此新建共享 `FuType` 除非走 3 拍退路并单独成一次提交。
6. **不写绝对化措辞**：未实测一律「目标/待测」；结果表只从 `results/*.json` 生成。
7. **不伪造证据**：没跑的命令不写进 `Verified:`；没生成的日志不写路径。

---

## 8. 完成判据（可执行）

1. 本文 TBD 条目 ≤15：正文 `grep -n 'TBD:' design/CODING-STD.md | grep -v 'grep -n' | wc -l` 输出 ≤15（当前 12），与 §9 表 12 行一一对应（只匹配精确 `[TBD]`；`[TBD: …]` 的数量由本条的 grep 命令约束）。
2. 任一提交都能用其 `Verified:` 段的命令复跑，且 `git rev-parse --short HEAD` 与记录的 hash 一致。
2. 新 Scala 文件满足 `scalastyle-config.xml` 的 800 行 / 120 列 / 50 行方法 / 8 参数 / 无 Tab / 尾换行。
3. 新 C 文件带 Mulan PSL v2 头、`__RISCV64_<FILE>_H__` guard、2 空格缩进；非法路径用 `longjmp_exception(EX_II)`。
4. 每处改动都有对应任务记录与证据路径；`results/` 中每条结果显式标注 `通过/失败/未运行`。

---

## 9. 未定条目汇总（≤15）

| # | 条目 | 原因 |
|---|---|---|
| 1 | 新归约模块的文件名与模块名 | §2.2，ARCHITECTURE §4.1 只写 `X-new`，未冻结命名 |
| 2 | NEMU 是否新增独立 `.c` 文件 | §2.3，取决于实现体规模 |
| 3 | yunsuan 子模块是否强制 scalafmt-clean | §3.1，顶层 `.scalafmt.conf` 的 `includePaths` 仅覆盖 frontend |
| 4 | scalastyle 是否接入校验、接入方式 | §3.1，仓内配置存在但无调用点 |
| 5 | C 侧是否引入 `.clang-format` | §4.1，仓库当前无配置 |
| 6 | C 文件是否沿用 800 行上限 | §4.1，该阈值来自 Scala 侧 scalastyle |
| 7 | RTL 定向用例的目录归属（`test/` vs `yunsuan/src/test`） | §5.1，项目级 `test/` 尚未建立 |
| 8 | `fireS1` 仿真期断言是否可行 | §5.3，需确认 `GatedValidRegNext` 的 XMR 可见性 |
| 9 | `results/*.json` schema 字段 | §6.2，ALGORITHM §3.6 只要求定 schema |
| 10 | 波形/日志的存放路径与命名 | §6.2，`results/` 尚未建立 |
| 11 | Verible `lint/format` 是否作为强制校验 | §7.3，本机仅有静态包，未接入 CI 与任务记录 |
| 12 | 是否给目标目录统一补 license 头 | §3.3，覆盖率不均（8/14、1/20、0/3），统一补会放大 diff 面 |

> 上表 12 条与正文 12 处 TBD 标记一一对应，≤15 上限仍有余量。

---

## 10. 证据附录（精选证据 + 指针）

### A-1｜三棵树的中文注释实测（`grep -rlP '[\x{4e00}-\x{9fff}]'`）

```
XiangShan/src/main/scala/（全树）             → 1 个文件 / 382 个 .scala（NewCSR/InterruptFilter.scala）
XiangShan/yunsuan/src/main/scala/             → 0
NEMU/src/isa/riscv64/instr/rvv/               → 0
⇒ 结论：三棵树的注释语言事实上是英文；本规范把它写死，不再新增中文注释。
```

### A-2｜格式工具链的现状（实测）

```
repos/XiangShan/Makefile:344-348   check-format: mill xiangshan.checkFormat / reformat: mill xiangshan.reformat
repos/XiangShan/.github/workflows/emu.yml:619-638  job "scalafmt" → make check-format
repos/XiangShan/.scalafmt.conf:3,26  maxColumn = 120；includePaths 仅 xiangshan/frontend/**.scala
grep -rn 'scalastyle' repos/XiangShan/build.sc .github/  → 无调用点（只有配置文件本身）
repos/XiangShan/yunsuan/  → 无 .scalafmt.conf / scalastyle 配置
repos/NEMU/ → 无 .clang-format / .editorconfig
```

### A-3｜命名/风格规则的出处（`repos/XiangShan/scalastyle-config.xml`）

```
:27-31 FileLengthChecker maxFileLength=800      :38-44 FileLineLengthChecker maxLineLength=120
:46-50 NumberOfMethodsInTypeChecker maxMethods=30   :52-56 ParameterNumberChecker maxParameters=8
:57-62 MethodLengthChecker maxLength=50         :66 FileTabChecker
:126-136 ClassNamesChecker/ObjectNamesChecker   :138-144 FieldNamesChecker（sx_ 前缀例外）
:146-163 MethodArgumentNamesChecker/MethodNamesChecker/PackageNamesChecker
:115-122 BlockImportChecker / UnderscoreImportChecker（chisel3._、chisel3.util._ 例外）
:170 TodoCommentChecker                         :174-179 禁止行尾 ';'
```

### A-4｜模块接口与 fireS1 锚点（`repos/XiangShan/yunsuan/.../VIMac64b.scala`）

```
:12-30  class VIMac64b / io 端口表（Input/Output 显式 .W）
:33     val fireS1 = GatedValidRegNext(fire)
:187    val sum_wo = Wire(Vec(8, UInt(16.W)))
:200    sum_wo(i) := adder_16b.out
:208    walOut := RegEnable(sum_wo.asUInt, fireS1)
:295    io.vxsat := Mux(isFixPS2, vxsat, 0.U)
```

### A-5｜wrapper 分工与 XSError 先例（`repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/`）

```
VIMacU.scala:45   class VIMacU(cfg: FuConfig)(implicit p: Parameters) extends VecPipedFuncUnit(cfg)
VIMacU.scala:46   XSError(io.in.valid && io.in.bits.ctrl.fuOpType === VimacType.dummy, "VialuF OpType not supported")
VIMacU.scala:64   private val vimacs = Seq.fill(numVecModule)(Module(new VIMac64b))
VIMacU.scala:65   private val mgu = Module(new Mgu(dataWidth))
VIMacU.scala:148  io.out.bits.res.data := mgu.io.out.vd
VIMacU.scala:150  io.out.bits.ctrl.exceptionVec.get(ExceptionNO.illegalInstr) := mgu.io.out.illegal
VFMA.scala:17 / VIDiv.scala:16  同款 XSError 用法
```

### A-6｜NEMU C 侧约定（实测）

```
vcompute.h:868-874   def_EHelper(vmacc) { ARITH(MACC, SIGNED) }；2 空格缩进
vcompute_impl.c:332-336  void require_vm(Decode *s) { if (s->vm == 0 && id_dest->reg == 0) longjmp_exception(EX_II); }
vcommon.c:20-24      void check_vstart_exception(Decode *s) { if (vstart->val > 0) longjmp_exception(EX_II); }
vreg_impl.c:286-290  void set_vreg_tail(...) 写 0xffffffffffffffff（不是 0）
vreg_impl.c:82       int get_vlmax(int vsew, int vlmul)（vlmul=0 ↔ LMUL=1）
decode.h:314/372     def_THelper(vopmvv) 起点 / return EXEC_ID_inv
isa-all-instr.h:157,177,204   VECTOR_INSTR_TERNARY(f) 起 / f(vmacc) / 结束
debug.h:53           #define Assert(cond, ...)
exec.h:30            #define def_EHelper(name) static inline void concat(exec_, name) (Decode *s)
grep -rIn 'isa_raise_intr|INTR_II' repos/NEMU/  → 仅 tools/qemu-dl-diff/ 的 x86 桩，RVV 路径无此 API
```

### A-7｜版本锁定与 commit 风格（实测）

```
repos/XiangShan          a4eeaab  "fix(frontend): carry true PC guard bits through BPU and RAS (#6720)"
repos/NEMU               a683e0b  "feat(configs): add layered BOOM reference profiles (#1262)"
repos/XiangShan/yunsuan  9559211  "build: bump chisel 6.7.0"
repos/YunSuan            267ff73（禁止参照）
```

**完整证据指针**（不列入每次必读，按需到达）

- `design/ARCHITECTURE.md` §4/§5：改动位置表、成对改动、X15 专门约束；
- `design/ALGORITHM.md` §3：验证矩阵、可复现六件套、回归基线；
