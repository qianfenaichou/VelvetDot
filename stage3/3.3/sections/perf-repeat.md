# perf-repeat：四个 perf 用例的跨重复中位数与预登记加速比口径

> **状态：预登记已执行 + 实测已回填（2026-11-08）**。本文件的 §0/§1 在任何本轮
> 数据产生前写死；§2 为作业返回后的实测回填。两者无冲突：实测 `L_vdot` 跨重复
> 中位数为 4，按预登记口径得 **1.33×**（整数打印口径 1.25×），未改口径。
> **定位**：`stage3/3.3/report.md` 的外部支撑小节（源文件，不并入正文小节编号）。
> **标注约定**：【预登记】= 本轮作业前写定；【实测】= 昆山作业实跑；【实读】= 本次
> 逐字读到仓内文件；【未运行】= 本次未执行。

---

## 0. 预登记：官方 3.3 要的加速比口径

### 0.1 官方原文（分母的合法性边界）

- `docx/02-赛题与评分细则.md:61`：「用已有向量指令组合实现相同功能作为基线；对比基线组合与 vdot 专用加速单元的延迟，完成加速比分析。」
- `docx/02-赛题与评分细则.md:66`：「3.3 延迟加速分析报告：对比 Baseline（组合指令）与 vdot 加速单元的 latency 加速比分析」。

两条都指向 **latency**（延迟），且只要求基线「用已有向量指令组合实现」，**未规定组合的
条数、未规定统计口径**。因此本文件把「每指令归一延迟比」预登记为官方 3.3 的加速比口径，
分母与限定逐条写死如下。

### 0.2 预登记口径（唯一主张）

```
speedup_per_instr = (L_base_chain / 3) / L_vdot
```

| 项 | 预登记值 | 定义与来源 |
|---|---|---|
| 分母 `L_base_chain` | **16 cyc/链步** | 3 条串行指令 `vwmul.vv → vwadd.vx → vredsum.vs` 的 RAW 依赖链，**全程 e16,m1、配置外提、循环内零 `vsetvli`**；full 尺度 8 轮 × 2000 = 16000 合并样本的**中位数**。来源：作业 `126762127`，`results/difftest/b3/91-b3-20261104T115624.log` 的 `PERF L_base_chain: rounds=8 samples=16000 median=16 …` 与 `VDOT_METRIC L_base_chain 16`【实读】 |
| 分母归一 | **16/3 ≈ 5.333 cyc/指令** | 链内 3 条串行指令平摊；脚本整数打印为 `5` |
| 分子 `L_vdot` | **本轮 4 次重复的跨重复中位数** | `vdot.vv v10,v10,v1` 的 `vd==vs2` RAW 依赖链；每次独立 emu 进程内 N=2000、去前 16 次暖机、取用例内中位数；本轮再对 4 个进程的结果取中位数。计数法与分母同源（`design/verify/perf/perf_vdot.c:40-43`、`design/ALGORITHM.md:192,212`） |
| 主张值（若 `L_vdot` 中位数 = 4） | **1.33×** | `5.333 / 4 = 1.3333…` |
| 整数打印口径（同口径保守舍入） | **1.25×** | `5 / 4 = 1.25`；仅作同一口径的整数舍入下界，不另立口径 |

**预登记结论句（跑前写定）**：若本轮 `L_vdot` 的 4 次跨重复中位数为 4，则官方 3.3 的
加速比主张为 **1.33×（每指令归一；整数打印口径 1.25×）**；若不是 4，按实测重算并
如实报告，**不把 1.33× 写死**。

### 0.3 明确不采用「内核 16/7 ≈ 2.29×」作为官方口径（跑前写定）

`stage3/3.3/report.md` §4.5 已把 `16/7 = 2.285…` 标为「**内核级动态拍数对比**」并明写：

> 「本小节只报『指令数对比 / 吞吐对比』，**不是延迟加速比、不是官方口径**」（`report.md:129`）

该数的分母是「每次内核调用」的 8-lane 内核拍数（含装载/配置/读回与 C 循环），
分子是同一内核的 vdot 版本拍数；它回答「一次内核调用省几拍」，**不回答单条指令的
latency**。把它写成官方 3.3 的 latency 加速比，会把「内核总拍数比」偷换成「指令延迟比」，
与官方 `docx/02:61,66` 的问法不一致。**因此本文件不采用它，也不把两个口径并列成
「两种加速比」。**

### 0.4 判定规则（先写死，防止事后改口径）

