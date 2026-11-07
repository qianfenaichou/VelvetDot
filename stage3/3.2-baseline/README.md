# 3.2 基线功能实现（B1 / B2 组合指令序列）

> 计划完成日：2026-11-03（非官方截止日）
> 结论：**新口径 B1/B2 已在当前 30 例整份 `--full` 里实测并通过自检**——`json/20-full-20261103T142246.json`（作业 `126676734`）`metrics[]` 给 **B1 = 6 cyc/dot、B2 = 9 cyc/dot**，且用例自报 `PERF_BASE verdict=ALL_OK B1=OK B2=OK b2_not_vl4=yes discriminates=yes want=0x00000008 want_vl4=0x00000012`——即 B2 的 `e32,m2`（VLMAX=8）修复与「数据可分辨 vl=8/vl=4」两条自检都成立。**B3 已测（2026-11-04）**：`B3 = 11 cyc/op`（2016 ops、`result=0x00000008` = 期望、`not_vl4=yes`），出处 `results/difftest/b3/91-b3-20261104T115624.log`（作业 `126762127`，`scale=full`、`b3=OK`）；**只进敏感性分析、不作分母、不与任何链相减**。注意：B3 的实现落在 `design/verify/cases/perf_base_chain.c` 的 `B3_ONCE()`，**不在** `perf_base.c`（`perf_base.c` 仍只有 `b1_once`/`b2_once`）。此前记「B3 未测」依据的 `126750763`（`scale=min(ladder/B3_skipped)`）是 min 尺度作业，已被 `126762127` 取代。

## 1. 目录内容

| 路径 | 内容 |
|---|---|
| `json/20-full-20261103T142246.{json,log,cases.tsv}` | **当前口径**：30 例整份 `--full`（作业 `126676734`），`metrics[]` 含 B1/B2，`case_id=perf_base` |
| `json/20-full-20261102T000517.{json,log,cases.tsv}` | 旧口径（作业 `126542079`，20 例，`B1=6`/`B2=9`，来自 `e32,m1` 版源码） |
| `perf_base.20261102T000517.log` | 旧口径 `perf_base` 完整用例日志（4.75 MB，md5 `1a0c56c0…` 与远端一致） |
| `evidence/perf_base.20261103T142246.key.txt` | **新口径**判据行摘录（`PERF_BASE verdict=ALL_OK …` + `HIT GOOD TRAP`），含源日志 sha256 |
| `evidence/metrics-extract.txt` | 旧口径的指标抽取与可分辨性手算记录 |
| `sources/perf_base.worktree.c` | 产生**新口径** B1/B2 的源码（`e32,m2` + `data_discriminates`/`b2_not_vl4` 自检），与 `design/verify/perf/perf_base.c` **逐字节相同**（`diff -q` 无输出） |
| `sources/perf_base.HEAD-c611d43.c` | 旧口径源码（`e32,m1`，`result=0xA` 不可分辨 vl） |

## 2. 实测数字与出处

| 指标 | 值 | JSON 路径 | 用例日志原始行 |
|---|---|---|---|
| `B1` | **6** cyc/dot | `results/difftest/20-full-20261103T142246.json` → `metrics[]`（`{"name":"B1","value":"6","case_id":"perf_base"}`） | `PERF B1: ops=2000 cycles=12002 cycles_per_op=6 result=0x00000008 want=0x00000008 match=OK`；`VDOT_METRIC B1 6` |
| `B2` | **9** cyc/dot | 同上（`{"name":"B2","value":"9","case_id":"perf_base"}`） | `PERF B2: ops=2000 cycles=19335 cycles_per_op=9 result=0x00000008 want=0x00000008 not_vl4=yes match=OK`；`VDOT_METRIC B2 9` |
| `B3` | **11** cyc/op（仅敏感性分析，不作分母） | `results/difftest/b3/91-b3-20261104T115624.log` → `PERF B3: ops=2016 cycles=22457 cycles_per_op=11 result=0x00000008 want=0x00000008 not_vl4=yes match=OK` / `VDOT_METRIC B3 11`（作业 `126762127`，`scale=full`） | 实现不在 `sources/perf_base.worktree.c`（该文件只有 `b1_once`/`b2_once`），而在 `design/verify/cases/perf_base_chain.c` 的 `B3_ONCE()`；口径为**内部自设**，不与 B1/B2 做同法差值（B3 不丢暖机，B1/B2 无暖机） |

序列定义（`sources/perf_base.worktree.c:2-3` 注释、`:68` `b1_once`、`:84` `b2_once`）：

- **B1** = `vwmul.vv` + `vwredsum.vs`（2 条向量计算 / 6 宏 / 11 uop）
- **B2** = `vwmul.vv` + `vwadd.vx`（widen 到 32）+ `vredsum.vs`（3 条向量计算 / 8 宏 / 17 uop）

口径：`VL=8`、`N=2000` 次、整段墙钟相除（`sources/perf_base.worktree.c` 的 `#define N 2000`）。

## 3. 新口径的两条自检（相对旧口径的关键差别）

