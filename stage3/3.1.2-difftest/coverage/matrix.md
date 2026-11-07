# 3.1.2 · vdot 覆盖率矩阵（30 例主清单 × 29 coverpoints + extra 套件）

> 用途：**要证明「测试覆盖了哪些功能点、哪些没覆盖」**、或要给 3.3 报告补「功能验证有效性」的量化证据时读本文。
> 本文只做三件事：给覆盖矩阵、给缺口与补测建议、给可复算的生成命令。语义/编码正文在 `design/SPEC.md`，验证算法在 `design/ALGORITHM.md`。
> 证据等级：【实测】= 本次命令输出或存量日志串；【静态】= 二进制/源码扫描；【未运行】= 没有跑过，不得计为通过。
> **路径说明**：3.1.2 的目录名为 `stage3/3.1.2-difftest/`（`stage3/README.md:9`）；为兼顾 `stage3/3.1.2/coverage/matrix.md` 这一字面路径，另建符号链接 `stage3/3.1.2 -> 3.1.2-difftest`（`readlink -f` 指向同一文件，无第二份副本），正文存放于此。

---

## 0. 口径与生成方式（先读这里，防误读）

| 项 | 口径 |
|---|---|
| 覆盖对象 | `vdot.vv`（SEW=8 / LMUL=1 / K=8 单结果）；**不是**整核覆盖率 |
| 功能覆盖来源 | 30 例主清单的**存量逐用例日志**（`stage3/3.1.2-difftest/full-logs-20261103T142246/`，作业 `126676734`，30/30 通过）+ 30 个 `.bin` 的**二进制编码扫描** + `.c` 源码静态事实 |
| 结构覆盖（RTL line/toggle） | **【未运行（实跑受阻）】**：覆盖 emu 已重建，但覆盖构建 + `--diff` 在用例退出段 SIGSEGV（rc=139）、`.coverage.dat` 0 字节；定位与重跑见 §6 |
| 采样域 | `legal` = 只采 `trap==0` 的 vdot（对应 ACT4 `iff (ins.trap == 0)`）；`trap` = 只采非法陷入的 vdot。**负例不向 legal 域贡献**。**例外：F28 是 bin 级寄存器索引空间，按「真实发射过的编码」统计（含负例编码），其合法子域见 §3 注释** |
| 状态定义 | `covered` = ≥2 例命中；`thin` = 仅 1 例（命中但回归脆弱）；`partial` = 只在部分 bin 上命中；`gap` = 0 命中 |
| 格符号 | `●` hit（该例在本 CP 上有独立证据）/ `◐` partial（部分 bin 或只有 `--no-diff` 自检）/ `✗` miss（该例具备条件但未命中）/ `—` na（不发射 vdot / 域不匹配） |
| 生成器 | `stage3/3.1.2-difftest/coverage/gen_hits.py`（本目录）；产物 `hits.tsv`（870 格长表）、`summary.tsv`、`regspace.tsv` |
| ACT4 出处 | `std-vec:L` = `coverpoints/general/RISCV_coverage_standard_coverpoints_vector.svh:L`；`Vx8:L` = `coverpoints/unpriv/Vx8_coverage.svh:L`（commit `8b9dded…`，分支 act4） |

**复算命令（零机时，本地）**：

```bash
python3 -I stage3/3.1.2-difftest/coverage/gen_hits.py \
  --manifest design/verify/cases/manifest.tsv \
  --logs stage3/3.1.2-difftest/full-logs-20261103T142246 \
  --log-suffix .20261103T142246.log --bins design/verify/cases \
  --out stage3/3.1.2-difftest/coverage
# → cases=30 cps=29 cells=870 / coverage: covered=11 thin=15 partial=2 gap=1
```

**与早期内部统计（下称「早期统计」）§4.1 的差异（必须逐项说明来源，否则同一指标会出现两个数）**：

| 差异 | 早期统计口径 | 本文口径 | 原因 |
|---|---|---|---|
| 状态计数 | covered 20 / thin 7 / partial 1 / gap 1 | **covered 11 / thin 15 / partial 2 / gap 1** | 早期统计按「≥2 例**或** ≥1024 样本」判 covered，且把 4 个不发射 vdot 的例（vadd/perf_base/perf_vadd/perf_vmacc）算进了合法域；本文按「≥2 例**独立命中**」且把这 4 例判 `na`。**更严，不更松** |
| F28 寄存器空间 | 记为 partial（vd 14/32、vs1 1/32、vs2 2/32） | 记为 **partial**，实测 vd 16/32、vs1 5/32、vs2 3/32 | 本文把 8 个负例的编码也算进索引空间（它们是真实发射过的编码），早期统计未算 |
| F14 vd==vs2 | covered（3999 次） | **partial** | 早期统计把 `perf_vdot` 的 `--no-diff` 自检算 covered；本文要求 difftest 比对，故降级为 partial |

> 结论口径：**功能覆盖 11 covered / 15 thin / 2 partial / 1 gap（29 项）**；把 thin 与 partial 折算成「至少命中 1 次」则为 **28/29 项有命中、1 项（F15 `vs1==vs2`）零命中**。

