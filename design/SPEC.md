# vdot.vv 指令规格（SPEC）

> 文档地位：**本文档集（SPEC/ARCHITECTURE/ALGORITHM）为设计与实现的依据，与其他材料冲突时以本文档集为准**。本文只陈述现行设计，不叙述纠错史。
> 适用：**改 RTL 译码或执行语义、改 NEMU `vdot` 实现、写测试期望值、锁定编码、准备答辩语义口径**时必读。
> 关联文档：微架构与改动位置见 `design/ARCHITECTURE.md`；19 位位宽推导与验证算法见 `design/ALGORITHM.md`。
> 证据附录：§4 为精选证据（≤80 行，逐条给出 `文件:行`）。

---

## 0. 速查表

| 项 | 裁决 |
|---|---|
| 指令 | `vdot.vv vd, vs2, vs1`（OPMVV，无掩码） |
| 语义 | `S = Σ_{i=0..7} sext19(sum_wo[i])`，其中 `sum_wo[i] = sext8(vs1[i]) × sext8(vs2[i])`；取低 64 位 lane 0–7 |
| 内部位宽 | 19 位有符号；写回 `vd[31:0] = sext32(S)`，`vd[127:32] = 0` |
| 合法条件 | **六条必要条件**：`SEW=8 ∧ LMUL=1 ∧ vm=1 ∧ vstart=0 ∧ vill=0 ∧ mstatus.VS≠OFF`，任一不成立即非法；**非法判定优先于 `vl=0` 全写** |
| 编码 | opcode `1010111` / funct3 `010` / funct6 `001110` / vm `1`（C-enc1b）；回退池见 §2.4 |
| 机器码示例 | `vdot.vv v3, v2, v1` = `0x3A20A1D7`（vs2=v2、vs1=v1） |

---

## 1. 指令语义

### 1.1 语义定义（以本文档集为准）

| 项 | 裁决 |
|---|---|
| 运算 | `S = Σ_{i=0..7} sext19(sum_wo[i])`，其中 `sum_wo[i] = sext8(vs1[i]) × sext8(vs2[i])` 是 16 位有符号积；每个积先符号扩展到 19 位再入树，**严禁零扩展**。取 vs1/vs2 **低 64 位 lane 0–7**，高 64 位不参与 |
| 内部位宽 | **19 位有符号**（最坏 8×(−128)×(−128)=131072，超过 18 位有符号上限 131071）；写回 32 位 |
| 写回 | `vd[31:0] = sext32(S)`，`vd[127:32] = 0`（恒清零，与 vta/vma/tail 无关，本指令是全写指令） |
| 旧 vd | **不读、不累加**（vdRen=F、不进 isMacc、不登记 vmaInsts，见 §3.3） |
| 合法条件 | **六条彼此独立的必要条件**：`SEW=8 ∧ LMUL=1 ∧ vm=1 ∧ vstart=0 ∧ vill=0 ∧ mstatus.VS≠OFF`；任一不成立即非法（illegal instruction），**非法判定优先于 `vl=0` 全写**。`vill=1` 时即使 vsew=0/vlmul=0 恰好对应 SEW=8/LMUL=1 也必须判非法（非法 vsetvl 会把 vtype 清 0，四元组照常成立：RTL `Vsetu.scala:121-128`、NEMU `vcommon.c:114-120`）；`mstatus.VS=OFF` 由 `DecodeUnit.scala:908` 拦截。谓词写法固定，见 §1.3 |
| vl | 不影响结果：vl 任意值（含 0 与 1–7）都算 lane 0–7 并全写 vd。这是对 RVV 常规"vl=0 不写回"的有意偏离，理由=官方伪代码无条件；NEMU/RTL/金模型同口径。**NEMU 侧禁止用 `check_vstart_ignore`**（它在 `vstart>=vl` 时跳过写回，vl=0 时 0>=0 成立 → 不写 vd，与本条冲突） |
| vstart | **`vstart≠0` 触发非法指令**（与 `VecExceptionGen.scala:275` 现行为一致，不改异常生成器）；正常执行路径 vstart 恒为 0 |
| vta/vma | 均不影响结果，`vd[127:32]` 恒清零；测试覆盖 vta/vma 四组合并断言结果不变 |
| vxsat | **恒 0、不修改**（`VIMac64b.scala:295` 的 `Mux(isFixPS2, vxsat, 0.U)` 已保证；`vxsat` 是 sticky 位，执行前后读回必须一致）；测试用 `csrr vxsat` 前后对比断言不变 |
| mstatus.VS / 旧 vd | 正常执行后 `mstatus.VS` 置 Dirty；**非法路径的 VS 只记录实测值，不预设「不变」**（裁决 D04：先用 `vstart=1` 定向用例测出真实值再定论）。旧 vd **不是语义输入**（`vdRen=F`、`src3=X`）：预填非零旧值必须不影响输出，`vd==vs1/vs2` 重叠按写后读语义 |
| 数值范围 | S ∈ [−130048, 131072]（含全 −128 组合）；19 位有符号 [−262144, 262143] 可容 |

