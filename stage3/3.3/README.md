# 3.3 延迟加速分析报告（目录说明）

## 结论

报告正文 `report.md` 的延迟对比由 T5 ΔL 三链实测支撑：**`L_vadd=3` / `L_vmacc=4` / `L_vdot=4`，ΔL(vdot−vmacc)=0，ΔL_mv=1**。该三数由两个独立作业复现——`126646321`（4 例 T5+G0 清单）与 `126676734`（30 例整份清单）——判据 `t5_delta_latency=达标`。

## 边界

2026-11-04 的基线组合链在两种样本尺度上给出同一结果：min 尺度作业 `126750763`（`results/difftest/b3/91-b3-20261104T092457.log`，4×500=2000 合并样本）与 full 尺度作业 `126762127`（`results/difftest/b3/91-b3-20261104T115624.log`，8×2000=16000 合并样本、`scale=full`）均产出 `L_base_chain=16`，归一 `L_base_chain_per_instr=16/3≈5.33`（脚本打印整数 `5`）；对 `L_vdot=4` 的每指令延迟比为 **1.33×**（打印整数口径 1.25×）；官方整链口径的 `16/4 = 4.0×` 与之并列，差异只来自分母是否按指令数归一。

同一 full 作业 `126762127` 还产出阶梯链 `L_base_chain_ladder=24` 与 `B3=11 cyc/op`（`b3=OK`、`not_vl4=yes`）；三者互不相减。以上数字均为内部自设口径（用例头注 `design/verify/cases/perf_base_chain.c:55-56`），不写作「官方口径」。min 尺度作业 `126749121`（全量镜像首提）超时，rc=124。

## 依据

形式验证作业 `126751660`（正向 `SUCCESS`、负控 mutant `FAIL`）与面积重跑 `126752216`（VIMac64b `42783/293640/100`、VdotReduce `481/4900/22`）同日完成；`grep -cE "延迟加速 (6|9)"` 对 `report.md` 计数为 0。

## 修订记录（2026-11-07）

§4.8、§4.11、§4.13 按当日最终数据重做：§4.8 改为**吞吐 / 依赖间隔 / T5-L 三口径 A/B/C 分列**（作业 `127142843`，M1–M8 重测并新增 M9/M10/M11 同口径对照），§4.8/§5.5 的双链比值统一为**同窗 5.5/7.5 倍吞吐差（M5/M8，q4/q8；跨窗「7.5×」废止）**；§4.11 的结构覆盖在 2026-11-07 记为「实跑受阻、无覆盖率数字」（**2026-11-08 已由 line-only 重建实测取代**：全 SoC 顶层 67.5%、三模块 `tree_line` 分母 1/3/3，见 `report.md` §4.11.4）；§4.13（P-2）为改 RTL 后的新增实测（481→500 cells / 22→14 级 / DFF 19→38，`L_vdot=4` 不变）。§5 面积基线仍为 481/22；§9 核对表扩至 19 行。`sections/` 七件的定稿版 sha256 与字节数见 `report.md` §8.1；复算 `grep -cE "延迟加速 (6|9)"` 仍为 0。

## 目录内容

