# 3.3 补充小节：多规模斜率 + R² + stream 类（perf_base_slope）

> **位置**：本文件是 `stage3/3.3/report.md` 的正文来源，对应 §4.6 小节编号表的 **§4.9**。
> **并入方式**：按 §4.6 的编号约定整件插入、标题降为 `#### 4.9.x`；正文与源文件一致（仅标题层级与用词统一）。
> **版本**：XiangShan `913ddd3` / yunsuan `83059b5` / NEMU `a9dca53`（实施 HEAD）；基线 pin `a4eeaab` / `9559211` / `a683e0b`。**两种口径并列**：作业日志 `versions:` 行记录的是昆山源树的 git HEAD（`a4eeaab`/`9559211`）**+ 工作树改动**（实现在远端工作树中、未提交），不是 `913ddd3`；`913ddd3`/`83059b5` 是本地实施提交口径。两者不互称等价。
> **标注约定**：【实测】= 昆山作业实跑并取回日志；【实读】= 本次逐字读到仓内文件；【未运行】= 本次未执行。
> **数据源（全部来自一个作业）**：昆山作业 **`127043836`**（`kshcnormal`，8 核，`COMPLETED`，`Elapsed=00:08:53`，`ExitCode=0:0`）。
> 日志：`results/difftest/slope/98-slope-20261106T162837.log`（作业级，4,410 B）与
> `results/difftest/slope/cases-perf_base_slope.20261106T162837.log.gz`（emu 原始输出，4.76 MB → 145 KB gz）；
> JSON：`results/difftest/slope/98-slope-20261106T162837.json`（`status=通过`，8/8 criteria `达标`）；
> 复算件：`results/difftest/slope/98-slope-20261106T162837.recalc.json`（`calc_slope.py --out-json` 产出）。

---

## 4.9.1 结论（三句话，先说清口径边界）

1. **斜率口径可行，且给出的是「每点成本」而不是延迟**：`vdot` resident 斜率 **1.021 cyc/dot**（三点 R²=0.994990；两点斜率 0.969，见 §4.9.3）、`b2` resident 斜率 **11.019 cyc/dot**（R²=0.999963）。两者同为 `cyc = a + b·N` 的最小二乘 `b`，**同一把天平的每点开销倍数 = 11.019 / 1.021 ≈ 10.8 倍**（这是「每点开销倍数」，**不是加速比**，也不是本报告 §4.3 的每指令 `1.33×`）。
2. **加 stream 类后倍数收窄到 ≈ 4.7 倍**（`b2` stream 14.643 vs `vdot` stream 3.143 cyc/dot，R² 均 ≥ 0.994990）：把「每点重新 load 两路 8 B」计入后，vdot 自身的每点成本从 1.02 涨到 3.14，涨幅（+2.12 cyc/dot）与 B2 的涨幅（+3.62）同量级 ⇒ 在**本用例的 stream 定义下**（同一对 16 B 缓冲、L1 命中，见 §4.9.4 边界），装载开销是共同成本，指令本身的差值被摊薄。
3. **`n=8` 这一点不能当结论用**：它是 `rdcycle` 括窗与 ROB 深度同量级的一点（三个窗口只有 11/22/28 拍），窗口可与内核体重排 ⇒ 该点的**绝对周期**不可引用；三点 R² 高（四组 0.994990–0.999964）只说明三点近似共线，**不说明测量稳定**。同一组数据的两点拟合（只用 N=64/512）给出 0.969 且与三点斜率同量级（1.021 vs 0.969）⇒ 无坏点的证据是**两点拟合一致**。**报告正文引用斜率时，必须同时给出两点拟合值。**

---

## 4.9.2 三点原始数据（每点 3 个窗口，原样 CSV）

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

## 4.9.3 斜率与 R²（最小二乘，整数拟合 + 独立复算）

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

## 4.9.4 三套口径不可混称（本节最容易被误读的地方）

