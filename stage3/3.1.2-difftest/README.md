# 3.1.2 协同仿真验证（NEMU ↔ RTL difftest）

> 计划完成日：2026-11-03（非官方截止日）
> 结论：**当前 30 例清单整份 `--full` 已跑并通过**——`json/20-full-20261103T142246.json`（昆山作业 `126676734`，2026-11-03 14:22:46→14:51:47，实耗 29:01）：`status=通过`、`cases_pass=30/30`、`cases[].abort` 全 `"0"`（0 次 ABORT）、`regression_delta=0`、`criteria[reg_size_match]=达标`、`no_empty_green=达标`（自检串 21/21、G0 捕获 1/1），9/9 criteria 达标。**`perf_base_chain` 不在 30 例清单内**（口径裁定：保持独立测量；该行已从 `design/verify/cases/manifest.tsv` 移除，清单 sha256 回到运行当时的 `a90d1071…`）：该例由 `core-package/scripts/91-run-b3.sh` 单独实测，min 尺度作业 `126750763`（`verdict=ALL_OK`、`L_base_chain=16`）与 full 尺度作业 `126762127`（`scale=full`、`samples=16000`、`verdict=ALL_OK`）两轮均已跑通 ⇒ 本目录的 30/30 仍是功能/回归的权威口径，不把该例的链延迟数字混进来。

## 1. 目录内容

| 路径 | 内容 |
|---|---|
| `json/20-full-20261103T142246.{json,log,cases.tsv}` | **当前口径 30 例整份 `--full`**（作业 `126676734`，`status=通过`） |
| `../../results/difftest/extra/94-extra-20261108T014445.{json,log,cases.tsv}` | **扩容清单 224 例**（`94-run-extra.sh`，作业 `127194011`：`224/224`、负例 `57/57`、自检串 `162/162`、G0 `2/2`、8/8 criteria） |
| `json/20-full-*.json|.log|.cases.tsv`（其余 4 份） | 历史运行：1102 全量 20 例；1103 的 4/6/3 例分片 |
| `json/20-smoke-*.json|.log|.cases.tsv` | `--smoke` 运行（**仅 1103 的两次**：`032017`、`032337`；`ls json/ \| grep -c 20261105` → **0**）。**2026-11-05 的 3 次 smoke（`092822`/`095320`/`112035`）不在本目录**，落在仓根的 `results/difftest/20-smoke-20261105T{092822,095320,112035}.{json,log,cases.tsv}`（逐例日志归档在 `results/difftest/cases-112035/`）；其中 `112035` 为 G0 白名单修复后的通过件（`status=通过`、`cases_pass=24/24`），另两次是修复前结构不可通过的历史件（见 2026-11-06 条记录） |
| `keys-20261103T142246/`（30 份） | `142246` 逐用例判据行摘录（自检通过串 / `HIT CRITICAL ERROR` / `HIT GOOD TRAP`），含源日志路径 + 字节数 + sha256 |
| `slurm/`（7 份） | Slurm stdout，含 `126676734_t3e_full30.out` |
| `images/`（8 个 `.bin`） | 涉及的镜像（hello_identity / perf_* / vdot_mix / vdot_rand / vdot_ill_sew），md5 与 `design/verify/cases/` 同值 |
| `manifest.tsv` | `142246` 运行时的 **30 行**用例清单（sha256 `a90d1071…`）；现行 `design/verify/cases/manifest.tsv` 与它**逐字节相同**（曾短暂加入的 `perf_base_chain` 行已移除，见 `sha256sum` 两文件同值） |
| `cases/`（9 份） | 旧口径逐用例完整日志（perf_vadd/vmacc/vdot ×2 轮、vdot_g0_badexp、vdot_mix ×2） |
| `full-logs-20261103T142246/`（30 `.log` + 30 `.gz`） | **30 例逐用例完整日志**（2026-11-05 回传，逐份 sha256/size 对 `keys-*/` 复算 `ok=30 bad=0`） |

## 2. 逐份运行证据