| 路径 | 说明 |
|---|---|
| `report.md` | 报告正文（**9 个二级节（`^## ` = 9）+ 28 个三级子节（`^### ` = 28）+ 47 个四级小节（`^#### `，其中 §4.7–§4.13 为七个专题小节）+ 21 个五级小节**：口径声明 / 方法学 / 延迟与吞吐（3.1–3.4）/ 基线对比（**§4.5 内核级指令数/吞吐对比**、**§4.6 外部专题小节（七件）+ §4.7–§4.13 七个专题小节**）/ 面积佐证（§5；含 **§5.1–§5.4 创新性四项支撑点**「零新增乘法器 / 0 拍契约 / Mgu 旁路硬清零 / 编码全库扫描」、**§5.5 4 cyc 机制归因（机制已确认、4 cyc 数值未独立复现）**、**§5.6 软硬协同机制**，对应 `docx/02:93–95`；评分对应表含 **`docx/02:91` 技术路径合理性 10 分行**）/ 复现性 / **扩展潜力（§7，对应评分表「扩展应用潜力」`docx/02:96` 5 分）** / 待回填（§8 + **§8.1 小节来源与并入核对**）/ 用词核对（§9，含 **19 行核对表（2026-11-07 由 16 行扩至 19 行）**）；**§4.7–§4.13 七节（llmbench / dualchain / perf-slope / methodology / coverage / case-expand / innovation-p2）均已并入报告；2026-11-07 按当日最终数据重做 §4.8（13:11 三轴版）、§4.11（08:54 实跑版），并新增 §4.13（13:52 版）**；复算命令 `grep -c '^## ' report.md` → 9、`grep -c '^### ' report.md` → 28、`grep -c '^#### ' report.md` → 47、`grep -c '^##### ' report.md` → 21（2026-11-07 复算） |
| `evidence/20-full-20261103T075552.{json,log,cases.tsv}` | 首次 T5 ΔL 数据源（作业 `126646321`，4/4、9/9 criteria） |
| `evidence/20-full-20261103T142246.{json,log,cases.tsv}` | **当前口径 30 例整份**数据源（作业 `126676734`，30/30、9/9 criteria），`metrics[]` 三链与 075552 完全同值 |
| `evidence/126646321_t5_t5g0.out`、`evidence/126676734_t3e_full30.out` | 两次作业的 slurm stdout |
| `evidence/perf_{vadd,vmacc,vdot}.20261103T075552.log` | 075552 的三条链逐用例完整日志（含 `PERF_* verdict=ALL_OK`） |
| `evidence/perf_{vadd,vmacc,vdot}.20261103T142246.key.txt` | 142246 三条链的判据行摘录（含源日志 sha256），补上「30 例整份也跑出同样三数」的交叉核对 |
| `evidence/perf_vdot.20261102T000517.log` | 旧口径（VL=16、均值）对照日志 |
| `evidence/number-trace.txt` | 报告里每个数字 → JSON 路径 → 字段 → 实测值 的溯源表 |
| `evidence/metrics-current.txt` | `metrics[]` + `criteria[]` 全表（脚本打印） |
| `evidence/area-derivation.txt` | §5 面积数字（458 / 41,945 / 481 / 42,783 / 19 DFF）的核算过程 |
| `../../results/difftest/b3/91-b3-20261104T092457.log` | **2026-11-04 基线链 min 尺度**（作业 `126750763`）：`L_base_chain=16`、`L_base_chain_per_instr=5`、`verdict=ALL_OK`；失败的全量镜像首提作业 `91-b3-20261104T090223.log`（`126749121`，rc=124）同目录 |
| `../../results/difftest/b3/91-b3-20261104T115624.{log,key.txt,summary.json}` | **2026-11-04 full 尺度（作业 `126762127`，`scale=full`）**：`L_base_chain=16`、`L_base_chain_ladder=24`、`B3=11`、`verdict=ALL_OK`；provenance（sacct 状态 / 远端镜像 md5）见同目录 `provenance/91-b3-provenance.txt` |
| `../../results/formal/50-miter-20261104T093531.json`、`../../results/yosys/40-area-20261104T094144.json` | 形式 miter（`126751660`，SUCCESS + mutant FAIL）与面积重跑（`126752216`，42783/293640/100 与 481/4900/22）的结果 JSON |
| `evidence/t2-grep-check.txt` | T2 判据核对：`grep -cE "延迟加速 (6|9)"` → 0 |

## 关键实测（每条带 JSON 路径）

- `L_vadd = 3`：`results/difftest/20-full-20261103T142246.json` → `metrics[]`（`case_id=perf_vadd`）；同值见 `20-full-20261103T075552.json`
- `L_vmacc = 4`：同上（`case_id=perf_vmacc`）
- `L_vdot = 4`：同上（`case_id=perf_vdot`；`L_vdot_mean` 亦为 4，`L_vdot_loop` 为 6，属另一口径）
- `T_steady = 1`：同上（`case_id=perf_vdot`）
- `T_kernel = 290`：同上（`case_id=perf_vdot`）
- `B1 = 6` / `B2 = 9`：同上 `metrics[]`（`case_id=perf_base`，**新口径**，见 `../3.2-baseline/README.md` §3）
- `L_base_chain = 16` / `L_base_chain_per_instr = 5`：`results/difftest/b3/91-b3-20261104T092457.log`（作业 `126750763`，min 尺度）与 `results/difftest/b3/91-b3-20261104T115624.log`（作业 `126762127`，full 尺度，`samples=16000`）两处同值；见 `report.md` §4.3；精确归一 16/3≈5.33
- `L_base_chain_ladder = 24` / `B3 = 11`：同上 full 尺度日志（`scale=full`、`ladder=OK`、`b3=OK`）；两者与 `L_base_chain` **不相减**，B3 不作分母
- 独立复现链：`126646321`（4 例 T5+G0）→ `126631414`（3 例 perf）→ `126676734`（30 例整份），三次 `L_vadd/L_vmacc/L_vdot` 均为 `3/4/4`
- 形式/面积（2026-11-04）：`126751660` miter 正向 `SUCCESS` + 负控 `FAIL`（`results/formal/50-miter-20261104T093531.json`）；`126752216` 面积 `42783/293640/100`（VIMac64b）与 `481/4900/22`（VdotReduce）（`results/yosys/40-area-20261104T094144.json`）

