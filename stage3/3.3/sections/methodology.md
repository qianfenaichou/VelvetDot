# 3.3 补充小节：测量口径防御 · 时序边界 · 功耗边界

> **位置**：本文件是 `stage3/3.3/report.md` 的正文来源。A/B/C 三节为**报告正文**（可直接并入），D/E/F 为**附录**（不进报告正文，供答辩使用）。
> **并入位置**：`stage3/3.3/report.md` 的 **§4.10**（本次实读位于 `report.md:837`）。按 §4.6 的并入约定，A/B/C 三节整件插入 §4.10 一处，不改数字与口径标签，也不拆到 §2/§5。
> **版本**：XiangShan `913ddd3` / yunsuan `83059b5` / NEMU `a9dca53`（实施 HEAD）；基线 pin `a4eeaab` / `9559211` / `a683e0b`。
> **标注约定**：【实测】=本次在本机或昆山实跑并看到输出；【实读】=本次取回原文/源码逐字读到；【推算】=由实读证据做的算术推导，非实测；【未运行】=本次未执行；【未核实】=查不到或无条件验证。
> **口径约定**：加速比只允许两个并列口径——官方整链 `16/4 = 4.0×` 与每指令归一 `1.33×`（整数打印口径 `1.25×`，见 `report.md` §4.3），引用时须写明是哪一个；`6 / 9` 只写「每点开销倍数」；`481 / 42,783` 只写 cell 占比，不是面积、不是功耗。
> **状态行（2026-11-08 同步）**：B 节（4.10.2 时序边界）的**结论状态已变**——STA 已补做（自建 OpenSTA 3.2.0 + Nangate45 代理 `typical` Liberty、预布局、仅模块级数据通路），**两版 `VdotReduce` 在 333 / 500 ps 下均违例**，2 拍仍是**未达成的设计目标**。**实测表、工具/Liberty/约束与六条边界只在 `report.md` §4.10.2 维护**，本文件不复制数字，避免出现第二份正文。A 节（4.10.1）与 C 节（4.10.3）**未变**；C 节的「功耗」仍【未运行】（缺活动率），但「工具与 Liberty 缺」这一条已不成立（见 C.3 路线 C 的本日注记）。

---

## A. 4.10.1 测量口径防御（为什么这些数字可以信、信到什么程度）

本节回答三个问题：为什么主指标取中位数而不是均值或最小值；emu 的 `rdcycle` 能不能当硅延迟；不同口径的数字为什么不能合并。**结论先写：能信的是「同一把天平上的相对比较」；不能信的是「跨口径的绝对换算」。**

### A.1 为什么取中位数：三个估计量的偏差方向不同

本报告主指标是 `L_vadd / L_vmacc / L_vdot` 的**逐次 `rdcycle` 差分中位数**（N_RAW=2000、丢前 `N_WARMUP=16` ⇒ 计入 1984 样本；`design/verify/cases/perf_vadd.c:42,44,84,90-101`、`perf_vmacc.c:42,44`、`design/verify/perf/perf_vdot.c:41,43,118-129`）。三链同 VL=8、同 SEW=8、同计数法，`cycles_per_op=` 是 median 的别名（`perf_vadd.c:138-144` 的 printf 把 median 同时打到 `cycles_per_op`）。

| 估计量 | 它假设什么 | 本环境的实际偏离 | 本报告的一手证据 |
|---|---|---|---|
| 最小值 `min` | 干扰只增周期、计数器读本身有序 ⇒ 最小值 = 干净样本（Agner Fog §18.1 方法 2） | `minstret/instret` 的读不按序、`mcycle/time` 可能被提前读（issue #6852）；本报告样本里还能直接看到**计数器回退**（`c1 < c0` 的无符号回绕） | `L_vadd` 的 1984 样本 `min=2`、`max=18446744073709551614`（= 2^64−2，说明至少一次 `c1<c0`）、`over=42`：`stage3/3.3/evidence/perf_vadd.20261103T075552.log:4`、`stage3/3.1.2-difftest/full-logs-20261103T142246/perf_vadd.20261103T142246.log:4` |
| 均值 `mean` | 噪声零均值、分布对称 | 宿主调度/中断是**单边**的（只加周期），均值被右尾拖高；但主指标三链 mean 与 median 同值 | `results/difftest/20-full-20261103T142246.json` → `metrics[]`：`L_vadd=3/L_vadd_mean=3`、`L_vmacc=4/4`、`L_vdot=4/4` |
| 中位数 `median` | 被污染样本 < 50% | 对低端回退与高端中断都不敏感；8 轮 × 2000 样本的基线链 **8/8 轮中位数都是 16**，16000 样本的均值也正好是 16 | `results/difftest/b3/91-b3-20261104T115624.log:5-13`（逐轮 `median=16 mean=16`；汇总行 `rounds_agree=yes`） |

**一句话**：中位数不是为了「更好看」，而是因为本环境的两个主要污染源一个向下（计数器读重排/回退）、一个向上（宿主调度），`min` 会被向下的污染骗到，`mean` 会被向上的污染拖高；中位数在污染样本不足一半时对两者都稳。**代价**：中位数不告诉你尾部形状，也不构成置信区间；所以本报告并列披露 `mean`、`min`、`max`、`over` 与逐轮中位数，读者可自行检查污染程度，而不是只看到一个中位数。