---

## 1. 30 例 × 29 coverpoints 全矩阵

行 = coverpoint，列 = 30 例（列名缩写：`pb`=perf_base、`pv`=perf_vadd、`pm`=perf_vmacc、`pd`=perf_vdot、`rnd`=vdot_rand、`mtx`=vdot_matrix、`g0`=vdot_g0_badexp、`n1/n3/n5/n7`=vdot_neg_odd1/3/5/7）。最后一列 `●` 是该 CP 的命中例数（`+N◐` 表示另有 N 例 partial）。

| CP | vadd | pos1 | pos2 | pos3 | neg1 | n1 | n3 | n5 | n7 | bound1 | bound2 | bound3 | bound4 | bound5 | rnd | mtx | g0 | ill_sew | ill_lmul2 | ill_lmul4 | ill_lmul8 | ill_vm0 | ill_vstart | ill_vill | ill_vs | pd | pb | pv | pm | mix | ● |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| F01 | — | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | — | — | — | — | — | — | — | — | ● | — | — | — | ● | 18 |
| F02 | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | ✗ | — | — | — | — | — | 1 |
| F03 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 1 |
| F04 | — | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ✗ | ● | ● | — | — | — | — | — | — | — | — | ✗ | — | — | — | ● | 16 |
| F05 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 1 |
| F06 | — | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | — | — | — | — | — | — | — | — | ● | — | — | — | ● | 18 |
| F07 | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | — | — | — | — | — | 1 |
| F08 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 1 |
| F09 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 1 |
| F10 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 1 |
| F11 | — | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | — | — | — | — | — | — | — | — | ● | — | — | — | ● | 18 |
| F12 | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | ✗ | ✗ | ✗ | ✗ | ● | ✗ | ✗ | ✗ | — | — | — | — | — | 1 |
| F13 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 1 |
| F14 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | — | — | — | — | — | — | — | — | ◐ | — | — | — | ✗ | 0+1◐ |
| F15 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 0 |
| F16 | — | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | — | — | — | — | — | — | — | — | ✗ | — | — | — | ● | 17 |
| F17 | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | ● | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | — | — | — | — | — | 1 |
| F18 | — | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | — | — | — | — | — | — | — | — | ✗ | — | — | — | ● | 17 |
| F19 | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | ✗ | ● | ● | ● | ✗ | ✗ | ✗ | ✗ | — | — | — | — | — | 3 |
| F20 | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | — | — | — | — | — | 1 |
| F21 | — | ✗ | ✗ | ● | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ● | ● | ● | ● | ● | ✗ | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 7 |
| F22 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 1 |
| F23 | — | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 16 |
| F24 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 1 |
| F25 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 1 |
| F26 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | — | — | — | — | — | — | — | — | ● | — | — | — | ● | 3 |
| F27 | — | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ● | ✗ | ✗ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ✗ | 1 |
| F28 | — | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | — | — | — | ◐ | 0+26◐ |
| F29 | — | ◐ | ● | ● | ● | ● | ● | ● | ● | ◐ | ● | ● | ◐ | ● | ● | ● | ◐ | — | — | — | — | — | — | — | — | ✗ | — | — | — | ● | 13+4◐ |
| **●/例** | 0 | 7 | 8 | 9 | 8 | 8 | 8 | 8 | 8 | 8 | 9 | 9 | 8 | 9 | 11 | 16 | 7 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 4 | 0 | 0 | 0 | 8 | — |

**读表要点（三句话）**：

1. **四例不发射 vdot**（`vadd-microbench`、`perf_base`、`perf_vadd`、`perf_vmacc`）整列为 `—`——二进制扫描 0 个 vdot 编码（【静态】`hits.tsv` 的 `basis=bin`）。它们只提供共享向量通路的结构覆盖，**不能**充当任何 vdot 功能 coverpoint 的命中格。
2. **`vdot_matrix` 是 7 个 CP 的仅有来源**（F05/F08/F09/F10/F13/F24/F25 只由它命中）⇒ 回归时漏跑 matrix 会直接使这 7 项重新落入 gap（同「早期统计」§4.3 的 G5）。
3. **`vdot_rand` 是 F03/F22/F27 的仅有来源**（vl=VLMAX、1024 组随机、高 64 位干扰）⇒ 同 G4：smoke 白名单不含 rand，**不能用 smoke 产物出覆盖率报告**。

---

## 2. 逐 coverpoint 状态与证据

