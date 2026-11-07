# vdot.vv 算法内核与验证（ALGORITHM）

> 文档地位：**本文件与 `design/SPEC.md`、`design/ARCHITECTURE.md` 共同构成设计的语义与编码事实源**。本文只陈述现行设计，不叙述纠错史。
> 适用场景：**推导 19 位位宽、选归约树拓扑、写验证用例、跑形式验证/Yosys、做基线加速比、准备「量化收益」证据**时必读。
> 关联文档：语义与编码见 `design/SPEC.md`；数据通路、改动点与 2 拍时序见 `design/ARCHITECTURE.md`；代码规范见 `design/CODING-STD.md`。
> 证据附录：§4 为精选证据（≤80 行，逐条给出可核对的位置）。

---

## 0. 一句话内核

8 个 int8 有符号乘 → 8 个 16 位精确积 → 每积 sext19 → 8→1 归约（默认 **4:2 树**：8→4→2，2 段 3 实例；备选 3:2 树）→ 19 位 CPA → 32 位符号扩展写回；乘法复用 `VIMac64b` 的 Booth radix-4 + Wallace，归约树是 vdot 相对 `vmacc` 新增的结构。

---

## 1. 算法内核

### 1.1 乘法：Booth radix-4 + Wallace

- 复用 `VIMac64b` 的 **Booth radix-4**（3 位重叠窗）+ Wallace。
- **不是 radix-2 / Booth-2**：全文统一术语，防答辩被问穿。
- 若走 A2 自建亦用 radix-4：34 vs 67 加数、7 vs 9 级压缩。
- `VIMac64b` 的三级结构（源码实测）：
  1. 第一级：Booth 重编码 + 部分积生成；
  2. 第二级：128+128 加法（Wallace 压缩）；
  3. 第三级：取 vd / vsmul / 减法重排。
- Booth 窗口构造：`vs1Booth3b(i) := vs1(2*i+1, 2*i-1)`；在元素边界（`i%4==0` / `i%8==0` / `i==16`）改为 `Cat(vs1(2*i+1,2*i), 0)`，**保证部分积不跨 int8 元素边界**。
- 加数总数 = 32 个 Booth 部分积 + 1 个 `+1` 修正项 + 1 个 old vd 项 = **34**（`VIMac64b.scala:69,113,117`）。
- 跨流水级 retiming：`wallaceStage(size-1-3)` 后打拍，注释明写 "To alleviate timing, move last 3 steps of wallace into the second pipeline stage"（`VIMac64b.scala:165-168`）。

### 1.2 8→1 归约树

| 拓扑 | 结构 | 深度（源码布尔式模型计数，**未综合**） | 取舍 |
|---|---|---|---|
| **4:2 树（默认）** | 8 → 4 → 2（仓内 `CSA_Nto2With3to2MainPipeline(n=8,width=19,pipeLevel=0)`，2 段 3 实例）→ 19 位 CPA | **2 段 / 8 级全加器**；3 实例 / 684 门 | 段数与门数不劣；主线按此核算 |
| 3:2 树（备选） | 8 → 6 → 4 → 3 → 2 → 19 位 CPA | **4 段 / 12 级**；6 实例 / 798 门 | FA 等效持平（6 vs 6）；等价备选，不作"减一级"退路 |

> 勘误：旧表述"4:2 并不更浅"不成立——FA 等效持平，但 4:2 在段数/门数上不劣（−14% 模型门计数）。两者相对第二拍总量收益均有限，故 4:2 按**叠加项**处理，3:2 树仍是等价备选。

要点：

- **入树语义写死**：`S = Σ_{i=0..7} sext19(sum_wo[i])`；每个 16 位有符号积先符号扩展到 19 位再入树，**严禁零扩展**。
- 归约树的位宽只需覆盖最坏和（19 位），不需要 32 位。
- 香山现有归约（`Reduction.scala`）是窄归约会回绕，**拓扑可参考、位宽不可照抄**；vdot 的树必须重新参数化到 19 位。
- 可复用 `CSA3to2/CSA4to2`（`VectorFloatFMA.scala:1581,1596`），与香山既有归约单元风格一致。

### 1.3 19 位位宽推导

**结论：内部 `S` 必须是 19 位有符号；写回仍是 32 位。**

推导（K=8，int8 全范围 `[−128, 127]`）：

| 项 | 值 | 说明 |
|---|---|---|
| 最大单积 | `16384` | `(−128) × (−128)` |
| 最小单积 | `−16256` | `(−128) × 127` |
| 8 项最大和 | `131072` | `8 × 16384` |
| 8 项最小和 | `−130048` | `8 × (−16256)` |
| 18 位有符号上限 | `131071` | **装不下 131072** |
| 19 位有符号范围 | `[−262144, 262143]` | 可容 |

