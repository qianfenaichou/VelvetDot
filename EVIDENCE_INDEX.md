# 证据索引

一行一条证据。列含义：

- **证据文件**：仓库内相对路径，全部在本次核对中做过存在性检查（`test -e`），路径按原文抄写。
- **它证明什么**：该文件里能被读到的内容，不写文件里没有的东西。
- **生成方式**：用什么脚本、哪个 Slurm 作业、什么工具产生。作业号取自 JSON 的 `slurm_job_id` 字段或文件头。
- **对应结论**：回到 `VALIDATION.md` 的编号（V01–V25）。

数字口径统一取自 `out/submission/facts-ledger.md`。凡是「未采集」「未做」的条目，本索引照录，不替换成 0。

---

## 1. 语义、位宽与编码

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `design/SPEC.md` | 语义式、19 位内部位宽、写回零高 96 位、六条合法条件、`vl` 任意值全写、编码三元组与 `0x3A20A1D7` 位域展开 | 人工设计文档；编码复核在 2026-10-31 对 riscv-opcodes `f24ac23` 做过 | V01 V02 V03 V04 |
| `design/verify/vdot_model.py` | 金模型常数与写回掩码（19 位累加、32 位输出、高 96 位清零），与 SPEC 一致 | 手写 Python 参考模型 | V01 V02 |
| `design/verify/vdot_model_test.py` | 金模型自检 1142 例通过 | 本轮 `python3 -I design/verify/vdot_model_test.py` → `ALL TESTS PASSED (1142 cases)`，EXIT=0 | V01 V02 |
| `design/verify/encoding-gate.py` | 冻结三元组与工作区/上游快照的全空间重叠判定；阳性对照 P1–P4；不带快照时退出码 4 表示官方归属维度未覆盖 | 手写离线校验脚本，输入为工作区源码与本地 riscv-opcodes 快照 | V04 V05 |
| `design/_recon/vendor/riscv-opcodes-f24ac23/encoding.h` | 上游编码快照，用于判定官方归属 | `riscv-opcodes` @ `f24ac23` 的本地副本 | V04 V05 |
| `design/verify/cases/cases.json` | vdot 用例规格（21 条 `cases[]`）：机器码常量 `0x3a20a1d7`，期望值由算法 B 的 int64 累加算出 | 手写用例规格 | V04 |
| `design/verify/cases/extra/spec.extra.json` | 224 例扩容规格：`rows`、`counts`、`quota`、逐例定义 | 生成器 `design/verify/cases/gen_extra.py` 产出 | V03 V08 |
| `design/verify/cases/extra_crosscheck.py` | 224 例期望常量与金模型逐条一致（`problems=0`、`verdict=MATCH`） | 本轮 `python3 -I design/verify/cases/extra_crosscheck.py --quiet`，EXIT=0 | V08 |
| `design/verify/cases/cover.extra.tsv` | 逐例覆盖到的 SPEC 条款与不变量（含 `xb_vl_sweep` 的 `vl=0..8` 全扫说明） | 用例编写时登记 | V03 |