| CP | coverpoint | ACT4 对应 | 域 | 状态 | 命中 | 命中例（30 例内） |
|---|---|---|---|---|---|---|
| F01 | vstart_zero | `std-vec:31` | legal | **covered** | 18 | vdot_pos1,vdot_pos2,vdot_pos3,vdot_neg1,vdot_neg_odd1,vdot_neg_odd3,vdot_neg_odd5,vdot_neg_odd7,vdot_bound1,vd…（共 18 例） |
| F02 | vstart≠0 非法（负例） | 无（自定义扩展） | trap | **thin** | 1 | vdot_ill_vstart |
| F03 | vl_max | `std-vec:109` | legal | **thin** | 1 | vdot_rand |
| F04 | vl_not_max | `std-vec:114` | legal | **covered** | 16 | vdot_pos1,vdot_pos2,vdot_pos3,vdot_neg1,vdot_neg_odd1,vdot_neg_odd3,vdot_neg_odd5,vdot_neg_odd7,vdot_bound1,vd…（共 16 例） |
| F05 | vl=0 全写 | `Vx8:88 cp_vl_0` | legal | **thin** | 1 | vdot_matrix |
| F06 | vill=0 | `std-vec:23` | legal | **covered** | 18 | vdot_pos1,vdot_pos2,vdot_pos3,vdot_neg1,vdot_neg_odd1,vdot_neg_odd3,vdot_neg_odd5,vdot_neg_odd7,vdot_bound1,vd…（共 18 例） |
| F07 | vill=1 非法（负例） | `std-vec:27` | trap | **thin** | 1 | vdot_ill_vill |
| F08 | vta（`cp_csr_vtype_vta`） | `Vx8:206` | legal | **thin** | 1 | vdot_matrix |
| F09 | vma（`cp_csr_vtype_vma`） | `Vx8:210` | legal | **thin** | 1 | vdot_matrix |
| F10 | vta×vma | `Vx8:218（裁剪）` | legal | **thin** | 1 | vdot_matrix |
| F11 | vm=1 | `std-vec:40 的反面` | legal | **covered** | 18 | vdot_pos1,vdot_pos2,vdot_pos3,vdot_neg1,vdot_neg_odd1,vdot_neg_odd3,vdot_neg_odd5,vdot_neg_odd7,vdot_bound1,vd…（共 18 例） |
| F12 | mask_enabled（vm=0 ⇒ 非法） | `std-vec:40（bin enabled={0}）` | trap | **thin** | 1 | vdot_ill_vm0 |
| F13 | vd==vs1 | `std-vec:85` | legal | **thin** | 1 | vdot_matrix |
| F14 | vs2_vd_overlap（vd==vs2） | `std-vec:89` | legal | **partial** | 0 | （无）；◐ perf_vdot |
| F15 | vs1==vs2 | `std-vec:93` | legal | **gap** | 0 | （无） |
| F16 | SEW=8 | `std-vec:216` | legal | **covered** | 17 | vdot_pos1,vdot_pos2,vdot_pos3,vdot_neg1,vdot_neg_odd1,vdot_neg_odd3,vdot_neg_odd5,vdot_neg_odd7,vdot_bound1,vd…（共 17 例） |
| F17 | SEW≠8 非法（负例） | 无（自定义） | trap | **thin** | 1 | vdot_ill_sew |
| F18 | LMUL=1 | `std-vec:172` | legal | **covered** | 17 | vdot_pos1,vdot_pos2,vdot_pos3,vdot_neg1,vdot_neg_odd1,vdot_neg_odd3,vdot_neg_odd5,vdot_neg_odd7,vdot_bound1,vd…（共 17 例） |
| F19 | LMUL≠1 非法（负例） | 无（自定义） | trap | **covered** | 3 | vdot_ill_lmul2,vdot_ill_lmul4,vdot_ill_lmul8 |
| F20 | VS=OFF 非法（负例） | `std-vec:64 std_trap_vec 的补集` | trap | **thin** | 1 | vdot_ill_vs |
| F21 | 边界值（`cp_vs1/vs2_edges`） | `Vx8:106,138` | legal | **covered** | 7 | vdot_pos3,vdot_bound1,vdot_bound2,vdot_bound3,vdot_bound4,vdot_bound5,vdot_rand |
| F22 | 随机 1024 | `ACT4 约束随机（生成侧）` | legal | **thin** | 1 | vdot_rand |
| F23 | 高 96 位=0 | 无（自定义） | legal | **covered** | 16 | vdot_pos1,vdot_pos2,vdot_pos3,vdot_neg1,vdot_neg_odd1,vdot_neg_odd3,vdot_neg_odd5,vdot_neg_odd7,vdot_bound1,vd…（共 16 例） |
| F24 | 旧 vd | `std-vec:290（近似）` | legal | **thin** | 1 | vdot_matrix |
| F25 | vxsat | 无（自定义） | legal | **thin** | 1 | vdot_matrix |
| F26 | 背靠背/RAW | 无（自定义） | legal | **covered** | 3 | vdot_matrix,perf_vdot,vdot_mix |
| F27 | 高 64 位干扰 | 无（自定义） | legal | **thin** | 1 | vdot_rand |
| F28 | 寄存器空间 | `std-vec:73,77,81` | **bin（含负例，见 §3）** | **partial** | 26 | vdot_pos1,vdot_pos2,vdot_pos3,vdot_neg1,vdot_neg_odd1,vdot_neg_odd3,vdot_neg_odd5,vdot_neg_odd7,vdot_bound1,vd…（共 26 例） |
| F29 | 符号组合 | `官方 2.3.1–2.3.3` | legal | **covered** | 13 | vdot_pos2,vdot_pos3,vdot_neg1,vdot_neg_odd1,vdot_neg_odd3,vdot_neg_odd5,vdot_neg_odd7,vdot_bound2,vdot_bound3,…（共 13 例）；◐ vdot_pos1,vdot_bound1,vdot_bound4,vdot_g0_badexp |