1. **有效样本**：4 个用例 × 4 次重复 = 16 次独立 emu 进程；每次必须
   `HIT GOOD TRAP ≥ 1`、`ABORT == 0`、`HIT BAD TRAP == 0`、`rc == 0`，且命中各自
   `PERF_* verdict=ALL_OK` 汇总行。
2. **统计量**：同一用例的同一 `VDOT_METRIC` 在 4 次重复上取**中位数**（偶数次取中间
   两数均值）并同时报**极差 = max − min**；不丢任何一次、不挑最好一次。
3. **分子缺失/不为 4**：若 `L_vdot` 跨重复中位数不是 4，则 `speedup_per_instr` 按
   `5.333 / 实测中位数` 重算并如实写出；同时把「与 report §1 的 `L_vdot=4` 不一致」
   记为未达标，不静默改口径。
4. **分母不变**：`L_base_chain=16` 是预登记常量，本轮**不重测**分母；若分母本身被
   后续作业推翻，应另开一轮预登记，而不是在本轮改分母。

### 0.5 限定（必须与数字同页出现）

1. **两个口径并列，不能混称**：整链口径 `L_base_chain / L_vdot = 16/4 = 4.0×` 是官方 3.3 要求的「基线组合指令 / vdot latency 加速比」，分母是「3 条指令链」的整链（含 3 条指令的串行开销）；每指令归一口径 `5.333/4 = 1.33×` 是把整链 latency 摊到 3 条指令后的微架构比值。两者差异只来自分母是否按指令数归一，引用时必须写明是哪一个，不能互相替代。
2. **分母来自另一作业**：`L_base_chain=16` 来自作业 `126762127`，不是本轮 16 次运行
   测得的；本轮只重测分子 `L_vdot`。两作业的同一性前提是：同一 `VimacCfg`、同一
   VL=8、同一计数法（逐次 `rdcycle` 取差、去 16 次暖机、取中位数）、配置外提。
3. **模型周期，不是硅延迟**：`rdcycle` 是 emu 的模型周期；4 次重复的极差只说明本批
   进程间离散，**不是置信区间**，也不构成「硅片实测」。
4. **内部自设口径**：官方只要求「用已有向量指令组合实现」，未规定条数与统计口径；
   `L_base_chain` 的 3 条链与 `16/3` 归一是本包内部自设口径，不写成「官方规定的基线」。
5. **4 次 < ALGORITHM §3.4 的 ≥5 次**：`design/ALGORITHM.md:212` 的报告级口径要求
   「同配置再跑 ≥5 次取中位数」；本批是 4 次，属于补充证据，**不替代**该条。
6. **`--no-diff`**：所有 perf 用例都以 `--no-diff` 运行（emu 读 `rdcycle`，与 NEMU
   参照不一致）；功能正确性由各用例的 `PERF_* verdict` 自检承担，不是 difftest。
7. **不做的比较**：不与 §4.2 的 `B1/B2` 每点开销（6/9）相除或互替；不与 §4.9 的
   斜率（1.021/11.019 cyc/dot）相除或互替；不与 §4.5 的内核 16/7 并列成「两种加速比」。

---

## 1. 实验设计（预登记）

| 项 | 值 |
|---|---|
| 用例 | `perf_vdot.bin`（`L_vdot`/`T_steady`/`T_kernel`）、`perf_base.bin`（`B1`/`B2`）、`perf_vadd.bin`（`L_vadd`）、`perf_vmacc.bin`（`L_vmacc`） |
| 重复 | 4 次；每次对四个用例各起一个**独立 emu 进程**（不共享进程、不共享暖机） |
| 命令 | `$EMU --no-diff -i <case>.bin --max-instr=200000000` |
| 解析 | 与 `core-package/scripts/20-run-difftest.sh:311-327` 同一套：`^VDOT_METRIC <name> <value>` 取数值；`PERF <tag>` 汇总行原样留档 |
| 自检串 | 沿用 `20-run-difftest.sh:199-226`：`PERF_VDOT/PERF_BASE/PERF_VADD/PERF_VMACC verdict=ALL_OK` |
| 机读件 | JSON：每次重复的逐用例 metrics + 原始 `PERF` 行 + 跨重复中位数/极差 + 预登记加速比 |
| 脚本 | `core-package/scripts/99-run-perf-repeat.sh` |
| 机时 | `P3-full`；`-p kshcnormal -N 1 -n 8 --time=01:00:00` |

---

## 2. 实测

### 2.1 作业与环境（【实测】）

