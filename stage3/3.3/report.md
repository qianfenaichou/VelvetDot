# 3.3 延迟加速分析报告

> 项目：CIE 香山社区 · vdot.vv 自定义向量指令（SEW=8, LMUL=1, K=8 单结果）
> 团队：芯芯像绒（XinXiangXiangRong）
> 版本：XiangShan `913ddd3` / yunsuan `83059b5` / NEMU `a9dca53`（基线 pin 见 `versions.env`）。**例外（§4.13，P-2 重定时）**：该节实测跑在本机子仓 `repos/XiangShan/yunsuan` @ `8942811`（父提交 `83059b5`）上，改动只以 `patches/0005-…` 形式留档、**不在公开仓 9 个基线 patch 内**；报告其余各节的数字不来自该改动（§4.13 首注与 §4.13.5 已逐条披露）。
> 数据源（当前口径，30 例整份 `--full`）：`results/difftest/20-full-20261103T142246.json`（`metrics[]`，作业 `126676734`，`status=通过`、30/30）
> 数据源（同值复核，4 例 T5+G0）：`results/difftest/20-full-20261103T075552.json`（`metrics[]`，作业 `126646321`）
> 数据源（旧口径，仅历史对照）：`results/difftest/20-full-20261102T000517.json`（`metrics[]`，作业 `126542079`）
> 日期：2026-11-03（2026-11-02 首稿；T5 ΔL 三链实测改写 §1/§3/§4/§7；2026-11-04 补 30 例整份数据源，数值不变；2026-11-04 再补基线链 `L_base_chain` 实测（作业 `126750763`）与形式/面积重跑（`126751660`/`126752216`），改写 §4.3/§5/§7；**2026-11-04 本用例 full 尺度闭合**：作业 `126762127` 跑通 8×2000 + 阶梯链 + B3（`verdict=ALL_OK`、`scale=full`），§4.1/§4.3/§6/§7 按「min / full」分列改写（口径为**内部自设**，非官方口径）；同日补 2.2 lint（作业 `126761068`）；**2026-11-04**：§4.1/§4.3/§7 按 full 实测复核，min/full 两口径分列标注（同值 16），阶梯链 24 与 B3 11 各自注明口径；**2026-11-06 创新与协同**：新增 §4.6–§4.12 外部专题小节与 §5.1–§5.6 创新性四项支撑点 + 软硬协同机制、§9 核对表（15 行）；**2026-11-06**：六件已全部定稿并原文并入（`llmbench`→§4.7、`dualchain`→§4.8、`perf-slope`→§4.9、`methodology`→§4.10、`coverage`→§4.11、`case-expand`→§4.12），§5.5 按双链实验改写为「机制归因已确认、4 cyc 数值未独立复现」，§4.11/§4.12 按 extra 129/129 终态与 `case-expand.md` 16:33 修订版更新，§8.1 改为小节来源明细与 sha256 核对；**2026-11-07 修订**：按 R1/R2/R3 修后最终版替换 §4.7（`llmbench.md`）/§4.8（`dualchain.md`）/§4.9（`perf-slope.md`）、按 R6 定稿版替换 §4.11（`coverage.md`，源文件声明「以本文件为准」），头注小节归属逐件核对一致；§4.12 就地微调 2 处（「我方独有」改中性表述、复现命令 `<runid>` 落实为实测 runid）；§A.x 交叉引用重映射到 §4.11.x/§4.12.x；评分对应表补 `docx/02:91`（技术路径合理性 10 分）行；VecExceptionGen 行号 `:277→:280`（vstartIllegal）；编码检查口径改「阳性 3/3 + 反向 1/1」；§5.5/§8 与 §4.8 新口径对齐（当时按同窗 5.6/7.3 倍取代跨窗「7.5×」、废止「唯一变量」表述；**该比值已由本次 5.5/7.5 取代，见下**）；§9 核对表与计数按本版重跑；`evidence/t2-grep-check.txt` 按当前行号重生成；**2026-11-07 定稿**：按 13:11 三轴版替换 §4.8（`dualchain.md`，A/B/C 三口径分列 + M9/M10/M11 同口径对照，作业 `127142843`）、按 08:54 实跑版替换 §4.11（`coverage.md`，结构覆盖改为「实跑受阻、无数字」）、新增 `innovation-p2.md` 为 **§4.13**（§4.6 专题小节扩为七件，481→500 cells / 22→14 级 / DFF 19→38，`L_vdot=4` 不变）；§5 补 P-2 对应与 §5.5/§8 双链新数字（同窗 5.5/7.5 倍，M5/M8）；§9 核对表扩至 19 行并按本版重跑计数（`推算` 23、`未运行` 37、跨窗「7.5×」/「唯一变量」5 处）；**2026-11-08 报告同步轮**：§4.11.3/§4.12 的扩容用例数由 129 改为**实测 224**（`manifest.extra.tsv` 224 数据行；作业 `127194011` 224/224、8/8 criteria、`EXTRA_CROSSCHECK verdict=MATCH`；本地复跑 `crosscheck cases=224 problems=0`），30 例整份同轮 **exit=1 且零产物 ⇒ 记【未运行（无产物）】**（不写成通过），合计 **254 个镜像**（30 + 224）；§4.2/§4.3 挂 `perf-repeat` 4 次重复的跨重复中位数与极差（作业 `127196036`：`T_steady`=1/极差 0、`B1`=6/0、`B2`=9/0、`L_vdot`=4/0、`L_vadd`=3/0、`L_vmacc`=4/0），并写清 1.33× 的分子（4 次中位数）/分母（`L_base_chain`=16，另一作业 `126762127`）口径；§4.9 标明斜率本轮**未重测**；§5.6 挂 `co-sim.md`/`tri-consistency.md` 引用；§9 计数按本版重跑

---

## 1. 口径声明（先读这里，防误读）

本报告使用**九个互不可替代的性能口径行**（B1/B2 合并为一行两列；本次新增的 `L_base_chain` / `L_base_chain_ladder` / `B3` 已逐行登记）。它们不可互相替代；只有「同属 per-dot 周期」的两类可以相除：

| 口径 | 符号 | 定义 | 实测值 | JSON 路径与字段 |
|---|---|---|---|---|
| 依赖延迟（vadd 参照） | `L_vadd` | `vadd.vv v10,v10,v1` RAW 依赖链（`vd==vs2`），2000 次逐次 `rdcycle` 取差后取**中位数**（`design/verify/cases/perf_vadd.c:41-43,74-77`） | **3** cyc/依赖步 | `results/difftest/20-full-20261103T142246.json` → `metrics[]` 中 `name=L_vadd, case_id=perf_vadd`（`{"name":"L_vadd","value":"3","case_id":"perf_vadd"}`） |
| 依赖延迟（vmacc 参照） | `L_vmacc` | `vmacc.vv v10,v1,v10` RAW 依赖链（`vd==vs2`），同规模同计数（`design/verify/cases/perf_vmacc.c:41-43,79`） | **4** cyc/依赖步 | 同上 → `name=L_vmacc, case_id=perf_vmacc`（`{"name":"L_vmacc","value":"4","case_id":"perf_vmacc"}`） |
| 依赖延迟（本指令） | `L_vdot` | `vdot.vv v10,v10,v1` RAW 依赖链（`vd==vs2`），同规模同计数（`design/verify/perf/perf_vdot.c:40-43`） | **4** cyc/依赖步 | 同上 → `name=L_vdot, case_id=perf_vdot`（`{"name":"L_vdot","value":"4","case_id":"perf_vdot"}`） |
| 背靠背吞吐 | `T_steady` | 8 个独立 `vd`、4000 条背靠背 vdot、循环内零 `vsetvli`，整段 `rdcycle` 相除 | **1** cyc/dot | 同上 → `name=T_steady, case_id=perf_vdot`（`{"name":"T_steady","value":"1","case_id":"perf_vdot"}`） |
| 装载+执行序列 | `T_kernel` | 1 条 vdot + `vsetvli`/`2×vle8`/`vmv.x.s` 的完整序列（仅含 1 个 dot） | **290** cyc | 同上 → `name=T_kernel, case_id=perf_vdot`（`{"name":"T_kernel","value":"290","case_id":"perf_vdot"}`） |
| 基线每点开销 | `B1` / `B2` | 组合指令序列单 dot 整段序列的每点开销（**新口径**：`e32,m2` + 可分辨数据，见 §4.4） | **6 / 9** cyc/dot | `results/difftest/20-full-20261103T142246.json` → `metrics[]`（`case_id=perf_base`）；同值见 `20-full-20261102T000517.json` |
| 基线组合链延迟（**内部自设口径**，配置外提） | `L_base_chain` | 3 条串行指令 `vwmul.vv→vwadd.vx→vredsum.vs` 同 `vd` RAW 链，**全程 e16,m1、循环内零 `vsetvli`**（配置在计时窗外）；8 轮×2000=16000 合并样本的中位数 | **16** cyc/链步（归一每指令 `16/3≈5.33`，脚本整数打印 `5`；**min 口径 4×500=2000 样本同为 16**，见 §4.3） | `results/difftest/b3/91-b3-20261104T115624.log` → `PERF L_base_chain` / `VDOT_METRIC L_base_chain 16` / `VDOT_METRIC L_base_chain_per_instr 5`（作业 `126762127`） |
| 基线阶梯链延迟（含配置） | `L_base_chain_ladder` | 忠实 B2 形态：`e8→e16→e32,m2` 三段 SEW 不同 ⇒ 每点**含** 3 次 `vsetvli` 阶梯配置 | **24** cyc/链步（median；2000 样本） | 同一份 full 日志 `PERF L_base_chain_ladder` / `VDOT_METRIC L_base_chain_ladder 24` |
| 无归约上限（敏感性分析） | `B3` | 7 条计算 + 3 次配置的无归约序列，整段墙钟 / 点数；**只进敏感性分析、不作分母** | **11** cyc/op（2016 ops） | 同一份 full 日志 `PERF B3` / `VDOT_METRIC B3 11` |

> 上述三行的共同前提：**都是内部自设口径**（用例头注 `design/verify/cases/perf_base_chain.c:55-56` 明写「官方 `docx/02` 只要求『用已有向量指令组合实现』，未规定条数/延迟口径 ⇒ 本用例的任何数字都不得写成『官方口径』」；`design/ALGORITHM.md:189` 同口径把基线分母定义为「内部自设口径」）。`8 轮×2000` 只是本用例自设的测量尺度，**不是官方规定口径**。

**口径约定**：
- 三链统一 **VL=8**、统一「逐次 `rdcycle`、N=2000、去 16 次暖机、取中位数」的计数法（`perf_vadd.c:41-43`、`perf_vmacc.c:41-43`、`perf_vdot.c:40-43`），互为同一把天平。
- 三链的**读回视图不同**：`perf_vadd.c` / `perf_vmacc.c` 在 e8/vl=8 视图下用 `vmv.x.s` 读 lane0 自检，`perf_vdot.c` 用 e32 读回（32 位标量结果）。读回视图只影响自检取数，不影响 `rdcycle` 依赖链计时；三链可比性由同 VL=8 / SEW=8 / 同计数法保证。
- `cycles_per_op=` 是 **median 的别名**，不是均值；均值另列 `L_vadd_mean` / `L_vmacc_mean` / `L_vdot_mean`（`metrics[1]/[4]/[7]`，均为 3 / 4 / 4）。旧版整段循环口径另列 `L_*_loop`（`metrics[2]/[5]/[8]`，5 / 6 / 6）。
- `T_steady` 是**背靠背吞吐**（per-dot 周期），`B1/B2` 是**每点开销**（per-dot 周期）——这两类同属「每 dot 周期」，可以相除；**延迟 `L_*` 不能与它们相除**（§1 口径约定：延迟与吞吐不可混用）。
- `T_kernel=290` 只含 1 个 dot，是「装载+执行+读回」的序列开销，**不是单指令延迟**，也不代表吞吐。
- `metrics[6]`（`L_vdot`）与 `metrics[8]`（`L_vdot_loop`=6）是**两个不同口径**：前者是中位数（主指标），后者是旧版整段墙钟相除（仅历史对拍用），不得混引。

## 2. 方法学

- 测量平台：华东一区【昆山】超算，`kshcnormal` 分区（计算节点 32 vCPU / 126,500 MB ≈ 123.5 GiB）。**主数据源 = 作业 `126676734`**（`results/difftest/20-full-20261103T142246.json`：`started_at=2026-11-03T14:22:46+0800`、`ended_at=2026-11-03T14:51:47+0800` ⇒ 实际墙钟 **29:01**，`30/30` 用例，`status=通过`，9/9 criteria 达标）；**同值复核 = 作业 `126646321`**（`results/difftest/20-full-20261103T075552.json`：`4/4` 用例、`status=通过`，墙钟 10:02）。两次的 `L_vadd/L_vmacc/L_vdot/T_steady/T_kernel` 逐项相同。
- 仿真器：XiangShan `build/emu`（Verilator 5.053，`EMU_THREADS=8`，`results/emu/10-build-20261103T032307.log:4`）；NEMU `riscv64-xs-kmhv2-ref_defconfig` 参考模型（同日志 `:7`）作为 difftest 参照。
- 计数器：`rdcycle`，逐次读取 + 直方图中位数（`HIST_MAX=4096`，越界计入 `over` 并打印，不静默截断）。
- 数据采集：`core-package/scripts/20-run-difftest.sh --full`（`126676734` 用 30 例整份 `manifest.tsv`；`126646321` 用 4 例 `manifest.t5g0.tsv`）的 `perf` 用例；用例自报 `VDOT_METRIC <name> <value>` 行，被脚本收进 JSON 的 `metrics[]`（`core-package/scripts/20-run-difftest.sh:282-297`）。
- 复现命令：`sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 core-package/scripts/20-run-difftest.sh --full --manifest ~/core/test/manifest.tsv`（30 例整份，`126676734` 用这条；`126646321` 用的是 4 行 `manifest.t5g0.tsv`）。
- 用例自检（防「假通过」）：`PERF_VADD verdict=ALL_OK vl=OK chain=OK chain_alt=OK alt_differs=yes chain_loop=OK`；`PERF_VMACC verdict=ALL_OK vl=OK chain=OK chain_alt=OK alt_differs=yes chain_loop=OK`；`PERF_VDOT verdict=ALL_OK enc=OK vl=OK raw=OK alt=OK alt_differs=yes loop=OK steady=OK kernel=OK`（`results/difftest/perf_{vadd,vmacc,vdot}.20261103T075552.log` 末行）。
- 运行级判据：`126676734` 的 `cases_pass=达标（30/30）`、`metrics_three=达标`、`t5_delta_latency=达标`、`no_empty_green=达标`（自检串 21/21、G0 捕获 1/1）、`regression_delta=0`（`results/difftest/20-full-20261103T142246.json` 的 `criteria[]`，9/9 达标）；`126646321` 的同类判据为 4/4、自检串 3/3（`20-full-20261103T075552.json`）。

## 3. vdot 延迟与吞吐（当前口径，VL=8）

### 3.1 依赖延迟：`L_vdot = 4 cyc`

`L_vdot` 是 `vdot.vv v10,v10,v1`（`vd` 同时是 `vs2`，相邻两次是真 RAW 依赖）的端到端延迟，实测 **4 周期/依赖步**（`results/difftest/20-full-20261103T142246.json` → `metrics[]`，`case_id=perf_vdot`；同批 `L_vdot_mean=4`、`L_vdot_loop=6`，后者为整段墙钟口径、非主指标。同值见 `20-full-20261103T075552.json` 的 `metrics[6]/[7]/[8]`）。

### 3.2 ΔL 三链：tap 对端到端延迟贡献 0

同一把天平上的三链（`142246` 的 `metrics[]`：`perf_vadd` / `perf_vmacc` / `perf_vdot`；与 `075552` 的 `metrics[0]/[3]/[6]` 逐项同值）：

| 链 | 指令 | 每步延迟（median） | 相对 `L_vadd` |
|---|---|---|---|
| `L_vadd` | `vadd.vv v10,v10,v1` | **3** cyc | 基准 |
| `L_vmacc` | `vmacc.vv v10,v1,v10` | **4** cyc | +1 cyc（乘累加路径固有） |
| `L_vdot` | `vdot.vv v10,v10,v1` | **4** cyc | +1 cyc |

- **`L_vdot == L_vmacc = 4`** ⇒ vdot 的 8×8 乘法 + 19 位归约树 + tap 加法**没有给端到端依赖延迟增加任何一拍**，相对 vmacc 的增量 **ΔL = 0**。这是判据「tap 对端到端延迟贡献 0」的实测落地。
- **`L_vmacc − L_vadd = 1`** ⇒ 这 1 拍属于乘累加路径（vmacc 相对 vadd），**不是 vdot 引入的**；vdot 完全继承了 vmacc 的延迟。
- 脚本判据 `criteria[t5_delta_latency] = 达标`，`actual = "L_vadd=3 L_vmacc=4 L_vdot=4 (ΔL_mv=1)"`（`results/difftest/20-full-20261103T142246.json`；`075552` 同值）。
- 独立复现：作业 `126631414`（`results/difftest/20-full-20261103T033328.json`，3 例）产出**完全相同**的三数（`metrics[0]=3`、`metrics[3]=4`、`metrics[6]=4`，`t5_delta_latency=达标`）；该次整体 `status=未运行` 仅因清单缺 g0 反例（`no_empty_green=未运行`），数值本身与 `126646321` 一致 ⇒ 两个独立作业互证。

**与旧口径的差异（必须说明）**：2026-11-02 的 `L_vdot=6`（`results/difftest/20-full-20261102T000517.json` → `metrics[0]`）是 **VL=16 + 整段均值口径**（旧 `perf_vdot.c` 用 `li t0,16`、`cyc/N`）；本次统一 **VL=8 + 中位数**后为 **4**。两个数不是同一把天平，**不可相减、不可互相替代**（§1 的口径裁定）。

### 3.3 背靠背吞吐：`T_steady = 1 cyc/dot`

8 个独立目标寄存器、4000 条背靠背 vdot（循环内零 `vsetvli`）时，每个 dot 平均 **1 周期**（`metrics[9]`）——即每周期可发射并完成一条 vdot。这是「本指令」的吞吐上限；与基线每点开销的对比见 §4.2。

### 3.4 装载+执行序列：`T_kernel = 290 cyc`（仅 1 dot）

`T_kernel` 是「配置 vtype → 装载 8 字节 → vdot → 读回结果」的完整序列（`metrics[10]`）。它反映**真实 kernel 中单次点积的总体开销**，绝大部分是向量装载与配置指令，vdot 本身只占 1 个周期。旧口径为 289（`results/difftest/20-full-20261102T000517.json` → `metrics[2]`）；差 1 拍属 VL/镜像变更后的重测值，**以 290 为当前值**。

## 4. 与基线实现的对比

### 4.1 基线定义（B1 / B2 / B3）

| 代号 | 基线序列（B1/B2 源在 `design/verify/perf/perf_base.c`；B3 源在 `design/verify/cases/perf_base_chain.c` 的 `B3_ONCE()`） | 每点开销 |
|---|---|---|
| B1 | `vwmul.vv` + `vwredsum.vs`（最保守下界，2 条向量计算） | 6 cyc/dot（新口径实测，`142246`） |
| B2 | `vwmul.vv` + `vwadd.vx`（widen 到 32）+ `vredsum.vs`（3 条向量计算） | 9 cyc/dot（新口径实测，`142246`；`b2_not_vl4=yes`、`discriminates=yes`） |
| B3 | 无归约上限（只进敏感性分析，不作分母） | **已实测（本用例 full 尺度 `scale=full`，仅敏感性分析）**：`B3 = 11 cyc/op`（2016 ops、`result=0x00000008` = 期望、`not_vl4=yes`；作业 `126762127`，`results/difftest/b3/91-b3-20261104T115624.log`）。**不作分母、不与 `L_base_chain` 或 `L_base_chain_ladder` 相减**；需注意计数法与 B1/B2 不同（B3 对 2016 次全部计时、不丢 16 次暖机；B1/B2 是 N=2000 无暖机，见 §4.3 诚实边界 ⑥），故只并列、不做同法差值 |

> **B2 的忠实阶梯形态（2026-11-04 full 口径实测）**：`L_base_chain_ladder = 24 cyc/链步`（`e8→e16→e32,m2` 三段 SEW、每点**含** 3 次 `vsetvli` 阶梯配置；2000 样本、`cycles=47843`、median 24、mean 23、`chain=OK`；作业 `126762127`，`results/difftest/b3/91-b3-20261104T115624.log:18-19`）。它是**含配置**的链延迟，与 `L_base_chain`（16，配置外提、循环内零 `vsetvli`）**不可相减、不可互替**，也不替代 B2 的 `9 cyc/dot` 每点开销口径（三者是三种不同测量）。只作「含配置的忠实基线形态」，不作分母。

### 4.2 吞吐口径对比（可相除，分母已声明）

| 口径 | vdot | B1 | B2 | 比值 |
|---|---|---|---|---|
| 背靠背吞吐 `T_steady`（`metrics[9]` = 1 cyc/dot） | 1 | 6 | 9 | **每点开销倍数 6 / 9**（`B1 ÷ T_steady` = 6÷1、`B2 ÷ T_steady` = 9÷1；即「基线每 dot 周期 ÷ vdot 每 dot 周期」）。**这是吞吐口径的倍数，不是加速比**——本报告**仅有的**加速比数字是 §4.3 的每指令归一 `1.33×`（打印整数口径 `1.25×`） |

**结论（吞吐口径）**：以 `T_steady=1` 为 vdot 吞吐、`B1=6` / `B2=9` 为基线每点开销，vdot 的每 dot 周期是基线每点开销的 1/6（B1）与 1/9（B2），即吞吐口径的**每点开销倍数 6 / 9**（比值式 = `B1÷T_steady` = 6、`B2÷T_steady` = 9）；该式**不写作「快 N 倍/加速比」**。三个数字同属「每 dot 周期」类计数，比值可复现（`T_steady`：`results/difftest/20-full-20261103T142246.json` → `metrics[]`；B1/B2：同份 `metrics[]` 的 `case_id=perf_base`，新口径；同值另见 `20-full-20261103T075552.json` 与 `20-full-20261102T000517.json`）。

**该比值不是 latency 加速比**：`T_steady` 是背靠背吞吐，`B1/B2` 是单 dot 整段序列的每点开销，二者都不含依赖链等待；把该比值标成「延迟加速」是把两种口径混用（§1 口径约定第 ① 条）。延迟口径的结论见 §4.3。

**跨重复复测（2026-11-08，作业 `127196036`，4 次重复）**：4 个用例各起 **4 个独立 emu 进程**（`$EMU --no-diff -i <bin> --max-instr=200000000`），跨重复中位数与极差为 `T_steady` **1**（1,1,1,1；极差 **0**）、`B1` **6**（6,6,6,6；极差 0）、`B2` **9**（9,9,9,9；极差 0）；16/16 次 `rc=0`、`HIT GOOD TRAP=1`、`ABORT=0`、`HIT BAD TRAP=0`、各用例 `PERF_* verdict=ALL_OK`，9/9 criteria 达标（`status=通过`）。**分母口径（与 §4.1 同一套，不另立）**：`T_steady` 是背靠背吞吐（8 个独立 `vd`、4000 条 `vdot`、循环内零 `vsetvli`，整段 `rdcycle` 相除），`B1/B2` 是 `design/verify/perf/perf_base.c`（`e32,m2`、VLMAX=8）单 dot 整段序列的每 dot 周期；三者同属「每 dot 周期」类，故 `B1÷T_steady=6÷1=6`、`B2÷T_steady=9÷1=9` 仍是同口径比值，**不是 latency 加速比**。证据：`results/difftest/perf-repeat/99-perf-repeat-4x-20261108.summary.tsv`（13 行逐指标 `values/median/min/max/range`）、`.json` 的 `criteria[]` 与 `runs[].raw_perf_lines`。

### 4.3 延迟口径对比（T5 ΔL 三链 + 基线组合链）

| 对比 | 实测 | 出处 |
|---|---|---|
| `L_vdot` vs `L_vmacc` | 4 vs 4 ⇒ **ΔL = 0** | `results/difftest/20-full-20261103T075552.json` → `metrics[6]` / `metrics[3]` |
| `L_vdot` vs `L_vadd` | 4 vs 3 ⇒ +1 cyc | 同上 → `metrics[6]` / `metrics[0]` |
| `L_vdot` vs 基线组合序列的**依赖链**（**full 口径**：本用例 full 尺度 8 轮×2000 = 16000 样本、`scale=full`） | `L_base_chain = 16`（3 指令链 `vwmul.vv→vwadd.vx→vredsum.vs`，8 轮中位数一致；`rounds_agree=yes`、`finals_distinct=yes`）→ 归一 `L_base_chain_per_instr = 16/3 ≈ 5.33`（脚本打印整数 `5`）；对 `L_vdot = 4` ⇒ **每指令 1.33×**（打印整数口径 1.25×） | `results/difftest/b3/91-b3-20261104T115624.log`（作业 `126762127`，2026-11-04 11:56:24→13:26，镜像 `perf_base_chain.bin` md5 `8c5538c9…`，`verdict=ALL_OK`、`samples=16000`、`rounds=8`、`scale=full`；机器抽取摘要 `91-b3-20261104T115624.summary.json`） |
| 同上（**min 口径**：4 轮×500 = 2000 样本，历史对照；`scale=min` ⇒ 阶梯链/B3 段**未执行**） | `L_base_chain = 16`（同链、同 VL=8、**全程 e16,m1**；样本数少 8 倍，数值与本用例 full 尺度一致） | `results/difftest/b3/91-b3-20261104T092457.log`（作业 `126750763`，`samples=2000`、`rounds=4`、`scale=min(ladder/B3_skipped)`） |
| 阶梯链 `L_base_chain_ladder`（**每点含 `vsetvli` 配置**，本用例 full 尺度） | `24 cyc/链步`（median；2000 样本、`cycles=47843`、mean 23、min 6、max 25；`chain=OK`） | 同一份 full 日志 `PERF L_base_chain_ladder` / `VDOT_METRIC L_base_chain_ladder 24` |
| B3（**只进敏感性分析**，本用例 full 尺度） | `B3 = 11 cyc/op`（2016 ops、`cycles=22457`、`result=0x00000008` = want、`not_vl4=yes`） | 同一份 full 日志 `PERF B3` / `VDOT_METRIC B3 11` |

**min / full 两口径同值（分列，不合并）**：`L_base_chain` 在 **full 口径（16000 样本）** 与 **min 口径（2000 样本）** 都是 **16 cyc/链步**（`rounds_agree=yes`、8/4 轮中位数全 16；两处均为 `VL=8`、全程 `e16,m1`、配置外提）。**本报告当前引用值取 full 口径**；min 口径只作同链同 VL 的交叉核对——两者是同一链条、同一计数法，仅样本规模差 8 倍，**不可当作两次独立测量求平均**，也不与 `L_base_chain_ladder`（24，含配置）相减。

**跨重复复测与 1.33× 的分子/分母（2026-11-08，作业 `127196036`，4 次重复）**：`L_vdot` 在 4 个独立 emu 进程上实测 `4,4,4,4` → **跨重复中位数 4、极差 0**；同批 `L_vadd` `3,3,3,3`（中位数 3、极差 0）、`L_vmacc` `4,4,4,4`（中位数 4、极差 0），故 ΔL(`vdot−vmacc`)=0、ΔL(`vdot−vadd`)=+1 cyc 在本轮复现。**分子口径**：`L_vdot` = 本轮 4 个进程的**跨重复中位数**（每个进程内 N=2000、去前 16 次暖机、取进程内中位数）；**分母口径**：`L_base_chain_per_instr = L_base_chain/3 = 16/3 ≈ 5.33`，其中 `L_base_chain = 16 cyc/链步` 来自**另一作业** `126762127`（8 轮×2000=**16000 合并样本**的中位数，链 = 3 条串行 `vwmul.vv→vwadd.vx→vredsum.vs`、全程 `e16,m1`、**配置外提**、循环内零 `vsetvli`），**本轮不重测分母**。⇒ `(16/3)/4 = 1.333333`，4 次重复逐次同值（极差 0），写作 **1.33×**（整数打印口径 `5/4 = 1.25×`）。证据 `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.{json,summary.tsv}`。**限定**：`design/ALGORITHM.md:212` 的报告级口径要求「同配置再跑 ≥5 次取中位数」，本轮 4 次属**补充证据、不替代该条**（`sections/perf-repeat.md` §0.5 第 5 条）；4 次的极差 0 只说明本批 4 个 emu 进程的模型周期完全一致，**不是置信区间**。

**口径约定（三条）**：① `L_base_chain`（**全程 e16,m1**、配置**外提**、循环内零 `vsetvli`）与 `L_base_chain_ladder`（`e8/e16/e32` **阶梯** SEW、每点**含** `vsetvli`）**不可相减、不可互替**——两者 vtype 与数据通路宽度都不同，**不做差值归因**（用例头注 `perf_base_chain.c:40-48` 明写「两个数不可相减」）；② `B3` 是「无归约上限」的第三套基线，**只进敏感性分析、不作分母、不与任何链相减**；③ 仅允许与单指令 `L_vdot` 相除的是归一量 `L_base_chain_per_instr = L_base_chain/3`（链内 3 条串行指令），原始 `16/4 = 4.0×` 是跨口径，不写成 latency 加速比。

**结论（延迟口径）**：在同一 `VimacCfg`、同一 VL=8、同一计数法下，**vdot 的端到端依赖延迟等于 vmacc（4 cyc），比 vadd 多 1 cyc，且 tap 数据通路贡献 0 拍**——即「专用单元不引入额外延迟」是实测结论，不是设计声明。**基线组合链已按本用例 full 尺度实测（内部自设口径，非官方口径）**：作业 `126762127` 的 `L_base_chain=16 cyc/链步` 是 3 条串行指令（`vwmul.vv→vwadd.vx→vredsum.vs`）的 RAW 链延迟（VL=8、**全程 e16,m1**、循环内零 `vsetvli`、**8 轮×2000=16000 合并样本**的中位数；8 轮 `median=16` 全一致、`rounds_agree=yes`、`finals_distinct=yes`）。按用例仅允许的归一方式 `L_base_chain_per_instr = L_base_chain/3 ≈ 5.33`（`design/verify/cases/perf_base_chain.c:25-30`；脚本整数打印为 `5`），对单指令 `L_vdot=4` 的每指令延迟比为 **5.33/4 ≈ 1.33×**（若引用打印整数 `5` 则为 1.25×）。原始 `L_base_chain/L_vdot = 16/4 = 4.0×` 是「3 指令链 vs 单指令」的跨口径比值，**本报告不把它写成 latency 加速比**。阶梯链 `L_base_chain_ladder=24` 与 B3=`11` 按上表口径分别只作「含配置的忠实基线形态」与「敏感性分析」，**不与 `L_base_chain` 相减**。

**诚实边界**：① 上述 1.33× 是**每指令**归一后的比值（`L_base_chain/3` 对 `L_vdot`），不是每 dot 端到端比值；② full 尺度镜像 `perf_base_chain.bin` 本次为新增 `scale=full` 输出字段而重建（源码仅改一行 printf 格式串：`design/verify/cases/perf_base_chain.c` 的 `#else` 分支加 `scale=full`；改动前源码用同一 14.2.0 工具链重建可逐字节复现旧镜像 `eede780e…`，改动后 md5 `8c5538c9…`，其余 4 个 perf 镜像逐字节不变）；③ 计时为 emu 内的 `rdcycle`，`over=0`（无直方图越界）；④ 全量作业在**独占整节点**（`-n 32`，节点 `<node>`；`<node>` 为节点名占位）下完成（sacct：`COMPLETED`、`Elapsed=01:30:18`）；此前 `-n 8` 的共享节点作业 `126758062` 在 1:02:30 内只走完 round 0/1 即被取消（sacct `CANCELLED+`；`results/difftest/b3/91-b3-20261104T105245.log` 实读只有 2 条 `chain_free_round` 行）⇒ 按 sacct 实数复算：完成作业 `5418 s/(8×2016+2×2016+2016=22176 iter)=0.244 s/iter`，取消作业 `3750 s/(2×2016=4032 iter)=0.930 s/iter` ⇒ **慢 3.81×**（该倍数是「已完成批次/耗时」的粗算，不含初次暖机与 ladder/B3 段的差异，只作量级说明）。取消的直接原因是操作者观察到同节点另有 VASP 作业占核（`srun --overlap ps` / `/proc/loadavg`），但**该观察没有落盘进仓库**——本报告只把「共享节点慢、被取消」记为有据事实，「VASP 占核」记**操作者口述、未留日志**（见 `results/difftest/b3/provenance/91-b3-provenance.txt` §P4）；⑤ **测量异常（必须披露）**：8 轮逐轮 `min` 并非均匀——**round 0/1/2 的 `min=3`，round 3–7 的 `min=16`**（`results/difftest/b3/91-b3-20261104T115624.key.txt:2-9` 逐行实读：`round=0/1/2 … min=3`，`round=3..7 … min=16`）。前 3 轮出现了远低于中位数的样本（疑似宿主调度/中断或初次 cache 冷态），但**8 轮中位数全为 16**（`rounds_agree=yes`），故中位数本身不受影响；`min=3` 只说明该口径存在低端离群，**不能**把 16 当作「最坏情况/上界」，也不能把 3 当作可复现延迟。这是 16 cyc 这一中位数的可信度边界（`design/ALGORITHM.md:213` 的失真点口径要求写明）；⑥ **B3 的计数法与 B1/B2 不同**：B3 循环（`design/verify/cases/perf_base_chain.c:520-525`）对 `N_ITER=2016` 次**全部计时**、**不丢** `N_WARMUP=16` 暖机样本（对比 `cf_measure`/`ld_measure` 都有 `if (i < N_WARMUP) continue;`），`samples` 记为 2016；而 B1/B2（`design/verify/perf/perf_base.c:121-131`）是 `N=2000`、**无暖机丢弃**。两者虽同属「每点开销」类，但**暖机处理不同**，故 §4.1/§4.3 只把 B3 并列进敏感性分析、不与 B1/B2 做「同法同口径」的差值或比值。

### 4.4 B1/B2 的新口径实测与旧口径保留

**新口径（当前引用值）**：`B1=6` / `B2=9`（`results/difftest/20-full-20261103T142246.json` → `metrics[]`，`case_id=perf_base`；用例日志 `PERF B1: ops=2000 cycles=12002 cycles_per_op=6 result=0x00000008 want=0x00000008 match=OK`、`PERF B2: ops=2000 cycles=19335 cycles_per_op=9 result=0x00000008 want=0x00000008 not_vl4=yes match=OK`），用例汇总行 `PERF_BASE verdict=ALL_OK B1=OK B2=OK b2_not_vl4=yes discriminates=yes want=0x00000008 want_vl4=0x00000012`。源码为 `e32,m2`（VLMAX=8）版，`stage3/3.2-baseline/sources/perf_base.worktree.c` 与 `design/verify/perf/perf_base.c` `diff -q` 无差异。

**旧口径（只作历史对照，不再引用为当前值）**：`results/difftest/20-full-20261102T000517.json` → `metrics[3]`/`metrics[4]` 也是 `6`/`9`，但来自 `perf_base.c` 的 HEAD 版（`c611d43`）：B2 第 3 段是 `e32,m1`（VLMAX=4，`avl=8` 被钳到 4 ⇒ 只归约前 4 lane），且旧数据下前 4 积和 = 全 8 积和 = 10（`result=0xA` 无法分辨 vl=8 与 vl=4）。**两个 6/9 数值相同但含义不同**：引用时必须注明是新口径（`142246`）还是旧口径（`000517`），详见 `../3.2-baseline/README.md` §3。

### 4.5 内核级指令数/吞吐对比（清单外独立测量，2026-11-06 新增）

> **口径约定**：本小节只报「**指令数对比 / 吞吐对比**」，**不是延迟加速比、不是官方口径**；分母固定为**未融合 RVV 序列**（判据串里 `denom=unfused_rvv_seq` 固定）。比值一律写成裸比值 `N_base/N_vdot`、`cyc_base/cyc_vdot`。
> **测量对象**：同一 8×int8 点积内核的两个版本——BASE = `vwmul.vv→vwadd.vx→vredsum.vs`（3 条向量计算指令，**不融合**）；VDOT = `vdot.vv` 单指令。两版本共用同一条装载/配置序列，**静态指令数差 = 纯计算段差**。

| 口径 | BASE | VDOT | 裸比值 |
|---|---|---|---|
| **静态指令数**（objdump，`[<*_kernel>, <*_end)` 逐条计数） | **18** | **11** | `18/11 = 1.636…`（脚本整数打印 `1.63`） |
| **动态指令数**（`minstret`，三点差分 route1：逐轮**原始增量**取中位数，再除以 step） | **18** | **11** | 同静态，逐值相等（静态↔动态交叉核对成立） |
| **动态拍数**（`mcycle`，三点差分 route1 的逐轮商**中位数**） | **16** | **7** | `16/7 = 2.285…`（脚本整数打印 `2.28`） |
| 动态拍数（**均值口径**，另算，非主指标） | 15 | 7 | `15/7 ≈ 2.143`（比中位数口径低 **6.25%**（`(16/7−15/7)/(16/7)`）；`base` 逐轮商在 15/16 间跳） |

- **数据源**：作业 `126986882`（`results/difftest/kernel/run-20261106T053316/`）与独立复跑 `126989295`（`run-20261106T060159/`），两批四数 `18/16/11/7` **逐值相同**；判据 `KERNEL_CMP verdict=ALL_OK`、`static_xcheck` 两版本 `OK`、`HIT GOOD TRAP` 1 次、`ABORT`/`HIT BAD TRAP`/`MISMATCH` 均 0。每版本 2400 次内核调用（≥2000）。
- **样本口径**：**估计量来自 10 轮批间差分（8 轮有效、2 轮暖机不计）**，不是 2400 个逐次独立样本的统计 —— 后者在本 OoO 核上已被两次实跑证伪（`mcycle`/`minstret` 不在有序读 CSR 白名单，CSR 读可与内核体重排）。调用次数 2400 是**数量硬要求**，不是统计样本数。
- **route2 披露（不作判据）**：两批日志均 `route1_base=18 route1_vdot=11 route2_base=17 route2_vdot=11`（`route2_minus_route1_base=-1`）。route2 两端都含内核，尾端缺口使其偏离；**route1 是唯一可用的估计量**。
- **诚实边界**：① 这是**内部自设口径**的内核级对比，用例不进 `design/verify/cases/manifest.tsv`（冻结 `a90d1071…`、30 行），走 `core-package/scripts/93-run-kcmp.sh` 单例独立测量；② 两个数（静态 18/11、动态 16/7）是「每次内核调用」的归一量，**不与 §4.2 的 B1/B2（每点开销 6/9）相除或互替**——三者是三种不同测量（B1/B2 是单 dot 整段序列、本节是 8-lane 内核含装载/配置/读回）；③ 拍数取中位数（日志 `cyc_med=16 cyc_mean=15 cyc_min=15 cyc_max=16`，**逐轮分布未打印**；均值 15 是 `b_sum/b_n` 的整数除法结果，故不能反推「几轮 16、几轮 15」），均值口径另列，**不得把两个比值混称**。

### 4.6 外部专题小节（七个，§4.7–§4.13）

> 本节七份外部小节均位于 `stage3/3.3/sections/`，本报告只读引用、不改其内容；**七件已全部定稿**，按本表的小节**原文插入**（`case-expand.md` 按 16:33 修订版；**2026-11-07 修订**：`llmbench`/`dualchain`/`perf-slope` 按 R1/R2/R3 修后版替换 §4.7/§4.8/§4.9，`coverage.md` 按 R6 定稿版替换 §4.11；**2026-11-07 定稿**：`dualchain.md` 按 13:11 三轴版替换 §4.8、`coverage.md` 按 08:54 实跑版替换 §4.11、`innovation-p2.md` 新增为 §4.13——其源文件声明「正文与快照元数据以本文件为准」，本次照此执行）。定稿状态以 `ls -l stage3/3.3/sections/` 实读为准（小节来源明细、mtime 与源文件 sha256 见 §8.1）。

| 小节 | 外部文件（只读） | 主题（按文件名与来源口径） | 对应小节 | 状态（2026-11-07 定稿） |
|---|---|---|---|---|
| §4.7 | `sections/llmbench.md` | 真实 LLM 算子复核：Q8_0 block = 4×K=8 子块，三轴（指令数/拍数/内核吞吐）、主分母 `unfused_rvv_seq` | 见 §4.7（**已并入**：4.7.0–4.7.11） | **2026-11-07 00:37 整理版（定稿版 19,274 B / 243 行）** |
| §4.8 | `sections/dualchain.md` | 依赖链双链实验：吞吐 / 依赖间隔 / T5-L **三口径 A/B/C 分列** + old_vd 机制归因 + M9/M10/M11 同口径对照（§5.5 机制归因的**确认依据**） | 见 §4.8（**已并入**：4.8.1–4.8.7） | **2026-11-07 13:11 三轴版（定稿版 26,389 B / 252 行）；作业 `127142843` 12/12 criteria** |
| §4.9 | `sections/perf-slope.md` | 性能斜率 / 标度分析 | 见 §4.9（**已并入**：4.9.1–4.9.7） | **2026-11-07 00:45 整理版（定稿版 22,151 B / 177 行）** |
| §4.10 | `sections/methodology.md` | 测量方法学（口径防御 / 时序边界 / 功耗边界） | 见 §4.10（**已并入**：4.10.1–4.10.3） | **13:57 首版 / 14:19 末次修订（定稿版 34,562 B / 221 行）；2026-11-07 复核零改动** |
| §4.11 | `sections/coverage.md` | 功能覆盖率（29 coverpoints × 30 例）与结构覆盖率（**实跑受阻、数字未运行**） | 见 §4.11（**已并入**：4.11.1–4.11.6） | **2026-11-07 08:54 实跑版（定稿版 19,306 B / 184 行）** |
| §4.12 | `sections/case-expand.md` | 用例矩阵扩展（`manifest.extra.tsv` **224 例**；2026-11-08 实测 224/224，见 §4.12.4） | 见 §4.12（**已并入**：4.12.1–4.12.5） | **14:20 首版 / 16:33 内容修订 / 19:10 修订（定稿版 15,172 B / 139 行）；2026-11-07 复核零改动，正文就地微调 2 处见 §4.12 来源注；2026-11-08 按 224 例实测补记（源文件仍 129 例快照）** |
| §4.13 | `sections/innovation-p2.md` | P-2 跨拍 CPA 重定时（`(sum,carry)` 过 `fireS1` 边界）：481→500 cells / 22→14 级 / DFF 19→38，功能与延迟口径不变 | 见 §4.13（**已并入**：4.13.1–4.13.7） | **2026-11-07 13:52 定稿版（定稿版 19,045 B / 163 行）；四个验证面均达标、未触发回滚** |

> 并入约定三条：① 各节**原文插入**，不改数字、不改口径标签（仅 §4.11 的源内 `§A.x` 类交叉引用按小节编号重映射、§4.12 就地微调 2 处，均在各节来源注登记）；② 一节一号，小节号在定稿后也不重排，来源记录始终可机械核对；③ 定稿状态同时出现在本节表格末列与 **§8.1「小节来源明细」**，并用源文件 sha256 固定「并入的是哪一版」。**第七件（§4.13）与其它六件的性质差别**：它是**改 RTL 之后的新增实测**（P-2 patch），因此 481/22 仍是 §5 的面积基线，500/14 单列于 §4.13、不并入基线（源文件首注已披露公开仓不可复现该 patch 情形）。

### 4.7 `sections/llmbench.md`（**2026-11-07 00:37 整理版**）

> **来源**：`stage3/3.3/sections/llmbench.md`（定稿版 19,274 B、243 行，2026-11-07 00:37 整理版；sha256 `19c2f49e…`）。**并入方式**：按 §4.6 的编号约定整件插入，源文件 `## N.` 降级为 `#### 4.7.N`，正文与源文件一致（仅标题层级与用词统一；含其【实测】/【实读】/【未运行】标签与用词核对）；源文件头注的小节归属一致（标注 §4.7 小节）。**本节内「§N」均指 `4.7.N`。** 本版为 R2 口径修订后的最终版（「dot=K=8 子块」口径与三套单位并列、macc 臂 bug 轮作业号更正为 `127039889`、拍数拟合口径改 route1 `I(n)−I(0)`/2 有效样本上中位数、编码自检 vd=12、`vwadd.vx` 别名注），取代 2026-11-06 17:54 并入的旧版。

> 状态：**已实跑并复跑**（昆山作业 `127049777`，2026-11-06 17:07–17:21，节点 `<node>`（节点名占位）；复跑 `127051826`，
> 2026-11-06 17:23–17:45，`COMPLETED 00:22:12`、`ExitCode=0:0`、脚本 `status=通过` 9/9 criteria 达标）。
> **两次独立作业的全部数字逐值相同**（见文末「复跑」节）。
> 来源口径：BenchSpec 见 llama.cpp 的 `ggml_vec_dot_q8_0_q8_0`（`ggml-quants.c`）与 `block_q8_0` 定义；用例 `design/verify/cases/perf_llm_attn.c`；
> 金模型生成器 `design/verify/cases/gen_llm_attn.py`；运行脚本 `core-package/scripts/97-run-llm.sh`。

#### 4.7.0 口径声明（先读，防误读）

- **只报三轴**：静态指令数、动态拍数、内核吞吐。**不是**延迟加速比、**不是**官方 latency 口径、**不是**端到端 token/s。
- **主分母固定 `unfused_rvv_seq`**：每 K=8 子块 `vwmul.vv → vwadd.vx → vredsum.vs`（`design/ALGORITHM.md` §3.4 的定义）。
  `vwmacc_rvv_seq`（每子块 `vwmacc.vv + vwredsum.vs` 两条计算；累加器清零是 **body 级 9 条 `vmv.v.i`**，不是每子块 1 条）**只作敏感性**，两者不合并、不相除。
- **与 §4.3 的每指令 `1.33×` 分节、不相乘/不相除**：那是「`L_base_chain=16` 对 `L_vdot=4` 的依赖链归一」，
  本节是「Q8_0 attention tile 的批处理内核实测」。两者测量对象、口径、单位都不同。
- **emu ≠ 硅**：`mcycle`/`cycleCnt` 均为 Verilator 周期级仿真值，不是硅实测。
- 本节**不主张**对 llama.cpp 上游宽核（每 32 元素 2 条计算指令）的优势；理由见 §6。

#### 4.7.1 算子、形状与数据

| 项 | 值 |
|---|---|
| 算子 | INT8 attention QK 点积（与 `ggml_vec_dot_q8_0_q8_0` 的 block 内层点积同形） |
| 形状 | 8 query × 8 key × head_dim=64 ⇒ 64 个 score、**512 个 K=8 chunk dot** |
| 数据布局 | 每行 2 × `block_q8_0 { uint16_t d; int8_t qs[32]; }`（34 B/block，`qs` 在 `+2`），68 B/行 |
| 子块偏移 | `2, 10, 18, 26, 36, 44, 52, 60`（**刻意非 8 字节对齐**，测非对齐 `vle8.v`） |
| 量化 scale | 全部 block `d = 0x3800`（fp16 = 0.5）⇒ 去量化因子 `d_q·d_k = 0.25` **精确**，score = isum/4 |
| 期望值 | `gen_llm_attn.py` 用 `vdot_model.dot_product()`（任意精度）与 `vdot_model.vdot_vv()`（19 位模型）**逐 chunk 交叉核对**后生成头文件；用例内无手写期望常量 |
| 数据边界 | key 行 7 的 chunk 0/1/2 = 全 -128 / 全 +127 / 交替极值 ⇒ S = +131072 / +129032 / **-130048**（19 位模型上下沿） |
| 二进制 | nexus-am flat binary，链接 `0x80000000` 起；正常退出走 `0x5006b`（emu 打印 `HIT GOOD TRAP`） |

**score 级不是单指令**：一条 `vdot.vv` 只完成一个 K=8 子块；一个 head_dim=64 的 score 需要 **8 条 vdot + 7 条 `vadd.vv`**。
本节的「dot」一律指一个 **K=8 子块**（8 个 int8 对、8 次乘加），不是 score。
**术语换算（防 8× 误读）**：1 个 K=8 dot = 8 个 int8 对；1 个 score = 8 个 K=8 dot = 64 个 int8 对。
用例日志字段 `dots=` 与拟合 x 计的是 **int8 对数**（`perf_llm_attn.c:111-113` 的 `LLM_DPS=64`，窗口内 `x = 64n`）；
本报告引用时一律换算并标明口径（cyc/dot、dot/cyc、int8 对/cyc 三套并列）。

#### 4.7.2 三个臂与静态指令数（objdump 逐条计数）

| 臂 | 分母名 | 每 K=8 子块 | 每 score（8 子块） | 静态总数 |
|---|---|---|---:|---:|
| A | **`unfused_rvv_seq`（主分母）** | `vsetivli`·2×`vle8.v`·`vwmul.vv`·`li`·`vsetvli`·`vwadd.vx`·`li`·`vsetvli`·`vredsum.vs`（+2 `addi` 取址） | 计算段 **24** | **100** |
| B | `vwmacc_rvv_seq`（敏感性） | `vsetivli`·2×`vle8.v`·`vwmacc.vv`·`li`·`vsetvli`·`vwredsum.vs`（+2 `addi`；body 级另有 13 条，见下） | 计算段 **16** | **85** |
| C | `vdot_seq` | `vsetivli`·2×`vle8.v`·`vdot.vv`（+2 `addi`） | 计算段 **8 vdot + 7 vadd = 15** | **58** |

- **macc 臂的清零是 body 级 9 条 `vmv.v.i`**（`perf_llm_attn.c:214-224`）：分别清 8 个独立宽化累加器
  （v4/v6/v8/v12/v14/v16/v18/v20）+ 链式累加器 v10，**不是每子块 1 条**。
  body 级合计 13 条（`vsetivli` + 9×`vmv.v.i` + `li` + `vsetvli` + `vmv.x.s`）；8 子块 × 9 条 + 13 = **85**（与 `N_macc=85` 一致）。
- **objdump 别名**：源里的 `vwadd.vx v6, v4, zero` 被 binutils 2.41 反汇编为别名 `vwcvt.x.x.v v6, v4`
  （同一编码 `0xc6406357`，见 `results/difftest/llm/llm_attn_static_base.txt:10`）；逐条列表以 objdump 输出为准，指令种类仍按 `vwadd.vx` 计。
- **计数范围**：`[<llm_*_begin>, <llm_*_end)`，即 C 源里 asm 文本自身；**不含** gcc 补的 `sext.w`/`ret`、
  不含 gcc 在函数入口给 `"r"` 操作数做的 `mv`、不含 C 运行时/printf。
- **地址形成单列**：三个臂每子块各有 2 条 `addi`（共 16 条/score）。原因是本机 binutils 2.41 不接受
  向量访存的非零立即数偏移（`vle8.v v1,2(a5)` → `illegal operands`，实测），故地址一律显式形成。
  该项三臂相同，**不进入「计算段」比较**。
- **裸比值**（不是加速比）：`N_base/N_vdot = 100/58 = 1.724`；`N_macc/N_vdot = 85/58 = 1.466`；
  计算段 `24/15 = 1.600`、`16/15 = 1.067`。
- 逐条列表：`results/difftest/llm/llm_attn_static_{base,macc,vdot}.txt`（各 100 / 85 / 58 行）。
- **静态↔动态交叉核对**：`minstret` 差分（route2，见 §3）给出的每 score 指令数
  **逐值等于**静态计数：`static_base=100 measured_base=100 base=OK`、
  `static_macc=85 measured_macc=85 macc=OK`、`static_vdot=58 measured_vdot=58 vdot=OK`。

#### 4.7.3 动态拍数：4 点规模拟合（含斜率与 R²）

测量方式（详见用例头注）：`mcycle` 三点差分族。**拍数拟合用 route1 `I(n)−I(0)`**
（`perf_llm_attn.c:486-504`：每轮先测一个 n=0 空批点，再逐点测 n>0），逐轮原始增量取中位数。
`ROUNDS=3`、`N_WARMUP=1` ⇒ **只有 2 个有效样本**，`median_u64` 取 `a[n/2]` = **上中位数**（较大者）。
route2（`I(n_max)−I(n_min)`）**只用于 §2/§5 的静态↔动态指令数核对**，不用于拍数拟合。
`n` = 每次调用的 score 数；拟合 x = 窗口内 **int8 对数** `64n`（每 K=8 dot = 8 个 int8 对 ⇒ K=8 dot 数 = `8n`）。

**原始点（每臂 4 点，中位数；`R_LOOP=1`、2 个有效样本取上中位数）**

| 臂 | n=2 / 128 int8 对（16 K=8 dot） | n=8 / 512 int8 对（64 K=8 dot） | n=16 / 1024 int8 对（128 K=8 dot） | n=32 / 2048 int8 对（256 K=8 dot） |
|---|---:|---:|---:|---:|
| base（`unfused_rvv_seq`） | 218 cyc | 758 cyc | 1479 cyc | 2918 cyc |
| macc（`vwmacc_rvv_seq`） | 188 cyc | 654 cyc | 1277 cyc | 2518 cyc |
| vdot（`vdot_seq`） | 136 cyc | 422 cyc | 806 cyc | 1566 cyc |

**拟合（最小二乘，x = 窗口内 int8 对数，y = 窗口内 mcycle 增量）**

| 臂 | Σx | Σy | Σxy | Σx² | Σy² | A | B | C |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| base | 3712 | 5373 | 7906560 | 5521408 | 11324253 | 11681664 | 8306688 | 16427883 |
| macc | 3712 | 4637 | 6823424 | 5521408 | 8434113 | 10081152 | 8306688 | 12234683 |
| vdot | 3712 | 2930 | 4265984 | 5521408 | 3298572 | 6187776 | 8306688 | 4609388 |

| 臂 | 斜率 = A/B（cyc/int8 对） | 每 K=8 dot 周期 = 8·A/B | 每 score 周期 = 64·A/B | 截距（cyc/窗口） | R² = A²/(B·C) |
|---|---:|---:|---:|---:|---:|
| base | `30421/21632 = 1.406296` | **11.250** | **90.00** | 38.21 | **0.99999982** |
| macc | `26253/21632 = 1.213619` | **9.709** | **77.67** | 33.01 | **0.99999932** |
| vdot | `8057/10816 = 0.744915` | **5.959** | **47.67** | 41.22 | **0.99999540** |

**裸比值（同一轴 = cyc/int8 对）**：`slope_base/slope_vdot = 1.406296/0.744915 = 1.888`；`slope_macc/slope_vdot = 1.630`。
截距含「窗口边缘 + 循环控制」的固定开销（三个臂同一量级 33–41 cyc/窗口），**不进斜率**。

> **复算方法**（报告里的数字全部可由上表两行复算，不需要任何私有中间量）：
> ```
> A = 4·Σxy − Σx·Σy ;  B = 4·Σx² − (Σx)² ;  C = 4·Σy² − (Σy)²
> cyc_per_int8pair = A/B      # 拟合 x 是 int8 对数
> cyc_per_dot      = 8·A/B    # dot = K=8 子块 = 8 个 int8 对
> dot_per_cyc      = B/(8·A)
> int8pair_per_cyc = B/A
> int8op_per_cyc   = 2·B/A    # 每个 int8 对含 2 个操作数
> per_score        = 64·A/B
> intercept = (Σy·B − A·Σx)/(4·B) ;  R² = A²/(B·C)
> ```
> 一键复算（把三行 Σ 值抄进去即可）：
> ```sh
> python3 -c "A=11681664;B=8306688;C=16427883;s=A/B;print('cyc/int8pair',s,'cyc/dot',8*s,'dot/cyc',1/(8*s),'int8pair/cyc',1/s,'per-score',64*s,'R2',A*A/(B*C))"
> python3 -c "A=6187776;B=8306688;C=4609388;s=A/B;print('cyc/int8pair',s,'cyc/dot',8*s,'dot/cyc',1/(8*s),'int8pair/cyc',1/s,'per-score',64*s,'R2',A*A/(B*C))"
> ```
> 实算结果：base `cyc/int8pair 1.406296228, cyc/dot 11.250370, dot/cyc 0.088886, int8pair/cyc 0.711088, per-score 90.0030, R2 0.99999982`；
> vdot `cyc/int8pair 0.744914941, cyc/dot 5.959320, dot/cyc 0.167804, int8pair/cyc 1.342435, per-score 47.6746, R2 0.99999540`。

> **route1 披露（指令数口径）**：`I(n)−I(0)` 的指令数含有与 n 无关的常量边缘项（实测 +2 条/调用，
> `route1_disclosure=102/87/60`），除以 n 后会随 n 漂移，故**只披露、不作判据**；
> route2 把该常量精确消掉，才得到与静态计数逐值相等的 100/85/58。
> （拍数拟合仍用 route1；常量边缘项落在截距里，不进斜率——见上表。）

#### 4.7.4 内核吞吐（三套单位并列，不换算 token/s）

| 臂 | cyc/dot（dot=K=8，8 乘加） | dot/cyc（K=8） | int8 对/cyc | int8 操作数/cyc | 每 score 周期 |
|---|---:|---:|---:|---:|---:|
| base | **11.250** | **0.0889** | **0.7111** | **1.422** | 90.00 |
| macc | **9.709** | **0.1030** | **0.8240** | **1.648** | 77.67 |
| vdot | **5.959** | **0.1678** | **1.3424** | **2.685** | 47.67 |

- **口径换算（三套数同源、并列，不互引）**：拟合 x 是 int8 对数 ⇒ `cyc/int8 对 = A/B`；
  `cyc/dot = 8·A/B`；`dot/cyc = 1/(cyc/dot)`；`int8 对/cyc = 1/(cyc/int8 对)`；
  `int8 操作数/cyc = 2 × int8 对/cyc`（每个 int8 对含 2 个操作数）。三套数的精确值与复算见 §3。
- 吞吐裸比值（**同一轴内相除，不是加速比**）：`(int8 对/cyc)_vdot/(int8 对/cyc)_base = 1.3424/0.7111 = 1.888`；
  `(int8 对/cyc)_vdot/(int8 对/cyc)_macc = 1.630`。该比值在 cyc/dot 轴与 dot/cyc 轴数值相同，
  但本节只按所标轴各写一次，不与其它节互引。
- **不折算 GOP/s**：emu 没有可外推的真实频率；任何 GOP/s 都会是假定频率下的【推算】，本节不给。
- **load 形态披露**：计时窗口内重复读同一 chunk（resident/L1-hot），**不含跨 block 指针推进与流式访存**；
  功能校验另走完整 512 chunk（34 B 步长、`+2` 偏移）的真实布局。故本节的拍数是「内核 resident」口径，
  不是 memory-bound 口径（后者未运行）。

#### 4.7.5 自检与防「假通过」

| 检查 | 实测 |
|---|---|
| 编码自检 | `enc_check=0x3A20A1D7 expect=0x3A20A1D7 OK`（body 实际发射 `0x3A20A657` = `VDOT_ENC(12,1,2)`，解出 **vd=12**；与首条 `vdot.vv v12` 一致） |
| vl 自检 | `vl base=8 macc=8 vdot=8 expect=8 OK` |
| 金模型逐 score | `golden isum_fnv=0xAE617E159015FC18 expect=0xAE617E159015FC18 chunks=512 scores=64 arms_ok=64/64/64 OK` |
| 第三条独立路径 | `scalar_ref ref_vs_header_bad=0 OK`（纯标量参考和与头文件逐 score 相等） |
| 长度可分辨 | `base_alt accum_n=0xFFF3472F accum_nm1=0xFFF3DFEC alt_differs=yes` |
| 正常镜像 | `LLM_ATTN verdict=ALL_OK … enc_ok=OK vl_ok=OK golden_ok=OK alt_differs=yes fit=OK static_xcheck=OK` |
| G0 反例 | `LLM_ATTN verdict=HAS_FAIL reason=golden_mismatch score=0,0 got=0x0000D73D want=0x0000D73E arms_bad=1/1/1`（把期望值 `[0][0]` 故意 +1；仅该 score 被判负，其余 63 个仍 OK ⇒ 判负逻辑有分辨力） |
| 陷阱 | 两个镜像均 `HIT GOOD TRAP`；`ABORT=0`、`HIT BAD TRAP=0` |

> **实跑抓到过一个真 bug**：作业 `127039889`（15:53 的作业，FAILED）中 macc 臂 64 个 score **全错**（`arms_ok=64/0/64`）。
> 根因：`vwmacc.vv` 在 SEW=8 时目的组是 EEW=16/EMUL=2（两个寄存器），而累加器清零写在 e8 视图下
> 只清了 64 位（半个组），高 64 位是脏值。改为 e16 视图逐条清零 8 个独立累加器后，
> 复跑 `127049777` 的 G0 显示 `arms_bad=1/1/1`（只有被故意改错的那个 score 错），macc 臂通过。
> 这条留在这里是证据链的一部分：**G0 + 三臂互比确实抓得住实现错误**。

#### 4.7.6 这个基准能主张什么、不能主张什么

**能主张（限本节口径）**

1. 同一 Q8_0 attention tile、同一 VL=8、同一计时区下，**主分母** `unfused_rvv_seq` 的每 score
   计算指令 24 条、静态总数 100 条；`vdot_seq` 计算段 15 条、静态总数 58 条（裸比值 1.600 / 1.724）。
2. 同一数据与同一差分口径下，**每 K=8 dot 周期** `11.250` vs `5.959`；**每 int8 对周期** `1.406296` vs `0.744915`
   （两套各自同轴相除，裸比值均为 `1.888`；R² 分别为 `0.99999982` / `0.99999540`，4 个规模点）。
3. **敏感性**：对 `vwmacc_rvv_seq`（每子块 2 条计算指令，比主分母更省），vdot 的计算段优势只有
   `16/15 = 1.067`，同轴（int8 对/cyc）拍数裸比值 `1.630`。即 **vdot 的收益主要来自「把 3 条未融合序列压成 1 条」**，
   而不是「比任何 RVV 写法都省」。
4. K=8 语义的**固定代价**：一个 head_dim=64 的 score 需要 8 条 vdot + 7 条 vadd；
   「vdot 单指令」只在 **K=8 子块**级成立，**score/block 级不是单指令**。

**不能主张**

- **对 llama.cpp 上游宽核的优势**：上游 Q8_0 RVV 核每 32 元素只有 2 条计算指令（宽 LMUL 装载 + 宽化归约），
  本节的 `unfused_rvv_seq` 是 12 条/32 元素。两者分母不同；本节**不主张** VDOT 对上游宽核占优。
- **端到端 token/s / LLM 推理加速 N×**：昆明湖 emu 跑 AM flat binary，不是 Linux 进程，跑不了 llama.cpp；
  本节只有 kernel 级数字。
- **与 §4.3 的 `1.33×` 混称**：本节不引用、不相乘、不相除。
- **硅上性能**：全部拍数为 Verilator 仿真周期（`Core-0 cycleCnt=453,987` 是整程序口径，含 printf 与自检，
  不可当 kernel 数字；kernel 数字来自窗口内 `mcycle` 差分）。

#### 4.7.7 与评分表的映射

| 评分项 | 官方出处 | 本节位置 |
|---|---|---|
| 阶段三 25 分（3.3 报告） | `docx/02-赛题与评分细则.md:90` | 真实 LLM 算子（Q8_0 attention QK）的第二组证据；不替代 §4.3 |
| 探索性 5 分（微架构优化分析） | `docx/02:93` | 三轴（静态指令 / 动态拍 / 吞吐）+ 4 点拟合斜率与 R² |
| 创新性 5 分（扩展应用潜力） | `docx/02:96` | `16/15 = 1.067` 的敏感性结果 **直接量化**「K=8 单结果语义在 head_dim=64 上的映射损失」，与 §7 的「K=16 / np 多结果」扩展路线图衔接 |
| 可行性 | `docx/02:91-92` | 全部复用现有 AM/emu/金模型/差分口径；改动面 = 一个用例 + 一个生成器 + 两个构建/运行脚本，**无 RTL 改动** |

#### 4.7.8 证据路径（全部在库）

| 证据 | 路径 |
|---|---|
| 用例源码 | `design/verify/cases/perf_llm_attn.c` |
| 金模型生成器 / 头文件 | `design/verify/cases/gen_llm_attn.py`、`design/verify/cases/llm_attn_vectors.h`（sha256 `60914c8e…`） |
| 静态计数（逐条 + 汇总） | `results/difftest/llm/llm_attn_static_{base,macc,vdot,summary}.txt`、`llm_attn_static_diff.txt` |
| 镜像与构建摘要 | `results/difftest/llm/llm_attn.bin`、`llm_attn_g0.bin`、`llm_attn_build_summary{,_g0}.txt` |
| 实跑（主） | `results/difftest/llm/run-20261106T170716/`（`97-llm-*.log/json` + 正常/G0 两份 case log） |
| 运行脚本 | `core-package/scripts/97-run-llm.sh` |
| 构建/计数脚本 | `design/verify/cases/build_llm_attn.sh`、`design/verify/cases/objdump_llm_attn.sh` |
| 口径修订复算（20261107） | 按 §3 的 `python3 -c` 两行与 §2 的 objdump 计数可直接重跑（三套单位复算 + 编码解码 + 核对输出） |

#### 4.7.9 用词核对（对照 `stage3/3.3/report.md` §9）

- 本节不写「延迟加速」与「每点开销倍数」的组合表述；该组合涉及的每点开销数字在本节**未引用**。
- 本节不写「2 拍已收敛」「SEW=16/LMUL=2 已支持」「比竞品快 N 倍」。
- 本节把「加速」类词汇只用于**禁止性说明**（§0/§6）；所有比值一律写成裸比值 `A/B`。
- 所有未实测项（端到端 token/s、memory-bound 口径、GOP/s、硅上周期）**明写未运行**。

#### 4.7.10 复跑（独立作业 `127051826`）

| 项 | 实测 |
|---|---|
| 作业 | `127051826` / `kshcnormal` / `COMPLETED 00:22:12` / `ExitCode=0:0` / 8 核 |
| 脚本判据 | `status=通过`，9/9 criteria 达标（`normal_all_ok`、`g0_has_fail`、`good_trap`、`no_abort`、`no_bad_trap`、`llm_fields`、`no_mismatch_line`、`emu_rc`、`static_xcheck` 全 `达标`） |
| 正常镜像 | `LLM_ATTN verdict=ALL_OK … enc_ok=OK vl_ok=OK golden_ok=OK alt_differs=yes fit=OK static_xcheck=OK` |
| G0 镜像 | `LLM_ATTN verdict=HAS_FAIL reason=golden_mismatch score=0,0 got=0x0000D73D want=0x0000D73E arms_bad=1/1/1` |
| 逐点拍数 | base `218 / 758 / 1479 / 2918`、macc `188 / 654 / 1277 / 2518`、vdot `136 / 422 / 806 / 1566`（**与 `127049777` 逐值相同**） |
| 拟合 | base `A/B = 11681664/8306688`、macc `10081152/8306688`、vdot `6187776/8306688`（**与 `127049777` 逐值相同**） |
| 静态↔动态 | `static_base=100 measured_base=100 base=OK static_macc=85 measured_macc=85 macc=OK static_vdot=58 measured_vdot=58 vdot=OK div=OK` |

结论：本节的数字是**可复现的**（两次独立作业、同一镜像 sha256、emu 确定性行为），不是单次偶然。

#### 4.7.11 机时（如实记账）

昆山 `results/budget-log.tsv` 实读（`90-budget-log.sh`）：

| 作业 | 状态 | elapsed | node-h |
|---|---|---:|---:|
| `127039889` | FAILED（暴露 macc 臂 bug 的作业，不构成结论） | 215 s | 0.060 |
| `127042412` | TIMEOUT（用例 1200 s 超时，不构成结论） | 1344 s | 0.373 |
| `127046416` | 主动 `scancel`（分支阶梯与点表不一致，不构成结论） | 891 s | 0.248 |
| `127049777` | COMPLETED（用例侧 `verdict=ALL_OK`；脚本 CR 解析误判） | 867 s | 0.241 |
| `127051826` | COMPLETED（`status=通过` 9/9 criteria） | 1330 s | 0.369 |
| **合计** | | | **1.291** |

该项落在 **P3-full** 科目下；远端 `90-budget-log.sh summary` 显示 **P3-full 与合计均已超线**
（`P3-full 10.819/3.0`、`合计 14.815/10.6`，含其它并行批次的用量）。本节如实记账，不做冲销，也不作辩解。

### 4.8 `sections/dualchain.md`：双链实验（**2026-11-07 13:11 三轴版**）

> **来源**：`stage3/3.3/sections/dualchain.md`（定稿版 26,389 B、252 行，2026-11-07 13:11 三轴版；sha256 `baca2d90d25b9d2ac127f1b5243fe95a13c2b513576ee28415bba6da582b0d43`）。**并入方式**：按 §4.6 的编号约定整件插入，源文件 `## 4.8.N` 降级为 `#### 4.8.N`，正文与源文件一致（仅标题层级与用词统一；含其【我方 emu 实测】/【对方文档】/【推算】/【未运行】标签）；源文件头注的小节归属一致（标注 §4.8 小节）。本版取代 2026-11-07 00:42 版：新增作业 `127142843` 全量重测（M1–M8 逐链读数更新，并新增对方依赖链口径的 M9/M10/M11 对照臂 = §4.8.5）；把「吞吐 / 依赖间隔 / T5-L」固定为 A/B/C **三口径分列**（§4.8.1），同窗比值由 5.6/7.3 改为本次 **5.5/7.5（M5/M8，q4/q8）**；`4.8.4(c)` 补 M9 gross 6.984 与 `4 + 2.98` 的口径切法说明；机时台账补第三行 `127142843`（记账合计 6.809 core-h）。**跨批次口径**：M1–M8 以本次主表为准，上一次 `127043684` 作复现记录（源文件 §4.8.6 第 9 条）；M9/M10/M11 只在本次测量。§5.5 的确认依据即本节。

> **小节归属**：本文件并入 `stage3/3.3/report.md` **§4.8**；编号即按 **§4.8.x** 书写，并入时按原样插入、编号不变。
>
> 定稿：2026-11-07 ｜ 作业：`127142843`（kshcnormal，`COMPLETED 00:16:46`，`ExitCode=0:0`，`status=通过`、12/12 criteria 达标）｜
> 用例：`design/verify/cases/vdot_dualchain.c`（**不进** `manifest.tsv`；主清单 `sha256 a90d1071…`、30 数据行未变）｜
> 构建：`design/verify/cases/build_dualchain.sh`（两镜像，`-DDC_G0=1` 为 G0 反例；本次 `source_sha256=d23b049b…`、xpack 13.2.0）｜ 运行：`core-package/scripts/96-run-dualchain.sh`
> emu：`md5=fd65ca4a…`；版本 `xiangshan=a4eeaab / yunsuan=9559211 / nemu=a683e0b`（作业日志头）。
> 远端证据：`~/core/results/difftest/dualchain/96-dualchain-20261107T124540.{log,json}`、
> `cases/vdot_dualchain.20261107T124540.log`、`cases/vdot_dualchain_g0.20261107T124540.log`；本地副本 `results/difftest/dualchain/`。
>
> **标记约定**：`【我方 emu 实测】`= 本作业日志读数；`【对方文档】`= 对手文档数字、本仓未复跑其镜像；`【推算】`/`【未运行】` 按字面。
> **口径约定**：本节把「吞吐」「依赖间隔」「T5-L」**三分列**，三者**不相除、不互引**；同口径比值只在「吞吐」列内部使用（两条链同窗相比）。
> 芯锐/Gloria 的「7 cyc」见其公开材料，本仓未复跑，相关处逐条标注。
> 本节**不写**「优于同题」「全场唯一」；芯锐/Gloria 的 7 cyc 均按【对方文档】处理。

---

#### 4.8.1 结论先行：三个口径分列

> **口径约定**：A 吞吐、B 依赖间隔、C T5-L 是**三种不同窗口/不同单位**的量。
> **禁止**把 A 的数字除以 B 或 C 的数字得到「倍数」，也禁止用 B/C 的差去证明 A。下表每行只在自己的口径内读数。

| 口径 | 窗口与单位 | 本次实测【我方 emu 实测】 | 能说明什么 | 不能说明什么 |
|---|---|---|---|---|
| **A 吞吐** | 无依赖流（源常量、vd 不被读），差分商 q4/q8，**cyc/条** | 无依赖 `vdot`：M8 **0.890/1.011**、M3 **1.125/0.968**（q4/q8）；读旧 vd 的 `vmacc`：M5 **4.875/7.531** | 同测量形状下，无依赖 `vdot` ≈**1.0 cyc/条**，读旧 vd 的 `vmacc` ≈**7.5 cyc/条**（q8）；同窗比值：M5/M8 q8 **7.45**、q4 **5.48**（M5/M3 q8 7.78、q4 4.33）。机制见 §4.8.3：`vd_old=INT.X` ⇒ `vdRen=F`、旧 vd 不进归约 | 这是**每指令吞吐差，不是单条延迟、不是加速比**；不能与 B 的 5.7–7.5 或 C 的 4 相除/相减；两条链**指令不同**（vdot vs vmacc），不称「单一变量」 |
| **B 依赖间隔** | RAW 链，`rdcycle` 括窗差分中位数 q4/q8，**cyc/步** | M1 **5.687/7.031**、M2 **6.437/6.984**、M4 **4.812/7.531**、M5 **4.875/7.531**、M6 **2.000/4.375** | 依赖链的每步商落在 **4.8–7.5**；五条依赖链全部 `q8>q4`，差分模型 `q(R)=L+O/R` 反解 `O<0`（物理不可能）⇒ 只能读作**上界型参考** | **不能读作 `L`**（依赖间隔）；不能与 A 的吞吐、C 的 4 相除；不能据此否定 C 的 4 |
| **C T5-L** | `perf_vdot.bin` 的逐条 `rdcycle` 括窗（8 轮×2000 次，中位数），**cyc/步** | `L_vdot=4`、`L_vmacc=4`、`L_vadd=3`（既有口径）；同镜像全环 `L_vdot_loop=6.98`；三链「全环−括窗」= **2.9495/2.9730/2.9785** | 4 是**该镜像、该括窗口径**下的延迟读数；与全环 6.98 相差恒定的 ~2.97 拍（三条不同指令链互证） | 不是本次双链差分复现值（B 未复现 4，也未推翻）；不是跨实现/跨镜像稳定的常量；**不能与 A 相除** |

**Headline（口径 A，【我方 emu 实测】）**：无依赖 `vdot` **≈1.0 cyc/条**（本次 M8 0.890/1.011、M3 1.125/0.968，q4/q8；上一次 q8 = **1.03**），
而源为常量、**只读旧 vd** 的 `vmacc`（M5）**4.875/7.531 cyc/条** ⇒ 同窗**约 5.5 倍（q4）/ 约 7.5 倍（q8）**的每指令吞吐差。
机制归因：`vdot` 的 `vd_old=INT.X`，译码 `vdRen=F`、不申请旧 vd 读口、旧 vd 不进归约 ⇒ 背靠背 `vdot` 不形成写回环（§4.8.3）。
上一次作业 `127043684`（emu `md5=529c9abc…`）给 M8 **1.007/1.007**、M5 **5.625/7.531**，同一结论；两批 M5/M8 同窗比稳定在 **≈5.5（q4）/≈7.5（q8）**。
**该倍数只在口径 A 内部成立，不是加速比，不得与 B/C 的数字相除或互引。**

---

#### 4.8.2 逐链实测（作业 `127142843`，VL=8 / SEW=8 / LMUL=1 / 同一组 `buf_a`/`buf_b`）

口径：**差分法中位数**。每轮测 `C(n)` 与 `C(2n)`：`n=4` 个 rep、每 rep 连发 R 条同型链指令
（R=4 与 R=8 各测一次），`rdcycle` 只在循环外括窗；逐轮商 `q(R)=(C(2n)−C(n))/(n·R)` 取 5 轮中位数（毫拍精度）。
M2 一步两条、M8 一步八条，均按「条」归一。

| 链 | 指令序列（汇编打印顺序） | 形状 | `q(R=4)` cyc/条 | `q(R=8)` cyc/条 | 判读 |
|---|---|---|---|---|---|
| **M1** | `vdot.vv v10,v10,v1` | vd==vs2 自别名，真 RAW | **5.687** | **7.031** | 有依赖 |
| **M2** | `vdot.vv v11,v10,v1` / `vdot.vv v10,v11,v1` 交替 | 跨寄存器真 RAW | **6.437** | **6.984** | 有依赖 |
| **M3** | `vdot.vv v3,v1,v2` ×N | **无任何数据依赖**（源常量、vd 固定不被读） | **1.125** | **0.968** | **≈1，无串行化** |
| **M4** | `vmacc.vv v10,v1,v10` | 对照：old_vd 是语义输入且 vd==vs2 | **4.812** | **7.531** | 有依赖 |
| **M5** | `vmacc.vv v10,v1,v2` | 对照：**串行源只有 old_vd**（vs2 常量） | **4.875** | **7.531** | **有依赖** |
| **M6** | `vadd.vv v10,v10,v1` | 非 vimac 的 ALU 参照链 | **2.000** | **4.375** | 有依赖（更短） |
| **M7** | `vadd.vv v3,v1,v2` | 无依赖地板（源常量、vd 固定） | **1.937** | **1.031** | ≈1，地板 |
| **M8** | `vdot.vv v8..v15` 轮流写、源常量 | 无依赖且**不同 vd**（释放同号 WAW 压力） | **0.890** | **1.011** | **≈1** |

**上一次复现（作业 `127043684`，emu `md5=529c9abc…`，同源版本）**：M1 `5.687/7.531`、M2 `6.437/6.718`、M3 `1.000/1.031`、
M4 `5.562/7.218`、M5 `5.625/7.531`、M6 `4.125/4.343`、M7 `1.500/1.281`、M8 `1.007/1.007`。
两批在 M1/M2/M8 的 q4/q8 与 M5 的 q8 上一致到 ~0.5 拍内；M5 的 q4 两批为 4.875/5.625（差 0.75），M4/M6/M7 的批次间抖动更明显（emu 同一源码但重建、q 取 5 轮中位数）。
**结论（有依赖/无依赖、vdot/vmacc 的分离）两批一致；本文件主表用本次（与 M9/M10/M11 同一 emu、同一作业），上一次作复现记录。**

**交叉核对（仓内既有 `perf_*.bin`，2026-11-03 镜像；与本次不是同一 emu 构建）**
`perf_vdot.c` 自带的整段墙钟口径 `L_vdot_loop`：`13957 cycles / 2000 ops = 6.98 cyc/步`（`perf_vdot.20261103T075552.log:9`）；
`L_vmacc_loop = 13946/2000 = 6.97`（`perf_vmacc...:8`）、`L_vadd_loop = 11899/2000 = 5.95`（`perf_vadd...:8`）。
三条链的整段口径与本节差分口径**逐条同序**（vdot≈vmacc>vadd），说明本项测量与仓内既有口径不矛盾（跨镜像，仅作序关系核对）。

**本项差分法自身的缺陷（必须与上表并读）**：模型 `q(R)=L+O/R` 要求 `q4>q8`（O>0）。实测**五条依赖链全部 `q8>q4`**
（M1 `+1.344`、M4 `+2.719`、M5 `+2.656`、M2 `+0.547`、M6 `+2.375`），反解出的 `O` 为负，**物理上不可能**；
三条无依赖链（M3/M7/M8）的 `q4≈q8`（`−0.157/−0.906/+0.121`，均在 ~1 拍量级）。
⇒ 差分法只在「无依赖」时自洽，对依赖链**系统性高估**（队列深度效应随批大小放大）。
**所以本表的 `q` 只能读作「上界型参考值」，不能读作 `L`；本项不拿它去反推 `L` 或做跨口径运算——本项只在口径 A 的 M5/M8 使用同口径比值（q4 与 q8 各自同窗相比，已在 §4.8.1 标明）。**

**口径注解（表内 `q4/q8` 与作业 JSON 的 `L=2q8−q4`：两套数并存、用途分列）**：

- 表内 `q(R=4)`/`q(R=8)` 是**差分商原值**：每轮 `(C(2n)−C(n))/(n·R·I)` 取 5 轮中位数（`rdcycle` 只在循环外括窗的读数），是每指令拍数的原始观测量。
- 作业 JSON（`96-dualchain-20261107T124540.json` 的 `metrics[]`）里的 `M1=8/M2=8/M3=1/M4=10/M5=10/M6=7/M7=0/M8=1` 是**差分模型的派生量** `L=round(2q8−q4)`（毫拍版 `M1_milli=8375` 即 `2×7031−5687`），打印在 `design/verify/cases/vdot_dualchain.c:465/:468/:472-473`。
- 两者**不是两套独立测量**：`L` 由同一对 `q4/q8` 线性组合而来（可算但**不可当作独立证据**），且 `L=2q8−q4` 仅在 `q(R)=L+O/R` 成立时有物理意义——依赖链 `q8>q4`（上段）已使该前提失效，故 JSON 的 `L` 值只作产物留档，**正文一律引用 `q4/q8` 原值，不把 `L` 读作依赖间隔，也不做 `q ↔ L` 的换算引用**。
- 同窗比较示例（口径 A 内部）：`q4` 口径 M5/M8 = 4.875/0.890 ≈ **5.5 倍**，`q8` 口径 = 7.531/1.011 ≈ **7.5 倍**；旧稿的「7.5×」若指 `q8(M5)/q4(M3)` 则是跨窗相除，已废止。C1 一律用同窗值。

---

#### 4.8.3 机制归因（file:line）

**链路**：`vdot` 的 `vd_old` 字段取 `INT.X` ⇒ 译码不把旧 vd 当源 ⇒ 数据通路也不把旧 vd 并入归约 ⇒ 背靠背 `vdot`
在"源无依赖"时不形成写回环；而 `vmacc` 的 `vd_old` 取 `INT.S`、`isMacc(opcode)=true`，旧 vd 是**语义输入**，同形状链条即被串行化。

1. **`vd_old = INT.X`（类型编码）**：`repos/XiangShan/yunsuan/src/main/scala/yunsuan/package.scala:400`
   `def vdot = LiteralCat(0.U(2.W), INT.S, INT.S, INT.X, FMT.VVV, VimacOpcode.vdot)`——布局注释在 `:381`/`:383`
   （`pad | vs2 sign | vs1 sign | vd_old sign | format | opcode`）；同文件 `:391` 的 `vmacc` 该位是 `INT.S`。
2. **译码 `vdRen=F`（不申请旧 vd 读口）**：`repos/XiangShan/src/main/scala/xiangshan/backend/decode/VecDecoder.scala:385`
   `VDOT_VV -> OPMVV(F, FuType.vimac, VimacType.vdot, F, T, F, UopSplitType.VEC_VVV)`；`OPMVV` 的
   `private def src3: BitPat = if (vdRen) SrcType.vp else SrcType.X` 在 `:91`（`:108` 属另一个 case class）。
   `vdRen=F` ⇒ `src3=X` ⇒ 该 uop 不向寄存器堆要第三个操作数。
3. **`isMacc` 不含 `vdot`**：`repos/XiangShan/yunsuan/src/main/scala/yunsuan/encoding/Opcode/VimacOpcode.scala:18`
   `def isMacc(opcode) = Seq(vmacc, vnmsac, vmadd, vnmsub).map(_ === opcode).reduce(_ || _)`（`:14` 是 `def vdot = "b111"`，不在集合内）。
4. **旧 vd 不进入归约**：`repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VIMac64b.scala:125`
   `partProd(33) := Mux(io.isMacc, Mux(io.widen, Cat(oldVd, oldVd), Mux(io.isSub, ~oldVdReorg, oldVdReorg)), 0.U)`
   —— `isMacc=false` 时**恒 0**，旧 vd 只在被选中的那一支里出现。
5. **归约的寄存使能来自 `fireS1` 端口线**：`VIMac64b.scala:37` `val fireS1 = Output(Bool())`、`:219` `io.fireS1 := fireS1`
   （`:41` `val fireS1 = GatedValidRegNext(fire)`）；wrapper 侧只连 `vimacs(0)`：
   `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:129` `vdotReduce.io.sum_wo := vimacs(0).io.sum_wo`、
   `:130` `vdotReduce.io.fireS1 := vimacs(0).io.fireS1`；输出旁路 Mgu 取 `outCtrl`：
   `VIMacU.scala:159` `outIsVdot = outCtrl.fuOpType === VimacType.vdot`、`:160` `res.data := Mux(outIsVdot, vdotReduce.io.vd, mgu.io.out.vd)`。

**实验侧的 A/B 对照（结论不是"读代码推的"）**：

- **M3 vs M5**：两条链**测量形状相同**（源为常量、vd 固定、无跨指令 RAW），但**指令不同**（`vdot` vs `vmacc`）、内部通路也不同 ⇒ 不能称「单一变量」。
  实测每指令吞吐 `1.125/0.968` vs `4.875/7.531` cyc/条（q4/q8）⇒ 读旧 vd 的链每指令代价高约 **5.5 倍（q4 同窗，M5/M8）/ 7.5 倍（q8 同窗，M5/M8）**（M5/M3 分别为 4.3/7.8 倍；q4 的 M3 本次偏高），与第 1–4 条的 RTL 机制（`vd_old=INT.X`、`isMacc` 不含 vdot、旧 vd 不进归约）**方向一致**；
  因果强度只到「一致」，不写成单变量证明。
- **M3 vs M8**：都无依赖，差别只在"写同一个 vd"(M3) 与"轮转 8 个 vd"(M8)。实测 `0.968–1.125` vs `0.890–1.011` ⇒ 同号 vd 的 WAW
  也被消化（全写 + 不读旧值），不是"靠换寄存器名躲开"。
- **M1 vs M2**：`5.687/7.031` vs `6.437/6.984` ⇒ 自别名与跨寄存器两种真 RAW 的间隔同量级（差 <1.5 cyc），不是自别名假象。
- **M6**（`vadd` 自别名）本次 `2.000/4.375`（q4/q8），上一次 `4.125/4.343`——**批次间抖动明显**（q4 差 >2 拍），
  故只保留定性结论「vadd 链短于 vimac 链（乘 + 压缩树 + CPA 的流水级），不是 vdot 特有」，**不引用精确差值**。

---

#### 4.8.4 关于「4 cyc」：本项能说什么、不能说什么

**(a) 本项未能复现 4。** 差分口径给 M1（`vdot.vv v10,v10,v1`，与 `perf_vdot.c` 的 `L_vdot` 同一条链）`5.687/7.031` cyc/步。

**(b) 但本项也没有推翻 4。** 差分模型在依赖链上自相矛盾（`q8>q4`，反解 `O<0`，§4.8.2 末段），
所以 `5.7–7.5` 只能当"上界型参考"，**不能作为 `L` 的反证**。诚实记法是「另一口径未复现 4」，不是「4 被证伪」。

**(c) 仓内的两个既有口径其实是互相印证的。** 把 `perf_*.c` 的整段口径减去括窗口径：

| 链 | `loop/N` | 括窗 `L` | 差 |
|---|---|---|---|
| vadd | 5.9495 | 3 | **2.9495** |
| vmacc | 6.9730 | 4 | **2.9730** |
| vdot | 6.9785 | 4 | **2.9785** |

三条**不同指令**的链给出同一个差值 **≈2.97 拍**（极差 0.03）。一个自然的解释是：`loop-total = 括窗延迟 + 每轮固定循环开销`，
而每轮循环开销（`addi`+`bne`+取指）与链类型无关。**因此 `L_vdot=4` 与 `L_vdot_loop=6.98` 不是矛盾，更像是同一事实的两种切法：
前者是"延迟"、后者是"延迟 + 环路开销"。** 这**不构成**对 4 的独立证明（差值恒定是拟合结果，不是预注册判据），但足以说明 §3.1 的 4 在本镜像内**不自相矛盾**。
本次 M9 的同口径 gross 斜率 **6.984** 与 `4 + 2.98`（C 的括窗 4 + 本条差值）在数值上吻合——**仅作「同一实现的两种切法」的解释，不把 C 与 M9 当同一量、不据此做跨口径运算**（§4.8.5）。

**(d) 逐条括窗的敏感性观测只能作方法学线索（证据来自被取代镜像）。** 本项 2026-11-06 交付源码已删逐条括窗（brk）代码；下列 7 行只存在于**被取代镜像**的日志
`results/difftest/dualchain/cases-vdot_dualchain.20261106T155006.log`（`expected_sha256=4fed31e3…` ≠ 当时交付头 `c1beda4b…`，`verdict=HAS_FAIL func_fails=4`），**仅作方法学记录**：

```
DUALCHAIN M1 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
DUALCHAIN M3 brk samples=112 len=128 median=2 mean=2 min=2 max=6 over=0
DUALCHAIN M4 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
DUALCHAIN M5 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
DUALCHAIN M6 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
DUALCHAIN M7 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
DUALCHAIN M8 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
```

**含完全无依赖的 M3/M7/M8 在内，七条链全部返回 median=2** ⇒ 该逐条括窗口径**疑似**对**二进制布局/调度**敏感
（`mcycle`/`cycle` 不在香山的有序读 CSR 白名单：`repos/XiangShan/src/main/scala/xiangshan/backend/fu/NewCSR/CSROoORead.scala:10-55`
的两个列表均不含它们，两层 `rdcycle` 可与中间的向量指令重排——同 `perf_kernel_cmp.c` 头注的判废结论）。
**结论（仅作方法学线索）**：这只是**方法学线索**，不是本次交付镜像上的实测结论；4 在 `perf_vdot.bin` 里自洽，但不是"换实现/换布局都成立"的常量；对外引用必须带"来自该镜像的括窗口径"这一限定。

---

#### 4.8.5 同口径对照：Gloria/GEMwhu 的依赖链口径（M9/M10/M11）

**口径原文**（对手公开材料 `相关证明材料/performance/README.md:35`，【对方文档】）：

> 「72个程序各三次，共216次；循环次数为0、64、256、1024。输入预先存于寄存器，结果描述重复计算，不包含每次重新装载输入的应用成本。**依赖链参照为20.991935对7.008065周期/点积，周期比2.995。**」

**归属更正（按证据就近修正）**：该 `performance/README.md:35` 路径属于 **Gloria-Deng/GEMwhu**
（其公开仓库的 `相关证明材料/performance/` 目录），**不是香山芯锐**；芯锐的「7 cyc/次」在
`docs/正文/09_延迟测量与软件优化分析.md:95-97`，是**另一套口径**（N=1/8/32 的增量斜率、空窗口 74 拍、RVV-m1 55 / mf2 47）。
**芯锐的 7 cyc 与本项 M9 口径不可比**（对方【对方文档】；其程序 `apps/vdot-chain-v1/cases.S` 虽公开，但本次未复跑，
且 N 集/拟合方式与 M9 的 N=0/64/256/1024 四点 OLS 不同）。本节的 M9/M10/M11 复现的是 **Gloria 的
「依赖链 w1、N=0/64/256/1024、每点 3 次重复、4 点 OLS 斜率（含循环开销）」** 口径；芯锐的 7 cyc 不与 M9 直接比较。

**可复现性判定**：可复现。对方仓库公开了方法链：`相关证明材料/experiments/throughput/study.py`（`line_fit`/`summarize`：
同 N 取 3 次中位数、4 点 OLS、`gross=slope/width`、`adjusted=(slope−control)/width`）与
`verified/generated_source/dependent_w1_{vdot,rvv,control}_n{0,64,256,1024}.S`（依赖链 w1：vd 同时是源 v30 + 目的；
其 vdot 编码 `funct6=0b101100`、vs1=30/vs2=31/vd=30）。本项用**同链形状 + 同 N 集 + 同拟合**在**本项编码（0x0E）**上复现。
**M9/M10/M11 是独立的第四口径（对方依赖链，含循环开销），不与 §4.8.1 的 A/B/C 相除或互引。**

- **M9**：`vdot.vv v30, v31, v30`（vd=30、vs1=30、vs2=31；v30 既源又目的）；
- **M10**：标准 RVV 五指令等价链（`vwmul.vv v16,v31,v30` / `vsetivli e16` / `vmv.v.i v30,0` / `vwredsum.vs v30,v16,v30` / `vsetivli e8`）——对方 `dependent_w1_rvv` 的同构基线，本项独立重写；
- **M11**：空循环 control（对方 `control` 臂，用于 `adjusted` 估计）。

**实测（作业 `127142843`，【我方 emu 实测】；对方列为【对方文档】）**：

| 臂 | 本项 gross（cyc/点积） | 本项 adjusted（减 M11） | 对方 gross【对方文档】 | 对方 adjusted【对方文档】 | 差（gross / adjusted） |
|---|---:|---:|---:|---:|---:|
| **M9 vdot 依赖链** | **6.984** | **6.006** | **7.008065** | **5.979839** | −0.024 / +0.026 |
| **M10 标准 RVV 五指令链** | **20.994** | **20.016** | **20.991935** | **19.963710** | +0.002 / +0.052 |
| **M11 空循环 control** | **0.978** | — | 1.028226 | — | −0.050 |

原始读数（`DUALCHAIN_G44` 行，3 次重复的中位数）：M9 `N=0/64/256/1024 → 36/514/1824/7200` 拍；M10 `36/1382/5407/21534` 拍；
M11 `36/183/305/1073` 拍。斜率由 4 点 OLS 计算，R²（独立恒等式与残差式互证）= M9 **0.99998**、M10 **0.9999999**、M11 **0.99387**。

**结论（同口径量级对照，不做优势论证）**：

1. **M10 与对方文档的 RVV 基线差 0.002 cyc/点积**（20.994 vs 20.991935）⇒ 该口径在本 emu 上**复现成功**，M9 与对方 vdot 的比较有共同标尺。
2. **M9 与对方文档的 vdot 依赖链差 −0.024 cyc/点积（−0.3%）**（6.984 vs 7.008065）；adjusted 差 +0.026（+0.4%）。
   即：**同口径下两者是同一量级（≈7 cyc/点积），本项不主张任何优势**。上一稿「我方 4 vs 对方 7」是**跨口径**
   （C 的括窗 `L_vdot=4` 对 A/对方含循环的 gross 7），已按三分列废止；M9 的 6.984 与 `4 + 2.98` 环路开销数值吻合，
   **仅作口径切法的解释，不把 C 与 M9 当同一量、不做跨口径运算**（§4.8.4c）。
3. **残余口径差（如实）**：对方 vdot 编码位置 `funct6=0b101100` vs 本项 `0x0E`；对方 emu 构建未知 vs 本项 `md5=fd65ca4a…`
   （`a4eeaab/9559211/a683e0b`）；对方 cycle 网格 8 拍、每次重复单独启动 emu、计时窗口含循环后 store/fence/比较，
   本项 `rdcycle` 精确到 1 拍、同进程 3 重复、窗口只括循环。M10 的 0.002 差说明这些差异对斜率的影响 <0.01 cyc/点积。
4. **硬性约束**：对方 7.008065/20.991935 是【对方文档】、本仓未复跑其镜像；本节只做**同口径量级对照**，不写「优于同题」「全场唯一」，
   不把 M9/M10 与对方数字相除当加速比（表中比值仅用于核对复现，不是性能主张）。

---

#### 4.8.6 诚实边界

1. **本项没有独立复现「4 cyc」**，也没有推翻它（§4.8.4）。任何"vdot 依赖间隔 = 4 cyc，已由双链实验独立验证"的表述**不成立**；
   正确的表述是"`perf_vdot.bin` 的逐条括窗口径给 4，且与同镜像全环口径 6.98 相差恒定的 ~2.97 拍环路开销（三条链互证）"。
2. **本项不主张优于任何对手**。竞品 7.008/20.992 是其文档、未复跑；§4.8.5 的同口径对照只说明「量级相同、口径已对齐」，不做减法。
3. **机制归因（口径 A）的论证以 RTL 为准，不靠单变量 A/B**：M3/M5 是同一程序、同一 VL、同一操作数、同一测量法下的两条链，但**指令不同**（`vdot` vs `vmacc`）、通路不同，因此 1.125/0.968 vs 4.875/7.531 cyc/条（q4/q8）只描述这两条链的**每指令吞吐差**（同窗约 5.5/7.5 倍，M5/M8），**不写成"单一变量"**；机制成立性以 §4.8.3 的 file:line（`vd_old=INT.X`、`vdRen=F`、`isMacc` 不含 vdot、旧 vd 不进归约）为准，测量仅作方向一致的佐证。
4. **未测**：真实硅后时序（emu 是 RTL 仿真，`rdcycle` 是模型周期）；带负载下的依赖间隔；`LMUL>1`/`SEW≠8` 按规定非法，不在本节范围。
5. **机时台账**（远端 `~/core/results/budget-log.tsv`，2026-11-07 复核）：本项正式作业两行——
   `127039614`（`1233 s`，`2.740 core-h`，超时作业）、`127043684`（`843 s`，`1.873 core-h`）——加本次 `127142843`
   （`988 s`，`2.196 core-h`，`COMPLETED 00:16:46`），**记账合计 `6.809 core-h`（`0.851 node-h`）**。
   另有**未记账**三次：`127030411`（外部取消，`23 s`）、`127031493`（初次超时）、`127142422`（本次为放宽
   `CASE_TIMEOUT_S` 主动取消，`4:44`、8 核 ≈`0.63 core-h`）——这三次的实际消耗不在台账里，如实披露。
6. **M3/M7/M8 的 `≈1.0 cyc/条` 是吞吐不是延迟**：VL=8 单结果、128b 通路全宽下的发射率；**M5 的 7.531（q8）也是同一差分口径的每步商，不是单条指令延迟**。上述数字均不可与"依赖间隔"混读，也不得与 §4.8.4 的 5.7–7.5 依赖链口径或 T5-L 的 4 相除/互引。
7. **JSON 产物**：本次 `96-dualchain-20261107T124540.json` 可被严格 `json.load` 解析（`status=通过`、12 criteria、19 metrics，含 M9/M10/M11 斜率）；上一次的 CR 缺陷已由 `metric_rows()` 的 `tr -d '\r'` 修复。本节数字取自用例日志的 `DUALCHAIN ... dep` 与 `DUALCHAIN_G44 ... fit` 行。
8. **M9/M10 的功能自检只覆盖「跑 1 步」**（结果 = 单次 dot(a,b)，与金模型 `DCW_M3` 逐字节一致，两条链均 `bytes_bad=0`）；N 步的最终值不在功能判据内（它们是计时臂）。完整 16 条功能链（M1–M8 及 alt）仍由金模型逐行复核（`LOG_MATCH chains=16 dep_lines=8`）。
9. **emu 重建差**：两批源版本相同（`a4eeaab/9559211/a683e0b`），但 emu `md5` 由 `529c9abc…` 变为 `fd65ca4a…`；M1–M8 有 ~0.5 拍级抖动（M4/M6/M7 更明显），M9/M10/M11 只在本次测量。跨批次引用 M1–M8 时以本次主表为准，上一次作复现记录。

---

#### 4.8.7 复现命令

```sh
# 1) 金模型生成期望头 + 构建两镜像（昆山登录节点；必须先 source env.sh，
#    否则 PATH 里的旧工具链会段错误——本次实测：不 source 时连 trivial .c 都 rc=139）
ssh kunshan
source ~/tools/env.sh
export PATH=/public/software/apps/python/3.8.13/bin:$PATH
cd ~/core
AM_HOME=$HOME/core/src/nexus-am CROSS_COMPILE=riscv64-unknown-elf- \
  bash verify/cases/build_dualchain.sh "$HOME/core/results/difftest/dualchain/build"
# 2) 把 build 产物两个 bin 放到作业脚本读取的位置（96-run-dualchain.sh 默认 IMG=~/core/test/bin/）
cp ~/core/results/difftest/dualchain/build/vdot_dualchain.bin \
   ~/core/results/difftest/dualchain/build/vdot_dualchain_g0.bin ~/core/test/bin/
# 3) 提交单例作业（清单外；自动走 90-budget-log.sh 记账）。
#    本次三臂 M9/M10/M11 使主镜像约 11–12 min；为留余量用 CASE_TIMEOUT_S=2400、作业墙钟 50 min
#    （实测 127142843：COMPLETED 00:16:46、ExitCode 0:0；默认 900 s 未在本次直接验证是否够用）
CASE_TIMEOUT_S=2400 sbatch --time=00:50:00 -p kshcnormal -N 1 -n 8 \
  ~/core/core-package/scripts/96-run-dualchain.sh
# 4) 取数 + 金模型逐行复核
grep -a '^DUALCHAIN M[0-9] dep ' ~/core/results/difftest/dualchain/cases/vdot_dualchain.<runid>.log
grep -a '^DUALCHAIN_G44 '        ~/core/results/difftest/dualchain/cases/vdot_dualchain.<runid>.log
python3 -I ~/core/verify/cases/dualchain_check.py --check-log <case_log>   # 期望 LOG_MATCH
# 5) G0 反例判负（必须 MISMATCH，不得 MATCH）
grep -a 'CASE vdot_dualchain_g0:' ~/core/results/difftest/dualchain/cases/vdot_dualchain_g0.<runid>.log
```

**用词核对**（2026-11-07 复核，逐条如实）：`grep -nE "优于同题|全场唯一|唯一.*优势" stage3/3.3/sections/dualchain.md`
→ 命中均为**禁止性说明句本身**（本节首注、§4.8.5 硬性约束、§4.8.6 第 2 条），**无一处作为结论使用**。
`grep -nE "延迟加速 ?(6|9)"` → **0 命中（rc=1）**。`grep -n "7 cyc"` → 全部在【对方文档】/口径说明语境，逐处带标记。

### 4.9 `sections/perf-slope.md`（**2026-11-07 00:45 整理版**）

> **来源**：`stage3/3.3/sections/perf-slope.md`（定稿版 22,151 B、177 行，2026-11-07 00:45 整理版；sha256 `feb28dcc…`）。**并入方式**：按 §4.6 的编号约定整件插入，源文件 `## 4.9.x` 降级为 `#### 4.9.x`，正文与源文件一致（仅标题层级与用词统一；含其【实测】/【实读】/【未运行】标签）；源文件头注的小节归属一致（标注 §4.9 小节）。本版为 R1 口径修订后的最终版（R² 公式修正为 `1−SSres/SStot` 并与独立恒等式交叉验证、四组 R² 改正为 0.994990/0.999230/0.999963/0.999964、机时按远端台账逐作业如实表（4 作业 5 行、实记 0.907）、补 `design/ALGORITHM.md:213` 偏离声明与 trisaul 逐格对照），取代 2026-11-06 16:51 并入的旧版。

> **版本**：XiangShan `913ddd3` / yunsuan `83059b5` / NEMU `a9dca53`（实施 HEAD）；基线 pin `a4eeaab` / `9559211` / `a683e0b`。**两种口径并列**：作业日志 `versions:` 行记录的是昆山源树的 git HEAD（`a4eeaab`/`9559211`）**+ 工作树改动**（实现在远端工作树中、未提交），不是 `913ddd3`；`913ddd3`/`83059b5` 是本地实施提交口径。两者不互称等价。
> **标注约定**：【实测】= 昆山作业实跑并取回日志；【实读】= 本次逐字读到仓内文件；【未运行】= 本次未执行。
> **数据源（全部来自一个作业）**：昆山作业 **`127043836`**（`kshcnormal`，8 核，`COMPLETED`，`Elapsed=00:08:53`，`ExitCode=0:0`）。
> 日志：`results/difftest/slope/98-slope-20261106T162837.log`（作业级，4,410 B）与
> `results/difftest/slope/cases-perf_base_slope.20261106T162837.log.gz`（emu 原始输出，4.76 MB → 145 KB gz）；
> JSON：`results/difftest/slope/98-slope-20261106T162837.json`（`status=通过`，8/8 criteria `达标`）；
> 复算件：`results/difftest/slope/98-slope-20261106T162837.recalc.json`（`calc_slope.py --out-json` 产出）。

> **报告侧补记（2026-11-08，本轮不重测斜率）**：本轮 `perf-repeat` 的 4 次重复只重测**中位数口径**（`T_steady` 中位数 1、极差 0；`L_vdot` 中位数 4、极差 0；作业 `127196036`），**没有重测本节的斜率**——`1.021 / 3.143 / 11.019 / 14.643 cyc/dot` 与四组 R² 仍是作业 `127043836` 的单批结果【未运行：本轮未重测】。两者只作**同量级交叉核对**（本节 `vdot/resident` 斜率 1.021 对 §4.2 的 `T_steady` 1，本节 `b2/resident` 11.019 对 §4.1 的 `B2` 9），**不相除**（§4.9.4 已把该纪律写成硬约束）。

---

#### 4.9.1 结论（三句话，先说清口径边界）

1. **斜率口径可行，且给出的是「每点成本」而不是延迟**：`vdot` resident 斜率 **1.021 cyc/dot**（三点 R²=0.994990；两点斜率 0.969，见 §4.9.3）、`b2` resident 斜率 **11.019 cyc/dot**（R²=0.999963）。两者同为 `cyc = a + b·N` 的最小二乘 `b`，**同一把天平的每点开销倍数 = 11.019 / 1.021 ≈ 10.8 倍**（这是「每点开销倍数」，**不是加速比**，也不是本报告 §4.3 的每指令 `1.33×`）。
2. **加 stream 类后倍数收窄到 ≈ 4.7 倍**（`b2` stream 14.643 vs `vdot` stream 3.143 cyc/dot，R² 均 ≥ 0.994990）：把「每点重新 load 两路 8 B」计入后，vdot 自身的每点成本从 1.02 涨到 3.14，涨幅（+2.12 cyc/dot）与 B2 的涨幅（+3.62）同量级 ⇒ 在**本用例的 stream 定义下**（同一对 16 B 缓冲、L1 命中，见 §4.9.4 边界），装载开销是共同成本，指令本身的优势被摊薄。
3. **`n=8` 这一点不能当结论用**：它是 `rdcycle` 括窗与 ROB 深度同量级的一点（三个窗口只有 11/22/28 拍），窗口可与内核体重排 ⇒ 该点的**绝对周期**不可引用；三点 R² 高（四组 0.994990–0.999964）只说明三点近似共线，**不说明测量稳定**。同一组数据的两点拟合（只用 N=64/512）给出 0.969 且与三点斜率同量级（1.021 vs 0.969）⇒ 无坏点的证据是**两点拟合一致**。**报告正文引用斜率时，必须同时给出两点拟合值。**

---

#### 4.9.2 三点原始数据（每点 3 个窗口，原样 CSV）

【实测】作业 `127043836`，`rounds_per_point=3`，同 VL=8、同 `buf_a`/`buf_b`、同 8 路独立 `vd`（`v8..v15`）展开。每行 3 个数是该点 3 个独立窗口的 `rdcycle` 差值（单位：周期），`median` 取这 3 个数的中位数。

| 通道 `ch` | 类 `cls` | N=8（cyc / median） | N=64（cyc / median） | N=512（cyc / median） |
|---|---|---|---|---|
| `vdot` | `resident` | `28,22,11` / **22** | `185,94,119` / **119** | `681,553,553` / **553** |
| `vdot` | `stream` | `46,26,26` / **26** | `394,250,197` / **250** | `1771,1630,1579` / **1630** |
| `b2` | `resident` | `86,86,86` / **86** | `892,740,717` / **740** | `5794,5655,5645` / **5655** |
| `b2` | `stream` | `121,119,119` / **119** | `1138,987,937` / **987** | `7625,7519,7467` / **7519** |

机器可读原件（同一份数据，`results/difftest/slope/98-slope-20261106T162837.log` 逐行）：

```
SLOPE point ch=vdot cls=resident n=8 rounds=3 median=22 min=11 max=28 cyc=28,22,11
SLOPE point ch=vdot cls=resident n=64 rounds=3 median=119 min=94 max=185 cyc=185,94,119
SLOPE point ch=vdot cls=resident n=512 rounds=3 median=553 min=553 max=681 cyc=681,553,553
SLOPE point ch=vdot cls=stream n=8 rounds=3 median=26 min=26 max=46 cyc=46,26,26
SLOPE point ch=vdot cls=stream n=64 rounds=3 median=250 min=197 max=394 cyc=394,250,197
SLOPE point ch=vdot cls=stream n=512 rounds=3 median=1630 min=1579 max=1771 cyc=1771,1630,1579
SLOPE point ch=b2 cls=resident n=8 rounds=3 median=86 min=86 max=86 cyc=86,86,86
SLOPE point ch=b2 cls=resident n=64 rounds=3 median=740 min=717 max=892 cyc=892,740,717
SLOPE point ch=b2 cls=resident n=512 rounds=3 median=5655 min=5645 max=5794 cyc=5794,5655,5645
SLOPE point ch=b2 cls=stream n=8 rounds=3 median=119 min=119 max=121 cyc=121,119,119
SLOPE point ch=b2 cls=stream n=64 rounds=3 median=987 min=937 max=1138 cyc=1138,987,937
SLOPE point ch=b2 cls=stream n=512 rounds=3 median=7519 min=7467 max=7625 cyc=7625,7519,7467
```

> 上段逐行抄自 `98-slope-20261106T162837.log` 的 `^SLOPE point` 行（`grep '^SLOPE point'` 实读 12 行，与上表逐值一致）。

---

#### 4.9.3 斜率与 R²（最小二乘，整数拟合 + 独立复算）

【实测】拟合式（`design/verify/cases/perf_base_slope.c` 的 `fit_points()`，全整数运算，无浮点）：

```
b = (n·Σxy − Σx·Σy) / (n·Σx² − (Σx)²)                     # 单位 cyc/dot
a = (Σy·den − num·Σx) / (n·den)                             # 截距，单位 cyc（仅披露，不作结论）
R² = 1 − (den·(n·Σyy − Σy²) − num²) / (den·(n·Σyy − Σy²))   # 1 − SSres/SStot（SSres = Σy² − aΣy − bΣxy）
   = num² / (den·(n·Σyy − Σy²))                              # 独立恒等式，用于交叉校验
```

| 通道 / 类 | 三点斜率 `b`（cyc/dot） | 截距 `a`（cyc） | R² | **两点斜率（仅 N=64/512）** | 判定 |
|---|---|---|---|---|---|
| `vdot` / `resident` | **1.021** | 32.571 | **0.994990** | **0.969** | 三点与两点同量级（差 0.052） |
| `vdot` / `stream` | **3.143** | 23.429 | 0.999230 | **3.080** | 同量级（差 0.063） |
| `b2` / `resident` | **11.019** | 15.214 | 0.999963 | **10.971** | 同量级（差 0.048） |
| `b2` / `stream` | **14.643** | 24.429 | 0.999964 | **14.580** | 同量级（差 0.063） |

- 上表「三点斜率 / 截距 / R²」由 `calc_slope.py` 从 `SLOPE point` 的原始 CSV 重算（`SLOPE fit` 行同步打印五阶矩 `sx/sxx/sy/syy/sxy`，原件见 `results/difftest/slope/98-slope-20261106T162837.log`）：**斜率与用例内拟合逐值一致（Δslope=0 permille）**；**R² 两式（`1−SSres/SStot` 与独立恒等式）逐组精确同值（Δ0uu、`cross=OK`）**【实测】。日志内的 `SLOPE fit` R²（0.853631/0.969640/0.994642/0.993526）由**修正前**的旧式产生，可由旧式从同一批五阶矩逐值复现（Δ=0uu，见 §4.9.6），**不再用于任何结论**。复算命令与输出见 §4.9.6。
- **R² 的读法**：三点拟合只有 3 个点、1 个自由度，R² 高只说明三点近似共线，**不说明测量稳定** —— 四组 R² 落在 0.994990–0.999964，但 `n=8` 点的窗口只有 8 条 `vdot` 指令（~11–28 拍）、与 ROB 深度同量级，`rdcycle` 读可与内核体重排（`repos/XiangShan/src/main/scala/xiangshan/backend/fu/NewCSR/CSROoORead.scala:10-55` 的两个有序读列表均不含 `mcycle`/`cycle`；同源实测见 `design/verify/cases/perf_kernel_cmp.c:27-40`），该点的抖动**不因 R² 高而消失**。**因此本节的斜率以两点拟合为稳健性交叉，报告正文引用时两个数并列。**
- 截距 `a` 只作披露：它吸收「与 N 无关的窗口边缘固定项」（`rdcycle` 括窗与流水线重排的偏斜），本身没有物理含义（例如 `vdot/resident` 的 32.571 cyc 不代表任何一条指令的延迟）。**C 层循环开销随 N 增长（每 8 点 2 条指令），不是固定项，摊在斜率 `b` 里**（四组循环结构同形，见 §4.9.5(b)）⇒ 本节 `b` 是**含循环开销**的每点边际成本。

---

#### 4.9.4 三套口径不可混称（本节最容易被误读的地方）

| 口径 | 定义 | 本节的数 | 能回答什么 | **不能**回答什么 |
|---|---|---|---|---|
| **① 斜率口径**（本节主产出） | 同一变体测 N=8/64/512 三点的窗口周期中位数，对 `cyc = a + b·N` 做最小二乘，取 `b`（cyc/dot） | `vdot` resident **1.021**、`vdot` stream **3.143**、`b2` resident **11.019**、`b2` stream **14.643** | 「批量跑 N 个点时，每多点一个点的边际成本」 | 单条指令的依赖延迟；单条指令的稳态吞吐；任何「延迟加速」结论 |
| **② 中位数口径**（既有 `T_steady` / `L_*`） | 逐次 `rdcycle` 取差、去 16 次暖机、取中位数（`design/verify/perf/perf_vdot.c:41,43,118-129`） | `T_steady=1`、`B2=9`（`stage3/3.3/report.md` §1/§4.4） | 单条指令背靠背的每点开销 | 多规模标度；与①**不可互换、不可相除** |
| **③ 每指令 1.33×** | `L_base_chain_per_instr / L_vdot`（整数口径 1.25×，`perf_base_chain.c` + T5 三链） | 1.33×（`stage3/3.3/report.md` §4.3） | 「同一把天平上的每指令归一比值」 | 与本节的 10.8 / 4.7 倍**不是同一个量**：那两个是①口径内部的 `cyc/dot ÷ cyc/dot`，本节只写成「每点开销倍数」 |

**评分对应**：① 行对应 `docx/02-赛题与评分细则.md:90`「阶段三交付物完成度」中的「基线实现、延迟加速分析报告」（25 分档）——本节给出基线（B2）与 vdot 的每点成本对照、拟合质量与 stream 类边界，作为该分析报告的支撑材料之一；本节**不新增任何加速比表述**，§4.3 的每指令 `1.33×` 仍是仅有的加速比口径。

**三条硬约束（本文件自我约束，评审可机械核对）**：

- 本文件**不出现**「加速比」定义句；`10.8 / 4.7` 全部写成「每点开销倍数」。
- **不把①与②相除**：例如「1.021 vs `T_steady=1`」「11.019 vs `B2=9`」只能写成「同量级交叉核对」，绝不能写成「差 0.021」「差 2.019」。同量级核对本身也只是**披露**，不是判据（两者估计量与窗口结构都不同：本节窗口是 8 点展开，`T_steady` 是逐条括窗）。
- `L_base_chain=16`（含 `L_base_chain_per_instr=5`）是 `perf_base_chain.c` 的**独立测量项**，本节**不引用、不修改、不相除**（该文件与其镜像本次零改动，见 §4.9.5）。

---

#### 4.9.5 方法学：为什么用斜率、为什么这样切 stream、边界在哪

**（a）为什么斜率能消掉 `rdcycle` 的固定偏斜。** 香山的 `mcycle`/`minstret`/`cycle` 不在有序读 CSR 白名单（`CSROoORead.scala:10-55`），`rdcycle` 括窗可与内核体重排 ⇒ 单点绝对周期带一个**与 N 无关的固定偏斜**。对 `cyc = a + b·N` 拟合时，该固定项落进截距 `a`，斜率 `b` 不受其影响；`n=8` 点因窗口太短而抖动，正是这条机制的直接后果（§4.9.3）。

**（b）为什么每个 BODY 是固定 8 点 + C 层循环，而不是按 N 全展开。** N=512 的 B2 若用 `.rept 512` 展开会生成 ~26 KB 直落代码，把 L1I 打爆 —— 那时测到的是「代码体积」而不是「每点开销」。因此四个通道都用**同形的「8 点展开 + C 循环」**（`design/verify/cases/perf_base_slope.c` 的 `VDOT_RES_8`/`VDOT_STR_8`/`B2_RES_8`/`B2_STR_8` 与 `window_vdot`/`window_b2`），循环开销（计数器 + 分支，每 8 点一次）对四组**完全相同**，摊进斜率的是同一个量 ⇒ `b2 − vdot` 之差就是每点开销差，不被循环结构污染。

**（c）两条通道的「点」定义不同（已按各自既有定义对齐，不混称）。**
`vdot` 点 = 1 条 `vdot.vv`（8 路独立 `vd`，窗口内零 `vsetvli`、零读回）—— 与 `perf_vdot.c` 的 `T_steady` 同形态（`T_steady=1` cyc/dot，本节 1.021，**同量级交叉核对**）。
`b2` 点 = `perf_base.c` 的 `b2_once` 全序列（3 条配置 + `vmv.v.x v8` 死指令 + 归约初值 + `vwmul/vwadd/vredsum` + 读回配置 + `vmv.x.s`）—— 与 `B2=9`（每点开销）同形态。`perf_kernel_cmp.c:11-13` 把 `vmv.v.x v8, zero` 当死指令**删掉**了；本用例与 `perf_base.c` 一致**保留**（因为 `B2=9` 就由 `perf_base.c` 定义），两者差 1 条指令是**已知差异**。

**（d）stream 类的边界（必须一起读，否则会把 4.7 倍读成内存带宽结论）。**
stream = **每点重新 load 两路 8 B**（`vle8.v v3,(a0)` + `vle8.v v4,(a1)`，随后 `vdot` 读 v3/v4；B2 侧同样在首条 `vsetivli e8,m1,vl=8` 之后插 2 条 load）。两个地址是**同一对 16 B 缓冲 `buf_a`/`buf_b`（L1 常驻）**，不是遍历大数组 ⇒ 本节量的是**装载通路吞吐 + 计算**，**不是 DRAM/LLC 带宽**。报告正文不得据此写「内存受限时只有 1.0×」之类结论；若要该结论，需要另做「大工作集、逐点换地址」的用例【未运行】。

**（e）自检（防假通过）。** 用例每跑完一组就回读结果与软件模型比对：`vdot` 读 `v8` 与 `v15` 都必须等于 `0x00000008` 且都不等于「只归约前 4 lane」的错值 `0x00000012`；`b2` 读 `v10` 同样两个断言。作业日志四条 `SLOPE check` 全 `match=OK not_vl4=yes`，另有 `vl=8`、编码 `0x3A20A1D7`、单调性 `increasing=yes` 四项总检 ⇒ `SLOPE verdict=ALL_OK`【实测】。**未覆盖**：本次没有做「N 与实际点数」的独立计数（如 `minstret` 对账），点数的真实性由 `cyc ∝ N` 的单调性与拟合线性间接支撑 —— 这是本节承认的残余风险。

**（f）与 trisaul 的方法学逐格对照（外部参照，口径不同、不相除）。** 对手公开材料记录 cccs/trisaul 的方法是「4 workload（resident/batch/chain/stream）× 3 基线 × N=128/512/2048 线性拟合 + R²（0.997–1.000）」。对手公开材料能逐格引到的只有 `rvv_strict`（保留每次完整目的语义）一列的斜率与部分 vdot 列：

| workload | trisaul `rvv_strict` 斜率（cyc/dot） | trisaul vdot 斜率（cyc/dot） | 逐格 R² |
|---|---|---|---|
| resident | 8.00 | 1.05 | 全表范围 0.997–1.000（逐格值本地未载） |
| batch | 6.00 | 本地未载 | 同上 |
| chain | 29.00 | 6.99 | 同上 |
| stream | 19.72 | 18.95 | 同上 |

另两条基线与逐格 R² 的单元格在对手公开材料的摘录中未记录（其 `fits.csv` 未收录），**不补造**。本节 `b2/resident` 11.019 与上表 8.00 同为「每点成本」量级，但分母定义（配置/清零是否外提、N 点集）与本节窗口斜率不同 ⇒ **只作量级参照，不相除、不换算**；trisaul 自报的比值列见其 `report.md:5-14`，本节不引用、不互引。

---

#### 4.9.6 复算与机时

**复算（可复跑，命令逐字可抄）**：

```sh
python3 results/difftest/slope/calc_slope.py \
  --log results/difftest/slope/98-slope-20261106T162837.log \
  --json results/difftest/slope/98-slope-20261106T162837.json \
  --out-json results/difftest/slope/98-slope-20261106T162837.recalc.json
```

【实测】退出码 0，输出摘要（`fit2` 两行从略）：

```
[OK] b2/resident: slope=11.019 cyc/dot (case 11.019) intercept=15.214 cyc | r2=0.999963 ident=0.999963 (Δ0uu, cross=OK) case_r2=0.994642 [LEGACY:日志由公式修正前二进制产出] | rawΔslope=0pp
[OK] b2/stream: slope=14.643 cyc/dot (case 14.643) intercept=24.429 cyc | r2=0.999964 ident=0.999964 (Δ0uu, cross=OK) case_r2=0.993526 [LEGACY:日志由公式修正前二进制产出] | rawΔslope=0pp
[OK] vdot/resident: slope=1.021 cyc/dot (case 1.021) intercept=32.571 cyc | r2=0.994990 ident=0.994990 (Δ0uu, cross=OK) case_r2=0.853631 [LEGACY:日志由公式修正前二进制产出] | rawΔslope=0pp
[OK] vdot/stream: slope=3.143 cyc/dot (case 3.143) intercept=23.429 cyc | r2=0.999230 ident=0.999230 (Δ0uu, cross=OK) case_r2=0.969640 [LEGACY:日志由公式修正前二进制产出] | rawΔslope=0pp
[NOTE] case_r2 与旧式逐值一致的组：b2/resident, b2/stream, vdot/resident, vdot/stream —— 这些日志的 `SLOPE fit` R² 由 2026-11-07 公式修正前的二进制产出；上报 R² 以上行 r2=（按原始五阶矩重算）为准。
[OK] 全部 4 组：三点斜率/截距复算与用例内拟合一致；R² 两式（1−SSres/SStot 与恒等式）精确同值；case R² 为旧式（4 组，日志二进制早于公式修正），改正值以上行 r2= 为准
```

**R² 公式修正（2026-11-07）**：`design/verify/cases/perf_base_slope.c` 的 `fit_points()` 与 `results/difftest/slope/calc_slope.py` 旧实现都把 `SSres` 分子写成 `Syy·den − num·Σxy`（C 与 Python 同错 ⇒ 旧版「复算逐值一致」抓不到该错）。现两文件都改为 `R² = 1 − SSres/SStot`（`SSres = Σy² − a·Σy − b·Σxy = (den·(n·Syy−Sy²) − num²)/(n·den)`），并加**独立恒等式** `(n·Σxy−Σx·Σy)²/((n·Σxx−Σx²)(n·Σyy−Σy²))` 交叉校验：四组两式输出同值（`Δ0uu`、`cross=OK`，逐组见上行 `r2=` 与 `ident=`）。旧日志的 `SLOPE fit` R²（0.853631/0.969640/0.994642/0.993526）是旧式值——用旧式从同一批五阶矩复算逐值一致（Δ=0uu），**只作为历史日志识别，不再进入任何结论**；改正后四组为 0.994990/0.999230/0.999963/0.999964。

**与 `design/ALGORITHM.md:213` 报告级口径的偏离（如实声明）**：该处要求「同配置再跑 ≥5 次取中位数，并补 N=0/64/256/1024 的斜率回归（扣循环开销）」。本节是报告级口径的**补充证据**，有三处偏离：① 每点 3 个窗口（`ROUNDS=3`），未做 ≥5 次取中位数；② 用 N=8/64/512 三点，未做 N=0/64/256/1024 四点；③ 斜率**未扣** C 循环开销（循环开销随 N 增长、四组同形，落在斜率里，见 §4.9.5(b)）⇒ 本节 `b` 是**含循环开销**的每点边际成本。因此本节不能替代报告级口径本身；引用时按本节口径署名。

**机时（`90-budget-log.sh` 自动 + 人工补记，单位 node-hours；逐行按远端台账 `~/core/results/budget-log.tsv`）**：

| 作业 | 用途 | sacct 终止状态 | Elapsed | 台账行 | 记账 |
|---|---|---|---|---|---|
| `127035102` | 冒烟（`ROUNDS=2`） | `TIMEOUT`（10 min 上限） | 00:10:28 | 1 行（人工 `record`） | 0.174 |
| `127039213` | 冒烟（QUIET 版，验证打印是否瓶颈） | `FAILED`（1:0）【复审实测；本次未重跑 sacct】 | 00:10:02 | **2 行**（`auto` + 人工 `record` 重复登记） | 0.167 × 2 = 0.334 |
| `127041527` | 首次正式跑（`ROUNDS=3`，`CASE_TIMEOUT=900`） | `FAILED`：emu 在 900 s 被 `timeout` 杀掉，差 4 行收尾（`rc=124`） | 00:15:04 | 1 行（`auto`） | 0.251 |
| **`127043836`** | **正式出数（`ROUNDS=3`，`CASE_TIMEOUT=1800`）** | **`COMPLETED`（0:0）**，`status=通过`，8/8 criteria | **00:08:53** | 1 行（`auto`） | **0.148** |

> `sacct 终止状态` 与 `Elapsed` 两列来自前一批作业记录与复审实测；本次**未在昆山重跑 `sacct`**【未运行】，只读本地日志与台账摘要。

- **台账实记合计 0.907 node-hours（4 个作业、5 行）**：`127039213` 的 `auto` 与人工 `record` 各登记 0.167（同一作业重复），按唯一作业去重后为 **0.740**。两个数并列、不互相替代（0.907 为该批作业结束后的台账实记值；仓内 `results/budget-log.tsv` 是 2026-11-06 06:06:50 的快照，早于本节作业，不含这 4 行）。
- 两批冒烟（去重 0.341）与一次超时重跑（0.251）是**方法论成本**，如实计入，不隐去。
- 该量级与 `perf_base_chain`（1.5 h / 次）相比约 **2 倍**【推算】（去重 0.740 vs 1.5 h；实记 0.907 时约 1.7 倍）：本次不再跑 full 尺度，`L_base_chain=16` 旧数原样保留。
- **台账现状（实读快照，含并行工作项）**：`CORE_DIR=$HOME/core bash core-package/scripts/90-budget-log.sh summary`（2026-11-06 16:47:33 于昆山登录节点）
  → `P3-full 10.209/3.0（340%）`、`合计（不含缓冲）14.205/10.6`、`[超支] … 停跑、重估`，脚本退出码 **1**（实跑：`… >/tmp/bs.out 2>&1; echo $?` → `1`；不是合规状态）。
  该合计含本节去重 0.740（实记 0.907）与其它并行工作项的作业；**本节那部分可单独归因**。远端台账此后继续增长（最新合计 15.063，取自远端 `~/core/results/budget-log.tsv`），以远端为准。按约定不再为抬升 R² 而加跑。

---

#### 4.9.7 诚实边界（本节的「不能说什么」清单）

- **不能**把 1.021 / 3.143 / 11.019 / 14.643 写成任何形式的「延迟」「加速比」或与官方口径挂钩：这些是 `cyc = a + b·N` 的**批吞吐斜率**，内部自设口径（同 `perf_base_chain.c:55-56` 的「官方只要求用已有向量指令组合实现，未规定条数/延迟口径」）。
- **不能**把 `10.8 倍` 与 `1.33×` 并列成「两种加速比」：前者是同口径的每点开销倍数（`b2` vs `vdot` 的斜率比），后者是每指令归一的 `L_base_chain_per_instr / L_vdot`；两者分母不同、口径不同。
- **不能**把 stream 的 4.7 倍说成「内存受限下的真实差距」：工作集只有 32 B（§4.9.5(d)）。
- **不能**用三点的 R² 单独证明测量质量：三点拟合 R² 高（0.994990–0.999964）只说明三点近似共线；`n=8` 的窗口只有 ~11–28 拍、可与 ROB 重排，结论必须带两点拟合交叉（`vdot/resident` 三点 1.021 vs 两点 0.969）。
- **未运行**：逐点 `minstret` 对账（点数真实性）；大工作集 stream；`ROUNDS > 3` 的统计（机时预算否决，见 §4.9.6）。
- `n=8` 的绝对周期（22 / 26 / 86 / 119）**不作任何结论引用**，只作为拟合的低端锚点出现。

### 4.10 `sections/methodology.md`（**2026-11-06 13:57 定稿**）

> **来源**：`stage3/3.3/sections/methodology.md`（定稿版 34,562 B、221 行，2026-11-06 14:19 末次修订）。**并入方式**：原文三节 A/B/C **整节插入**此处（该文件原标注的位置是"§2 末 + §5 末"，但 §5.5/§5.6 已被机制解释与软硬协同占用，故按 §4.6 的并入约定整体并入 §4.10，只把标题层级降一级为 4.10.1–4.10.3，正文未改）。该文件的 D/E/F 三节是附录（引用清单 / 能力边界总表 / 并入说明），不进报告正文，见原文件 `:175-221`。

**并入约定三条**：① 三节正文与源文件一致（仅标题层级与用词统一；含其【实测】/【实读】/【推算】/【未运行】/【未核实】标签）；② 数字不与本报告其它节互引或相除；③ 该文件的 B/C 两节原本要写"§5.5 时序 / §5.6 功耗"，本报告保留其对"2 拍未收敛、功耗未测"的结论，但**标题改为 4.10.2 / 4.10.3**，避免与本报告 §5.5（4 cyc 机制解释）和 §5.6（软硬协同）编号冲突。

#### 4.10.1 测量口径防御（为什么这些数字可以信、信到什么程度）

本节回答三个问题：为什么主指标取中位数而不是均值或最小值；emu 的 `rdcycle` 能不能当硅延迟；不同口径的数字为什么不能合并。**结论先写：能信的是「同一把天平上的相对比较」；不能信的是「跨口径的绝对换算」。**

##### A.1 为什么取中位数：三个估计量的偏差方向不同

本报告主指标是 `L_vadd / L_vmacc / L_vdot` 的**逐次 `rdcycle` 差分中位数**（N_RAW=2000、丢前 `N_WARMUP=16` ⇒ 计入 1984 样本；`design/verify/cases/perf_vadd.c:42,44,84,90-101`、`perf_vmacc.c:42,44`、`design/verify/perf/perf_vdot.c:41,43,118-129`）。三链同 VL=8、同 SEW=8、同计数法，`cycles_per_op=` 是 median 的别名（`perf_vadd.c:138-144` 的 printf 把 median 同时打到 `cycles_per_op`）。

| 估计量 | 它假设什么 | 本环境的实际偏离 | 本报告的一手证据 |
|---|---|---|---|
| 最小值 `min` | 干扰只增周期、计数器读本身有序 ⇒ 最小值 = 干净样本（Agner Fog §18.1 方法 2） | `minstret/instret` 的读不按序、`mcycle/time` 可能被提前读（issue #6852）；本报告样本里还能直接看到**计数器回退**（`c1 < c0` 的无符号回绕） | `L_vadd` 的 1984 样本 `min=2`、`max=18446744073709551614`（= 2^64−2，说明至少一次 `c1<c0`）、`over=42`：`stage3/3.3/evidence/perf_vadd.20261103T075552.log:4`、`stage3/3.1.2-difftest/full-logs-20261103T142246/perf_vadd.20261103T142246.log:4` |
| 均值 `mean` | 噪声零均值、分布对称 | 宿主调度/中断是**单边**的（只加周期），均值被右尾拖高；但主指标三链 mean 与 median 同值 | `results/difftest/20-full-20261103T142246.json` → `metrics[]`：`L_vadd=3/L_vadd_mean=3`、`L_vmacc=4/4`、`L_vdot=4/4` |
| 中位数 `median` | 被污染样本 < 50% | 对低端回退与高端中断都不敏感；8 轮 × 2000 样本的基线链 **8/8 轮中位数都是 16**，16000 样本的均值也正好是 16 | `results/difftest/b3/91-b3-20261104T115624.log:5-13`（逐轮 `median=16 mean=16`；汇总行 `rounds_agree=yes`） |

**一句话**：中位数不是为了「更好看」，而是因为本环境的两个主要污染源一个向下（计数器读重排/回退）、一个向上（宿主调度），`min` 会被向下的污染骗到，`mean` 会被向上的污染拖高；中位数在污染样本不足一半时对两者都稳。**代价**：中位数不告诉你尾部形状，也不构成置信区间；所以本报告并列披露 `mean`、`min`、`max`、`over` 与逐轮中位数，读者可自行检查污染程度，而不是只看到一个中位数。

**可证伪条件（写进报告，供评委反向检查）**：若某轮中位数与其余轮不一致（`rounds_agree=no`），或 `mean` 与 `median` 的差大于 1 拍且方向一致，或 `over` 计数显著升高，则中位数本身也不可信，必须停下查测量链路。当前数据不触发：三链 mean=median（3/4/4）、基线链 `rounds_agree=yes`、`L_base_chain` mean=median=16；只有含离群的两条链并列披露 1 拍差（`L_base_chain_ladder` median 24 / mean 23；kernel `cyc_med=16 / cyc_mean=15`，`results/difftest/kernel/run-20261106T053316/93-kcmp-20261106T053316.log:14`）。

**两条必须同时写出的边界**：① `min=2`/`max=2^64−2` 不证明「某次中断真的发生了」——具体归因本次**未做实验**（没有关中断/关重排的对照），只作为「该样本集含低端与回退样本」的客观读数【未核实机制】；② 8 轮 × 2000 是本用例**自设尺度**（`design/verify/cases/perf_base_chain.c:55-56` 明写官方只要求「用已有向量指令组合实现」），不是官方规定口径。

##### A.2 emu 的 `rdcycle` 是模型周期，不是硅延迟

`rdcycle` 读的是 emu 里 RTL 模型的周期计数器（emu 由 Verilator 从 RTL 编译：`results/emu/10-build-20261103T032307.log:4,8`）。它回答「这个微架构在模型里要走几拍」，不回答「这颗芯片在硅上要几纳秒、能跑多少 GHz」。

- **它能支撑的结论**：同模型、同 VL/SEW/vtype、同计数法下的相对比较——`L_vdot` vs `L_vmacc`（4 vs 4）、`T_steady` vs `B1/B2`（每点开销倍数 6 / 9）、8 轮中位数一致性。
- **它不能支撑的结论**：绝对频率（Fmax）、ps 级延迟、mW 级功耗、跨工艺/跨平台换算。2 拍时序目标因此只能写「设计目标」（见 B 节），不能用 `L_vdot=4` 或 `ltp=22` 代替 STA。
- **它自身的可信度边界**：difftest 把 `mcycle..mhpmcounter31` 全部标成 `isPerfCnt`（`repos/XiangShan/src/main/scala/xiangshan/backend/fu/NewCSR/NewCSR.scala:942-943,1140`），`isSkipDiff = isMMIO || isNCIO || isPerfCnt`（`repos/XiangShan/src/main/scala/xiangshan/Bundle.scala:365,369`），提交级 `difftest.skip := dt_skip`（`repos/XiangShan/src/main/scala/xiangshan/backend/rob/Rob.scala:1544,1548`）。**所以 30/30 difftest 通过不验证计数器语义**；计数器路径的已知问题见 issue #6852（OPEN）与 #6501（OPEN），前者直接涉及本报告口径。
- **单次样本不是证据**：主指标是 1984 个样本的中位数；`over=0` 只表示直方图未越界，不表示无离群。离群值原样披露（`min`/`max`），不静默截断。
- **内核级数字的额外限制**：§4.5 的 `18/16/11/7` 用 `mcycle`/`minstret` 做批间差分，两个计数器都不在有序读 CSR 白名单，故只采用 route1（10 轮批间差分的原始增量中位数再除以 step），route2 不作判据（`report.md` §4.5）。

##### A.3 跨口径不合并：四条机械规则

1. **同对象、同计数法、同配置** ⇒ 可比、可相除。例：`L_vdot` vs `L_vmacc`（都是单指令 RAW 链、VL=8、N_RAW=2000、median）。
2. **同对象、不同计数法** ⇒ 并列，不相除。例：`L_vdot`（median 4）vs `L_vdot_loop`（整段墙钟 6）；`L_base_chain`（median 16，配置外提）vs `L_base_chain_ladder`（含 3 次 `vsetvli` 的 median 24）。用例头注明写「两个数不可相减」（`perf_base_chain.c:48`）。
3. **不同对象** ⇒ 只报裸比值并写清分母，不称「加速比」。例：`T_steady`（背靠背吞吐）÷ `B1/B2`（单 dot 整段每点开销）是「每点开销倍数 6 / 9」；原始 `L_base_chain / L_vdot = 16/4 = 4.0` 是「3 指令链 vs 单指令」的跨口径比值，本报告**不采用**；可采用的只有每指令归一 `L_base_chain_per_instr = L_base_chain/3 ≈ 5.33` 对 `L_vdot=4` 的 `1.33×`。
4. **不同平台/不同工艺** ⇒ 不合并、不换算。emu `cyc`、Yosys `cells`、FPGA `LUT/W`、ASIC `μm²/mW` 是四种量纲；`481 cells` 不能换 μm²，不能当功耗，不能与任何百分比合并。

> **核对问句（写数字前问三遍）**：① 这个数测的是什么对象？② 计数法是 median / mean / min / 整段墙钟中的哪一个？③ 分母是谁、和分子同对象吗？三问有一问答不上，就不写比值。

##### A.4 与 Agner Fog、Kalibera & Jones 的准确关系（避免夸大引用关系）

| 来源 | 原文口径 | 本报告的关系 |
|---|---|---|
| Agner Fog, *Optimizing subroutines in assembly language* §18.1（pp.154–155） | 读计数器前后插 `CPUID` 串行化（"You have to insert XOR EAX,EAX / CPUID before and after each read of the counters..."）；短代码「重复测、取最小值」（"assume that the lowest of the clock counts measured represents a situation where no interrupt has occurred"）；丢弃暖机 | **借其原则**（丢弃暖机、重复测量、报告一个稳健的次序统计量），**明确偏离**其「取最小值」——前提「计数器读有序」在香山 emu 上不成立（issue #6852；本报告样本里可见回退） |
| Kalibera & Jones, *Rigorous Benchmarking in Reasonable Time*, ISMM 2013, pp.63–74 | 层次化重复（iterations / executions / builds）+ **算术平均**（"Calculate arithmetic means of these measurements for different levels."）+ 效应量**置信区间**（"We exhort researchers to report confidence intervals for their results..."） | **借其层次化重复**（我方有 iteration 级 8 轮与 execution 级两个独立作业）；**不主张**中位数是他们的方法（全文正文只在引述他文时出现一次 "median"，且指的是 Mytkowicz 等人的观测，不是其方法）；我方**没有**算置信区间、**没有** build 级随机化 ⇒ 只写「可复现」，不写「统计显著」 |

**因此报告中不得出现的三句话**：①「中位数是 Agner Fog 的方法」；②「中位数是 Kalibera & Jones 的方法」；③「已做置信区间／统计显著」。正确写法是：「中位数是我方针对本机噪声结构选择的稳健估计量，与上述两份方法学来源的关系是借用其重复测量/层次化抽样原则，并对 `min` 口径做了有理由的偏离。」

---

#### 4.10.2 时序边界：2 拍是设计目标，不是收敛结论

**结论先写**：本报告**没有** STA，也没有 Liberty 与工艺库；2 拍是**设计目标（预算内候选）**，写成「已收敛」即为越界。

##### B.1 判据（内部预登记，统一定义）

闭合判据：`∀X∈{S1,S2,S3}: X_own + Δ_X ≤ P0`，`P0 = max(ltp(VIMac64b)=100, S3_own)`；K1 时 Δ 为 `S2 +22、S3 +0`，故在 `S3_own ≤ 100` 时真正起作用的约束是 `S2_own ≤ 78`。这是**相对预算**判断——问的是「新增 tap 会不会让某一段超过既有 `VIMac64b` 的最长拓扑路径」，不是「在目标工艺/目标频率下 setup 是否满足」。

##### B.2 现在有什么：每条证据能说明什么、不能说明什么

| 证据 | 数值 | 出处 | 能说明 | 不能说明 |
|---|---|---|---|---|
| `ltp(VdotReduce)` | 22 级 | `results/yosys/40-area-20261104T094144.json` → `metrics[1].longest_path`（作业 `126752216`、`status=通过`） | 新增树的**拓扑级数**远小于 `VIMac64b` 的 100 级 | 不能换 ps；不能证明 setup；`ltp` 只算单模块内拓扑（Yosys 文档原文见 D-9） |
| `ltp(VIMac64b)` | 100 级 | 同文件 → `metrics[0].longest_path` | 作为相对基准 `P0` | 同上 |
| 结构不变量 I1/I2 | `fireS1` 同使能同边界；结果寄存器与 `outCtrl` 在 C2 对齐 | `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:129-130,159-160`（端口连接与输出选路） | vdot 不新增流水级；第 2 拍与 `VIMac64b` 的第 2 拍并行 | 不证明该拍内组合延迟满足 |
| 交付形态的 2 拍目标 | `VimacCfg.latency = CertainLatency(2)` | `repos/XiangShan/src/main/scala/xiangshan/backend/fu/FuConfig.scala:551,563` | 交付配置写的是 2 拍 | 不是 STA 结论 |
| 面积 JSON 的性质 | `scope` 字段=「仅 vdot 数据通路模块，未含 VIMacU 其余部分，**未含工艺库**」 | 同 JSON 的 `scope` 字段（实读） | 该 JSON 不是可喂 STA 的网表 | 不存网表、不是 Liberty 映射后的标准单元 |

**缺什么（G-D 缺省）**：2026-11-04 24:00 设了 G-D 缺省——E-0/E-2 实测与 vmac 回归未齐时锁定 tap0/K1，2 拍只写「设计目标/预算内候选」，不自动升 3 拍、不启 X16（`design/ARCHITECTURE.md:103`）。**具体缺项**：`S2_own`/`S3_own` 切段探针（`design/verify/area/gen_probes.sh` 未建，该目录本次实读**只有** `build_area_rtl.sh`）、Liberty、Yosys 工艺映射（`dfflibmap -liberty` + `abc -liberty`）、OpenSTA、SDC 与 `report_checks`。

##### B.3 可学的先例：rvpeak 的 ASAP7 + OpenSTA 与负 slack 如实报告

同类作品 rvpeak（`yeyumeng7799/cie2026-rvpeak-vdot_llm_xiangshan`，本次实读 `README.md` @ commit `01996d9f92eb`，第 88-110 行）给出了一个**可复用的范式**：

| 项 | rvpeak 的做法（原文数值） | 值得学的点 |
|---|---|---|
| 工具链 | Yosys + OpenSTA + 固定版 OpenROAD-flow-scripts（`ORFS_ROOT` 指到 `0fcc4186e344f85167d97c1d67994bef01e89036`），脚本 `eda/run_eda.sh` | 工具版本固定，避免「换工具换结论」 |
| 约束 | 333 ps 参考预算（≈ 3.003 GHz【推算：1/333 ps】） | 预算明写，读者可自行换算 |
| 结果 | `VIMacU` 映射面积差 109.30626 µm²（约 1.73%）；预布局 STA 最差路径 **821.4327 ps**、路径裕量 **−488.4327 ps**（= 821.4327 − 333，本次复算一致） | **负 slack 照实写**，并声明「为后续优化提供模块级量化基线」 |
| 边界声明 | 「该结果基于公开 ASAP7 库与局部实验约束」 | 明确是工艺代理 + 局部约束，不冒充目标工艺签核 |

**我方与它的差距必须写明**：本仓**没有**做这一步（工具与工艺库都不在，见 B.5），所以本报告只能写「2 拍为设计目标」，**不能**写「已做 STA 且满足」。若后续补做，**负 slack 也照实写**，并按 rvpeak 的写法注记「工艺代理 + 局部约束 + 预布局」。

##### B.4 若要闭合：路线（本次未运行）

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

##### B.5 工具与工艺库可达性（本次实测，只核实不实跑 STA）

完整命令与原始输出：`stage3/3.3/evidence/sta-toolcheck-20261106.txt`（46 行，逐条命令 + 原样输出）。

| 位置 | `yosys` | `sta` | `openroad` / `opensta` | Liberty / PDK |
|---|---|---|---|---|
| 本机（开发机） | NOT_FOUND（`command -v` 无输出、`EXIT=1`） | NOT_FOUND | NOT_FOUND | 仓内 `*.lib/*.lef/*.sdc/*.db` **0 个** |
| 昆山登录节点（未 source） | NOT_FOUND | NOT_FOUND | NOT_FOUND | — |
| 昆山登录节点（`source ~/tools/env.sh`） | **可用**：`~/tools/yosys/bin/yosys`，`Yosys 0.48 (git sha1 aaa53474…)` | NOT_FOUND | NOT_FOUND | `module avail` 无 openroad/opensta/asap7/sky130（`grep` 退出 1）；HOME 内无 ORFS/OpenROAD 目录、无 `.sif`；`*.lib` 只命中 `core/src/nexus-am/Makefile.lib`（构建片段，非 Liberty） |

⇒ **STA 与 `report_power` 均【未运行】**：不是脚本出错，是工具与工艺库数据链缺失。本次**未安装、未构建、未下载任何 PDK**，未执行任何 STA 命令。

---

#### 4.10.3 功耗边界：RTL 级能说什么、不能说什么

**结论先写**：本报告**没有**功耗实测，也**没有**可换算成 mW 的 RTL 功耗估算。能写的是三条有证据的结构性事实 + 一条外部 FPGA 参照；不能写「功耗仅增 1.12%」「几乎不增功耗」这类把面积当功耗的句子。

> 口径定位：官方 3.3 的显式判据只有「Baseline 与 vdot 的 latency 加速比」（`docx/02-赛题与评分细则.md:66`）；功耗不是独立评分行，但官方描述提到低功耗（`docx/02-赛题与评分细则.md:18`）。本节是**防守性口径说明**，不冒充官方要求。

##### C.1 外部参照：Nanhu-vdot 的 +0.5% 是 FPGA 数，不是硅数

arXiv:2409.00661（Chen 等，2024）在 XiangShan Nanhu **最小配置**上做 vdot 扩展，报告：

| 项 | nanhu | nanhu-vdot | 增量（本次复算） | 口径 |
|---|---|---|---|---|
| LUT | 564,211 | 579,888 | +15,677（+2.78%，论文写 2.8%） | Xilinx VU19P FPGA（S2C Prodigy S7-19PS 机箱）+ Vivado 2020.2 综合实现 |
| Flip-Flop | 278,746 | 281,232 | +2,486（+0.89%，论文写 0.9%） | 同上 |
| BRAM | 436.5 | 436.5 | 0 | 同上 |
| 功耗 | 8.454 W | 8.494 W | +0.040 W（+0.47%，论文写 0.5%） | 论文只给数值，**未写**测量方法/活动率/VCD/SAIF；「Vivado 实现后功耗报告」是上下文推断【推算】 |

**用法与边界**：只能作为「同类 vdot 扩展在 FPGA 原型上资源/功耗增幅为个位数百分比」的**方向性佐证**；不能当香山 ASIC 的功耗数，不能把 +0.5% 搬到本设计。原因：① FPGA 功耗与 ASIC 功耗不是同一量纲；② 论文用**最小配置**（减少译码/执行单元、去 L2），与昆明湖 V2 全配置不同；③ 未给活动率/VCD/SAIF 设置，无法复算。

##### C.2 我方一手事实：面积占比 + always-on 结构

| 事实 | 数值 | 出处 | 能说明什么 |
|---|---|---|---|
| `VdotReduce` 全口径 cell 占比 | 481 / 42,783 = **+1.12%**（精确 1.1243%） | `results/yosys/40-area-20261104T094144.json` → `metrics[]`（`VdotReduce` 481 / `VIMac64b` 42,783） | 通用门计数的面积增量 |
| 组合口径 cell 占比 | 458 / 41,945 = **+1.09%**（精确 1.0919%） | `results/yosys/vdot.stat.json`（481 = 458 组合 + 19 `$_DFFE_PP_` + 4 `$scopeinfo`）+ `results/yosys/vmac_only.stat.json`（42,783 − 838 时序单元 = 41,945） | 组合逻辑增量；不含 19 FF |
| cell 组成（说明「面积占比 ≠ 功耗占比」） | `$_XNOR_ 134 / $_XOR_ 128 / $_MUX_ 105 / $_ANDNOT_ 32 / $_OR_ 23 / $_DFFE_PP_ 19 …` | `results/yosys/vdot.stat.json` → `num_cells_by_type`（本次实读） | tap 的 cell 类型比例与 `VIMac64b` 不同，不能假设「同比例同功耗」 |
| tap 的连接与使能 | `vdotReduce.io.sum_wo := vimacs(0).io.sum_wo`（常连，无 opcode 门控）；`io.vd := RegEnable(result, io.fireS1)` | `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:129-130`、`repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala:44` | 归约树对**每条 vimac** 都在算、都 latch |
| 选路只在输出级 | `outIsVdot = outCtrl.fuOpType === VimacType.vdot`；`Mux(outIsVdot, vdotReduce.io.vd, mgu.io.out.vd)` | `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:159-160` | 选路不 gate 树，只是选择输出 |
| 操作数隔离 | 未实现（列为可选低功耗项，收益未实测） | `design/ALGORITHM.md:114`（第 16 项，标「C 可选」） | 没有「vdot 空闲时钳 0」的机制 |

**由这些事实能推出的功耗结论只有一句**：新增逻辑的**面积**是 +1.12%；由于 tap 没有 opcode 门控，它的动态功耗在**每条 vimac** 上都会发生，而不是只在 vdot 上发生。这是定性成本，不是 mW 数字。

##### C.3 四条估算路线与可行性

| 路线 | 需要什么 | 现在能不能做 | 能产出 | 不能产出 |
|---|---|---|---|---|
| A. 面积代理 | 已有 481 / 42,783 | **能**（已完成） | 「cell 占比 +1.12%」 | 不能称功耗；不能假设 cell 电容/活动率相同 |
| B. 手算 `P_dyn = α C V² f` | `C`（Liberty/PDK）、`V`、`f`、`α`（VCD/SAIF 或假设） | **不能**（缺 C/V/f/α） | 若强行假设，只能给无量纲比值 | 不能给 mW；不能当实测 |
| C. OpenSTA/OpenROAD `report_power` | Liberty + 映射后网表 + 活动率（VCD/SAIF 或 `set_power_activity`） | **工具支持、数据链缺**；【未运行】 | 给定 Liberty/活动率下的 internal/switching/leakage/total power（W） | 没有 Liberty 就没有数；用公开 PDK 只是工艺代理 |
| D. 用现有 VCD 做活动率 | VCD 必须是真实时钟域、覆盖代表性负载 | **不能**：`stage2/2.2-rtl/wave/` 的 `key.vcd` 的 clock 是**采样域时钟**（每拍 dump 一次 ⇒ 摘录中恒为 1、窗口 [8377,8577] 内 **0 次翻转**），且仅 213 个时间戳、非 `VdotReduce` 独立 top | — | 不能当活动率证据 |

**OpenSTA 的能力边界（引原文）**：`report_power` 用 Liberty power models + propagated/annotated pin activities，报告 internal/switching/leakage/total power（"Power values are reported in watts."）；无仿真活动时用 `set_power_activity`，输入默认 activity=0.1、duty=0.5（OpenSTA Commands 页，本次实取）。这恰好说明：**没有 Liberty 和活动率，`report_power` 给不出有意义的数**。

##### C.4 禁止写法

- 不写「功耗仅增 1.12%」「功耗几乎不增」——1.12% 是 cell 占比，不是功耗。
- 不写「Nanhu-vdot +0.5% ⇒ 本设计也 +0.5%」——平台/配置/工艺都不同。
- 不写「OpenROAD 可算功耗 ⇒ 已算」——工具存在不等于数据链存在；本次【未运行】。
- 不写「tap 只在 vdot 时翻转」——源码显示它对每条 vimac 都 latch。

---
### 4.11 `sections/coverage.md`（**2026-11-07 08:54 实跑版**）

> **来源**：`stage3/3.3/sections/coverage.md`（定稿版 19,306 B、184 行，2026-11-07 08:54 实跑版；定稿版 sha256 `d60d2a2c7e1bbe6e35fe3c5ed8583b0cca8cc1eb157a4f03f7c9690ce6192346`）。**并入方式**：正文 A–F 六节**整节插入**此处，标题按 §4.6 编号约定降级为 4.11.1–4.11.6（节内 `### X.N` 降为 `##### X.N`），正文与源文件一致（仅标题层级与用词统一；含其【实测】/【静态】/【推算】/【未运行】标签）；仅把源文件内部的 `§A.1`/`§A.2`/`§B.4`/`§C`/`§D`/`§D.1`/`§D.3` 交叉引用按小节编号重映射为 `§4.11.1`/`§4.11.1（A.2）`/`§4.11.2（B.4）`/`§4.11.3`/`§4.11.4`/`§4.11.4（D.1）`/`§4.11.4（D.3）`。该文件头注的来源声明约定 §4.11 的正文与校验值按其更新、不一致时以其为准，本次照此执行。本版取代 2026-11-07 01:00 版：§A.2 与 §D 由「预算闸未放行（未运行）」改写为**实跑受阻**的实测记录（覆盖 emu 重建成功 110 min、`--diff` 用例退出段 SIGSEGV rc=139、`.coverage.dat` 0 字节、`--diff` 全跑即使不 dump 也在退出段崩溃、gdb 栈指向 `VerilatedCovImp::write`、line-only 修复作业 `127128086` 结果待收）；预算口径改为「用户授权越过自设 11.0 机时预算、超支如实入账」（`P3-full 14.808/3.0`、合计 `18.804/10.6`、`summary` EXIT=1）；`95-coverage.sh` 证据更新为实跑适配后 `sha256 7a1f98b6…`。**本节不含任何覆盖率数字：结构覆盖记【未运行（实跑受阻）】。** 另：B.2 表 F21 行的 `|S|` 在报告中作了纯 Markdown 转义（`\|S\|`，渲染结果相同；源文件 `coverage.md:45` 仍为未转义形式），否则该行会被表格语法切碎——后续更新请沿用同一转义。

> **位置**：本文件是 `stage3/3.3/report.md` **§4.11** 的正文来源（编号见 `report.md:154`），按 §4.6 的编号约定原文并入。
> **标注约定**：【实测】=本次命令输出或存量日志串逐字读到；【静态】=二进制/源码扫描；【推算】=由实测做的算术外推，非实测；【未运行】=本次未执行。
> **口径约定**：本节不出现任何加速比；`6 / 9` 不出现；面积/功耗不出现。全文只出现一种比值：**覆盖率**（命中格 ÷ 总格），与性能无关。
> **修订记录（2026-11-06）**：15:42 版曾并入 `report.md` §4.11；15:53 之后新增的 3 条证据行（30 行冻结清单回传、昆山登录节点干跑、昆山预算闸实跑）已随本次更新进入 §4.11。本文件后续修改时，`report.md` §4.11 同步更新。
> **来源声明（2026-11-07）**：本文件是 `report.md` §4.11 的源文件；§4.11 的正文与校验值按本文件更新，两者不一致时以本文件为准（编号见 `report.md:154`）。
> **修订记录（2026-11-07 实跑）**：§4.11.1（A.2） 与 §4.11.4 由「预算闸未放行（未运行）」改为**实跑受阻**的实测记录（覆盖 emu 建成、`--diff` 退出段 SIGSEGV rc=139、gdb 栈、line-only 修复作业 `127128086` 结果待收）；本次**仍不含任何覆盖率数字**。§4.11 并入时须整段更新。
> **数据源**：`stage3/3.1.2-difftest/full-logs-20261103T142246/`（30 份逐用例日志，作业 `126676734`，30/30 通过）+ 30 个 `.bin` 的编码扫描；结构覆盖实跑诊断在 `stage3/3.1.2-difftest/coverage/evidence/cov-debug-20261107/`；机读件在 `stage3/3.1.2-difftest/coverage/`。

---

#### 4.11.1 结论（三句话）

1. **功能覆盖已量化**：29 个 coverpoint × 30 例 = **870 格**，其中 `covered 11 / thin 15 / partial 2 / gap 1`；把 thin/partial 折算成「至少命中一次」则是 **28/29 项有命中**，仅 **F15 `vs1==vs2`** 仍为零命中（【实测】`summary.tsv`，生成命令见 `matrix.md` §0；30 例内为零，extra 的 `xo_v12_*` 10 例已通过，见 §4.11.3）。
2. **结构覆盖（RTL line/toggle）本次【未运行（实跑受阻）】**：2026-11-07 已在昆山实跑（用户授权突破自设 11.0 机时预算）：覆盖率 emu **重建成功**（`EMU_COVERAGE=1`，作业 `127117867`，构建 04:34→06:24 = 110 min，emu `sha256 b86f95b4…`、424 MB），但**覆盖构建的 emu 在 `--diff` 用例的退出段 SIGSEGV（rc=139）、`.coverage.dat` 为 0 字节**，30 例只跑完第 1 例即中止。定位（【实测】，`coverage/evidence/cov-debug-20261107/`）：`--no-diff -C 100 --dump-coverage` 可正常退出且 dat 达 **3.3 GB（100 条指令）**；`--diff` 全跑即使不 dump 也在退出段 rc=139；gdb 栈 `VerilatedCovImp::write → std::map::operator[] → _Rb_tree_insert_and_rebalance`（`Emulator::save_coverage ← ~Emulator ← main`）。**本次不写任何覆盖率数字**；修复方向 = 去掉 `--coverage-toggle` 的 line-only 重建（冒烟作业 `127128086`，**结果待收**），命令见 `matrix.md` §6.3。
3. **对外表述**：官方 12 项交付物里**没有「代码覆盖率」这一项**（`docx/02:45-66` 逐条核对）；本节的作用是给 **可行性 10 分格的「功能验证有效性」**（`docx/02:92`）与 3.1.2 协同仿真补**量化证据**，不声称完成一项官方覆盖率交付物。

---

#### 4.11.2 功能覆盖：29 coverpoint × 30 例

##### B.1 状态口径（固定，全文同一定义）

| 状态 | 定义 | 本次计数 |
|---|---|---|
| `covered` | **≥2 例**有独立证据（运行日志串 或 二进制/源码静态事实） | **11** |
| `thin` | 仅 **1 例**命中（命中但回归脆弱） | **15** |
| `partial` | 只在部分 bin 上命中，或只有 `--no-diff` 自检（缺 difftest 比对） | **2**（F14、F28） |
| `gap` | **0 例**命中 | **1**（F15） |

> 采样域：`legal` 只采 `trap==0` 的 vdot（对应 ACT4 `iff (ins.trap == 0)`）；`trap` 只采非法陷入。**负例不向 legal 域贡献**。**例外（仅 F28 一项）：F28 是 bin 级寄存器索引空间，按「真实发射过的编码」统计，含负例编码；其合法子域在 §4.11.2（B.4） 单列**（不把负例算进 legal 子域）。四例不发射 vdot（`vadd-microbench`/`perf_base`/`perf_vadd`/`perf_vmacc`，二进制扫描 0 个 vdot 编码）在所有 CP 上记 `na`，**不充当命中格**。

##### B.2 11 个 `covered` 与 1 个 `gap`（摘要；全表见 `matrix.md` §2）

| CP | coverpoint | 状态 | 命中 | 一手证据（【实测】日志串 /【静态】编码） |
|---|---|---|---|---|
| F01 | `vstart_zero` | covered | 18 例 | 18 例合法执行（GOOD TRAP ∧ ABORT=0），源码无 `csrw 0x008` |
| F04 | `vl_not_max` | covered | 16 例 | `li t1,8` 主体 + `MATRIX vlinvar vl=1..8 … OK` |
| F06 | `vtype_prev_vill_clear` | covered | 18 例 | 未写非法 vtype |
| F11 | `vm_unmasked` | covered | 18 例 | 编码全 `vm=1`（30 个 `.bin` 扫描） |
| F16 | `vtype_sew_8` | covered | 17 例 | `vsetvli … e8` + 合法执行 |
| F18 | `vtype_lmul_1` | covered | 17 例 | `vsetvli … m1` |
| F19 | `lmul_ne_1_trap` | covered | 3 例 | `vdot_ill_lmul{2,4,8}` 各 `HIT CRITICAL ERROR`=1 |
| F21 | `vs1_vs2_edges` | covered | 7 例 | 操作数含 `-128`/`127`/`0` 或 `\|S\|>32767`（`bound1` S=131072、`bound2` S=−130048、`bound4` S=129032） |
| F23 | `hi96_zero` | covered | 16 例 | 运行行 `hi_nonzero=000` / `hi=[0x00000000 0x00000000 0x00000000]` |
| F26 | `back_to_back_raw` | covered | 3 例 | `MATRIX back_to_back … OK`、`MIX verdict=ALL_OK`、`chain=OK` |
| F29 | `sign_mix` | covered | 13 例 | 操作数正负混合（pos2/neg_odd*/bound2/bound3/bound5/rand/matrix/mix） |
| **F15** | **`vs2_eq_vs1`** | **gap** | **0 例** | **30 例全部是 `vs1=v1`、`vs2∈{2,10}`；无一条 `vs1==vs2` 编码** |

##### B.3 15 个 `thin`（单例依赖，回归脆弱）

`F02`(vdot_ill_vstart) `F03`(vdot_rand，`li t1,16`=VLMAX) `F05`(vdot_matrix vl=0) `F07`(vdot_ill_vill) `F08`/`F09`/`F10`(vdot_matrix vta×vma 4/4) `F12`(vdot_ill_vm0) `F13`(vdot_matrix `overlap_vd_eq_vs1`) `F17`(vdot_ill_sew) `F20`(vdot_ill_vs) `F22`(vdot_rand 1024 组) `F24`(matrix `oldvd_prefill`) `F25`(matrix `vxsat before=0x0 after=0x0`) `F27`(vdot_rand 16 字节随机)。

> **风险直说**：`F05/F08/F09/F10/F13/F24/F25` **只由 `vdot_matrix` 一例支撑**，`F03/F22/F27` **只由 `vdot_rand` 一例支撑**。这两例都**不在** `--smoke` 白名单里（`20-run-difftest.sh` 的 `class_selected()`），因此**不能用 smoke 产物出覆盖率报告**；覆盖率跑必须全选 30 例。

##### B.4 寄存器索引空间（F28 = partial）

| 操作数 | 命中 bin | 未命中 | 命中率 |
|---|---|---|---|
| `vd` | 16/32（v0, v1, v3–v16） | v2, v17–v31 | 50% |
| `vs1` | 5/32（v0, v1, v2, v4, v8） | 其余 27 个 | 16% |
| `vs2` | 3/32（v0, v2, v10） | 其余 29 个 | 9% |

> `vs1`/`vs2` 的 v0/v4/v8 来自**非法编码**（`vdot_ill_sew` 的 `vd=vs1=vs2=v0`、`vdot_ill_lmul*` 的组基址）；**合法域**的 `vs1` 实际只有 `v1`，`vs2` 只有 `{2,10}`。这就是 F28 记 `partial` 而不是 `covered` 的原因。

##### B.5 与对手调研稿（§4.1）的差异

| 差异 | 调研稿 | 本文 | 原因 |
|---|---|---|---|
| 状态计数 | covered 20 / thin 7 / partial 1 / gap 1 | **covered 11 / thin 15 / partial 2 / gap 1** | 调研稿按「≥2 例**或** ≥1024 样本」判 covered，且把 4 个不发射 vdot 的例算进合法域；本文按「≥2 例**独立命中**」且这 4 例判 `na`。**更严，不更松** |
| F14 `vd==vs2` | covered | **partial** | 调研稿把 `perf_vdot` 的 `--no-diff` 自检算 covered；本文要求 difftest 比对 |
| F28 寄存器空间 | vd 14/32、vs1 1/32、vs2 2/32 | vd 16/32、vs1 5/32、vs2 3/32 | 本文把 8 个负例的真实编码也计入索引空间 |

---

#### 4.11.3 扩容套件 `manifest.extra.tsv` 的补强（**224 例**，2026-11-08 实测）

主清单（30 行、`sha256 a90d1071…`）是官方回归口径的冻结件，**一行未动**；扩容用例全部落在 `design/verify/cases/manifest.extra.tsv`（**224 数据行**、本地 `sha256 9e72b97b…`：`vdot-pl` 98 / `negative` 57 / `vdot-ov` 56 / `vdot-base` 7 / `negative-legal` 3 / `g0` 2 / `vdot-rand10k` 1；`design/verify/cases/extra/spec.extra.json` 的 `rows=224` 与 `counts` 字段逐类同值）。与 30 例主清单合计 **254 个镜像**（远端工作目录名即 `vdot-254`）。

**对 30 例缺口的三条直接补强（【静态】`extra-static-scan.tsv` 是 **129 例快照**：129/129 文件扫到 vdot 编码；新增 95 例的 `.bin` 未取回本地——`ls design/verify/cases/extra/*.bin | wc -l` → 129、`*.c` → 224，故这 95 例的编码扫描【未运行】）**：

| 30 例缺口 | extra 补强 | 编码事实 |
|---|---|---|
| F15 `vs1==vs2` **gap** | `xo_v12_*` **10 例** | 10 个 `.bin` 含 `vs1==vs2` 编码 |
| F13 `vd==vs1` thin | `xo_vs1_*` 10 + 交叉 5 = **15 例** | 15 个 `.bin` 含 `vd==vs1` |
| F14 `vd==vs2` partial | `xo_vs2_*` **10 例**（走 `--diff`） | 10 个 `.bin` 含 `vd==vs2` |

> **已实跑覆盖（2026-11-08 终态）**：`94-extra-20261108T014445`（作业 `127194011`，`P3-full`，`started_at=2026-11-08T01:44:45+0800` → `ended_at=03:24:34+0800` ⇒ 墙钟 1:39:49）`status=通过`、**`selected=executed=pass=224`**、8/8 criteria `达标`（含 `golden_crosscheck=达标 :: EXTRA_CROSSCHECK verdict=MATCH`）；`counters={selected:224, executed:224, pass:224, not_run:0, reg_size_bad:0, selfcheck_req:162, selfcheck_ok:162, g0_req:2, g0_caught:2, neg_req:57, neg_ok:57}`。**本地复核（本轮实跑）**：`python3 -I design/verify/cases/extra_crosscheck.py --quiet` → `EXTRA_CROSSCHECK cases=224 reads_or_groups=10357 vdot_encs=415 problems=0` / `EXTRA_CROSSCHECK verdict=MATCH（全部期望常量与金模型逐条一致）` / `EXIT=0`。**同轮 30 例整份 `--full` 未跑通**：提交 exit=1，但 `find results -name '*20261108*'` 只命中 `results/difftest/perf-repeat/` 下的用例日志与汇总件、**零份 30 例产物**（本地 `out/audit/final/` 也只有 4 份 extra JSON），按分诊记录 `sacct -S 2026-11-08T00:00` 亦无对应 full 作业 ⇒ 记 **【未运行（无产物）】**，**不记通过**；30/30 的结论仍只来自历史作业 `126676734`（`142246`）/ `127137638`（`104227`）。**因此这三条补强已从「仅编码事实」升级为「编码 + 实跑」双重证据**；但 extra 仍不进 30 例主清单、不参与 `regression_delta`，F15 在 30 例矩阵内仍记 gap（§4.11.1）。上一轮 129 例 `127031933`（`94-extra-20261106T143635`）保留为**历史**（同一清单的前身）。

---

#### 4.11.4 结构覆盖（RTL line/toggle）：实跑受阻，数字【未运行】

##### D.1 实跑发生了什么（2026-11-07，用户授权突破自设 11.0 机时预算）

| 项 | 实测值 | 证据 |
|---|---|---|
| 覆盖率 emu 重建 | **成功**：04:34→06:24 = 110 min；emu `sha256 b86f95b4…`、424 MB | 作业 `127117867`；`coverage/evidence/cov-debug-20261107/` |
| 30 例运行 | **只跑完第 1 例**（`vadd-microbench`，GOOD=0）即中止 | 同上 |
| 第 1 例退出码 | **rc=139（SIGSEGV）**，`.coverage.dat` **0 字节** | 同上 |
| 无 diff 探针（`-C 100 --dump-coverage`） | rc=0，但 dat = **3 320 861 425 B（3.09 GiB）** | 诊断作业 `127126206` 的 p1 |
| `--diff` 全跑、**不 dump** | 用例跑完（`HIT GOOD TRAP` ×1、`Host time spent: 56266ms`），退出段 **rc=139** | 诊断作业 `127127119` 的 q1 |
| `--diff` + `-C 100` + dump | **rc=0**（截断到 100 条即可正常退出） | 同上 q2 |
| gdb 栈 | `std::_Rb_tree_insert_and_rebalance` ← `std::map<int,std::string>::operator[]` ← `VerilatedCovImp::write` ← `Emulator::save_coverage` ← `Emulator::~Emulator` ← `main` | 同上 q3（`evidence/cov-debug-20261107/dbg2/q3.log`） |

**结论**：① 崩溃在**退出析构段**（与 difftest 比对结果无关：q1 无 dump 也崩、用例本身通过）；② `--coverage-toggle` 的 dat 规模不可用（100 条指令 3.3 GB；`vtransform.py` 只认 `.v`、香山是 `.sv`，SRAM/Difftest 的 `coverage_off` 不生效 = 配方档 T2）；③ 短跑不崩、全跑崩。因此**本次不写任何覆盖率数字**，结构覆盖记 **【未运行（实跑受阻）】**，**不写「覆盖率达标」**。

**下一步（未完成）**：去掉 `--coverage-toggle` 的 **line-only** 重建（远端 `verilator.mk:72` 临时改 `--coverage-line`，备份 + diff 在 `evidence/cov-debug-20261107/dbg3/`），冒烟作业 `127128086` **结果待收**；若仍崩则改 `EMU_THREADS=1` 重建。重跑与解析命令见 `matrix.md` §6.3。

##### D.2 流水线状态（本次实测更新）

| 项 | 状态 | 证据 |
|---|---|---|
| `core-package/scripts/95-coverage.sh` | **实跑适配后 `bash -n` 退出 0**；本次新增三处最小适配：`NOOP_HOME` export（T9）、预算闸授权越过记「已越过」、`--skip-build` 记「已复用」 | 本地 `sha256 7a1f98b6…`；昆山部署件 `sha256 e243b7be…`（部署后仅 `--skip-build` 一处再改，台账见本节「预算闸」行） |
| 上游 9 个问题点（T1–T9） | 逐条在脚本里处置（T9=本次新增：`make -C difftest emu-mk` 必须 export `NOOP_HOME`） | 头注 T1–T9；作业 `127113117` 实测 rc=2 |
| 预算闸 | 脚本内置；本次按用户授权用 `--no-budget-guard` 越过，判据记「已越过」、JSON `budget_guard_bypassed=true` | 远端台账；超支事实由 `90-budget-log.sh auto` 入账（2026-11-07 08:54:48 summary：`P3-full 14.808/3.0`、合计 **18.804/10.6**、EXIT=1） |
| 昆山路径 | 10/10 `test -e` 命中（含 `build/rtl/SimTop.sv`） | `evidence/95-remote-pathcheck-20261107.txt` |
| 30 行冻结清单 | `~/core/test/manifest.30.tsv`，`sha256 e12470e6…`，30 数据行 | `evidence/95-remote-manifest30.txt` |
| 结构覆盖解析器 | 合成 fixture 6/6 通过；**元组口径已更正**为 `(covered, NOT_covered, pct)`，新增 `line_total` 列 | `evidence/vdot-structural-fixture-selftest.tsv` + `evidence/README-fixture-selftest.txt`；`parse_stats.py` 出五段长表 |

##### D.3 拿到可用 `.dat` 后的收集命令（可直接复制）

```bash
# 0) 核预算（自设 11.0 机时预算由用户授权越过；超支如实入账，不改判据）
ssh kunshan 'bash ~/core/core-package/scripts/90-budget-log.sh summary'

# 1) 提交（line-only 版 verilator.mk 已就位；不带 --skip-build 会重建）
ssh kunshan 'cd ~/core && sbatch -p kshcnormal -N 1 -n 32 --time=06:00:00 -J vdot-coverage \
  core-package/scripts/95-coverage.sh --manifest ~/core/test/manifest.30.tsv \
  --ref-so ~/core/src/NEMU/build/riscv64-nemu-interpreter-so --timeout 2400 --expect-rows 30 --no-budget-guard'

# 2) 短轮询（单次前台 ≤10 min）
ssh kunshan 'sacct -j <JOBID> --format=JobID,State,Elapsed -X'

# 3) 回传
rsync -a kunshan:~/core/results/coverage/<runid>/ results/coverage/<runid>/

# 4) 解析（五段报告 + 功能/结构）
python3 -I stage3/3.1.2-difftest/coverage/parse_stats.py \
  --log results/coverage/<runid>/merged.coverage/coverage_SimTop.log --out results/coverage/<runid>
python3 -I stage3/3.1.2-difftest/coverage/gen_hits.py \
  --manifest design/verify/cases/manifest.tsv \
  --logs results/coverage/<runid>/cases --log-suffix .log \
  --bins design/verify/cases --out results/coverage/<runid> \
  --statistics results/coverage/<runid>/merged.coverage/coverage_SimTop.log
```

**拿到数字后写时的三条硬性约束**：① `statistics.py` 的 line 覆盖只数 `if`/`end else` 行、toggle 只数声明行翻转 ⇒ 写「条件行覆盖率 + 信号翻转覆盖率」，**不写「语句覆盖率」**；② 元组是 `(covered, NOT_covered, pct)`，总数 = covered + not_covered（`statistics.py:309-315`）；③ 只报 `VdotReduce`/`VIMac64b`/`VIMacU`/`VIMacSrcTypeModule` 四个模块的 `tree_line`/`tree_toggle`，阈值初次不设。

---

#### 4.11.5 缺口与补测建议（可执行清单）

| # | 缺口 | 现状 | 补测建议 | 成本 |
|---|---|---|---|---|
| G1 | **F15 `vs1==vs2`** | 30 例 0 命中；extra `xo_v12_*` 10 例已随整套 **224/224** 通过（`127194011`；上一轮 129/129 `127031933` 为历史） | 若要把 F15 从 gap 升为 covered，需在 30 例主清单内加例（extra 不进官方清单）；否则报告按 gap 披露 | 0.2 机时 |
| G2 | **F28 寄存器空间** | vd 16/32、vs1 5/32、vs2 3/32 | 加 1 条 `vd/vs1/vs2 ∈ {0,1,15,16,31}` 扫描例（避开无意重叠 bin） | 0.1 机时 |
| G3 | **F14 只有 `--no-diff`**（30 例内） | extra `xo_vs2_*` 10 例走 difftest 且已随 224/224 通过（`127194011`）；30 例内仍只有 `--no-diff` 样本 | 在 30 例主清单内补 1 例 difftest 路径，或报告按 partial 披露 | 0.1 机时 |
| G4 | **F03 `vl_max`** | 30 例由 `vdot_rand` 的 `li t1,16` 命中；extra 的 `xb_vl_sweep` 只到 vl=8 | 在 `xb_vl_sweep` 加 `vl=16` 一档 | 0.1 机时 |
| G5 | **F25 `vxsat`** | 仅 `vdot_matrix` 1 例 | extra 加「先 `csrw vxsat,1` 再 vdot 再读回」 | 0.1 机时 |
| G6 | **7 个 CP 单点依赖 `vdot_matrix`、3 个依赖 `vdot_rand`** | 回归漏跑即回落为 gap | 覆盖率跑必须全选 30 例（脚本已如此） | 0 |
| G7 | **F23 `perf_vdot` 未断言高 96 位** | 16/18 合法例命中 | 若要 17/18，在 `perf_vdot` 链后加 `vse32.v` + 断言 | 0.1 机时 |
| G8 | **结构覆盖** | 【未运行（实跑受阻）】：覆盖 emu 已建，但 `--diff` 退出段 SIGSEGV（rc=139）、dat 0 字节 | line-only 重建后重跑（§4.11.4（D.1） 末段 + §4.11.4（D.3）） | 本次已耗 3.3 机时；重跑预计 2–3 机时 |
| G9 | ACT4 `cr_vtype_agnostic` / `mask_enabled` / `cp_masking_edges` | **结构性不可达**（vdot 合法编码强制 `vm=1`） | 报告写 N/A；用 F10/F11/F12 替代，**不伪造 ACT4 cross 命中** | 0 |
| G10 | ACT4 无 `vstart≠0`/`vill=1`/`VS=OFF` 的 trap bin | 用自定义 F02/F07/F20 覆盖 | 报告注明「ACT4 模板扩展」 | 0 |
| G11 | 分数 LMUL（mf8/mf4/mf2） | extra `xn_lmul_mf8/mf4/mf2` 已随整套 224/224 通过（`127194011`；历史 `127031933` 129/129） | 无（已闭合） | 0 |

---

#### 4.11.6 评分对应与诚实边界

| 评分格 | 本节提供的证据 | 边界（不得越界表述） |
|---|---|---|
| 可行性 10 分格「功能验证有效性：测试用例是否覆盖正数、负数、边界值，协同仿真是否通过」（`docx/02:92`） | 29 CP × 30 例 = 870 格矩阵；`covered 11 / thin 15 / partial 2 / gap 1`；正/负/边界/溢出四类各有定向例（F29/F21）；30/30 用例通过（`126676734`；**其中 `perf_vdot`/`perf_base`/`perf_vadd`/`perf_vmacc` 4 例按 `manifest.tsv:27-30` 第 4 列以 `--no-diff` 运行，属自检/性能口径，不计 difftest 逐位比对**）；扩容 **224/224** 通过（`127194011`，含 `golden_crosscheck=达标`；上一轮 129/129 `127031933` 为历史） | **不写「覆盖率 100%」**；gap 与 thin 逐条列出；结构覆盖【未运行（实跑受阻，§4.11.4（D.1））】；extra 不进 30 例官方清单；**30 例整份本轮 exit=1 且无产物，记【未运行（无产物）】**，不并入 extra 的通过数 |
| 3.1.2 协同仿真验证 | 覆盖率跑复用与 20-run **同一套自检串语义**（`95-coverage.sh` 的 `selfcheck_pattern()`），不另立宽松判据 | 覆盖率跑**未产出结果**（覆盖构建 + `--diff` 退出段 rc=139，§4.11.4（D.1）），30/30 的结论仍只来自 `142246` |
| 官方 12 项交付物 | **无「代码覆盖率」项**（`docx/02:45-66`） | 不声称完成一项官方覆盖率交付物 |

**四条诚实边界（必须与本节数字同页出现）**：

1. **结构覆盖是【未运行（实跑受阻）】，不是「低覆盖率」**：2026-11-07 实跑已建出覆盖 emu，但 `--diff` 用例退出段 SIGSEGV（rc=139）、`.coverage.dat` 0 字节（gdb 栈见 §4.11.4（D.1））；**没有数字，就不能说「RTL 覆盖率高/低」**。
2. **thin ≠ covered**：15 项只有 1 例支撑，回归漏跑即失效；本节不把它们合并成「28/29 覆盖」对外宣称（28/29 只是「至少命中一次」的折算，已在 §4.11.1 注明）。
3. **extra 已到实跑终态（224/224），但仍是清单外证据**：作业 `127194011` `status=通过`、`selected=executed=pass=224`、`golden_crosscheck=达标`（上一轮 `127031933` 为 129/129 历史）；`xo_v12_*` 10/10 通过。该结果**不进** 30 例官方回归清单，也**不参与** `regression_delta`，因此不得把 extra 的通过数并入「30/30」或「29 CP × 30 例」矩阵。**同轮 30 例整份未跑通**（提交 exit=1、零产物、`sacct` 无对应作业）⇒ 30/30 仍是历史作业结论，不因本轮 extra 通过而更新。
4. **条件行覆盖 ≠ 语句覆盖**（放行后写结构覆盖数字时同样适用）。

### 4.12 `sections/case-expand.md`（**2026-11-06 16:33 修订版**）

> **来源**：`stage3/3.3/sections/case-expand.md`（定稿版 15,172 B、139 行，2026-11-06 16:33 内容修订 / 19:10 修订；定稿版 sha256 `2f489d36…`；2026-11-07 复核零改动）。**并入方式**：按 §4.6 的编号约定整件插入，源文件 `## A. 4.12.N` 降级为 `#### 4.12.N`，正文与源文件一致（仅标题层级与用词统一；含其【实测】/【实读】/【推算】/【未运行】标签）。源文件内部的「§A.N」交叉引用已按小节编号重映射为 `4.12.N`（本版仅剩 `§4.12.2` 一处已重映射）。**2026-11-07 就地微调 2 处（与源文件的差异仅此两处，登记在此）**：① §4.12.2 对照表「随机」行判定「我方独有」改中性表述（对手口径标【对方文档】）；② §4.12.5 复现命令的 `94-extra-<runid>` 占位符落实为实测件 `results/difftest/extra/94-extra-20261106T143635.*`。本版取代 15:49 的早期版本（旧版通过数列为「见 §A.4」、作业号写 `127028127`）；更新依据为该文件 16:33 修订说明。
>
> **2026-11-08 补记（本轮同步，与源文件的差异登记在此）**：扩容清单已从 129 例扩到 **224 数据行**（`design/verify/cases/manifest.extra.tsv`，本地 `sha256 9e72b97b…`；`spec.extra.json` 的 `rows=224`），昆山整套实跑 **224/224**（作业 `127194011`，8/8 criteria、`EXTRA_CROSSCHECK verdict=MATCH`）。本节 §4.12.2/§4.12.3/§4.12.4/§4.12.5 的用例数、逐类通过与复现命令已按 224 改写；**上一轮 129 例（作业 `127031933`）的实测作为历史保留**。源文件 `sections/case-expand.md` 仍是 129 例快照、本轮**未改**。

#### 4.12.1 为什么扩：竞品标尺与评分对应

评分细则对「功能验证有效性」的要求只写到「正数/负数/边界」，但同题头部队伍的实际投递规模远高于此（各队公开仓库与投递材料，【对方文档】口径）：

| 团队 | 正常/定向 | 异常 | 寄存器重叠 | 流水/依赖 | 合计 |
|---|---|---|---|---|---|
| 香山芯锐 | 7（smoke） | **64** | **60** | **120** | **251 例** + 432 次等价调用 |
| 全栈漏洞队 | 含在流水/随机内 | 部分 | v0/v31 边界 | **1664 条流水压力** | ≈7664 次 |
| qixuan | 1518 单元 | 5 | 单元级 | 单元级 | 1518 + 1513 + 12 |
| Sun | 3 边界 + 3×100 随机 | 有 | 未单列 | 96 次 | 303 |
| **扩容前的我方** | 10 | 8 | **无独立分类** | `vdot_mix` 1 例 | **30 例**（`manifest.tsv`） |

上表的对比判读是：我方规模排第 6–7，且**缺「重叠」与「流水压力」两个独立分类**——而这正是芯锐 60 + 120 的得分点。本节的扩容就是针对这两个缺口，外加把异常矩阵从 8 类做成参数化组合。

**扩容的边界条件**：`design/verify/cases/manifest.tsv`（30 行、sha256 `a90d1071…`）是官方回归口径的冻结件，**一行未动**；扩容用例全部落在新清单 `design/verify/cases/manifest.extra.tsv`，由独立脚本 `core-package/scripts/94-run-extra.sh` 驱动（`20-run-difftest.sh` 未改）。这与 `perf_base_chain`、`vdot_xcontam` 的「清单外独立测量」裁定同口径（本报告 §1 的口径裁定）。

---

#### 4.12.2 覆盖点矩阵（分类 / 行数 / 通过数）

清单实读：`awk -F'\t' '!/^#/ && NF>=3' design/verify/cases/manifest.extra.tsv | wc -l` → **224 行**（表头 1 行不计；`spec.extra.json` 的 `rows=224`、`cases` 数组 224 条同值）。分类计数与逐类通过数见下表；「通过数」列的口径是 `94-run-extra.sh` 写出的 `cases.tsv` 第 3 列（`通过` 精确匹配），**未实跑的格子一律写「未运行」，不写「通过」**。本轮 `counters` 为 `selected=executed=pass=224`，且下表行数之和 = 224 ⇒ **逐类通过数 = 该类行数**（这是「全选全过」的算术结果；逐例 `cases.tsv` 本轮**未取回本地**，逐类数不是逐行读出来的）。

| 分类（`cls`） | 行数 | 配额 | 覆盖内容 | 通过数（按 `counters` 折算） | 证据 |
|---|---|---|---|---|---|
| `vdot-base` | 7 | =7（对齐芯锐 7 例基础） | 正/负/上边界/下边界/`vl=0..8` 全扫/`vta·vma` 四组合/旧 `vd` 预填 | **7/7** | `out/audit/final/94-extra-20261108T014445.json`（`counters`） |
| `vdot-ov` | **56** | ≥24 | 原 30 例：`vs2=vd` / `vs1=vd` / `vs1=vs2` 三类 × 10 组数据模式（正/负/奇数负/上边界/下边界/零/交错极值/量级不对称/lane8-15 干扰/随机）；**新增 26 例**：`alias3` 9 / `alias-wb` 5 / `alias-vl` 4 / `alias-lanehi` 4 / `alias-hi96` 4（`cover.extra.tsv` 的 `family` 列实读） | **56/56** | 同上 |
| `vdot-pl` | **98** | ≥40 | 原 48 例：背靠背 2/3/4/6/8、bubble 1/2/3/5/7、同 `vd` RAW 链 2/3/4/6/8、写回口竞争、控制流取消、异常构造-清除、高 96 位、旧 `vd`、循环；**新增 50 例**：`vd-reuse` 7 / `rotate` 6 / `cross-class` 6 / `bb-distinct` 5 / `waw-x` 5 / `war` 5 / `vtype-imm` 5 / `vl-imm` 5 / `raw-mid` 4 / `raw-cross` 2 | **98/98** | 同上 |
| `negative` | **57** | ≥32 | 原 41 例：`vill`(4) / `vstart`(6) / `SEW`(3) / `LMUL`(6：m2/m4/m8/mf8/mf4/mf2) / `mstatus.VS=OFF`(1) / `vm=0`(1) / SEW×LMUL 9 组合 / `vstart`×SEW 4 组合 / 双谓词同时不满足 3 / **非法优先于 `vl=0` 全写** 3；**新增 16 例**（同族扩展，`family=illegal`） | **57/57** | 同上（`neg_req=57 / neg_ok=57`） |
| `negative-legal`（**新增类**） | 3 | — | `negative-control`：构造非法前置但按合法路径执行的对照例（3 例） | **3/3** | 同上 |
| `g0` | 2 | ≥1 | 期望值故意错 1 bit（重叠类 1 例、背靠背类 1 例），必须 `CASE <cid>: MISMATCH` 且不得出现 `MATCH` | **2/2** | 同上（`g0_req=2 / g0_caught=2`） |
| `vdot-rand10k` | 1（10000 组） | 新增 | 固定种子 `20261106` 的 10000 组随机；期望由金模型烧进镜像，C 侧算法 B 独立复算（`model_bad` 必须 0） | **1/1** | 同上 |
| **合计** | **224** | ≥96 | — | **224/224** | `94-extra-20261108T014445.json` → `cases_pass=达标（224/224）`、`status=通过` |

**与竞品 251 例的逐类对照**（左列芯锐为【对方文档】，右列我方为本次实读清单行数；`g0` 2 / `negative-legal` 3 / `vdot-rand10k` 1 **不计入**「异常/重叠/流水/基础」四类）：

| 维度 | 香山芯锐 | 我方本次 | 判定 |
|---|---|---|---|
| 基础 | 7 | **7** | 打平 |
| 异常 | 64 | **57** | **少 7** |
| 重叠 | 60 | **56** | **少 4** |
| 流水/依赖 | 120 | **98** | **少 22** |
| 随机 | 未见独立随机套件 | **1 例 × 10000 组** | 我方本次新增独立随机套件；对手口径（【对方文档】）未见独立随机套件（其等价测试另计 144 配置 × 2 条 RVV），不作「独有」主张 |
| 合计 | 251 | **224 + 10000 组随机**（另含 `g0` 2、`negative-legal` 3） | 条数少 **27**，但**每行都是独立镜像 + 独立自检串**，不是同一程序里的子断言计数 |

**这张表怎么读（避免误读成「打平/超越」）**：
1. **条数不是同一量纲**。芯锐的 251 是【对方文档】的用例计数，本次**未复跑**其仓库；我方的 224 是 `manifest.extra.tsv` 的**数据行数**，本轮实跑 `selected=executed=224`（逐例一个独立镜像）；但**本地 `design/verify/cases/extra/` 只有 129 个 `.bin`**（`*.c` 有 224 个），新增 95 例的二进制在远端构建、未取回本地。每份镜像内还有 1–9 个断言点（最多的是 `xb_vl_sweep`：`vl=0..8` 共 9 个读回点）（`cover.extra.tsv` 的 `note` 列写明每行覆盖什么）。
2. **分类口径也不同**。我方 `vdot-ov` 的 56 行 = 「3 种重叠形态 × 10 组数据」的 30 行 + 26 行 alias 族，不是 56 个不同的重叠语义；`vdot-pl` 的 98 行按「形态 × 长度」展开（其中新增 50 行按新族展开）。
3. **本次仍未追平 251**。异常 57 < 64、重叠 56 < 60、流水 98 < 120，分别少 7 / 4 / 22。要追平需要把每类的数据模式从 10 组扩到 20 组以上，本次未做——每行都要独立编译 + 独立 difftest，224 行在 `--time=02:00:00` 内的实际墙钟为 **1:39:49**（作业 `127194011`，见 §4.12.4），仍在单作业 2 h 上限内。

---

#### 4.12.3 期望值来源：全部由金模型生成（可机械复核）

本节要求「期望值全部由 `design/verify/vdot_model.py` 金模型生成」。落实方式是**生成期烧常量 + 事后机械复核**两道：

1. **生成期**：`design/verify/cases/gen_extra.py` 逐条重放用例的指令序列，每遇 `vdot` 就调 `M.vdot_vv(vs1_reg, vs2_reg)` 取完整 128 位 `vd`，把低 32 位写成 C 里的断言常量（`if (got[i] != 0x........u)`）。生成器里**没有第二套点积实现**。
2. **事后复核**：`design/verify/cases/extra_crosscheck.py` 从 `.c` 源解析 `//@OP` 注释重新重放一遍，与源里**实际烧进去的常量**逐条比对；同时用 `M.decode_vdot_vv()` 反解每条 `vdot` 的机器码，确认 `(vd, vs2, vs1)` 与注释一致。

复核实跑（**本轮本地实跑**；昆山侧的同一脚本由 `94-run-extra.sh` 的 `golden_crosscheck` 判据承担，JSON 记 `EXTRA_CROSSCHECK verdict=MATCH`）：

```
$ python3 -I design/verify/cases/extra_crosscheck.py --quiet
EXTRA_CROSSCHECK cases=224 reads_or_groups=10357 vdot_encs=415 problems=0
EXTRA_CROSSCHECK verdict=MATCH（全部期望常量与金模型逐条一致）
EXIT=0
```

- `reads_or_groups=10357` = `vdot_rand10k` 的 10000 组 + 其余 **223 例的 357 个断言读点**（10357−10000=357，224−1=223；脚本只打印合计数，逐例分解本轮未打印）；`vdot_encs=415` = 清单里 `vdot.vv` 机器码的条数（含被 `jal` 跳过的边角条目）。上一轮 129 例的对应值为 `10162 / 191`（历史）。
- **负例不靠期望值**：57 个 `negative` 行的判据是「DUT/NEMU 双侧一致陷入非法」，由 `M.illegal_reasons()` 在复核阶段确认「该状态在模型里确实非法」（`extra_crosscheck.py` 的 `check_negative()`），运行时判据是 difftest 日志的 `HIT CRITICAL ERROR`；本轮 JSON `negatives_illegal=达标（57/57）`。
- **`vdot_rand10k` 的双算**：镜像里 `want10k[]` 由金模型生成；C 侧再用算法 B（`long long` 逐项累加）独立复算一遍并比对，不一致就打 `model_bad`。这样「Python 的 LCG 流」与「C 的 LCG 流」一旦分叉，`model_bad>0` 立刻判负，不会出现「DUT 与期望同时错」的假通过。

**G0 反例（假通过的机械证明）**：2 行 `g0` 的期望常量被**故意异或 1 bit**，程序仍正常走到结尾（`HIT GOOD TRAP`），因此只能被「自检串」判据抓住——日志必须出现 `CASE <cid>: MISMATCH` 且**不得**出现 `CASE <cid>: MATCH`。`94-run-extra.sh` 对 `g0` 类单独走这条判据并把 `G0_CAUGHT` 计入 `no_empty_green`。若某次 `G0_REQ>0` 而 `G0_CAUGHT<G0_REQ`，整套判「未达标」。

---

#### 4.12.4 昆山实跑结果（逐行 status）

> 本节数字**只写本轮实读到的**；未跑完的格子写「未运行」，未取回的证据写「未取回」。

**作业（当前终态，2026-11-08）**：`127194011`（`P3-full`，分区 `kshcnormal`，宿主 `a07r1n09`，清单 `/public/home/scnsokdzoq/core/vdot-254/manifests/manifest.full.tsv`，`rows=224`、远端 `sha256 ad787baa…`），`started_at=2026-11-08T01:44:45+0800` → `ended_at=03:24:34+0800` ⇒ 墙钟 **1:39:49**；JSON `status=通过`。**同轮提交的 30 例整份 `--full` 未跑通**：提交 exit=1，但 `find results -name '*20261108*'` 只命中 `results/difftest/perf-repeat/`、**零份 30 例产物**，`sacct -S 2026-11-08T00:00` 亦无对应 full 作业（分诊记录）⇒ 记【未运行（无产物）】；30/30 仍以历史作业 `126676734`（`142246`）/ `127137638`（`104227`）为准，**不因本轮 extra 通过而更新**。

| 分类 | 行数 | 通过 | 未通过 | 未运行 |
|---|---|---|---|---|
| `vdot-base` | 7 | 7 | 0 | 0 |
| `vdot-ov` | 56 | 56 | 0 | 0 |
| `vdot-pl` | 98 | 98 | 0 | 0 |
| `negative` | 57 | 57 | 0 | 0 |
| `negative-legal` | 3 | 3 | 0 | 0 |
| `g0` | 2 | 2 | 0 | 0 |
| `vdot-rand10k` | 1 | 1 | 0 | 0 |
| **合计** | **224** | **224** | **0** | **0** |

> 上表是 **作业 `127194011` 的实测终态**。JSON 顶层：`status=通过`、`counters={selected:224, executed:224, pass:224, not_run:0, reg_size_bad:0, selfcheck_req:162, selfcheck_ok:162, g0_req:2, g0_caught:2, neg_req:57, neg_ok:57}`；8/8 criteria `达标`（含 `golden_crosscheck=达标 :: EXTRA_CROSSCHECK verdict=MATCH`、`no_empty_green=达标`（自检串 162/162、G0 捕获 2/2）、`negatives_illegal=达标（57/57）`）。**证据边界（如实记）**：逐例日志与 `.cases.tsv` 留在远端 `…/vdot-254/results/difftest/extra/94-extra-20261108T014445.{log,cases.tsv}`，**本地只回传了 JSON**（`out/audit/final/94-extra-20261108T014445.json`）⇒ 逐类「通过」数按 `selected=executed=pass=224` 与该类行数推得，**不是逐行读 `cases.tsv`**；自检串 162/162、G0 2/2、负例 57/57 取自 JSON `criteria[].actual`，不是本地 grep 日志。

**上一轮（2026-11-06，129 例，历史记录；以下保留原样）**：

**作业**：`127031933`（`-p kshcnormal -N 1 -n 32 --time=02:00:00`，脚本 `core-package/scripts/94-run-extra.sh --manifest ~/core/test/manifest.extra.abs.tsv --timeout 600`），`COMPLETED`、`Elapsed=01:32:48`。
**被取消的前序作业（如实记）**：`127028127`（129 例全套，跑到第 50 例时被 `CANCELLED by 276820`，作业内 50/50 全通过）与 `127030078`（单跑 rand10k，3 分钟后同样被取消）。两次取消都发生在 14:26:03，同一账号下其它并行作业（`127029615`/`127030411` 等）也在同一分钟被取消 ⇒ 属**账号级并发回收**，与本用例无关；本次不把取消原因归给用例，也不把中途结果计入通过数。

**冒烟测试（暴露并修复三个真实问题，如实记录）**：作业 `127026020`（6 例冒烟）判 `失败 3/6`，暴露：
- `xn_sew_e16` 负例**根本没构造非法状态**（生成器 `emit_negative()` 读的是 `n["extra"]` 而不是 `n["pre"]`，状态序列为空）⇒ 哨兵串出现、`CRIT=0`。修复：改为遍历 `n["pre"]`。
- `xg0_overlap` 判 `GOOD=0 BAD=1`——G0 用例 `return 1` 导致 `HIT BAD TRAP`，判负原因退化成 BAD TRAP 而非「自检串未命中」。修复：G0 类统一 `return 0`（先例 `design/verify/cases/vdot_g0_badexp.c:38`）。
- `vdot_rand10k` `rc=124`（900 s 单例上限不够）。修复：`94-run-extra.sh` 给随机类单独 `RAND_TIMEOUT_S=5400`，且**不**参与「剩余时间/剩余用例数」均分（均分会把它压到几十秒）。
- 另：`golden_crosscheck` 初次报「缺 `spec.extra.json`」——上传包漏了该文件与 `.c` 源。已补传，昆山侧 `EXTRA_CROSSCHECK verdict=MATCH`。

| 分类 | 行数 | 通过 | 未通过 | 未运行 |
|---|---|---|---|---|
| `vdot-base` | 7 | 7 | 0 | 0 |
| `vdot-ov` | 30 | 30 | 0 | 0 |
| `vdot-pl` | 48 | 48 | 0 | 0 |
| `negative` | 41 | 41 | 0 | 0 |
| `g0` | 2 | 2 | 0 | 0 |
| `vdot-rand10k` | 1 | 1 | 0 | 0 |
| **合计** | **129** | **129** | **0** | **0** |

> 上表是 **作业 `127031933` 的实测终态**（`started_at=2026-11-06T14:36:35+0800`、`ended_at=2026-11-06T16:09:10+0800` ⇒ 墙钟 1:32:35；`--time=02:00:00` 内完成）。JSON 顶层：`status=通过`、`counters={selected:129, executed:129, pass:129, not_run:0, reg_size_bad:0, selfcheck_req:86, selfcheck_ok:86, g0_req:2, g0_caught:2, neg_req:41, neg_ok:41}`；8/8 criteria `达标`（含 `golden_crosscheck=达标 :: EXTRA_CROSSCHECK verdict=MATCH`）。
>
> 关键自检串实读：`grep -a "RAND10K" cases/vdot_rand10k.20261106T143635.log` → `RAND10K verdict=ALL_OK groups=10000 mism=0 model_bad=0 ab_bad=0`；`CASE xo_vs2_pos: MATCH`、`CASE xg0_overlap: MISMATCH`、`xn_sew_e16` 日志含 `HIT CRITICAL ERROR`。逐用例关键行已抽取为本地件 `results/difftest/extra/94-extra-20261106T143635.keys.txt`（129 行：86 条 `MATCH`、2 条 G0 `MISMATCH`、41 条 `HIT CRITICAL ERROR`、1 条 `RAND10K`），完整单例日志（约 4.7 MB/份）留在远端 `~/core/results/difftest/extra/cases/`。

> 复核命令（本地取回件）：`awk -F'\t' '{n[$2]++; if($3=="通过") p[$2]++} END{for(k in n) printf "%s %d/%d\n", k, p[k], n[k]}' results/difftest/extra/94-extra-20261106T143635.cases.tsv | sort` → `g0 2/2` / `negative 41/41` / `vdot-base 7/7` / `vdot-ov 30/30` / `vdot-pl 48/48` / `vdot-rand10k 1/1`；`grep -c 通过` → 129。

---

#### 4.12.5 工程形态与可复现

| 件 | 路径 | 作用 |
|---|---|---|
| 生成器 | `design/verify/cases/gen_extra.py` | 224 份 `.c` + `manifest.extra.tsv` + `cover.extra.tsv` + `extra/spec.extra.json`；生成期即做配额自检（`--check` 只打印不写盘） |
| 构建 | `design/verify/cases/build_extra.sh` | 逐例 AM 构建（`ARCH=riscv64-xs`），最后按清单核对产物齐备（**新增 95 例的 `.bin` 本轮未取回本地**，本地 `extra/*.bin` 仍 129 个） |
| 期望值复核 | `design/verify/cases/extra_crosscheck.py` | 金模型重放 + 机器码反解 + G0 错 1 bit 校验 |
| 运行 | `core-package/scripts/94-run-extra.sh` | 走 extra 清单的独立 difftest 作业（判据与 `20-run-difftest.sh` 逐条同构，**不改后者**） |
| 覆盖点表 | `design/verify/cases/cover.extra.tsv` | 每行 `cid / cls / family / 规范锚点 / 说明`，供本节表格机械汇总 |
| 用例清单 | `design/verify/cases/manifest.extra.tsv` | **224 条**用例及分类（本表数据来源；本地 `sha256 9e72b97b…`） |

复现三条命令（本地构建 → 昆山实跑 → 逐行取状态；`<runid>` 本轮为 `20261108T014445`）：

```
AM_HOME=<nexus-am> CROSS_COMPILE=riscv64-unknown-elf- bash design/verify/cases/build_extra.sh
sbatch -p kshcnormal -N 1 -n 32 --time=02:00:00 core-package/scripts/94-run-extra.sh \
       --manifest $HOME/core/test/manifest.extra.abs.tsv --timeout 600
awk -F'\t' '{n[$2]++; if($3=="通过") p[$2]++} END{for(k in n) printf "%s %d/%d\n", k, p[k], n[k]}' \
    results/difftest/extra/94-extra-20261108T014445.cases.tsv
```

**未做与边界（不作达标声明）**：
- 未追平芯锐 251（异常 57/64、重叠 56/60、流水 98/120，分别少 7/4/22，见 §4.12.2 对照表）。
- 竞品 251 的分布是【对方文档】口径，本次**未复跑**其仓库；本节的对照只作规模参照，不作「谁更强」的结论。
- `manifest.extra.tsv` 的 224 行**不进** 30 例官方回归清单，也不参与 `regression_delta`（该判据的基线是 `results/difftest/baseline.tsv` 的 30 行）。
- 机时（本轮）：作业 `127194011` 的 `started_at`→`ended_at` 实算墙钟 **1:39:49（=1.664 h，1 节点）**；**远端 `90-budget-log.sh` 台账本轮未读取【未运行】**，故只写墙钟、不写「已入账 X node-h」；按 §4.12 上一轮同口径（32 核 × 5557 s ⇒ 1.544 node-h）折算，若本轮核数同为 32 则约 1.664 node-h —— 该折算**依赖未核实的核数**，只作量级参考。**上一轮（历史）**：`127031933` 由 `90-budget-log.sh auto` 记 `1.544 node-h`（32 核 × 5557 s），跑完 `summary` 显示 `P3-full 8.862/3.0（295%）`、合计 `12.858/10.6`、**EXIT=1**，超支事实照旧披露。

### 4.13 `sections/innovation-p2.md`：P-2 跨拍 CPA 重定时（**2026-11-07 13:52 定稿版**）

> **来源**：`stage3/3.3/sections/innovation-p2.md`（定稿版 19,045 B、163 行，2026-11-07 13:52；sha256 `a91f824486cf78223abbd8b310a9ac82d1e87995c2aba339c5a8870ac6bb1909`）。**并入方式**：按 §4.6 的编号约定整件插入（**第七件**，小节号按 §4.6 表定为 §4.13），源文件 `## 4.13.N` 降级为 `#### 4.13.N`，正文与源文件一致（仅标题层级与用词统一；含其【实测】/【推算】/【未运行】标签）；源文件头注的小节归属一致（标注 §4.13 小节）。**与其它六件的性质差别（如实登记）**：本件是**改 RTL 之后的新增实测**（`VdotReduce.scala` `+19 / −6` 行），不是既有数字的旁证——§5 的 481 / 22 仍是 K1（公开仓 9 个基线 patch 可复现）口径，P-2 的 **500 / 14** 是**本地实测值**、单列于本节，其可复现性以 `patches/0005-X-new-P-2-VdotReduce-carry-save-retiming-yunsuan.patch` 为准（源文件首注「公开仓可复现性」）；报告**不把 500/14 写进 §5 的面积基线**，也不把它写成「时序收敛」（无 STA/liberty，§4.13.5 第 1 条）。

> **小节归属**：本文件并入 `stage3/3.3/report.md` **§4.13**（§4.6 专题小节的第七件；本节编号按 `4.13.x` 书写）。**正文只写本节实测**，不引用未复跑的外部数字。
>
> 日期：2026-11-07 ｜ 设计依据：P-2 预登记（候选 A）
> 改动文件：`repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala`（**仅此一个**；`+19 / −6` 行，`git -C repos/XiangShan/yunsuan diff --stat` 实测）
> 昆山作业：重建 `127135641` ｜ 30 例 `--full` `127137638` ｜ 面积 K1 `127135437`、P-2 `127137643` ｜ extra 129 `127137640`
> 证据（本地副本，与远端同 sha256）：`results/emu/10-build-20261107T100125.{json,log}`、`results/difftest/20-full-20261107T104227.{json,log,cases.tsv}`、`results/difftest/94-extra-20261107T104230.{json,log,cases.tsv}`、`results/yosys/40-area-20261107T095404.*`（K1）、`results/yosys/40-area-20261107T104238.*`（P-2）、`results/yosys/vdot-{k1,p2}.{stat.json,ltp.txt,stat.cmos.txt}`
>
> **公开仓可复现性（2026-11-07 终检披露）**：P-2 的源码改动在本机子仓 `repos/XiangShan/yunsuan` @ `8942811`（父提交 `83059b5`），完整 diff 已按 `git -C repos/XiangShan/yunsuan format-patch -1 8942811` 原样落到根仓 `patches/0005-X-new-P-2-VdotReduce-carry-save-retiming-yunsuan.patch`（3,587 B，sha256 `2d25778c…`；在 `83059b5` 工作树上 `git apply --check` rc=0，在 `8942811` 上 `git apply -R --check` rc=0）。**公开仓 `origin/master=4e323d8` 不收录该 patch，且 `repos/` 被 `.gitignore` 排除**（`git ls-tree -r 4e323d8 | grep -c '^repos/'` = 0），故只按公开仓的 9 个基线 patch 复现得到 K1 的 **481 / 4,900 / 22**，**得不到本节的 500 / 4,900 / 14**；评审复现 500/14 须在 `0002-X15`、`0003-X-new` 之后应用 `patches/0005-…`，再按 §4.13.7 重跑。本节的 500/14 是**本地实测值**，其可复现性以该 patch 为准。

---

#### 4.13.1 结论（先看这里）

| # | 结论 | 证据 |
|---|---|---|
| C1 | **改动面 = 一个文件、一处切点**：4:2 树的 `(sum, carry)` 冗余对（2×19 = **38 FF**）过 `io.fireS1` 边界，19 位 CPA 与 `Cat(96'b0, sext32(S))` 格式化移到寄存之后的**输出拍（S3）**；`VdotReduce` 的三个端口（`sum_wo`/`fireS1`/`vd`）、`VIMac64b`、共享 `VimacCfg`、wrapper `VIMacU.scala` **均未改**。 | `VdotReduce.scala:49-57`；生成的 SV：`reg [18:0] sumS2/carryS2`、`assign io_vd = {96'h0, {13{cpa[18]}}, cpa}`（§4.13.2） |
| C2 | **面积实测 481 → 500 cells（+19）**，组合部分 **458 → 458（不变）**，增量**恰好是 38−19 = 19 个 FF**；`VIMac64b` 对照 42,783 / ltp 100 逐值未变。 | `40-area-20261107T104238.json`；`vdot-p2.stat.json` 的 `$_DFFE_PP_ = 38`、`$scopeinfo = 4`（§4.13.3） |
| C3 | **最长组合路径 22 → 14 级（−8 级，−36.4%）**，且 ltp 报出的起点是 `\sumS2`（即寄存器之后的 CPA 段），说明 S2 侧树锥已不再是模块最长路径。 | `vdot-k1.ltp.txt` 22 级 vs `vdot-p2.ltp.txt` 14 级（起点 `\sumS2`） |
| C4 | **功能未被破坏**：30 例 `--full` `status=通过`、`cases_pass=30/30`、9/9 criteria 达标、`regression_delta=0`、自检串 21/21、G0 反例捕获 1/1；**`L_vdot` 仍为 4 cyc**（`T_steady=1`、`T_kernel=290`、`B1/B2=6/9` 均与 K1 同值）⇒ 2 拍契约与延迟口径未变。 | `20-full-20261107T104227.json`（§4.13.4） |
| C5 | **清单外补强同样通过**：extra 129 例 `status=通过`、129/129、8/8 criteria 达标，其中 **`golden_crosscheck=达标`（`EXTRA_CROSSCHECK verdict=MATCH`）**、自检串 86/86、G0 2/2、负例 41/41、`vdot_rand10k`（10,000 组随机）通过。 | `94-extra-20261107T104230.json`（V12） |
| C6 | **口径**：P-2 是**时序裕量/面积**方向的改动，**不是加速**；`ltp` 只作相对级数、不换 ps、不代表频率；全节**不写「收敛」**（无 STA/liberty）。 | 本节全部数字均为 Yosys 0.48 同脚本同口径实测 |

---

#### 4.13.2 改了什么（before / after 结构）

**before（K1，`83059b5`）**：`sum_wo[8×16b] → sext19 → 4:2 树(pipeLevel=0) → 19 位 CPA(+&) → Cat(96'b0, sext32) → RegEnable(·, fireS1)`。寄存器只有格式化后的 19 位（高 96 位恒零，被综合折叠），全模块最长组合路径 = 树 + CPA = 22 级。

**after（P-2）**：`sum_wo → sext19 → 4:2 树 → RegEnable(out_sum/out_car, fireS1) [38 FF] → 19 位 CPA(+&) → Cat(96'b0, sext32) → io.vd`。CPA 与格式化变成**寄存后组合输出**，在输出级与 `mgu.io.out.vd` 经 `Mux(outIsVdot, …)` 并联选路（该 Mux 在 K1 已存在，未改）。

代码锚点（`VdotReduce.scala`，改后 58 行）：

| 行 | 内容 |
|---|---|
| `:29-33` | IO：`sum_wo: Input(Vec(8, UInt(16.W)))`、`fireS1: Input(Bool())`、`vd: Output(UInt(128.W))` —— **三项与 K1 逐字相同** |
| `:40-43` | 4:2 树（`pipeLevel = 0`，`tree.io.fire := io.fireS1` 保留） |
| `:49-50` | `sumS2 = RegEnable(tree.io.out_sum, io.fireS1)`、`carryS2 = RegEnable(tree.io.out_car, io.fireS1)` —— 新增 38 FF |
| `:52-54` | `cpa = sumS2 +& carryS2`、`s19 = cpa(18,0)` —— CPA 移到此拍 |
| `:57` | `io.vd := Cat(0.U(96.W), s19.asSInt.pad(32).asUInt)` —— 格式化 + 直出（K1 这里还有一层 `RegEnable`） |

**生成的 SystemVerilog 逐行核对**（`build/rtl/VdotReduce.sv`，2026-11-07 10:17:39，`sumS2/carryS2` 命中 7 行）：

```
reg  [18:0] sumS2;
reg  [18:0] carryS2;
wire [18:0] cpa = 19'(sumS2 + carryS2);
      sumS2   <= _tree_io_out_sum;      // fireS1 使能
      carryS2 <= _tree_io_out_car;
assign io_vd = {96'h0, {13{cpa[18]}}, cpa};   // = Cat(96'h0, sext32(s19))，96+13+19 = 128
```

**与「加一级流水」的区别（本节的定义口径）**：寄存器使能仍是从 `VIMac64b` 端口取来的 `io.fireS1`（`design/CODING-STD.md` §3.4 的约定不变），寄存器边界与 K1 同一拍；变的只是**过边界的数据表示**（解析后的和 → 冗余 `(sum, carry)` 对）与**边界后的算术位置**。因此 `VimacCfg` 的 latency=2 与外部看到的拍数不变（§4.13.4 的 `L_vdot=4` 是实测复核，不是推断）。

**未动清单（逐项，均可 grep 复核）**：`VIMac64b.scala` 与 `VimacCfg` 未改——`git -C repos/XiangShan/yunsuan status --porcelain` 只列 ` M …/VdotReduce.scala` 一行；`VIMacU.scala`（含死代码副本 `fu/vector/VIMacU.scala`）未改——`git -C repos/XiangShan status --porcelain -- <两个 VIMacU 路径>` → **0 行**；superproject 侧只多出 ` M yunsuan`（子模块指针/工作树变动，`git -C repos/XiangShan diff --submodule=short` 可复核）；`repos/YunSuan/` 零改动；30 例主清单 `design/verify/cases/manifest.tsv`（sha256 `a90d1071…`）未变。

---

#### 4.13.3 面积与级数（同一 Yosys 0.48 脚本，before / after）

口径与官方面积作业一致：`core-package/scripts/40-yosys-area.sh`（`synth → flatten → stat -json → stat -tech cmos → ltp -noff`），**只综合数据通路模块、无工艺库**；两版用同一脚本、同一节点类型（`kshcnormal`），各自作业独立。

| 版本 | 作业 | cells | 其中组合 | `$_DFFE_PP_` | `$scopeinfo` | 晶体管估算 | ltp |
|---|---|---:|---:|---:|---:|---:|---:|
| **K1（基线，重跑 sanity）** | `127135437` | **481** | 458 | **19** | 4 | 4,900 | **22** |
| **P-2（本次改动）** | `127137643` | **500** | 458 | **38** | 4 | 4,900 | **14** |
| 差值 | — | **+19（+3.95% vs 481）** | 0 | +19 | 0 | 0 | **−8（−36.4%）** |
| 对照：`VIMac64b` | 同两作业 | 42,783 / 42,783 | — | — | — | 293,640 | 100 |

- **基线 sanity 成立**：K1 重跑逐值复现官方作业 `126752216`（`results/yosys/40-area-20261104T094144.json` 的 `481 / 4900 / 22`，`vdot.stat.json` 的 `$_DFFE_PP_=19`）⇒ 本次 500/14 与官方 481/22 是**同一把尺子**上的两个点，可直接相减。
- **与模型预期的对照（诚实差异）**：P-2 预登记的模型预期是 `cells=500`、`max(S2,S3)=15`；**实测 cells 逐值一致（500）**，ltp **比模型少 1 级（14 vs 15）**。模型只作相对增量，绝对值以本节实测为准。
- **占比（分母口径各自标注、不相减混用）**：P-2 的 500 cells 占 `VIMac64b` 全口径 42,783 的 **1.169%**（K1 为 481/42,783 = **1.124%**，差 **+0.044 个百分点**）；组合口径分母 41,945 时，P-2 组合仍为 458，**组合增量 0**。
- **DFF 指纹**：19 → **38**，与 P-2 预登记的 38 FF 预算一致（`38` 是判据值，不是估计）。

---

#### 4.13.4 验证清单（逐项，命令 + 输出）

| # | 检查 | 命令（昆山） | 实测输出 | 判定 |
|---|---|---|---|---|
| V1 | 重新 elaborate + 编译 | `sbatch … 10-build-emu.sh --src-root ~/core/src`（前置 `rm -f build/rtl/SimTop.sv`，原因见 §4.13.5） | JSON `status=通过`；`build_emu: rc=0`；`nm_exec_vdot=命中 2 行` | 达标 |
| V2 | 构建冒烟 | 同上（脚本内置） | `rc=0 HIT_GOOD_TRAP=1 ABORT=0 BAD=0`；镜像 `microbench(fallback)` ⇒ `hello_evidence=no`（**不冒充 1.1 证据**） | 达标（仅构建冒烟） |
| V3 | 30 例 `--full` 用例 | `sbatch … 20-run-difftest.sh --full --manifest ~/core/test/manifest.p2-30.abs.tsv --emu ~/core-p2/emu-p2 --ref-so ~/core-p2/ref-p2.so` | `status=通过`、`cases_pass=30/30`、`cases_all_ran=30/30` | 达标 |
| V4 | 回归基线 | 同上（`--full` 自动比对 `results/difftest/baseline.tsv`） | `regression_delta=0` | 达标 |
| V5 | 防假通过（自检串） | 同上 | `selfcheck_req=21 / selfcheck_ok=21` | 达标 |
| V6 | G0 反例被判负 | 同上 | `g0_req=1 / g0_caught=1`（GOOD TRAP 但 `CASE …: MISMATCH`） | 达标 |
| V7 | 三口径 / T5 ΔL | 同上 | `L_vdot=4`、`T_steady=1`、`T_kernel=290`、`B1=6`、`B2=9`、`L_vadd=3`、`L_vmacc=4`（ΔL_mv=1） | 达标 |
| V8 | 面积 K1 sanity | `sbatch … 40-yosys-area.sh --vdot-rtl ~/core-p2/k1/vdot_dp.sv …` | `VdotReduce 481 / 4900 / 22`、`$_DFFE_PP_=19`（复现官方 `126752216`） | 达标 |
| V9 | 面积 P-2 | `sbatch … 40-yosys-area.sh --vdot-rtl ~/core-p2/rtl/area/vdot_dp.sv …` | `VdotReduce 500 / 4900 / 14`、`$_DFFE_PP_=38` | 达标 |
| V10 | 非 vdot 通路未回归 | V3 的 30 例含 `vadd-microbench`（vadd/vmacc 通路） | 该例 `通过`，且 `L_vadd=3`/`L_vmacc=4` 与 K1 同值 | 达标 |
| V11 | 清单未被改动 | 本地 `sha256sum design/verify/cases/manifest.tsv` | `a90d107118773ebb0de5c1518846680b174b03cf0eb0cdf8be333e582dddbab1`（30 数据行） | 未变 |
| V12 | extra 129（清单外补强） | `sbatch … 94-run-extra.sh --emu ~/core-p2/emu-p2 --ref-so ~/core-p2/ref-p2.so --manifest ~/core/test/manifest.extra.abs.tsv` | 作业 `127137640` `status=通过`：`cases_pass=129/129`、8/8 criteria 达标、**`golden_crosscheck=达标`（`EXTRA_CROSSCHECK verdict=MATCH`）**、自检串 86/86、G0 2/2、负例 41/41、`vdot_rand10k` 通过；墙钟 10:42:30→11:43:54 | 达标 |

> **关于「golden_crosscheck」**：`20-run-difftest.sh` **没有**这个 criterion 名（`grep -n golden_crosscheck core-package/scripts/20-run-difftest.sh` → 0 命中）；30 例里金模型的作用体现在 V5 的 21 条自检串——它们的期望值由 `design/verify/vdot_model.py` 金模型生成、编进镜像。带 `golden_crosscheck` 这个名字的判据在 `94-run-extra.sh`（extra 129 用 `extra_crosscheck.py` 逐条对拍金模型），V12 的结果为 `达标`。

---

#### 4.13.5 诚实边界（必须与数字同页出现）

1. **无 STA / 无 liberty**：`ltp` 是 Yosys 拓扑级数，不是 ps、不是频率。因此本节只能说「最长组合路径从 22 级降到 14 级」，**不能**说「2 拍已收敛」「频率提升」——这属于禁止表述③的范围。
2. **S2 / S3 锥没有分开探**：`M-S2`/`M-S3` 切段探针本次**未建、未跑**；`ltp=14` 是**模块级**最长组合路径（起点 `\sumS2`），不能据此反推「S2 树锥 = 8 级」。
3. **面积只覆盖数据通路**：两版都是 `VdotReduce` 模块闭包、无标准单元库、无布线/时钟树；42,783 是 `VIMac64b` 对照口径，不含 `VIMacU` 其余部分。
4. **延迟不变是实测**：`L_vdot=4` 来自 30 例里的 `perf_vdot`（RAW ×2000 逐次 rdcycle），与 K1 的 4 同值；这支持「2 拍契约未被破坏」，但不等于「时序闭合」。
5. **构建系统陷阱（复现必读）**：`repos/XiangShan/Makefile:54` 的 `SCALA_FILE = $(shell find ./src/main/scala -name '*.scala')` **不覆盖 yunsuan 子模块**，所以只改子模块源码时 `make emu` 会报 `对"emu-mk"无需做任何事` 并**沿用旧 RTL**（本次首个作业 `127135545` 实测踩到，已 `scancel`、无证据价值）。复现本结果必须先 `rm -f build/rtl/SimTop.sv` 强制 re-elaborate，并在构建后 `grep sumS2 build/rtl/VdotReduce.sv` 校验。
6. **共享树并发**：本次与覆盖率作业共用 `~/core/src`（`build/emu` 曾被 `95-coverage.sh` 移走）。为免二进制被并发重建替换，构建成功后立刻把 `build/emu`、NEMU `.so` 快照到 `~/core-p2/`，30 例与 extra 作业都用**快照**跑（`--emu/--ref-so` 显式指定）。
7. **清单等价性**：昆山 30 例用的是 `manifest.p2-30.abs.tsv`——由冻结清单只做 `@IMG_DIR@ → /public/home/<account>/core/test/bin` 替换得到（`<account>` 为集群账号占位，执行时替换为实际账号）；数据行 `(cid, cls)` 投影与 `design/verify/cases/manifest.tsv` **完全一致**（两文件 `awk` 抽取后 sha256 同为 `c98eafcd…`），30 条镜像逐条 `test -f` 通过。
8. **不做竞品比较**：本节不做跨队优劣断言；Gloria/Sun/qixuan 的公开材料只用于「已抽查材料中未见同一切法」的说明（对手公开材料的抽查记录），不进入本节的数字论证。
9. **形式 miter 未跑【未运行】**：本次验证未要求 `50-formal-miter.sh`；且 P-2 把 `io.vd` 从「寄存器输出」改成「寄存器后组合」，miter 的 `-seq` 拍数需按 P-2 预登记的重定时口径重新校准后才能用，直接沿用旧结论不算证据。
10. **共享树的后续影响（后续注意项）**：本次把 `~/core/src/XiangShan` 的 `build/rtl` 与 `build/emu` 更新成了 P-2 版本；覆盖率作业若要在同一棵树上继续跑，需先把 `VdotReduce.scala` 判回/重编到其所需版本，或直接用其自己的 `emu.nocov` 快照（`~/core-p2/` 下的 K1 源码备份 `VdotReduce.k1.bak.scala` 仅供回滚，未回写）。
11. **机时（如实记）**：本项共 7 个作业，远端台账 `~/core/results/budget-log.tsv` 逐行合计 **2.315 node-h**（`127135437` 0.010 / `127135641` 0.604 / `127137599` 0.001 / `127137611` 0.002 / `127137643` 0.176 / `127137638` 0.498 / `127137640` 1.024），在预估的 3–4 h 验证预算内；其中两个失败作业（清单路径问题）合计 0.003 node-h。

---

#### 4.13.6 评分对应

| 官方指标 | 本报告位置 | 本节提供的证据 |
|---|---|---|
| 创新性 → **设计优化独特性（5 分，优秀 4–5）**（`docx/02:95`） | 把内部评委「无实测 PPA」的扣分点补成**可复算的 PPA**：同一把尺子上的 481→500 cells、22→14 级、DFF 19→38，且改动只有一个文件、不碰共享模块 | §4.13.3 |
| 探索性 → **微架构优化分析（5 分）**（`docx/02:93`） | 时序轴：切点选在树的冗余表示上（carry-save retiming），并把「为什么不加流水级」写成可核对的结构事实（同一 `fireS1` 使能、同一拍边界） | §4.13.2 |
| 阶段三 → 报告完整性 | `L_vdot=4` 等口径与 K1 同值 ⇒ 性能结论不受本次改动影响，报告的既有数字无需改写 | §4.13.4 V7 |

> 不承诺档位：本节只提交实测 PPA 与结构说明，不给「几分」的预测；无 STA/功耗数据，按调研口径**不承诺 5 分**。

---

#### 4.13.7 复现（逐条可复制）

```sh
# 0) 前提：昆山 ~/core 已落位（`<account>` 为集群账号占位）；改动文件在 repos/XiangShan/yunsuan（本地 = 远端同 sha256）
scp repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala \
    kunshan:~/core/src/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala
#    从公开仓复现：先按 stage2/2.2-rtl/CHANGES.md 应用 9 个基线 patch，再在 yunsuan 仓应用
#    patches/0005-X-new-P-2-VdotReduce-carry-save-retiming-yunsuan.patch（基于 83059b5；改的就是上面这个文件）

# 1) 强制 re-elaborate（见 §4.13.5 第 5 条）+ 构建
ssh kunshan 'rm -f ~/core/src/XiangShan/build/rtl/SimTop.sv'
ssh kunshan 'cd ~/core && sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 \
    core-package/scripts/10-build-emu.sh --src-root /public/home/<account>/core/src'
ssh kunshan 'grep -c "sumS2\|carryS2" ~/core/src/XiangShan/build/rtl/VdotReduce.sv'   # 期望 7

# 2) 30 例 --full（用冻结清单的绝对路径版；数据行与冻结件等价）
ssh kunshan 'cd ~/core && sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 \
    core-package/scripts/20-run-difftest.sh --full \
    --manifest /public/home/<account>/core/test/manifest.p2-30.abs.tsv \
    --emu /public/home/<account>/core-p2/emu-p2 --ref-so /public/home/<account>/core-p2/ref-p2.so'

# 3) 面积：K1 sanity（用 ~/core-p2/k1/ 下的 K1 闭包）与 P-2（用 build_area_rtl.sh 从当次 build/rtl 生成）
ssh kunshan 'cd ~/core && sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 \
    core-package/scripts/40-yosys-area.sh \
    --vdot-rtl /public/home/<account>/core-p2/k1/vdot_dp.sv --vdot-top VdotReduce \
    --vmac-rtl /public/home/<account>/core-p2/k1/vmac_only.sv --vmac-top VIMac64b'
ssh kunshan 'bash ~/core/design_verify/area/build_area_rtl.sh ~/core/src/XiangShan ~/core-p2/rtl/area'
ssh kunshan 'cd ~/core && sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 \
    core-package/scripts/40-yosys-area.sh \
    --vdot-rtl /public/home/<account>/core-p2/rtl/area/vdot_dp.sv --vdot-top VdotReduce \
    --vmac-rtl /public/home/<account>/core-p2/rtl/area/vmac_only.sv --vmac-top VIMac64b'

# 4) DFF 指纹 / ltp
python3 -c 'import json;d=json.load(open("vdot.stat.json"));m=list(d["modules"].values())[0];print(m["num_cells"],m["num_cells_by_type"]["$_DFFE_PP_"])'
head -3 vdot.ltp.txt
```

**回滚点**：`repos/XiangShan/yunsuan` @ `83059b5`；被改文件改前 blob `4fbaff570e80f45f2613d8e22ee9f64fff0a4122`；回滚命令 `git -C repos/XiangShan/yunsuan checkout -- src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala`。**四个验证面（重建 / 30 例 `--full` / 面积 before-after / extra 129）均达标，未触发回滚。**

## 5. 面积与扩展性佐证（微架构优化）

> **对应官方评分表「探索性（10 分）→ 微架构优化分析」**（`docx/02-赛题与评分细则.md:93`：指标描述「是否完成 Baseline 与 vdot 加速单元的延迟对比分析」，二级权重 5%、5 分）。该行的**延迟对比主体**在 §3.2 / §4.3（`L_vadd=3 / L_vmacc=4 / L_vdot=4`、`L_base_chain=16`、每指令归一 1.33×）；**本节的对应**是同一分析的面积/通路侧佐证（tap 组合增量 458 / 1.09%、VdotReduce 481 / 42,783 = +1.12%、最长拓扑路径 22 vs 100 级、形式 miter 正负控）。⇒ 该评分行的显式对应 = **§3.2 + §4.3（延迟轴）+ §5（面积/通路轴）**。

> 溯源说明：difftest 不产出面积数字，本节四个数（458 / 41,945 / 481 / 42,783）来自 `results/yosys/*.json`，不是 `results/difftest/*.json`；逐项核算过程见 `evidence/area-derivation.txt`。

- tap 组合增量：**458 cells**，相对 VIMac64b 组合口径 41,945 为 **+1.09%**；全口径 **481 / 42,783 = +1.12%**（含 19 个 `$_DFFE_PP_`）。出处：`results/yosys/vdot.stat.json`（`modules.\VdotReduce.num_cells = 481`、`num_cells_by_type.$_DFFE_PP_ = 19`）、`results/yosys/vmac_only.stat.json`（`num_cells = 42,783`）、`results/yosys/40-area-20261101T211702.json`（`metrics[1]`：`cells=481`、`transistors_est=4900`、`longest_path=22`）。**2026-11-04 重跑**：作业 `126752216`（`results/yosys/40-area-20261104T094144.json`，`status=通过`）给出同值——VIMac64b `cells=42783`/`transistors_est=293640`/`longest_path=100`，VdotReduce `cells=481`/`transistors_est=4900`/`longest_path=22`；DFF 指纹 `19` 仍来自 2026-11-01 的 `vdot.stat.json`（新 JSON 的 `metrics[]` 未列 DFF 项）。scope 仅数据通路、无工艺库。
- 数据通路形式等价：作业 `126751660`（2026-11-04 09:35:31→09:38:54，`results/formal/50-miter-20261104T093531.json`，`status=通过`）正向 miter 实得 `SAT proof finished - no model found: SUCCESS!`，负控 mutant 实得 `model found: FAIL!`；scope **仅 `vdot_dp` 数据通路，不覆盖流水/发射/旁路**（`50-miter-20261104T093531.json` 的 `scope` 字段）。
- 复用：乘法阵列 0 行新增，Booth/Wallace/16b CPA 全部复用 `VIMac64b`（结构方案）。
- 扩展：`accW = 2·SEW + ⌊log2 K⌋`（K=8→19 位，紧式），np 轴优先于 K 轴（模型口径验证见 `stage2/2.1-design/ALGORITHM.md`）→ 逐参数量化（SEW/VLEN/LMUL/np）与面积线性度见 **§7**。
- 最长拓扑路径 22 级 vs `VIMac64b` 100 级（`results/yosys/40-area-20261101T211702.json` → `metrics[0]` / `metrics[1]`）；该数字是 Yosys `ltp -noff` 的拓扑级数，**不是 STA 收敛结论**（2 拍时序闭合未测，见 §8）。
- **P-2 重定时（§4.13，2026-11-07 新增实测）**：在同一把尺子上（同一 `40-yosys-area.sh`、同一节点类型、K1 基线 sanity 复现 `481/4900/22`），把 `VdotReduce` 的 `(sum,carry)` 冗余对挪过 `fireS1` 边界后，**cells 481→500（+19，差值恰为 38−19 个 FF）、组合 458→458（0）、DFF 19→38、ltp 22→14 级（−36.4%）**；`VIMac64b` 对照 42,783 / 100 逐值未变，30 例 `--full` 仍 30/30 且 `L_vdot=4`（作业 `127137638`）。**边界**：① 481/22 仍是本节的面积基线——P-2 的源码改动只以 `patches/0005-…` 形式存在、**不在公开仓 9 个基线 patch 内**（`repos/` 被 `.gitignore` 排除）；500/14 是**本地实测值**，复现须先应用该 patch（§4.13.7）；② ltp 14 同样是拓扑级数、**不是 STA**，全节不写「收敛」（§4.13.5 第 1 条）；③ P-2 属**时序裕量/面积**方向，不是加速。

### 5.1 创新性支撑点 ①：零新增 8×8 乘法器（复用 `VIMac64b.sum_wo`）

**一句话**：vdot 的算术增量**只有归约树**；8 个 int8×int8→16 位有符号积仍由既有的 `VIMac64b` 在第二级算出，本设计**没有新增任何乘法器实例**。

- **乘法在哪算（锚点）**：`repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VIMac64b.scala:195` 声明 `val sum_wo = Wire(Vec(8, UInt(16.W)))`，`:196-209` 用 8 个 `Adder_16b` 按 lane 收 `wallaceOutReg` 的进位保存结果，`:217` 把该线导出为端口（端口声明 `:35`）。vdot 侧只读这条线：`repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:129` `vdotReduce.io.sum_wo := vimacs(0).io.sum_wo`。
- **tap 里没有乘法（可复算的否定证据）**：`repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala` 全文非注释代码只有 4 类操作——`pad`（`:30`）、生成器例化（`:33`）、`+&` CPA（`:38`）、`Cat`/`RegEnable`（`:42,44`）；**没有 `*` 运算符**。核对命令与输出：
  ```
  $ grep -vE '^\s*(\*|/\*|//)' repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala | grep -c '\*'
  0
  $ grep -c '^  val .*=.*\*' VdotReduce.scala   # 0（无乘法赋值行）
  0
  ```
- **数字（实测，面积）**：`results/yosys/40-area-20261104T094144.json:19` → `{"top":"VdotReduce","cells":"481","transistors_est":"4900","longest_path":"22"}`；同文件 `:18` 的 `VIMac64b` = `42783 / 293640 / 100`。⇒ 新增归约树 **481 / 42,783 = +1.1243%**（报告写 +1.12%）；组合口径 **458 / 41,945 = +1.0919%**（报告写 +1.09%，分解 481 = 458 组合 + 19 `$_DFFE_PP_` + 4 `$scopeinfo`，`results/yosys/vdot.stat.json` 本机实读 `num_cells=481`、`$_DFFE_PP_=19`、`$scopeinfo=4`）。**没有第二个 8×8 阵列的面积项**：若真的新增一套乘法器，量级应与 `VIMac64b` 的 42,783 cells 同阶，而不是 481。
- **改动面（可核对的"零"）**：`VIMac64b` 的乘法/压缩逻辑**一行未改**；为取数只在端口表加 3 个 Output（`VIMac64b.scala:35-37`）并在 `:217-219` 各赋值一次（X15 一次性导出约定，`design/ARCHITECTURE.md` §5.3）。
- **边界**：481 cells 是 Yosys `abc` 通用门计数、**未含工艺库**（同 JSON `:12` 的 `scope`），不是硅面积；`longest_path=22` 是 `ltp -noff` 拓扑级数、不是 STA 结论。

### 5.2 创新性支撑点 ②：tap 对端到端延迟贡献 0 拍（`fireS1` 契约）

**一句话**：归约 tap 与 `VIMac64b` 的第二级**同拍同使能**寄存，不插流水级、不改 `VimacCfg`，因此端到端依赖延迟与 vmacc 完全相同（实测 ΔL=0）。

- **契约（三处锚点，缺一不可）**：
  1. 使能来源是端口线本身：`VIMac64b.scala:41` `val fireS1 = GatedValidRegNext(fire)`，`:219` `io.fireS1 := fireS1`；
  2. tap 用同一根线寄存：`VdotReduce.scala:16-18`（注释写明「registered on `io.fireS1`, the very same enable that latches `VIMac64b.io.walOut`」）、`:44` `io.vd := RegEnable(result, io.fireS1)`；
  3. wrapper **只连不重建**：`VIMacU.scala:129-130` 两行分别接 `vimacs(0).io.sum_wo` 与 `vimacs(0).io.fireS1`；机械判据 `grep -c 'vimacs(0)\.io\.fireS1' VIMacU.scala` → **1**（且该行是端口连接，不是 `io.in.valid`/`RegNext` 重建；wrapper 内 `RegNext`/`GatedValidRegNext` 字样仅出现在 `:126` 的注释里）。
- **数字（实测，延迟）**：`results/difftest/20-full-20261103T142246.json` → `metrics[]` 的 `L_vadd=3` / `L_vmacc=4` / `L_vdot=4`，`criteria[t5_delta_latency]` 的 `actual="L_vadd=3 L_vmacc=4 L_vdot=4 (ΔL_mv=1)"`、`status=达标`（同值见 `20-full-20261103T075552.json`）。即 **ΔL(vdot−vmacc)=0 拍**——tap 没有给依赖链加拍；`+1` 那拍属于 vmacc 相对 vadd 的乘累加路径。
- **结构佐证**：`VimacCfg` 的 `latency = CertainLatency(2)`（`repos/XiangShan/src/main/scala/xiangshan/backend/fu/FuConfig.scala:563`）**未被修改**（本设计禁止改共用 `VimacCfg`）；tap 的 `RegEnable` 与 `walOut` 的 `RegEnable`（`VIMac64b.scala:216`）同一 `fireS1`，因此 tap 占用的是**既有第 2 拍**的寄存器边界，不是新拍。
- **边界**：本节的"0 拍"是**端到端依赖延迟不增**的实测结论（`L_vdot==L_vmacc`），**不是**「tap 组合逻辑延迟为 0」；tap 自身的组合锥级数见 §5（22 级，拓扑口径）。

### 5.3 创新性支撑点 ③：Mgu 旁路硬清零（高 96 位恒零断言 + 5 例边界）

**一句话**：vdot 的 `vd[127:32]` 由数据通路 `Cat(96'b0, ·)` 直接给 0，并在 wrapper 用**输出级 ctrl** 旁路 Mgu；同时用一条**每拍常开**的断言把"高 96 位恒零"变成可被仿真直接判红的不变量。

- **清零在哪（锚点）**：`VdotReduce.scala:42` `private val result = Cat(0.U(96.W), s19.asSInt.pad(32).asUInt)`——96 位常量 0 与 `sext32` 拼接，与 vta/vma/tail 无关；`:41` 注释即该口径。
- **旁路（锚点）**：`VIMacU.scala:159` `private val outIsVdot = outCtrl.fuOpType === VimacType.vdot`（取**输出级** ctrl，避免背靠背混合流串指令）、`:160` `io.out.bits.res.data := Mux(outIsVdot, vdotReduce.io.vd, mgu.io.out.vd)`。**为什么必须旁路**：Mgu 的 tail/agnostic 按 byte 逐位算（`repos/XiangShan/src/main/scala/xiangshan/backend/fu/vector/Mgu.scala:89-92` 的 `MuxCase(oldVdVecByte(i), activeEn→vd, agnosticEn→byte1s)`），给不出"固定的 0"。
- **断言（锚点）**：`VIMacU.scala:165-166`
  ```scala
  assert(!io.out.valid || !outIsVdot || (PopCount(io.out.bits.res.data(VLEN - 1, 32)) === 0.U),
    "VIMacU: vdot.vv must write zeros to vd[127:32]")
  ```
  即 **valid ∧ vdot ⇒ popcount(vd[127:32]) == 0**，任何一位为 1 立即断言失败（不是"事后比对"，是同一拍的不变量）。
- **数字（实测，5 例边界）**：`stage2/2.3.3-bound/cases/vdot_bound{1..5}.20261103T142246.key.txt:5` 五份逐行实读，每份的 `hi=[0x00000000 0x00000000 0x00000000]`（即 3 个 32 位字、共 **15 个高半区字全零**）且 `MATCH`：

  | 用例 | 输入形态 | `result` 实读 | `expect` | 高 96 位 |
  |---|---|---|---|---|
  | `vdot_bound1` | 全 −128（上边界，S=131072=`0x20000`） | `0x00020000` | `0x00020000` | `hi=[0 0 0]` |
  | `vdot_bound2` | 最小负和 S=−130048 | `0xFFFE0400` | `0xFFFE0400` | `hi=[0 0 0]` |
  | `vdot_bound3` | 一侧全零 | `0x00000000` | `0x00000000` | `hi=[0 0 0]` |
  | `vdot_bound4` | 全 +127（S=129032=`0x1F808`） | `0x0001F808` | `0x0001F808` | `hi=[0 0 0]` |
  | `vdot_bound5` | 交错极值 | `0x00000001` | `0x00000001` | `hi=[0 0 0]` |

  用例侧的判据是显式的三条与：`int ok = ((uint32_t)res == expect) && (w1==0) && (w2==0) && (w3==0);`（`design/verify/cases/vdot_bound1.c` 主函数末段；五个 bound 用例同构），因此"高 96 位为 0"是**用例自己判的**，不是只看 PASS 串。
- **边界**：断言只覆盖 `io.out.valid` 的那一拍；它证明"写回值为 0"，**不覆盖** Mgu 内部行为是否被正确旁路（旁路正确性靠上表 5 例 + `vdot_mix` 背靠背串数据用例）。

### 5.4 创新性支撑点 ④：编码检查全库扫描（funct6=0x0E 无占用 + 阳性对照）

**一句话**：`vdot.vv` 的编码 `funct6=001110(0x0E)/funct3=010/opcode=0x57/vm=1` 在 riscv-opcodes 全库（ratified + unratified）该编号位**无占用**，且检查带有"历史撞车必须被检出"的阳性对照。

- **全库扫描（本次实跑，可复算）**：快照 `$OPCODES_SNAPSHOT`（口径 `source=github.com/riscv/riscv-opcodes`、`commit=f24ac23ec9fa947011781a09cd6fd25a7c36dc45`、`fetched=2026-11-01`；本地检出方法：`git clone https://github.com/riscv/riscv-opcodes "$OPCODES_SNAPSHOT" && git -C "$OPCODES_SNAPSHOT" checkout f24ac23ec9fa947011781a09cd6fd25a7c36dc45`）。对 `extensions/**` 下全部文件按「`6..0=0x57` 且 `14..12=0x2`」筛出 OPMVV 行，再按 `31..26` 聚合（脚本可逐字复跑）：
  ```
  $ cd "$OPCODES_SNAPSHOT" && python3 -I - <<'EOF'
  import glob,re,collections,os
  files=[p for p in glob.glob('extensions/**',recursive=True) if os.path.isfile(p)]
  rows=[]
  for f in files:
      for line in open(f,errors='ignore'):
          line=line.split('#')[0].strip()
          if not line or '=' not in line: continue
          m=re.match(r'^(\S+)\s+(.*)$',line)
          if not m: continue
          name,fields=m.group(1),m.group(2)
          d=dict(re.findall(r'(\d+\.\.\d+)=0x([0-9A-Fa-f]+)',fields))
          if d.get('6..0','').lower()!='57': continue
          if d.get('14..12','').lower()!='2': continue
          if d.get('31..26') is None: continue
          rows.append((int(d['31..26'],16),name,f))
  occ=collections.defaultdict(list)
  for v,n,f in rows: occ[v].append(n)
  print("files:",len(files),"OPMVV rows:",len(rows))
  for v in sorted(occ): print("  0x%02X -> %s"%(v,",".join(occ[v])))
  print("0x0E ->",occ.get(0x0E,'FREE'))
  EOF
  files: 141 OPMVV rows: 82
    0x00 -> vredsum.vs
    ...（共 59 个已占 funct6 值，此处节选 7 行；完整列表见下方命令的实跑输出）
    0x0C -> vclmul.vv
    0x0D -> vclmulh.vv
    0x0F -> vpairo.vv
    0x28 -> vdot4au.vv
    0x2A -> vdot4asu.vv
    0x2C -> vdot4a.vv
    0x3E -> vzip.vv
  0x0E -> FREE
  ```
  即 **0x0E 在 59 个已占 funct6 值、82 条 OPMVV 行中都不出现**（FREE），而同编号位的 0x0C/0x0D（Zvbc）、0x28/0x2A/0x2C（Zvdot4a）、0x3E（Zvzip）都有主。带文件位置复核两例：`$OPCODES_SNAPSHOT/extensions/rv_zvbc:4-5`（funct6=0x0C 的两行：`vclmul.vv` 与 `vclmul.vx`）、`.../extensions/unratified/rv_zvzip:3`（0x3E `vzip.vv`）。
- **阳性对照（检查自检，必须命中才算有效）**：`python3 -I design/verify/encoding-gate.py --snapshot "$OPCODES_SNAPSHOT"` 实跑输出节选（本次）：
  ```
  [P1] 阳性对照 · 旧码 001100/010/vm=1 (0x3220A1D7) vs encoding.h MATCH_VCLMUL_VV ... -> 命中（正确）
  [P2] 阳性对照 · 111111/010 在 rocket-chip Instructions.scala 中被占用（VWMACCSU_VV, :819）-> 命中（正确）
  [P3] 阳性对照 · NEMU vopmvv 表含 funct6=101101（vmacc）-> 命中（正确）
  [P4] 反向对照 · funct3=110 的 vclmul.vx 不得与 010 位置判重叠 -> 正确排除
  [U] 阳性对照: 0x0C->['vclmul.vv'] 0x2C->['vdot4a.vv'] ; 0x0E(本编码)->FREE ; 判定=管线有效
  [U] riscv-opcodes 本地快照 ...: 文件 141 / 指令行 1521（32 位 1459）-> 与冻结三元组重叠 0 条
  ```
  ⇒ **上游维度 0 重叠、阳性对照 3/3 命中 + 反向对照 1/1 正确排除、管线有效**（P1–P3 为阳性对照、P4 为反向对照，四条不能合并计作「阳性 4/4」）。
- **必须同时写出的退出码**：该次实跑 **`EXIT=1`**，脚本末行为 `!!! 检出冲突/漂移 3 条`，三条分别是 `[SCALA-BITPAT] rocket-chip/Instructions.scala`、`[NEMU-DECODE-H] vopmvv vdot`、`[VECDECODER] opmvv VDOT_VV`——**都是本仓自己已落地的 vdot 表项**（检查把"仓库内已存在的 vdot 表项"也算作与冻结三元组重叠）。因此本报告**不宣称「编码检查通过」**：可主张的是**上游全库（141 文件 / 1521 指令行）在本编号位 0 占用 + 阳性对照命中**；不可主张的是「`encoding-gate.py` 退出码 0」。同口径见 `stage2/2.1-design/README.md` §3（两次均 `EXIT=1`）。
- **来源文档**：2026-10-31 的编码核对记录（2026-10-31 联网复核：0x0C 被 Zvbc `vclmul.vv` 占用 ⇒ 改线 0x0E；新机器码 `vdot.vv v3,v2,v1 = 0x3A20A1D7`）；该文档同时声明旧记录的"0 命中"结论**已被推翻**。
- **边界**：编码是否被上游"未来分配"占用只能按快照 commit 说事；快照过期后须重跑同脚本。

### 5.5 探索性支撑点 ⑤：4 cyc 依赖延迟的机制解释（2026-11-06 双链实验后改写；2026-11-07 按三轴版复核）

> **状态标签（先读）**：`sections/dualchain.md` 已定稿，正文见 §4.8（**作业 `127142843`**，`status=通过`、**12/12 criteria 达标**；2026-11-07 13:11 三轴版替换，取代 00:42 版；上一次 `127043684` 作复现记录）。**机制归因已由 A/B 实验确认（强）**：`vdot` 不读旧 vd（`vdRen=F`）⇒ 源操作数无依赖时（M8/M3）`0.890/1.011` 与 `1.125/0.968 cyc/条`（q4/q8）背靠背发射；测量形状相同但要读旧 vd 的 `vmacc`（M5）`4.875/7.531 cyc/条`（q4/q8）——**同窗口径约 5.5 倍（q4）/ 约 7.5 倍（q8）的每指令吞吐差（M5/M8），不是加速比**（§4.8.1 口径 A 行；两臂指令不同，不写「唯一变量」，该倍数不与依赖链口径或 T5-L 相除）。**但「依赖间隔恰为 4 cyc」这一数值本身未被独立复现**：差分口径（口径 B）给 `vdot.vv v10,v10,v1` 串行链 5.7–7.5 cyc/步，且该差分模型在依赖链上自相矛盾（`q8>q4` ⇒ 反解每 rep 固定开销为负），只能记「另一口径未复现 4」，**不能记「4 被证伪」**（§4.8.1 口径 B/C 行、§4.8.4）。仓内 `perf_vdot.bin` 的括窗口径仍给 4，且与全环口径 6.98 相差恒定的 ≈2.97 拍环路开销（vadd/vmacc/vdot 三链互证，§4.8.4(c)）。**同口径对照（§4.8.5，同一作业）**：按 Gloria/GEMwhu 的依赖链口径（N=0/64/256/1024 四点 OLS、含循环开销）复现，本项 vdot 依赖链 **6.984 cyc/点积** vs 对方文档 **7.008065**（差 −0.024，−0.3%），RVV 基线 **20.994** vs **20.991935**（差 +0.002）⇒ **同口径下同一量级，本项不主张任何优势**；对方的 7.008/20.992 是【对方文档】、本仓未复跑其镜像。

**已确认的机制（不是假说）**：vdot 的 `vd` 在译码期被标成"不读旧 vd"（`vdRen=F` ⇒ `src3=X`），数据通路的旧 vd 项也恒为 0；因此**不存在"写回值 → 下一写回"的 old-vd 写回环依赖**。双链实验的 M3/M8（`vdot` 源常量、vd 固定或轮转）与 M5（`vmacc` 源常量、但要读旧 vd）**测量形状相同、但指令与通路不同（不称「唯一变量」）**：每指令吞吐 `0.890–1.125` vs `4.875/7.531` cyc/条（q4/q8，同窗约 5.5/7.5 倍，M5/M8）⇒ 与「旧 vd 读入是串行化来源」的 RTL 机制（`vd_old=INT.X`、`isMacc` 不含 vdot、旧 vd 不进归约）**方向一致**；因果强度只到「一致」，机制成立性以 §4.8.3 的 file:line 为准（§4.8.6 第 3 条）。

**代码锚点（只证明"不读旧 vd"这件事成立，不证明 4 cyc 的拍分解）**：

1. `repos/XiangShan/src/main/scala/xiangshan/backend/decode/VecDecoder.scala:91`：`private def src3: BitPat = if (vdRen) SrcType.vp else SrcType.X`；
2. 同文件 `:385`：`VDOT_VV -> OPMVV(F, FuType.vimac, VimacType.vdot, F, T, F, UopSplitType.VEC_VVV)`——第一个参数 `vdRen=F`，于是 `src3=X`（不读旧 vd）；
3. `repos/XiangShan/yunsuan/src/main/scala/yunsuan/package.scala:400`：`def vdot = LiteralCat(0.U(2.W), INT.S, INT.S, INT.X, FMT.VVV, VimacOpcode.vdot)`——`vd_old` 位取 `INT.X`（=0，与 `vmul`/`vsmul` 同款，见 `:384,399`）；
4. `repos/XiangShan/src/main/scala/xiangshan/backend/decode/DecodeUnit.scala:1069`：`isDependOldVd := isVppu || isVecOPF || isVStore || ... || isVma || isFof || vstartIsNotZero`——列表**不含 vimac 类**，故 vdot 只有在 `vstart≠0` 时才置真，而 `vstart≠0` 已由译码判非法（`VecExceptionGen.scala:280,299`，`:280` 为 `vstartIllegal` 实测锚点、2026-11-07 复核，旧记 `:277` 已更正）。

**"不读旧 vd"在数据通路上也有冗余闭环**：`VIMac64b.scala:125` `partProd(33) := Mux(io.isMacc, ..., 0.U)`，而 `VimacOpcode.isMacc` 的集合不含 `vdot`（`repos/XiangShan/yunsuan/src/main/scala/yunsuan/encoding/Opcode/VimacOpcode.scala:18`），故 vdot 的"旧 vd 项"恒为 0；wrapper 侧 `oldVd` 仍被接进 split 与 `mod.io.oldVd`（`VIMacU.scala:83,98,116`），**仅因 `isMacc=false` 而无害**——这条是"接线残留但语义不依赖"，不是"环依赖被优化掉"的证据。

**仍未测（不得写成已证事实）**：① 4 cyc 里"发射占用/写回/旁路"各占几拍；② 若把 `vdRen` 改成 T 会不会变慢；③ 与 `L_vmacc=4` 的相等是"共享同一路径"还是"两条不同路径碰巧同值"（§4.8.6 第 4 条）。这三问都需要同核对拍实验；本次双链实验**没有回答**它们。

**引用 4 时必须带镜像限定**：4 来自 `perf_vdot.bin` 的逐条括窗口径；同一写法在同一 emu 上重测七条链（含无依赖的 M3/M7/M8）全部 median=2 ⇒ 该口径对二进制布局/调度敏感，**不是跨实现稳定的常量**（§4.8.4(d)）。**不得**把 4 与竞品声明的 7 cyc 相减做"优势"论证（§4.8.6 第 2 条）。

### 5.6 探索性支撑点 ⑥：软硬协同机制（NEMU 金模型 ↔ RTL difftest）

> **对应官方评分表「探索性（10 分）→ 软硬件协同理解」**（`docx/02-赛题与评分细则.md:94`：指标描述「是否理解 NEMU 与 RTL 的协同仿真机制」，二级权重 5%、5 分）。本节给的是**机制链条**（参照模型怎么算、怎么逐拍比、怎么防"假通过"），不是再报一遍性能数字。

**链条四环（每环给锚点）**：

1. **参照模型侧：NEMU 里有一个与 RTL 同语义的 `vdot` 实现**。`repos/NEMU/src/isa/riscv64/instr/rvv/decode.h:371-373` 把 `001110 1 ????? ????? ??? ????? ????? ??` 直接绑到 `vdot`（`vm` 位**固定为 1**，掩码编码匹配不到 ⇒ 非法，与 RTL BitPat、金模型三方同口径）；`repos/NEMU/src/isa/riscv64/instr/rvv/vcompute.h:877-901` 的 `def_EHelper(vdot)`：`require_vector(true)` 先判 VS/vill（`:878`），再独立判 `vm/sew/lmul`（`:879-881`），`check_vstart_exception`（`:883`），循环取 8 个 lane 的 `int8` 做有符号累加（`:885-891`），写回时**手写显式清零高 96 位**（`:894-897` 的 `for (w=0..3) set_vreg(..., (w==0)?result:0, ...)`），**不用 `set_vreg_tail`**（它写 `0xFF`，见 `design/ALGORITHM.md` §3.3）。
2. **金模型侧：三变异自检证明"金模型自己会红"**。`design/verify/vdot_model_test.py:511-565` 的 `mutation_self_check()` 注入三个变异体——M1 写回并回 `old_vd` 高位、M2 高 96 位写 1、M3 删掉 `vill` 判定——**任一未被判红就记失败**（`:562-565`），即"金模型通过"这件事本身是有自检的。同文件 `:581-603` 还有一层**反假通过自检**：把正确结果分别翻转 bit0、翻转 19 位边界 bit、置 `vd[32]`、用 `0xFF` 填 `vd[127:32]`，四种腐化**都必须被 `result_problem()` 拒绝**。
3. **比对侧：difftest 是"逐步（每提交步）比对全状态"，不是只比 PC**。`repos/XiangShan/difftest/src/test/csrc/emu/emu.cpp:517-540` 每个仿真步取 `get_difftest_step()` 后调 `difftest_nstep(step, enable_diff)`；`repos/XiangShan/difftest/src/test/csrc/difftest/difftest.cpp:114-135` 在内层 `for (i=0;i<step;i++)` 里**逐步**调 `difftest_step()`，`:149-165` 该函数对每个核调 `difftest[i]->step()`，`STATE_DIFF` 时 `display()` 并返回 `STATE_ABORT`；最终比对在 `difftest.cpp:695` `if (proxy->compare(dut) || pc_mismatch)`。`repos/XiangShan/difftest/src/test/csrc/difftest/refproxy.cpp:185-230` 的 `RefProxy::compare` 用 `memcmp` 逐字段比，**`vrf`（向量寄存器堆）在 `CONFIG_DIFFTEST_ARCHVECREGSTATE` 打开时参与比较**（`:192-194`）——这是"向量寄存器真的比了"而不是"只比标量"的关键开关；缺它就会"假通过"。
4. **判据侧：`reg_size_match` 把"参照模型与 DUT 是否配套"变成一条可判定的 criterion**。`core-package/scripts/20-run-difftest.sh:459-465` 的注释写明 `1400 B` 是 DUT/NEMU 配套的 state 大小口径（来源 `design/ALGORITHM.md:175`），判据实现是"日志不含 `is configured with different states than DUT`"；`results/difftest/20-full-20261103T142246.json:19` 实读 `{"name":"reg_size_match","expected":"日志不含 'is configured with different states than DUT'","actual":"0 次（1400 B 口径）","status":"达标"}`。

**数字（实测，30 例整份）**：`results/difftest/20-full-20261103T142246.json`（作业 `126676734`）→ `status=通过`；`cases_pass=达标（30/30）`（`:18`）、`reg_size_match=达标`（`:19`）、`no_empty_green=达标`（`:20`，`actual="自检串 21/21 命中；G0 捕获 1/1（GOOD TRAP 但自检 MISMATCH）"`）、`t5_delta_latency=达标`（`:22`）、`vec_reg_compare=达标`、`nm_exec_vdot=达标（命中 2 行）`，共 **9/9 criteria 达标**；同一份 `cases[].abort` 全 `"0"`（0 次 ABORT）。

**这条链为什么算"理解机制"而不是"跑了一遍"**：① 参照模型不是"调现成宏"——`ARITH(...)` 宏按 `vl` 逐 lane 散布，语义不对，所以 vdot 是**手写**的（`vcompute.h:877-901`，与 `design/ALGORITHM.md` §3.3 的"不能复用 `ARITH`"同口径）；② 三端（NEMU / RTL / 金模型）对**同一条非法条件**（`vm=0`、SEW≠8、LMUL≠1、vstart≠0、vill、VS=OFF）给出**同一判定**，且 NEMU 侧把 `vm` 位写进 BitPat 而不是运行时判——这样"掩码编码"根本匹配不到，与 RTL BitPat 的非法路径一致；③ 比对粒度是**每提交步**而非每用例，所以背靠背 `vdot → vmacc → vdot`（R13 串数据风险）能被逐拍抓到；④ `reg_size_match` + `vec_reg_compare` + `no_empty_green`（含 G0 反例）三条合起来，堵的是"参照模型不配套/向量寄存器没比/用例自己不自检"这三种"假绿"。

**边界**：① 这是 **QEMU 级 difftest**（NEMU 参考 .so vs Verilator `build/emu`），**不是硅片实测**，平台为昆山 `kshcnormal`（`stage3/3.1.2-difftest/README.md` §4 第 5 条）；② `design/verify/vdot_model_test.py` 的 `ALL TESTS PASSED (N cases)` 属三条强制检查之一，**按本报告约定本次不跑**（由脚本最后统一执行）⇒ 本节引用其用例结构（`:511-565`、`:581-603`）为**代码锚点**，"1142 cases 全过"是此前一批次记录（2026-11-01 的记录），本次**未运行**、不记为本次证据；③ `reg_size_match` 的 `1400 B` 是 DUT/NEMU 配套口径，**不是**"vdot 的状态宽度"。

**配套材料（2026-11-08 挂接，两件只读引用；§10 索引）**：

- `stage3/3.3/sections/co-sim.md`（本地 20,255 B，`sha256 e52e55f8…`）：① §A 把链条画成**五层机制图**（语义源 `SPEC.md` → 金模型 `vdot_model.py` → NEMU EHelper → RTL `VecDecoder`/`VecExceptionGen`/`VdotReduce` → difftest 比对环）；② §C 给 **18 项 DIFFTEST 参数表**（逐项含锚点，如 `CONFIG_DIFFTEST_ARCHVECREGSTATE` 控制 `vrf` 比对、`1400 B` state 口径、4 个 perf 例走 `--no-diff`）；③ §D 给 **11 条 criteria** 逐条说明堵哪种「假绿」。其「本次状态」三列取自主清单 `142246`（`126676734`）、P-2 主清单 `104227`（`127137638`）与扩容 `127031933`（**129 例快照**）——**扩容那一列本轮未回写**，224 例（`127194011`）见 §4.11.3/§4.12.4。
- `stage3/3.3/sections/tri-consistency.md`（本地 22,682 B，`sha256 9286577d…`）：① §B 逐行给 13 条数值正例的 `result`/`hi` 原值，以及 4 条随机/不变量/反例（`vdot_rand` 1024 组、`vdot_matrix` 六项、`vdot_mix`、G0）；② §C 给六条非法条件 + 组合 + 「非法优先于 `vl=0`」的负例覆盖；③ §D 给边界与语义不变量；④ §A 明写金模型↔NEMU **没有单独直连比对器**，靠「金模型≡RTL」与「RTL≡NEMU」两条边**传递闭合**。该文件同样按 **129 例**记扩容（`negatives_illegal=41/41`），本轮 224 例的 `negatives_illegal=57/57`（`127194011`）未回写该文件。

> 两件的共同边界（与本节口径一致）：**不新增性能数字、不新增作业**；负例只判「两侧一致陷入」，不主张异常字段逐字段相等（`tri-consistency.md` §F.1）；两件均声明「报告侧只读引用，不改本文」，故本轮只挂引用、未改其正文。两件的 `sha256` 与字节数为本轮 `sha256sum` / `wc -c` 实读。

**评分对应表（§5 定稿，含 B 段七件小节）**：

| 官方评分行（`docx/02`） | 本报告位置 | 状态（2026-11-07） |
|---|---|---|
| 探索性→微架构优化分析（`:93`，5 分） | §3.2 + §4.3（延迟轴）+ §5（面积/通路轴）+ §5.1/§5.2（复用与 0 拍）+ **§4.10.1–4.10.3（`methodology.md` 已并入：口径防御 / 时序边界 / 功耗边界）** + **§4.9（`perf-slope.md` 已并入：三点斜率 + R² + 两点拟合交叉）** + **§4.13（`innovation-p2.md` 已并入：P-2 跨拍 CPA 重定时，面积/级数 before-after 实测）** | 主体已实测；`methodology` / `perf-slope` / `innovation-p2` **已定稿**（`perf-slope` 给的是每点开销斜率，§4.13 给的是时序裕量方向的 PPA，两者都不是延迟/加速比） |
| 探索性→软硬件协同理解（`:94`，5 分） | **§5.6**（NEMU EHelper / 金模型三变异 / 逐提交步比对 / `reg_size_match`）+ **配套件 `sections/co-sim.md`（五层机制图 + 18 项参数表 + 11 条判据）与 `sections/tri-consistency.md`（三端一致性对照）** + §3.1.1 交付物 + §3.1.2 交付物 | 已落成（两件配套材料已挂接，只读引用） |
| 创新性→设计优化独特性（`:95`，5 分） | **§5.1**（零新增乘法器）+ **§5.2**（0 拍契约）+ **§5.3**（旁路硬清零+断言）+ **§5.4**（编码全库扫描）+ §5.5（机制归因已确认、4 cyc 数值未独立复现）+ **§4.8（`dualchain.md` 2026-11-07 三轴版：吞吐/依赖间隔/T5-L 三口径分列 + old_vd 机制 A/B + M9/M10/M11 同口径对照）** + **§4.13.2/§4.13.3（carry-save retiming：切点在树的冗余表示、不碰共享模块；481→500 cells / 22→14 级可复算）** | 已落成；机制归因**已确认（强）**，4 cyc 数值未独立复现（§5.5）；P-2 的 500/14 是**本地实测**（复现须应用 `patches/0005-…`，不在公开仓基线 patch 内） |
| 创新性→扩展应用潜力（`:96`，5 分） | §7（7.1–7.4） | 已落成（扩展值全标【推算】） |
| 阶段三交付物完成度（`:90`，25 分） | §3/§4（延迟与基线）+ §6（复现性）+ **§4.10.1–4.10.3（methodology 已并入）** + §4.12（case-expand 已并入，**224 例**扩容清单，**224/224** 通过，作业 `127194011`；历史 129/129 ×2）+ **§4.7（`llmbench.md` 已并入：Q8_0 attention 三轴）** + **§4.13.4（P-2 改动后的 30 例 `--full`：30/30、`regression_delta=0`、`L_vdot=4` 不变）** | 主体现已实测；`llmbench` **已定稿**（两次独立作业逐值相同）；P-2 改动后功能与延迟口径**实测未变**（§4.13.4 V3–V7）；**同轮 30 例整份未跑通（无产物）**，不并入 224 的通过数 |
| 可行性→技术路径合理性（`:91`，10 分；2026-11-07 补行） | §5.1（复用 `VIMac64b.sum_wo`、乘法阵列 0 行新增）+ §5.2（`fireS1` 同拍契约、不改共用 `VimacCfg`）+ §5.4（`funct6=0x0E` 全库 0 占用）+ §7（SEW/VLEN/LMUL/np 扩展路线与逐条阻断点）+ **§4.13.2（P-2 证明「改时序不动契约」：同一 `fireS1`、同一拍边界、`VimacCfg` 未改）** + 设计文档 `design/SPEC.md`/`ARCHITECTURE.md`/`ALGORITHM.md` 与 RTL difftest 30/30 | 已落成（RTL/形式 miter/面积均实测；可落地性见 §5.1/§7；不写「已得分」） |
| 可行性→功能验证有效性（`:92`，10 分） | §3.1.2 交付物（30/30、0 ABORT）+ **§4.11（coverage 2026-11-07 实跑版：29 coverpoints × 30 例，`covered 11/thin 15/partial 2/gap 1`；结构覆盖【未运行（实跑受阻）】，无覆盖率数字）** + **§4.12（case-expand 已并入：`manifest.extra.tsv` 224 例，昆山实跑 224/224 通过，作业 `127194011`；历史 129/129 两批：`127031933`、`127137640`）** + 配套件 `sections/tri-consistency.md` | 30/30 已实测（历史）；extra **224/224** 已实测（历史两批 129/129）；**同轮 30 例整份未跑通（无产物）**；结构覆盖**只有实跑受阻记录、没有数字**，不得写成「覆盖率达标」；三件**已并入** |

> 表中七节均已定稿，不再保留空缺小节。本报告仍不写"某某分已拿到"，也不写"优于同题/全场唯一"（对手数字一律【对方文档】，见 §9）。**§4.13（P-2）与其它六件的性质差别**：它是改 RTL 后的新增实测，故 §5 的 481 / 22 面积基线**不变**，500 / 14 只作 §4.13 的本地实测值单列（复现须应用 `patches/0005-…`，不在公开仓 9 个基线 patch 内）。

## 6. 复现性

- 当前口径全部数字来自 `results/difftest/20-full-20261103T142246.json` 的 `metrics[]`（30 例整份）；同值复核来自 `results/difftest/20-full-20261103T075552.json` 的 `metrics[0..10]`；旧口径来自 `results/difftest/20-full-20261102T000517.json` 的 `metrics[0..4]`。脚本读取复现：
  `python3 -c "import json;d=json.load(open('results/difftest/20-full-20261103T142246.json'));print([(m['name'],m['value'],m['case_id']) for m in d['metrics']])"`
- 源码：`design/verify/cases/perf_vadd.c`、`design/verify/cases/perf_vmacc.c`、`design/verify/perf/perf_vdot.c`、`design/verify/perf/perf_base.c`（编译入口 `design/verify/perf/build.sh`，总入口 `design/verify/cases/build_all.sh`）。
- 作业 provenance（sacct 状态 / 远端镜像 md5 / 失败作业原始产物）：`results/difftest/b3/provenance/91-b3-provenance.txt`（修订时的 ssh 实跑逐条命令与输出）。
- 用例日志：`results/difftest/cases/perf_{vadd,vmacc,vdot}.20261103T075552.log`（本目录 `evidence/` 有同份副本，另有三条链在 `142246` 的判据行摘录 `evidence/perf_*.20261103T142246.key.txt`）；旧口径 `evidence/perf_vdot.20261102T000517.log`（从昆山 scp 取回，md5 与远端一致 `eca6f6c9aab9fbe7fea2c13473ff7be4`）。
- 作业：`126676734`（**主数据源**，30 例整份，`status=通过`、30/30、9/9 criteria 达标）、`126646321`（同值复核，4/4、9/9 criteria 达标）、`126631414`（同值复核，`status=未运行` 仅因清单缺 g0）、`126542079`（旧口径，20/20）；**2026-11-04 新增**：`126762127`（基线链 **本用例 full 尺度** 8×2000 + ladder + B3，`verdict=ALL_OK`、`scale=full`，`results/difftest/b3/91-b3-20261104T115624.log`）、`126750763`（基线链 `L_base_chain=16`，min 尺度，`status` 由日志 `verdict=ALL_OK` 判定）、`126751660`（形式 miter，`status=通过`）、`126752216`（面积重跑，`status=通过`）、`126758062`（full 尺度首提，共享节点上 1:02:30 只走完 round 0/1 后取消；同节点 VASP 占核为操作者口述、未留日志，仅作排障记录）。

## 7. 扩展潜力（更高 SEW/VLEN、LMUL>1、np 多结果）

> 对应官方评分表「创新性 / 扩展应用潜力」（`docx/02-赛题与评分细则.md:96`：指标描述「方案是否具备向其他向量指令或更高 SEW/VLEN 扩展的能力」，二级权重 5%、5 分，优秀档 4–5）。
> **本节标签约定（先读，防误读）**：凡带【实测】的，是本次已在库的昆山/本机产物；凡带【推算】的，是按 §5 实测基数做的**线性外推**，**没有对应 RTL、没有综合、没有 difftest**；凡带【定理】的，是已证的位宽结论（定理 L4；证明脚本 `out/validate/run.log`）。**本节不含任何加速比**——延迟对比只有 §4.3 的每指令归一 `1.33×` 与 T5 ΔL 三链（`L_vadd=3 / L_vmacc=4 / L_vdot=4`，ΔL(vdot−vmacc)=0）。**本节确有倍数，但全部是面积比值**（`cells ÷ cells`，同一量纲）：§7.3 的 `1.36 倍`/`2.39 倍`（655/481、1,149/481）、§7.4 表的「相对 481 倍数」列（0.35–11.45 倍）、§7.4 结论 1 的 `2.39/2.22/2.15 倍` 与结论 2 的 `1.84 倍`、§7.2 口径 (b) 段的 `1.56/1.92/1.96 倍`（生成器退化 3:2 相对理想 4:2）。这些**都不是加速比**，也不与任何延迟/吞吐数字相除。

### 7.1 位宽参数化：19 位不是常数，是 SEW 与 K 的函数

归约树的数据位宽由**最坏积和**决定，与树形无关（位宽定理 L4，39 格 tight，`out/validate/run.log`）：

```
W_min(SEW, K) = 2·SEW + ⌊log2 K⌋          # 紧式；K=8, SEW=8 → 16+3 = 19
```

三项来源可逐项对上：① 单积幅度 ≤ 2^(2·SEW)（SEW=8 时最大单 lane 积 = `16384 = 2^14`，`out/validate/run.log:21` 的 `[A14]` 行实读 `max lane product 16384`）；② K 个同号最坏积相加 ⇒ 再乘 K，即 `+⌊log2 K⌋`（K=8 时 `8×2^14 = 2^17 = 131072`，19 位位宽推导）；③ 取 ⌊⌋ 而非 ⌈⌉：非 2 的幂时 ⌈log2 K⌉ 会多 1 位（K=8 恰为 2 的幂，两种写法同值 19；A6 的 `ceil-gap cells=21` 列出的正是 21 个非 2 幂格）。K=8 的紧性见证唯一（全 `−128` 组合取到 131072 > 18 位上限 131071，19 位位宽推导）。

**随 SEW 推广的位宽表**（W 由 L4 公式【定理】代入；`out/validate/run.log:13` 的 `[A6]` 行实测打印的是其中三格——`W(8,8)=19`、`W(8,16)=20`、`W(16,2)=33`，**其余格为公式代入值、未逐格打印**）：

| SEW | K=4 | K=8 | K=16 | K=32 | K=64 |
|---|---|---|---|---|---|
| 8  | 18 | **19**（当前实测锚点，A6 打印） | 20（A6 打印） | 21 | 22 |
| 16 | 34 | 35 | 36 | — | — |

**关键设计后果（这是本节唯一与「能不能扩」直接相关的一条）**：位宽公式**线性于 SEW**，因此树的门数也线性于 SEW——参数化不需要改结构，只需把 `width` 从 19 换掉。当前 `VdotReduce` 把它**固定**成编译期常量并加了断言，扩 SEW 时必须先解除这处锁：

```scala
// repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala:20,27
class VdotReduce(k: Int = 8, width: Int = 19) extends Module {
  require(k == 8 && width == 19, "VdotReduce is specified for K=8 int8 lanes and a 19-bit accumulator")
```

`require` 是**位宽参数化路线的关键阻断点**（去掉它即可让 `k`/`width` 随 SEW/K 走；SEW=16 另有两处接口/布局阻断，见下），树本身的生成器 `CSA_Nto2With3to2MainPipeline(n, width, pipeLevel)` 已经是双参数化的（`repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/VectorFloatFMA.scala:1881`，`width` 直接进 `CSA4to2`/`CSA3to2` 的逐位循环 `:1610`）——**树不用重写，只是 19 这个常量不再够用**。

**SEW=16 的两个额外阻断（不是位宽问题，是接口/布局问题）**——此处给出可核对的对应关系：

1. **`cout_wo` 未导出**：`VIMac64b` 的 8 个 16 位 CPA 每 lane 有一个进位输出（`repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VIMac64b.scala:194` 声明 `val cout_wo = Wire(Vec(8, Bool()))`、`:198` 赋值），SEW=16 时一个 32 位元素跨两个 16 位段、**必须靠 `cout_wo` 串接**；该信号不在 `:35-37` 的导出端口表内（当前只导出 `sum_wo`/`walOut`/`fireS1`），要扩 SEW=16 得**再改一次共享模块端口**（X15 的「一次导完」约定已把这次改动关掉，见 `design/ARCHITECTURE.md` §5.3）。
2. **容器装不下**：W=35 > 32，`vd[31:0]` 会**丢高 3 位**（位宽约束：「SEW=16,K≥2 起 W≥33>32，32 位容器丢高 3 位（W=35），不是 13」），必须同时改 vd 布局（每结果 64 位或换 `vwdot` 类 widening 形态）。

### 7.2 VLEN 扩展：lane 数、树深度与面积的两个口径

**先说清一件事**：当前 `VLEN=128`（`repos/XiangShan/src/main/scala/xiangshan/Parameters.scala:60`），`VIMacU` 按 `dataWidth/64` 例化 **2 个** `VIMac64b`（`repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:49-51` 的 `numVecModule = cfg.destDataBits/64`、`:64` 的 `Seq.fill(numVecModule)`），而 vdot **只取 `vimacs(0)`** 的 `sum_wo`/`fireS1`（`VIMacU.scala:129-130`）——即**只消费 vs1/vs2 的低 64 位**（`vimacs(0)` 对应第 0 个 64 位切片，与 `design/SPEC.md:29` 的「取 vs1/vs2 **低 64 位 lane 0–7**，高 64 位不参与」一致）。所以 VLEN 扩展对 vdot 有**两种互不相同的语义**，必须分开算：

**口径 (a)「K 固定 = 8、结果数 np = VLEN/64」**（**注意：这条口径下语义是变的，不是不变**）：**每 64 位**数据是一个独立的 8-lane 点积 ⇒ VLEN=128 时有 **2 个结果**（np=2），VLEN=256 时 np=4。因此**每个 64 位切片复制一份 `VdotReduce`**（VLEN=128 时就是 `vimacs(0)`/`vimacs(1)` 各一份），树深度**恒为 2 段**（不随 VLEN 变），**每份树的 lane 数/树形完全不动**。**保持不变的只有「每 64 位的 K=8 单结果点积」这个原子语义**；整条指令从「1 个结果」变成「np 个结果」，这正是 §7.3 说的 np 轴扩展（要改 vd 布局、Mgu 旁路粒度与编码，见 §7.3 改动点 2/3），**不是「只是寄存器变宽」**。当前交付的 RTL **只连了 `vimacs(0)`**（`VIMacU.scala:129-130`）、实测面积 **481** 是**一份**树的面积 ⇒ 上表 VLEN=128 行的 962 是 **np=2 的推算值，与交付件不是同一形态**。面积【推算】= `481 × (VLEN/64)`：

| VLEN | 64 位切片数 | VdotReduce 面积【推算】 | 相对 VIMac 阵列【推算】 | 树深度 |
|---|---|---|---|---|
| 128 | 2 | 962 | 1.12%（= 962/(2×42783)） | 2 段【源码】 |
| 256 | 4 | 1,924 | 1.12% | 2 段（同构复制） |
| 512 | 8 | 3,848 | 1.12% | 2 段（同构复制） |

（**公开仓基线（K1）的实测值是 481 / 4,900 / 22**——那是**一份** `VdotReduce`（= np=1、只连 `vimacs(0)`）的面积（`results/yosys/40-area-20261104T094144.json:19`）；**当前 RTL（本地 P-2，`yunsuan@8942811`）实测 500 / 4,900 / 14**（`results/yosys/40-area-20261107T104238.json`，复现须应用 `patches/0005-…`，见 §4.13），**不是**上表 VLEN=128 行的 962（962 是 np=2 的推算值，对应「每 64 位各出一个结果」的形态，交付件未实现）；「2 段」来自生成器对 n=8 的确定性调度 `8→4→2`（`VectorFloatFMA.scala:1894-1900` 的 `n_next==8 ⇒ CSA4to2Num = n/4`），不是综合或 STA 结论；Yosys 的 `longest_path=22` 是拓扑级数，两者单位不同、不可互引。）

**占比恒为 1.12%** 是这条口径的核心结论：`VdotReduce` 与 `VIMac64b` 数量**同比例增长**（每 64 位一份树、每 64 位一个 MAC），所以「归约树相对乘法阵列」的比值与 VLEN 无关——**VLEN 扩展不恶化面积占比**（与 §5 实测的 `481 / 42,783 = +1.12%` 同值，因为 `481` 是一份树对一份 MAC 的比值，与复制多少份无关）。但**占比不恶化 ≠ 交付形态不变**：该口径下 np 随 VLEN 增长（VLEN=128 → np=2），需要 §7.3 的 vd 布局 / Mgu 旁路 / 编码三处改动，**均未实现**；「同构复制」只描述树本身，不覆盖这三处。

**口径 (b)「K = VLEN/8」**（把整个向量寄存器收成一个单结果点积，即真·K=VLEN/8）：此时 lane 数 = `VLEN/8`，K 随 VLEN 走，树深度按下式增长【推算】：

```
lanes(VLEN)  = VLEN / SEW                        # SEW=8: 16 / 32 / 64
K            = lanes                             # 口径 (b) 取整寄存器归约
depth_stages = ⌈log2 K⌉ − 1                      # 4:2 每段 n→n/2，故段数 = log2(n) − 1
             = log2(VLEN) − 4                    # 代入 K=VLEN/8、SEW=8
```

其中 `depth_stages = log2(K) − 1` 是 4:2 树的**理想段数**（K=8 → 2 段，与实测 `VdotReduce` 的 2 段一致）；实例数 `K/2 − 1`（K=8 → 3，与 `design/ARCHITECTURE.md:73` 的「2 段 / 3 个实例」一致）。**注意 `log2(VLEN)−4` 只对 K=VLEN/8 且 SEW=8 成立**，且口径 (b) 在 VLEN=128 时就是 K=16（**已不是当前交付的 K=8**，仅作扩展形态）：

| VLEN | lanes = K | W【定理】 | 理想实例数 | 理想段数【推算】 | 面积【推算】 | 占 VLEN 对应阵列【推算】 |
|---|---|---|---|---|---|---|
| 128 | 16 | 20 | 7 | 3 | 1,149 cells / 11,704 tr | 1.34% |
| 256 | 32 | 21 | 15 | 4 | 2,556 cells / 26,039 tr | 1.49% |
| 512 | 64 | 22 | 31 | 5 | 5,506 cells / 56,090 tr | 1.61% |

**必须如实标注的一条**：上表「面积【推算】」用的是**理想 4:2 树**（每段严格 4→2）。仓内生成器 `CSA_Nto2With3to2MainPipeline` 在 `n ∉ {4,8}` 时**退化为 3:2**（`VectorFloatFMA.scala:1894-1895`：`CSA4to2Num = if(n_next==8 || n_next==4) n_next/4 else 0`、`CSA3to2Num = ... else n_next/3`），我按源码逐段模拟其调度得【推算】：n=16 → 11 实例 / 4 段；n=32 → 29 实例 / 7 段；n=64 → 61 实例 / 9 段，对应面积 1,792 / 4,918 / 10,809 cells——**是理想 4:2 的 1.56 倍 / 1.92 倍 / 1.96 倍**。因此「K>8 直接复用现成生成器」不成立，扩 K 时**要么补一条纯 4:2 调度，要么接受约 2 倍的面积与近乎翻倍的段数**。这条是本节的**反面结论**，写在这里是为了防止「树不用改」被读成「什么都能直接扩」。

**深度与拍数的关系（只到定性，不外推）**：当前 2 段树 + 19 位 CPA 整体落在 `VimacCfg` 的第 2 拍内（`repos/XiangShan/src/main/scala/xiangshan/backend/fu/FuConfig.scala:563` `latency = CertainLatency(2)`），实测 `L_vdot=4`、拓扑级数 22（§5【实测】）。口径 (b) 到 5 段（VLEN=512）时，段数从 2 增到 5，**第 2 拍是否仍容得下未测**——本报告不给「仍 2 拍」或「需 N 拍」的结论，需 STA（§8 已声明缺省）。口径 (a) 则是同构复制，**每份树的深度不变**，这一条不依赖 STA 也成立。

### 7.3 LMUL>1 与多结果（np）：改动点集中在 wrapper 与 Mgu，不在树

**先给结论**：LMUL 不是独立的扩展轴，它是 (K, np) 的**别名**（扩展性设计的选择）——LMUL=2 意味着一次指令吃 2 个向量寄存器，等价于「每寄存器一个结果」（np=2）或「跨寄存器 K 翻倍」。两种读法在面积上差别很大，且**都未实现**。

**改动点 1：`VIMac64b` 复用度不降**（这是本节最正面的一条）。vdot 的算术增量只有归约树，乘法阵列 0 行新增（§5【实测】）。扩 LMUL>1 时：

- **np 轴（每 64 位出一个结果）**：`VIMac64b` **原样复用**，只是把 `vimacs(0)` 换成 `vimacs(0..n-1)` 的**逐切片扇出**。当前 wrapper 只连了第 0 片（`VIMacU.scala:129-130`），扩 np 的改动是**把这两行变成 `for` 循环**，MAC 侧零改动。
- **K 轴（跨寄存器累加）**：需要先解决 §7.2 的生成器退化问题（3:2 调度导致 1.56 倍–1.96 倍的面积），且 `sum_wo` 的符号扩展必须保持（`design/ARCHITECTURE.md` §2.2 第 3 条「严禁零扩展」）。
- **np=4 × K=4（SEW=8）** 的面积【推算】：4 个 1 实例树（W=18）+ 4 组输出寄存器 = **655 cells / 6,668 tr**（每个结果约 164 cells），相对当前 481 是 **1.36 倍**；同参数改用 K 轴（K=16 单结果）则是 1,149 cells / 2.39 倍。**同等的「每指令 8×int8 点积数」，np 轴的面积倍率明显低于 K 轴**——这是 「np 轴优先于 K 轴」的设计选择在**实测基数线性推算**下的量化支撑（该设计选择本身另有模型口径依据，两者不可互引）。

**改动点 2：Mgu 链路必须逐条重判**（当前靠 `Mux` 旁路，扩 np 后旁路的粒度变了）。当前实现是**整条 `res.data` 一次性旁路**：

```scala
// repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:159-160
private val outIsVdot = outCtrl.fuOpType === VimacType.vdot
io.out.bits.res.data := Mux(outIsVdot, vdotReduce.io.vd, mgu.io.out.vd)
```

扩 np 后 `res.data` 里有 n 个结果，但 Mgu 的 tail/agnostic 是**按 byte 逐位算**的（`repos/XiangShan/src/main/scala/xiangshan/backend/fu/vector/Mgu.scala:89-92` 的 `MuxCase(oldVdVecByte(i), activeEn→vd, agnosticEn→byte1s)`）。所以：

- **旁路不能整条**：必须改成「vdot 结果区（`n×32` 位）旁路 + 其余位仍走 Mgu」，否则 `vl < VLMAX` 的 tail 区会跟着一起被清零/覆盖，破坏 vta/vma 语义。
- **一个反直觉的点**：vdot 的语义是「无条件全写」（`design/SPEC.md:34` 的 vl 行：vl 任意值都算 lane 0–7 并全写 vd）。扩 LMUL 后「全写」的范围变成 `n×32` 位，**这与 Mgu 的按 vl 裁剪天然冲突**——即扩 LMUL 不是「加个循环」，而是要重新定义「哪些 byte 归 vdot 全写、哪些归 Mgu」。这是本节**改动面最大的一处**，比树大得多。
- **断言要跟着改**：`VIMacU.scala:165` 的 `assert(... PopCount(io.out.bits.res.data(VLEN - 1, 32)) === 0.U)` 断言的是「32 位以上全零」，扩 np 后这个断言**会直接失败**，必须换成按结果区逐段断言。

**改动点 3：编码不可交付**（扩展性限制）。`VimacOpcode.width = 3` 八个值已全占（`repos/XiangShan/yunsuan/src/main/scala/yunsuan/encoding/Opcode/VimacOpcode.scala:6-14`：`000`–`111`，其中 `111` = `vdot`）。np≥2 的语义变化（每 32 位一个结果 vs 整寄存器一个结果）**不能塞进同一个 opcode**，需要新的 `funct6` 或新的 opcode 空间——`design/SPEC.md:105` 给的方向是 `vdot4a` 类严格对齐 `101100/010`（Zvdot4a 官方分配，`design/SPEC.md:100`）。**故 np≥2 只写规格 + 代价 + 「未实现」**（已列入「不做」清单）。

**`vdot.vs`（标量广播形态）**：未在设计中登记，本报告**不做架构断言**。可核对的现状是：标量广播在香山向量侧走的是 `i2v`/`f2v` 的 dup 路径（`repos/XiangShan/src/main/scala/xiangshan/backend/decode/DecodeUnitComp.scala:471-474` 的 `FuType.i2v` + `IF2VectorType.iDup2Vec`），即**标量先广播成一个向量临时寄存器、再当 vs2 用**；因此 `vdot.vs` 的合理对应是复用该路径 + 现有 `VdotReduce`，**代价是多一条 dup uop、不是改树**。该形态**未实现、未测**，此处只记路径判断，不作为证据。

### 7.4 面积线性度：以实测 481 / 4,900 / 22 为单位基数

**实测参照基数**：`results/yosys/40-area-20261104T094144.json:19`（作业 `126752216`，`status=通过`，`scope` 见同文件 `:12`「仅 vdot 数据通路模块，未含 VIMacU 其余部分，未含工艺库」）：

```json
{"top": "VdotReduce", "cells": "481", "transistors_est": "4900", "longest_path": "22", ...}
```

同文件 `:18` 的对照项 `VIMac64b` = `42783` / `293640` / `100`。分解见 `stage3/3.3/evidence/area-derivation.txt`：481 = **458 组合** + **19 `$_DFFE_PP_`** + **4 `$scopeinfo`**（`results/yosys/vdot.stat.json` → `modules.\VdotReduce.num_cells_by_type`，本机实读）。

**推算模型（固定公式，可复算）**：把实测 458 组合 cells 摊到「实例·位」上，得到单位基数

```
u      = 458 / (3 实例 × 19 位) = 8.035 cells / (实例·位)      # 实测反解
tr/cell = 4900 / 481 = 10.19                                    # 实测比值
```

于是 `cells(K, SEW, np) ≈ u · (np·I(K)) · W(SEW,K) + np·W + 4`，其中 `I(K) = K/2 − 1`（理想 4:2 实例数），`np` = 每指令结果数（np=1 时退化为 `u·I·W + W + 4`，即「树 + 1 组 W 位输出寄存器 + 4 scopeinfo」；实测的 19 个 `$_DFFE_PP_` 正是这 19 位结果寄存器）。**回代校验**：`K=8, SEW=8, np=1` → `8.035 × 3 × 19 + 19 + 4 = 481.0`，与实测 481 精确闭合——这说明该线性模型**只是把实测值重新参数化，没有引入新数字**。

**扩展面积【推算】**（每一行都按实测基数线性推算，均**无 RTL、无综合、无 difftest**）：

| 参数 | W【定理】 | 实例总数 | 段数 | cells【推算】 | transistors【推算】 | 相对 481 倍数 | 占单个 VIMac64b |
|---|---|---|---|---|---|---|---|
| K=4, SEW=8, np=1 | 18 | 1 | 1 | 167 | 1,697 | 0.35 倍 | 0.39% |
| **K=8, SEW=8, np=1（当前）** | **19** | **3** | **2** | **481【实测】** | **4,900【实测】** | **1.00 倍** | **1.12%** |
| K=16, SEW=8, np=1 | 20 | 7 | 3 | 1,149 | 11,704 | 2.39 倍 | 2.69% |
| K=32, SEW=8, np=1 | 21 | 15 | 4 | 2,556 | 26,039 | 5.31 倍 | 5.97% |
| K=64, SEW=8, np=1 | 22 | 31 | 5 | 5,506 | 56,090 | 11.45 倍 | 12.87% |
| K=8, SEW=16, np=1 | 35 | 3 | 2 | 883 | 8,992 | 1.84 倍 | 2.06% |
| K=4, SEW=16, np=1 | 34 | 1 | 1 | 311 | 3,170 | 0.65 倍 | 0.73% |
| K=4, SEW=8, np=4 | 18 | 4 | 1 | 655 | 6,668 | 1.36 倍 | 1.53% |

> 表内「相对 481 倍数」是**面积比值**（同一量纲 cells ÷ cells），不是任何形式的加速比；本报告**被采用**的「×」形态加速比只有 §4.3 的每指令归一 `1.33×`（该处另有整数打印口径 `1.25×` 与其口径说明）。

**线性度结论（三条，全部基于上表）**：

1. **K 轴是超线性的，但斜率温和**：K 每翻倍，面积涨 **2.39 倍 / 2.22 倍 / 2.15 倍**（K=8→16→32→64）。原因是实例数 `K/2−1` 线性、W 只按 `+1` 增长（`⌊log2 K⌋`），两者相乘给出 `O(K log K)`；但**固定项与 W 的占比随规模摊薄**，所以倍率从 2.39 降到 2.15——即**规模越大，单位 lane 越便宜**。
2. **SEW 轴近似线性**：SEW 8→16 在 K=8 下面积 481→883（`883/481 = 1.8358` 倍），`W` 从 19→35（`35/19 = 1.8421` 倍）—— 两者**差 0.34%（相对）**，不是「完全同倍率」。差源是固定项 `np·W + 4`（模型 `u·I·W + W + 4`）：门数部分与 W 严格成正比，但 +19（输出寄存器）+4（scopeinfo）这两项不随 W 等比放大，故实际倍率略低于 W 的倍率。**结论应按「近似线性（偏差 0.3% 量级、来自固定项）」表述**，不写「完全同倍率」。
3. **相对乘法阵列的占比始终是个位数**：即使 K=64（VLEN=512 口径 b）也只有 **12.87%**（相对**单个** `VIMac64b`）；若按该 VLEN 下应有的 8 个 MAC 算占比（`5,506 / (8 × 42,783)`）则降到 **1.61%**。**即：归约永远不是面积瓶颈，乘法阵列才是**——这是「复用 VIMac64b + 只加归约树」路线在扩展维度上的定量支撑。

**关于「K 轴 vs np 轴」的一条**（承接 §7.3）：同样把每指令的 8×int8 点积数从 1 提到 4，**np=4 × K=4 走 655 cells（1.36 倍）**，而 **K=16 单结果走 1,149 cells（2.39 倍）**。差异来源是 W：K=4 时 W=18、K=16 时 W=20，而 K=16 需要 7 个压缩实例 vs np=4 只需 4 个。**即：在「单位点积数」口径下，横向复制（np）比纵向加深（K）更省面积**——这与「np 轴优先于 K 轴」的设计选择同向，但该处依据是另一套模型口径（818/823 等），**两者不可互引、不可相减**（台账禁区）。

**两条必须同时写出的边界**：① 上表 `cells` 是 Yosys `abc` 通用门计数（`results/yosys/40-area-20261104T094144.json:12` 明确「未含工艺库」），**不是硅面积**，不能换 μm²；② `longest_path = 22` 是 `ltp -noff` 的**拓扑级数**，与 FA 级数（4:2 每段约 4 级）不同单位，**不可互引**（台账禁区）。

## 8. 待回填项（诚实声明）

| 项 | 现状 | 回填路径 |
|---|---|---|
| 基线组合序列的**依赖链延迟**（官方 3.3 要求项「Baseline 与 vdot 的 latency 加速比」所需的测量输入；本用例口径为**内部自设**，非官方口径） | **已实测，min / full 两口径分列**：**full 口径**（8×2000=16000 样本、`scale=full`）作业 `126762127`（`results/difftest/b3/91-b3-20261104T115624.log:13-16`、`:24`，`rounds=8`、`rounds_agree=yes`、`verdict=ALL_OK`）→ `L_base_chain=16`、`L_base_chain_per_instr=5`（精确 16/3≈5.33）；**min 口径**（4×500=2000 样本、`scale=min(ladder/B3_skipped)`）作业 `126750763`（`91-b3-20261104T092457.log:9-12`、`:14`）→ 同值 16（同链同 VL 交叉核对）。阶梯链 `L_base_chain_ladder=24` 与 `B3=11` 分列同表（本行不混算），见 §4.3 | 已闭合；口径约定见 §4.3「三条」；加速比只有一个：每指令归一 **1.33×**（整数口径 1.25×），原始 `16/4=4.0×` 属跨口径不采用；**不得**把本行数字写成「官方口径」（`perf_base_chain.c:55-56`） |
| 基线阶梯链（每点含 `vsetvli` 配置） | **已实测（本用例 full 尺度）**：`L_base_chain_ladder = 24 cyc/链步`（2000 样本、`cycles=47843`、median 24、mean 23、`chain=OK`；作业 `126762127`） | 见 §4.1 脚注 / §4.3；与 `L_base_chain`（16，配置外提）**不可相减、不可互替**，只作「含配置的忠实形态」，不作分母 |
| B3（第三套基线，**不作分母**） | **已实测（本用例 full 尺度，仅敏感性分析）**：`B3 = 11 cyc/op`（`126762127`，`not_vl4=yes`）；不作分母、不与任何链相减 | 见 §4.1 / §4.3（**不得**把 B3 当分母或与 `L_base_chain` 相减） |
| ~~新口径 B1/B2~~ | **已实测**（`142246`，`B1=6`/`B2=9`，`PERF_BASE verdict=ALL_OK`） | 见 §4.4 与 `../3.2-baseline/README.md` §3 |
| 面积重跑最新 JSON（含 DFF 指纹） | **已重跑（2026-11-04）**：作业 `126752216`（`results/yosys/40-area-20261104T094144.json`，`status=通过`）给出 VIMac64b `42783/293640/100`、VdotReduce `481/4900/22`，与 2026-11-01 同值；DFF 指纹 `19` 仍来自 `results/yosys/vdot.stat.json`（2026-11-01），新 JSON 未列 DFF | `results/yosys/40-area-*.json` → 本报告 §5 |
| 形式验证 miter（数据通路） | **已跑并达标（2026-11-04）**：作业 `126751660`（`results/formal/50-miter-20261104T093531.json`，`status=通过`）正向 `SUCCESS`、负控 mutant `FAIL`；scope 仅 `vdot_dp` 数据通路 | 不覆盖流水/发射/旁路；全流水形式验证仍未运行 |
| 2 拍时序闭合（`S2_own`/`S3_own` 探针） | **未运行**（`gen_probes.sh` 未建 + 无 Liberty/STA）。工具可达性本次已核实（`stage3/3.3/evidence/sta-toolcheck-20261106.txt`）：昆山登录节点 `source ~/tools/env.sh` 后 **Yosys 0.48 可用**，但 `sta`/`openroad`/`opensta` **均 NOT_FOUND**；`module avail` 与 `HOME` 内均无 OpenSTA/OpenROAD/ORFS、无 ASAP7/sky130 工艺库、无 Apptainer 镜像；本机 `yosys`/`sta`/`openroad` 全不在 PATH（`command -v` EXIT=1），仓内 0 个 Liberty/LEF/SDC/DB。⇒ **不是脚本出错，是工具与工艺库数据链缺失** | 本报告 §5 与 **§4.10.2**（写「设计目标」，不写「已收敛」） |
| 功耗 | **未测**（cell 占比 `481/42,783 = +1.12%` **不是功耗**；外部 Nanhu-vdot 的 `+0.5%` 是 **FPGA** 参照、不是硅数）。RTL 级只能给三条结构性事实（见 §4.10.3） | 见 §4.10.3；`report_power` 需 Liberty + 活动率，两者均缺（`evidence/sta-toolcheck-20261106.txt` §L6 结论 4） |
| 2.2 lint | **已跑（2026-11-04）**：作业 `126761068`（`results/lint/25-rtl-lint-20261104T113051.json`）对 `VdotReduce`（+两级 CSA）与 `VIMac64b` 两个 top 跑 `verilator --lint-only -Wno-fatal`，均 `rc=0`、`%Error=0`。**该次 `-Wno-fatal` 会把 warning 降级，`%Warning` 计数天然为 0 ⇒ 不能据此声称「无告警」**；修订另跑两档：**(a) 去 `-Wno-fatal`、默认告警集**（作业 `126798101`）两 top 均 `rc=0`/`%Error=0`/`%Warning=0`（`results/lint/25-strict-*.log`）；**(b) `-Wall`（打开告警集合）**（作业 `126803426`）`VdotReduce` `%Warning=1`、`VIMac64b` `%Warning=12`，**13 条全为 `UNUSEDSIGNAL`（Chisel 生成物的未用信号/未用位，含 `_RANDOM`），`%Error` 每 top 各 1 行（`VdotReduce` `Exiting due to 1 warning(s)`、`VIMac64b` `Exiting due to 12 warning(s)`，合计 2 行，均为汇总行、非缺陷类 error）；无 LATCH/WIDTH/CASEINCOMPLETE 等实质缺陷类**；Verilator 对 warning 计入退出码故 `rc=1`。⇒ 「lint 通过」（入库脚本判据 `rc=0 ∧ %Error=0`）在 (a) 成立；若判据是「`-Wall` 下 0 告警」则**不成立**（13 条 UNUSEDSIGNAL），本报告不把 (b) 写成通过 | 脚本 `core-package/scripts/25-rtl-lint.sh`（档 a 用一次性脚本 `results/lint/strict-lint2.sh`，**未加 `-Wall`**；档 b 用 `results/lint/wall-lint.sh`，两端 md5 分别 `a382af89…`/`f7089880…` 同值）；范围仅 `--lint-only`；provenance 见 `results/lint/provenance-strict-lint.txt` §P1–§P8 |
| ~~当前 30 例清单整份 `--full`~~ | **已跑**（`142246`，30/30、0 ABORT、9/9 criteria、`status=通过`） | 见 `../3.1.2-difftest/README.md` §2 |
| 编码检查退出码（`design/verify/encoding-gate.py`） | **EXIT=1（不是 PASS）**：本次实跑 `python3 -I design/verify/encoding-gate.py --snapshot "$OPCODES_SNAPSHOT"` → 上游维度 0 重叠、P1–P3 阳性对照 3/3 命中 + P4 反向对照 1/1 正确排除，但检出 3 条 `[SCALA-BITPAT]/[NEMU-DECODE-H]/[VECDECODER]` 漂移——**均为本仓自己已落地的 vdot 表项** | 见 §5.4；本报告**不宣称「编码检查通过」**，只主张「上游全库本编号位 0 占用 + 阳性对照 3/3 + 反向 1/1 命中」；同口径见 `stage2/2.1-design/README.md` §3 |
| 4 cyc 依赖延迟的**机制分解**（发射/写回/旁路各占几拍；`vdRen=T` 会否更慢） | **机制归因已确认（强），4 cyc 数值未独立复现**：`vdot` 不读旧 vd ⇒ 无依赖 `0.890/1.011`、`1.125/0.968 cyc/条`（q4/q8，M8/M3）；测量形状相同但读旧 vd 的 `vmacc` `4.875/7.531 cyc/条`（q4/q8，同窗 **5.5/7.5 倍**吞吐差（M5/M8），**不是加速比**；§4.8.2/§4.8.6 第 3 条，两臂指令不同、不称「唯一变量」）。「4 cyc」在 `perf_vdot.bin` 括窗口径自洽，但差分口径未复现（5.7–7.5），且差分模型自相矛盾，不能据此否定 4（§4.8.4）。**同口径对照（§4.8.5）**：按 Gloria/GEMwhu 依赖链口径复现，本项 6.984 vs 对方文档 7.008065 cyc/点积（RVV 基线 20.994 vs 20.991935）⇒ 同一量级、不主张优势 | 见 §5.5 / §4.8；确认作业 **`127142843`**（`status=通过`、12/12 criteria 达标；上一次 `127043684` 作复现记录） |
| 七份外部小节（`llmbench`/`dualchain`/`perf-slope`/`methodology`/`coverage`/`case-expand`/`innovation-p2`） | **7/7 已定稿并并入**：`llmbench.md`（§4.7.0–4.7.11）、`dualchain.md`（§4.8.1–4.8.7，2026-11-07 13:11 三轴版）、`perf-slope.md`（§4.9.1–4.9.7）、`methodology.md`（§4.10.1–4.10.3）、`coverage.md`（§4.11.1–4.11.6，2026-11-07 08:54 实跑版）、`case-expand.md`（§4.12.1–4.12.5）、`innovation-p2.md`（§4.13.1–4.13.7，2026-11-07 13:52 定稿） | 见 §4.6 与 §8.1 |

### 8.1 小节来源与并入核对

**本次（2026-11-06）定稿状态（实读）**：`stage3/3.3/sections/` 目录 13:31 建立。`ls -l stage3/3.3/sections/` 逐时实测：13:57 第 1 件（methodology）、14:20 第 2 件（case-expand）、14:23 第 3 件（coverage）；**15:16:06 轮询按 120 min 上限记 `TIMEOUT present=3/6`**，但后三件随后到达：16:51 `perf-slope.md`、17:31 `dualchain.md`、17:54 `llmbench.md`。**本节以最终 `ls -l` 实读为准**，15:16 的 TIMEOUT 快照已被取代；报告 §4.6 表与 §4.7–§4.12 均按最终版本（§4.13 为 2026-11-07 追加的第七件，见下条）。
**2026-11-07 修订（实读）**：R1/R2/R3/R6 修订后 `llmbench.md`/`dualchain.md`/`perf-slope.md`/`coverage.md` 四件内容更新（mtime 00:37/00:42/00:45/01:00，sha256 见下），本次按定稿源替换 §4.7/§4.8/§4.9/§4.11；`methodology.md`/`case-expand.md` 两件 sha256 与 2026-11-06 记录逐字同值（零改动），§4.10 未替换、§4.12 仅就地微调 2 处。
**2026-11-07 定稿（实读，本节最新）**：`dualchain.md`（13:11）、`coverage.md`（08:54）、`innovation-p2.md`（13:52）三件为本次更新/新增，按源文件替换 §4.8、§4.11，并把 `innovation-p2.md` 新增为 §4.13（§4.6 专题小节的第七件）；`llmbench.md`/`perf-slope.md`/`methodology.md`/`case-expand.md` 四件 sha256 与 2026-11-07 修订逐字同值（零改动、未替换）。**§4.13 是改 RTL 后的新增实测**（P-2 patch），不是既有数字的旁证——481/22 面积基线不变，500/14 单列（见 §4.13 来源注与 §5 末注）。

**小节来源与版本（七件全到；2026-11-07 定稿版以三件最新源替换 §4.8/§4.11 + 新增 §4.13）**：

| # | 文件 | 定稿版本（mtime / 大小 / 行数） | 并入结果 |
|---|---|---|---|
| 1 | `sections/llmbench.md` | 17:54 首版 → **2026-11-07 00:37 整理版** / 定稿版 19,274 B / 243 行 | **§4.7**：源 `## N.` → `#### 4.7.N`，正文一致（R2 口径修订版） |
| 2 | `sections/dualchain.md` | 17:31 首版 → 2026-11-07 00:42 → **2026-11-07 13:11 三轴版** / 定稿版 26,389 B / 252 行 | **§4.8**：源编号即 `4.8.x`，标题降级为 `#### 4.8.x`，正文一致（A/B/C 三口径 + M9/M10/M11 对照） |
| 3 | `sections/perf-slope.md` | 16:51 首版 → **2026-11-07 00:45 整理版** / 定稿版 22,151 B / 177 行 | **§4.9**：源 `## 4.9.x` → `#### 4.9.x`，正文一致（R1 口径修订版） |
| 4 | `sections/methodology.md` | 13:57 首版 / 14:19 修订 / 定稿版 34,562 B / 221 行 | **§4.10**：A/B/C 三节 → `#### 4.10.1–4.10.3`；D/E/F 附录按源文件标注不进正文（2026-11-07 复核零改动） |
| 5 | `sections/coverage.md` | 14:23 首版 / 16:00 修订 / 19:11 修订 / 2026-11-07 01:00 定稿 → **2026-11-07 08:54 实跑版** / 定稿版 19,306 B / 184 行 | **§4.11**：A–F 六节 → `#### 4.11.1–4.11.6`，正文一致（仅源内 `§A.x`/`§B.4`/`§C`/`§D`/`§D.1`/`§D.3` 交叉引用按小节编号重映射；源文件声明「以本文件为准」） |
| 6 | `sections/case-expand.md` | 14:20 首版 / 16:33 内容修订 / 19:10 修订 / 定稿版 15,172 B / 139 行 | **§4.12**：五节 → `#### 4.12.1–4.12.5`；按 16:33 修订版（终态作业 `127031933`、129/129）；2026-11-07 复核零改动，正文就地微调 2 处（见 §4.12 来源注） |
| 7 | `sections/innovation-p2.md` | **2026-11-07 13:52 定稿** / 定稿版 19,045 B / 163 行 | **§4.13**（第七件）：源 `## 4.13.N` → `#### 4.13.N`，正文一致；源文件头注的小节归属为 §4.13 |

**来源校验值（2026-11-07 定稿版的源文件 sha256 与字节数，可用 `git show HEAD:stage3/3.3/sections/<文件名>` 复核）**：`llmbench.md` = `19c2f49ea57f98bc94017e32f6502ef8bacfc3ce19d456352a888ca923465d4b`（mtime 2026-11-07 00:37，本次零改动）、`dualchain.md` = `baca2d90d25b9d2ac127f1b5243fe95a13c2b513576ee28415bba6da582b0d43`（mtime 2026-11-07 13:11）、`perf-slope.md` = `feb28dccf443c3c7574d5e5aeda708e19c4be479851b7d48277a8a75588daffc`（mtime 2026-11-07 00:45，本次零改动）、`methodology.md` = `59c48a1192211b23b05804092bac07a436f1870abf81fc76a1b37e2527a53797`（mtime 14:23，与 2026-11-06 记录同值）、`coverage.md` = `d60d2a2c7e1bbe6e35fe3c5ed8583b0cca8cc1eb157a4f03f7c9690ce6192346`（mtime 2026-11-07 08:54）、`case-expand.md` = `2f489d3625b92770ca770ea7be96db5dc62b83ecb4e24a6f7037b2b5b48794af`（mtime 19:10，与 2026-11-06 记录同值）、`innovation-p2.md` = `a91f824486cf78223abbd8b310a9ac82d1e87995c2aba339c5a8870ac6bb1909`（mtime 2026-11-07 13:52）。并入的正文与源文件一致（标题仅做层级降级；§4.11 仅做源内字母节交叉引用→小节号重映射；§4.12 仅 2 处就地微调，差异登记在 §4.12 来源注）。上述 sha256 与字节数为 2026-11-07 定稿版取值，对应 `git show HEAD:stage3/3.3/sections/<文件名>` 的 blob，可把 `git show HEAD:stage3/3.3/sections/<文件名>` 的输出接 `sha256sum` 逐件复核；2026-11-07 之后仅做用词统一，工作区当前文件的摘要与上表不同，`sha256sum stage3/3.3/sections/*.md` 给出的是当前值、不作为本表依据。

**七件到齐后的影响**：前六件是**追加证据**（LLM 算子复核、依赖链机制归因、斜率、方法学、覆盖率、用例扩展），并入只增不改已冻结数字；§1–§4.5、§5、§5.1–§5.6、§6、§7、§9 的既有结论不依赖它们。`llmbench` 两次独立作业逐值相同；`dualchain` 三轴版确认机制归因、未独立复现 4 cyc（同窗 5.5/7.5 倍，三口径不相除），并新增 M9/M10/M11 同口径量级对照（不主张优势）；`perf-slope` 只给每点开销斜率；`case-expand` 的**源文件**停在 129/129（作业 `127031933`），报告侧 §4.12 已按 **224/224**（作业 `127194011`，2026-11-08）补记，两者差异已在 §4.12 来源注登记。**第七件（`innovation-p2`）性质不同**：它改了一行 RTL（`VdotReduce.scala` +19/−6），实测 481→500 cells / 22→14 级 / DFF 19→38，且 30 例 `--full` 与 extra 129 复跑均通过（作业 `127137638`/`127137640`）；**该改动不在公开仓 9 个基线 patch 内**（`patches/0005-…`），故 §5 面积基线仍写 481/22，500/14 只作 §4.13 的本地实测值。

## 9. 用词核对（T2 判据）

- 本报告**不含**「延迟加速」+ 6/9 的组合表述：核对命令 `grep -cE "延迟加速 (6|9)" stage3/3.3/report.md` → **0**（命令与输出见 `evidence/t2-grep-check.txt`）。
- 6 / 9 只作为**每点开销倍数**出现在 §4.2 的吞吐口径行，并同句声明「不是加速比」；全报告仅有的加速比**主张**是 §4.3 的每指令归一 `1.33×`（整数口径 `1.25×`），原始 `16/4=4.0×` 明确标为跨口径、不采用。§4.7/§4.8/§4.9 只写裸比值、同窗吞吐差与每点开销倍数；§5.5 的「不是加速比」是否定句。
- 「481 cells」不写作完整面积/组合面积（组合口径是 458，见 §5）。
- §7 的扩展面积全部标【推算】、按 §5 实测基数线性外推，**不写成实测**；§7 不含任何加速比，但**含面积比值倍数**（「相对 481 倍数」列、§7.3 的 1.36/2.39 倍、§7.4 结论 1 的 2.39/2.22/2.15 倍与结论 2 的 1.84 倍、§7.2 口径 (b) 段的 1.56/1.92/1.96 倍），全部是 cells ÷ cells（同一量纲），已在 §7 标签约定句逐项登记。
- 不写「2 拍已收敛」（无 STA，见 §8）。
- 不写「SEW=16 / LMUL=2 已支持」（§7 一律写作「扩展形态 / 未实现」，并逐条给出阻断点）。
- 不写「比竞品快 N 倍」。

**2026-11-06 新增小节（§4.6–§4.12、§5.1–§5.6、§8.1）+ 2026-11-07 修订（16 行）+ 2026-11-07 定稿（扩至 19 行：新增第 17–19 行对应 §4.11 结构覆盖实跑受阻、§4.13 P-2 口径、§4.8 三口径不相除）**：

| # | 禁止表述 / 易违规表述 | 本报告的处理 | 核对命令与实测输出（2026-11-07 重跑） |
|---|---|---|---|
| 1 | 「延迟加速」紧跟裸 6/9 的组合表述 | 不出现（本行刻意不写出该字面串，避免核对文本自身被 grep 计入） | **全文**：`grep -cE "延迟加速 (6\|9)" stage3/3.3/report.md` → **0**（rc=1） |
| 2 | 全报告**仅有的**加速比主张 | 仅 §4.3 每指令归一 **1.33×**（整数口径 1.25×）是主张；§5.1–§5.6 内 `加速比` 命中 **2 处，均为否定句**（§5.5「同窗口径约 5.5/7.5 倍的每指令吞吐差，不是加速比」与评分对应表「不是延迟/加速比」）；§4.7/§4.8/§4.9 只写裸比值 / 同窗吞吐差 / 每点开销倍数；§4.13 的 481→500 / 22→14 是 before-after 差值，源文件 C6 明写「不是加速」 | `sed -n '/^### 5\.1/,/^## 6\./p' stage3/3.3/report.md \| grep -c '加速比'` → **2（均否定语境，无主张）** |
| 3 | 6 / 9 只能写成「每点开销倍数」 | 仅 §4.2 一处，且同句「不是加速比」；§4.9 的 10.8 / 4.7 也只写「每点开销倍数」，不是加速比 | `sed -n '/^### 4\.2/,/^### 4\.3/p' stage3/3.3/report.md \| grep -c '每点开销倍数'` → **2**；§4.9 的倍数逐句带「不是加速比」 |
| 4 | 新增比值必须各标口径、不互引 | §5.1 的 `+1.12% / +1.09%` 标「cells÷cells 面积比」；§5.4 的 `OPMVV 行数 82 / 已占 funct6 值 59 / 文件数 141 / 指令行数 1521` 标「编码扫描计数」；§5.3 的 `3 个 32 位高半区字` 标「3×32 位字」；§4.7 的 `100/58`、`1.406296/0.744915` 等标「裸比值（指令数 / cyc per int8 对）」；§4.8 的 `5.5/7.5 倍` 标「口径 A 内同窗每指令吞吐差（M5/M8）」、`M9 6.984 vs 7.008065` 标「同口径 cyc/点积对照」；§4.9 的 `10.8 / 4.7` 标「每点开销倍数」；§4.13 的 `+19 cells / −8 级` 标「同脚本 before-after 差值」；以上均**不称加速比、互不相除** | 逐节人工核对（本节表格逐条列出） |
| 5 | 不写「优于同题 / 全场唯一 / 首次 / 唯一设计」 | **5 命中，全部否定/非主张语境**：§4.8 首注（1 行）、§4.8.5 硬性约束（1 行）、§4.8 用词核对的命令文本（1 行）、§4.9.6 机时表「首次正式跑」（1 行，指第一次正式跑，不是「首次提出」）、§5 评分表注（1 行） | `sed -n '1,/^## 9\./p' … \| grep -nE '优于同题\|全场唯一\|首次\|唯一设计'` → **5 命中（行 418 / 603 / 654 / 814 / 1665），逐行确认无一处作结论使用** |
| 6 | 假说必须标【假说】；定稿后必须改写 | §5.5 已按 §4.8 双链实验改写：机制归因标「已确认（强）」，4 cyc 数值标「未独立复现」；旧标签「假说，待 sections/dualchain.md 实验确认」已全部移除 | `sed -n '1,/^## 9\./p' … \| grep -c '假说，待 sections/dualchain.md 实验确认'` → **0**；`grep -c '未独立复现'`（§9 前正文）→ **4** |
| 7 | 未实测数字必须标【推算】/【未运行】 | §5.4 编码扫描是**实测**（本次实跑）；§5.6 引的金模型 `1142 cases` 标「此前一批次记录、本次**未运行**」；§8 各待回填行逐条标注；§4.7–§4.13 并入进来的七件保留其自带【未运行】标签（LLM memory-bound / 斜率 minstret 对账 / **结构覆盖（实跑受阻）** / STA / 功耗 / P-2 的 miter 均明标未运行）；**2026-11-08 新增**：§4.9 斜率「本轮未重测」、§4.11.3/§4.11.6/§4.12.4 的「30 例整份无产物」、§4.12.5 机时台账「未读取」 | `sed -n '1,/^## 9\./p' … \| grep -c '未运行'` → **44**；`grep -c '推算'`（§9 前正文）→ **24** |
| 8 | 不得宣称「编码检查通过」 | §5.4 明写 `EXIT=1`、三条漂移均为本仓自身表项、**不宣称通过** | `sed -n '1,/^## 9\./p' … \| grep -c '不宣称「编码检查通过」'` → **2** |
| 9 | 定稿状态不得写错 | §4.6 表末列逐件标「已替换/已定稿」+ 大小/行数；§4.7–§4.13 七节标题均带并入版本；§8.1 逐件给 mtime/sha256；正文不再出现「未定稿」 | `sed -n '1,/^## 9\./p' … \| grep -c '未定稿'` → **0** |
| 10 | 不得把 481 写成完整/组合面积 | §5.1 明确 481 = 458 组合 + 19 DFF + 4 scopeinfo，组合口径 458 / 41,945；§4.10 引用同一分解；§4.13 的 481→500 只作同尺子 before-after（组合部分 458→458） | `sed -n '1,/^## 9\./p' … \| grep -c '481 = 458'` → **2**（§5 与 §4.10 各 1，均写作分解式） |
| 11 | 不得把 §5 的 22 级当 STA | §5.1 末「边界」句写明 `ltp -noff` 拓扑级数、不是 STA；§4.13.5 第 1 条对 14 级同口径声明 | `sed -n '1,/^## 9\./p' … \| grep -c 'ltp -noff'` → **4** |
| 12 | 不得把 difftest 当硅片实测 | §5.6 末「边界」① 明写 QEMU 级 difftest、平台昆山 | `sed -n '1,/^## 9\./p' … \| grep -c '不是硅片实测'` → **1** |
| 13 | 不写「功耗仅增 1.12%」/「几乎不增功耗」 | §4.10.3 开头即写"没有功耗实测、也没有可换算成 mW 的 RTL 功耗估算"，§8「功耗」行同口径；`481/42,783 = +1.12%` 只作 **cell 占比** | `grep -n '功耗仅增 1.12%'` → **3 命中，全在否定语境**（§4.10.3 开头"不能写"句 `report.md:958`、§4.10.3 的 C.4 禁止写法 `report.md:1001`、本表第 13 行），**无一处是主张**（按 methodology §F.4 的提醒：否定语境不能用裸 `grep -c` 判 0，须逐行确认） |
| 14 | 不写「2 拍已收敛」/「22 级 ⇒ 满足 2 拍」 | §4.10.2 标题即「2 拍是设计目标，不是收敛结论」；§8 该行现状写「未运行」并给工具缺失证据 | `grep -n '2 拍已收敛'` → **3 命中，全在否定语境**（§4.7.9「本节不写…」`report.md:367`、§9 禁止表述清单"不写…"条、本表第 14 行），**无一处是主张** |
| 15 | 不写「中位数是 Agner / K&J 方法」/「已做置信区间 / 统计显著」 | §4.10.1 的 A.4 末尾「因此报告中不得出现的三句话」逐条列出并给正确写法 | `grep -nE '中位数是 (Agner\|Kalibera)'` → **2 命中，全在否定语境**（§4.10.1 的"不得出现"句 `report.md:889`、本表第 15 行），**无一处是主张** |
| 16 | 跨窗「7.5×」/「唯一变量」不得作为结论（2026-11-07 新增） | §4.8 已改**同窗 5.5/7.5 倍（口径 A 内 M5/M8，q4/q8）**并明写「不写『唯一变量』」；§5.5/§8 同步改写；旧跨窗「7.5×」只在 §4.8.2 口径注解里作**已废止**说明 | `sed -n '1,/^## 9\./p' … \| grep -c '7\.5×\|唯一变量'` → **5**（行 9 / 479 / 1619 / 1621 / 1837），全部是「废止/不写/不称/不能称」语境，**无一处作结论使用** |
| 17 | 结构覆盖不得写成「覆盖率达标」或「覆盖率偏低」（2026-11-07 新增） | §4.11 通篇写 **【未运行（实跑受阻）】** 并给 `rc=139` / gdb 栈 / `--diff` 全跑崩溃的证据；§4.11.6 四条边界第 1 条明写「没有数字，就不能说 RTL 覆盖率高/低」；§5 评分表该行同步写「只有实跑受阻记录、没有数字」 | `sed -n '1,/^## 9\./p' … \| grep -c '未运行（实跑受阻）'` → **6**；`grep -n '覆盖率达标'`（§9 前）→ **2 命中，均为否定句**（行 1115「不写『覆盖率达标』」、行 1663「不得写成『覆盖率达标』」） |
| 18 | P-2 不得写成「加速 / 时序收敛」；500/14 不得当作公开仓直接可复现（2026-11-07 新增） | §4.13.1 C6 明写「P-2 是时序裕量/面积方向的改动，**不是加速**」；§4.13.5 第 1 条写「`ltp` 是拓扑级数、不是 ps、不是频率，**不写『2 拍已收敛』**」；§4.13 首注披露 patch 不在公开仓、`repos/` 被 `.gitignore` 排除；§5 末注重申 481/22 面积基线不变、500/14 单列 | `grep -c '时序收敛'`（§9 前）→ **1 命中，否定句**（§4.13 来源注「也不把它写成『时序收敛』」）；`grep -c 'patches/0005'`（§9 前）→ **9**（口径披露与复现路径，不当作已进基线） |
| 19 | 双链三口径不得相除；对手 7.008/20.992 必须标【对方文档】（2026-11-07 新增） | §4.8.1 口径约定固定「A/B/C 三者**不相除、不互引**」；§4.8.5 表内对方两列逐格标【对方文档】，结论只写「同口径下同一量级、本项不主张任何优势」，并明写不做减法是「不把 M9/M10 与对方数字相除当加速比」；§5.5 同步；**§4.9 报告侧补记**把「斜率 vs `T_steady`/`B2`」也固定为不相除 | `sed -n '1,/^## 9\./p' … \| grep -c '不相除'` → **10**；`grep -c '不主张任何优势'`（§9 前）→ **2**（§4.8.5 结论、§5.5，均为「同一量级」语境） |

> **计数口径**：本表所有计数都只统计 **§9 之前**的正文（`sed -n '1,/^## 9\./p'`），因为 §9 自身的核对表会写出被查的字面串；§9 内部的重复命中不计入上表。这一条同时解释了为什么"全文 `grep`"与"正文 `grep`"会有差值。

**逐行清单（供人工复核，命令 + 实测输出，2026-11-07 定稿版重跑）**：

```
$ grep -cE "延迟加速 (6|9)" stage3/3.3/report.md          # 全文，含本表
0
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -cE "延迟加速 (6|9)"
0
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -nE '优于同题|全场唯一|首次|唯一设计'
418:> 本节**不写**「优于同题」「全场唯一」；芯锐/Gloria 的 7 cyc 均按【对方文档】处理。
603:4. **硬性约束**：对方 7.008065/20.991935 是【对方文档】、本仓未复跑其镜像；本节只做**同口径量级对照**，不写「优于同题」「全场唯一」，
654:**用词核对**（2026-11-07 复核，逐条如实）：`grep -nE "优于同题|全场唯一|唯一.*优势" stage3/3.3/sections/dualchain.md`
814:| `127041527` | 首次正式跑（`ROUNDS=3`，`CASE_TIMEOUT=900`） | `FAILED`：emu 在 900 s 被 `timeout` 杀掉，差 4 行收尾（`rc=124`） | 00:15:04 | 1 行（`auto`） | 0.251 |
1665:> 表中七节均已定稿，不再保留空缺小节。本报告仍不写"某某分已拿到"，也不写"优于同题/全场唯一"（对手数字一律【对方文档】，见 §9）。**§4.13（P-2）与其它六件的性质差别**：它是改 RTL 后的新增实测，故 §5 的 481 / 22 面积基线**不变**，500 / 14 只作 §4.13 的本地实测值单列（复现须应用 `patches/0005-…`，不在公开仓 9 个基线 patch 内）。
$ sed -n '/^### 5\.1/,/^## 6\./p' stage3/3.3/report.md | grep -c '加速比'
2
$ sed -n '/^### 4\.2/,/^### 4\.3/p' stage3/3.3/report.md | grep -c '每点开销倍数'
2
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '假说，待 sections/dualchain.md 实验确认'
0
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '未独立复现'
4
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '未定稿'
0
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '推算'
24
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '不宣称「编码检查通过」'
2
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '未运行'
44
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '481 = 458'
2
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c 'ltp -noff'
4
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '不是硅片实测'
1
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '7\.5×\|唯一变量'
5
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '未运行（实跑受阻）'
6
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '不相除'
10
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '不主张任何优势'
2
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c 'patches/0005'
9
$ sed -n '1,/^## 9\./p' stage3/3.3/report.md | grep -c '未运行(dry-run)'   # §4.11 08:54 版已删除 dry-run 表行
0
$ grep -c '未运行(dry-run)' stage3/3.3/report.md          # 全文仅本行注释自身（§9 内的自指）
1
```

**各非零计数的定性**：① `优于同题|全场唯一|首次` 的 5 处 = §4.8 首注（1，行 418）+ §4.8.5 硬性约束（1，行 603）+ §4.8 用词核对的命令文本（1，行 654）+ §4.9.6 机时表「首次正式跑」（1，行 814，指第一次正式跑，不是「首次提出」）+ §5 评分表注（1，行 1665）；**没有一处是主张**。② `推算` 的 24 处 = §7 既有各处 + §5 边界引用 + §4.7/§4.9/§4.10/§4.11/§4.12/§4.13 各节（各源文件自带【推算】标签），**全部带标签**。③ `未定稿` 现为 **0**：§4.6 表、§4.7–§4.13 标题与 §8.1 均按「已替换/已定稿」写。④ `加速比` 在 §5.1–§5.6 的 2 处均为**否定句**（§5.5 的「不是加速比」与评分对应表的「不是延迟/加速比」），**§5 不含任何加速比主张**；§4.7/§4.8/§4.9 只写裸比值、同窗吞吐差与每点开销倍数，§4.13 只写 before-after 差值并明写「不是加速」。⑤ `未运行` 的 44 处集中在 §4.7（memory-bound / GOP/s）、§4.9（sacct 复跑 / minstret 对账 / 大工作集 / **本轮未重测斜率**）、§4.10.2（STA）、**§4.11（结构覆盖实跑受阻 6 处 + 干跑与未测声明 + 30 例整份无产物）**、§4.12.4/§4.12.5（30 例无产物、机时台账未读）、§4.13（形式 miter 未跑）、§8 表与 §5.6 边界，**均为未测声明**。⑥ 跨窗「7.5×」与「唯一变量」在 §9 前正文共 **5** 处命中，**全部是废止说明或禁止性表述**（日期行变更流水 行 9 / §4.8.2 口径注解 行 479 / §5.5 行 1619、1621 / §8 行 1837），符合第 16 行判据。⑦ `覆盖率达标` 2 处（行 1115 / 1663）与 `时序收敛` 1 处（行 1331）**全部是否定句**，对应第 17、18 行判据。⑧ `不相除` 9 处、`不主张任何优势` 2 处均属「三口径分列 / 同一量级」的口径约定句，对应第 19 行判据。

## 10. 配套材料索引（两件，2026-11-08 新增）

> 本节只做索引与引用，**不并入两份文件的正文**；正文留在 `sections/`，供后续合并时按 §4.6 的约定整件插入或替换。两件都是“把已有证据整理成图/表”，**不含新实测、不新增作业**。放在文末而不插入 §4/§5，是为了不推移 §4.7–§4.13 与 §8/§9 已登记的 `file:line` 锚点。

| 文件 | 主题 | 报告中的引用点 | 状态 |
|---|---|---|---|
| `stage3/3.3/sections/co-sim.md` | 软硬件协同验证机制图（五层链条 + 金模型/NEMU/RTL 传递闭合）与 DIFFTEST 参数/判据表（**18 项参数、11 条判据**） | §5.6 的配套材料（§5.6 只写四环正文，本文件补图与参数表） | **已就位，正文未并入** |
| `stage3/3.3/sections/tri-consistency.md` | 三端（金模型 / NEMU / RTL）正/负/边界用例对照表（**13 条数值正例、4 条随机/不变量、8 条负例覆盖行（含组合/非法优先）、8 条语义不变量、4 组最坏值**） | §5.6 / §4.11 / §4.12 的配套材料 | **已就位，正文未并入** |

> 两件的口径与 §5.6、§4.11、§4.12 一致：不新增性能数字，不写绝对化表述（优劣、排他、首创类），负例只判“两侧一致陷入”而不主张异常字段逐字段相等（`sections/tri-consistency.md` §F.1 明示）。**2026-11-08 复跑** `python3 -I design/verify/vdot_model_test.py` → `ALL TESTS PASSED (1142 cases)`、EXIT=0（见 `sections/co-sim.md` §G）；§5.6 上文「本次未运行」指的是 2026-11-07 那次报告生成口径，两者不冲突。