---

**逐格证据出处**：每一格的 `basis`（`runtime` / `bin` / `static` / `bin+legal` …）与 `evidence`（命中的具体日志串或编码事实）都在 `hits.tsv` 的第 5–7 列；本文只给结论，不复制 870 行。

---

## 3. 寄存器索引空间（F28 的 bin 级明细）

F28 是 **bin 级** coverpoint（`vd`/`vs1`/`vs2` 各 32 个 bin），单例只贡献部分 bin。30 例并集（【静态】，`regspace.tsv`）：

| 操作数 | 命中 bin | 未命中 bin | 命中率 |
|---|---|---|---|
| `vd` | 16/32：v0, v1, v3–v16 | v2, v17–v31（16 个） | 50% |
| `vs1` | 5/32：v0, v1, v2, v4, v8 | v3, v5–v7, v9–v31（27 个） | 16% |
| `vs2` | 3/32：v0, v2, v10 | v1, v3–v9, v11–v31（29 个） | 9% |

> `vs1`/`vs2` 的 v0/v4/v8 等索引来自**非法编码**（`vdot_ill_sew` 的 `vd=vs1=vs2=v0`、`vdot_ill_lmul*` 的组基址）——它们确实发射过、也确实走到了译码/非法判定，因此计入「索引空间」；但**合法域**的 `vs1` 实际只有 `v1` 一个值、`vs2` 只有 `{2,10}`。

`regspace.tsv` 是 96 行（3 操作数 × 32 bin）的机读件，每行给 `hit=0/1` 与命中例清单。

---

## 4. `manifest.extra.tsv` 命中表（129 例扩容套件，独立清单）

> 口径：extra 套件**不进 30 例主清单**（主清单是官方回归口径的冻结件，`sha256 a90d1071…`）。本节的命中判定**只用二进制编码扫描**（【静态】`extra-static-scan.tsv`，129/129 文件扫到 vdot 编码）；**实跑状态见 §5**——作业 `127031933` 已跑出 129/129 通过（2026-11-06）。

### 4.1 套件构成（`design/verify/cases/manifest.extra.tsv`，129 数据行）

| 类 | 例数 | 族（`cover.extra.tsv` 的 family 列） |
|---|---|---|
| `vdot-base` | 7 | base：正/负/边界/vl 扫描/vta-vma/旧 vd |
| `vdot-ov` | 30 | overlap：vs2=vd 10 例、vs1=vd 10 例、vs1=vs2 10 例（各配 pos/neg/mixodd/bmax/bmin/zero/ext/asym/lanehi/rand 数据模式） |
| `vdot-pl` | 48 | back2back 5 / bubble 5 / raw-chain 5 / wb-port 4 / wb-port-vdot 2 / cancel 4 / illegal-interleave 6 / mix-issue 4 / hi96 3 / old-vd 4 / bb+bubble 2 / loop 4 |
| `negative` | 41 | illegal：SEW/LMUL/vm0/vstart/vill/VS 六类必要条件矩阵与交叉组合 |
| `g0` | 2 | g0：重叠与背靠背各一条「期望值故意错 1 bit」反例 |
| `vdot-rand10k` | 1 | rand10k：固定种子 20261106，10000 组 |
| **合计** | **129** | |

### 4.2 逐 CP 命中（extra 129 例）


