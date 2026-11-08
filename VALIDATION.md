# 验证说明：哪些结论有证据，哪些没有

本文件逐条列出这次交付的结论、怎么验的、证据在哪、结果如何、边界在哪。数字全部取自 `out/submission/facts-ledger.md`；此处只做归并和判读，不引入新数。

四个结果词的定义：

- **通过**：证据记录了该结论成立，且本次核对读到了对应字段。
- **未通过**：证据记录了该结论不成立（数字与断言相反）。
- **未成立**：产物存在，但缺少证明目标或对照件，只能说明命令跑完，不能说明结论成立。
- **未运行**：没有产物，或产物明确记「未做／未采集」。

「验证方式」列区分两种情况：**本轮重跑**指 2026-11-08 核对时在本机执行了命令并读到输出；**归档复核**指只读已归档的远端作业产物（JSON、TSV、日志），没有重跑仿真、综合、STA 或功耗。两者都能支撑结论，但前者可当场复现，后者依赖归档件完整。

---

## 1. 逐条结论

| 编号 | 结论 | 验证方式 | 证据 | 结果 | 未覆盖的部分 |
|---|---|---|---|---|---|
| V01 | 【语义】 语义为 `S = Σ_{i=0..7} sext19(sext8(vs1[i]) × sext8(vs2[i]))`，取低 64 位 lane 0–7，高 64 位不参与；`vd[31:0]=sext32(S)`、`vd[127:32]=0` | 本轮重跑：金模型自检 + 224 例期望值交叉核对；归档复核：主回归与扩容的逐例结果 | `design/verify/vdot_model_test.py`（本轮 `ALL TESTS PASSED (1142 cases)`，EXIT=0）；`design/verify/cases/extra_crosscheck.py`（本轮 `cases=224 problems=0`、`verdict=MATCH`，EXIT=0）；`design/SPEC.md:15,29-31` | 通过 | 形式验证只到 `vdot_dp` 数据通路、3 拍有界（V17）；没有硅后寄存器实测 |
| V02 | 【语义】 内部 19 位有符号：最坏正和 `8×(−128)×(−128)=131072`，超过 18 位有符号上限 131071；19 位范围 `[−262144, 262143]` 可容 | 本轮重跑：算术复核（`2**18-1=262143`、`16×16384=262144`）+ 金模型边界用例 | `design/SPEC.md:30,62-63,169`；`design/verify/vdot_model_test.py`（本轮 EXIT=0） | 通过 | 没有 18 位实现的 RTL 对照件，「用 18 位会错」只在模型与算术层成立，未在门级复现 |
| V03 | 【语义】 `vl` 任意值（含 0 与 1–7）都算 lane 0–7 并全写 `vd`，这是对 RVV「`vl=0` 不写回」的有意偏离 | 归档复核：224 例扩容中的 `vl` 全扫用例（`xb_vl_sweep`、`xo3_vl_sweep`）随整套 224/224 通过 | `design/verify/cases/manifest.extra.tsv:6,64`；`results/difftest/extra/94-extra-20261108T014445.json:15`；`design/SPEC.md:34,56` | 通过 | 与外部 `specs/vdot-v0.1.json` 的 `vl` 口径不同（其 0 与 8..16 合法），未按外部口径验证（`design/SPEC.md:298`） |
| V04 | 【编码】 编码三元组为 opcode `1010111` / funct3 `010` / funct6 `001110` / vm `1`；`vdot.vv v3, v2, v1` = `0x3A20A1D7` | 本轮重跑：编码门禁（工作区快照 + riscv-opcodes 本地快照 `f24ac23`）；归档复核：perf 用例运行时 `enc_check` | `design/verify/encoding-gate.py`（带快照本轮 `PASS` 退出码 0；不带快照退出码 4，即官方归属维度未覆盖）；`results/difftest/perf-repeat/99-perf-repeat-4x-20261108.cases/perf_vdot.r1.20261108T020356.log.gz:3`（`enc_check=0x3A20A1D7 expect=0x3A20A1D7 OK`） | 通过 | 上游快照为 `f24ac23`（2026-10-31）；此后上游若有新分配，本次未复核 |
| V05 | 【编码】 曾用的 `001100/010`（0x0C）已被 Zvbc `vclmul.vv` 占用，故改用 `001110/010`；`101100/010` 属未批准提案 Zvdot4a，主线不用 | 本轮重跑：编码门禁的阳性对照（旧码 `0x3220A1D7` 必须判撞车） | `design/verify/encoding-gate.py`（本轮 `[P1]` 命中）；`design/SPEC.md:77,81,100-105` | 通过 | 只对着 `f24ac23` 快照核对，快照之后的上游变动不在范围内 |
| V06 | 【功能】 主回归 30 例 30/30 通过，`regression_delta=0`，9/9 判据达标（作业 127137638，2026-11-07 10:42:27–11:12:17） | 归档复核：读 JSON 的 `status`、`cases[]`、`criteria[]`、`counters` | `results/difftest/20-full-20261107T104227.json:5,8-13,17-23,72`；`.cases.tsv`（30 数据行）；`.log`（30 条 `case … -> 通过`） | 通过 | 2026-11-08 没有 30 例 `--full` 复跑（`ls results/difftest/20-full-*` 最新为 20261107）；11-07 轮逐例日志未取回本地，本地只有 11-03 轮的 `full-logs-20261103T142246/` 副本 |
| V07 | 【功能】 同清单 30 例在 2026-11-03 也跑出 30/30、9/9 判据（作业 126676734，14:22:46–14:51:47） | 归档复核：读 JSON；与 V06 比对清单哈希 | `results/difftest/20-full-20261103T142246.json:5,7-12`（manifest sha256 与 V06 同为 `e12470e6…`） | 通过 | 两次共用同一份 30 行清单；清单本身覆盖什么、不覆盖什么见 V09 与 V10 |
| V08 | 【功能】 扩容 224 例 224/224 通过，`not_run=0`，8/8 判据达标，`golden_crosscheck=MATCH`（作业 127194011，2026-11-08 01:44:45–03:24:34） | 归档复核：读 JSON 的 `counters` 与 `criteria`；本轮重跑交叉核对脚本 | `results/difftest/extra/94-extra-20261108T014445.json:5,10-17,19-20,26,27`；`design/verify/cases/extra_crosscheck.py`（本轮 `cases=224 reads_or_groups=10357 vdot_encs=415 problems=0`） | 通过 | 224 例实跑在远端，本地未重跑；本地 `design/verify/cases/extra/` 有 224 个 `.c` 但只有 129 个 `.bin` |
| V09 | 【功能】 防空绿：主回归自检串 21/21 命中、G0 反例 1/1 被同一判据判负；扩容自检串 162/162、G0 2/2、负例 57/57 双侧一致陷入非法；`reg_size_bad=0` | 归档复核：counters + G0 用例日志的 `MISMATCH` 行 | `results/difftest/20-full-20261107T104227.json:20,72`；`stage3/3.1.2-difftest/full-logs-20261103T142246/vdot_g0_badexp.20261103T142246.log:3-4`；`results/difftest/extra/94-extra-20261108T014445.json:15-17,24-25` | 通过 | G0 是人工篡改期望值的单一反例种类；判据能抓这一类，不等于能抓所有实现错误 |
| V10 | 【功能】 两份清单 cid 交集为 0、并集 254 条；主回归只算 30 例，扩容 224 例单独跑，`254` 不是回归用例数 | 本轮重跑：集合比对 + 行数统计 | `design/verify/cases/manifest.tsv`（30 数据行）；`design/verify/cases/manifest.extra.tsv`（224 数据行）；本轮 `grep -vc '^#'` 得 30 / 224，cid 交集 0 | 通过 | 扩容 JSON 另记 `manifest_main_sha256=413b5796…`，与主回归的 `e12470e6…` 不同，两者不能当成同一份主清单 |
| V11 | 【性能】 `L_vdot=4` cycles/指令（4 次独立重复均为 4，极差 0），`T_steady=1`，kernel 级 290 cycles；`L_vadd=3`、`L_vmacc=4`、B1=6、B2=9 | 归档复核：perf-repeat 的 summary TSV 与 JSON | `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.summary.tsv:2-14`；`results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json`（`summary.perf_vdot`） | 通过 | emu 的 rdcycle 模型周期，不是硅；4 次少于 `design/ALGORITHM.md:212` 要求的「同配置再跑 ≥5 次」；4 个 perf 用例均以 `--no-diff` 运行 |
| V12 | 【性能】 主加速比 `1.333× = (16/3)/4`；`1.25×` 是整数截断口径；`4.0×` 与 `2.285714×` 不能当 latency 加速比 | 本轮重跑：算术复核；归档复核：JSON 的预登记口径与 `not_used` 段 | `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json:32-37,50-60,75-79`；`results/difftest/b3/91-b3-20261104T115624.log:13`（`L_base_chain` 16，rounds=8、samples=16000） | 通过 | 分子 16 来自另一作业 126762127，不是这 4×4 次运行测得；本轮只重测分母 `L_vdot` |
| V13 | 【面积】 K1 `VdotReduce` 481 cells / 19 DFF / LTP 22；P2 500 / 38 / LTP 14；VIMac64b 42783 cells / 293640 transistors / LTP 100；VdotReduce 占 VIMac64b 1.12%（K1 cells）、1.17%（P2 cells）、1.67%（晶体管估算） | 归档复核：Yosys stat JSON、`ltp -noff` 文本、`stat -tech cmos` 文本；本轮重跑比例算术 | `results/yosys/vdot-k1.stat.json:15,19`；`vdot-p2.stat.json:15,19`；`vdot-k1.ltp.txt:3`；`vdot-p2.ltp.txt:3`；`vmac_only.stat.json:15`；`results/yosys/40-area-20261107T095404.json:18-19` | 通过 | abc 通用门计数，不是硅面积；`mapped_area_um2=-1`，给不出 µm²；`vmac_only.ltp.txt` 本地未归档，LTP 100 只有 JSON 的 `metrics` 值 |
| V14 | 【时序】 K1 `VdotReduce` @333 ps worst slack −791.8 ps（path delay 1084.3 ps）、@500 ps −624.8 ps；P2 @333 −375.8 ps（658.8 ps）、@500 −208.8 ps | 归档复核：worst-slack TSV 与原始 `.rpt` | `results/sta/20261108/worst_slack_20261108.tsv:2-3,6-7`；`results/sta/20261108/reports/K1_VdotReduce_0.333ns_20261108.rpt:49`；`reports/P2_VdotReduce_0.333ns_20261108.rpt:41` | 通过 | Nangate45 代理库、预布局、无 CTS/SPEF/负载模型、理想时钟；K1 的 required time 已扣 40.532 ps 库 setup，不能按 `period−50−arrival` 验算 |
| V15 | 【时序】 K1/P2 `VdotReduce` 在 500 ps 周期下不满足 setup（两条路径均违例） | 归档复核：同上 TSV | `results/sta/20261108/worst_slack_20261108.tsv:3,7`（−624.8 / −208.8 ps，均 VIOLATED） | 未通过 | K1 与 P2 的 slack 都小于 0；要满足须放宽周期（V16）或改 RTL |
| V16 | 【时序】 闭合点：P2 在 750 ps 首次 worst slack ≥0（+41.161 ps；700 ps 为 −8.839 ps）；K1 在 1200 ps 首次 ≥0（+75.164 ps；1100 ps 为 −24.836 ps） | 归档复核：闭合扫描 TSV 与 `.rpt` | `results/sta/20261108/worst_slack_closure_20261108.tsv:2-7`；`reports_closure/P2_VdotReduce_0.750ns_20261108.rpt:41`；`reports_closure/K1_VdotReduce_1.200ns_20261108.rpt:49` | 通过 | 代理工艺 + 预布局下的模块级 worst slack，不是频率结论、不是流片结论；VIMac64b 未进闭合扫描 |
| V17 | 【形式验证】 `vdot_dp` 组合 miter 正向 `SUCCESS`、负控 mutant `FAIL`，2/2 判据达标，3 拍有界 | 归档复核：Yosys 日志与 JSON | `results/formal/miter.20261104T093531.yosys.log:104`；`results/formal/miter.mutant.20261104T093531.yosys.log:104`；`results/formal/50-miter-20261104T093531.json:5,11,14-15` | 通过 | 只证数据通路，不覆盖流水、发射、旁路；是 RTL vs 行为级 `vdot_dp_spec`，不是 RTL vs NEMU/ISA；`-seq 3` 有界 |
| V18 | 【扩展】 K16 977 cells / 20 DFF / 10744 transistors / LTP 26 / 20 位有符号；K16Gen 1593 cells / LTP 27 是退化旁证（以上为综合数字）。K8 vs 公开仓、K8 vs gold、K16 vs gold 三组 miter 的日志打印 `SUCCESS`（2 拍有界），但命令用 `-make_outputs`、没有导入证明目标，`SUCCESS` 不构成等价；K16 等价未完成 | 归档复核：ext JSON、逐 top stat/ltp 文本、三份 miter 的命令行与 `Import proof` 行 | `results/yosys/ext-127231914.json:11-12,15-20,23-25`；`results/yosys/ext-127231914/miter_k8_vs_public.yosys.log:9,76`；`miter_k8_vs_gold.yosys.log:9,72`；`miter_k16_vs_gold.yosys.log:9,80` | 未成立 | 2 拍有界（`-seq 2`），不是无界证明；只覆盖独立归约树，未集成进 VIMacU；补齐等价需要一条导入 assert 或 trigger 目标的日志，以及被比较参照件的存档；`design/SPEC.md:170-171` 仍写「不写扩展 RTL」，与 2026-11-08 的 ext 证据表述不一致 |
| V19 | 【结构覆盖】 SimTop 顶层行覆盖 67.5%（113628/168283，30 个 `.dat` 合并，Verilator 5.053）；VdotReduce / VIMacU / VIMac64b 的 `tree_line` 分别为 1/1、3/3、3/3 | 归档复核：覆盖率汇总文本与 AllCoverage 日志段落 | `results/coverage/20261108T103732/merged30all.coverage/verilator_coverage-summary.txt:2`；`.../coverage_SimTop.log:13262-13263,11167-11168,8772-8773`；`.../dats.list`（30 行） | 通过 | 67.5% 是 SimTop 顶层行覆盖，不是 vdot 模块覆盖率；`tree_line` 的分母只有 1、3、3 个计数点；采集主作业 127239138 退出码 1，报告由后处理作业 127252294 重做 |
| V20 | 【结构覆盖】 toggle / branch / expr / fsm_state / fsm_arc 未采集；`VIMacSrcTypeModule` 无覆盖点 | 归档复核：汇总文本的 0/0 行与审计记录 | `.../verilator_coverage-summary.txt:3-7`；`out/audit/coverage-summary.md:15,51-52` | 未运行 | 构建只开 `--coverage-line`；这些维度没有产物，不能写成「覆盖率 0%」 |
| V21 | 【环境】 2026-11-05 09:27:24 的工具链探针 `status=通过`，gcc/g++ 13.3.0、cmake 3.25.0、make 4.2.1、python3 3.8.13、java 17.0.21、git 2.30.2、Verilator 5.053、Yosys 0.48、Mill 0.12.3、riscv64-unknown-elf-gcc 13.2.0 | 归档复核：探针 JSON 的 `criteria` 与 TSV | `results/env/00-env-20261105T092724.json:5,14-26`；`results/env/00-env-20261105T092724.tools.tsv` | 通过 | `sby` 记为 `MISSING`（50 用 Yosys 内置 `sat`，不阻塞）；`z3`、`apptainer` 同样缺失；探针是登录节点单次采样 |
| V22 | 【环境】 版本：基线 pin `a4eeaab` / `9559211` / `a683e0b` 是实施 HEAD `913ddd3` / `8942811` / `a9dca53` 的祖先；`repos/YunSuan`（`267ff73`）零改动 | 本轮重跑：`git rev-parse --short HEAD` 与 `git merge-base --is-ancestor`（三次均 exit 0）；`git status --porcelain` | `versions.env:2-6`；本轮命令输出（见 §2 第 11 项） | 通过 | `repos/XiangShan` 工作树有 ` M yunsuan`（子模块指针未提交），所以「HEAD = 交付内容」只对已提交部分成立 |
| V23 | 【功耗】 K1 leakage 17.78420 µW、1 GHz 合成活动率（0.1/cycle、duty 0.5）下 total 0.904848 mW；P2 19.74276 µW / 0.9546821 mW；VIMac64b 746.2668 µW / 35.99424 mW | 归档复核：power TSV 与 `report_power` 原始日志的 `Total` 行 | `results/sta/20261108/power_summary_20261108.tsv:3-8`；`results/sta/20261108/reports_power/K1_VdotReduce_leak_20261108.log:49`；`.../K1_VdotReduce_synthetic_20261108.log:49`；`.../VIMac64b_synthetic_20261108.log:49` | 通过 | leakage 与 dynamic 分列；synthetic 活动率不是真实负载；无 VCD/SAIF、无整核功耗、无 IR-drop |
| V24 | 【未做项】 布局布线后 STA / CTS / SPEF 反标 / 真实 VCD·SAIF / 整核功耗 / IR-drop；全流水形式验证与 ISA 级合规；硅后实测；VIMac64b 时序闭合扫描；2026-11-08 的 30 例 `--full` 复跑 | 归档复核：审计文「未做」节与台账缺口节；本轮 `ls` 确认无 11-08 full 产物 | `out/audit/sta-closure-power.md:142`；`results/formal/50-miter-20261104T093531.json:11`；`out/submission/facts-ledger.md` §12 | 未运行 | 这些项没有任何产物；本文件与索引中出现的所有性能、面积、时序、功耗数字都不是硅数据 |
| V25 | 【代码质量】 RTL 在 `verilator --lint-only -Wall` 下零告警 | 归档复核：读 `-Wall` 运行日志的逐 top 汇总行 | `results/lint/25-wall-lint-20261104T185050.log`（两个 top 均 `rc=1`，以 `%Error: Exiting due to … warning(s)` 结束；`UNUSEDSIGNAL` 类告警） | 未通过 | 该维度的计数不在 `out/submission/facts-ledger.md` 内，本行不引具体计数。默认 `--lint-only`（不加 `-Wall`）另有一次运行，详见 `results/lint/25-rtl-lint-20261104T113051.json` |