| 口径 | 定义 | 本节的数 | 能回答什么 | **不能**回答什么 |
|---|---|---|---|---|
| **① 斜率口径**（本节主产出） | 同一变体测 N=8/64/512 三点的窗口周期中位数，对 `cyc = a + b·N` 做最小二乘，取 `b`（cyc/dot） | `vdot` resident **1.021**、`vdot` stream **3.143**、`b2` resident **11.019**、`b2` stream **14.643** | 「批量跑 N 个点时，每多点一个点的边际成本」 | 单条指令的依赖延迟；单条指令的稳态吞吐；任何「延迟加速」结论 |
| **② 中位数口径**（既有 `T_steady` / `L_*`） | 逐次 `rdcycle` 取差、去 16 次暖机、取中位数（`design/verify/perf/perf_vdot.c:41,43,118-129`） | `T_steady=1`、`B2=9`（`stage3/3.3/report.md` §1/§4.4） | 单条指令背靠背的每点开销 | 多规模标度；与①**不可互换、不可相除** |
| **③ 每指令 1.33×** | `L_base_chain_per_instr / L_vdot`（整数口径 1.25×，`perf_base_chain.c` + T5 三链） | 1.33×（`stage3/3.3/report.md` §4.3） | 「同一把天平上的每指令归一比值」 | 与本节的 10.8 / 4.7 倍**不是同一个量**：那两个是①口径内部的 `cyc/dot ÷ cyc/dot`，本节只写成「每点开销倍数」 |

**评分对应**：① 行对应 `docx/02-赛题与评分细则.md:90`「阶段三交付物完成度」中的「基线实现、延迟加速分析报告」（25 分档）——本节给出基线（B2）与 vdot 的每点成本对照、拟合质量与 stream 类边界，作为该分析报告的支撑材料之一；本节**不新增任何加速比表述**，§4.3 的整链 `4.0×` 与每指令归一 `1.33×` 是两个并列口径。

**三条硬约束（本文件自我约束，评审可机械核对）**：

- 本文件**不出现**「加速比」定义句；`10.8 / 4.7` 全部写成「每点开销倍数」。
- **不把①与②相除**：例如「1.021 vs `T_steady=1`」「11.019 vs `B2=9`」只能写成「同量级交叉核对」，绝不能写成「差 0.021」「差 2.019」。同量级核对本身也只是**披露**，不是判据（两者估计量与窗口结构都不同：本节窗口是 8 点展开，`T_steady` 是逐条括窗）。
- `L_base_chain=16`（含 `L_base_chain_per_instr=5`）是 `perf_base_chain.c` 的**独立测量项**，本节**不引用、不修改、不相除**（该文件与其镜像本次零改动，见 §4.9.5）。

---

## 4.9.5 方法学：为什么用斜率、为什么这样切 stream、边界在哪

**（a）为什么斜率能消掉 `rdcycle` 的固定偏斜。** 香山的 `mcycle`/`minstret`/`cycle` 不在有序读 CSR 白名单（`CSROoORead.scala:10-55`），`rdcycle` 括窗可与内核体重排 ⇒ 单点绝对周期带一个**与 N 无关的固定偏斜**。对 `cyc = a + b·N` 拟合时，该固定项落进截距 `a`，斜率 `b` 不受其影响；`n=8` 点因窗口太短而抖动，正是这条机制的直接后果（§4.9.3）。

**（b）为什么每个 BODY 是固定 8 点 + C 层循环，而不是按 N 全展开。** N=512 的 B2 若用 `.rept 512` 展开会生成 ~26 KB 直落代码，把 L1I 打爆 —— 那时测到的是「代码体积」而不是「每点开销」。因此四个通道都用**同形的「8 点展开 + C 循环」**（`design/verify/cases/perf_base_slope.c` 的 `VDOT_RES_8`/`VDOT_STR_8`/`B2_RES_8`/`B2_STR_8` 与 `window_vdot`/`window_b2`），循环开销（计数器 + 分支，每 8 点一次）对四组**完全相同**，摊进斜率的是同一个量 ⇒ `b2 − vdot` 之差就是每点开销差，不被循环结构污染。