| CP | 名称 | 命中例数 | 例（前 5） | 判定依据 | extra 侧结论 |
|---|---|---|---|---|---|
| F01 | vstart_zero | 86/129 | xb_pos_lanehi, xb_neg_all, xb_bound_max, xb_bound_min, xb_vl_sweep… | 非 negative/g0 且发射 vdot | 补上 |
| F02 | vstart≠0 非法（负例） | 14/129 | xn_vstart1, xn_vstart2, xn_vstart3, xn_vstart4, xn_vstart7… | cid 含 vstart（仅 negative 类；剔除合法执行的 xp_ilv_vstart） | 补上 |
| F03 | vl_max | 0/129 | （无） | **无**：xb_vl_sweep 只扫 vl=0..8，未扫 VLMAX=16 | 仍缺 |
| F04 | vl_not_max | 1/129 | xb_vl_sweep | xb_vl_sweep（vl=1..8 全扫） | 补上 |
| F05 | vl=0 全写 | 1/129 | xb_vl_sweep | xb_vl_sweep 含 vl=0 | 补上 |
| F06 | vill=0 | 86/129 | xb_pos_lanehi, xb_neg_all, xb_bound_max, xb_bound_min, xb_vl_sweep… | 非 negative/g0（未写非法 vtype） | 补上 |
| F07 | vill=1 非法（负例） | 5/129 | xn_vill_38, xn_vill_20, xn_vill_3a, xn_vill_24, xn_vill_vstart1 | cid 含 vill（仅 negative 类；剔除合法执行的 xp_ilv_vill） | 补上 |
| F08 | vta（`cp_csr_vtype_vta`） | 1/129 | xb_vta_vma | xb_vta_vma 四组合（0x00/0x40/0x80/0xC0） | 补上 |
| F09 | vma（`cp_csr_vtype_vma`） | 1/129 | xb_vta_vma | 同上 | 补上 |
| F10 | vta×vma | 1/129 | xb_vta_vma | 同上 4/4 bins | 补上 |
| F11 | vm=1 | 86/129 | xb_pos_lanehi, xb_neg_all, xb_bound_max, xb_bound_min, xb_vl_sweep… | 非负例且编码无 vm=0 | 补上 |
| F12 | mask_enabled（vm=0 ⇒ 非法） | 2/129 | xn_vm0, xn_vm0_sew16 | 编码含 vm=0（xn_vm0 / xn_vm0_sew16） | 补上 |
| F13 | vd==vs1 | 15/129 | xo_vs1_pos, xo_vs1_neg, xo_vs1_mixodd, xo_vs1_bmax, xo_vs1_bmin… | 二进制扫描 vd==vs1（xo_vs1_* 10 + 交叉 5） | 补上 |
| F14 | vs2_vd_overlap（vd==vs2） | 10/129 | xo_vs2_pos, xo_vs2_neg, xo_vs2_mixodd, xo_vs2_bmax, xo_vs2_bmin… | 二进制扫描 vd==vs2（xo_vs2_* 10） | 补上 |
| F15 | vs1==vs2 | 10/129 | xo_v12_pos, xo_v12_neg, xo_v12_mixodd, xo_v12_bmax, xo_v12_bmin… | 二进制扫描 vs1==vs2（xo_v12_* 10） | 补上 |
| F16 | SEW=8 | 86/129 | xb_pos_lanehi, xb_neg_all, xb_bound_max, xb_bound_min, xb_vl_sweep… | 非 negative/g0 | 补上 |
| F17 | SEW≠8 非法（负例） | 16/129 | xn_sew_e16, xn_sew_e32, xn_sew_e64, xn_e16_m2, xn_e16_m4… | cid 含 e16/e32/e64（按此口径复算=16；`xn_sew16_vl0`/`xn_vm0_sew16` 不计入） | 补上 |
| F18 | LMUL=1 | 86/129 | xb_pos_lanehi, xb_neg_all, xb_bound_max, xb_bound_min, xb_vl_sweep… | 非 negative/g0 | 补上 |
| F19 | LMUL≠1 非法（负例） | 7/129 | xn_lmul_m2, xn_lmul_m4, xn_lmul_m8, xn_lmul_mf8, xn_lmul_mf4… | cid 含 lmul（含 mf8/mf4/mf2 分数 LMUL；剔除合法执行的 xp_ilv_lmul_back） | 补上 |
| F20 | VS=OFF 非法（负例） | 3/129 | xn_vs_off, xn_vs_off_vstart1, xn_vs_off_vl0 | cid 含 vs_off | 补上 |
| F21 | 边界值（`cp_vs1/vs2_edges`） | 14/129 | xb_bound_max, xb_bound_min, xo_vs2_bmax, xo_vs2_bmin, xo_vs2_zero… | cid 含 bound/bmax/bmin/ext/zero | 补上 |
| F22 | 随机 | 1/129 | vdot_rand10k | vdot_rand10k（10000 组） | 补上 |
| F23 | 高 96 位=0 | 3/129 | xp_hi2, xp_hi4, xp_hi8 | xp_hi2/4/8 逐条断言 vd[127:32]=0 | 补上 |
| F24 | 旧 vd | 5/129 | xb_oldvd, xp_oldvd1, xp_oldvd2, xp_oldvd3, xp_oldvd4 | xb_oldvd + xp_oldvd1..4（预填 0x00/0x01/0x7F/0x80） | 补上 |
| F25 | vxsat | 0/129 | （无） | **无**：extra 未加 vxsat 前后对照专项（仅 30 例的 matrix 有） | 仍缺 |
| F26 | 背靠背/RAW | 35/129 | xp_bb2, xp_bb3, xp_bb4, xp_bb6, xp_bb8… | bb/bub/chain/loop/mix/wbp/cxl 八族 | 补上 |
| F27 | 高 64 位干扰 | 4/129 | xb_pos_lanehi, xo_vs2_lanehi, xo_vs1_lanehi, xo_v12_lanehi | cid 含 lanehi | 补上 |
| F28 | 寄存器空间 | 129/129 | xb_pos_lanehi, xb_neg_all, xb_bound_max, xb_bound_min, xb_vl_sweep… | 全表并集（vd 10 / vs1 5 / vs2 5） | 部分 |
| F29 | 符号组合 | 86/129 | xb_pos_lanehi, xb_neg_all, xb_bound_max, xb_bound_min, xb_vl_sweep… | 非 negative/g0（pos/neg/mixodd/bmax/bmin 数据模式） | 补上 |

