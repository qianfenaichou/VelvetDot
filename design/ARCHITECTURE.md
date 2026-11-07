# vdot.vv 微架构设计（ARCHITECTURE）

> 文档地位：**本文档集（SPEC/ARCHITECTURE/ALGORITHM）为设计与实现的依据，与其他材料冲突时以本文档集为准**。本文只陈述现行设计，不叙述纠错史。
> 适用：**动 RTL、改 `VIMacU`/`VIMac64b` 端口、做译码集成、评估 2 拍时序、准备"复用香山现有向量实现"论证**时必读。
> 关联文档：语义与编码见 `design/SPEC.md`；算法内核与验证见 `design/ALGORITHM.md`。
> 证据附录：§10 为精选证据（≤80 行，逐条给出 `文件:行`）。

---

## 0. 一句话架构

不另造乘法阵列：`VIMac64b` 在 SEW=8 下已经算出 8 个完整 16 位积（`sum_wo`），vdot 只缺"跨 lane 水平归约"。X15 从 `VIMac64b` **一次导出三信号**：`sum_wo`（128 位）、`walOut`（128 位）、`fireS1`（`Output(Bool())`，`:33` 的 `GatedValidRegNext(fire)`）；主线挂 **tap0 接法**：`sum_wo` → `sext19` → 仓内 `CSA_Nto2With3to2MainPipeline(n=8, width=19, pipeLevel=0)` 的 **4:2 树（8→4→2，2 段 3 实例）** → 19 位 CPA → `RegEnable(reduction, io.fireS1)`（与 `walOut` 同拍）→ `Cat(96'b0, sext32(S))`；wrapper 用输出 Mux 旁路 Mgu。目标 2 拍（预算见 §3.1，**待综合验证**；3:2 树为等价备选）。C 支线（引 `walOut` 落 S3 组合拍）只作 E-2 预登记实验，见 §2.2。

---

## 1. 战略与路线

### 1.1 路线 = 方案 C 的结构（A 主线 + 文档路线图扩展）

- 主线按官方伪代码 K=8 单结果语义，先冻结证据；扩展（vdot4a 多结果 / K=16 / 参数化）**全部降级为文档路线图**：只做编码、位宽、接口预留的设计说明，**不写扩展 RTL**。主线三阶段证据冻结前不开写扩展。
- 主线独立可交付，扩展只上行不下行。
- 若距**官方报名/材料提交截止 2026-11-08 23:59:59**（`docx/01-官方通知与规则.md:32`、`docx/README.md:23`）不足 5 天且主线未绿，扩展全部裁剪，直接交 A；内部计划日（D+0=2026-10-28）滑期不算官方逾期。

### 1.2 微架构 = 复用香山 VIMac 路径的 A1 方案

- 不另造乘法阵列：`VIMac64b` 在 SEW=8 下已经算出 8 个完整 16 位积（`sum_wo`），vdot 只缺"跨 lane 水平归约"。
- 挂 8→1 归约：4:2 压缩树（8→4→2，2 段 3 实例）+ 19 位 CPA，用 X15 导出的 `io.fireS1` 寄存（与 `walOut` 同拍），目标 2 拍（待综合验证）。
- 直接命中评分细则"复用香山现有向量实现"的字面要求，面积增量小（估算，待综合）。

---

## 2. A1 数据通路

### 2.1 数据通路图

```
vs1[63:0], vs2[63:0]
  → VIMac64b（isMacc=false → partProd(33)=0，旧 vd 项为 0）
  → 第二级组合信号 sum_wo：8 × 16 位有符号积（VIMac64b.scala:185-201），由 X15 导出为 Output(Vec(8, UInt(16.W)))
  → 树输入先把每个 16 位积 sext19（严禁零扩展）
  → 新增 8→1 归约（tap0 主线）：CSA_Nto2With3to2MainPipeline(n=8, width=19, pipeLevel=0) 的 4:2 树（8→4→2，2 段 3 实例）
  → 19 位 CPA → RegEnable(reduction, io.fireS1)；fireS1 由 X15 显式导出（VIMac64b.scala:33 的 GatedValidRegNext(fire)），与 walOut（:208）同一拍 ★主线取 tap0（树在第二拍组合内、结果寄存）；C 支线（引 walOut 落 S3 组合拍）只作 E-2 实验，见 §2.2
  → Cat(96'b0, sext32(S)) → wrapper 输出 Mux(outIsVdot, vdotVd, mgu.io.out.vd) 旁路 Mgu；outIsVdot 取 outCtrl.fuOpType（见 X8）
```

### 2.2 关键点