## 2. 功能：主回归 30 例

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/difftest/20-full-20261107T104227.json` | 30/30 通过、9/9 判据达标、`regression_delta=0`、清单 sha256 `e12470e6…`、counters（`selfcheck 21/21`、`g0 1/1`、`reg_size_bad=0`） | `core-package/scripts/20-run-difftest.sh --full` 经 sbatch 提交（日志头记 `slurm_script mode=full`），作业 127137638，2026-11-07 10:42:27–11:12:17 | V06 |
| `results/difftest/20-full-20261107T104227.cases.tsv` | 30 例逐例状态、`good_trap=1`、`abort=0`、`bad_trap=0` 与各自日志路径 | 同上作业 | V06 |
| `results/difftest/20-full-20261107T104227.log` | 30 条 `case … -> 通过` 行，逐例带 GOOD/ABORT/BAD/rc | 同上作业的 stdout | V06 |
| `results/difftest/20-full-20261103T142246.json` | 同清单第二次 30/30、9/9 判据，manifest sha256 与 11-07 轮相同 | 同上脚本，作业 126676734，2026-11-03 14:22:46–14:51:47 | V07 |
| `results/difftest/20-full-20261103T142246.log` | 11-03 轮 30 例逐例通过记录 | 同上作业 | V07 |
| `stage3/3.1.2-difftest/manifest.tsv` | 冻结主清单：30 数据行、`@IMG_DIR@` 占位写法、sha256 `a90d1071…` | `design/verify/cases/make_manifest.sh` 或手工冻结 | V06 V10 |
| `results/coverage/20261108T103732/manifest.30.tsv` | 绝对路径写法的同一份 30 行清单，sha256 `e12470e6…` | 覆盖作业从远端 `test/manifest.30.tsv` 复制 | V06 V10 |
| `stage3/3.1.2-difftest/evidence/criteria-check.txt` | 对历次 JSON 的判据机检：`cases[].abort` 全 0、`regression_delta=='0'`、`reg_size_match` 达标 | 打包轮脚本读 JSON，不重跑仿真 | V06 V07 |
| `stage3/3.1.2-difftest/full-logs-20261103T142246/vdot_g0_badexp.20261103T142246.log` | G0 反例 `result=0x24 expect=0x25(MUTATED)` 后 `CASE … MISMATCH` | 11-03 轮 difftest 用例日志本地副本 | V09 |
| `stage3/3.1.2-difftest/full-logs-20261103T142246/vdot_pos1.20261103T142246.log` | 正例 `MATCH` 对照，说明同一判据对正负例给出不同结论 | 同上 | V09 |
| `results/difftest/cases/vdot_g0_badexp.20261105T112035.log` | 11-05 轮 G0 仍为 `MISMATCH`，`hi` 三字为 0 | 20-run 作业的逐例日志 | V09 |
| `results/difftest/baseline.tsv` | 30 例的基线逐例通过状态表 | 早期轮次汇总 | V06 |

## 3. 功能：扩容 224 例

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/difftest/extra/94-extra-20261108T014445.json` | `selected=executed=pass=224`、`not_run=0`、8/8 判据、`selfcheck 162/162`、`g0 2/2`、`neg 57/57`、`golden_crosscheck=MATCH` | `core-package/scripts/94-run-extra.sh`，作业 127194011，2026-11-08 01:44:45–03:24:34 | V08 V09 |
| `results/difftest/extra/94-extra-20261108T014445.cases.tsv` | 224 例逐例状态与日志路径 | 同上作业 | V08 |
| `results/difftest/extra/94-extra-20261108T014445.log` | 作业头记 `emu_md5`、`ref_so` md5、manifest sha256 `ad787baa…`、`selected=224` | 同上作业的 stdout | V08 |
| `design/verify/cases/manifest.extra.tsv` | 224 数据行扩容清单与其类别列 | 生成器 + `make_manifest.sh` 展开镜像路径 | V08 V10 |
| `design/verify/cases/extra/xb_vl_sweep.c` | `vl` 全扫用例的源（期望值由金模型算出） | 生成器 `gen_extra.py` 产出 | V03 |
| `design/verify/cases/extra/xb_oldvd.c` | 旧 `vd` 预填不干扰结果的定向用例源 | 同上 | V01 |
| `design/verify/cases/extra/xb_vta_vma.c` | `vta`/`vma` 四组合结果不变的定向用例源 | 同上 | V01 |
| `results/difftest/extra/94-extra-20261106T143635.json` | 2026-11-06 的旧规模扩容为 129 例（作业 127031933），说明 129 不是现行规模 | `94-run-extra.sh` 早期轮次 | V10 |