> extra 侧命中**只由二进制编码扫描判定**（`extra-static-scan.tsv`：129/129 文件均扫到 vdot 编码，0 个「无 vdot」）；`cid` 前缀约定（`xo_`=overlap、`xb_`=base、`xp_`=pipeline、`xn_`=negative、`xg0_`=g0、`vdot_rand10k`）用于把编码事实映射到 coverpoint，**不是**运行日志证据。
>
> **trap 域计数口径（2026-11-07 修正）**：`xp_ilv_vstart`/`xp_ilv_vill`/`xp_ilv_lmul_back` 属 `vdot-pl` 正向流水族，实跑日志为 `GOOD=1 ABORT=0 BAD=0`（`results/difftest/extra/94-extra-20261106T143635.log:71,72,75`），是**合法执行**，不计入 trap 域；F02/F07/F19 已各剔除 1 例（15→14、6→5、8→7）。F17 按「cid 含 e16/e32/e64」口径复算为 **16**（旧写 17 与判定口径不符）。

**extra 套件对 30 例缺口的补强（关键三条）**：

| 30 例缺口 | extra 补强 | 依据 |
|---|---|---|
| F15 `vs1==vs2` **gap（0 例）** | `xo_v12_*` **10 例** | 二进制扫描：10 个 `.bin` 含 `vs1==vs2` 编码（【静态】`extra-static-scan.tsv` 第 6 列 `yes`） |
| F13 `vd==vs1` thin（1 例） | `xo_vs1_*` 10 例 + 交叉 5 例 | 同上，`vd_eq_vs1=yes` 共 15 例 |
| F14 `vd==vs2` partial（仅 `--no-diff`） | `xo_vs2_*` 10 例（difftest 路径，`94-run-extra.sh` 带 `--diff`） | 同上，`vd_eq_vs2=yes` 共 10 例 |

> **F15/F13/F14 的 extra 例已拿到「整套通过」的实跑结论（2026-11-06 终态）**：`94-extra-20261106T143635`（作业 `127031933`）`status=通过`、`cases_pass=129/129`、8/8 criteria `达标`（含 `golden_crosscheck=达标`）；`xo_v12_*` 10 例、`xo_vs1_*` 10 例、`xo_vs2_*` 10 例在 `.cases.tsv` 第 3 列全部为「通过」。**但 extra 仍不进 30 例主清单**：本节只声明「用例已构造且已实跑通过」，不把 extra 的通过数并入 30 例矩阵；F15 在 30 例内仍记 gap（§5 G1）。

---

## 5. 缺口清单与补测建议（逐条可执行）

| # | 缺口 | 现状 | 补测建议（最小改动） | 预计成本 |
|---|---|---|---|---|
| G1 | **F15 `vs1==vs2`** | 30 例 0 命中；extra `xo_v12_*` 10 例已随整套 129/129 通过（`127031933`） | 若要把 F15 从 gap 升为 covered，需在 30 例主清单内加例（extra 不进官方清单）；否则报告按 gap 披露 | 0.2 机时（主清单加例） |
| G2 | **F28 寄存器空间** | vd 16/32、vs1 5/32、vs2 3/32；合法域 vs1 只有 v1 | 新增 1 条 `vd/vs1/vs2 ∈ {0,1,15,16,31}` 的扫描例（避开无意重叠 bin），走 extra 清单 | 0.1 机时 |
| G3 | **F14 只有 `--no-diff` 样本**（30 例内） | extra `xo_vs2_*` 10 例走 difftest 且已随 129/129 通过；30 例内仍只有 `--no-diff` 样本 | 在 30 例主清单内补 1 例 difftest 路径，或报告按 partial 披露 | 0.1 机时 |
| G4 | **F03 `vl_max`（VLMAX=16）** | 30 例由 `vdot_rand` 的 `li t1,16` 命中；extra 的 `xb_vl_sweep` 只到 vl=8 | 在 `xb_vl_sweep` 加 `vl=16` 一档（或在 `vdot_rand` 保持现状并把 F03 记为 thin） | 0.1 机时 |
| G5 | **F25 `vxsat`** | 仅 30 例的 `vdot_matrix` 1 例 | extra 加 1 条「先 `csrw vxsat,1` 再 vdot 再读回」 | 0.1 机时 |
| G6 | **F05/F08/F09/F10/F13/F24/F25 只在 `vdot_matrix`** | 单点依赖，回归漏跑即重新落入 gap | 覆盖率跑必须全选 30 例（`95-coverage.sh` 已按 manifest 全选，不裁剪） | 0 |
| G7 | **F23 `perf_vdot` 未断言高 96 位** | 30 例内 16 例命中（含 matrix/rand），`perf_vdot` 只读 lane0 | 若要 17/18（合法例计），在 `perf_vdot` 链后加一次 `vse32.v` + 断言；否则报告写 16/18（合法例） | 0.1 机时 |
| G8 | **结构覆盖（RTL line/toggle）** | **【未运行（实跑受阻）】**：toggle 覆盖 100 条指令即 3.3 GB dat；覆盖构建 + `--diff` 退出段 rc=139 | 改 line-only 覆盖重建后重跑（§6.3；修复实验作业 `127128086` 结果待收） | 已耗 3.3 机时；重跑预计 2–3 机时 |
| G9 | ACT4 `cr_vtype_agnostic` / `mask_enabled` / `cp_masking_edges` | **结构性不可达**（vdot 合法编码强制 vm=1） | 报告写 N/A；用 F10（vta×vma）与 F11/F12 替代，**不要伪造 ACT4 cross 命中** | 0 |
| G10 | ACT4 无 `vstart≠0` / `vill=1` / `VS=OFF` 的 trap bin | 用自定义 F02/F07/F20 覆盖 | 报告注明「ACT4 模板扩展」 | 0 |
| G11 | 分数 LMUL（mf8/mf4/mf2） | 30 例未测；extra `xn_lmul_mf8/mf4/mf2` 已随整套 129/129 通过（`127031933`） | 无（extra 已闭合；30 例内仍不覆盖） | 0 |

