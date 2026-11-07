# 3.3 补充小节：功能覆盖率与结构覆盖率（vdot.vv）

> **位置**：本文件是 `stage3/3.3/report.md` **§4.11** 的正文来源（编号见 `report.md:154`），按 §4.6 的编号约定原文并入。
> **标注约定**：【实测】=本次命令输出或存量日志串逐字读到；【静态】=二进制/源码扫描；【推算】=由实测做的算术外推，非实测；【未运行】=本次未执行。
> **口径约定**：本节不出现任何加速比；`6 / 9` 不出现；面积/功耗不出现。全文只出现一种比值：**覆盖率**（命中格 ÷ 总格），与性能无关。
> **修订记录（2026-11-06）**：15:42 版曾并入 `report.md` §4.11；15:53 之后新增的 3 条证据行（30 行冻结清单回传、昆山登录节点干跑、昆山预算闸实跑）已随本次更新进入 §4.11。本文件后续修改时，`report.md` §4.11 同步更新。
> **来源声明（2026-11-07）**：本文件是 `report.md` §4.11 的源文件；§4.11 的正文与校验值按本文件更新，两者不一致时以本文件为准（编号见 `report.md:154`）。
> **修订记录（2026-11-07 实跑）**：§A.2 与 §D 由「预算闸未放行（未运行）」改为**实跑受阻**的实测记录（覆盖 emu 建成、`--diff` 退出段 SIGSEGV rc=139、gdb 栈、line-only 修复作业 `127128086` 结果待收）；本次**仍不含任何覆盖率数字**。§4.11 并入时须整段更新。
> **数据源**：`stage3/3.1.2-difftest/full-logs-20261103T142246/`（30 份逐用例日志，作业 `126676734`，30/30 通过）+ 30 个 `.bin` 的编码扫描；结构覆盖实跑诊断在 `stage3/3.1.2-difftest/coverage/evidence/cov-debug-20261107/`；机读件在 `stage3/3.1.2-difftest/coverage/`。

---

## A. 4.11.1 结论（三句话）

1. **功能覆盖已量化**：29 个 coverpoint × 30 例 = **870 格**，其中 `covered 11 / thin 15 / partial 2 / gap 1`；把 thin/partial 折算成「至少命中一次」则是 **28/29 项有命中**，仅 **F15 `vs1==vs2`** 仍为零命中（【实测】`summary.tsv`，生成命令见 `matrix.md` §0；30 例内为零，extra 的 `xo_v12_*` 10 例已通过，见 §C）。
2. **结构覆盖（RTL line/toggle）本次【未运行（实跑受阻）】**：2026-11-07 已在昆山实跑（用户授权突破自设 11.0 机时预算）：覆盖率 emu **重建成功**（`EMU_COVERAGE=1`，作业 `127117867`，构建 04:34→06:24 = 110 min，emu `sha256 b86f95b4…`、424 MB），但**覆盖构建的 emu 在 `--diff` 用例的退出段 SIGSEGV（rc=139）、`.coverage.dat` 为 0 字节**，30 例只跑完第 1 例即中止。定位（【实测】，`coverage/evidence/cov-debug-20261107/`）：`--no-diff -C 100 --dump-coverage` 可正常退出且 dat 达 **3.3 GB（100 条指令）**；`--diff` 全跑即使不 dump 也在退出段 rc=139；gdb 栈 `VerilatedCovImp::write → std::map::operator[] → _Rb_tree_insert_and_rebalance`（`Emulator::save_coverage ← ~Emulator ← main`）。**本次不写任何覆盖率数字**；修复方向 = 去掉 `--coverage-toggle` 的 line-only 重建（冒烟作业 `127128086`，**结果待收**），命令见 `matrix.md` §6.3。
3. **对外表述**：官方 12 项交付物里**没有「代码覆盖率」这一项**（`docx/02:45-66` 逐条核对）；本节的作用是给 **可行性 10 分格的「功能验证有效性」**（`docx/02:92`）与 3.1.2 协同仿真补**量化证据**，不声称完成一项官方覆盖率交付物。

