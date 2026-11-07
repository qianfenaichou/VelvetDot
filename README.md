# vdot.vv：香山 V2 的 K=8 int8 点积

`vdot.vv` 是 RISC-V 向量扩展（RVV）的自定义指令，在 SEW=8、LMUL=1、K=8 下单条完成 8 个 int8 元素的点积；K=8 指每条指令固定处理 lane 0–7 的 8 个 int8 元素。19 位有符号结果符号扩展后写回 `vd[31:0]`，`vd[127:32]` 恒为零，不读旧 vd（[`design/SPEC.md`](design/SPEC.md) §1）。

仓库含指令规格、Chisel RTL 与 NEMU 改动、Python 参考模型（golden model）、协同仿真用例，以及三阶段的测试与性能材料。

```
patches/       10 个补丁：9 个功能与单测 + 1 个跨拍重定时
design/        规格、微架构、算法、编码规范；verify/ 为参考模型、用例与 miter
core-package/  批量脚本与落位手册（rsync 到 $CORE_DIR）
results/       实测产物：difftest、perf 重复、yosys、formal、lint、wave、coverage
stage1–3/      三阶段材料
docx/          赛题原文与评分细则
versions.env   上游版本锚点
```

基线为 XiangShan `a4eeaab`（`kunminghu-v2`）与 NEMU `a683e0b`；docx 编号项 12 项均有产物（见文末索引），形式验证只到数据通路、三个视频位未产出，缺口写在已知限制。主回归 30/30；扩容 224 例在 2026-11-08 全量通过（224/224），与主清单合计 254 个镜像。

## 指令规格

下表是 RTL、NEMU 与参考模型三端必须对齐的定义。

| 项 | 定义 |
|---|---|
| 指令 | `vdot.vv vd, vs2, vs1`（OPMVV，无掩码） |
| 语义 | `S = Σ(i=0..7) sext19( sext8(vs1[i]) × sext8(vs2[i]) )`，只取 vs1/vs2 低 64 位（lane 0–7） |
| 内部位宽 | 19 位有符号；最坏 `8×(−128)×(−128) = 131072`，超出 18 位有符号上限 131071 |
| 写回 | `vd[31:0] = sext32(S)`，`vd[127:32] = 0`；不读旧 vd，`vxsat` 不变，`vl`/`vta`/`vma` 不影响结果 |
| 合法条件 | `SEW=8 ∧ LMUL=1 ∧ vm=1 ∧ vstart=0 ∧ vill=0 ∧ mstatus.VS≠OFF`，任一不成立即非法；非法判定优先于 `vl=0` 全写 |
| 编码 | opcode `1010111` / funct3 `010` / funct6 `001110` / vm `1`；`vdot.vv v3, v2, v1` = `0x3A20A1D7` |

编码空间按 riscv-opcodes 快照 `f24ac23` 核对：同一空间的 `001100`（`0x0C`）已被 Zvbc `vclmul.vv` 占用，`001110` 在 ratified 与 unratified 全库中空闲。规格全文见 [`design/SPEC.md`](design/SPEC.md)，核对记录见 [`stage2/2.1-design/encoding-gate-zvbc-2026-10-31.md`](stage2/2.1-design/encoding-gate-zvbc-2026-10-31.md)。

## 实测结果

三张表分列功能回归、面积与形式验证、延迟与吞吐。

| 项 | 结果 | 证据（作业号） |
|---|---|---|
| 30 例整份 `--full` | 30/30 通过，`regression_delta=0`，9/9 判据达标（2026-11-07） | [`20-full-20261107T104227.json`](results/difftest/20-full-20261107T104227.json)（127137638） |
| 扩容 224 例（清单外；与 30 例合计 254 个镜像） | 224/224 通过，负例 57/57，自检串 162/162，G0 捕获 2/2，8/8 判据达标 | [`94-extra-20261108T014445.json`](results/difftest/extra/94-extra-20261108T014445.json)（127194011） |
| 30 例整份 `--full`（2026-11-08 复跑） | 未完成：退出码 1，未生成结果 JSON，`sacct` 无对应作业记录 | 无产物 |
| 参考模型自检 | 1142 例通过，三套独立算法交叉 | `python3 design/verify/vdot_model_test.py`（本地，秒级） |