---

## 2. 本轮（2026-11-08）实跑的检查与输出

以下命令在本机执行过，输出为原样摘录。

1. `node design/verify/check.js`
   ```
   门禁通过：文档体系检查全部 OK
   EXIT=0
   ```

2. `node design/verify/check-v3.js`
   ```
   v3 门禁通过：引用存在性 / 任务票六字段 / INDEX 可达性 / 命名合规 全部 OK
   EXIT=0
   ```

3. `python3 -I design/verify/vdot_model_test.py`
   ```
   ALL TESTS PASSED (1142 cases)
   EXIT=0
   ```

4. `python3 -I design/verify/cases/extra_crosscheck.py --quiet`
   ```
   EXTRA_CROSSCHECK cases=224 reads_or_groups=10357 vdot_encs=415 problems=0
   EXTRA_CROSSCHECK verdict=MATCH（全部期望常量与金模型逐条一致）
   EXIT=0
   ```

5. `python3 -I design/verify/encoding-gate.py`
   ```
   结论: 工作区维度 0 冲突，但官方归属维度未覆盖（退出码 4）。
   ```
   即不带上游快照时只能证明「工作区不自撞」，不能证明「官方未分配」。

6. `python3 -I design/verify/encoding-gate.py --snapshot design/_recon/vendor/riscv-opcodes-f24ac23`
   ```
   [U] riscv-opcodes 本地快照 ...: 与冻结三元组重叠 0 条
   [U]   阳性对照: 0x0C->['vclmul.vv'] 0x2C->['vdot4a.vv'] ; 0x0E(本编码)->FREE ; 判定=管线有效
   结论: PASS（退出码 0）
   ```

