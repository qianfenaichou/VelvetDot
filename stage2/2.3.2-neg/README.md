# 2.3.2 负数点积测试

**结论：该次 30 例清单整份 `--full` 已全部通过（昆山作业 `126676734`，2026-11-03 14:22:46→14:51:47，`status=通过`、`30/30`、`regression_delta=0`；**清单曾短暂加入 `perf_base_chain` 成 31 行，现行 `design/verify/cases/manifest.tsv` 为 30 行（`sha256 a90d1071…`）；该例全量镜像未进入 `--full`（作业 `126749121` 600 s 超时、rc=124、只完成 round 0），但 min 镜像已由作业 `126750763` 单独实测（`verdict=ALL_OK`、`L_base_chain=16`，min 口径）；故 `--full` 口径是 30/30。**），本类 5 例 `vdot_neg1` + `vdot_neg_odd1/3/5/7` 全部 `通过`（`GOOD TRAP=1`、`ABORT=0`），每例日志实命中 `CASE vdot_neg*: MATCH`——即「奇数负 lane 数 1/3/5/7」判据首次拿到实测证据。`vdot_neg2`/`vdot_neg3` 已不在当前用例集，只作历史对照。**

对应官方条目：`docx/02-赛题与评分细则.md:56`「2.3.2 负数点积测试：基于香山仿真环境，验证含负数输入的点积结果」。

## 1. 目录结构

| 路径 | 内容 |
|---|---|
| `runs/20-full-20261103T142246.{json,cases.tsv,log}` | **当前口径全部通过证据**（30 例整份） |
| `runs/126676734_full30.out` | 同一次作业的 Slurm stdout（与上一份 `.log` 逐字节相同） |
| `runs/20-full-2026110*.json`、`runs/20-smoke-*.json` | 历史作业原始 JSON / TSV（旧 20 例口径，含已下线的 `neg2/neg3`） |
| `CASES.tsv` | 本类用例跨作业汇总（28 行；末 5 行为 `142246` 的 `neg1` + `neg_odd1/3/5/7`） |
| `cases/vdot_neg{1,odd1,odd3,odd5,odd7}.20261103T142246.key.txt` | 五例判据行摘录（`CASE <cid>: MATCH` + `HIT GOOD TRAP`），含源日志路径、字节数、sha256 |
| `src/vdot_neg1.c` | 全负积：`av={-1..-8}`、`bv=全 1` ⇒ S=−36 |
| `src/vdot_neg_odd1/3/5/7.c` | 奇数个负积 n=1/3/5/7：`a` 前 k 个为 −7、其余 +5，`b` 全 +3（专抓符号扩展 bug） |

## 2. 逐次结果（`CASES.tsv` 全量）

| 用例 | 通过 / 出现 | 作业 |
|---|---|---|
| `vdot_neg1` | 10 / 10 | `126538619` `126540844` `126541295` `126542079` `126642005` `126536502` `126536746` `126537392` `126630806` `126676734` |
| `vdot_neg_odd1/3/5/7` | 各 1 / 1 | `126676734`（**首次执行**，此前从未在硬件跑过） |
| `vdot_neg2` | 7 / 7 | `126538619` `126540844` `126541295` `126542079` `126536502` `126536746` `126537392`（**均已不是当前用例集**） |
| `vdot_neg3` | 7 / 7 | 同上（**均已不是当前用例集**） |

权威作业 = `126676734` / `runs/20-full-20261103T142246.json`（`status=通过`、30/30、`regression_delta=0`、`no_empty_green=达标`）。该 JSON 的 `manifest.rows=30` 对应**当时**的 30 行清单；清单曾短暂为 31 行（`perf_base_chain` 全量镜像未跑；min 镜像 `126750763` 已单独实测 `L_base_chain=16`，min 口径），现行 `manifest.tsv` 为 30 行（`sha256 a90d1071…`），两者不可混引。

### 2.1 本类 5 例在 `142246` 的判据行（原样摘录，见 `cases/*.key.txt`）