| 项 | 值 | 来源 |
|---|---|---|
| 作业号 | **`127196036`** | `sacct -j 127196036` |
| 分区 / 节点 | `kshcnormal` / `a08r3n00`（提交时 `CPUAlloc=0`、`CPULoad=0.05`、`State=IDLE`） | `scontrol show node a08r3n00`；日志首行 |
| 资源 | `-N 1 -n 8 --time=01:00:00`，另加 `--exclusive -w a08r3n00` | 提交命令见 §2.2 |
| sacct 终止状态 | **`COMPLETED`，`Elapsed=00:35:49`，`ExitCode=0:0`** | `sacct -j 127196036 --format=JobID,JobName,Elapsed,State,ExitCode` |
| emu | `$HOME/core/src/XiangShan/build/emu`，md5 `fd65ca4a…` | JSON `provenance.emu_md5` |
| 镜像 md5 | `perf_vdot 1d06ab25…`、`perf_base b5a4eeff…`、`perf_vadd 05f8c2b7…`、`perf_vmacc dd78ae5e…` | JSON `provenance.img_md5` |
| 远端版本 | xiangshan `a4eeaab` / yunsuan `9559211` | 日志 `versions:` 行 |

**运行环境披露（必须与数字同页）**：首次 smoke（作业 `127194031`，节点 `a01r4n09`）
在共享负载约 24–31 的节点上，`perf_vdot` 单例跑了 6 分 20 秒仍未完成，已取消；第二次
smoke（`127194792`，`a02r4n18`，`CPULoad≈31.5`）同样取消。正式作业改用**空闲节点
`a08r3n00`**（提交时 `CPULoad=0.05`）并加 `--exclusive`，`perf_vdot` 单例回落到
240–287 s。**因此本轮数字的有效范围是「独占空闲节点」**，不能当作共享节点下的
最坏情况；反过来，共享节点上的慢也不能归因于指令本身（与 `report.md:119` §4.3
诚实边界 ④ 的共享节点/VASP 观察同一类问题）。

### 2.2 复现命令（逐字可抄）

```sh
# 本地 → 远端（脚本已随包）
rsync -av --chmod=F755 core-package/scripts/99-run-perf-repeat.sh \
  kunshan:core/core-package/scripts/99-run-perf-repeat.sh

# 远端提交（本轮实际命令；--wait 使 sbatch 阻塞到作业结束）
ssh kunshan 'cd ~/core && sbatch --wait --exclusive -w a08r3n00 \
  -p kshcnormal -N 1 -n 8 --time=01:00:00 \
  --output=$HOME/core/results/difftest/perf-repeat/perf-repeat-4x-%j.out \
  core-package/scripts/99-run-perf-repeat.sh \
  --emu $HOME/core/src/XiangShan/build/emu \
  --cases $HOME/core/test/bin \
  --repeats 4 \
  --out $HOME/core/results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json'
```

> **连接披露**：`sbatch --wait` 客户端在作业运行中途因 SSH 服务器瞬时无响应退出
> （`Timeout, server cancon.hpccube.com not responding`），Slurm 作业本身继续运行；
> 最终状态由 `sacct` 独立核对（`COMPLETED 0:0`），不是靠客户端退出码推断。

### 2.3 逐重复原始值（【实测】）

4 次重复、每次四个独立 emu 进程；下表 16 行全部 `rc=0`、`HIT GOOD TRAP=1`、
`ABORT=0`、`HIT BAD TRAP=0`、各自 `PERF_* verdict=ALL_OK`。

| 重复 | L_vdot | L_vdot_mean | L_vdot_loop | T_steady | T_kernel | B1 | B2 | L_vadd | L_vmacc | 单例耗时（vdot/base/vadd/vmacc，s） |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 4 | 4 | 6 | 1 | 290 | 6 | 9 | 3 | 4 | 287 / 112 / 89 / 102 |
| 2 | 4 | 4 | 6 | 1 | 290 | 6 | 9 | 3 | 4 | 258 / 66 / 110 / 107 |
| 3 | 4 | 4 | 6 | 1 | 290 | 6 | 9 | 3 | 4 | 281 / 65 / 71 / 117 |
| 4 | 4 | 4 | 6 | 1 | 290 | 6 | 9 | 3 | 4 | 240 / 79 / 73 / 90 |