**（c）两条通道的「点」定义不同（已按各自既有定义对齐，不混称）。**
`vdot` 点 = 1 条 `vdot.vv`（8 路独立 `vd`，窗口内零 `vsetvli`、零读回）—— 与 `perf_vdot.c` 的 `T_steady` 同形态（`T_steady=1` cyc/dot，本节 1.021，**同量级交叉核对**）。
`b2` 点 = `perf_base.c` 的 `b2_once` 全序列（3 条配置 + `vmv.v.x v8` 死指令 + 归约初值 + `vwmul/vwadd/vredsum` + 读回配置 + `vmv.x.s`）—— 与 `B2=9`（每点开销）同形态。`perf_kernel_cmp.c:11-13` 把 `vmv.v.x v8, zero` 当死指令**删掉**了；本用例与 `perf_base.c` 一致**保留**（因为 `B2=9` 就由 `perf_base.c` 定义），两者差 1 条指令是**已知差异**。

**（d）stream 类的边界（必须一起读，否则会把 4.7 倍读成内存带宽结论）。**
stream = **每点重新 load 两路 8 B**（`vle8.v v3,(a0)` + `vle8.v v4,(a1)`，随后 `vdot` 读 v3/v4；B2 侧同样在首条 `vsetivli e8,m1,vl=8` 之后插 2 条 load）。两个地址是**同一对 16 B 缓冲 `buf_a`/`buf_b`（L1 常驻）**，不是遍历大数组 ⇒ 本节量的是**装载通路吞吐 + 计算**，**不是 DRAM/LLC 带宽**。报告正文不得据此写「内存受限时只有 1.0×」之类结论；若要该结论，需要另做「大工作集、逐点换地址」的用例【未运行】。

**（e）自检（防假通过）。** 用例每跑完一组就回读结果与软件模型比对：`vdot` 读 `v8` 与 `v15` 都必须等于 `0x00000008` 且都不等于「只归约前 4 lane」的错值 `0x00000012`；`b2` 读 `v10` 同样两个断言。作业日志四条 `SLOPE check` 全 `match=OK not_vl4=yes`，另有 `vl=8`、编码 `0x3A20A1D7`、单调性 `increasing=yes` 四项总检 ⇒ `SLOPE verdict=ALL_OK`【实测】。**未覆盖**：本次没有做「N 与实际点数」的独立计数（如 `minstret` 对账），点数的真实性由 `cyc ∝ N` 的单调性与拟合线性间接支撑 —— 这是本节承认的残余风险。

**（f）外部方法学参照的边界。** 本节只采用本仓定义的四通道与线性拟合口径。外部公开材料曾以「4 workload × 3 基线 × N=128/512/2048 线性拟合 + R²」组织数据；其 workload 分类、N 点集与本节不同，**不能直接比较、不相除、不换算**。其摘录未记录另两条基线与逐格 R²，本项**不补造**；本节 `b2/resident` 11.019 只在本节口径内解释，不引用其它实现的自报比值。

---

## 4.9.6 复算与机时

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

## 4.9.7 诚实边界（本节的「不能说什么」清单）

- **不能**把 1.021 / 3.143 / 11.019 / 14.643 写成任何形式的「延迟」「加速比」或与官方口径挂钩：这些是 `cyc = a + b·N` 的**批吞吐斜率**，内部自设口径（同 `perf_base_chain.c:55-56` 的「官方只要求用已有向量指令组合实现，未规定条数/延迟口径」）。
- **不能**把 `10.8 倍` 与 `1.33×` 并列成「两种加速比」：前者是同口径的每点开销倍数（`b2` vs `vdot` 的斜率比），后者是每指令归一的 `L_base_chain_per_instr / L_vdot`；两者分母不同、口径不同。
- **不能**把 stream 的 4.7 倍说成「内存受限下的真实差距」：工作集只有 32 B（§4.9.5(d)）。
- **不能**用三点的 R² 单独证明测量质量：三点拟合 R² 高（0.994990–0.999964）只说明三点近似共线；`n=8` 的窗口只有 ~11–28 拍、可与 ROB 重排，结论必须带两点拟合交叉（`vdot/resident` 三点 1.021 vs 两点 0.969）。
- **未运行**：逐点 `minstret` 对账（点数真实性）；大工作集 stream；`ROUNDS > 3` 的统计（机时预算否决，见 §4.9.6）。
- `n=8` 的绝对周期（22 / 26 / 86 / 119）**不作任何结论引用**，只作为拟合的低端锚点出现。