---

## B. 4.11.2 功能覆盖：29 coverpoint × 30 例

### B.1 状态口径（固定，全文同一定义）

| 状态 | 定义 | 本次计数 |
|---|---|---|
| `covered` | **≥2 例**有独立证据（运行日志串 或 二进制/源码静态事实） | **11** |
| `thin` | 仅 **1 例**命中（命中但回归脆弱） | **15** |
| `partial` | 只在部分 bin 上命中，或只有 `--no-diff` 自检（缺 difftest 比对） | **2**（F14、F28） |
| `gap` | **0 例**命中 | **1**（F15） |

> 采样域：`legal` 只采 `trap==0` 的 vdot（对应 ACT4 `iff (ins.trap == 0)`）；`trap` 只采非法陷入。**负例不向 legal 域贡献**。**例外（仅 F28 一项）：F28 是 bin 级寄存器索引空间，按「真实发射过的编码」统计，含负例编码；其合法子域在 §B.4 单列**（不把负例算进 legal 子域）。四例不发射 vdot（`vadd-microbench`/`perf_base`/`perf_vadd`/`perf_vmacc`，二进制扫描 0 个 vdot 编码）在所有 CP 上记 `na`，**不充当命中格**。

### B.2 11 个 `covered` 与 1 个 `gap`（摘要；全表见 `matrix.md` §2）

| CP | coverpoint | 状态 | 命中 | 一手证据（【实测】日志串 /【静态】编码） |
|---|---|---|---|---|
| F01 | `vstart_zero` | covered | 18 例 | 18 例合法执行（GOOD TRAP ∧ ABORT=0），源码无 `csrw 0x008` |
| F04 | `vl_not_max` | covered | 16 例 | `li t1,8` 主体 + `MATRIX vlinvar vl=1..8 … OK` |
| F06 | `vtype_prev_vill_clear` | covered | 18 例 | 未写非法 vtype |
| F11 | `vm_unmasked` | covered | 18 例 | 编码全 `vm=1`（30 个 `.bin` 扫描） |
| F16 | `vtype_sew_8` | covered | 17 例 | `vsetvli … e8` + 合法执行 |
| F18 | `vtype_lmul_1` | covered | 17 例 | `vsetvli … m1` |
| F19 | `lmul_ne_1_trap` | covered | 3 例 | `vdot_ill_lmul{2,4,8}` 各 `HIT CRITICAL ERROR`=1 |
| F21 | `vs1_vs2_edges` | covered | 7 例 | 操作数含 `-128`/`127`/`0` 或 `|S|>32767`（`bound1` S=131072、`bound2` S=−130048、`bound4` S=129032） |
| F23 | `hi96_zero` | covered | 16 例 | 运行行 `hi_nonzero=000` / `hi=[0x00000000 0x00000000 0x00000000]` |
| F26 | `back_to_back_raw` | covered | 3 例 | `MATRIX back_to_back … OK`、`MIX verdict=ALL_OK`、`chain=OK` |
| F29 | `sign_mix` | covered | 13 例 | 操作数正负混合（pos2/neg_odd*/bound2/bound3/bound5/rand/matrix/mix） |
| **F15** | **`vs2_eq_vs1`** | **gap** | **0 例** | **30 例全部是 `vs1=v1`、`vs2∈{2,10}`；无一条 `vs1==vs2` 编码** |

### B.3 15 个 `thin`（单例依赖，回归脆弱）

`F02`(vdot_ill_vstart) `F03`(vdot_rand，`li t1,16`=VLMAX) `F05`(vdot_matrix vl=0) `F07`(vdot_ill_vill) `F08`/`F09`/`F10`(vdot_matrix vta×vma 4/4) `F12`(vdot_ill_vm0) `F13`(vdot_matrix `overlap_vd_eq_vs1`) `F17`(vdot_ill_sew) `F20`(vdot_ill_vs) `F22`(vdot_rand 1024 组) `F24`(matrix `oldvd_prefill`) `F25`(matrix `vxsat before=0x0 after=0x0`) `F27`(vdot_rand 16 字节随机)。