- 两端都要在推导中出现，不能只算一端：全 +127 时 `S = 8×127×127 = 129032`（18 位有符号可容，上限 131071）；最大值出现在全 −128，`S = 131072` 超出 18 位，必须 19 位。
- 写回 32 位 `vd[31:0] = sext32(S)`，因此风险只在内部归约树位宽与边界测试，外部可观测结果不变。
- 若实现写成 18 位，`vs1 = vs2 = 全 −128` 会溢出（131072 回绕成 −131072），边界测试必挂。
- 复现命令（原文）见 §4 A-2。

### 1.4 边界数值清单

| 用例 | 数值/期望 | 验证对象 |
|---|---|---|
| 全 0 | `S = 0` | 清零通道 |
| 全 +127 | `S = 8×127×127 = 129032` | 32 位写回、全正端点 |
| 全 −128 | `S = 8×(−128)×(−128) = 131072` | **19 位边界用例** |
| 全 −128 × 全 +127 | `S = 8×(−128)×127 = −130048` | 负向下界 |
| ±127、±128 | 单元素边界 | 符号扩展 |
| 交错极值 | 正负交替 | 归约树/符号扩展 |
| 混合符号奇数负 lane（负 lane 数 = 1/3/5/7） | 按算法 A/B 双算期望 | **符号扩展定向用例** |
| 仅第 8 个 lane 非零 | 低 64 位选择 | lane 0–7 |
| 高 64 位全 `0xFF`、低 64 位为 0 | 若误算高半区则结果改变 | 高 64 位不参与 |

**为什么必须补奇数负 lane 用例**：若把 16 位积当无符号入树，n 个负 lane 会产生 `n×2^16` 的偏差（模 2^19）。n=0 与 n=8 时该偏差在模 2^19 下消失（`8×2^16 = 2^19 ≡ 0`），所以"全 +127"和"全 −128"两组边界用例恰好抓不到零扩展 bug；必须用 1/3/5/7 个负 lane 的混合符号组合。

> 表中数值由对已知常量的算式直接展开得到，可逐项复算。

### 1.5 K=16 位宽（扩展路线图）

- K=16 需 **20 位**有符号累加：`16 × 16384 = 262144 > 2^18−1 = 262143`（19 位有符号上限）。
- 主线 19 位预算不变；K=16 只在文档路线图中给出编码/位宽/接口预留说明，**不写扩展 RTL**。

---

## 2. 优化候选与来源（方案空间调研摘录）

> **性质声明**：以下 16 条是方案空间的候选清单，**不是已采纳的设计决策**。每条给"来源"与"预期收益"；收益未标注"实测"的均为**估算/需实测**，不得在交付文档中写成已实现数字。采纳与否以本文 §1/§3 为准。**扩展类候选（8/9/10/16）只作文档路线图，不写扩展 RTL。**