## 口径保留

1. 旧口径 `L_vdot=6`（`results/difftest/20-full-20261102T000517.json` → `metrics[0]`）是 VL=16 + 整段均值，**不可与新值 4 相减或互替**。
2. 6 / 9 只作**吞吐口径的每点开销倍数**（`B1÷T_steady`、`B2÷T_steady`），不是加速比，也不写作「快 6 倍/快 9 倍」（2026-11-04 已在 §4.2/§4.4/§4.7.7 降级）；报告 §4.1/§4.3/**§8** 已按 **min（2000 样本）/ full（16000 样本）两口径分列**回填 `L_base_chain`（同值 16）、阶梯链 `24`、`B3=11`（§7 标签约定句内 `L_base_chain` 命中 0），并同句声明归一方式与三条边界；**加速比两口径并列：整链 `16/4 = 4.0×` 与每指令归一 1.33×（整数口径 1.25×）**，引用时须写明是哪一个；§4.8/§5.5 的双链比值一律写**同窗 5.5/7.5 倍吞吐差（M5/M8；跨窗「7.5×」已废止）**，且**不得与依赖间隔口径（5.7–7.5 cyc/步）或 T5 的 `L_vdot=4` 相除**。
3. 面积已于 2026-11-04 重跑（`results/yosys/40-area-20261104T094144.json`，作业 `126752216`），数值与 2026-11-01 相同；DFF 指纹 19 仍来自 `results/yosys/vdot.stat.json`（2026-11-01），新 JSON 未列 DFF。
4. **`report.md` 本次（2026-11-04）已改写 §4.3/§5/§6/§7**：补 `L_base_chain` 实测、形式 miter、面积重跑；§1/§3 引用的 `075552` 数字与 `142246` 完全一致，未改。
5. **B3 已测（2026-11-04 修订同步）**：`B3 = 11 cyc/op`（作业 `126762127`，`scale=full`、`b3=OK`、`not_vl4=yes`，`results/difftest/b3/91-b3-20261104T115624.log`）。此前记「B3 未测」依据的 min 尺度作业 `126750763`（`scale=min(ladder/B3_skipped)`）已被取代。约定：B3 只进敏感性分析、**不作分母**、不与 `L_base_chain`/`L_base_chain_ladder` 相减；其计数法与 B1/B2 不同（B3 不丢暖机，B1/B2 无暖机，见 `report.md` §4.3 诚实边界 ⑥）。

## 本次（2026-11-04）核对命令与输出

```
$ python3 -I -c "import json;d=json.load(open('results/difftest/20-full-20261103T142246.json'));print([(m['name'],m['value']) for m in d['metrics']])"
[('L_vdot','4'),('L_vdot_mean','4'),('L_vdot_loop','6'),('T_steady','1'),('T_kernel','290'),('B1','6'),('B2','9'),('L_vadd','3'),('L_vadd_mean','3'),('L_vadd_loop','5'),('L_vmacc','4'),('L_vmacc_mean','4'),('L_vmacc_loop','6')]
$ grep -aE 'PERF_BASE_CHAIN|VDOT_METRIC L_base_chain' results/difftest/b3/91-b3-20261104T092457.log | head -5
VDOT_METRIC L_base_chain 16
VDOT_METRIC L_base_chain_mean 16
VDOT_METRIC L_base_chain_per_instr 5
PERF_BASE_CHAIN verdict=ALL_OK vl=OK chain_free=OK chain_free_rounds=OK chain_free_alt=OK chain_free_alt_differs=yes samples=2000 rounds=4 scale=min(ladder/B3_skipped)
VDOT_METRIC L_base_chain 16
$ python3 -I -c "import json;d=json.load(open('results/formal/50-miter-20261104T093531.json'));print(d['status'],d['slurm_job_id'],[(c['name'],c['status']) for c in d['criteria']],d['scope'])"
通过 126751660 [('miter_prove', '达标'), ('miter_mutant', '达标')] 只证数据通路（vdot_dp），不覆盖流水/发射/旁路
$ python3 -I -c "import json;d=json.load(open('results/yosys/40-area-20261104T094144.json'));print(d['status'],d['slurm_job_id'],[(m['top'],m['cells'],m['transistors_est'],m['longest_path']) for m in d['metrics']])"
通过 126752216 [('VIMac64b', '42783', '293640', '100'), ('VdotReduce', '481', '4900', '22')]
$ grep -cE "延迟加速 (6|9)" stage3/3.3/report.md
0
$ grep -c 'PERF_VDOT verdict=ALL_OK' stage3/3.3/evidence/perf_vdot.20261103T142246.key.txt
1
```