```
CASE vdot_neg1: MATCH
CASE vdot_neg_odd1: MATCH
CASE vdot_neg_odd3: MATCH
CASE vdot_neg_odd5: MATCH
CASE vdot_neg_odd7: MATCH
```

五例同时满足 `HIT GOOD TRAP` 且 `ABORT=0`（`runs/20-full-20261103T142246.cases.tsv` 第 6-10 行 `通过 1 0 0`）。

## 3. 关键口径问题（必读）

1. **`vdot_neg2`/`vdot_neg3` 已被替换，源码与镜像不存在**：`ls design/verify/cases/ | grep -E "neg2|neg3"` → **0 命中**；当前 `design/verify/cases/manifest.tsv` 的 `vdot-neg` 行只有 `vdot_neg1` + `vdot_neg_odd1/3/5/7`。⇒ 那 7 次 `通过` 对应的镜像**已无法重建**，只能作为历史证据引用，**不能当作当前口径的覆盖**。
2. **新负数用例已执行**：`vdot_neg_odd1/3/5/7` 在 `126676734` 全部 `通过` 且命中 `CASE …: MATCH`；本文件先前记的「从未执行」结论不再成立。
3. **逐用例完整日志已回传**：`../3.1.2-difftest/full-logs-20261103T142246/`（30 例全量，`ok=30 bad=0`）；本目录仍保留判据行摘录。
4. **波形**：本目录无本用例波形；`vdot.vv` 自身波形见 `../2.2-rtl/wave/`（清单外 `vdot_wave` 用例，作业 `126875390`），**不能**当作 neg 用例的波形证据。
5. **语义裁决的外部依据**（2026-11-06 补注、2026-11-07 对齐判定用词，**本目录证据件未改动**）：本类用例靠"奇数个负 lane"抓符号扩展，其位宽前提（19 位有符号内部和、`vd[31:0]=sext32(S)`）的外部判定见 `design/SPEC.md` §3.4：`3.4.5` 第 ① 行把 19 位判为**无外部依据（算术推导）、与外部 32 位容器惯例相容**，第 ② 行的 32 位容器与 `sext32` 写回判**相容**（`vqdot` 为未批准提案、`SDOT`/`VPDPBUSD` 为厂商 ISA，属惯例/提案，非规范字面支撑；**支撑**仅限 `vd==vs` 重叠合法性，不涉容器位宽）。⇒ 读 `CASE …: MATCH` 时，语义出处引 SPEC §3.4，不得把 19 位写成"行业标准"。

## 4. 数据要点

- `vdot_neg1` 期望 S = −(1+2+…+8) = **−36** = `0xFFFFFFDC`（按 ALGORITHM §3.1 算法 B 逐项 int64 累加后截 32 位补码；本机 `python3 -c "sum(...)"` 复算 = −36）。
- `vdot_neg_oddN` 期望 S = `N×(−7×3) + (8−N)×(5×3)` = `−21N + 120 − 15N`；N=1/3/5/7 ⇒ **+84 / +12 / −60 / −132**（`0x00000054 / 0x0000000C / 0xFFFFFFC4 / 0xFFFFFF7C`，本机复算）。
  ⇒ 这组用例的「奇数负 lane」判据只对**求和符号**敏感，N=1/3 结果为正、N=5/7 为负。

## 5. 核对命令与输出（2026-11-04 实跑）

```
$ grep -c "^20-full-20261103T142246" stage2/2.3.2-neg/CASES.tsv
5
$ grep -c 'CASE vdot_neg_odd7: MATCH' stage2/2.3.2-neg/cases/vdot_neg_odd7.20261103T142246.key.txt
1
$ grep -c 'vdot_neg_odd7' results/difftest/20-full-20261103T142246.cases.tsv
1
$ grep -a 'PERF_BASE_CHAIN verdict' results/difftest/b3/91-b3-20261104T092457.log | tail -1
PERF_BASE_CHAIN verdict=ALL_OK vl=OK chain_free=OK chain_free_rounds=OK chain_free_alt=OK chain_free_alt_differs=yes samples=2000 rounds=4 scale=min(ladder/B3_skipped)
```