| # | 候选 | 来源 | 预期收益 | 适用方案 |
|---|---|---|---|---|
| 1 | **VIMac64b `sum_wo` 引出 + 8→1 CSA 归约树**（不新增乘法器） | `VIMac64b.scala:185-201`（8×16-bit 积）、`:207-208`（walOut 是 sum_wo 的寄存） | 省去 8 个 8×8 乘法器与 Booth 逻辑；面积增量约 6–7 个 16 位 CSA + 1 个 19 位 CPA（估算，未综合）；2 拍可继承 | A/C 主线 |
| 2 | **4:2 压缩器归约树（8→4→2→CPA）** | `CSA4to2` 定义 `VectorFloatFMA.scala:1596`；`Reduction.scala:475-486` 先例 | 全加器级数约 4 级，与 4 级 3:2 相当，**并不更浅**；仅作结构备选（估算） | A/C 主线 |
| 3 | **Booth radix-4 vs no-Booth 的 A/B 选择** | `VIMac64b.scala:48-66`（radix-4）；`VIMac64b_noBooth.scala:44-62,148`（67 加数） | radix-4 使加数 34 vs 67、压缩树 7 vs 9 级（报告实算 −49.3%）；但 8×8 乘法每元素仅 4 个部分积，收益小于 64 位乘法，需综合权衡 | A2/B2 |
| 4 | **跨流水级 retiming：Wallace 末 3 级放第二拍** | `VIMac64b.scala:165-168` | 维持 2 拍（对齐 `FuConfig.scala:563`）；若归约仍不收敛，3 拍时 `piped=true` 仍可 1 条/拍，只增依赖延迟 | A/C |
| 5 | **Mgu 旁路 + `Cat(96'b0, sext32(S))` 格式化** | `Mgu.scala:83,90-92`（tail 保留旧 vd、agnostic 写 0xFF）；`docx/02` 的评分要求 | 满足"其余通道清零"，不受 `vta/vma` 影响；避免边界测试与 difftest 因高位非零失败 | 全部 |
| 6 | **不登记 `vmaInsts` + `vdRen=F`（去旧 vd 假依赖）** | `VecDecoder.scala:81,91`；`DecodeUnit.scala:1063,1069` | 连续 vdot 无 RAW/WAW 假依赖，背靠背吞吐目标 1 条/拍（待实测）；代价是 OPMVV 表当前无 `OPMVV(F` 先例（grep 0），需验证 `src3=X` 路径 | A/C 主线 |
| 7 | **19 位内部累加器（覆盖全 −128 边界）** | 本次实算 `131072 > 18 位上限 131071`（推导见 §1.3） | 覆盖全 `−128` 边界，避免回绕；写回仍 32 位，外部结果不变 | 全部 |
| 8 | **双模式共享乘法阵列：官方 K=8 + Zvdot4a 风格 4×int32** | 两片 `VIMac64b` 共 16 个积（`VIMac64b.scala:185-201`）；Sun 的公开路线 | 同一硬件第二条指令出 4 个 int32，算力密度 4×；2 拍内 4 路并行归约比 16→1 更浅。**只作文档路线图，不写扩展 RTL** | C 路线图 |
| 9 | **参数化 K/SEW/VLEN（K=4/8/16, SEW=8/16, VLEN=128/256）** | `docx/02:96` | 直接命中"扩展应用潜力"5 分；K=16 变体还覆盖官方宣讲页口径；RTL 用参数/generate 而非硬编码。**只作文档路线图，不写扩展 RTL** | A/C 路线图 |
| 10 | **多精度 INT4/INT16 模式（int4 复用 8 位乘法器半区）** | BISDU 的 SIMD 面积/利用率警告（DOI 10.1145/3608447）；Sun 三档的公开说明 | int4 吞吐 2×、int16 减少 lane 数；作为面积-精度对比表的素材有价值。**不建议进主线** | B/C 可选 |
| 11 | **编码三元组治理（最终采用 C-enc1b `001110/010`；原 `001100/010` 因 Zvbc `vclmul.vv` 占用而放弃）** | 五家五码对照；`encoding-gate-zvbc-2026-10-31.md`；禁用清单见 `design/SPEC.md` §2.5 | 避免劫持 `vwmaccsu`、`vclmul` 等正式指令；把"为什么选这个槽位"写成双侧 + 官方全库扫描证据，是原创性加分项；扩展指令用实现侧空闲槽位可避免"冒用官方分配" | 全部 |
| 12 | **组合 miter 等价 + Yosys SAT 证明数据通路** | Yosys `sat` / `equiv_simple` 实跑输出（见 §4 A-3/A-4/A-6） | 对 8 个 `sext8` 乘法的最易错点提供形式证据；本机可跑，成本低。现有 0.1 s / 93 s 数据是**玩具原型实测（8 乘法器 + 3 级树），非 VIMac64b 集成、非 PPA**；集成后用固定脚本重测 | 全部 |
| 13 | **边界向量枚举（全 −128、全 +127、高半区干扰、lane 8 选择）** | 照 riscv-vector-tests 的输入对枚举法；本次实算 `129032/131072/−130048` | 覆盖 2.3.1–2.3.3 三类测试，尤其是 19 位边界与"高 64 位是否被误算"的 lane 选择验证 | 全部 |
| 14 | **Python 金模型 ↔ NEMU ↔ RTL 三方对拍（固定 seed，difftest 逐位比较）** | `refproxy.cpp:185-229` 的 `memcmp` 路径（见 §3.1）；固定种子与 ≥1000 组见 §3.2 | 把"清零语义"变成机器判据；随机 ≥1000 组 + 固定 seed；日志记录 clean SHA；避免 Sun 式数字不自洽 | 全部 |
| 15 | **合规基线：B1/B2 + B3（仅敏感性分析，不作分母；内部自设口径）** | `docx/02:63-66`（官方只要求"组合实现"，无"最小 N 条"）；基线序列见 §3.4 | 同负载同 VL 的周期对比给 3.3 可信加速比；**B2 主分母、B1 最保守下界、B3 只进敏感性**；序列与计数口径见 §3.4；避免以标量基线计加速比的方法学扣分 | 全部 |
| 16 | **操作数隔离/门控（可选低功耗）** | `VIMac64b` 源码中未见显式 operand isolation，需自建 | vdot 空闲时把归约树输入钳 0，降低动态功耗；本机无功耗工具，收益未实测 | C 可选 |

---

## 3. 验证算法

### 3.1 三方金标准与防"空绿"

**Python 金模型 ↔ NEMU ↔ RTL difftest。**

执行流：金模型生成测试向量与期望值 → 汇编测试程序内嵌期望 → NEMU/RTL 执行 → difftest 逐位比较。

判据（三条同时满足）：