1. **主线引 `sum_wo`（tap0），不引 `walOut`**：`walOut` 是 `sum_wo` 的寄存版本（`VIMac64b.scala:207-208`）。**「引 `walOut` = 第 3 拍」不成立**：`walOut` 与 `io.out.valid` 同在 t+2，引它**不增加 latency**，只是把归约放进 S3（格式化+Mgu）组合拍、增加 S3 深度。主线仍取 tap0（树在 S2 组合内、结果用 `fireS1` 寄存），改动面最小且不碰共享拍级；C 支线（`walOut`→S3 归约）作 **E-2 预登记实验**，仅当实测 S3 深度比值 ≤1.5 且 S2 比值 >1.5 时才升级为默认（裁决 D02）。
2. **旧 vd 项为 0**：`isMacc=false` 使 `partProd(33)=0`；vdot 不进 `isMacc`（`VimacOpcode.isMacc` 只含 vmacc/vnmsac/vmadd/vnmsub）。
3. **入树语义写死**：`S = Σ_{i=0..7} sext19(sum_wo[i])`；每个积符号扩展到 19 位再入树，**严禁零扩展**（零扩展在 n 个负 lane 时产生 `n×2^16` 偏差，模 2^19）。
4. **19 位 CPA**：内部归约树位宽必须参数化到 19 位。
5. **清零在数据模块输出端完成**：不依赖 Mgu；禁止用 `vta=1` 代替清零（得到的是 `0xFF` 不是 0）。
6. **wrapper 输出 Mux**：`Mux(outIsVdot, vdotVd, mgu.io.out.vd)`，vdot 时完全旁路 Mgu。
7. **fireS1 约束**：X15 在 `VIMac64b` 端口表显式导出 `val fireS1 = Output(Bool())`（值 = `:33` 的 `GatedValidRegNext(fire)`），并与 `sum_wo`（`:187`）同一次端口改动导出；X-new 用 `RegEnable(reduction, io.fireS1)`，与 `walOut`（`:208`）同拍。wrapper 只做端口连接（`vimacs(0).io.fireS1`），禁止用 `io.in.valid` / `GatedValidRegNext(valid)` / `RegNext(valid)` 重建；`VIMacU.scala:101` 的 `mod.io.fire := io.in.valid` 是 `VIMac64b` 的输入 fire，保持不变。

### 2.3 A2 退路（仅功能退路）

新建独立 64 位点积模块（8×8 有符号乘法阵列 + CSA + 19 位 CPA，接口照 `VIMac64b.scala:11-29`），不侵入 `VIMac64b`。

- wrapper/译码/NEMU/测试与 A1 完全共用，切换只换数据模块。
- A2 是 **`VIMac64b` 端口改动（X15）导致 vmac 回归失败**时的功能退路；它同在 `VIMacU`、同一拍级，**不是时序退路**（时序退路见 §3.2）。
- A2 若自建 2 级流水，其第二级使能同样必须复刻 `GatedValidRegNext(fire)` 语义（对应 A1 的 `io.fireS1`），禁止用 `io.in.valid` 或自行猜测 `valid`。

### 2.4 乘法

- 复用 `VIMac64b` 的 **Booth radix-4**（3 位重叠窗）+ Wallace。
- **不是 radix-2 / Booth-2**；文档统一术语，避免答辩口径分歧。
- 若走 A2 自建亦用 radix-4（34 vs 67 加数、7 vs 9 级压缩）。
- 算法细节与证据见 `design/ALGORITHM.md` §1.1。

### 2.5 归约树与 Mgu 旁路

- **8→1 归约（默认 4:2，备选 3:2）**：仓内 `CSA_Nto2With3to2MainPipeline(n=8, width=19, pipeLevel=0)` 的 4:2 树 = 8→4→2，**2 段 / 8 级全加器 / 3 个实例 / 模型门计数 684**；3:2 树（备选）= 8→6→4→3→2，**4 段 / 12 级 / 6 实例 / 798 门**。**FA 等效持平（6 vs 6）**，4:2 在段数与门数上不劣（−14% 模型门计数）；相对第二拍总量收益有限，故作**叠加项**而非唯一退路。以上段数/门数是按源码布尔式的**模型计数、未综合**。末级 19 位 CPA 用普通 `+`（不引入新前缀加法器）。
- **位宽**：香山现有归约（`Reduction.scala`）是窄归约会回绕，拓扑可参考（`Reduction.scala:455-490`）但不能照抄；vdot 的归约树必须重新参数化到 19 位。
- **Mgu 旁路（唯一实现，不再二选一）**：Mgu 的 tail 保留旧 vd、agnostic 写 `0xFF`（`Mgu.scala:83,90-92`），永远不会给出 0。因此"其余通道清零"不能由 Mgu 完成，必须在数据模块输出端 `Cat(96'b0, sext32(S))`，并在 wrapper 输出 Mux 中旁路 Mgu。**"覆盖 Mgu 输入"方案已被否决**：vl<8 或 vta=0 时 Mgu 仍会回带旧 vd 或 0xFF，无法满足 vd[127:32]=0 的语义要求。wrapper 只做 `Mux(outIsVdot, vdotVd, mgu.io.out.vd)`，不改 Mgu 模块。

---

## 3. 流水与时序

### 3.1 2 拍对齐与预算

- 2 拍对齐 `VimacCfg.latency = CertainLatency(2)`（`FuConfig.scala:563`）。
- `VIMac64b` 正好两级：`fireS1 = GatedValidRegNext(fire)`（`:33`），`walOut := RegEnable(..., fireS1)`（`:208`）；`FuncUnit.scala:213` 用 `preLat = latency - latdiff` 建流水。
- 新数据模块若只有 1 级或 3 级，写回数据会错位；A1 的归约树必须挂在第二级组合逻辑内。

**第二拍预算（显式核算，待综合验证）**

| 第二拍内容 | 说明 |
|---|---|
| Wallace 末 3 级（既有 retiming） | `VIMac64b.scala:165-168` |
| 8 个 16 位 CPA（既有） | `VIMac64b.scala:185-201` |
| 4:2 归约（新增，2 段 3 实例） | 输入先 sext19；FA 等效 6 级 |
| 19 位 CPA + 符号扩展（新增） | 输出 `sext32(S)` |