> **风险直说**：`F05/F08/F09/F10/F13/F24/F25` **只由 `vdot_matrix` 一例支撑**，`F03/F22/F27` **只由 `vdot_rand` 一例支撑**。这两例都**不在** `--smoke` 白名单里（`20-run-difftest.sh` 的 `class_selected()`），因此**不能用 smoke 产物出覆盖率报告**；覆盖率跑必须全选 30 例。

### B.4 寄存器索引空间（F28 = partial）

| 操作数 | 命中 bin | 未命中 | 命中率 |
|---|---|---|---|
| `vd` | 16/32（v0, v1, v3–v16） | v2, v17–v31 | 50% |
| `vs1` | 5/32（v0, v1, v2, v4, v8） | 其余 27 个 | 16% |
| `vs2` | 3/32（v0, v2, v10） | 其余 29 个 | 9% |

> `vs1`/`vs2` 的 v0/v4/v8 来自**非法编码**（`vdot_ill_sew` 的 `vd=vs1=vs2=v0`、`vdot_ill_lmul*` 的组基址）；**合法域**的 `vs1` 实际只有 `v1`，`vs2` 只有 `{2,10}`。这就是 F28 记 `partial` 而不是 `covered` 的原因。

### B.5 与对手调研稿（§4.1）的差异

| 差异 | 调研稿 | 本文 | 原因 |
|---|---|---|---|
| 状态计数 | covered 20 / thin 7 / partial 1 / gap 1 | **covered 11 / thin 15 / partial 2 / gap 1** | 调研稿按「≥2 例**或** ≥1024 样本」判 covered，且把 4 个不发射 vdot 的例算进合法域；本文按「≥2 例**独立命中**」且这 4 例判 `na`。**更严，不更松** |
| F14 `vd==vs2` | covered | **partial** | 调研稿把 `perf_vdot` 的 `--no-diff` 自检算 covered；本文要求 difftest 比对 |
| F28 寄存器空间 | vd 14/32、vs1 1/32、vs2 2/32 | vd 16/32、vs1 5/32、vs2 3/32 | 本文把 8 个负例的真实编码也计入索引空间 |

---

## C. 4.11.3 扩容套件 `manifest.extra.tsv` 的补强（129 例）

主清单（30 行、`sha256 a90d1071…`）是官方回归口径的冻结件，**一行未动**；扩容用例全部落在 `design/verify/cases/manifest.extra.tsv`（129 数据行：`vdot-base` 7 / `vdot-ov` 30 / `vdot-pl` 48 / `negative` 41 / `g0` 2 / `vdot-rand10k` 1）。

**对 30 例缺口的三条直接补强（【静态】`extra-static-scan.tsv`，129/129 文件扫到 vdot 编码）**：

| 30 例缺口 | extra 补强 | 编码事实 |
|---|---|---|
| F15 `vs1==vs2` **gap** | `xo_v12_*` **10 例** | 10 个 `.bin` 含 `vs1==vs2` 编码 |
| F13 `vd==vs1` thin | `xo_vs1_*` 10 + 交叉 5 = **15 例** | 15 个 `.bin` 含 `vd==vs1` |
| F14 `vd==vs2` partial | `xo_vs2_*` **10 例**（走 `--diff`） | 10 个 `.bin` 含 `vd==vs2` |

> **已实跑覆盖（终态，2026-11-06）**：`94-extra-20261106T143635`（作业 `127031933`）`status=通过`、`cases_pass=129/129`、8/8 criteria `达标`（含 `golden_crosscheck=达标 :: EXTRA_CROSSCHECK verdict=MATCH`）；`xo_v12_*` 10 例在 `.cases.tsv` 第 3 列全部为「通过」。**因此这三条补强已从「仅编码事实」升级为「编码 + 实跑」双重证据**；但 extra 仍不进 30 例主清单、不参与 `regression_delta`，F15 在 30 例矩阵内仍记 gap（§A.1）。