**可证伪条件（写进报告，供评委反向检查）**：若某轮中位数与其余轮不一致（`rounds_agree=no`），或 `mean` 与 `median` 的差大于 1 拍且方向一致，或 `over` 计数显著升高，则中位数本身也不可信，必须停下查测量链路。当前数据不触发：三链 mean=median（3/4/4）、基线链 `rounds_agree=yes`、`L_base_chain` mean=median=16；只有含离群的两条链并列披露 1 拍差（`L_base_chain_ladder` median 24 / mean 23；kernel `cyc_med=16 / cyc_mean=15`，`results/difftest/kernel/run-20261106T053316/93-kcmp-20261106T053316.log:14`）。

**两条必须同时写出的边界**：① `min=2`/`max=2^64−2` 不证明「某次中断真的发生了」——具体归因本次**未做实验**（没有关中断/关重排的对照），只作为「该样本集含低端与回退样本」的客观读数【未核实机制】；② 8 轮 × 2000 是本用例**自设尺度**（`design/verify/cases/perf_base_chain.c:55-56` 明写官方只要求「用已有向量指令组合实现」），不是官方规定口径。

### A.2 emu 的 `rdcycle` 是模型周期，不是硅延迟

`rdcycle` 读的是 emu 里 RTL 模型的周期计数器（emu 由 Verilator 从 RTL 编译：`results/emu/10-build-20261103T032307.log:4,8`）。它回答「这个微架构在模型里要走几拍」，不回答「这颗芯片在硅上要几纳秒、能跑多少 GHz」。

- **它能支撑的结论**：同模型、同 VL/SEW/vtype、同计数法下的相对比较——`L_vdot` vs `L_vmacc`（4 vs 4）、`T_steady` vs `B1/B2`（每点开销倍数 6 / 9）、8 轮中位数一致性。
- **它不能支撑的结论**：绝对频率（Fmax）、ps 级延迟、mW 级功耗、跨工艺/跨平台换算。2 拍时序目标因此只能写「设计目标」（见 B 节），不能用 `L_vdot=4` 或 `ltp=22` 代替 STA。
- **它自身的可信度边界**：difftest 把 `mcycle..mhpmcounter31` 全部标成 `isPerfCnt`（`repos/XiangShan/src/main/scala/xiangshan/backend/fu/NewCSR/NewCSR.scala:942-943,1140`），`isSkipDiff = isMMIO || isNCIO || isPerfCnt`（`repos/XiangShan/src/main/scala/xiangshan/Bundle.scala:365,369`），提交级 `difftest.skip := dt_skip`（`repos/XiangShan/src/main/scala/xiangshan/backend/rob/Rob.scala:1544,1548`）。**所以 30/30 difftest 通过不验证计数器语义**；计数器路径的已知问题见 issue #6852（OPEN）与 #6501（OPEN），前者直接涉及本报告口径。
- **单次样本不是证据**：主指标是 1984 个样本的中位数；`over=0` 只表示直方图未越界，不表示无离群。离群值原样披露（`min`/`max`），不静默截断。
- **内核级数字的额外限制**：§4.5 的 `18/16/11/7` 用 `mcycle`/`minstret` 做批间差分，两个计数器都不在有序读 CSR 白名单，故只采用 route1（10 轮批间差分的原始增量中位数再除以 step），route2 不作判据（`report.md` §4.5）。

### A.3 跨口径不合并：四条机械规则

1. **同对象、同计数法、同配置** ⇒ 可比、可相除。例：`L_vdot` vs `L_vmacc`（都是单指令 RAW 链、VL=8、N_RAW=2000、median）。
2. **同对象、不同计数法** ⇒ 并列，不相除。例：`L_vdot`（median 4）vs `L_vdot_loop`（整段墙钟 6）；`L_base_chain`（median 16，配置外提）vs `L_base_chain_ladder`（含 3 次 `vsetvli` 的 median 24）。用例头注明写「两个数不可相减」（`perf_base_chain.c:48`）。
3. **不同对象** ⇒ 只报裸比值并写清分母，不称「加速比」。例：`T_steady`（背靠背吞吐）÷ `B1/B2`（单 dot 整段每点开销）是「每点开销倍数 6 / 9」；原始 `L_base_chain / L_vdot = 16/4 = 4.0` 是「3 指令链 vs 单指令」的跨口径比值，本报告**不采用**；可采用的只有每指令归一 `L_base_chain_per_instr = L_base_chain/3 ≈ 5.33` 对 `L_vdot=4` 的 `1.33×`。
4. **不同平台/不同工艺** ⇒ 不合并、不换算。emu `cyc`、Yosys `cells`、FPGA `LUT/W`、ASIC `μm²/mW` 是四种量纲；`481 cells` 不能换 μm²，不能当功耗，不能与任何百分比合并。

> **核对问句（写数字前问三遍）**：① 这个数测的是什么对象？② 计数法是 median / mean / min / 整段墙钟中的哪一个？③ 分母是谁、和分子同对象吗？三问有一问答不上，就不写比值。

### A.4 与 Agner Fog、Kalibera & Jones 的准确关系（避免夸大引用关系）