> 结论：2 拍是**设计目标**；是否收敛以综合/STA 结果为准，本表所有数字均待测。**测量前置**：E-1 先测 S3 基线（格式化+Mgu 现有深度），E-0 三探针（tap0/tap2/C 支线）再测新增段；`ltp` 级数只作相对量、不换算 ps（裁决 D03）。

### 3.2 时序不收敛的退路链（严禁跳步）

**严禁直接改共享的 `VimacCfg`——会让所有 vimac 指令一起变慢。** 退路按顺序（**缺省判定日，裁决 D03**）：

1. **首选 2 拍 tap0**：`sum_wo` + 4:2 树，用 X15 导出的 `io.fireS1` 与 `walOut` 同拍寄存；预算见 §3.1，**待综合验证**。
2. **缺省判定日**：**2026-11-04 24:00 前** E-0/E-2 实测与 vmac 回归未齐 ⇒ **锁定 tap0**，2 拍只写"设计目标/预算内候选"，**不自动升 3 拍、不启 X16**。
3. **有外部证据才启 3 拍**（改动位置 X16）：仅由 STA/liberty 负 slack 或 emu 实测反压触发；**不接受合成触发条件**（如 `min(Δ)>40`，与"tap2 上界=基线"矛盾、不可达）。启用时须新建 `FuType.vdot` + 3 拍 `VdotCfg` + `Parameters.scala:449` 登记 + `VecExceptionGen.isVArith` 覆盖 + `allConfigs`/`ExeUnitParams` + 唤醒/旁路复核。**影响面**：FuType 是 one-hot 枚举（`FuType.scala:11`），新增类型让所有承载 `fuType` 的 Bundle 加宽；**不是"只加一行"**，但比改共享 `VimacCfg` 可控。
4. **A2 独立模块只是功能退路**：仅当 X15 端口改动导致 vmac 回归失败时启用；A2 与 A1 同在 `VIMacU`、同一拍级，不改善时序。

### 3.3 拓扑参考

Wallace 末 3 级放第二拍的 retiming 香山自己在用（`VIMac64b.scala:165-168`）；vdot 的归约树可沿用同一风格切分。

---

## 4. 改动位置清单（改动面 8+3）

### 4.0 编号说明

- X 系列编号沿用源码勘察记录；本表给出 **X1–X15 共 15 个编号位置 + X-new**，其中 8 个改动、其余明确不改或只做旁路。
- N 系列为 NEMU 三处必改点。
- 表中"文件:行"是源码定位锚点；新代码没有既有行号时，给出最近的锚点与勘察记录出处。

### 4.1 RTL 改动位置（8 项）

| # | 改动位置（文件:行） | 改动 | 备注/证据 |
|---|---|---|---|
| X1 | `rocket-chip/.../Instructions.scala`（锚点 `:407` VADD_VV、`:819` VWMACCSU_VV） | 新增 `VDOT_VV = BitPat("b0011101??????????010?????1010111")` | **vm 位固定 1**；funct6=`001110`（C-enc1b，Zvbc 复核后）；vm=0 不命中 vdot，走非法。同位格式参考 `:407`。证据 `stage2/2.1-design/encoding-gate-zvbc-2026-10-31.md` |
| X2 | `decode/VecDecoder.scala` OPMVV 表（`:370-442`） | `VDOT_VV -> OPMVV(F, FuType.vimac, VimacType.vdot, F, T, F, UopSplitType.VEC_VVV)` | **vdRen=F**（不读旧 vd）；当前无 `OPMVV(F` 先例（grep 计数 0），`src3=X` 路径需专门验证——风险项。`OPMVV` 定义 `:80-95`，`src3` `:91` |
| X6 | `yunsuan/package.scala` VimacType（对象 `:364`，defs `:382-399`，布局注释 `:381`） | `def vdot = LiteralCat(0.U(2.W), INT.S, INT.S, INT.X, FMT.VVV, VimacOpcode.vdot)` | **9 位值 `0x067`**（`00_110_0_111`）：vd_old 位取 `INT.X`（不读旧 vd，与 `vmul`/`vsmul` 同款，`package.scala:384,397`）；`dummy = BitPat.Y(OpTypeWidth)` 是**全 1 模式 `0x1FF`**（不是 don't-care），二者不相等。查重时同时核对 `0x067` 与 `0x077` |
| X7 | `yunsuan/.../VimacOpcode.scala`（width `:6`，000–110 `:7-13`，isMacc `:17`） | `def vdot = "b111".U(3.W)` | 3 位空间最后一格；**不进 isMacc** |
| X8 | `fu/wrapper/VIMacU.scala`（class `:45`，2×VIMac64b `:64`，Mgu `:65`，拼接 `:126`，Mgu 输入 `:131-147`，输出 `:148-150`） | 例化 X-new（只取 `vimacs(0)` 的 `sum_wo` 与 `fireS1`）+ 输出 Mux 旁路 Mgu：`res.data := Mux(outIsVdot, vdotVd, mgu.io.out.vd)`，**`outIsVdot` 取 `outCtrl.fuOpType`**（不得取输入级 `inCtrl.fuOpType`，否则背靠背混合流串指令）；Mux 后加 `assert(PopCount(res.data(VLEN-1,32)) === 0)` | 端口改动单独 commit + vmac 回归（见 §5.3）；`VecPipedFuncUnit.scala:68` `outCtrl = ctrlVec.last` |
| X-new | `yunsuan/.../vectorIMAC/`（新增模块） | **tap0 接法**：8→1 归约（`CSA_Nto2With3to2MainPipeline(8,19,pipeLevel=0)` 4:2 树）+ 19 位 CPA + 格式化；接口 = `Input(Vec(8, UInt(16.W))) sum_wo` + `Input(Bool()) fireS1` + 控制位；`RegEnable(reduction, io.fireS1)`；输出 `Cat(96'b0, sext32(S))` | 或 A2 整模块；接口不照 `VIMac64b.scala:11-29` 的全量 MAC 端口（见 §5.3）；3:2 树为等价备选 |
| X14 | `DecodeUnit.scala` / `VecExceptionGen.scala`（`VecExceptionGen:57-58,175,275,294`；`DecodeUnitComp:173,198`） | **谓词唯一写法**：`isVdot && (SEW =/= 0.U \|\| LMUL =/= 4.U)` → 非法（`SEW`/`LMUL` 定义见 `:57-58`：`vsew=0`↔SEW=8、`vlmul=000`→`LMUL=4`↔LMUL=1）；另 `vill=1`（`:178`）、`mstatus.VS=OFF`（`DecodeUnit.scala:908`）、`vstart≠0`（`:275`）各为独立非法项。**禁止写 `vlmul === "b001"`**（那是 LMUL=2） | `Mgu.illegal` 恒 false（`Mgu.scala:131`），判定必须在译码层；必测 LMUL=1 合法 / LMUL=2/4/8 非法 |
| X15 | `yunsuan/.../VIMac64b.scala`（端口表 `:11-30`；内部 `sum_wo` `:187`；`fireS1` `:33`；`walOut` 寄存 `:208`） | **一次导出三信号**：`Output(Vec(8, UInt(16.W))) sum_wo`（`:187`）+ `Output(UInt(128.W)) walOut`（`:208`）+ `Output(Bool()) fireS1`（`:33` 的 `GatedValidRegNext(fire)`），**同一 commit 一次导完，禁止第二次改共享模块**（tap0 用 `sum_wo`+`fireS1`；C 支线用 `walOut`，切换只改 wrapper） | **单独 commit + vmac 回归**（vmac 系列 difftest 无新增失败）；回归失败退 A2 |
| X16 | `FuType.scala`、`FuConfig.scala`、`Parameters.scala:449`、`VecExceptionGen.scala`（`isVArith`）——**仅在 2 拍时序不收敛时启用** | 新建 `FuType.vdot` + 3 拍 `VdotCfg` + 登记 + 非法判定覆盖；X-new 的 `RegEnable` 从 `io.fireS1` 改为独立使能 | **条件改动**：2 拍综合/STA 通过则不启用；启用时须复核 issue/wakeup 路径和 Bundle 宽度变更（`FuType.width = num`） |