> 注：改动位置见 `design/ARCHITECTURE.md` §4 的 X8/X14 与 §6（不登记 vmaInsts）；NEMU 侧入口检查见 `design/ARCHITECTURE.md` §4.2 的 N2。

### 1.2 三个机器可判点

语义是否被正确实现，最终由以下三点逐位判定，不允许"看起来对"：

1. **lane 选择**：只取 vs1/vs2 的低 64 位（lane 0–7），高 64 位不参与。测试必须包含"高 64 位干扰用例"。
2. **高位清零**：`vd[127:32]` 恒为 0，与 `vta/vma/tail` 无关。每个用例必须断言"高 96 位恒零"。
3. **不读旧 vd**：`vdRen=F`、不进 `isMacc`、不登记 `vmaInsts`；清零由数据通路 `Cat(96'b0, ...)` 保证，不依赖 Mgu。

### 1.3 合法条件与非法判定位置

- 合法条件 = **六条必要条件**（任一不成立即非法）：`SEW=8`、`LMUL=1`、`vm=1`、`vstart=0`、`vill=0`、`mstatus.VS≠OFF`；非法判定优先于 `vl=0` 全写。
- RTL 译码层按**编码后的 vtype 字段**判定，**谓词固定写法**：`isVdot && (SEW =/= 0.U || LMUL =/= 4.U)` → 非法。其中 `SEW = io.vtype.vsew(1,0)`（`vsew=0` ↔ SEW=8，故 `SEW =/= 0.U` 即 SEW≠8）；`LMUL = Cat(~io.vtype.vlmul(2), io.vtype.vlmul(1,0))`（`VecExceptionGen.scala:58`，`vlmul=000` → `LMUL=4` ↔ LMUL=1，故 `LMUL =/= 4.U` 即 LMUL≠1）。**禁止写 `vlmul === "b001"`**（那是 LMUL=2：`Bundles.scala:168-169` `m1="b000"`、`m2="b001"`）。`vill=1` 由 `VecExceptionGen.scala:178` 的 `villIllegal` 覆盖（vimac 在 `isVArith` 内，`FuType.scala:127,130`），`mstatus.VS=OFF` 由 `DecodeUnit.scala:908` 覆盖。必测三例：LMUL=1 合法；LMUL=2/4/8 非法。
- `vstart≠0` 判非法与硬件现行为一致（`VecExceptionGen.scala:275`：`vstartIllegal = isVArith && io.vstart =/= 0.U`，`vimac` 在 `isVArith` 内）；NEMU 同口径判非法。正常执行路径 vstart 恒为 0。
- `vl` 不影响语义：无条件计算 lane 0–7 并全写 vd，`vl==0` 亦然（有意偏离 RVV 常规，见 §1.1）。
- `Mgu.illegal` 恒为 false（`Mgu.scala:131`），因此非法判定**必须在译码层**（`DecodeUnit.scala` / `VecExceptionGen`），不能依赖 FU 输出；改动位置见 `design/ARCHITECTURE.md` §4 的 X14。
- NEMU 侧入口用同一组条件：`vm=0`、`vsew≠0`、`vlmul≠0`、`vill=1` 任一命中 → 非法指令；`vstart` 用 `check_vstart_exception(s)`（`vcommon.c:20-24`，`vstart->val > 0` 抛 `EX_II`）覆盖。**禁止用 `check_vstart_ignore`**（它在 `vstart>=vl` 时跳过写回，vl=0 时 0>=0 成立 → 不写 vd，与 §1.1 的 vl=0 全写语义冲突）。实现所用的异常 API 以 `design/CODING-STD.md` §4.4 为准（`longjmp_exception(EX_II)`），**不要写 `isa_raise_intr(INTR_II, …)`**——本仓库 RVV 路径无此 API（`INTR_II` 全仓无定义）。NEMU 的 `vlmul=0` ↔ LMUL=1（`vreg_impl.c:82-105` 的 `get_vlmax`）。**禁止用 `set_vreg_tail` 清零**：它在 `vreg_impl.c:286` 写 `0xFF` 而不是 0；高 96 位必须手写显式清零。