1. `HIT GOOD TRAP`；
2. **0 次 ABORT**（任一 mismatch 即 ABORT；`memcmp` 覆盖 `CPU_state` 含 `vr`；前提是 `CONFIG_DIFFTEST_ARCHVECREGSTATE` 在 difftest 构建中开启，`refproxy.cpp:185-229` 的 memcmp 路径确认向量寄存器参与比较；证据写进协同仿真记录）；
3. 旧向量回归 `regression_delta == 0`（基线见 §3.6）。

**harness 负向自检（进入下一阶段前必须通过）**：故意把 vd 期望写错 1 bit，difftest 必须报 mismatch/ABORT；若仍"全绿"即判"空绿"，禁止进入下一阶段。

**金模型的"双算法交叉对照"（定义写死）**：

- 算法 A：Python 任意精度逐项 `sext8` 相乘累加；
- 算法 B：位级模型（16 位积 → `sext19` → 模 2^19 累加 → 取 19 位有符号 → `sext32`）。

**金模型 API（2026-11-01 起生效）**：

- 返回 **128 位 vd**（不是 32 位）：`vd = result & WRITE_MASK`，其中 `result = S & 0xFFFF_FFFF`、`WRITE_MASK = 0x0000_0000_FFFF_FFFF`；即 `vd[31:0] = sext32(S)`、`vd[127:32] = 0`（**恒零**，与 `old_vd`/`vta`/`vma`/`vl` 无关，SPEC §1.1）。`old_vd` 只作入参接收、**不参与写回合成**：写回式里不得出现把旧值高位并回的项，否则高 96 位不再是常量零，SPEC §1.1「恒清零」即被破坏。高位清零必须**可被断言观测**。旧版 `return total & OUT_MASK` 使"高 96 位恒零"断言恒真（分支不可达），属零覆盖，**该口径废除**。
- 入参扩到 `vill`、`mstatus_vs`、`vxsat_in`、`old_vd`（与 `vl/vta/vma/vstart/vm/sew/lmul` 并列）；非法路径给出 `reasons`，顺序固定 `vs_off → vill → sew → lmul → vm → vstart`。
- 返回值扩为 `(vd, vs_dirty, vstart_next, vxsat_next)`。
- **三条变异必须变红**（模型自检的组成部分）：`WRITE_MASK→32`、`Cat(96'h1, …)`、删 `vill`；任一不变红即判模型无效。

### 3.2 测试矩阵

| 用例组 | 要求 |
|---|---|
| 正数 | ≥3 组定向 + 随机 |
| 负数 | 全负 / 混合 / 符号扩展边界 |
| **混合符号奇数负 lane** | 负 lane 数 = 1/3/5/7，按算法 A/B 双算期望（专抓符号扩展 bug） |
| 边界值 | 0、±127、±128、**全 −128（S=131072，19 位边界用例）**、全 +127（S=129032）、最小负和 −130048、交错极值 |
| 高 64 位干扰 | 高半区填满随机值，验证 lane 选择只取低 64 位 |
| 高 96 位恒零断言 | 每例必查；方法：`vse8.v` 存回内存后检查内存，或 `vslidedown` + `vmv.x.s` 逐段读回 |
| vl | `vl=0`、`vl=1/4/7` 断言"结果不变" |
| vta/vma | 四组合断言结果不变 |
| vstart | `vstart=1` → illegal |
| **vill** | `vill=1`（非法 vsetvl 后执行 vdot）→ illegal；NEMU/RTL/金模型同口径 |
| mstatus.VS | `VS=OFF` → illegal；**非法路径的 VS 只记实测值，不预设"不变"**（做法：先用 `vstart=1` 定向用例测出真实值） |
| vxsat | 用 `csrr vxsat` 前后读回一致（sticky 不变；恒 0 断言见 §3.1 金模型） |
| old vd | 预填非零旧 vd，断言输出不依赖旧值 |
| 重叠 | `vd==vs1`、`vd==vs2` 各一组，写清期望（正常/illegal） |
| RAW 链 | vdot → `vmv.x.s` / `vse8.v` |
| 背靠背 | N 条独立 vdot 连续发射，测 `T_steady` |
| 随机 | 固定种子(42)，≥1000 组，算法 A/B 交叉对照 |
| 非法编码 | SEW≠8 / LMUL≠1 / vm=0 / vstart=1 → illegal |

> 交付物映射：2.3.1–2.3.3 三组证据 + 加分项。

### 3.3 NEMU 协同仿真