### 4.2 NEMU 改动位置（3 项）

| # | 改动位置（文件:行） | 改动 | 备注/证据 |
|---|---|---|---|
| N1 | NEMU `rvv/decode.h` vopmvv 表（`:314-373`，`return` `:371`） | `def_INSTR_TAB("001110 1 ????? ????? ??? ????? ????? ??", vdot)` | **vm 位固定 1**；funct6=`001110`（C-enc1b）；完整 32 位 pattern，不写省略号。插在表尾 `return EXEC_ID_inv` 前（`:371` 附近） |
| N2 | NEMU `rvv/vcompute.h`（`def_EHelper(vmacc)` 锚点 `:868-870`） | `def_EHelper(vdot)`；入口检查：`vm=0`、`vsew≠0`、`vlmul≠0`、`vill=1` 任一命中 → 非法指令（API 用 `longjmp_exception(EX_II)`，见 `design/CODING-STD.md` §4.4），vstart 用 `check_vstart_exception(s)` 覆盖；**禁止 `check_vstart_ignore`**（vl=0 时跳过写回，与 SPEC §1.1 冲突） | **不能复用 `ARITH(...)` 宏**（按 vl 循环散布每 lane，语义不对）；手写取 8×int8 → 写 `vd[31:0]` → **手写显式清零其余位**；**禁止 `set_vreg_tail`**（`vreg_impl.c:286` 写 `0xFF` 不是 0）。NEMU `vlmul=0` ↔ LMUL=1（`vreg_impl.c:82-105`） |
| N3 | NEMU `include/isa-all-instr.h`（`VECTOR_INSTR_TERNARY(f)` `:157-204`，`f(vmacc)` `:177`） | `VECTOR_INSTR_TERNARY(f)` 加 `f(vdot)` | **必改点**：不加则 `EXEC_ID_vdot` 不存在、编译不过 |

### 4.3 不改清单（X 系列其余编号）