> **机械可核对**：4 条 `PERF L_vdot` 行逐字节相同：
> `PERF L_vdot : ops=1984 cycles=8378 mean=4 median=4 cycles_per_op=4 min=2 max=18446744073709551614 over=10 result=0xFFFFFF79 want=0xFFFFFF79 chain=OK`
> （JSON `runs[].raw_perf_lines` 中 `tag=L_vdot`；本文件 §2.7 解释 `max` 的 `2^64−2`
> 与 `over=10`）。**四个独立进程给出同一组模型周期**是 emu 确定性仿真的预期结果；
> 它证明的是「可重复」，**不是**「统计上无抖动」——见 §2.5 末条。

### 2.4 跨重复中位数与极差（【实测】）

| 用例 | 指标 | 4 次值 | 中位数 | 极差（max−min） |
|---|---|---|---|---|
| perf_vdot | **L_vdot** | 4, 4, 4, 4 | **4** | **0** |
| perf_vdot | L_vdot_mean | 4, 4, 4, 4 | 4 | 0 |
| perf_vdot | L_vdot_loop | 6, 6, 6, 6 | 6 | 0 |
| perf_vdot | **T_steady** | 1, 1, 1, 1 | **1** | **0** |
| perf_vdot | **T_kernel** | 290, 290, 290, 290 | **290** | **0** |
| perf_base | **B1** | 6, 6, 6, 6 | **6** | **0** |
| perf_base | **B2** | 9, 9, 9, 9 | **9** | **0** |
| perf_vadd | **L_vadd** | 3, 3, 3, 3 | **3** | **0** |
| perf_vadd | L_vadd_mean | 3, 3, 3, 3 | 3 | 0 |
| perf_vadd | L_vadd_loop | 5, 5, 5, 5 | 5 | 0 |
| perf_vmacc | **L_vmacc** | 4, 4, 4, 4 | **4** | **0** |
| perf_vmacc | L_vmacc_mean | 4, 4, 4, 4 | 4 | 0 |
| perf_vmacc | L_vmacc_loop | 6, 6, 6, 6 | 6 | 0 |

**与既有报告的交叉核对（【实测】本轮 vs【实读】`report.md` §1）**：本轮
`L_vadd=3`、`L_vmacc=4`、`L_vdot=4`、`T_steady=1`、`T_kernel=290`、`B1=6`、`B2=9`
与 `results/difftest/20-full-20261103T142246.json` 的 `metrics[]`（`report.md:19-24`
所引）逐值相同；本轮是 4 个新进程的复现，不是对旧 JSON 的转抄。

### 2.5 预登记加速比（【实测】+ 按 §0.2 计算）

```
speedup_per_instr = (L_base_chain / 3) / L_vdot
                  = (16 / 3) / 4
                  = 5.333333… / 4
                  = 1.333333…
```

| 表示 | 逐重复值 | 中位数 | 极差 | 结论 |
|---|---|---|---|---|
| 主口径：`(16/3)/4` | 1.333333, 1.333333, 1.333333, 1.333333 | **1.333333** | **0** | 写作 **1.33×**（每指令归一） |
| 整数打印口径：`5/4` | 1.25, 1.25, 1.25, 1.25 | **1.25** | **0** | 同一口径的整数舍入下界，写作 **1.25×** |

**分母与限定**（与 §0.2/§0.5 同一份，不另立）：

- 分母 `L_base_chain = 16 cyc/链步` 来自作业 `126762127`（full 尺度、`samples=16000`、
  `rounds=8`、中位数 16；`results/difftest/b3/91-b3-20261104T115624.log` 的
  `PERF L_base_chain` / `VDOT_METRIC L_base_chain 16`）；链为
  `vwmul.vv → vwadd.vx → vredsum.vs` 三条串行指令，配置外提、循环内零 `vsetvli`。
- 归一 `16/3 ≈ 5.333 cyc/指令`；本轮实测 `L_vdot=4`，故 `5.333/4 = 1.33×`（每指令归一）。
- **并列的整链口径**是 `16/4 = 4.0×`（官方 3.3 的「基线组合指令 / vdot latency 加速比」，分母含 3 条指令的串行开销）；两者差异只来自分母是否按指令数归一，不能混称。**不是** 内核 `16/7 ≈ 2.29×`（§0.3 已说明为何不作官方口径），**不是** §4.2 的 B1/B2 每点开销 6/9，**不是** §4.9 的斜率 1.021/11.019 cyc/dot。
- 4 次重复的极差为 0 只说明**本批 4 个 emu 进程的模型周期完全一致**；不是置信区间，
  也不改变 §0.5 第 3 条（rdcycle 是模型周期，不是硅延迟）。