---

## 6. 结构覆盖（RTL line/toggle）：实跑受阻，数字【未运行】

**结论（2026-11-07 实跑，用户已授权突破自设 11.0 机时预算）**：覆盖率 emu **重建成功**
（`EMU_COVERAGE=1`，作业 `127117867`，构建 04:34→06:24 = 110 min，emu `sha256 b86f95b4…`、424 MB），
但**覆盖构建的 emu 在 `--diff` 用例的退出段 SIGSEGV（rc=139），`.coverage.dat` 为 0 字节**；
30 例只跑完第 1 例（`vadd-microbench`，GOOD=0）即中止。此处**不写任何覆盖率数字**，结构覆盖记
**【未运行（实跑受阻）】**，不写「覆盖率达标」。

### 6.1 作业台账（机时 = node_hour；`90-budget-log.sh auto` 自动入账，数值取自 `results/budget-log.tsv`）

| 作业 | 起止（2026-11-07） | 终态 | 机时 | 说明 |
|---|---|---|---|---|
| `127113117` | 03:40:25→03:40:43 | FAILED（rc=2） | 0.005 | 构建前失败：`NOOP_HOME` 未 export（`difftest/Makefile:18`），已修 |
| `127113373` | 03:43→03:58 | CANCELLED by 276820 | 0.246 | 构建期被同账号 `scancel`（无产物） |
| `127114992` | 04:00→04:32 | CANCELLED by 276820 | 0.544 | 构建期被同账号 `scancel`（无产物） |
| `127117867` | 04:34→06:53 | CANCELLED（崩溃后主动停止，止损） | 2.311 | 构建成功；第 1 例 rc=139 / 0 B dat（§6.2） |
| `127126206` | 06:54→07:15 | CANCELLED（诊断用） | 见 §6.1 备注 | 诊断 p1/p2/p3：toggle dat 规模与 `--diff` 崩溃复现 |
| `127127119` | 07:14→07:32 | COMPLETED | 见 §6.1 备注 | 诊断 q1/q2/q3：gdb 栈 |
| `127128086` | 07:36→ | 运行中 | 见 §6.1 备注 | **line-only 重建 + 两例冒烟；结果待收** |

> 备注：`127126206`/`127127119`/`127128086` 是 `sbatch --wrap` 诊断作业，不跑 `95-coverage.sh` 的 EXIT trap，
> 因此**不自动入账**；其机时用 `90-budget-log.sh record --item P3-full` 手工补记：
> `127126206`=**0.337**、`127127119`=**0.298**（已入账）；`127128086` 运行中，**机时待记**。
> 合计新增 **3.741 机时**；`90-budget-log.sh summary`（2026-11-07 08:54:48）→ `P3-full 14.808/3.0（494%）`、
> 合计 **18.804/10.6**、**EXIT=1**（自设 11.0 预算由用户 2026-11-07 授权越过，超支如实入账）。

### 6.2 定位证据（全部【实测】，原始日志 `evidence/cov-debug-20261107/`）

| 实验 | 命令要点 | 结果 |
|---|---|---|
| p1 | `--no-diff -i microbench.bin -C 100 --dump-coverage` | **rc=0**，`.dat` = **3 320 861 425 B（3.09 GiB）** |
| p2 | `--no-diff -i microbench.bin -C 100`（不 dump） | **rc=0** |
| p3 | `--diff -i vdot_pos1.bin --dump-coverage`（全跑） | **rc=139**，`.dat` **0 B** |
| q1 | `--diff -i vdot_pos1.bin`（**不 dump**，全跑） | 用例本身跑完（`HIT GOOD TRAP` ×1、`Host time spent: 56266ms`），进程退出段 **rc=139** |
| q2 | `--diff -i vdot_pos1.bin -C 100 --dump-coverage` | **rc=0**（截断到 100 条可正常退出） |
| q3 | gdb 全跑 + dump | 栈：`std::_Rb_tree_insert_and_rebalance` ← `std::map<int,std::string>::operator[]` ← `VerilatedCovImp::write` ← `Emulator::save_coverage` ← `Emulator::~Emulator` ← `main` |