| # | 编号 | 现状/锚点 | 为什么不改 |
|---|---|---|---|
| X3 | `FuType.scala` | `:127` `vecOPI = Seq(vipu, vialuF, vppu, vimac, vidiv)` | 复用 vimac，FuType 不改 |
| X4 | `FuConfig.scala` `VimacCfg` | `:551-568`，latency `:563`，5 源 `:556`，destDataBits `:566` | VimacCfg 整体复用；时序退路时才新建 VdotCfg |
| X5 | `allConfigs` / FU 登记 | `allConfigs` `:843-848`；真正登记点 `Parameters.scala:449` | 复用 vimac 时两处都不动；新建 FU 才改 `Parameters.scala:449` |
| X9 | `fu/vector/VIMacU.scala` | 全文 75 行均为注释（死代码） | 改了无效；活文件是 `fu/wrapper/VIMacU.scala` |
| X10 | `DecodeUnit.scala` `vmaInsts` | `:976-979`（14 条） | vdot 不登记（见 §6） |
| X11 | `DecodeUnit.scala` `isWritePartVd` | `:1062` | 用 `VEC_VVV` ⇒ false；不影响全写语义 |
| X12 | `Mgu.scala` | class `:34`；输出逻辑 `:83,89-94`；illegal `:131` | 不改模块；在 wrapper 输出端旁路 |
| X13 | `UopSplitType` | `package.scala:768/771`，`VEC_VVV = "b010010"` | 不改；vdot 用 `VEC_VVV` |

> 说明：本表是编号与"不改"状态的定位表，依据上游源码锚点；不含新的设计改动。X5 的"真正登记点"来自源码勘察记录，用于防止把 `allConfigs` 误当登记点；复用 vimac 时 FuConfig 整体复用。

---

## 5. 集成规程

### 5.1 版本锁定

| 仓 | 版本 | 复核要求 |
|---|---|---|
| XiangShan | `kunminghu-v2` @ `a4eeaab` | 以上游源码实测复核为准 |
| yunsuan | `9559211` | 同上 |
| NEMU | `a683e0b` | 同上 |

**双副本约束**：只改 `repos/XiangShan/yunsuan/`（@ `9559211`，2 级 `fire/fireS1`）；`repos/YunSuan/`（@ `267ff7`，kunminghu-v3，3 级流水）**禁止参照**。集成 runbook 的 preflight 必须：

```sh
test "$(git -C repos/XiangShan/yunsuan rev-parse --short HEAD)" = 9559211
diff -q repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VIMac64b.scala \
        repos/YunSuan/src/main/scala/yunsuan/vector/vectorIMAC/VIMac64b.scala   # 预期：文件不同
```

第一条断言失败即停止；第二条用于确认没有误改到另一副本。

### 5.2 变更约定

- 每次工作：按本文档集与 `design/SPEC.md` 的指引取最小必读集；禁止漫游式阅读。
- 任务循环：spec 小节 → 实现（最小改动面）→ 校验（difftest / 金模型）→ 记录滚动更新。
- 一次一 commit（message 带改动编号 + 验证命令）、先 grep 后改、禁改死代码、每处改动后跑对应回归。
- 改动位置表之外不动；改后执行校验。

### 5.3 X15（`VIMac64b` 端口）改动的专门约束（风险 R5）

- `sum_wo`/`walOut`/`fireS1` 都是 `VIMac64b` 内部信号（`:187`/`:208`/`:33`），不在 `:11-30` 端口表；X15 **一次端口改动导出三信号**（见 §4.1 X15），**单独 commit** + vmac 回归。
- **使能约束（替代旧条款）**：旧"禁止 `GatedValidRegNext(valid)`/`RegNext(valid)`"不可判别（对 Bool 二者等价），废除。改为：X-new 寄存使能**必须来自 X15 端口线本身**，机械判据 = `grep -c 'vimacs(0).io.fireS1' VIMacU.scala` 恰为 1 且该行是端口连接；**禁止 wrapper 内本地重建**（含 `io.in.valid`、`RegNext(...)`、`GatedValidRegNext(...)`）。
- **反压约束**：`VIMacU` 加 `assert(!io.out.valid || io.out.ready)`（仿真零开销，首次 emu 即判）；**仅当断言失败时才允许**把 `mod.io.fire := io.in.valid`（`VIMacU.scala:101`）改为 `valid && ready`，改后必须跑 vmac 回归（裁决 D05）。
- **拍对齐检查**：背靠背 `vdot → vmacc → vdot`（**含 bubble**）用例必须验证写回不与上一条指令串数据（R13）。
- 若端口改动破坏 vmac 回归，退 A2（接口照 `VIMac64b.scala:11-29`）；A2 自建 2 级流水的第二级使能同样须来自端口线，禁止本地重建。
- 不改 `FuType`、`FuConfig`（VimacCfg 整体复用）、`UopSplitType`、`fu/vector/VIMacU.scala`（死文件）。

### 5.4 编译闭环的成对改动

- X1（BitPat）与 X2（译码表项）必须同时存在，否则 `VDOT_VV` 无定义；
- N1（表项）、N2（EHelper）、N3（`f(vdot)` 枚举）必须同时存在，否则 `EXEC_ID_vdot`/`exec_vdot` 不存在、编译不过（见 §4.2 N3）；
- X6/X7（VimacType/VimacOpcode）必须同时存在，否则 `VimacType.vdot` 引用的 opcode 未定义；
- X15（`VIMac64b` 端口，含 `sum_wo` + `fireS1`）与 X8/X-new（归约树/数据模块）必须同时存在，否则 wrapper 无端口可接；
- X14 与 X2 的合法性口径必须一致：译码层判非法，不能依赖 FU 输出。

> 以上是由改动位置直接推出的编译/语义依赖（供任务拆分参考），不是额外的设计决策；提交顺序按任务记录与最小改动面安排。

---

## 6. 不登记 vmaInsts 的设计权衡（答辩素材）

### 6.1 事实链