| 来源 | 原文口径 | 本报告的关系 |
|---|---|---|
| Agner Fog, *Optimizing subroutines in assembly language* §18.1（pp.154–155） | 读计数器前后插 `CPUID` 串行化（"You have to insert XOR EAX,EAX / CPUID before and after each read of the counters..."）；短代码「重复测、取最小值」（"assume that the lowest of the clock counts measured represents a situation where no interrupt has occurred"）；丢弃暖机 | **借其原则**（丢弃暖机、重复测量、报告一个稳健的次序统计量），**明确偏离**其「取最小值」——前提「计数器读有序」在香山 emu 上不成立（issue #6852；本报告样本里可见回退） |
| Kalibera & Jones, *Rigorous Benchmarking in Reasonable Time*, ISMM 2013, pp.63–74 | 层次化重复（iterations / executions / builds）+ **算术平均**（"Calculate arithmetic means of these measurements for different levels."）+ 效应量**置信区间**（"We exhort researchers to report confidence intervals for their results..."） | **借其层次化重复**（我方有 iteration 级 8 轮与 execution 级两个独立作业）；**不主张**中位数是他们的方法（全文正文只在引述他文时出现一次 "median"，且指的是 Mytkowicz 等人的观测，不是其方法）；我方**没有**算置信区间、**没有** build 级随机化 ⇒ 只写「可复现」，不写「统计显著」 |

**因此报告中不得出现的三句话**：①「中位数是 Agner Fog 的方法」；②「中位数是 Kalibera & Jones 的方法」；③「已做置信区间／统计显著」。正确写法是：「中位数是我方针对本机噪声结构选择的稳健估计量，与上述两份方法学来源的关系是借用其重复测量/层次化抽样原则，并对 `min` 口径做了有理由的偏离。」

---

## B. 4.10.2 时序边界：2 拍仍是设计目标，代理工艺 STA 实测全部违例

**结论先写（2026-11-08 更新）**：本报告现在**有** STA，但它只到**模块级数据通路**、用**工艺代理**（Nangate45，45 nm，135 cell）、跑在**预布局**网表上——不是目标工艺、不是全芯片、不是签核。结果是**两版 `VdotReduce` 在 333 ps 与 500 ps 下都违例**（worst slack −791.8 / −624.8 ps 与 −375.8 / −208.8 ps），`VIMac64b` 的模块级网表 slack 达 −11,857.3 / −11,690.3 ps。因此 2 拍是**未达成的设计目标**，写「已收敛」即为越界。**逐 run 表、工具版本、Liberty、约束与六条边界见 `report.md` §4.10.2**；本节只保留判据、历史快照与「能说什么/不能说什么」，不复制数字。2026-11-06 的「无 `sta`、无 Liberty」快照见 B.5，它描述的是补做之前的状态。

### B.1 判据（内部预登记，统一定义）

闭合判据：`∀X∈{S1,S2,S3}: X_own + Δ_X ≤ P0`，`P0 = max(ltp(VIMac64b)=100, S3_own)`；K1 时 Δ 为 `S2 +22、S3 +0`，故在 `S3_own ≤ 100` 时真正起作用的约束是 `S2_own ≤ 78`。这是**相对预算**判断——问的是「新增 tap 会不会让某一段超过既有 `VIMac64b` 的最长拓扑路径」，不是「在目标工艺/目标频率下 setup 是否满足」。

### B.2 现在有什么：每条证据能说明什么、不能说明什么

| 证据 | 数值 | 出处 | 能说明 | 不能说明 |
|---|---|---|---|---|
| `ltp(VdotReduce)` | 22 级 | `results/yosys/40-area-20261104T094144.json` → `metrics[1].longest_path`（作业 `126752216`、`status=通过`） | 新增树的**拓扑级数**远小于 `VIMac64b` 的 100 级 | 不能换 ps；不能证明 setup；`ltp` 只算单模块内拓扑（Yosys 文档原文见 D-9） |
| `ltp(VIMac64b)` | 100 级 | 同文件 → `metrics[0].longest_path` | 作为相对基准 `P0` | 同上 |
| 结构不变量 I1/I2 | `fireS1` 同使能同边界；结果寄存器与 `outCtrl` 在 C2 对齐 | `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:129-130,159-160`（端口连接与输出选路） | vdot 不新增流水级；第 2 拍与 `VIMac64b` 的第 2 拍并行 | 不证明该拍内组合延迟满足 |
| 交付形态的 2 拍目标 | `VimacCfg.latency = CertainLatency(2)` | `repos/XiangShan/src/main/scala/xiangshan/backend/fu/FuConfig.scala:551,563` | 交付配置写的是 2 拍 | 不是 STA 结论 |
| 面积 JSON 的性质 | `scope` 字段=「仅 vdot 数据通路模块，未含 VIMacU 其余部分，**未含工艺库**」 | 同 JSON 的 `scope` 字段（实读） | 该 JSON 不是可喂 STA 的网表 | 不存网表、不是 Liberty 映射后的标准单元（2026-11-08 补做 STA 的网表是另一次 yosys 映射产物，不是这个 JSON） |

**缺什么（G-D 缺省）**：2026-11-04 24:00 设了 G-D 缺省——E-0/E-2 实测与 vmac 回归未齐时锁定 tap0/K1，2 拍只写「设计目标/预算内候选」，不自动升 3 拍、不启 X16（`design/ARCHITECTURE.md:103`）。**具体缺项（2026-11-08 更新）**：`S2_own`/`S3_own` 切段探针**仍未建**（`design/verify/area/gen_probes.sh` 未建，该目录实读只有 `build_area_rtl.sh`）；Liberty、Yosys 工艺映射（`dfflibmap -liberty` + `abc -liberty`）、OpenSTA、SDC 与 `report_checks` **已由 2026-11-08 的 STA 补上**（见本节开头）——**剩下的缺口就是切段探针**。

