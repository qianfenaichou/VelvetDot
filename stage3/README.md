# stage3 —— 阶段三交付物（官方编号 3.1.1 / 3.1.2 / 3.2 / 3.3）

> owner：芯芯像绒（XinXiangXiangRong） · 打包日：2026-11-03（2026-11-04 00:40–01:10 按 30 例整份证据对齐四份 README；2026-11-04 09:02–09:42 再按 B3/形式/面积三组远程作业对齐结论行；2026-11-04 复核轮补 `-Wall` 档 lint 与「每 top 1 行 %Error」措辞）
> 结论：阶段三四项交付物已按官方编号落目录，**功能/回归主口径仍是「30 例整份 `--full`」**——作业 `126676734`（`results/difftest/20-full-20261103T142246.json`，2026-11-03 14:22:46→14:51:47）`status=通过`、30/30、9/9 criteria 达标、`regression_delta=0`。3.1.2 的全绿、3.2 的新口径 B1/B2、3.3 的三链延迟都由这一次运行直接支撑；3.1.1 的 `nm_exec_vdot`/`vec_reg_compare` 也取自同一次运行。**2026-11-04 远程作业**：① 基线链 `L_base_chain=16`（min 尺度作业 `126750763`；本用例 full 尺度作业 `126762127` 同值，`scale=full`，8×2000=16000 样本），归一每指令 5.33 vs `L_vdot=4` ⇒ 1.33×（口径为**内部自设**，非官方口径）；同作业给出阶梯链 `L_base_chain_ladder=24` 与 **`B3=11` cyc/op**（`b3=OK`、`not_vl4=yes`，只进敏感性分析、不作分母）；② 形式 miter 作业 `126751660`（正向 `SUCCESS`、负控 mutant `FAIL`，仅数据通路）；③ 面积重跑 `126752216`（VIMac64b `42783/293640/100`、VdotReduce `481/4900/22`，与 2026-11-01 同值）；④ 2.2 lint **三档**：`126761068`（`-Wno-fatal`，两 top `rc=0`/`%Error=0`，但 `%Warning` 计数不可信）、返修轮严格模式 `126798101`（去 `-Wno-fatal`，两 top `rc=0`/`%Error=0`/`%Warning=0`）、`-Wall` 档 `126803426`（`VdotReduce` `%Warning=1`、`VIMac64b` `%Warning=12`，**13 条全为 `UNUSEDSIGNAL`**，`%Error` 每 top 各 1 行为汇总行，`rc=1`）⇒「`-Wall` 下 0 告警」**不成立**，不记通过（`results/lint/`，provenance `results/lint/provenance-strict-lint.txt`）。

| 目录 | 官方编号 | 结论一行 | 状态 |
|---|---|---|---|
| `3.1.1-nemu/` | 3.1.1 NEMU 指令扩展 | NEMU `vdot.vv` 参考模型已落码（`a9dca53`，3 文件 +35/−1）；昆山 `nm … \| grep exec_vdot` 命中 2 行；`142246` 的 `criteria[nm_exec_vdot]=达标`、`vec_reg_compare=达标` | 已产出待验（patch 正向回 `a683e0b` 未复验） |
| `3.1.2-difftest/` | 3.1.2 协同仿真验证 | **30 例整份 `--full` 30/30 通过、0 次 ABORT、`regression_delta=0`、`reg_size_match=达标`、`no_empty_green=达标`（自检串 21/21、G0 1/1）**；`perf_base_chain` **不在 30 例清单内**（口径裁定：保持独立测量），其 min/full 两尺度由 `91-run-b3.sh` 作业 `126750763`/`126762127` 单独实测（`verdict=ALL_OK`），不混入本次 30/30 | 已产出待验（**逐用例完整日志 2026-11-05 已回传**：`full-logs-20261103T142246/` 30 `.log` + 30 `.gz`，`ok=30 bad=0`；判据行摘录仍在 `keys-*/`） |
| `3.2-baseline/` | 3.2 基线功能实现 | **新口径 B1=6 / B2=9 cyc/dot 实测通过自检**（`PERF_BASE verdict=ALL_OK … b2_not_vl4=yes discriminates=yes want=0x08 want_vl4=0x12`）；**B3=11 cyc/op 已测**（作业 `126762127`，`scale=full`、`b3=OK`；实现为 `perf_base_chain.c` 的 `B3_ONCE()`，不在 `perf_base.c`；只进敏感性分析、不作分母） | 已产出待验（B3 已测，仅敏感性分析） |
| `3.3/` | 3.3 延迟加速分析报告 | 报告用 T5 ΔL 三链：`L_vadd=3 / L_vmacc=4 / L_vdot=4`（ΔL=0，ΔL_mv=1），三数已由 `126646321`、`126631414`、`126676734` 三次运行互证；**基线链 `L_base_chain=16`（`126762127` full 尺度 + `126750763` min 尺度同值），归一每指令 5.33 vs `L_vdot=4` ⇒ 1.33×**（原始 16/4=4.0× 属跨口径，不写；口径为内部自设）；阶梯链 `24`、B3 `11` 分列、不相减；形式 miter `126751660` 与面积重跑 `126752216` 达标；禁语自查 0 命中 | 已产出待验（基线链已 full 尺度；全流水形式/2 拍 STA 仍未测） |