### 1.4 数值范围与位宽

- 内部 `S` 的最坏正和为 `8×(−128)×(−128) = 131072`，最坏负和为 `8×(−128)×127 = −130048`。
- 19 位有符号范围 `[−262144, 262143]` 可容；18 位有符号上限 `131071` 装不下 `131072`。
- 写回固定 32 位：`vd[31:0] = sext32(S)`，高 96 位清零；因此风险只在内部归约树位宽与边界测试，外部可观测结果不变。
- 推导过程与复现命令见 `design/ALGORITHM.md` §1.3。

---

## 2. 编码

### 2.1 编码三元组（C-enc1b）

| 字段 | 值 |
|---|---|
| opcode | `1010111` (0x57, OP-V) |
| funct3 | `010` (OPMVV) |
| funct6 | **`001110`（0x0E）**——2026-10-31 联网复核：riscv-opcodes `f24ac23` 全库在 funct3=010/opcode=0x57 下无任何占用（含 ratified Zvbc 与 unratified 提案）；香山/NEMU 实现侧同样空闲 |
| vm | `1`（无掩码；掩码版非法） |
| 机器码示例 | `vdot.vv v3, v2, v1` = **`0x3A20A1D7`**（标准汇编顺序 `vd, vs2, vs1`；vs2=v2、vs1=v1） |

> **为什么从 C-enc1 改到 C-enc1b**：原 `001100/010`（0x0C）经联网复核被 Zvbc 的 `vclmul.vv` 正式占用（`riscv-opcodes/extensions/rv_zvbc`）。新 `001110/010`（0x0E）在同一仓库全库扫描中无冲突。证据：`stage2/2.1-design/encoding-gate-zvbc-2026-10-31.md`。

### 2.2 机器码位域展开

下表的位域拼接是对机器码示例的格式展开，不改变任何字段值（汇编顺序 `vd, vs2, vs1`；位域固定为 vs2=[24:20]、vs1=[19:15]）：

| 位域 | 值 | 说明 |
|---|---|---|
| `[31:26]` funct6 | `001110` | C-enc1b |
| `[25]` vm | `1` | 无掩码 |
| `[24:20]` vs2 | `00010` | 示例中的 `v2` |
| `[19:15]` vs1 | `00001` | 示例中的 `v1` |
| `[14:12]` funct3 | `010` | OPMVV |
| `[11:7]` vd | `00011` | 示例中的 `v3` |
| `[6:0]` opcode | `1010111` | OP-V |
| 拼接 | `001110_1_00010_00001_010_00011_1010111` | 即 `0x3A20A1D7` |

### 2.3 为什么不是 `101100/010`（C-enc1 治理论证）

`101100/010` 是上游未批准提案 Zvdot4a 的 `vdot4a.vv` 官方分配，语义是"每 32 位元素 4×int8 **累加**"，与本项目的 K=8 单结果语义不同——**语义不同不占用他人官方分配**。

因此：

- 主线 `vdot.vv` 用实现侧空闲且经 riscv-opcodes 联网复核的 `001110/010`（C-enc1b）；
- 扩展 `vdot4a.vv`（严格对齐 Zvdot4a 语义，含 `vd[i]+=` 累加）用 `101100/010`，名正言顺；扩展只做文档路线图，不写扩展 RTL（见 §3.2）。

### 2.4 回退池（原 C-enc2 不再采用）

**原 C-enc2（主线借用 `101100/010`）判不可用**：`101100/010` 是未批准提案 Zvdot4a `vdot4a.vv` 的官方分配（§2.3），借用它与「语义不同不占用他人官方分配」自相矛盾；编码校验脚本的 mutant `0x2C` 实测 EXIT=1（命中）。编码锁定前若 `001110/010` 被占用，按顺位改用回退池并**逐个跑上游快照扫描**，命中即弃：

| 顺位 | funct6/010 | 依据 |
|---|---|---|
| 1 | `010001` | 实现侧空闲（§2.6 双侧 grep）+ 官方快照无占用 |
| 2 | `010011` | 同上 |
| 3 | `101110` | 同上 |
| 4 | `111001` | 同上 |