- 三改点后自编 NEMU，并**替换 `ready-to-run/riscv64-nemu-interpreter-so`**：预编译产物不含 `exec_vdot`（用 `nm | grep exec_vdot` 自检）。
- 配置 `riscv64-xs-kmhv2-ref_defconfig`（勿用 v3 层叠）。
- 核对 `DIFFTEST_REG_SIZE=1400 B` 与 DUT 一致；否则 `difftest_init_v2` 直接 assert。
- 确认 `CONFIG_DIFFTEST_ARCHVECREGSTATE` 开启（`refproxy.cpp:185-229`），否则向量寄存器不参与比较，会出现"空绿"。
- 注意 NEMU `vreg.h` 有两份同 include guard 文件（两者内容不同，改动前先确认命中的是哪一份）。
- NEMU 侧实现要点：
  - 入口检查：`vm=0`、`vtype->vsew != 0`、`vtype->vlmul != 0` 任一命中 → 非法指令（落码 API 用 `longjmp_exception(EX_II)`，见 `design/CODING-STD.md` §4.4）；vstart 用 `check_vstart_exception(s)`；
  - 不能复用 `ARITH(...)` 宏（按 vl 循环散布每 lane，语义不对）；手写取 8×int8 → 写 `vd[31:0]` → **手写显式清零高位**；
  - **禁止 `set_vreg_tail`**（`vreg_impl.c:286` 写 `0xFF` 不是 0）。

### 3.4 基线与加速比（三口径）

- **三口径写死**：
  - `L_vdot`：依赖链 latency（官方主口径；3.3 报告以它为主）；
  - `T_steady`：稳态吞吐（cyc/dot，背靠背）；
  - `T_kernel`：kernel 总周期（`mcycle` 差值）。
- **基线分母（内部自设口径；官方 `docx/02:63-66` 只要求"用已有向量指令组合实现"，无"最小 N 条"要求）**：
  - **B2 = 主分母**（3 条向量计算 / 8 宏 / 17 uop）：`vwmul.vv` + `vwadd.vx`（widen 到 32 位）+ `vredsum.vs`；不依赖 widening 归约这一最少被测路径，产出规范 128 位形态；
  - **B1 = 最保守下界**（2 条 / 6 宏 / 11 uop）：`vwmul.vv` + `vwredsum.vs`（下方序列）；
  - **B3 = 无归约上限**（7 条 / 10 宏 / 18 uop）：只进敏感性分析，不作分母。
  - **计数口径**：三条 `vsetvli` 必须带 `ta,ma`（或 `tu,mu`）；配置与计算分开计数；128 位结果比较用 `tu` + 预清零；掩码判等用 `vfirst.m`（不用 `vmax.vx`）；性能用例跑 `--no-diff`。`L_vdot` 用真 RAW 链（如 `vdot.vv v10, v10, v1`，标准顺序 `vd, vs2, vs1` ⇒ 此处 vd==vs2）测依赖延迟；三链统一「逐次 rdcycle 取差、N=2000、去前 16 次暖机、取中位数」，见 `perf_vdot.c`/`perf_vadd.c`/`perf_vmacc.c`。
- **B1 序列（最保守下界，VL=8）**：

```
vsetivli zero, 8, e8, m1, ta, ma   # VL=8（配置 1；与 perf_base.c/T5 同天平）
vle8.v v1, (a0)                    # 载入 vs1：8 B（8 个 int8 lane）
vle8.v v2, (a1)                    # 载入 vs2：8 B
vwmul.vv v4, v1, v2                # 计算 1：8 个 16 位积（占 v4/v5）
vsetvli t0, x0, e16, m1, ta, ma    # VL=8（配置 2）
vmv.v.i v3, 0                      # 清零目标（高 96 位）
vmv.v.i v6, 0                      # 清零归约初值
vwredsum.vs v3, v4, v6             # 计算 2：v3[0] = Σ v4[0..7]（32 位）
vsetvli t0, x0, e32, m1, tu, mu    # VL=4（配置 3）—— 读回 32 位结果
vmv.x.s a3, v3                     # 读回 32 位结果（0 次 store）
```

  合计 **2 条向量计算**（`vwmul.vv` + `vwredsum.vs`）+ 3 条配置 + 2 次 load + 2 条清零 + 1 条标量读回（= B1）。**vmv.x.s 前必须切 e32**，否则只读低 16 位，S=131072 读出 0（按有符号 16 位读回时该值回绕）。与 vdot 的 128 位形态逐位比较时用 `tu` + 预清零。
- **"约 10 条"只作 Sun 完整序列参考，不作为分母**（用 10 条会把加速比放大 2–3 倍）。
- **"约 10 条"只作 Sun 完整序列参考，不作为分母**（用 10 条会把加速比放大 2–3 倍）。
- **基线位宽溢出处理**：`8×127²=129032` 超出 int16；基线用 widening 累加（`vwmul` + `vwredsum` 的 32 位结果）或分段归约，并在基线设计/日志中写明，避免基准自身溢出。
- **测量方法学**：`mcycle` 是 guest cycle，主机负载不影响。用例内口径：`perf_vdot.c`/`perf_vadd.c`/`perf_vmacc.c` 各采 N=2000 次「逐次 rdcycle 取差」样本、去掉前 16 次暖机后取中位数（防 guest 侧中断/异常抖动）；报告级口径：同配置再跑 ≥5 次取中位数，并补 N=0/64/256/1024 的斜率回归（扣循环开销）。两级别分开写：`VDOT_METRIC L_*` 是用例内单次运行的中位数。
- **禁止标量基线**（方法学扣分）。
- GEMV 端到端基准：远程算力到位后再决定（见 `design/ARCHITECTURE.md` §9）。
- 口径细则（`mcycle` 差值、`speedup = T_baseline / T_vdot` 的定义、变量控制、失真点）见本节上文「测量方法学」。