---

## D. 4.11.4 结构覆盖（RTL line/toggle）：实跑受阻，数字【未运行】

### D.1 实跑发生了什么（2026-11-07，用户授权突破自设 11.0 机时预算）

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

### D.2 流水线状态（本次实测更新）

| 项 | 状态 | 证据 |
|---|---|---|
| `core-package/scripts/95-coverage.sh` | **实跑适配后 `bash -n` 退出 0**；本次新增三处最小适配：`NOOP_HOME` export（T9）、预算闸授权越过记「已越过」、`--skip-build` 记「已复用」 | 本地 `sha256 7a1f98b6…`；昆山部署件 `sha256 e243b7be…`（部署后仅 `--skip-build` 一处再改，台账见本节「预算闸」行） |
| 上游 9 个问题点（T1–T9） | 逐条在脚本里处置（T9=本次新增：`make -C difftest emu-mk` 必须 export `NOOP_HOME`） | 头注 T1–T9；作业 `127113117` 实测 rc=2 |
| 预算闸 | 脚本内置；本次按用户授权用 `--no-budget-guard` 越过，判据记「已越过」、JSON `budget_guard_bypassed=true` | 远端台账；超支事实由 `90-budget-log.sh auto` 入账（2026-11-07 08:54:48 summary：`P3-full 14.808/3.0`、合计 **18.804/10.6**、EXIT=1） |
| 昆山路径 | 10/10 `test -e` 命中（含 `build/rtl/SimTop.sv`） | `evidence/95-remote-pathcheck-20261107.txt` |
| 30 行冻结清单 | `~/core/test/manifest.30.tsv`，`sha256 e12470e6…`，30 数据行 | `evidence/95-remote-manifest30.txt` |
| 结构覆盖解析器 | 合成 fixture 6/6 通过；**元组口径已更正**为 `(covered, NOT_covered, pct)`，新增 `line_total` 列 | `evidence/vdot-structural-fixture-selftest.tsv` + `evidence/README-fixture-selftest.txt`；`parse_stats.py` 出五段长表 |

### D.3 拿到可用 `.dat` 后的收集命令（可直接复制）

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

## E. 4.11.5 缺口与补测建议（可执行清单）

| # | 缺口 | 现状 | 补测建议 | 成本 |
|---|---|---|---|---|
| G1 | **F15 `vs1==vs2`** | 30 例 0 命中；extra `xo_v12_*` 10 例已随整套 129/129 通过（`127031933`） | 若要把 F15 从 gap 升为 covered，需在 30 例主清单内加例（extra 不进官方清单）；否则报告按 gap 披露 | 0.2 机时 |
| G2 | **F28 寄存器空间** | vd 16/32、vs1 5/32、vs2 3/32 | 加 1 条 `vd/vs1/vs2 ∈ {0,1,15,16,31}` 扫描例（避开无意重叠 bin） | 0.1 机时 |
| G3 | **F14 只有 `--no-diff`**（30 例内） | extra `xo_vs2_*` 10 例走 difftest 且已随 129/129 通过；30 例内仍只有 `--no-diff` 样本 | 在 30 例主清单内补 1 例 difftest 路径，或报告按 partial 披露 | 0.1 机时 |
| G4 | **F03 `vl_max`** | 30 例由 `vdot_rand` 的 `li t1,16` 命中；extra 的 `xb_vl_sweep` 只到 vl=8 | 在 `xb_vl_sweep` 加 `vl=16` 一档 | 0.1 机时 |
| G5 | **F25 `vxsat`** | 仅 `vdot_matrix` 1 例 | extra 加「先 `csrw vxsat,1` 再 vdot 再读回」 | 0.1 机时 |
| G6 | **7 个 CP 单点依赖 `vdot_matrix`、3 个依赖 `vdot_rand`** | 回归漏跑即回落为 gap | 覆盖率跑必须全选 30 例（脚本已如此） | 0 |
| G7 | **F23 `perf_vdot` 未断言高 96 位** | 16/18 合法例命中 | 若要 17/18，在 `perf_vdot` 链后加 `vse32.v` + 断言 | 0.1 机时 |
| G8 | **结构覆盖** | 【未运行（实跑受阻）】：覆盖 emu 已建，但 `--diff` 退出段 SIGSEGV（rc=139）、dat 0 字节 | line-only 重建后重跑（§D.1 末段 + §D.3） | 本次已耗 3.3 机时；重跑预计 2–3 机时 |
| G9 | ACT4 `cr_vtype_agnostic` / `mask_enabled` / `cp_masking_edges` | **结构性不可达**（vdot 合法编码强制 `vm=1`） | 报告写 N/A；用 F10/F11/F12 替代，**不伪造 ACT4 cross 命中** | 0 |
| G10 | ACT4 无 `vstart≠0`/`vill=1`/`VS=OFF` 的 trap bin | 用自定义 F02/F07/F20 覆盖 | 报告注明「ACT4 模板扩展」 | 0 |
| G11 | 分数 LMUL（mf8/mf4/mf2） | extra `xn_lmul_mf8/mf4/mf2` 已随整套 129/129 通过（`127031933`） | 无（已闭合） | 0 |

