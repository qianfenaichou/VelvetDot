# 2.3.3 边界值测试

**结论：当前 30 例清单整份 `--full` 已全部通过（昆山作业 `126676734`，2026-11-03 14:22:46→14:51:47，`status=通过`、`30/30`、`regression_delta=0`），本类 5 个边界用例 `vdot_bound1/2/3/4/5` **全部 `通过`**（`CASE vdot_boundN: MATCH`，且 `hi=[0x00000000 0x00000000 0x00000000]` 五例全命中 = 高 96 位恒零实测），8 个合法性负例 `vdot_ill_{sew,lmul2,lmul4,lmul8,vm0,vstart,vill,vs}` 也全部 `通过`（`HIT CRITICAL ERROR` 1 次、无失配、无「未如期陷入」哨兵）。此前 `112401` 的 `vdot_ill_sew` 失败已由 13:13 用例补 `.4byte 0x3A002057` + 13:37 重建镜像解决。现行清单已扩到 31 行：第 31 例 `perf_base_chain`（`perf` 类，不属本类）于 2026-11-04 由作业 `126750763` 以 min 镜像单独实测（`verdict=ALL_OK`、`L_base_chain=16`；全量镜像作业 `126749121` 超时 rc=124），本类仍以 `142246` 的 30/30 为准。**

对应官方条目：`docx/02-赛题与评分细则.md:57`「2.3.3 边界值测试：基于香山仿真环境，验证边界值（如最大值、最小值、零等）的点积结果」。

## 1. 目录结构

| 路径 | 内容 |
|---|---|
| `runs/20-full-20261103T142246.{json,cases.tsv,log}` | **当前口径全部通过证据**（30 例整份） |
| `runs/126676734_full30.out` | 同一次作业的 Slurm stdout（与上一份 `.log` 逐字节相同） |
| `runs/20-full-2026110*.json`、`runs/20-smoke-*.json` | 历史作业原始 JSON / TSV（旧 20 例口径） |
| `CASES.tsv` | 本类用例跨作业汇总（36 行：5 个 bound 用例历史 23 行 + `142246` 的 5 行 + `142246` 的 8 个 negative 行） |
| `cases/vdot_bound{1..5}.20261103T142246.key.txt` | 五例判据行摘录（`CASE …: MATCH` + `result/expect/hi=` 三元组 + `HIT GOOD TRAP`） |
| `cases/vdot_ill_*.20261103T142246.key.txt`（8 份） | 8 个负例判据行（`HIT CRITICAL ERROR` + `HIT GOOD TRAP at pc = 0xe`） |
| `cases/vdot_bound1.20261102T000517.{key.txt,log.gz}` | 旧口径完整日志（解压 4.7 MB / 29 874 行），历史对照 |
| `src/vdot_bound1..5.c` | 5 个边界用例源码 |

## 2. 逐次结果（`CASES.tsv` 全量）

| 用例 | 通过 / 出现 | 作业 |
|---|---|---|
| `vdot_bound1` | 10 / 10 | `126538619` `126540844` `126541295` `126542079` `126642005` `126536502` `126536746` `126537392` `126630806` `126676734` |
| `vdot_bound2` | 8 / 8 | 除 `126642005`、`126630806` 外全部 |
| `vdot_bound3` | 8 / 8 | 同上 |
| `vdot_bound4` | 1 / 1 | `126676734`（**首次执行**） |
| `vdot_bound5` | 1 / 1 | `126676734`（**首次执行**） |
| `vdot_ill_{sew,lmul2,lmul4,lmul8,vm0,vstart,vill,vs}` | 各 1 / 1 | `126676734`（`vdot_ill_sew` **首次转绿**） |

权威作业 = `126676734` / `runs/20-full-20261103T142246.json`（`status=通过`、30/30、`regression_delta=0`、`no_empty_green=达标`）。

### 2.1 五例边界判据行（原样摘录，`cases/vdot_bound*.key.txt`）

```
CASE vdot_bound1: result=0x00020000 expect=0x00020000 hi=[0x00000000 0x00000000 0x00000000]
CASE vdot_bound2: result=0xFFFE0400 expect=0xFFFE0400 hi=[0x00000000 0x00000000 0x00000000]
CASE vdot_bound3: result=0x00000000 expect=0x00000000 hi=[0x00000000 0x00000000 0x00000000]
CASE vdot_bound4: result=0x0001F808 expect=0x0001F808 hi=[0x00000000 0x00000000 0x00000000]
CASE vdot_bound5: result=0x00000001 expect=0x00000001 hi=[0x00000000 0x00000000 0x00000000]
```

**高 96 位恒零**：五例 `hi=[0x00000000 0x00000000 0x00000000]` 全部命中——这是「高 96 位恒零断言」在当前口径下的实测证据（旧口径只有 `vdot_bound1` 一处）。

### 2.2 八个负例判据行（原样摘录，`cases/vdot_ill_*.key.txt`）

```
Core 0 dump: [31mHIT CRITICAL ERROR: please check if software cause a double trap.
[0mCore 0: [32mHIT GOOD TRAP at pc = 0xe
```

逐例复核（远端 `~/core/results/difftest/cases/<cid>.20261103T142246.log`，`grep -ac` 实测）：