### 3.5 形式验证与 Yosys 口径

**形式验证（创新项，主证据是组合 miter）**：

- **DUT 边界**：`vdot_dp` = 8 个 `sext19` 乘积 + 4:2 压缩树（`CSA_Nto2With3to2MainPipeline(k=8, width=19, pipeLevel=0)`，8→4→2；落码 `VdotReduce.scala:32-33`）+ 19 位 CPA + 格式化，输出 32 位；不含流水寄存器/发射/旁路。
- **金模型**：§3.1 的算法 B 位级模型。
- **主证据**：`vdot_dp` miter（DUT vs 金模型）。落码后实设：生成的 `VdotReduce` 输出口带 `fireS1` 寄存器，故 yosys 命令用 `sat -seq 3 -prove-asserts`（展开三拍；第 0 拍两侧寄存器同为 0，第 1 拍起比较的就是归约+格式化的组合等价）；`scripts/50-formal-miter.sh` 的 `run_sat` 已同步，负控变异体把金模型 lane3 改成零扩展，必须报 `model found: FAIL!`。
- **不做整条路径 SAT**：BMC depth>3 不收敛已实测（§4 A-5）。
- 前期实测（**玩具原型：8 乘法器 + 3 级树，非 VIMac64b 集成、非 PPA**）：miter 0.1 s 通过；注入符号扩展 bug 1 s 内出反例；`equiv_simple` 93 s 通过。集成后用固定脚本重测。
- **报告必须限定范围**：只证数据通路，不覆盖流水/发射/旁路。

**Yosys 命令（固定顺序，可复现入口只有 `50-formal-miter.sh`）**：

```sh
# 组合等价（miter）：不要直接读 design/verify/formal/vdot_dp_miter.sv
#   —— 那个文件里没有 DUT（VdotReduce）的子模块定义，prep/hierarchy 会因缺子模块失败。
#   正确入口：先由 build_miter.sh 把 VdotReduce 闭包 + 金模型拼成 *_full.sv，
#   再用 50-formal-miter.sh 跑 SAT（DUT=VdotReduce，REF=vdot_dp_spec）。
bash design/verify/formal/build_miter.sh            # 产出 <out>/vdot_dp_miter_full.sv（含 DUT 闭包）
sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 core-package/scripts/50-formal-miter.sh \
       --miter <out>/vdot_dp_miter_full.sv --dut VdotReduce --ref vdot_dp_spec \
       --mutant <out>/vdot_dp_miter_bug_full.sv
# 与脚本等价的单条 yosys 命令（$MITER = 上面拼好的 full.sv；seq 分支的完整形态）：
yosys -p "read_verilog -formal -sv -DSYNTHESIS $MITER; hierarchy -check; proc; \
          miter -equiv -make_assert -flatten VdotReduce vdot_dp_spec miter; \
          chformal -skip 1; sat -verify -prove-asserts -seq 3 \
          -set-at 1 in_io_fireS1 1 -set-at 2 in_io_fireS1 1 -set-at 3 in_io_fireS1 1 miter"
# 面积/级数（vmac-only 与 vdot 两版跑同一脚本；仓库内源文件都是 .sv）
yosys -p 'read_verilog -sv <top>.sv; synth -top <top>; flatten; stat -json; stat -tech cmos; ltp -noff'
```

- **为什么 `chformal -skip 1` + `-seq 3`**：`VdotReduce` 输出口有 `fireS1` 寄存器，第 0 拍两侧寄存器初值不受输入控制，跳过它；`-seq 3` 展开三拍，并把 strobe 端口 `in_io_fireS1` 在三拍内钉为 1（`50-formal-miter.sh:128` 的 `run_sat seq` 分支就是这条命令）。旧版正文写 `sat -prove-asserts`（无 `-formal`、无 `-seq`、无 strobe）与本条自相矛盾，已改。
- 负控变异体（`build_miter.sh` 产出的 `vdot_dp_miter_bug_full.sv`，金模型 lane3 零扩展）必须报 `model found: FAIL!`。
- **【未运行】**：本机 `command -v yosys` NOT_FOUND（见下条），上述命令未在本机执行，只做了静态一致性核对。