回退时必须同步改：本节/§2.1/§2.2、`design/ARCHITECTURE.md` 的 X1/N1、编码校验脚本的 `[A]` 核对文本、金模型测试的机器码常量。vdot4a 扩展编码另行分配，不再声称对齐 Zvdot4a 编码。

### 2.5 禁用清单（实测撞车）

| 编码（opcode/funct3/funct6） | 实际指令（命名空间） | 证据 |
|---|---|---|
| `111111/010` | `vwmaccsu` | `Instructions.scala:819` |
| `101100/000` | `vnsrl`（OPIVV 命名空间） | `Instructions.scala:705-707` |
| `101100/001` | `vfmacc`（OPFVV 命名空间） | `Instructions.scala:470-471` |
| `101101/010` | `vmacc` | `Instructions.scala:609` |

### 2.6 实现侧空闲 OPMVV funct6 全表

编码锁定证据（双侧 grep）：

```
001100 001101 001110 001111 010001 010011 010101 010110
101000 101010 101100 101110 111001 111110
```

- **编码三元组（opcode + funct3 + funct6）整体锁定，双侧 grep 留证。**
- 该表是"实现侧空闲"（香山与 NEMU 均未占用），不等于"RISC-V 官方未分配"；官方归属复核见 §2.4 与 §2.7。
- **2026-10-31 联网复核结论（更正早前结论）**：riscv-opcodes `master@f24ac23` 的 `extensions/rv_zvbc` 中 `vclmul.vv` 使用 `0x0C/010`、`vclmulh.vv` 使用 `0x0D/010`——即原 C-enc1 的 `001100/010` **已被正式 Zvbc 占用**；早期记录 `encoding-gate-2026-10-31.md` 的"0 命中"结论有误。全库扫描后，**新主线编码改为 `001110/010`（0x0E）**，在同一仓库 ratified + unratified 全库无占用（详见 `stage2/2.1-design/encoding-gate-zvbc-2026-10-31.md`）。

### 2.7 编码锁定前的核对要求

1. 查 riscv-opcodes，复核 `001110/010` 无官方分配；被占用则按 §2.4 回退 C-enc2。**2026-10-31 已联网复核关闭**：`git clone --depth 1 riscv/riscv-opcodes@f24ac23`，Python 精确扫描全部 `extensions/**` 中 funct3=0x2 且 opcode=0x57 的行 → `0x0E` 无任何占用；阳性对照 `0x0C/0x0D/0x15/0x16/0x28/0x2A/0x2C/0x2F/0x3E` 均命中对应扩展。证据：`stage2/2.1-design/encoding-gate-zvbc-2026-10-31.md`。官方其后若改分配，以同脚本重跑为准。
2. 香山（`rocket-chip/.../Instructions.scala` 与本地 `decode/Instructions.scala`）与 NEMU（`rvv/decode.h` 的 `vopmvv`）双侧 grep，留命令与输出。
3. funct6/funct3 粒度会“共槽”，最终必须按完整 25 位 BitPat 做重叠检查；实例见 §4 A-6。
4. 主线语义与编码冻结前必须完成本节的全部核对（D+0）。

---

## 3. 歧义裁决表

### 3.1 裁决主表

| 歧义 | 官方口径 | 本项目裁决 | 理由 |
|---|---|---|---|
| 结果位宽 | 未写死（SEW=8 的 vd[0] 装不下） | 32 位写 vd[31:0] | 自然容器；19 位 S 符号扩展 |
| 取哪 8 个元素 | "取 8 个 int8"（VLEN=128 有 16 个 byte lane） | 低 64 位 lane 0–7 | 最自然；用"高 64 位干扰"用例验证 lane 选择 |
| 其余位 | 伪代码 vd[1..]=0 | 恒清零（旁路 Mgu） | Mgu 的 tail/agnostic 永不为 0（实测 `Mgu.scala:83,90-92`：tail 保留旧 vd、agnostic 写 0xFF），必须旁路 |
| K=8 vs K=16 | 伪代码 K=8，宣讲页 K=16 | **主线 K=8**；K=16 只进扩展路线图 | 评分细则引用伪代码（docx/02 §三）；K=16 覆盖为 vdot16 扩展设计说明，不写扩展 RTL |

### 3.2 K=8 / K=16 对照（决策层）

