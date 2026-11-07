# 2.3.1 正数点积测试

**结论：当前 30 例清单整份 `--full` 已全部通过（昆山作业 `126676734`，2026-11-03 14:22:46→14:51:47，`status=通过`、`30/30`、`regression_delta=0`），本类 4 例 `vdot_pos1`/`vdot_pos2`/`vdot_pos3`/`vdot_rand` 全部 `通过`（`GOOD TRAP=1`、`ABORT=0`），且各自的自检通过串在日志里实命中：`CASE vdot_posN: MATCH`、`RAND_SUMMARY groups=1024 mism=0 ab_bad=0`。此前 `112401` 的 `vdot_rand` 失败已由 13:04 的用例修复 + 13:37 镜像重建解决。现行清单已扩到 31 行：第 31 例 `perf_base_chain`（`perf` 类，不属本类）于 2026-11-04 由作业 `126750763` 以 `perf_base_chain_min.bin` 单独实测（`verdict=ALL_OK`、`L_base_chain=16`，min 口径；全量镜像作业 `126749121` 超时 rc=124），本类 4 例仍以 `142246` 的 30/30 为准，两者不混引。**

对应官方条目：`docx/02-赛题与评分细则.md:55`「2.3.1 正数点积测试：基于香山仿真环境，验证正数输入的点积结果」。

## 1. 目录结构

| 路径 | 内容 |
|---|---|
| `runs/20-full-20261103T142246.{json,cases.tsv,log}` | **当前口径全部通过证据**（30 例整份；本类 4 例状态与自检串见 §2） |
| `runs/126676734_full30.out` | 同一次作业的 Slurm stdout（与上一份 `.log` 逐字节相同） |
| `runs/20-full-2026110*.json`、`runs/20-smoke-*.json` | 历史作业原始 JSON / TSV（未裁剪，可复核；旧 20 例口径） |
| `CASES.tsv` | 本类用例跨作业汇总（22 行；末 4 行为 `142246` 的 pos1/pos2/pos3/rand） |
| `cases/vdot_pos{1,2,3}.20261103T142246.key.txt`（3 份） | 三例的判据行摘录（`CASE vdot_posN: MATCH` + `HIT GOOD TRAP`），含源日志路径、字节数与 sha256 |
| `cases/vdot_rand.20261103T142246.key.txt` | 随机用例判据行（`RAND_SUMMARY groups=1024 mism=0 ab_bad=0`） |
| `cases/vdot_rand.20261102T000517.{key.txt,log.gz}` | 旧口径随机用例完整日志（解压 4.7 MB / 29 880 行），历史对照 |
| `src/vdot_pos1.c`、`src/vdot_pos2.c`、`src/vdot_pos3.c`、`src/vdot_rand.c` | 用例源码（期望值由 `design/verify/cases/gen.py` 按 ALGORITHM §3.1 算法 B 独立算出，不经归约树） |

## 2. 逐次结果（`CASES.tsv` 全量）

| 用例 | 通过 / 出现 | 覆盖的作业 |
|---|---|---|
| `vdot_pos1` | 10 / 10 | `126538619` `126540844` `126541295` `126542079` `126642005` `126536502` `126536746` `126537392` `126630806` `126676734` |
| `vdot_pos2` | 8 / 8 | 同上，除 `126642005`（该清单只含 pos1）与 `126630806` |
| `vdot_pos3` | 1 / 1 | `126676734`（**首次执行**，此前从未在硬件跑过） |
| `vdot_rand` | 3 / 3 | `126541295`、`126542079`（旧镜像）、`126676734`（**当前镜像**） |

权威作业 = `126676734` / `runs/20-full-20261103T142246.json`：`status=通过`、`cases_pass=30/30`、`no_empty_green=达标`（自检串 21/21 命中；空绿反例捕获 1/1）、`regression_delta=0`。

### 2.1 本类 4 例在 `142246` 的判据行（原样摘录，见 `cases/*.key.txt`）

```
# vdot_pos1/2/3
CASE vdot_pos1: MATCH
CASE vdot_pos2: MATCH
CASE vdot_pos3: MATCH
# vdot_rand
RAND_SUMMARY groups=1024 mism=0 ab_bad=0
```

四例同时满足 `HIT GOOD TRAP` 且 `ABORT=0`（`runs/20-full-20261103T142246.cases.tsv` 第 2-5 行 `通过 1 0 0`）。

## 3. 数据要点（从 `key.txt` 与 `src/*.c` 读得）