## 4. 性能

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json` | 4 用例 × 4 重复的跨重复中位数、极差；预登记加速比口径 `(16/3)/4`；`not_used` 段记 `2.285714` 不作 latency 加速比 | `core-package/scripts/99-run-perf-repeat.sh`，作业 127196036，2026-11-08 | V11 V12 |
| `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.summary.tsv` | 逐条指标：`L_vdot` 4,4,4,4；`T_steady` 1,1,1,1；kernel 290,290,290,290；`L_vadd` 3；`L_vmacc` 4；B1 6、B2 9 | 同上作业的后处理统计 | V11 |
| `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.log` | 16 次运行的汇总行与判据 | 同上作业的 stdout | V11 |
| `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.cases/perf_vdot.r1.20261108T020356.log.gz` | 单次 emu 的原始行：`enc_check=0x3A20A1D7 … OK`、`L_vdot ops=1984 median=4`、`T_steady ops=4000 cycles=4234` | 同上作业的逐例日志 | V04 V11 |
| `results/difftest/b3/91-b3-20261104T115624.log` | `L_base_chain: rounds=8 samples=16000 median=16 mean=16 min=3 max=18 over=0` | `core-package/scripts/91-run-b3.sh`，作业 126762127 | V12 |
| `results/difftest/b3/91-b3-20261104T115624.summary.json` | 同一条基线的机读摘要（JSON 自述由日志抽取，不是作业原生产物） | 由上述日志逐行抽取生成 | V12 |
| `results/difftest/b3/provenance/91-b3-provenance.txt` | `sacct` 记录：126749121 FAILED、126758062 CANCELLED、126762127 成功，附原始命令输出 | 返修轮 ssh 实跑记录 | V12 |
| `design/verify/perf/perf_vdot.c` | 度量口径常数：`N_RAW=2000`、`N_WARMUP=16`、`VL=8` | 手写用例源 | V11 |

## 5. 面积

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/yosys/vdot-k1.stat.json` | K1 `VdotReduce` `num_cells=481`、`$_DFFE_PP_=19` | `core-package/scripts/40-yosys-area.sh`（Yosys 0.48 `synth` + `stat -json`），作业 127135437 | V13 |
| `results/yosys/vdot-p2.stat.json` | P2 `VdotReduce` `num_cells=500`、`$_DFFE_PP_=38` | 同上脚本，作业 127137643 | V13 |
| `results/yosys/vmac_only.stat.json` | `VIMac64b` `num_cells=42783` | 同上脚本的对照网表 | V13 |
| `results/yosys/vdot-k1.stat.cmos.txt` | `Estimated number of transistors: 4900+`（粗估，带加号） | Yosys `stat -tech cmos` | V13 |
| `results/yosys/vdot-p2.stat.cmos.txt` | 同为 `4900+`，故不能据此算两版晶体管差值 | 同上 | V13 |
| `results/yosys/vdot-k1.ltp.txt` | `Longest topological path in VdotReduce (length=22)` | Yosys `ltp -noff` | V13 |
| `results/yosys/vdot-p2.ltp.txt` | `length=14` | 同上 | V13 |
| `results/yosys/40-area-20261107T095404.json` | `metrics`：VIMac64b 42783 cells / 293640 transistors / LTP 100；VdotReduce 481 / 4900 / 22 | 作业 127135437 的汇总 JSON | V13 |
| `results/yosys/40-area-20261107T104238.json` | `metrics`：VIMac64b 同上；VdotReduce 500 / 4900 / 14 | 作业 127137643 的汇总 JSON | V13 |
| `results/yosys/40-area-20261107T095404.log` | 逐网表解析行：`cells=42783 …`、`cells=481 …` | 作业 127135437 的 stdout | V13 |

## 6. 时序（STA）

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/sta/20261108/worst_slack_20261108.tsv` | 逐行：K1/P2 `VdotReduce` @333/500 ps 的 worst slack、path delay、起止点；VIMac64b 两行同为 −11857.3 / −11690.3 ps | OpenSTA 3.2.0 在 Yosys 映射后、预布局网表上跑 `report_checks`；文件 mtime 09:38 对应构建轮的 `sta` 作业 127234054（`results/sta/20261108/toolchain_20261108.log:181`） | V14 V15 |
| `results/sta/20261108/worst_slack_closure_20261108.tsv` | 周期闭合扫描：P2 700/750/800 ps、K1 1100/1200/1300 ps 的 slack | `sta_closure` 作业 127260543（`out/audit/sta-closure-power.md:14`），与上一行不是同一作业 | V16 |
| `results/sta/20261108/reports/K1_VdotReduce_0.333ns_20261108.rpt` | 最差路径逐级延迟与 `-0.7918 slack (VIOLATED)`；`-0.040532 library setup time` 证明 required time 已扣 setup | OpenSTA 原始报告 | V14 |
| `results/sta/20261108/reports/P2_VdotReduce_0.333ns_20261108.rpt` | `-0.3758 slack (VIOLATED)`、path delay 0.6588 ns | OpenSTA 原始报告 | V14 |
| `results/sta/20261108/reports/K1_VIMac64b_0.333ns_20261108.rpt` | 最差路径 `-11.8573 slack (VIOLATED)`；文件里另有一条异步复位路径的 slack 为正值，不在最差路径之列 | OpenSTA 原始报告 | V14 |
| `results/sta/20261108/reports_closure/P2_VdotReduce_0.700ns_20261108.rpt` | `-0.008839 slack (VIOLATED)` | OpenSTA 原始报告 | V16 |
| `results/sta/20261108/reports_closure/P2_VdotReduce_0.750ns_20261108.rpt` | `0.041161 slack (MET)` | OpenSTA 原始报告 | V16 |
| `results/sta/20261108/reports_closure/K1_VdotReduce_1.200ns_20261108.rpt` | `0.075164 slack (MET)` | OpenSTA 原始报告 | V16 |
| `results/sta/20261108/toolchain_20261108.log` | OpenSTA 3.2.0 的构建过程与工具版本 | 2026-11-08 现场编译记录 | V14 |
| `out/audit/sta-closure-power.md` | 代理工艺、预布局、无 CTS/SPEF、闭环定义、TSV 为原始行搬运、未做项清单 | 人工审计文档，汇总 OpenSTA 输出 | V14 V15 V16 V24 |

## 7. 功耗

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/sta/20261108/power_summary_20261108.tsv` | 逐行：K1/P2/VIMac64b 的 leakage-only 与 1 GHz 合成活动率两档 internal/switching/leakage/total | OpenSTA 3.2.0 `report_power -digits 6`，作业 127260994 | V23 |
| `results/sta/20261108/reports_power/K1_VdotReduce_leak_20261108.log` | `Total … 1.778420e-05`（leakage-only，无时钟） | OpenSTA 原始报告 | V23 |
| `results/sta/20261108/reports_power/K1_VdotReduce_synthetic_20261108.log` | `Total 5.527636e-04 3.343002e-04 1.778420e-05 9.048480e-04` | OpenSTA 原始报告 | V23 |
| `results/sta/20261108/reports_power/VIMac64b_synthetic_20261108.log` | `Total 2.320141e-02 1.204664e-02 7.461944e-04 3.599424e-02` | OpenSTA 原始报告 | V23 |
| `results/sta/20261108/reports_power/P2_VdotReduce_leak_20261108.log` | `Total … 1.974276e-05` | OpenSTA 原始报告 | V23 |