| 用例 | `HIT CRITICAL ERROR` | 「未如期陷入非法指令」哨兵 | `diff REF`/`Different operands` | 判定 |
|---|---|---|---|---|
| `vdot_ill_sew` | 1 | 0 | 0 | 通过 |
| `vdot_ill_lmul2` | 1 | 0 | 0 | 通过 |
| `vdot_ill_lmul4` | 1 | 0 | 0 | 通过 |
| `vdot_ill_lmul8` | 1 | 0 | 0 | 通过 |
| `vdot_ill_vm0` | 1 | 0 | 0 | 通过 |
| `vdot_ill_vstart` | 1 | 0 | 0 | 通过 |
| `vdot_ill_vill` | 1 | 0 | 0 | 通过 |
| `vdot_ill_vs` | 1 | 0 | 0 | 通过 |

判据逻辑见 `core-package/scripts/20-run-difftest.sh:229-246`（negative 类：`CRIT≥1` ∧ `MISMATCH=0` ∧ `ABORT=0` ∧ 哨兵=0）。

## 3. 边界值覆盖（期望值本机复算，`python3 -c "sum(...)"` 逐项 int64）

| 用例 | 输入（vs1 × vs2，lane 0–7） | S | `vd[31:0]` | 判据 |
|---|---|---|---|---|
| `vdot_bound1` | 全 −128 × 全 −128 | **131072** | `0x00020000` | 19 位有符号**上边界**（`8×128×128`）；实测 `result=0x00020000 expect=0x00020000` **MATCH**，`hi=[0,0,0]` |
| `vdot_bound2` | `{-128×4, 127×4}` × `{127×4, −128×4}` | **−130048** | `0xFFFE0400` | 最小负和 |
| `vdot_bound3` | 全 0 × `{127,−128,1,−1,5,−5,100,−100}` | **0** | `0x00000000` | 零边界（一侧全零） |
| `vdot_bound4` | 全 +127 × 全 +127 | **129032** | `0x0001F808` | 最大正和 |
| `vdot_bound5` | 交错极值（±127/±128/±1） | **1** | `0x00000001` | 交错极值 |

## 4. 口径保留（不得当通过）

1. **`112401` 的 `vdot_ill_sew` 失败只对应旧镜像**：那次 `SENTINEL=1`、`CRIT=0`（`SEW=16` 未被判非法）；13:13 用例在 e16 之后补发 `.4byte 0x3A002057`、13:37 重建镜像后，`126676734` 跑的是新镜像，实测 `CRIT=1`、哨兵 0、`ABORT=0`。旧失败不再代表当前状态。
2. **逐用例完整日志已回传**：`../3.1.2-difftest/full-logs-20261103T142246/`（30 例全量，含 8 个 `vdot_ill_*` 与 5 个 `vdot_bound*`；`ok=30 bad=0`）；本目录仍保留判据行摘录。
3. **波形**：本目录无本用例波形；`vdot.vv` 自身波形见 `../2.2-rtl/wave/`（清单外 `vdot_wave` 用例，作业 `126875390`），**不能**当作 bound 用例的波形证据。
4. **六条合法性负例归属**：它们属 `negative` 类（`manifest.tsv` 第 18–25 行），2.3.3 的验收判据覆盖这 8 例，故本目录同时收录其判据行。
5. **语义裁决的外部依据**（2026-11-06 补注、2026-11-07 对齐判定用词，**本目录证据件未改动**）：本类五例的 `hi=[0x00000000 0x00000000 0x00000000]` 断言"高 96 位恒零"，其外部判定**不是**"RVV 标准行为"——见 `design/SPEC.md` §3.4：`3.4.3`（`norm:vreduction_tail_policy`，同伴 `norm:vmask_agn_op` `:1063-1066`）判定为**偏离基线**（字面冲突），理由是"自定义编码全写指令"声明 + 官方伪代码无条件 `vd[1..]=0`；`3.4.5` 汇总表第 ② 行只把 32 位容器判**相容**（惯例/提案），**支撑**仅限 `vd==vs` 重叠合法性（不涉清零）。⇒ 答辩引用本目录五例时，须同时引 SPEC §3.4.3 的偏离声明。

## 5. 核对命令与输出（2026-11-04 实跑）

```
$ grep -c "^20-full-20261103T142246" stage2/2.3.3-bound/CASES.tsv
13
$ grep -c 'hi=\[0x00000000 0x00000000 0x00000000\]' stage2/2.3.3-bound/cases/vdot_bound*.20261103T142246.key.txt
# 5 个文件各 1 行
$ grep -l 'HIT CRITICAL ERROR' stage2/2.3.3-bound/cases/vdot_ill_*.20261103T142246.key.txt | wc -l
8
$ grep -c 'vdot_ill_sew' results/difftest/20-full-20261103T142246.cases.tsv
1
$ grep -a 'PERF_BASE_CHAIN verdict' results/difftest/b3/91-b3-20261104T092457.log | tail -1
PERF_BASE_CHAIN verdict=ALL_OK vl=OK chain_free=OK chain_free_rounds=OK chain_free_alt=OK chain_free_alt_differs=yes samples=2000 rounds=4 scale=min(ladder/B3_skipped)
```