1. **B2 配置已修正**：`sources/perf_base.worktree.c:95` 是 `vsetvli zero, t2, e32, m2, ta, ma`（VLMAX=8），旧版是 `e32,m1`（VLMAX=4，`avl=8` 被钳到 4 ⇒ 只归约前 4 lane）。实测 `not_vl4=yes` 即「读回值 ≠ 只归约前 4 lane 的值」。
2. **数据可分辨 vl=8 与 vl=4**：`want=0x00000008`（全 8 lane 点积）、`want_vl4=0x00000012`（前 4 lane），二者不等 ⇒ `discriminates=yes`。旧数据下两者都是 `0xA`，`match=OK` 无法证伪误配。

## 4. 口径边界（下列结果不得计为通过）

1. **B1/B2 是「每点开销」不是延迟**：它们是单 dot 整段序列的吞吐口径（`cyc/dot`），**不能**与 `L_vdot` 这类依赖链延迟相减或互替（`design/HARD-DESIGN.md` §4.1）。
2. **新旧值数值相同但含义不同**：`142246` 与 `000517` 都给 `6 / 9`，但前者跑的是 `e32,m2` + 可分辨数据的新镜像（`design/verify/cases/perf_base.bin` md5 `b5a4eeff…`，远端 `~/core/test/bin/perf_base.bin` 同值），后者是 `e32,m1` 旧镜像。引用时必须注明是哪一份。
3. **B3 已测（2026-11-04）**：`B3 = 11 cyc/op`（作业 `126762127`，`scale=full`、`b3=OK`、`not_vl4=yes`，`results/difftest/b3/91-b3-20261104T115624.log`）。实现位置是 `design/verify/cases/perf_base_chain.c:301` 的 `B3_ONCE()`，**不是** `perf_base.c`；`metrics[]`（difftest 的 30 例 JSON）里也没有 B3 行——B3 不进 30 例回归清单，只由 `91-run-b3.sh` 独立作业产出。**使用约束**：B3 只进敏感性分析、不作分母、不与任何链相减。此前「B3 未测」的结论基于 min 尺度作业 `126750763`（`scale=min(ladder/B3_skipped)`），已被 full 尺度作业 `126762127` 取代。
4. **逐用例完整日志已回传（2026-11-06 复核更正）**：`perf_base.20261103T142246.log` 现已在库 —— `stage3/3.1.2-difftest/full-logs-20261103T142246/perf_base.20261103T142246.log`（4,755,057 B，`sha256sum` → `c440982b5498…`，与该目录 `keys-20261103T142246/perf_base.key.txt:3` 记录的 `size=4755057 sha256=c440982b…` 同值）。本目录另保留 `evidence/perf_base.20261103T142246.key.txt` 摘录（判据行口径，便于速读）；旧口径的完整日志同样在库（`perf_base.20261102T000517.log`）。

## 5. 核对命令与输出（2026-11-04）

```
$ python3 -I -c "import json;d=json.load(open('results/difftest/20-full-20261103T142246.json'));print([(m['name'],m['value']) for m in d['metrics'] if m['case_id']=='perf_base'])"
[('B1', '6'), ('B2', '9')]
$ cat stage3/3.2-baseline/evidence/perf_base.20261103T142246.key.txt
# case=perf_base run=20261103T142246
# src=/public/home/$USER/core/results/difftest/cases/perf_base.20261103T142246.log
# size=4755057 sha256=f53aab43260a7348893e7d25d496b48cf8ecf1ad05db5c7ec5e59bc0a28f9ca2
## 判据行（原样）
PERF_BASE verdict=ALL_OK B1=OK B2=OK b2_not_vl4=yes discriminates=yes want=0x00000008 want_vl4=0x00000012
Core 0: HIT GOOD TRAP at pc = 0x80000406
$ diff -q stage3/3.2-baseline/sources/perf_base.worktree.c design/verify/perf/perf_base.c && echo SAME
SAME
$ grep -a 'PERF_BASE_CHAIN verdict' results/difftest/b3/91-b3-20261104T092457.log | tail -1
PERF_BASE_CHAIN verdict=ALL_OK vl=OK chain_free=OK chain_free_rounds=OK chain_free_alt=OK chain_free_alt_differs=yes samples=2000 rounds=4 scale=min(ladder/B3_skipped)
$ grep -ac 'B3_skipped' results/difftest/b3/91-b3-20261104T092457.log
2
$ grep -aE '^(PERF B3|VDOT_METRIC B3)' results/difftest/b3/91-b3-20261104T115624.log
PERF B3: ops=2016 cycles=22457 cycles_per_op=11 result=0x00000008 want=0x00000008 not_vl4=yes match=OK
VDOT_METRIC B3 11
PERF B3: ops=2016 cycles=22457 cycles_per_op=11 result=0x00000008 want=0x00000008 not_vl4=yes match=OK
VDOT_METRIC B3 11
# ↑ 每行出现两次：91-run-b3.sh 把 grep 结果又 tee -a 回同一份日志（脚本行为，不是两轮测量）
$ grep -a 'PERF_BASE_CHAIN verdict' results/difftest/b3/91-b3-20261104T115624.log | tail -1
PERF_BASE_CHAIN verdict=ALL_OK vl=OK chain_free=OK chain_free_rounds=OK chain_free_alt=OK chain_free_alt_differs=yes ladder=OK ladder_alt=OK ladder_alt_differs=yes b3=OK b3_not_vl4=yes discriminates=yes samples=16000 rounds=8 scale=full
```