## 8. 结构覆盖

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/coverage/20261108T103732/merged30all.coverage/verilator_coverage-summary.txt` | `line 67.5% (113628/168283)`；toggle/branch/expr/fsm_state/fsm_arc 均为 `0.0% (0/0)`；Annotation `72.7% (603019/829473)` | `core-package/scripts/95-coverage.sh` 采集 + 后处理 30 个 `.dat` 合并（Verilator 5.053），合并作业 127252294 | V19 V20 |
| `results/coverage/20261108T103732/merged30all.coverage/coverage_SimTop.log` | `- VdotReduce tree_line(1, 0, 100.00)`、`- VIMacU tree_line(3, 0, 100.00)`、`- VIMac64b tree_line(3, 0, 100.00)` | 同上合并 → `coverage.py`/`statistics.py` | V19 |
| `results/coverage/20261108T103732/merged30all.coverage/dats.list` | 30 个 `.dat` 的路径清单 | 合并作业的输入清单 | V19 |
| `results/coverage/20261108T103732/cases.tsv` | 30 例覆盖采集逐例状态（全 `通过`）与 `.dat` 路径 | 覆盖主作业 127239138 | V19 |
| `results/coverage/20261108T103732/slurm_script-20261108T103732.json` | 脚本自身 `status=失败`、`coverage_report` 判据 `rc=2` | 覆盖主作业的 JSON | V19 |
| `results/coverage/20261108T103732/annotated/VdotReduce.sv` | 149 行注释文件（仅标注展示，不是覆盖分母） | `verilator_coverage --annotate-all` | V19 |
| `results/coverage/20261108T103732/annotated/VIMacU.sv` | 752 行注释文件 | 同上 | V19 |
| `results/coverage/20261108T103732/annotated/VIMac64b.sv` | 2530 行注释文件 | 同上 | V19 |
| `out/audit/coverage-summary.md` | 覆盖口径、作业状态、`VIMacSrcTypeModule` 无覆盖点、预算、未采集维度 | 人工审计文档 | V19 V20 |

## 9. 形式验证

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/formal/50-miter-20261104T093531.json` | `status=通过`、2/2 判据、`scope=只证数据通路（vdot_dp），不覆盖流水/发射/旁路` | `core-package/scripts/50-formal-miter.sh`，作业 126751660，2026-11-04 09:35:31–09:38:54 | V17 |
| `results/formal/miter.20261104T093531.yosys.log` | `miter -equiv -make_assert -flatten …` 命令原文与 `SAT proof finished - no model found: SUCCESS!`；`567 cells`、`24354 variables`、`64752 clauses`；`-seq 3` | Yosys 0.48 `sat -verify -prove-asserts -seq 3` | V17 |
| `results/formal/miter.mutant.20261104T093531.yosys.log` | 负控 `SAT proof finished - model found: FAIL!` | 同上，对 mutant 版本 | V17 |
| `design/verify/formal/vdot_dp_spec.sv` | 行为级对照模型（miter 的另一侧） | 手写 SystemVerilog | V17 |
| `design/verify/formal/vdot_dp_miter.sv` | miter 顶层与 `fireS1` 约束 | 手写 SystemVerilog | V17 |