7. `sha256sum stage3/3.1.2-difftest/manifest.tsv design/verify/cases/manifest.tsv`
   ```
   a90d107118773ebb0de5c1518846680b174b03cf0eb0cdf8be333e582dddbab1  stage3/3.1.2-difftest/manifest.tsv
   a90d107118773ebb0de5c1518846680b174b03cf0eb0cdf8be333e582dddbab1  design/verify/cases/manifest.tsv
   ```

8. `sha256sum results/coverage/20261108T103732/manifest.30.tsv`
   ```
   e12470e653e64671129d6c093859841f795805bdd78412c1f04965d853cbb61b
   ```
   与 V06/V07 的 `manifest.sha256` 一致；两个哈希对应两种写法（`@IMG_DIR@` 占位 vs 绝对路径），不是同一文件。

9. `grep -vc '^#' stage3/3.1.2-difftest/manifest.tsv` → 30；`grep -vc '^#' design/verify/cases/manifest.extra.tsv` → 224。

10. `wc -l results/coverage/20261108T103732/annotated/*.sv` → 149（VdotReduce）、2530（VIMac64b）、752（VIMacU）。
    这是注释文件行数，不是覆盖分母。

11. `git -C <repo> rev-parse --short HEAD`：
    `repos/XiangShan` 913ddd3 · `repos/XiangShan/yunsuan` 8942811 · `repos/NEMU` a9dca53 · `repos/XiangShan/rocket-chip` c4d7616 · `repos/YunSuan` 267ff73。
    `merge-base --is-ancestor` 对 `a4eeaab` / `9559211` / `a683e0b` 均 exit 0。
    `repos/XiangShan status --porcelain` → ` M yunsuan`；`repos/XiangShan/yunsuan status --porcelain` → 空；`repos/YunSuan status --porcelain` → 空。