- `vdot_pos1`：`av={1..8}`、`bv=全 1` ⇒ 期望 S=36；`vdot_pos2`：`bv` 交替 `±1` ⇒ 混合符号；`vdot_pos3`：`{127,-128,1,-1,5,-5,100,-100}` × 全 1（±127/±128 单元素边界）。
- `vdot_rand`：`seed=42`、1024 组、`mism=0`、`ab_bad=0`；当前镜像的 `142246` 运行同样 `mism=0 ab_bad=0`。
- 三条用例都用 `li t1, 8` + `vsetvli zero, t1, e8,m1, ta, ma`（VL=8），与当前 VL=8 口径一致（`design/verify/cases/vdot_pos1.c:15-16`）。

## 4. 口径保留（不得当通过）

1. **`112401` 的 `vdot_rand` 失败只对应旧镜像**：那次 `GOOD TRAP + MISMATCH=0` 但未命中自检串；13:04 用例补 VS 使能序言、13:37 重建镜像后，`126676734`（14:22）跑的是**新镜像**（远端 `~/core/test/bin/vdot_rand.bin` md5 `3f8eda306ccfb8dd3a3f536ae5cf758d`，与本机 `design/verify/cases/vdot_rand.bin` 同值）。旧失败不再代表当前状态。
2. **逐用例完整日志已回传（2026-11-05 回传，2026-11-06 复核）**：`../3.1.2-difftest/full-logs-20261103T142246/` 有 `142246` 全部 30 例的完整 `.log` + `.gz`（本目录的 `vdot_pos1/2/3`、`vdot_rand` 均在其中；`gz` 解压后 sha256 对 `keys-*/` 记录 `ok=30 bad=0`）；本目录仍保留 `cases/*.key.txt` 判据行摘录（含源路径 + sha256 + 字节数）。
3. **波形**：本目录**无本用例波形**；`vdot.vv` 的**自身波形**已于 2026-11-05 产出在 `../2.2-rtl/wave/`（作业 `126875390`，用例是清单外的 `vdot_wave`，**不是**本目录的 pos 用例）⇒ 本目录验收项「日志 + 波形」中的波形位仍由清单外用例代证，如实记；1.3 的 `vadd.vv` 波形不能替代 vdot 的波形证据。
4. **镜像一致性**：`design/verify/cases/{vdot_rand,vdot_mix,vdot_ill_sew}.bin` 在 git 工作树里是 `M`（13:37 重建后入库版本已更新），与远端 `~/core/test/bin/` 的同名文件 md5 逐份相同（实测 36/36 命中）。
5. **语义裁决的外部依据**（2026-11-06 补注、2026-11-07 对齐判定用词，**本目录证据件未改动**）：本类用例断言的"结果写 `vd[31:0]`、高 96 位清零"两项，其外部依据、两家同校收敛（其一为跟帖确认，非独立多方）与判定强度见 `design/SPEC.md` §3.4（`3.4.1` `norm:vreduction_vl_0` 属**偏离基线**、`3.4.5` 汇总表第 ② 行 32 位容器判**相容**（惯例/提案，非规范字面支撑），**支撑**仅限 `vd==vs` 重叠合法性）；`vl` 变化覆盖见 `vdot_matrix` 类（本类固定 `vl=8`，不在此列）。读本目录的 `key.txt` 判据行时，语义出处以 SPEC §3.4 为准，**不要**把"高 96 位恒零"当成 RVV 标准行为（SPEC §3.4.3 判定为**偏离基线**）。

## 5. 核对命令与输出（2026-11-04 实跑）

```
$ python3 -I -c "import json;d=json.load(open('results/difftest/20-full-20261103T142246.json'));print(d['status'],d['slurm_job_id'],d['started_at'],d['ended_at'])"
通过 126676734 2026-11-03T14:22:46+0800 2026-11-03T14:51:47+0800
$ grep -c 'RAND_SUMMARY groups=1024 mism=0 ab_bad=0' stage2/2.3.1-pos/cases/vdot_rand.20261103T142246.key.txt
1
$ grep -c 'CASE vdot_pos3: MATCH' stage2/2.3.1-pos/cases/vdot_pos3.20261103T142246.key.txt
1
$ grep -a 'PERF_BASE_CHAIN verdict' results/difftest/b3/91-b3-20261104T092457.log | tail -1
PERF_BASE_CHAIN verdict=ALL_OK vl=OK chain_free=OK chain_free_rounds=OK chain_free_alt=OK chain_free_alt_differs=yes samples=2000 rounds=4 scale=min(ladder/B3_skipped)
```