## 10. 扩展（K=16）

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/yosys/ext-127231914.json` | K8 481/19/4900/22、K16 977/20/10744/26、K16Gen 1593/20/13552/27；6/6 判据；`mapped_area_um2=-1`；scope 记「未集成进 VIMacU」 | `design/verify/area/run_ext_yosys.sh`，作业 127231914 | V18 |
| `results/yosys/ext-127231914/VdotReduceK8.stat.cmos.txt` | `Number of cells: 481`、`transistors: 4900+` | Yosys `synth` + `stat -tech cmos` | V18 |
| `results/yosys/ext-127231914/VdotReduceK16.stat.cmos.txt` | `Number of cells: 977`、`transistors: 10744+` | 同上 | V18 |
| `results/yosys/ext-127231914/VdotReduceK16Gen.stat.cmos.txt` | `Number of cells: 1593`、`transistors: 13552+` | 同上 | V18 |
| `results/yosys/ext-127231914/VdotReduceK16.ltp.txt` | `length=26` | Yosys `ltp -noff` | V18 |
| `results/yosys/ext-127231914/VdotReduceK8.ltp.txt` | `length=22` | 同上 | V18 |
| `results/yosys/ext-127231914/miter_k8_vs_public.yosys.log` | K8 vs 公开仓 `VdotReduce`：命令行用 `-make_outputs`，日志里没有 `Import proof` 行，`SUCCESS` 不构成等价 | Yosys `sat -set-init-zero -seq 2` | V18 |
| `results/yosys/ext-127231914/miter_k8_vs_gold.yosys.log` | K8 vs 行为级 gold：同样用 `-make_outputs`、无导入证明目标，`SUCCESS` 不构成等价 | 同上 | V18 |
| `results/yosys/ext-127231914/miter_k16_vs_gold.yosys.log` | K16 vs 行为级 gold：同样用 `-make_outputs`、无导入证明目标，`SUCCESS` 不构成等价；等价未完成 | 同上 | V18 |
| `out/audit/ext-summary.md` | K16 与 K8 的逐项对比、与早前推算值的差异、`ltp` 不是 STA 结论 | 人工审计文档 | V18 |

## 11. 环境、版本与补丁

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/env/00-env-20261105T092724.json` | `status=通过`，逐工具判据；`tool_sby_optional` 记 `MISSING（50 用 yosys 内置 sat，不阻塞）` | `core-package/scripts/00-env-check.sh`，2026-11-05 09:27:24 | V21 |
| `results/env/00-env-20261105T092724.tools.tsv` | 逐个工具的绝对路径与版本，其中 `sby`、`riscv64-linux-gnu-gcc`、`riscv64-elf-gcc`、`riscv64-elf-newlib-gcc`、`z3`、`apptainer` 记 `MISSING` | 同上 | V21 |
| `versions.env` | 基线 pin：xiangshan、yunsuan、`NEMU=a683e0b`、`TAG=baseline-20261101`、`SNAPSHOT_COMMIT=f24ac23…` | 人工维护的版本锁定文件 | V22 |
| `results/emu/10-build-20261107T100125.json` | emu 构建 `status=通过`，`versions` 记 `a4eeaab/9559211/a683e0b` | `core-package/scripts/10-build-emu.sh`，作业 127135641 | V22 |
| `results/emu/30-hello-nodeip-20261104T105314.log` | 冒烟启动、`hostname -I` 取值口径、交叉编译器版本 | `core-package/scripts/30-hello-nodeip.sh`，作业 126758114 | V21 |
| `results/lint/25-rtl-lint-20261104T113051.json` | 两个 top 的 `verilator --lint-only`（默认开关）均 `rc=0 errors=0 warnings=0` | `core-package/scripts/25-rtl-lint.sh`，作业 126761068 | V21 |
| `results/lint/25-wall-lint-20261104T185050.log` | `-Wall` 严格告警档两个 top 均 `rc=1`，以 `%Error: Exiting due to … warning(s)` 结束（`UNUSEDSIGNAL`） | 一次单独的 `verilator --lint-only -Wall` 运行 | V25 |
| `patches/0001-N1-N2-N3-vdot.vv-reference-model-decode-entry-E-nemu.patch` | NEMU 参考模型补丁：3 files +35/−1 | `git format-patch` 从工作树导出 | V22 |
| `patches/0001-X1-add-VDOT_VV-custom-encoding-funct6-001-rocketchip.patch` | rocket-chip 自定义编码 BitPat：1 file +2 | 同上 | V22 |
| `patches/0001-X1-X2-decode-VDOT_VV-as-OPMVV-F-vimac-Vima-xiangshan.patch` | 香山译码为 OPMVV / VimacType.vdot：2 files +2/−1 | 同上 | V22 |
| `patches/0001-X6-X7-VimacOpcode.vdot-3-b111-and-VimacType.-yunsuan.patch` | yunsuan 侧 `VimacOpcode.vdot=3'b111`：2 files +2 | 同上 | V22 |
| `patches/0002-X14-vdot-legality-predicate-in-VecExceptio-xiangshan.patch` | 合法性谓词：1 file +7/−1 | 同上 | V22 |
| `patches/0002-X15-export-sum_wo-walOut-fireS1-from-VIMac64-yunsuan.patch` | 导出 `sum_wo`/`walOut`/`fireS1`：1 file +11 | 同上 | V22 |
| `patches/0003-X8-wrapper-bypasses-Mgu-for-vdot-and-asser-xiangshan.patch` | wrapper 旁路 Mgu 并加断言：2 files +20/−3 | 同上 | V22 |
| `patches/0003-X-new-VdotReduce-K-8-int8-dot-product-reduct-yunsuan.patch` | VdotReduce 归约树：1 file +45 | 同上 | V22 |
| `patches/0004-tests-VdotReduce-Chisel-B-19-200-xiangshan.patch` | Chisel 单测（算法 B 期望值、19 位边界、200 组随机）：1 file +129 | 同上 | V22 |
| `patches/0005-X-new-P-2-VdotReduce-carry-save-retiming-yunsuan.patch` | P-2 carry-save 重定时：1 file +19/−6 | 同上 | V22 |