## 口径总则（三项，贯穿全部目录）

1. **`未运行` 不是通过**：凡 JSON 的 `criteria[].status` 为 `未运行`，本目录 README 与本表一律照抄，不改写成达标。
2. **每个数字跟 JSON**：`3.3/evidence/number-trace.txt` 给出「数字 → `results/difftest/*.json` → 字段 → 实测值」的逐行溯源；其余目录的数字在各自 README 的表格里带路径。
3. **旧口径与新口径不混用**：`20-full-20261102T000517.json`（VL=16、均值、旧 20 例清单）与 `20-full-20261103T112401.json`（28/30，旧镜像）只作历史对照；**当前口径 = `20-full-20261103T142246.json`**（VL=8、中位数、30 例整份清单）。

## 30 例整份证据在各目录的落点

| 目录 | 本目录内的副本 | 关键字段 |
|---|---|---|
| `3.1.1-nemu/evidence/` | `20-full-20261103T142246.json` | `criteria[nm_exec_vdot]=达标`、`criteria[vec_reg_compare]=达标` |
| `3.1.2-difftest/json/` | `20-full-20261103T142246.{json,log,cases.tsv}` | `status=通过`、30/30、`regression_delta=0` |
| `3.1.2-difftest/keys-20261103T142246/` | 30 份逐用例判据行（含源日志 sha256） | 自检串 21/21、8 个负例 `HIT CRITICAL ERROR`、G0 `MISMATCH` |
| `3.2-baseline/json/` | `20-full-20261103T142246.{json,log,cases.tsv}` | `metrics[]` 的 `B1=6`/`B2=9`（`case_id=perf_base`） |
| `3.2-baseline/evidence/` | `perf_base.20261103T142246.key.txt` | `PERF_BASE verdict=ALL_OK …` |
| `3.3/evidence/` | `20-full-20261103T142246.{json,log,cases.tsv}` + 三条链的 `*.key.txt` | `L_vadd=3`/`L_vmacc=4`/`L_vdot=4`/`T_steady=1`/`T_kernel=290` |
| `../results/difftest/b3/`、`../results/formal/`、`../results/yosys/` | 2026-11-04 三组作业原始件 | `L_base_chain=16`（`126750763`）；miter `SUCCESS`+mutant `FAIL`（`126751660`）；面积 `42783/293640/100`+`481/4900/22`（`126752216`） |

## 未包含在 stage3 的项（不越界）

- 1.x（阶段一）在 `stage1/`；2.x（阶段二）在 `stage2/`。
- 本目录只做「复制 + 组织 + 结论」，不生成新测量：所有数字都来自 `results/difftest/*.json`、`results/yosys/*.json` 或 `results/formal/*.json`。2026-11-04 00:40–01:10 只做只读取件（`ssh/scp` 取 30 份判据行 + 4 份作业日志）；**09:02–09:42 另跑三组远程作业**：`126749121`/`126750152`/`126750763`（B3/基线链，前两者失败/诊断、后者 min 尺度达标）、`126751660`（形式 miter）、`126752216`（面积重跑）；**11:56–13:26 再跑** `126762127`（基线链 full 尺度 + ladder + B3，`scale=full`、`verdict=ALL_OK`）、`126761068`（2.2 lint）、`126758114`（1.1 节点 IP 冒烟）。
- 录屏（第三阶段基于波形仿真和性能分析录屏）属官方视频位，**未产出**。

## 本轮（2026-11-04）实跑的核对命令

```
$ python3 -I -c "import json;d=json.load(open('results/difftest/20-full-20261103T142246.json'));print(d['status'],d['slurm_job_id'],d['regression_delta'],len(d['cases']))"
通过 126676734 0 30
$ grep -c '^20-full-20261103T142246' stage2/2.3.3-bound/CASES.tsv
13
$ ls stage3/3.1.2-difftest/keys-20261103T142246 | wc -l
30
$ grep -cE "延迟加速 (6|9)" stage3/3.3/report.md
0
$ grep -aE 'PERF_BASE_CHAIN|VDOT_METRIC L_base_chain' results/difftest/b3/91-b3-20261104T092457.log | head -5
VDOT_METRIC L_base_chain 16
VDOT_METRIC L_base_chain_mean 16
VDOT_METRIC L_base_chain_per_instr 5
PERF_BASE_CHAIN verdict=ALL_OK vl=OK chain_free=OK chain_free_rounds=OK chain_free_alt=OK chain_free_alt_differs=yes samples=2000 rounds=4 scale=min(ladder/B3_skipped)
VDOT_METRIC L_base_chain 16
$ python3 -I -c "import json;d=json.load(open('results/formal/50-miter-20261104T093531.json'));print(d['status'],d['slurm_job_id'],[(c['name'],c['status']) for c in d['criteria']])"
通过 126751660 [('miter_prove', '达标'), ('miter_mutant', '达标')]
$ python3 -I -c "import json;d=json.load(open('results/yosys/40-area-20261104T094144.json'));print(d['status'],d['slurm_job_id'],[(m['top'],m['cells'],m['transistors_est'],m['longest_path']) for m in d['metrics']])"
通过 126752216 [('VIMac64b', '42783', '293640', '100'), ('VdotReduce', '481', '4900', '22')]
```