第一张表第 1–2 行来自两次作业，第 3 行是 2026-11-08 的 30 例复跑（无产物），第 4 行是本地命令；功能判据见 `core-package/scripts/20-run-difftest.sh:14-21`，正例须 `HIT GOOD TRAP`、`ABORT=0` 且命中用例自检串，负例须双侧一致陷入非法。三类数字口径不同：功能是 pass/fail 计数，面积是综合后的 cell 数与拓扑级数，延迟是 `rdcycle` 周期。

面积用 Yosys 0.48 综合，只统计 vdot 数据通路模块，不含 wrapper `VIMacU` 其余部分与工艺库；K1 与 P-2 是同日两次作业的不同镜像，只作同工具内的相对比较。两份 stat 件不带作业号，其 `num_cells` 与对应 `40-area-*.json` 的 `metrics[]` 同值；该 JSON 的 `stat_json` 仍指向 11-01 的旧件 `vdot.stat.json`（481 cells、DFF 19，与 500 矛盾），因此本表直接引 `vdot-p2` / `vdot-k1` 两份原始 stat 件。

| 项 | 结果 | 口径 | 证据（作业号） |
|---|---|---|---|
| `VdotReduce`（P-2） | 500 cells，14 级，DFF 38 | P-2 = 把 `(sum, carry)` 跨 `fireS1` 寄存的进位保存重定时版（`patches/0005-…`） | [`vdot-p2.stat.json`](results/yosys/vdot-p2.stat.json)、[`vdot-p2.ltp.txt`](results/yosys/vdot-p2.ltp.txt)、[`40-area-20261107T104238.json`](results/yosys/40-area-20261107T104238.json)（127137643） |
| `VdotReduce`（K1） | 481 cells，22 级，DFF 19 | K1 = 未重定时版 | [`vdot-k1.stat.json`](results/yosys/vdot-k1.stat.json)、[`vdot-k1.ltp.txt`](results/yosys/vdot-k1.ltp.txt)、[`40-area-20261107T095404.json`](results/yosys/40-area-20261107T095404.json)（127135437） |
| `VIMac64b` | 42,783 cells，100 级 | 11-04 与两次 11-07 作业同值 | [`40-area-20261107T104238.json`](results/yosys/40-area-20261107T104238.json)、[`40-area-20261104T094144.json`](results/yosys/40-area-20261104T094144.json)（126752216） |
| miter 正控 / 负控 | `SUCCESS` / `FAIL` | 只证 `vdot_dp` 数据通路 | [`50-miter-20261104T093531.json`](results/formal/50-miter-20261104T093531.json)（126751660） |

延迟与吞吐来自同一组 perf 用例：`L_vdot` 是依赖链 cyc，`T_steady` 是 cyc/dot，两者相除没有物理含义，不是加速比。同属每点周期的 `B1`/`B2` 与 `T_steady` 才能相除得出每点开销倍数 6 / 9，延迟侧可报的比值则是基线链每指令归一 `(16/3) ÷ 4 ≈ 1.33×`（[b3 日志](results/difftest/b3/91-b3-20261104T115624.log)，口径见 [`stage3/3.3/report.md`](stage3/3.3/report.md) §4.3）。基线是「用已有向量指令组合实现同等功能」的自设序列，官方细则未规定条数与计时窗口。2026-11-08 以 4 次独立重复复核该比值（作业 127196036）：`L_vdot` 四次均为 4，中位数 4、极差 0，`(16/3)/4 = 1.333333`（整数打印口径 `5/4 = 1.25`），口径与限定见 [`perf-repeat.md`](stage3/3.3/sections/perf-repeat.md) §2.5。

| 口径 | 值 | 含义 | 证据（作业号） |
|---|---|---|---|
| `L_vdot` | 4 cyc | `vd==vs2` 的依赖链延迟；对照链 `L_vmacc` 4、`L_vadd` 3 | [`20-full-20261107T104227.json`](results/difftest/20-full-20261107T104227.json)（127137638）`metrics[]` |
| `T_steady` | 1 cyc/dot | 8 个独立 `vd` 的背靠背吞吐 | [`20-full-20261107T104227.json`](results/difftest/20-full-20261107T104227.json)（127137638）`metrics[]` |
| `B1` / `B2` | 6 / 9 cyc/dot | B1 = `vwmul.vv + vwredsum.vs`；B2 = `vwmul.vv + vwadd.vx + vredsum.vs`（`design/verify/perf/perf_base.c:2-3`） | [`20-full-20261107T104227.json`](results/difftest/20-full-20261107T104227.json)（127137638）`metrics[]` |
| 4 次重复（2026-11-08） | `L_vdot` 4,4,4,4；中位数 4、极差 0 | 4 个独立 emu 进程；`T_steady`/`B1`/`B2`/`L_vadd`/`L_vmacc` 极差同为 0；模型周期，非置信区间 | [`99-perf-repeat-4x-20261108.json`](results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json)（127196036） |