- `flatten` 必须在 `stat` / `ltp -noff` 之前；`ltp -noff` 排除 FF，避免把流水寄存器算进组合路径。
- 报告口径：明确"仅对 vdot 数据通路模块综合，未含 VIMacU 其余部分，未含工艺库"；三个数一起给（cells / 晶体管估算 / 最长拓扑路径级数）并附完整命令；`stat -json` 存档；**`ltp` 级数只作相对量、不换算 ps**。
- **工具可达性（2026-11-01 实测）**：本机 `command -v yosys verilator iverilog sbt mill sby gh` **全部 NOT_FOUND**；PPA/形式验证挂昆山或指定镜像，跑不了就整组记**未运行**，不得引用玩具数字。

### 3.6 可复现要求与回归基线

- **可复现六件套**：命令、commit hash、配置、**波形、日志、测试输入/输出**。
- **test/ 工程化规划**：`.S` 编译链（xs-env 的 `riscv64-gcc`）、linker script、启动代码、trap handler、`ebreak` 约定、vd 读回方法，全部列入 `test/README`。
- **results schema**：`results/*.json` 定 schema；每条结果显式记录 `通过/失败/未运行`（`未运行` 不是通过）；`scripts/check_results.py` 聚合校验并生成表格。
- **回归基线（S2）**：
  - 基线文件：`results/regression_baseline.json`；
  - 内容：未修改 DUT（XiangShan @ `a4eeaab`）+ 未修改 NEMU（`a683e0b`）跑既有向量测试套件的逐用例快照；字段 `commit`、`nemu_commit`、`config`、`cases_total`、`case_id -> pass/fail`、`cycle`；
  - 跑什么/多少：既有向量测试全集（`riscv-vector-tests` 生成集 + 项目定向集），用例数在基线文件中固化；
  - 比较：修改后结果与基线逐用例比较，`regression_delta == 0`（新增失败数）才允许进入下一阶段。
- 日志记录 clean SHA；版本锁定见 `design/ARCHITECTURE.md` §5.1。

### 3.7 环境约束与执行分工

- **本机 15.3 GiB RAM，跑不了全核 emu（官方要求 ≥32 GB、推荐 64 GB）**。
- **进入下一阶段的前置条件写成可执行格式**（`命令 | 期望输出 | 证据文件 | 失败退路 | 执行平台`）：

| 命令 | 期望输出 | 证据文件 | 失败退路 | 执行平台 |
|---|---|---|---|---|
| `ssh <平台> 'cd XiangShan && make emu -j2'` 后运行 `./build/emu -b 0 -i xx.elf` | `HIT GOOD TRAP` | `results/env_emu.log` | 远程不可用 → 本机 `make emu JVM_XMX=8G JVM_XSS=256m`；仍失败 → 降级"模块级 + NEMU 协同"，并标注"非全核平台证据" | 远程 SSH / 本机 |
| `nm build/riscv64-nemu-interpreter-so \| grep exec_vdot` | 命中 1 行 | `results/nm_exec_vdot.log` | 检查 N3 与 `.so` 重编 | 远程/本机 |
| 文档体系检查（脚本随内部工程仓维护，不在本交付包内） | 退出码 0 | `results/check_js.log` | 修文档/补文件 | 本机 |
| `python3 design/verify/vdot_model_test.py` | 退出码 0 | `results/model_test.log` | 修金模型 | 本机 |

- **go/no-go 日期 11-01**：远程 SSH 或本机 `make emu JVM_XMX=8G JVM_XSS=256m`（低内存路径，先试）任一验证通过才继续全核路线；否则**降级**为"模块级 + NEMU 协同"，并主动在交付物标注"非全核平台证据"的扣分披露。
- **本机/远程分工**：

| 工作 | 平台 |
|---|---|
| Python 金模型 / 编码检查 / 文档校验 | 本机（`python3`/`node` 可用） |
| 形式验证 / Yosys 综合 / STA / Verilator 模块级 | **昆山**（或指定镜像）；不可达整组记「未运行」 |
| 全核 emu / difftest / 回归 / 性能 | 远程 SSH（昆山）；不可用则降级「模块级 + NEMU 协同」并标注 |

- 设计文档写明该分工；交付物里的仿真证据注明执行平台。
- **工具实测（2026-11-01，`command -v`）**：`mill`/`sbt`/`yosys`/`verilator`/`iverilog`/`sby`/`gh` **七项全 NOT_FOUND**；`python3`/`node`/`gcc`/`java`/`git`/`ssh` 可用。Docker 通路的环境记录为早期口径，**以本次 `command -v` 为准**；EDA 工作（综合/STA/形式/Verilator）挂昆山或指定镜像。

### 3.8 差异化证据分布（与 `design/ARCHITECTURE.md` §7 对齐）