| 项 | 内容 |
|---|---|
| 官方伪代码口径 | K=8（评分细则引用；`docx/02 §三`） |
| 官方宣讲页口径 | K=16 |
| 本项目主线 | K=8 |
| K=16 的位宽 | **20 位有符号累加**：`16 × 16384 = 262144 > 2^18−1 = 262143`（19 位有符号上限）；主线 19 位预算不变 |
| K=16 的覆盖位置 | 文档路线图（vdot16 扩展的编码/位宽/接口预留说明），不写扩展 RTL |
| 扩展约束 | 扩展全部降级为文档路线图；主线三阶段证据冻结前不开写；主线独立可交付，扩展只上行不下行 |
| 官方材料自相矛盾的具体证据 | 见 §4 A-1（原文摘录） |

**读法**：无论评委按哪版口径核对，SPEC 都给出对照与位置说明；主线始终以伪代码 K=8 为"完整性"基准，K=16 由扩展路线图覆盖。

### 3.3 裁决的落地约束

1. **三端同口径**：RTL、NEMU、Python 金模型必须同时遵守 §1.1 的全部行；任何一端偏离，difftest 会逐位暴露。
2. **测试必须覆盖裁决点**（并入 `design/ALGORITHM.md` §3.2 测试矩阵）：
   - "高 64 位干扰用例"验证 lane 选择；
   - "高 96 位恒零断言"验证清零；断言方法写明：`vse8.v` 存回内存后检查内存，或 `vslidedown` + `vmv.x.s` 逐段读回；
   - `vstart=1` 非法用例；`vl=0`、`vl<8` 用例断言"结果不变"；
   - `vill=1`（非法 vsetvl 后执行 vdot）非法用例；`mstatus.VS=OFF` 非法用例（记实测 `mcause/mtval`）；
   - `vta/vma` 四组合断言结果不变；`csrr vxsat` 前后读回一致；
   - 旧 vd 预填非零用例、`vd==vs1/vs2` 重叠用例；
   - old-vd 预填用例、`vd==vs1/vs2` 重叠用例、RAW 链（vdot → `vmv.x.s`/`vse8.v`）、N 条独立 vdot 背靠背。
3. **不得用 `vta=1` 代替清零**：这样得到的是 `0xFF`，不是 0；清零必须在数据模块输出端完成并旁路 Mgu。
4. **旧 vd 不是语义输入**：`vdRen=F` 是真开关；`isDependOldVd` 只是 dispatch/issue 的 `ignoreOldVd` 优化，不是"是否真读旧 vd"的总开关。

### 3.4 外部互证（三处语义裁决）

> 目的：把 §3.1 的三处本项目裁决（结果位宽与 lane 选择、`sext32` 写回与高 96 位清零、恒清零与 `vta`/`vma`/tail 无关）从"本项目声明"升级为"外部一手引文 + 同一学校的两份声明（其一为跟帖确认，非独立多方）"可核。判定词只有四个：**支撑**（外部一手规范字面支持该裁决）、**相容**（不与规范冲突，但规范未规定）、**无外部依据**（纯项目裁决或算术推导）、**偏离基线**（外部规范字面相反，属「无外部依据」的强形式，答辩须显式声明偏离理由）。
> 引文来源：三个 fenced 块逐字取自 2026-11-06 的实际下载与 `grep` 记录；上游一手文件为 `riscv/riscv-isa-manual` main @ `a5d2296` 的 `src/unpriv/vector-common.adoc`。

#### 3.4.1 锚点 A｜RVV 归约的 `vl=0`：`norm:vreduction_vl_0`

【逐字引文｜`src/unpriv/vector-common.adoc:3936-3937`】

```asciidoc
[#norm:vreduction_vl_0]#If csr:vl[]=0, no operation is performed and the destination register is
not updated.#
```

- main 稳定 URL：`https://github.com/riscv/riscv-isa-manual/blob/main/src/unpriv/vector-common.adoc#L3936`（行号随 main 漂移，锚点名 `norm:vreduction_vl_0` 稳定）。
- 判定：**偏离基线**（外部规范字面相反，属「无外部依据」的强形式，不是支撑）。该锚点属 `Vector Reduction Operations` 一节，规定 `vl=0` 时 no operation、目的寄存器不更新；§1.1 的裁决正相反（`vl` 任意值含 0 都算 lane 0–7 并全写 `vd`）。答辩写"偏离并说明理由"，不得写"与 RVV 归约一致"。
- 方向支撑面：`vl` 不参与写回判断这一点，由官方伪代码 `for i in range(8)` 无条件循环给出方向（`docx/02-赛题与评分细则.md:24-33`）；它不构成 RVV 标准语义。

#### 3.4.2 锚点 B｜寄存器组重叠：`norm:vreg_overlap_rsv`