- `DecodeUnit.scala:1069`：`isDependOldVd := ... || isVma || ...`；`isVma` 由 `vmaInsts`（`:976-978`）驱动。
- `vmaInsts` 只控制 `isDependOldVd` 这一 dispatch/issue 优化；对"全写 + 输出端清零"的实现，不登记并不导致清零错误。
- 我们的 vdot 是全写指令：`vdRen=F` 使 `src3=X` 真不读旧 vd；清零由数据通路 `Cat(96'b0, ...)` 保证。

### 6.2 收益与代价

- **收益**：消除 RAW/WAW 假依赖，连续 vdot 背靠背吞吐目标 1 条/拍（待实测）。
- **代价**：OPMVV 表当前无 `OPMVV(F` 先例（`grep` 计数 0），`src3=X` 路径需专门验证（风险见 §8 R4）。
- **注意措辞**：`isDependOldVd` 只是 dispatch/issue 的 `ignoreOldVd` 优化，不是"是否真读旧 vd"的总开关；真开关是 `vdRen`。

### 6.3 三种语义开关的组合矩阵（源码勘察记录）

| 语义 | vdRen | 进 vmaInsts | 进 isMacc | uopSplit |
|---|---|---|---|---|
| 覆盖写（官方伪代码） | F（或 T 但不用 oldVd） | 否 | 否 | VEC_VVV |
| 累加 old vd | T | 是 | 是（`VimacOpcode.isMacc`） | VEC_VVV |
| 本项目 vdot | **F** | **否** | **否** | **VEC_VVV** |

> 混用（vdRen=F 却进 isMacc）会读到 `src(2)` 的无效数据。

---

## 7. 差异化与创新（答辩素材；事实来自公开材料核对）

> 当前状态：本文档集是**设计包**，不是已完成的交付物；本节陈述"设计差异 + 证据到手后的验收方式"，不表示分数已获得，所有未实测数字一律写"目标/待测"。

### 7.1 四列对照

| 维度 | 我们（设计目标） | Gloria（GEMwhu） | Sun（AsyncSys） | qixuan（qxriscv） |
|---|---|---|---|---|
| 语义口径 | 官方伪代码 K=8 单结果，`vd[31:0]=sext32(S)`、`vd[127:32]=0`；`vstart≠0` 非法；vl/vta/vma 见 SPEC §1.1 | 官方 K=8 语义，`ACCW=19`、`OUTW=32` | Zvdot4a/SiFive 风格多结果，每 32 位元素 4×int8 累加 | 官方 K=8（README 声明）；编码 `funct3=000/OPIVV`、funct6=111111 |
| 微架构形态 | 复用 `VIMac64b` 的 `sum_wo` + 4:2 压缩树（8→4→2，2 段 3 实例）+ 19 位 CPA（§2） | 独立 `VDotU` 新 FU（ExeUnit_13），标准 8 lane 乘法 + CSA 树 | 新增 `VDot64b`，参数化三档精度 | 模块级设计（平台未集成） |
| 香山集成证据 | 目标：XSTop 级 PATH + 全核日志（待测） | `PATH VDotU: XSTop -> ... -> ExeUnit_13` 与 `FULL_SOC_PASS` | VCS 全核 difftest 日志与 `HIT GOOD TRAP` | 香山平台证据为零；阶段一阻塞 |
| 验证方法 | 19 位推导 + 混合符号奇数负 lane 定向用例 + Python/NEMU/RTL 三方对拍 + harness 负向自检 + 回归基线 JSON（§7.2 D-b） | 65 行全 PASS 全核日志（含非法/别名/vl 边界） | 三边界 + 3×100 随机组 | 模块级 1518 例 + 协同 1513 例 |
| 形式验证 | 目标：`vdot_dp` 组合 miter + bug 注入演示（`design/ALGORITHM.md` §3.5） | 公开材料未见 | 公开材料未见 | 公开材料未见 |
| 性能口径 | `L_vdot`（依赖链，主口径）/`T_steady`（稳态吞吐）/`T_kernel`（kernel 周期）三口径（`design/ALGORITHM.md` §3.4） | 252 次全核计时；独立点积 1.045–1.528 cyc/dot、依赖链 2.995× | GEMV 2.82×（README 与 pr_body 数字不一致） | 模块级 `latency_write=3`、`throughput 1 inst/cycle` |
| 文档形态 | 设计文档集 + 机械校验 | 按官方编号 10 份 PDF + 日志 | 文档 + 21 份原始日志 | IPD 五件套 + 13 节设计文档 |
| 许可证/诚信 | 自有代码，不使用他人无许可证代码 | 仓库无 LICENSE | 仓库无 LICENSE；数字前后不一致 | 仓库无 LICENSE |

> "我们"列是设计目标；未实测项不得写成已完成。表中事实以公开材料为准。

### 7.2 三条可审计差异（每条附"证据到手后如何验证"）

**D-a 复用路线（可行性口径）**

- 我们挂 `VIMac64b` 的 `sum_wo`，复用现有 VIMac 功能单元，直接命中评分原文"复用香山现有向量实现"的字面要求。
- Gloria 新建独立 FU（`VDotU`，ExeUnit_13），复用论证弱于我们。
- **证据到手后如何验证**：`git diff` 只含 `VIMac64b` 端口 + 新归约模块，无新乘法阵列；vmac 回归 `regression_delta == 0`；同一 Yosys 脚本对 vmac-only / vdot 两版跑面积对比（`design/ALGORITHM.md` §3.5，O1）。

**D-b 验证方法学**