### B.3 可学的先例：外部公开材料的 ASAP7 + OpenSTA 与负 slack 如实报告（调研范围内）

一份外部公开参赛材料采用了「固定版工具链 + 明写参考预算 + 负 slack 照实写」的写法。该材料的**具体数值、仓库路径与 commit 不在本文件列示**；本节只保留四条可复用的方法：

| 项 | 该材料的做法（只写方法） | 值得学的点 |
|---|---|---|
| 工具链 | Yosys + OpenSTA + 固定版 OpenROAD-flow-scripts | 工具版本固定，避免「换工具换结论」 |
| 约束 | 预先声明一个参考时钟预算 | 预算明写，读者可自行换算 |
| 结果 | 预布局 STA 出现负 slack，照实写并附面积/路径量级 | **负 slack 照实写**，不写成收敛 |
| 边界声明 | 明确「公开 ASAP7 库 + 局部实验约束」 | 明确是工艺代理 + 局部约束，不冒充目标工艺签核 |

**与它的关系（2026-11-08 更新）**：本仓**已补做**这一步（工具与工艺库均自建，见本节开头），并按该写法注记「工艺代理 + 局部约束 + 预布局」；**负 slack 照实写**（−791.8 … −11,857.3 ps），**不能**写「已做 STA 且满足」。二者**不做数值对比**：工艺库、对象、约束都不同；同口径只保留「负 slack、工艺代理」这一方向性一致，仅此而已。

### B.4 若要闭合：路线（2026-11-06 时未运行；2026-11-08 已跑通模块级部分）

1. **先补切段闭包**：`gen_probes.sh`（未建）生成 M-S2 / M-S3 两个 top，产出 `S2_own` / `S3_own`；没有这一步只能对 `VdotReduce` 单模块做 STA，不能对「tap 并入 S2」的真实路径做 STA。
2. **选 Liberty 与工艺代理**：公开 PDK（如 ASAP7 / sky130）只能作**工艺代理**，结论只能写「代理工艺下的相对路径比较」。
3. **Yosys 工艺映射**：`dfflibmap -liberty $lib`（昆山 Yosys 0.48 帮助原文：「Map internal flip-flop cells to the flip-flop cells in the technology library specified in the given liberty files.」，本次实取）→ `abc -liberty $lib` → `write_verilog -noattr -nohex -nodec mapped.v`（三个选项在昆山 Yosys 0.48 `help write_verilog` 中实读存在：`-noattr` / `-nohex` / `-nodec`）。
4. **OpenSTA 读入与检查**（与 ORFS 同一套路：`synth.tcl:347` 写网表、`load.tcl:33-34,42` 读网表/链设计/读 SDC）：
   ```tcl
   read_liberty $lib
   read_verilog mapped.v
   link_design VdotReduce   ;# 或 M_S2 / M_S3
   read_sdc constraints.sdc
   report_checks -path_delay max -format full_clock_expanded
   ```
   SDC 至少要有 `create_clock -period <T>`、输入/输出 `set_input_delay`/`set_output_delay`、`set_clock_uncertainty`；端口名以生成网表为准。
5. **判据**：在同一 Liberty、同一 clock 下比较切段路径与 `VIMac64b` 关键路径，判据是「tap 并入后 S2 仍不超过既有 MAC 关键路径」，**不是**「绝对频率达标」。

**2026-11-08 执行情况**：第 2–4 步已做（Liberty = Nangate45 代理；`dfflibmap` + `abc -liberty` 映射；OpenSTA `read_liberty → read_verilog → link_design → create_clock → set_*_delay → report_checks`）；第 1 步（`gen_probes.sh` 切段闭包）**仍未做** ⇒ 第 5 步的**切段**判据**未完成**，已跑的是两个模块各自的整模块路径（`report.md` §4.10.2 表）。

### B.5 工具与工艺库可达性（2026-11-06 实测快照；2026-11-08 已被新状态取代）

完整命令与原始输出：`stage3/3.3/evidence/sta-toolcheck-20261106.txt`（46 行，逐条命令 + 原样输出）。

| 位置 | `yosys` | `sta` | `openroad` / `opensta` | Liberty / PDK |
|---|---|---|---|---|
| 本机（开发机） | NOT_FOUND（`command -v` 无输出、`EXIT=1`） | NOT_FOUND | NOT_FOUND | 仓内 `*.lib/*.lef/*.sdc/*.db` **0 个** |
| 昆山登录节点（未 source） | NOT_FOUND | NOT_FOUND | NOT_FOUND | — |
| 昆山登录节点（`source ~/tools/env.sh`） | **可用**：`~/tools/yosys/bin/yosys`，`Yosys 0.48 (git sha1 aaa53474…)` | NOT_FOUND | NOT_FOUND | `module avail` 无 openroad/opensta/asap7/sky130（`grep` 退出 1）；HOME 内无 ORFS/OpenROAD 目录、无 `.sif`；`*.lib` 只命中 `core/src/nexus-am/Makefile.lib`（构建片段，非 Liberty） |

⇒ **该快照的结论**：2026-11-06 时 STA 与 `report_power` 均【未运行】，原因不是脚本出错，而是工具与工艺库数据链缺失（当次未安装、未构建、未下载任何 PDK，未执行任何 STA 命令）。**2026-11-08 变化**：STA 工具（自建 OpenSTA 3.2.0）与 Liberty（Nangate45 代理）已具备，STA **已跑**（`report.md` §4.10.2）；`report_power` **仍【未运行】**，因为仍缺**活动率**（VCD/SAIF）。