## 设计要点

- 复用 `VIMac64b` 在 SEW=8 下已算出的 8 个 16 位积 `sum_wo`，不新增乘法阵列。只补一级 8→1 归约：4:2 压缩树加 19 位 CPA（`VdotReduce.scala`），共用的 `VimacCfg` 未改动。
- 归约结果用 `VIMac64b` 显式导出的 `fireS1` 寄存，与 `walOut` 同拍，沿用 `CertainLatency(2)`。跨拍重定时把 481 cells / 22 级改为 500 cells / 14 级、DFF 19 增到 38，`L_vdot` 仍为 4 cyc。
- wrapper 用输出 Mux 旁路 Mgu（`Mux(outIsVdot, vdotReduce.io.vd, mgu.io.out.vd)`，`outIsVdot` 取 `outCtrl.fuOpType`），因为 Mgu 的 tail 会回带旧 vd 或写 `0xFF`（`repos/XiangShan/src/main/scala/xiangshan/backend/fu/vector/Mgu.scala:83,90-92`，见 [`design/ARCHITECTURE.md`](design/ARCHITECTURE.md) §2.5）。改动落在 `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala`；同目录 `fu/vector/VIMacU.scala` 是死文件，不含 vdot。
- 非法判定放在译码层：`isVdot && (SEW =/= 0.U || LMUL =/= 4.U)`，其中 `vsew=0`↔SEW=8、`vlmul=000`↔LMUL=1，与规格表不矛盾；`vill`、`vstart≠0`、`mstatus.VS=OFF` 各自成项，因为 `Mgu.illegal` 恒为 false（`Mgu.scala:131`），不能依赖 FU 报错。
- RTL、NEMU、参考模型三处实现同一语义。

## 复现

四步按顺序执行，成功标志写在代码块内；第 4 步的落位方法见 [`core-package/README.md`](core-package/README.md) §1，命令里的 `kunshan` 是 SSH 别名。第 3 步已在本地重跑通过，第 1、2、4 步未在本次文档更新中重跑，输出取自 `results/` 下的作业产物。