**读法（不外推）**：① 崩溃不在 difftest 比对、也不在用例执行，而在**退出析构段**（q1 无 dump 也崩）；
② `--coverage-toggle` 的 dat 规模不可用——**100 条指令就 3.3 GB**（`vtransform.py` 只认 `.v`、香山为 `.sv`，
SRAM/Difftest 的 `coverage_off` 过滤不生效，见「早期统计」的 T2）；③ 短跑（`-C 100`）不崩、全跑崩，与运行规模/线程相关。

### 6.3 修复方向与重跑命令（未完成）

1. **line-only 重建**（去掉 `--coverage-toggle`，保留 `--coverage-line`）：远端 `difftest/verilator.mk:72`
   临时改为 `VERILATOR_FLAGS += --coverage-line`，备份 `verilator.mk.pre-lineonly-20261107`，diff 见
   `evidence/cov-debug-20261107/dbg3/verilator-mk-lineonly.diff`；重建后两例冒烟（s1 `vdot_pos1 --diff + dump`、
   s2 `microbench --diff + dump --max-instr=2000000`）在作业 `127128086` 里，**结果待收**。
2. 若 line-only 仍崩：改 `EMU_THREADS=1` 重建（覆盖计数无跨线程归并；代价是仿真变慢，30 例可能 >4 机时）。
3. 拿到可用的 `.dat` 后，重跑与解析命令：

```bash
# 0) 预算/授权（自设 11.0 机时预算由用户 2026-11-07 授权越过，不改判据；超支如实入账）
ssh kunshan 'bash ~/core/core-package/scripts/90-budget-log.sh summary'

# 1) 重建 + 30 例 + 合并（line-only 版 verilator.mk 已就位；不带 --skip-build 会重建）
ssh kunshan 'cd ~/core && sbatch -p kshcnormal -N 1 -n 32 --time=06:00:00 -J vdot-coverage \
  core-package/scripts/95-coverage.sh --manifest ~/core/test/manifest.30.tsv \
  --ref-so ~/core/src/NEMU/build/riscv64-nemu-interpreter-so --timeout 2400 --expect-rows 30 --no-budget-guard'

# 2) 短轮询（单次前台 ≤10 min）
ssh kunshan 'sacct -j <JOBID> --format=JobID,State,Elapsed -X'

# 3) 回传 + 解析五段报告（LineSelf/LineTree/ToggleSelf/ToggleTree/AllCoverage）
rsync -a kunshan:~/core/results/coverage/<runid>/ results/coverage/<runid>/
python3 -I stage3/3.1.2-difftest/coverage/parse_stats.py \
  --log results/coverage/<runid>/merged.coverage/coverage_SimTop.log --out results/coverage/<runid>
python3 -I stage3/3.1.2-difftest/coverage/gen_hits.py \
  --manifest design/verify/cases/manifest.tsv --logs results/coverage/<runid>/cases --log-suffix .log \
  --bins design/verify/cases --out results/coverage/<runid> \
  --statistics results/coverage/<runid>/merged.coverage/coverage_SimTop.log
# → stats-5sections.tsv（五段长表）+ vdot-structural.tsv（6 模块 tree_line/tree_toggle）
```

**报告口径（拿到数字后照此写）**：`statistics.py` 的 line 覆盖只统计 `if` / `end else` 行的命中、toggle 统计声明行翻转，**不是语句覆盖率**；元组是 `(covered, NOT_covered, pct)`，总数 = covered + not_covered（`statistics.py:309-315`）；SRAM/Difftest 的 `coverage_off` 过滤对香山**无效**（T2，见「早期统计」），全设计数字不得冒充 vdot 模块数字。

---

## 7. 本文的复算校验

1. `python3 -I stage3/3.1.2-difftest/coverage/gen_hits.py --out stage3/3.1.2-difftest/coverage` 退出 0，输出 `cases=30 cps=29 cells=870`。
2. `wc -l stage3/3.1.2-difftest/coverage/hits.tsv` → 871（1 行表头 + 870 格）。
3. `awk -F'\t' 'NR>1{print $5}' stage3/3.1.2-difftest/coverage/hits.tsv | sort | uniq -c` → 只含 `hit/partial/miss/na` 四种值。
4. 本文 §2 的 `covered/thin/partial/gap` 计数与 `summary.tsv` 一致（11/15/2/1）。
5. 结构覆盖一节必须保留【未运行】字样与实跑证据路径（§6.1 作业台账 + §6.2 定位证据）；在 SIGSEGV 修复后的实跑数字到手前**不得**改成「已测」。