- 19 位推导（含 `8×(−128)²=131072` 溢出 18 位的完整推导，`design/ALGORITHM.md` §1.3）。
- **混合符号奇数负 lane 定向用例**（负 lane 数 = 1/3/5/7），专抓积的符号扩展 bug。
- 形式验证：`vdot_dp` 组合 miter + bug 注入演示（`design/ALGORITHM.md` §3.5）。
- difftest harness 负向自检：故意把期望写错 1 bit，必须 ABORT（防止假通过，`design/ALGORITHM.md` §3.1）。
- 回归基线 `results/regression_baseline.json` + `regression_delta == 0`。
- Gloria 公开材料无形式验证与 harness 自检。
- **证据到手后如何验证**：上述五项各自产出脚本/日志/JSON；`scripts/check_results.py` 聚合校验，任一缺失即判 D-b 未达成。

**D-c 无假依赖微架构**

- `vdRen=F` + 不登记 `vmaInsts`，连续 vdot 背靠背吞吐目标 1 条/拍（待实测）。
- 竞品公开材料均无此项。
- **证据到手后如何验证**：N 条独立 vdot 的 `mcycle` 差分给出 `T_steady`；RAW 链用例验证写回正确；按 `design/ALGORITHM.md` §3.4 的三口径报告。

### 7.3 为什么不是 Gloria / Sun

- **Gloria 是当前证据链标杆**：官方 K=8、`ACCW=19`、XSTop 层次 PATH、65 行全核 PASS、252 次计时、PR #128 已合并。我们的策略是**先在证据完整性上 match**（XSTop 级证据、全核日志、计时口径），再靠 D-a/D-b/D-c 三个维度超出；不使用绝对化措辞。
- **Sun 的软肋**：语义偏离赛题伪代码（Zvdot4a 多结果）；数字前后不一致（2.40× vs 2.09×）；部分日志 dirty。
- **qixuan**：文档最全，但香山平台证据为零、阶段一阻塞。
- **目标表述**：**每一维不输、三维独有**；不使用绝对化措辞。

> 其他答辩素材（非可审计差异）：编码治理见 `design/SPEC.md` §2.3–§2.6；扩展路线图见本文 §9（只做文档，不写扩展 RTL）。

---

## 8. 风险登记（全量单份）

| # | 风险 | 预案 |
|---|---|---|
| R1 | 语义被判不符（K=16 宣讲口径） | 歧义裁决表 + K=8/K=16 对照；"以官方补充为准"留口径 |
| R2 | 清零失败（Mgu 回带旧值/0xFF） | Mgu 旁路 + 恒零断言 + difftest 逐位 |
| R3 | 2 拍时序不收敛 | 首选 tap0 2 拍（§3.1 预算，待综合）；**缺省判定日**：11-04 24:00 前 E-0/E-2 + vmac 回归未齐 ⇒ 锁 tap0、2 拍只写"设计目标"，不自动升 3 拍；有 STA/liberty 负 slack 或 emu 实测反压才启 X16（不改共享 VimacCfg）；A2 只作功能退路 |
| R4 | OPMVV 表无 `OPMVV(F` 先例（src3=X）路径异常 | 专门定向验证；出问题回退 vdRen=T + 忽略旧值 |
| R5 | X15 的 `VIMac64b` 端口改动破坏 vmac 回归 | 端口改动单独 commit + vmac 回归；不行退 A2 |
| R6 | 本机无法 emu（15.3 GiB < 32 GB） | **go/no-go 11-01**：远程 SSH 或本机 `make emu JVM_XMX=8G JVM_XSS=256m` 任一通过才继续全核路线；否则降级"模块级 + NEMU 协同"并主动标注"非全核平台证据"（见 ALGORITHM §3.7） |
| R7 | NEMU .so 未重编/配置错 | kmhv2 defconfig + `nm \| grep exec_vdot` + 核对 1400 B |
| R8 | 编码撞车 | 三元组锁死 + 双侧 grep 扫描表；禁用清单（含 101101=vmacc）；riscv-opcodes 官方归属核对为 D+0 必过项 |
| R9 | 时间不够 | G0 校验 + 距官方报名/材料提交截止 2026-11-08 23:59:59 不足 5 天裁剪线（内部计划日滑期不算官方逾期，见 §1.1）；扩展全关退 A |
| R10 | 证据不自洽 | 结果以 `results/*.json` 为准，表格自动生成 |
| R11 | 形式验证被过度解读 | 报告限定"只证数据通路" |
| R12 | 术语/位宽回归（18 位/radix-2/101101 备选） | 全文统一 19 位/radix-4/禁用清单 |
| R13 | `fireS1` 误用 `valid` 导致写回上一条指令数据 | X15 显式导出 `Output(Bool()) fireS1`；X-new `RegEnable(..., io.fireS1)`；wrapper 禁止重建（§2.2 第 7 条、§5.3）；定向背靠背用例暴露 |

> R1/R8/R12 的语义/编码条款以 `design/SPEC.md` 为准；R2/R3/R4/R5 的流水条款以本文 §3/§4 为准；R6/R7/R10/R11 的验证条款以 `design/ALGORITHM.md` §3 为准。

---

## 9. 扩展与开放问题（只做文档路线图，不写扩展 RTL）