【逐字引文｜`src/unpriv/vector-common.adoc:1037-1038`】

```asciidoc
[[norm:vreg_overlap_rsv]]
Any instruction encoding that violates the overlap constraints is reserved.
```

- main 稳定 URL：`https://github.com/riscv/riscv-isa-manual/blob/main/src/unpriv/vector-common.adoc#L1037`
- 判定：**支撑**（仅限"`vd==vs1/vs2` 重叠是合法场景"这一条）。它引用的约束正文是 `norm:vreg_overlap_legal`（`:1013-1028`）：同 EEW 可重叠；目的 EEW 大于源 EEW 时"最高编号寄存器相同"可重叠。LMUL=1 下 `vd==vs` 落在其中之一，`vd!=vs` 属不重叠、不触发约束 ⇒ §3.3 第 2 条的重叠用例是合法场景，不是 reserved 场景。
- 边界：该锚点只规定**合法性**，字面不含"写后读"；"源在写回前读取"属单指令基本语义，判 **相容**，不得引 ISA manual 当逐字支撑。

#### 3.4.3 锚点 C｜归约的 tail 策略：`norm:vreduction_tail_policy`

【逐字引文｜`src/unpriv/vector-common.adoc:3932-3934`】

```asciidoc
  [#norm:vreduction_tail_policy]#The other elements in the destination vector register (0 < index <
  VLEN/SEW) are considered the tail and are managed with the current
  tail agnostic/undisturbed policy.#
```

> 缩进口径：上面三行的两空格缩进是**照抄 2026-11-06 下载原文的块**（该块在原文里嵌在列表项内）；上游 `vector-common.adoc:3932-3934` 本身无缩进，文字逐字相同。

- main 稳定 URL：`https://github.com/riscv/riscv-isa-manual/blob/main/src/unpriv/vector-common.adoc#L3932`
- 判定：**偏离基线**（字面冲突；靠「自定义编码全写指令」声明站住）。字面上，归约的 tail 跟随当前 tail agnostic/undisturbed 策略（即随 `vta` 变），与 §1.1「恒清零、与 `vta`/`vma`/tail 无关」相反；同伴 `norm:vmask_agn_op`（`:1063-1066`，锚点 `#The ... csr:vtype[]#` 的起止）对 masked-off 元素同样跟随 `vma`。站得住的理由只有两条：①本指令是**自定义编码的全写指令**，不属标准归约，通用 tail/mask 合并策略不适用；②官方伪代码 `vd[1..VLEN-1] = 0` 无条件清零（`docx/02-赛题与评分细则.md:24-33`）。**禁止**写成"RVV 标准允许与 `vta`/`vma` 无关"。

#### 3.4.4 外部公开材料的三处同向声明（非官方确认；非独立多方）

> 标注要求：本节全部是**外部公开材料的公开声明**。截至 2026-11-06 官方未答复：issue #126 `state=open`、`comments=1`，那 1 条评论也来自同一来源。故这些原文**不构成规范依据**，只作"同一学校的两份声明（其一为跟帖确认），非独立多方"的旁证。引文块一律原样粘贴（保留原缩进与列表符号），用于机械比对。

**来源 1｜issue #126 正文（外部公开材料；`2026-10-24T05:55:46Z`）——覆盖 ①②③**

以下三段**不连续**（分别在该 issue 正文的第 32、33、28 行），各自逐字粘贴、不拼句：

【逐字引文｜正文 `:32`，覆盖 ①】

```text
   八对 signed INT8 的精确和范围为 [-130048, 131072]，至少需要19位有符号数，不能放入一个8位元素。
```

【逐字引文｜正文 `:33`，覆盖 ②】

```text
   当前将精确和符号扩展至32位，写入 `vd[31:0]`，并令 `vd[127:32]=0`；例如结果 -4 写为 `0x00000000_00000000_00000000_fffffffc`。
```

【逐字引文｜正文 `:28`，覆盖 ③】

```text
   当前先检查合法性，再处理 vl=0，最后计算：合法非零 vl 时按结果布局覆盖整个 vd，不受 vta/vma 影响；合法 vl=0 保留整个旧 vd；非法情况不更新 vd。
```

**来源 2｜issue #126 评论（另一份外部公开材料；`2026-11-05T05:19:34Z`）——覆盖 ①（低 64 位）与 ②**

```text
- 仅取两源的低 8 对 signed int8，初值为 0，不累加旧 vd，高 64 位源数据不参与。
- 精确和写入 vd[31:0]，vd[127:32] 清零；负数仅低 32 位采用补码。
```