12. 补丁 diffstat 逐份解析：10 个 patch、15 个文件条目、合计 +272/−12 行（跨 patch 同一文件未去重）。

13. `ls design/verify/cases/extra/*.c | wc -l` → 224；`ls design/verify/cases/extra/*.bin | wc -l` → 129。

14. `ls results/difftest/20-full-*` → 最新为 `20-full-20261107T104227.{json,log,cases.tsv}`，没有 2026-11-08 的 `--full` 产物。

---

## 3. 没做的事，以及为什么不能补写成做了

- **没有重跑远端作业**：主回归、扩容、perf-repeat、Yosys、形式验证、覆盖率采集、STA、功耗全部是读归档。本机没有昆山集群的 emu、网表和 EDA 环境，重跑不在本次可及范围内。
- **没有重新采集覆盖率**：toggle/branch/expr/fsm 仍是未采集状态；采集主作业 127239138 的脚本判据 `coverage_report` 未达标，现在的 67.5% 来自同管线后处理重做。
- **没有做布局布线后时序**：现有 slack 全部是 Yosys 映射后、预布局、Nangate45 代理库条件下的模块级数值，不能外推为芯片频率或流片结论。
- **没有验证外部口径**：外部 `specs/vdot-v0.1.json` 的 `vl` 合法集合与本项目不同，本次未按外部口径复验。
- **没有硅后数据**：本文件所有性能、面积、时序、功耗均来自 emu、Yosys 估算或代理工艺/预布局，不是实测芯片。