| 运行 | 作业 | 清单 | 用例 | 0 ABORT | regression_delta | reg_size_match | 整体 status |
|---|---|---|---|---|---|---|---|
| **`20-full-20261103T142246`** | **`126676734`** | **`manifest.tsv`（30 例）** | **30/30 通过** | **是（30 例 abort 全 `0`）** | **`0`** | **达标** | **通过（9/9 criteria）** |
| `20-full-20261102T000517` | `126542079` | 旧 20 例（VL=16 镜像） | 20/20 通过 | 是 | `0` | 达标 | 通过（旧口径） |
| `20-full-20261103T075552` | `126646321` | `manifest.t5g0.tsv`（4 例） | 4/4 通过 | 是 | `0` | 达标 | 通过（9/9 criteria） |
| `20-full-20261103T062432` | `126642005` | `manifest.r13.tsv`（6 例） | 6/6 通过 | 是 | `0` | 达标 | 未运行（清单无 perf 用例 ⇒ `metrics_three`/`t5_delta_latency` 只能记未运行） |
| `20-full-20261103T033328` | `126631414` | `manifest.perf3.tsv`（3 例） | 3/3 通过 | 是 | `0` | 达标 | 未运行（清单缺 g0 反例 ⇒ `no_empty_green` 未运行） |
| `20-smoke-20261103T032337` | `126630806` | 5 例冒烟 | 5/5 通过 | 是 | 未运行 | 达标 | 失败（`nm_exec_vdot` 命中 0 行：与 `10-build-emu.sh` 重写 `.so` 时间窗重叠） |
| `20-smoke-20261103T032017` | `126630485` | 仅 `vdot_mix` 1 例 | 1/1 通过 | 是 | 未运行 | 达标 | 未运行（仅 1 例，`smoke_classes` 缺 4 类） |

`0 ABORT` 的统计口径：逐份 JSON 的 `cases[].abort` 全部为 `"0"`，并由运行日志的 `ABORT=0` 行交叉确认。`142246` 的 30 例逐条状态见 `json/20-full-20261103T142246.cases.tsv`（30 行全 `通过 1 0 0`）。

## 3. 30 例清单里各例的自检通过串（`keys-20261103T142246/`，逐例实测）

| 类别 | 用例 | 自检通过串（实测命中） |
|---|---|---|
| vadd | `vadd-microbench` | `MicroBench PASS` |
| vdot-pos | `vdot_pos1/2/3` | `CASE vdot_posN: MATCH` |
| vdot-rand | `vdot_rand` | `RAND_SUMMARY groups=1024 mism=0 ab_bad=0` |
| vdot-neg | `vdot_neg1`、`vdot_neg_odd1/3/5/7` | `CASE <cid>: MATCH` |
| vdot-bound | `vdot_bound1..5` | `CASE <cid>: result=… expect=… hi=[0 0 0]` + `MATCH` |
| vdot-matrix | `vdot_matrix` | `MATRIX verdict=ALL_OK fails=0` |
| vdot-mix | `vdot_mix` | `MIX verdict=ALL_OK fails=0` |
| g0（反例） | `vdot_g0_badexp` | `CASE vdot_g0_badexp: MISMATCH`（被同一判据判负，`G0_CAUGHT=1`） |
| negative | `vdot_ill_{sew,lmul2,lmul4,lmul8,vm0,vstart,vill,vs}` | `HIT CRITICAL ERROR`（8/8 命中，哨兵 0、失配 0） |
| perf | `perf_vdot` / `perf_base` / `perf_vadd` / `perf_vmacc` | `PERF_VDOT/PERF_BASE/PERF_VADD/PERF_VMACC verdict=ALL_OK` |

## 4. 口径边界（下列结果不得计为通过）