- **D-b 验证方法学**的五个物证在本文件落地：§1.3 的 19 位推导、§1.4 的奇数负 lane 用例、§3.1 的算法 A/B 与 harness 负向自检、§3.5 的组合 miter、§3.6 的回归基线 JSON。
- 每条物证都要有脚本/日志/JSON 路径；`scripts/check_results.py` 缺失任一项即判 D-b 未达成。
- 性能三口径（§3.4）是 D-c 的度量基础；未测前一律写"目标/待测"。

---

## 4. 证据附录（精选证据）

> 只收录与算法/验证直接相关的原文摘录（`文件:行`）。

### A-1｜`VIMac64b` 的 Booth radix-4 与 8 个完整积（`VIMac64b.scala` 源码实测）

```
Booth 是 3 位重叠窗口（radix-4）；加数总数 = 32 个部分积 + 1 个 +1 修正 + 1 个 old vd = 34。
SEW=8 时 `sum_wo` 每个 16-bit lane 是一个完整 16 位有符号积；`wallaceStage(size-1-3)` 后打拍把末 3 级 Wallace 放进第二拍。
【实测：VIMac64b.scala:43-46,48-66,69,113,117,155,165-168,185-208】
```

### A-2｜19 位位宽的实算输出（可逐项复算）

```
最大单积: 16384 对应 a=b=-128；最小单积: -16256 对应 a=-128,b=127
8项最大和: 131072；8项最小和: -130048
18bit signed 范围: [-131072, 131071] 容纳131072? False
19bit signed 范围: [-262144, 262143] 容纳131072? True
```

### A-3｜组合 miter 的实测（Yosys SAT 实跑输出）

```
`Solving problem with 24891 variables and 73221 clauses..` → `SAT proof finished - no model found: SUCCESS!`，CPU 0.1 s 级。
【玩具原型：8 乘法器 + 3 级树，非 VIMac64b 集成、非 PPA】
```

### A-4｜注入符号扩展 bug 的反例（Yosys 反例输出）

```
`SAT proof finished - model found: FAIL!`，反例 `a = 10111101...110010101`（最高字节 0xBD，有符号 = −67），并生成 `bug_trace.vcd`。
→ 符号扩展类 bug 会被"组合等价 + SAT"在 1 秒内抓出。
```

### A-5｜时序 BMC 的规模边界（Yosys BMC 实跑输出）

```
| depth 2 | SUCCESS | 0.24 s / 81 MB【实测】 |
| depth 3 | SUCCESS | 0.55 s / 124 MB【实测】 |
| depth 4（正确设计） | 未完成 | >200 s（timeout）/ 258 MB【实测】 |
| 全局对齐 depth 6 | 未完成 | >300 s（MiniSAT，296,494 vars / 872,077 clauses）【实测】 |
```

### A-6｜`equiv_simple` 的实测（Yosys 实跑输出）

```
`Found 32 $equiv cells in equiv: Of those cells 32 are proven and 0 are unproven. Equivalence successfully proven!`，CPU 93 s，峰值内存 116 MB。【玩具原型】
```

### A-7｜Yosys 面积/级数实测（`stat`/`ltp` 实跑输出）

```
门级单元数 4366；晶体管估算 34,476（`stat -tech cmos`）；最长拓扑路径 41 级（`ltp -noff`）；user 0.76 s。
【玩具原型，非香山集成 PPA；`ltp` 含 FF 会把流水寄存器算进路径，必须 `-noff`】
【**源已失效**：产出该数字的 /tmp 玩具工程已不在工作区，不可复现；正文不得引用这三个数，只作历史记录】
```

### A-8｜difftest 的中止语义（`difftest.cpp` 源码实测）

```
`difftest_step()` 里 `case STATE_DIFF: difftest[i]->display(); case STATE_ERROR: return STATE_ABORT;`
—— 任一 mismatch 即 `display()` 打印后直接返回 ABORT（`difftest.cpp:150-165`）。
→ "mismatch 统计"只能是"跑了 N 个用例，0 次 ABORT"。
```

以上 A-1 至 A-8 均为 `文件:行` 级摘要，复核时可按条目给出的源码位置重跑。

---

## 5. 完成判据（可执行）

1. `python3 design/verify/vdot_model_test.py` 退出码 0（算法 A 与算法 B 交叉一致，含全 −128、全 +127、负 lane 数 1/3/5/7 四组）。
2. `design/verify/` 下的 harness 负向自检脚本退出码 0：故意写错 1 bit 时期望 difftest ABORT；若未 ABORT 则退出码非 0。
3. `scripts/check_results.py` 校验 `results/*.json` schema 通过，且 `regression_delta == 0`。
4. 形式验证脚本对 `vdot_dp` 的 miter 输出 `SUCCESS`，日志与命令入 `results/`；报告限定"只证数据通路"。
5. 文档体系检查通过：检查脚本随内部工程仓维护，不在本交付包内，退出码 0。
6. 本文所有未实测数字保持"目标/待测"；报告中的每个数字都能在 `results/*.json` 找到来源。