---

## 4. 核对台账时发现的三处问题

这三处不影响数字本身，但会让照着台账回查的人落到错行或错文件，本文件与索引已改用正确出处。

1. **台账 §4 的行号引用错位 2 行。** 台账第 75–79 行把 P2 与 VIMac64b 的 slack 记成 `worst_slack_20261108.tsv:4`、`:5`、`:6-9`；实际该文件第 4–5 行是 `K1_VIMac64b`、第 6–7 行是 `P2_VdotReduce`、第 8–9 行是 `P2_VIMac64b`。按台账行号回查会读到别的行。本文件 V14 已改引 `:2-3,6-7`。
2. **`40-area` JSON 的 `stat_json` 字段无法区分 K1 与 P2。** `results/yosys/40-area-20261107T095404.json` 与 `40-area-20261107T104238.json` 的 `metrics[1].stat_json` 都指向 `.../results/yosys/vdot.stat.json`；本地该文件与 `vdot-k1.stat.json` 的 sha256 相同（`a9c219f1…`，481 cells），P2 的 500 cells 只在 `vdot-p2.stat.json`（sha256 `0540052f…`）里。V13 直接引两个分版本文件，不引 JSON 的 `stat_json` 指针。
3. **台账 §3 的 `4900 transistors` 原文是 `4900+`。** `vdot-k1.stat.cmos.txt` 与 `vdot-p2.stat.cmos.txt` 第 27 行都打印 `4900+`（粗估），因此不能据此算 P2−K1 的晶体管差值，也不能与 K16 的 `10744+` 做精确减法。