---

## C. 4.10.3 功耗边界：RTL 级能说什么、不能说什么

**结论先写**：本报告**没有**功耗实测，也**没有**可换算成 mW 的 RTL 功耗估算。能写的是三条有证据的结构性事实 + 一条外部 FPGA 参照；不能写「功耗仅增 1.12%」「几乎不增功耗」这类把面积当功耗的句子。

> 口径定位：官方 3.3 的显式判据只有「Baseline 与 vdot 的 latency 加速比」（`docx/02-赛题与评分细则.md:66`）；功耗不是独立评分行，但官方描述提到低功耗（`docx/02-赛题与评分细则.md:18`）。本节是**防守性口径说明**，不冒充官方要求。

### C.1 外部参照：Nanhu-vdot 的 +0.5% 是 FPGA 数，不是硅数

arXiv:2409.00661（Chen 等，2024）在 XiangShan Nanhu **最小配置**上做 vdot 扩展，报告：

| 项 | nanhu | nanhu-vdot | 增量（本次复算） | 口径 |
|---|---|---|---|---|
| LUT | 564,211 | 579,888 | +15,677（+2.78%，论文写 2.8%） | Xilinx VU19P FPGA（S2C Prodigy S7-19PS 机箱）+ Vivado 2020.2 综合实现 |
| Flip-Flop | 278,746 | 281,232 | +2,486（+0.89%，论文写 0.9%） | 同上 |
| BRAM | 436.5 | 436.5 | 0 | 同上 |
| 功耗 | 8.454 W | 8.494 W | +0.040 W（+0.47%，论文写 0.5%） | 论文只给数值，**未写**测量方法/活动率/VCD/SAIF；「Vivado 实现后功耗报告」是上下文推断【推算】 |

**用法与边界**：只能作为「同类 vdot 扩展在 FPGA 原型上资源/功耗增幅为个位数百分比」的**方向性佐证**；不能当香山 ASIC 的功耗数，不能把 +0.5% 搬到本设计。原因：① FPGA 功耗与 ASIC 功耗不是同一量纲；② 论文用**最小配置**（减少译码/执行单元、去 L2），与昆明湖 V2 全配置不同；③ 未给活动率/VCD/SAIF 设置，无法复算。

### C.2 我方一手事实：面积占比 + always-on 结构

| 事实 | 数值 | 出处 | 能说明什么 |
|---|---|---|---|
| `VdotReduce` 全口径 cell 占比 | 481 / 42,783 = **+1.12%**（精确 1.1243%） | `results/yosys/40-area-20261104T094144.json` → `metrics[]`（`VdotReduce` 481 / `VIMac64b` 42,783） | 通用门计数的面积增量 |
| 组合口径 cell 占比 | 458 / 41,945 = **+1.09%**（精确 1.0919%） | `results/yosys/vdot.stat.json`（481 = 458 组合 + 19 `$_DFFE_PP_` + 4 `$scopeinfo`）+ `results/yosys/vmac_only.stat.json`（42,783 − 838 时序单元 = 41,945） | 组合逻辑增量；不含 19 FF |
| cell 组成（说明「面积占比 ≠ 功耗占比」） | `$_XNOR_ 134 / $_XOR_ 128 / $_MUX_ 105 / $_ANDNOT_ 32 / $_OR_ 23 / $_DFFE_PP_ 19 …` | `results/yosys/vdot.stat.json` → `num_cells_by_type`（本次实读） | tap 的 cell 类型比例与 `VIMac64b` 不同，不能假设「同比例同功耗」 |
| tap 的连接与使能 | `vdotReduce.io.sum_wo := vimacs(0).io.sum_wo`（常连，无 opcode 门控）；`io.vd := RegEnable(result, io.fireS1)` | `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:129-130`、`repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala:44` | 归约树对**每条 vimac** 都在算、都 latch |
| 选路只在输出级 | `outIsVdot = outCtrl.fuOpType === VimacType.vdot`；`Mux(outIsVdot, vdotReduce.io.vd, mgu.io.out.vd)` | `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:159-160` | 选路不 gate 树，只是选择输出 |
| 操作数隔离 | 未实现（列为可选低功耗项，收益未实测） | `design/ALGORITHM.md:114`（第 16 项，标「C 可选」） | 没有「vdot 空闲时钳 0」的机制 |

**由这些事实能推出的功耗结论只有一句**：新增逻辑的**面积**是 +1.12%；由于 tap 没有 opcode 门控，它的动态功耗在**每条 vimac** 上都会发生，而不是只在 vdot 上发生。这是定性成本，不是 mW 数字。

### C.3 四条估算路线与可行性