```sh
git clone https://github.com/OpenXiangShan/XiangShan.git repos/XiangShan   # 1) 取上游源码（分钟级）
git -C repos/XiangShan checkout a4eeaab   # 成功标志：rev-parse --short HEAD 输出 a4eeaab，退出码 0
git -C repos/XiangShan submodule update --init --recursive   # yunsuan 9559211、rocket-chip 46f1efe
git clone https://github.com/OpenXiangShan/NEMU.git repos/NEMU
git -C repos/NEMU checkout a683e0b
# 2) 应用 10 个补丁（秒级）→ 成功标志：10 条命令退出码均为 0；先叶子仓（rocket-chip、yunsuan）后主仓，最后 NEMU
# 主仓补丁含子模块指针行，已初始化子模块时会打印 warning: unable to rmdir 'yunsuan': 目录非空 并返回 0，改动照常应用
git -C repos/XiangShan/rocket-chip apply -p1 "$PWD/patches/0001-X1-add-VDOT_VV-custom-encoding-funct6-001-rocketchip.patch"
git -C repos/XiangShan/yunsuan apply -p1 "$PWD/patches/0001-X6-X7-VimacOpcode.vdot-3-b111-and-VimacType.-yunsuan.patch"
git -C repos/XiangShan/yunsuan apply -p1 "$PWD/patches/0002-X15-export-sum_wo-walOut-fireS1-from-VIMac64-yunsuan.patch"
git -C repos/XiangShan/yunsuan apply -p1 "$PWD/patches/0003-X-new-VdotReduce-K-8-int8-dot-product-reduct-yunsuan.patch"
git -C repos/XiangShan/yunsuan apply -p1 "$PWD/patches/0005-X-new-P-2-VdotReduce-carry-save-retiming-yunsuan.patch"
git -C repos/XiangShan apply -p1 "$PWD/patches/0001-X1-X2-decode-VDOT_VV-as-OPMVV-F-vimac-Vima-xiangshan.patch"
git -C repos/XiangShan apply -p1 "$PWD/patches/0002-X14-vdot-legality-predicate-in-VecExceptio-xiangshan.patch"
git -C repos/XiangShan apply -p1 "$PWD/patches/0003-X8-wrapper-bypasses-Mgu-for-vdot-and-asser-xiangshan.patch"
git -C repos/XiangShan apply -p1 "$PWD/patches/0004-tests-VdotReduce-Chisel-B-19-200-xiangshan.patch"
git -C repos/NEMU apply -p1 "$PWD/patches/0001-N1-N2-N3-vdot.vv-reference-model-decode-entry-E-nemu.patch"
python3 design/verify/vdot_model_test.py   # 3) 参考模型自检（秒级）→ ALL TESTS PASSED (1142 cases)，退出码 0
export CORE_DIR="${CORE_DIR:-/public/home/$USER/core}"   # 4) 30 例协同仿真（小时级），落位根目录
rsync -av core-package/ kunshan:/public/home/$USER/core/   # 4.0 落位：脚本
rsync -av --exclude build --exclude target repos/XiangShan repos/NEMU kunshan:/public/home/$USER/core/src/   # 4.0 落位：源码树（子模块需先 init）
ssh kunshan 'test -f /public/home/$USER/core/scripts/00-env-check.sh && test -d /public/home/$USER/core/src/XiangShan'   # 返回 0 才算落位完成
AM_HOME=/path/to/nexus-am HOST_IP="$(hostname -I | awk '{print $1}')" \
  bash design/verify/cases/build_all.sh design/verify/cases   # 4.1 构建 30 例镜像与探针（需 riscv64-unknown-elf-gcc 与 nexus-am 源码树）
mkdir -p "$CORE_DIR/test"   # 4.2 展开清单：@IMG_DIR@ → 镜像绝对路径
bash design/verify/cases/make_manifest.sh "$PWD/design/verify/cases" > "$CORE_DIR/test/manifest.tsv"
sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 "$CORE_DIR"/scripts/10-build-emu.sh --src-root "$CORE_DIR/src"   # 4.3 构建 emu 与参照 .so
sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 "$CORE_DIR"/scripts/20-run-difftest.sh --full   # 4.4 → status=通过、cases_pass=30/30，退出码 0；emu 构建与 30 例回归各约 30–36 分钟
```

补丁路径用绝对路径：`git -C <dir> apply` 会把相对路径解析到 `<dir>` 内，写成 `patches/…` 会报「无法打开补丁」并返回 128；`0005` 必须跟在 `0003` 之后，两者修改同一文件 `VdotReduce.scala`。用例清单为 [`design/verify/cases/manifest.tsv`](design/verify/cases/manifest.tsv)（30 数据行，sha256 `a90d1071…`），它是 `@IMG_DIR@` 源清单，实跑前由 `make_manifest.sh` 展开成绝对路径版本（`20-full` 记录的 `manifest.sha256` 为 `e12470e6…`），两者哈希不同属预期。

## 已知限制

1. 验证覆盖不完整：形式验证只到 `vdot_dp` 数据通路（miter 的 scope 不覆盖流水、发射与旁路），译码与 wrapper 改动只由 difftest 与 Chisel 单测覆盖；lint 在默认告警集下两 top 0 warning，`-Wall` 下 13 条 `UNUSEDSIGNAL`（VdotReduce 1 + VIMac64b 12）、rc=1，未逐条修复。规避：改动后必跑 30 例主清单与 224 例扩容清单，并把 miter 顶层扩到 wrapper 列入后续。
2. 补丁按 `a4eeaab` 基线的检出生成、应用顺序有依赖，编码核对也基于 riscv-opcodes `f24ac23` 快照。换基线或上游重新分配 `001110/010` 时结果不可直接沿用；规避是先跑 `git apply --check`，必要时重跑 `design/verify/encoding-gate.py` 并改走 [`design/SPEC.md`](design/SPEC.md) §2.4 的回退池。
3. 30 例复现依赖集群 SLURM 分区 `kshcnormal`、`nexus-am` 源码树与 xPack `riscv64-unknown-elf-gcc 13.2.0`（版本记录见 `results/env/00-env-20261105T092724.tools.tsv`）。`nexus-am` 仓库不含（上游为 `https://github.com/OpenXiangShan/nexus-am`，本工作区未固定 commit），缺任一项时第 4 步会停在前置检查（`build_all.sh:21` 对 `AM_HOME` 硬退出、`10-build-emu.sh:167-170` 对两棵源码树 `fail_unrun`），此时只能用 `results/` 下的既有产物核对结论。
4. 官方要求的三个视频位未产出：`recording/` 下只有分镜脚本，没有视频文件。截图与文档不能顶替录屏，视频项提交前不完整；规避是按该目录三份分镜脚本补录后再提交。