---

## F. 4.11.6 评分对应与诚实边界

| 评分格 | 本节提供的证据 | 边界（不得越界表述） |
|---|---|---|
| 可行性 10 分格「功能验证有效性：测试用例是否覆盖正数、负数、边界值，协同仿真是否通过」（`docx/02:92`） | 29 CP × 30 例 = 870 格矩阵；`covered 11 / thin 15 / partial 2 / gap 1`；正/负/边界/溢出四类各有定向例（F29/F21）；30/30 用例通过（`126676734`；**其中 `perf_vdot`/`perf_base`/`perf_vadd`/`perf_vmacc` 4 例按 `manifest.tsv:27-30` 第 4 列以 `--no-diff` 运行，属自检/性能口径，不计 difftest 逐位比对**）；extra 129/129 通过（`127031933`，含 `golden_crosscheck=达标`） | **不写「覆盖率 100%」**；gap 与 thin 逐条列出；结构覆盖【未运行（实跑受阻，§D.1）】；extra 不进 30 例官方清单 |
| 3.1.2 协同仿真验证 | 覆盖率跑复用与 20-run **同一套自检串语义**（`95-coverage.sh` 的 `selfcheck_pattern()`），不另立宽松判据 | 覆盖率跑**未产出结果**（覆盖构建 + `--diff` 退出段 rc=139，§D.1），30/30 的结论仍只来自 `142246` |
| 官方 12 项交付物 | **无「代码覆盖率」项**（`docx/02:45-66`） | 不声称完成一项官方覆盖率交付物 |

**四条诚实边界（必须与本节数字同页出现）**：

1. **结构覆盖是【未运行（实跑受阻）】，不是「低覆盖率」**：2026-11-07 实跑已建出覆盖 emu，但 `--diff` 用例退出段 SIGSEGV（rc=139）、`.coverage.dat` 0 字节（gdb 栈见 §D.1）；**没有数字，就不能说「RTL 覆盖率高/低」**。
2. **thin ≠ covered**：15 项只有 1 例支撑，回归漏跑即失效；本节不把它们合并成「28/29 覆盖」对外宣称（28/29 只是「至少命中一次」的折算，已在 §A.1 注明）。
3. **extra 已到实跑终态（129/129），但仍是清单外证据**：作业 `127031933` `status=通过`、`pass=129`、`golden_crosscheck=达标`；`xo_v12_*` 10/10 通过。该结果**不进** 30 例官方回归清单，也**不参与** `regression_delta`，因此不得把 extra 的通过数并入「30/30」或「29 CP × 30 例」矩阵。
4. **条件行覆盖 ≠ 语句覆盖**（放行后写结构覆盖数字时同样适用）。