| 路线 | 需要什么 | 现在能不能做 | 能产出 | 不能产出 |
|---|---|---|---|---|
| A. 面积代理 | 已有 481 / 42,783 | **能**（已完成） | 「cell 占比 +1.12%」 | 不能称功耗；不能假设 cell 电容/活动率相同 |
| B. 手算 `P_dyn = α C V² f` | `C`（Liberty/PDK）、`V`、`f`、`α`（VCD/SAIF 或假设） | **不能**（缺 C/V/f/α） | 若强行假设，只能给无量纲比值 | 不能给 mW；不能当实测 |
| C. OpenSTA/OpenROAD `report_power` | Liberty + 映射后网表 + 活动率（VCD/SAIF 或 `set_power_activity`） | **Liberty 与映射网表已具备（2026-11-08 补做 STA 时自建 OpenSTA 3.2.0 + Nangate45 代理库）、活动率仍缺**；【未运行】 | 给定 Liberty/活动率下的 internal/switching/leakage/total power（W） | 没有活动率（VCD/SAIF）就给不出有意义的数；Nangate45 只是工艺代理，不是目标工艺 |
| D. 用现有 VCD 做活动率 | VCD 必须是真实时钟域、覆盖代表性负载 | **不能**：`stage2/2.2-rtl/wave/` 的 `key.vcd` 的 clock 是**采样域时钟**（每拍 dump 一次 ⇒ 摘录中恒为 1、窗口 [8377,8577] 内 **0 次翻转**），且仅 213 个时间戳、非 `VdotReduce` 独立 top | — | 不能当活动率证据 |

**OpenSTA 的能力边界（引原文）**：`report_power` 用 Liberty power models + propagated/annotated pin activities，报告 internal/switching/leakage/total power（"Power values are reported in watts."）；无仿真活动时用 `set_power_activity`，输入默认 activity=0.1、duty=0.5（OpenSTA Commands 页，本次实取）。**2026-11-08 注**：Liberty（Nangate45 代理）与映射后网表已具备，缺的只剩活动率——`set_power_activity` 的默认 0.1/0.5 是假设值、不是本设计数据，故 `report_power` 仍【未运行】，本节继续不写 mW 数字。

### C.4 禁止写法

- 不写「功耗仅增 1.12%」「功耗几乎不增」——1.12% 是 cell 占比，不是功耗。
- 不写「Nanhu-vdot +0.5% ⇒ 本设计也 +0.5%」——平台/配置/工艺都不同。
- 不写「OpenROAD 可算功耗 ⇒ 已算」——2026-11-08 起 Liberty 与映射网表已有，但活动率仍缺；`report_power` 仍【未运行】。
- 不写「tap 只在 vdot 时翻转」——源码显示它对每条 vimac 都 latch。

---

## D. 引用清单（作者 / 标题 / URL / 一句话用法 / 核实状态）

> 访问日期 2026-11-06。文件大小与本次抽取行号均为实测；issue 与仓内 README 走 `gh` API 实取。

| # | 作者/机构 | 标题 | URL | 一句话用法 | 核实状态 |
|---|---|---|---|---|---|
| 1 | Agner Fog | *Optimizing subroutines in assembly language: An optimization guide for x86 platforms*，§18.1 "Testing speed"，pp.154–155 | https://www.agner.org/optimize/optimizing_assembly.pdf | 计数器前后 `CPUID` 串行化、丢暖机、短代码重复取最小值；本报告借其原则、明确偏离「取最小值」 | 【实读】HTTP 200、1,091,275 B；`pdftotext -layout` 后 `agner.txt:9150`（CPUID 句）、`:9164-9165`（最低值句）逐字核对 |
| 2 | Agner Fog | *Test programs for measuring clock cycles and performance monitoring*（`testp.zip`） | https://www.agner.org/optimize/#testp | 他的测试程序实现「高优先级 + 取最小值」两种抗中断方法，说明 `min` 口径的适用前提 | 【实读】页面 HTML 取回，`testp.zip` 链接/大小/日期实读（未下载运行） |
| 3 | Tomas Kalibera, Richard E. Jones | *Rigorous Benchmarking in Reasonable Time*，ISMM 2013，pp.63–74，DOI 10.1145/2464157.2464160 | https://doi.org/10.1145/2464157.2464160；开放 PDF https://kar.kent.ac.uk/33611/45/p63-kaliber.pdf | 层次化重复 + 算术平均 + 效应量置信区间；不主张中位数 | 【实读】PDF HTTP 200、484,071 B、12 页；`kalibera.txt:866`（arithmetic means）、`:1086`（exhort confidence intervals）逐字核对 |
| 4 | David Harris（davidharrishmc） | *[Bug] csrr of minstret/instret is not ordered after older instructions (counters missing from waitForwardInOrderCsrReadList)*，issue #6852，OPEN，2026-11-03T09:52:43Z | https://github.com/OpenXiangShan/XiangShan/issues/6852 | 香山 kunminghu-v2 上 `minstret/instret` 读不按序；`mcycle`/`time` 可能被提前读 —— `min` 可能低于真实值的机制佐证 | 【实测】`gh issue view 6852 --json …` 返回 `state=OPEN`、author `davidharrishmc`；body 原文含「Two reads 8 instructions apart should differ by exactly 9 … usually differ by 0」「`mcycle` and `time` may arguably be read early」 |
| 5 | oChunCai | *[Bug] `csrw minstret, X` followed by `csrr` reads X+1 …*，issue #6501，OPEN，2026-09-06T15:08:03Z | https://github.com/OpenXiangShan/XiangShan/issues/6501 | 同仓另一条计数器语义边界；旁证计数器路径有已知问题（不直接用于本报告数字） | 【实测】`gh issue view 6501 --json …` → `state=OPEN`、author `oChunCai`、`createdAt=2026-09-06T15:08:03Z` |
| 6 | Parallax / OpenROAD Project | *Parallax Static Timing Analyzer*（OpenSTA）README | https://github.com/parallaxsw/OpenSTA | 门级 STA 读 Verilog netlist + Liberty + SDC；功耗可用 VCD/SAIF 活动率 | 【实读】`gh api …/contents/README.md` 取回，逐字读到「gate level static timing verifier」与文件格式清单 |
| 7 | Parallax / OpenROAD Project | OpenSTA Command Reference（`report_power` / `set_power_activity`） | https://opensta.readthedocs.io/en/latest/Commands/ | `report_power` 基于 Liberty power models + 活动率，报 W；无活动时 `set_power_activity` 默认 input 0.1 / duty 0.5 | 【实读】HTTP 200、383,262 B；命令条目文本本次抽取核对 |
| 8 | OpenROAD Flow Scripts | `flow/scripts/synth.tcl`、`flow/scripts/load.tcl` | https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/flow/scripts/synth.tcl；https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/flow/scripts/load.tcl | Yosys `write_verilog` → OpenSTA `read_verilog/link_design/read_sdc` 的标准先例 | 【实读】`gh api` 取回；`synth.tcl:347`、`load.tcl:33-34,42` 逐行核对 |
| 9 | YosysHQ | Yosys 命令文档：`ltp`、`dfflibmap`、`write_verilog` | https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd/index_passes_status.html（`ltp`）；https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd/index_passes_techmap.html（`dfflibmap`） | `ltp` 只算单模块内拓扑级数（`-noff` 排除 FF）；`dfflibmap -liberty` 做 FF 映射；`write_verilog -noattr` 写网表 | 【实读】`ltp` 页 HTTP 200、文本逐字核对；`dfflibmap` 帮助文本在昆山 `yosys 0.48` 上实跑取回（`help dfflibmap` 原文见 B.4） |
| 10 | Xu-Hao Chen, Si-Peng Hu, Hong-Chao Liu, Bo-Ran Liu, Dan Tang, Di Zhao | *Research on LLM Acceleration Using the High-Performance RISC-V Processor "Xiangshan" (Nanhu Version) Based on the Open-Source Matrix Instruction Set Extension (Vector Dot Product)*，arXiv:2409.00661 | https://arxiv.org/abs/2409.00661；PDF https://arxiv.org/pdf/2409.00661 | Nanhu-vdot 的「几乎不增功耗」= FPGA VU19P + Vivado 2020.2 + 最小配置：8.454→8.494 W、LUT +2.8%、FF +0.9%、BRAM 不变 | 【实读】PDF HTTP 200、741,721 B、10 页；`nanhu.txt:242-296` 逐字核对（含机箱/FPGA/工具链、资源表、功耗句） |
| 11 | 外部公开参赛材料 | README §4「ASAP7 综合与预布局 STA」 | 从略 | 方法学参照：固定版工具链 + 明写参考时钟预算 + 负 slack 照实写 + 「公开 ASAP7 库 + 局部约束」边界声明；**不列外部数值与可识别信息** | 【实读】本次调研覆盖的参赛材料中读到该写法；不记 commit/路径/数值 |