## 交付物索引

编号对应 [`docx/02-赛题与评分细则.md`](docx/02-赛题与评分细则.md)，设计与验证正文见下表之后的四份设计文档与材料索引。

| 编号 | 内容 | 位置 |
|---|---|---|
| 1.1 | 环境部署验证 | [`stage1/1.1-env/`](stage1/1.1-env/) |
| 1.2 | 部署与操作日志 | [`stage1/1.2-log/timeline.md`](stage1/1.2-log/timeline.md) |
| 1.3 | 向量加法执行过程（波形分析） | [`stage1/1.3-vadd/`](stage1/1.3-vadd/) |
| 2.1 | 指令设计文档 | [`stage2/2.1-design/`](stage2/2.1-design/) |
| 2.2 | RTL 实现（9 个基线补丁；重定时补丁另存 `patches/0005-…`） | [`stage2/2.2-rtl/`](stage2/2.2-rtl/) |
| 2.3.1 | 正数点积测试 | [`stage2/2.3.1-pos/`](stage2/2.3.1-pos/) |
| 2.3.2 | 负数点积测试 | [`stage2/2.3.2-neg/`](stage2/2.3.2-neg/) |
| 2.3.3 | 边界值测试 | [`stage2/2.3.3-bound/`](stage2/2.3.3-bound/) |
| 3.1.1 | NEMU 指令扩展 | [`stage3/3.1.1-nemu/`](stage3/3.1.1-nemu/) |
| 3.1.2 | NEMU 与 RTL 协同仿真 | [`stage3/3.1.2-difftest/`](stage3/3.1.2-difftest/) |
| 3.2 | 基线组合指令实现 | [`stage3/3.2-baseline/`](stage3/3.2-baseline/) |
| 3.3 | 延迟与加速分析报告 | [`stage3/3.3/report.md`](stage3/3.3/report.md) |

- [`design/SPEC.md`](design/SPEC.md)：语义、编码与非法判定；[`design/ARCHITECTURE.md`](design/ARCHITECTURE.md)：微架构、RTL 落点、2 拍时序
- [`design/ALGORITHM.md`](design/ALGORITHM.md)：19 位归约推导与测量定义；[`design/CODING-STD.md`](design/CODING-STD.md)：Chisel 与 C 代码规范
- 用例清单：[`design/verify/cases/manifest.tsv`](design/verify/cases/manifest.tsv)（30 行）与 [`manifest.extra.tsv`](design/verify/cases/manifest.extra.tsv)（224 行）
- [`stage3/3.3/sections/perf-repeat.md`](stage3/3.3/sections/perf-repeat.md)：4 次重复的逐值表、中位数/极差与加速比分母；[`co-sim.md`](stage3/3.3/sections/co-sim.md)：协同验证机制图与 DIFFTEST 参数表；[`tri-consistency.md`](stage3/3.3/sections/tri-consistency.md)：三端用例对照

## 上游版本与致谢

本工作基于香山昆明湖 V2（`a4eeaab`）与 YunSuan 向量实现（`9559211`，其 `rocket-chip` 子模块为 `46f1efe`），参考模型基于 NEMU（`a683e0b`），编码空间核对使用 riscv-opcodes 快照 `f24ac23`，并感谢 OpenXiangShan 社区维护这三个上游项目。结果产物对应 2026-11-01 基线，当前工作区检出已前移到实施 HEAD（`913ddd3` / `8942811` / `a9dca53`）。上游各组件的著作权与许可归其各自项目所有，版本锚点写在 [`versions.env`](versions.env)。更新日期：2026/11/08。

![VelvetDot key visual](assets/velvetdot-keyvisual.png)

![VelvetDot poster](assets/velvetdot-poster.png)