### 2.6 判据逐条（【实测】，JSON `criteria[]`）

| # | 判据 | 预期 | 实测 | 状态 |
|---|---|---|---|---|
| 1 | `repeat_count` | `repeats >= 4` | `4` | 达标 |
| 2 | `runs_total` | `4 用例 × 4 重复 = 16` | `16` | 达标 |
| 3 | `emu_rc_zero` | 全部 `rc == 0` | `16/16` | 达标 |
| 4 | `good_trap` | 全部 `HIT GOOD TRAP >= 1` | `16/16` | 达标 |
| 5 | `no_abort` | 全部 `ABORT == 0` | `0` | 达标 |
| 6 | `no_bad_trap` | 全部 `HIT BAD TRAP == 0` | `0` | 达标 |
| 7 | `verdict_all_ok` | 每用例 4/4 命中各自 `ALL_OK` 汇总行 | `16/16` | 达标 |
| 8 | `metrics_complete` | 每重复每用例含预期 `VDOT_METRIC` | 缺 0 项 | 达标 |
| 9 | `l_vdot_matches_report` | `L_vdot` 跨重复中位数 == `report.md` §1 的 4 | `4` | 达标 |

**总状态：`通过`（9/9 达标）**（JSON `status`）。

### 2.7 诚实边界（本轮新增的三条）

1. **`max=18446744073709551614` 与 `over=10` 必须一起披露**：`perf_vdot` 的
   `PERF L_vdot` 行里 `max = 2^64−2`，是 `rdcycle` 读与内核体重排造成的无符号下溢
   （同一个最大值在 4 次重复中完全相同）；`over=10` 表示 10 个样本超出自检直方图
   上界 4096。**中位数 4 不受影响**（4 次重复的 `median=4` 与 `mean=4` 一致），但
   不能把该行的 `max` 当作「最坏延迟」引用。这与 `report.md:119` §4.3 诚实边界 ⑤
   对 `min=3` 离群的披露同类：只说明计数法存在低端/高端离群，不改变中位数结论。
2. **共享节点不可比**：§2.1 已给出两次被取消的共享节点 smoke（`127194031`、
   `127194792`）与正式空闲节点作业（`127196036`）的耗时差；本文件的 1.33× 只在
   「独占空闲节点 + `--no-diff` + 模型周期」这一组条件下成立。
3. **4 次 ≠ ALGORITHM §3.4 的 ≥5 次**：本轮是 4 次（按任务口径），
   `design/ALGORITHM.md:212` 的报告级口径要求 ≥5 次；本文件按 §0.5 第 5 条只作
   补充证据，不替代该条，也不把极差 0 写成「统计显著」。

### 2.8 证据路径

| 件 | 本地路径 | 远端路径 |
|---|---|---|
| 结果 JSON | `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json` | `~/core/results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json` |
| 作业日志 | `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.log` | 同名 |
| 中位数/极差 TSV | `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.summary.tsv` | 同名 |
| sbatch stdout | `results/difftest/perf-repeat/perf-repeat-4x-127196036.out` | 同名 |
| 16 份 emu 原始日志 | `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.cases/`（16 个 `.log.gz`，本地由原始 `.log` 压缩） | `~/core/results/difftest/perf-repeat/99-perf-repeat-4x-20261108.cases/`（`.log` 原件） |
| 脚本 | `core-package/scripts/99-run-perf-repeat.sh` | `~/core/core-package/scripts/99-run-perf-repeat.sh`（同一 sha256） |

> 本地 JSON 复核命令与输出见 §2.9；本地与远端同名文件为同一次 `rsync` 传输。

### 2.9 本地复核命令（可复跑）

```sh
python3 - <<'PY'
import json, statistics
d = json.load(open('results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json'))
print(d['status'])
print([(c['name'], c['status']) for c in d['criteria']])
vals = [r['metrics']['L_vdot'] for r in d['runs'] if r['case'] == 'perf_vdot']
print(vals, statistics.median(vals), max(vals) - min(vals))
print((16/3) / statistics.median(vals))
PY
```

**【实测】本次输出**：

```
通过
[('repeat_count', '达标'), ('runs_total', '达标'), ('emu_rc_zero', '达标'),
 ('good_trap', '达标'), ('no_abort', '达标'), ('no_bad_trap', '达标'),
 ('verdict_all_ok', '达标'), ('metrics_complete', '达标'),
 ('l_vdot_matches_report', '达标')]
[4, 4, 4, 4] 4.0 0
1.3333333333333333
```