---

## E. 「能做 / 只能声明缺省」边界总表（报告 §8 的上位表）

> 左列 = 现在能写进报告的（有证据）；右列 = 只能写「缺省/未运行」的。任何右列内容被写成「已完成/已收敛/已实测」都是越界。

| # | 能力 | 现在能做（有证据，可写） | 只能声明缺省（禁止的写法） | 证据/命令 |
|---|---|---|---|---|
| 1 | 依赖延迟/吞吐的**相对比较** | `L_vadd=3`、`L_vmacc=4`、`L_vdot=4`（median=mean，1984 样本）；`T_steady=1 cyc/dot`；`L_base_chain=16`、`L_base_chain_ladder=24`、`B3=11` | 不能写「硅上 4 拍」「Fmax 可达 X GHz」「vdot 比基线快 4×/6×/9×」；不能把 6/9 叫 latency 加速比 | `results/difftest/20-full-20261103T142246.json` → `metrics[]`；`results/difftest/b3/91-b3-20261104T115624.log:5-22` |
| 2 | 中位数 vs 均值 | 主指标 median=mean（3/4/4）；基线链 median=mean=16、8/8 轮一致；ladder 24/23；kernel 16/15 | 不能写「中位数是 Agner/K&J 的方法」；不能写「已做置信区间/统计显著」；不能只报中位数而隐藏 mean/min/max | `perf_vadd.c:80-112`；`91-b3-…log:5-13`；`93-kcmp-…log:14` |
| 3 | `rdcycle` 读的可信度 | 可写「difftest 对 `mcycle..mhpmcounter31` 全部 skip，计数器语义不由 difftest 覆盖」；可写 #6852/#6501 的机制 | 不能写「30/30 通过 ⇒ 计数器读数一定对」；不能把单次 `min` 当干净样本；不能把 #6852 写成「官方口径」 | `Bundle.scala:365,369`；`NewCSR.scala:942-943,1140`；`Rob.scala:1544,1548`；`gh issue view 6852/6501` |
| 4 | 2 拍时序 | 可写「设计目标 2 拍（`VimacCfg.latency=2`）」；可写「`ltp(VdotReduce)=22` vs `ltp(VIMac64b)=100` 是拓扑级数」；可写 G-D 缺省锁 tap0/K1；**2026-11-08 起**可写「代理工艺 STA 实测：K1/P-2 `VdotReduce` 在 333/500 ps 下 worst slack −791.8/−624.8 与 −375.8/−208.8 ps，`VIMac64b` −11,857.3/−11,690.3 ps，全部违例」（`report.md` §4.10.2） | 不能写「2 拍已收敛」「setup 满足」「22 级 < 100 级 ⇒ 满足 2 拍」「换算成 ps/GHz」；**也不能**把代理工艺（Nangate45、预布局、仅数据通路）的负 slack 写成目标工艺签核数或频率 | `FuConfig.scala:563`；`40-area-20261104T094144.json`；`design/ARCHITECTURE.md:103`；`report.md` §4.10.2 表与六条边界 |
| 5 | STA | 可写「路线：`read_liberty → read_verilog → link_design → read_sdc → report_checks`」；可写 ORFS 先例与外部公开材料的负 slack 范式；**2026-11-08 起**可写「本仓已用自建 OpenSTA 3.2.0 + Nangate45 代理库跑过模块级 STA，结果为负 slack」（`report.md` §4.10.2，证据 `results/sta/20261108/`） | 不能写「STA 已通过/已签核/时序收敛」；不能写「用公开 PDK 签核」；不能把模块级、预布局、无寄生的结果当全芯片或目标工艺结论；`report_power` 仍不能写「已跑」 | `results/sta/20261108/toolchain_20261108.log`（OpenSTA 3.2.0、Liberty sha256、135 cell）；`worst_slack_20261108.tsv`（8/8 `rc=0`）；2026-11-06 的「`sta` NOT_FOUND」快照见 `evidence/sta-toolcheck-20261106.txt`（历史） |
| 6 | 面积 | 可写 `481/42,783=+1.12%`（全口径）、`458/41,945=+1.09%`（组合口径）、19 FF、`ltp=22` | 不能写「481 cells = 完整面积/硅面积」；不能换 μm²；不能把 cells 当功耗 | `40-area-20261104T094144.json`；`vdot.stat.json`；`vmac_only.stat.json` |
| 7 | 功耗 | 可写「cell 占比 +1.12%」；可写「tap 对每条 vimac 都在算、都 latch，无操作数隔离」；可写 Nanhu-vdot 的 FPGA +0.5% 作为方向性参照 | 不能写「功耗仅增 1.12%」「几乎不增功耗」；不能写「Nanhu +0.5% ⇒ 本设计 +0.5%」；不能给 mW 数字 | `VIMacU.scala:129-130,159-160`；`VdotReduce.scala:44`；`ALGORITHM.md:114`；arXiv:2409.00661 |
| 8 | 活动率/功耗工具 | 可写「OpenSTA `report_power` 需要 Liberty + 活动率（VCD/SAIF 或 `set_power_activity`，默认 0.1/0.5）」 | 不能写「已有可用活动率」；不能拿 `stage2/2.2-rtl/wave/` 的采样域 key VCD 当活动率证据 | OpenSTA Commands；`stage2/2.2-rtl/wave/vcd-summary-…probefix-20261106.txt`（窗口内 0 次翻转） |
| 9 | 跨口径比值 | 可写「同对象、同计数法、同配置」的比值：`B1/T_steady=6`、`B2/T_steady=9`（每点开销倍数）；`L_base_chain_per_instr/L_vdot≈1.33×`（每指令归一） | 不能写「16/4=4.0 是 latency 加速比」；不能把 `L_*` 与 `B1/B2` 相除；不能把不同 SEW/vtype 的链相减 | `report.md` §1「口径约定」；`perf_base_chain.c:20-30,48,55-56` |
| 10 | 可复现性 | 可写「两个独立作业 `142246`/`075552` 逐项同值」「8 轮中位数全 16」「三链 `mean=median`」 | 不能写「统计显著/置信区间」；不能写「已做 build 级重复」 | `20-full-20261103T142246.json`；`20-full-20261103T075552.json`；`91-b3-…log:5-13` |