**来源 3｜外部公开仓库 `specs/vdot-v0.1.json`（main @ `59dd91a`）——覆盖 ①②**

```json
    "accumulate_old_vd": false,
    "exact_sum_range": [
      -130048,
      131072
    ],
    "minimum_signed_accumulator_bits": 19,
    "result_bits": 32,
    "result_position": [
      31,
      0
    ],
    "zero_bits": [
      127,
      32
    ],
    "lane_mapping": "source element i = signed_int8((old_v[vs] >> (8*i)) & 0xff)",
```

**来源 3（续）｜同文件 `:110`——覆盖 ③**

```json
    "vta_vma": "both flag values accepted; custom whole-result policy overrides generic destination merging on nonzero-vl success",
```

- issue #126 稳定 URL：`https://github.com/OpenXiangShan/XiangShanLab/issues/126`（评论锚点 `#issuecomment-6650400501`）。
- 外部公开仓库稳定引用：`specs/vdot-v0.1.json` @ `59dd91ab94f4dda3e6d597676ed3350ad5987a29`（URL 从略）。
- **差异必须同时写**：该外部公开仓库对 `vl` 的裁决与本项目**不同**（其 `valid_vl_values` 为 0 与 8..16，`vl` 1–7 判非法，`vl=0` 保留旧 `vd`，见其 `vl_zero`/`vl_8_to_16` 字段）。故"互证"只覆盖 ①②③ 三处，**不覆盖 `vl` 口径**；本项目按 §1.1（`vl` 任意值全写）与之不同，答辩须主动区分。

#### 3.4.5 三处裁决的判定汇总

| # | 裁决（正文锚点） | 一手外部锚点 | 判定 | 外部声明互证（同校两份，非独立多方） |
|---|---|---|---|---|
| ① | **内部 19 位有符号 + 取低 64 位 lane 0–7**（§1.1、§1.4） | **调查范围**（RVV 批准手册 + `vqdot`/`SDOT`/`VPDPBUSD`/`TDPBSSD` 四份一手文件）内无规范使用 19 位；外部例子全是 32 位累加器（`vqdot`/`SDOT`/`VPDPBUSD`/`TDPBSSD`）。19 位来自算术：`8×(−128)×(−128)=131072 > 2^17−1=131071` | **无外部依据**（算术推导）；与外部 32 位容器惯例**相容** | issue #126 正文与外部规格文件 `minimum_signed_accumulator_bits=19`；该 issue 评论与同一规格文件 `source_element_indices=[0, 7]`（低 64 位、高 64 位不参与） |
| ② | **`vd[31:0]=sext32(S)`、`vd[127:32]=0`；取低 8 对 int8**（§1.1、§1.2） | `norm:vreg_overlap_rsv`（§3.4.2）支撑 `vd==vs` 用例合法；32 位容器与 `vqdot`（**未批准提案**）的 "widening (with sign-extension) to 32 bits"（`riscv-dot-product` `insns/vqdot.adoc:37-48`）同一惯例，`SDOT`/`VPDPBUSD` 属**厂商 ISA**；"对最终和再 `sext32`"外部未逐字写 | **相容**（32 位容器属**惯例/提案，非规范字面支撑**；"再 `sext32` 一步"同为**相容**）；`vd==vs` 重叠合法性另由 `norm:vreg_overlap_rsv` 判**支撑**（仅限该条，不支撑容器位宽） | issue #126 正文与评论、外部规格文件 `result_bits=32`/`result_position=[31, 0]`/`zero_bits=[127, 32]` 逐值相同（同一学校的两份声明，其一为跟帖确认，非独立多方） |
| ③ | **恒清零与 `vta`/`vma`/tail 无关**（§1.1、§3.1） | `norm:vreduction_tail_policy`（§3.4.3）字面相反；`norm:vmask_agn_op`（`:1063-1066`）同理；官方伪代码无条件清零只给方向 | **偏离基线**（字面冲突；靠"自定义编码全写指令"声明） | issue #126 正文"不受 vta/vma 影响"；外部规格文件 `vta_vma` 字段"custom whole-result policy overrides generic destination merging"（同一学校的两份声明，其一为跟帖确认，非独立多方） |