## 12. 旁证（清单外单例，不计入 30/224）

| 证据文件 | 它证明什么 | 生成方式 | 对应结论 |
|---|---|---|---|
| `results/difftest/dualchain/96-dualchain-20261107T124540.json` | 清单外双链用例判据全部达标，含 G0 捕获与 `golden_crosscheck=LOG_MATCH` | `core-package/scripts/96-run-dualchain.sh`，作业 127142843 | V08（旁证，不计入） |
| `results/difftest/kernel/run-20261106T060159/93-kcmp-20261106T060159.json` | 清单外 kernel 对比单例判据全部达标，`metrics` 记指令数与拍数对比 | `core-package/scripts/93-run-kcmp.sh`，作业 126989295 | V11（旁证，不计入） |
| `results/difftest/r13/92-xcontam-20261106T004445.json` | 清单外交叉污染用例 `status=通过` | `core-package/scripts/92-run-xcontam.sh`，作业 126957204 | V09（旁证，不计入） |
| `results/difftest/slope/98-slope-20261106T162837.json` | 清单外斜率回归 `status=通过` | `core-package/scripts/98-run-slope.sh`，作业 127043836 | V11（旁证，不计入） |
| `results/wave/62-wave-20261105T091811.json` | 波形取证作业六个阶段 `rc` 全 0、指令 `0x3A20A1D7`、VCD sha256 | `core-package/scripts/62-wave-vdot.sh`，作业 126875390 | V17（旁证，不计入） |
| `results/budget-log.tsv` | 每次作业的机时与用途登记 | `core-package/scripts/90-budget-log.sh` | 内部记录，不对应对外结论 |

---

## 13. 索引自身的核对方式

- 全部路径：`while read p; do [ -e "$p" ] || echo MISSING; done`，候选清单 0 缺失。本文件只收录通过存在性检查的路径。
- 全部作业号与时间：取自对应 JSON 的 `slurm_job_id`、`started_at`、`ended_at` 字段或文件头，未从记忆或正文转述。
- 全部数字：与 `out/submission/facts-ledger.md` 对应行逐项比对；比对中发现的差异见 `VALIDATION.md` §4。