---

## F. 并入说明

1. **整件插入 §4.10**：把 A/B/C 三节（`## A.` 起、到 `## D.` 之前的 `---` 为止）原文贴进 `stage3/3.3/report.md` 的 `### 4.10`（本次实读 `report.md:837`），标题层级改为 4.10.1–4.10.3。**不要**拆到 §2 与 §5——§5.1–§5.6 已被创新性/探索性支撑点占用，再插 5.5/5.6 会撞号。
2. **节号**：A/B/C 已按 `4.10.1 / 4.10.2 / 4.10.3` 编好；若编辑改用 `### 4.10.x` 以外的层级，正文内的 `4.10.x` 交叉引用需同步改。
3. **§8 待回填表**建议改两行：①「2 拍时序闭合」行现状补「`gen_probes.sh` 未建 + 无 Liberty/STA；昆山 Yosys 0.48 可用（`evidence/sta-toolcheck-20261106.txt`）」；②新增一行「功耗：未测（cell 占比 1.12% 不是功耗；Nanhu +0.5% 为 FPGA 参照）」。**2026-11-08 注**：① 已按新状态回填为「切段仍未运行；模块级 STA 已补做（代理工艺、预布局）」，本条的「无 Liberty/STA」只描述 2026-11-06 状态；② 功耗行仍**未测**，本轮 STA 不改变它（`report_power` 仍需活动率）。
4. **§9 用词核对**建议追加三条：不写「功耗仅增 1.12%」；不写「2 拍已收敛／22 级 ⇒ 满足 2 拍」；不写「中位数是 Agner/K&J 方法」。**注意否定语境**：本文件里这些短语只出现在「不写/禁止」句中，不要用裸 `grep -c` 判 0。
5. **不要动**：`report.md` 既有数字、`results/yosys/40-area-*.json`、RTL 源码。本文件只是正文来源与证据台账。