> **判定上限（不许升级）**：三处里没有一处拿到"外部一手规范逐字规定"的**支撑**，例外只有 ② 里的 `vd==vs` 重叠合法性（`norm:vreg_overlap_rsv`，仅支撑该条用例合法，不支撑 32 位容器或清零语义）；32 位容器属惯例/提案（`vqdot` 未批准、`SDOT`/`VPDPBUSD` 厂商 ISA），只能判**相容**；③ 字面冲突，判**偏离基线**。"外部声明互证"全部是【外部公开声明】且只有同一学校的两份（其一为跟帖确认），不得改写成"行业标准"、"官方确认"或"独立多方"。

---

## 4. 证据附录（精选证据）

> 本节只收录与 SPEC 直接相关的原文摘录（`文件:行`）。

### A-1｜K=8 与 K=16 的官方材料差异

```
- K 值：伪代码 **8** vs 宣讲 **16**；
- 传播方式：伪代码"逐个乘积相加"（K=8，一个标量和）vs 宣讲"16 个 32 位中间乘积再累加"（K=16）；
- 清零粒度：伪代码 `vd[1..VLEN-1]`（byte 下标，127 个字节）vs 宣讲 `vd[1..15]`（**元素**下标）；
- 指令名：`vdot.vv` vs `vdot.w`；
```

### A-2｜Mgu 的 tail/agnostic 永不为 0

```
`byte1s = (~0.U(8.W))`（:83）⇒ **tail/mask 未激活的字节保留旧 vd；agnostic 字节写全 1，不是 0**。【实测】
- `:131`：`io.out.illegal := false.B` ⇒ Mgu 不会产生非法指令。【实测】
```

### A-3｜香山 OPMVV / NEMU vopmvv 的双侧空闲 funct6

```
== OPMVV funct3=010 == Shan 50 / NEMU 50
   both-free: 001100 001101 001110 001111 010001 010011 010101 010110
              101000 101010 101100 101110 111001 111110
   Shan-free/NEMU-used: -
   NEMU-free/Shan-used: -
```

### A-4｜Zvdot4a 占用 `101100/010`

```
vdot4a.vv         31..26=0x2c vm vs2 vs1 14..12=0x2 vd 6..0=0x57
- `0x2c = 0b101100`，`funct3 = 0x2 = 0b010`，`opcode = 0x57`。
> **结论纠偏**：`101100/010` 已被 Zvdot4a 占用（unratified）；用它实现语义不同的指令等于冒用官方分配。
```

### A-5｜禁用清单的实测锚点

```
- 111111/010 → VWMACCSU_VV（香山 Instructions.scala:819；NEMU decode.h vwmaccsu）
- 101100/000 → VNSRL_WV（香山 :706；NEMU decode.h:201）
- 101100/001 → vfmacc（NEMU decode.h:450，落在 OPFVV 表）
- 101101/010 → VMACC_VV（rocket-chip Instructions.scala:609）
```

### A-6｜funct6/funct3 会共槽，需按 25 位 BitPat 检查

```
- **funct6/funct3 粒度会“共槽”**：例如 `VFCVT_*` 共享 `funct6=010010,funct3=001`，靠 rs1/rs2 区分；`VCPOP_M`/`VFIRST_M`/`VMV_X_S` 共享 `010000/010`。所以“某 funct6 是否空闲”只是第一层筛选，**最终必须按完整 25 位 BitPat 做重叠检查**。
```

### A-7｜一份外部公开实现的口径为作者声明

```
其 README :88-89 声明“低 64 bit 8 个 int8 → vd[31:0]，vd[127:32] 清零；内部 20 bit、输出 32 bit”【作者声明】，但“香山集成”明确标注**未执行**。
```

---

## 5. 完成判据（可执行）

1. `python3 design/verify/vdot_model_test.py` 通过，且机器码示例（`vdot.vv v3, v2, v1` → `0x3A20A1D7`）与模型一致；**金模型三条变异（`WRITE_MASK→32`、`Cat(96'h1,…)`、删 `vill`）必须被判失败**，任一未被判失败即判模型无效。
2. `python3 design/verify/encoding-gate.py` 退出码 0（阳性对照必命中）；`grep -n "0011101??????????010?????1010111"` 在 BitPat 定义处命中；`grep -n "001110 1 "` 在 NEMU `decode.h` 表项命中。
3. §3.2 的非法/边界用例在 difftest 中 0 次 ABORT（不是"mismatch 率"表述）；LMUL=1 合法 / LMUL=2/4/8 非法三例必过。
4. 改任何语义/编码前，先核对本文 §1.1 与 §2.7 的前置条件；本文档集与其他材料冲突时以本文档集为准。