1. **扩展优先级（文档）**：vdot4a（多结果）> vdot16（K=16 口径覆盖，需 20 位）> 参数化 > 多精度 INT4/INT16（BISDU 面积利用率警告，不进主线）。扩展只做编码、位宽、接口预留的设计说明。
2. **GEMV 端到端基准**：远程算力到位后再决定；测量口径见 `design/ALGORITHM.md` §3.4。
3. **`001110/010` 的 riscv-opcodes 官方归属复核**：编码冻结前的必过项，2026-10-31 已联网复核关闭（`stage2/2.1-design/encoding-gate-zvbc-2026-10-31.md`）；未来官方若改分配，以同脚本重跑，被占则回退 C-enc2（与 vdot4a 扩展编码互斥，见 `design/SPEC.md` §2.4）。

### 9.1 扩展的硬边界

- 扩展不得改动主线的编码/语义/测试期望；扩展失败只回退扩展（G1）。
- 扩展全部降级为文档路线图；主线三阶段证据冻结前不开写，**不写扩展 RTL**；主线独立可交付，扩展只上行不下行。
- K=16 覆盖为 vdot16 扩展设计说明（20 位）；vdot4a 严格对齐 Zvdot4a 语义后使用 `101100/010`；若回退 C-enc2，vdot4a 扩展改用 `001110/010` 且不再声称对齐 Zvdot4a 编码。

---

## 10. 证据附录（精选证据）

> 只收录与微架构直接相关的原文摘录（`文件:行`）。

### A-1｜`sum_wo` 就是 8 个完整积

```
`VIMac64b.scala:185-208`：`sum_wo` 定义 :187；`walOut := RegEnable(sum_wo.asUInt, fireS1)` :207-208。
SEW=8 时每个 16-bit lane 就是一个完整的 16 位有符号积。【实测】
```

### A-2｜tap0 取 `sum_wo`；「引 `walOut` = 第 3 拍」是旧误判（勘误）

```
- 原文（内部工作记录）：「不能直接引已寄存的 walOut 再做归约，否则归约树在第二级寄存器之后，等于第 3 拍。」
- 【勘误】walOut := RegEnable(sum_wo, fireS1)（VIMac64b.scala:208）与 io.out.valid 同在 t+2，引 walOut 归约不增加 latency，只是把归约放进 S3 组合拍、增加 S3 深度。
- 主线仍取 sum_wo（tap0）：改动面最小、不碰共享拍级；C 支线（walOut→S3）作 E-2 预登记实验，升级条件见 §2.2。
```

### A-3｜Mgu 的 tail/agnostic 永不为 0

```
`byte1s = (~0.U(8.W))`（:83）⇒ tail/mask 未激活的字节保留旧 vd；agnostic 字节写全 1，不是 0。【实测】
```

### A-4｜`isDependOldVd` 不是读旧 vd 的总开关

```
- `isDependOldVd` 只用于 dispatch/issue 的 `ignoreOldVd` 优化；真正的旧 vd 读使能是 `OPMVV` 的 `vdRen` → `src3 = SrcType.vp`（`VecDecoder.scala:81,91`）。
- 因此：覆盖写 + 其余清零应 `vdRen=F` 且不必进 vmaInsts。
```

### A-5｜`VimacType.vdot` 与 `dummy` 的数值（`yunsuan/package.scala:381-399`，按位域计算）

```
布局：pad(2) | vs2 sign | vs1 sign | vd_old sign | format | opcode(3)
vdot = 00_1_1_0_0_111 = 0x067（9 位；vd_old 位取 INT.X=0，不读旧 vd）
dummy = BitPat.Y(OpTypeWidth)（全 don't-care；按位模式数值视作 0x1FF）
⇒ 二者不相等，且 dummy 不是可译码 opcode。
```

### A-6｜`vxsat` 恒 0（`VIMac64b.scala:295`）

```
io.vxsat := Mux(isFixPS2, vxsat, 0.U)
```

### A-7｜vtype 内部编码与 vstart 非法（`VecExceptionGen.scala:57-58,275`）

```
private val SEW = io.vtype.vsew(1, 0)
private val LMUL = Cat(~io.vtype.vlmul(2), io.vtype.vlmul(1, 0))
private val vstartIllegal = isVArith && (io.vstart =/= 0.U)
```

### A-8｜真正的 FU 登记点

```
真正的登记点是 `Parameters.scala:449`：`ExeUnitParams(“VFEX0”, Seq(VfmaCfg, VialuCfg, VimacCfg, VppuCfg), ...)`。
复用 vimac 时这里不动；新建 FU 时必须改这里。【实测】
```

### A-9｜在 FU 的 illegal 输出里判定的风险

```
`VIMacU` 从未消费 `typeMod.io.out.illegal`；wrapper 只接 `mgu.io.out.illegal`（:150），而 Mgu 恒置 false（`Mgu.scala:131`）。
结论：SEW/LMUL/vm 合法性优先在 `VecExceptionGen`（或 DecodeUnit）里做。
```

---

## 11. 完成判据（可执行）

1. 改动位置表 8+3 的每个编号在源码中 `grep` 命中：`VDOT_VV`、`VimacType.vdot`、`VimacOpcode.vdot`、`exec_vdot`、X15 端口 `sum_wo` 与 `fireS1` 各一处；命令与输出存证据路径。
2. §3.1 的 2 拍预算表在综合/STA 后产出实测值；未测前保持"待测"，不得写成已收敛。
3. §7 四列对照表的每条事实都有公开材料出处；D-a/D-b/D-c 各有一份证据文件路径。
4. §8 的 R1–R13 逐条有状态（开放/已关闭/已降级）。