1. **1102 的 20/20 是旧口径**：该作业早于 2026-11-02 20:56 的镜像重建（VL=16→8、均值→median），清单为旧 20 行；其 `L_vdot=6` / `T_kernel=289` 不代表当前口径。它的协同仿真结论（20/20、0 ABORT、delta=0）仍成立，性能数字不成立。
2. **`112401`（作业 `126664477`）的 28/30 已被 `142246` 取代**：那次 `vdot_rand`（自检串未命中）与 `vdot_ill_sew`（负例未陷入）失败，对应的是 13:37 之前的旧镜像；修复后 `142246` 30 例全部通过。两份 JSON 都保留在 `results/difftest/`，不删除。
3. **`20-smoke-20261103T032337` 的 `nm_exec_vdot` 未达标不是 NEMU 缺陷**：同一 `.so` 复跑 `nm` 稳定 2 行（见 `../3.1.1-nemu/evidence/nm-exec_vdot.txt`），根因是构建作业与 difftest 作业重叠。
4. ~~**无 30 例逐用例完整日志**~~ → **已回传（2026-11-05，2026-11-06 复核）**：`full-logs-20261103T142246/` 实存 30 份 `.log`（142,653,110 B）+ 30 份 `.gz`（4.09 MB）；按 `keys-20261103T142246/*.key.txt` 的 `# size=/sha256=` 逐份复算 → `ok=30 bad=0 total=30`。**打包形态（2026-11-06 已修）**：`.gitignore` 新增 `!stage3/3.1.2-difftest/full-logs-*/*.log.gz` ⇒ 30 份 `.gz` 现可直接 `git add`（实测 `git add -An` 命中 30 件）；裸 `.log` 137 MB 也会被 `git add -A` 一并暂存，交付介质吃紧时只加 `.gz` 即可（`gzip -dc` 逐份 sha256 与裸件同值，实测 `ok=30 bad=0`）。
5. 以上均为 QEMU 级 difftest（NEMU ref .so vs Verilator `build/emu`），不是硅片实测；平台为昆山 `kshcnormal`。
6. **`manifest.tsv` 与远端同名文件 sha256 不同**：本地冻结件 `a90d1071…`/30 行；远端 `test/manifest.tsv` **现为 `413b5796…`/31 行**（2026-11-06 远端实读复验），比冻结件**多一行 `perf_base_chain`**（`2026-11-04` 追加，未回退）。`142246` 运行时远端是 `make_manifest.sh` 把 `@IMG_DIR@` 展开后的 30 行版（当时哈希 `e12470e6…`），**与现在这份不同**。⇒ 该漂移**未收敛**：`perf` 类不在 smoke 白名单，24/24 选例不受影响；但远端再跑 `--full` 会选 31 例，「30/30」不能按当前远端清单复现。已登记。
7. **`perf_base_chain` 不在 30 例清单内**（且已不在 `design/verify/cases/manifest.tsv`）：该例由 `91-run-b3.sh` 独立作业实测——min 尺度 `126750763`（`verdict=ALL_OK`、`L_base_chain=16`，`results/difftest/b3/91-b3-20261104T092457.log`）与 **full 尺度 `126762127`**（`scale=full`、`samples=16000`、`verdict=ALL_OK`，`results/difftest/b3/91-b3-20261104T115624.log`）两轮均跑通；历史失败 `126749121`（600 s 超时、rc=124、只完成 round 0）与 `126758062`（共享节点 1:02:30 后取消）只作排障记录。**两轮数字都不能当作「31/31 全量通过」**——它们不是 30 例回归集的一部分，且口径为内部自设。
8. **2026-11-08 的 30 例 `--full` 复跑未生成结果**：退出码 1，`sacct` 无对应作业记录；同日扩容 224 例（`127194011`）与性能 4 次重复（`127196036`）完成。30/30 仍以 `20-full-20261107T104227.json`（`127137638`）为准。

## 5. 核对命令与输出（2026-11-04）

```
$ python3 -I -c "import json;d=json.load(open('results/difftest/20-full-20261103T142246.json'));print(d['status'],d['slurm_job_id'],d['regression_delta'],len(d['cases']),sum(1 for c in d['cases'] if c['status']=='通过'),sum(1 for c in d['cases'] if c['abort']!='0'))"
通过 126676734 0 30 30 0
$ ls stage3/3.1.2-difftest/keys-20261103T142246 | wc -l
30
$ grep -l 'HIT CRITICAL ERROR' stage3/3.1.2-difftest/keys-20261103T142246/vdot_ill_*.key.txt | wc -l
8
$ grep -c 'MISMATCH' stage3/3.1.2-difftest/keys-20261103T142246/vdot_g0_badexp.key.txt
1
$ grep -a 'PERF_BASE_CHAIN verdict' results/difftest/b3/91-b3-20261104T092457.log | tail -1
PERF_BASE_CHAIN verdict=ALL_OK vl=OK chain_free=OK chain_free_rounds=OK chain_free_alt=OK chain_free_alt_differs=yes samples=2000 rounds=4 scale=min(ladder/B3_skipped)
$ grep -vc '^#' design/verify/cases/manifest.tsv
30
$ sha256sum design/verify/cases/manifest.tsv stage3/3.1.2-difftest/manifest.tsv
a90d107118773ebb0de5c1518846680b174b03cf0eb0cdf8be333e582dddbab1  design/verify/cases/manifest.tsv
a90d107118773ebb0de5c1518846680b174b03cf0eb0cdf8be333e582dddbab1  stage3/3.1.2-difftest/manifest.tsv
# 注：grep -vc '^#' = 30（表头行以 '#' 开头被排除）；perf_base_chain 行已移除，数据行为 30。
# 核实数据行：awk 'NR>1 && $0!="" && $0 !~ /^#/{n++} END{print n}' design/verify/cases/manifest.tsv
$ awk 'NR>1 && $0!="" && $0 !~ /^#/{n++} END{print n}' design/verify/cases/manifest.tsv
30
```
