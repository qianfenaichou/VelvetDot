# vdot.vv · 香山昆明湖 V2 的 K=8 int8 点积向量指令

`vdot.vv` 是一条 RISC-V 向量扩展（RVV）自定义指令：单条指令完成 **8 个 int8 元素的点积**（SEW=8、LMUL=1、K=8 单结果），把 19 位内部累加结果符号扩展后写回向量寄存器 `vd` 的低 32 位，`vd` 的高 96 位恒为零。本仓库包含该指令的规格、Chisel RTL 实现、NEMU 参考模型、Python 金模型、协同仿真用例，以及三阶段的测试与性能分析材料。

目标场景是 INT8 量化推理中的点积密集算子。`design/verify/cases/perf_llm_attn.c:1-30` 按 llama.cpp `ggml_vec_dot_q8_0_q8_0` 的 block 内层点积同形构造 attention QK 基准：QK=32 的 block 由 4 个 K=8 子块组成，head_dim=64 时为 8 个子块。

## 指令规格

| 项 | 定义 |
|---|---|
| 指令 | `vdot.vv vd, vs2, vs1`（OPMVV，无掩码） |
| 语义 | `S = Σ(i=0..7) sext19( sext8(vs1[i]) × sext8(vs2[i]) )` |
| 参与元素 | 仅 vs1/vs2 的低 64 位（lane 0–7）；高 64 位不参与 |
| 内部位宽 | 19 位有符号；最坏 `8×(−128)×(−128) = 131072`，超出 18 位有符号上限 131071 |
| 写回 | `vd[31:0] = sext32(S)`，`vd[127:32] = 0`；不读旧 vd，`vxsat` 不变，`vl`/`vta`/`vma` 不影响结果 |
| 合法条件 | `SEW=8 ∧ LMUL=1 ∧ vm=1 ∧ vstart=0 ∧ vill=0 ∧ mstatus.VS≠OFF`，任一不成立即非法；非法判定优先于 `vl=0` 全写 |
| 编码 | opcode `1010111` / funct3 `010` / funct6 `001110` / vm `1` |
| 机器码示例 | `vdot.vv v3, v2, v1` = `0x3A20A1D7` |

规格全文见 [`design/SPEC.md`](design/SPEC.md)。编码空间据 `design/SPEC.md` §2.1 与复核记录 [`stage2/2.1-design/encoding-gate-zvbc-2026-10-31.md`](stage2/2.1-design/encoding-gate-zvbc-2026-10-31.md)：在 riscv-opcodes 快照 `f24ac23` 的 funct3=010 / opcode=0x57 空间内，`001110` 空闲；同一空间的 `0x0C` 已被 Zvbc `vclmul.vv` 占用，故未采用。

## 特性

- **复用既有向量乘法通路。** 不新增乘法阵列，也不改动共用的 `VimacCfg`：`VIMac64b` 在 SEW=8 下已算出 8 个 16 位积（`sum_wo`），本设计只补一级跨 lane 水平归约——新增 `VdotReduce`（4:2 压缩树 + 19 位进位传播加法），在 `VIMacU` wrapper 层以输出 Mux 旁路 Mgu（向量写回末尾的掩码/尾部合并单元，负责按 `vta`/`vma` 合并掩码与旧值，见 `design/ARCHITECTURE.md` §2.2）。
- **面积与时序开销可控。** Yosys 0.48 综合：`VdotReduce` 500 cells、最长路径 14 级；跨拍寄存器重定时前为 481 cells / 22 级。`VIMac64b` 本体 42,783 cells，两版同值。测量口径（范围与定义）为仅 vdot 数据通路模块，不含 VIMacU 其余部分与工艺库。
- **沿用 2 拍执行契约。** 归约结果与 `walOut` 同拍寄存（`io.fireS1` 使能），对齐 `VimacCfg.latency = CertainLatency(2)` 的既有 2 拍配置；实测依赖链 `L_vdot = 4` cyc，与 `vmacc.vv` 相同。
- **恒定写回，无尾/掩码处理。** 高 96 位恒零、不读旧 vd，与 `vl`、`vta`、`vma` 无关；写回路径不依赖 Mgu，也不使用 `set_vreg_tail` 一类清零手段。
- **非法判定在译码层。** 六条必要条件由译码链联合判定：编码 `BitPat` 钉死 `vm=1`（rocket-chip `Instructions.scala`），`VecExceptionGen` 判 SEW / LMUL / vstart / vill，`DecodeUnit.scala:908` 拦截 `mstatus.VS=OFF`；`Mgu.illegal` 恒为 false，不能依赖 FU 报错。NEMU 侧同口径。
- **三端同口径、测试可判定。** RTL、NEMU、Python 金模型使用同一组语义；difftest 要求向量寄存器参与比较、正例必须命中用例自检串、负例必须双侧一致陷入非法，以避免测试空跑（看起来通过、实际未验证）。
- **金模型三算法交叉。** `vdot_model_test.py` 以三套独立算法（19 位模型 / 位级 16 位积加 sext19 / 任意精度求和）逐例比对，共 1142 例：覆盖定向边界（`131072`、`129032`、`−130048`、零、`±127`、`−128`、奇数个负 lane）、固定种子 42 的随机 1000 组、非法集合，以及 `vl`/`vta`/`vma` 不变性。

## 仓库结构

```
patches/            10 个补丁：9 个功能/单测补丁 + 1 个跨拍重定时补丁（P-2）
design/
  SPEC.md           指令语义、编码、非法判定
  ARCHITECTURE.md   微架构、8 处 RTL 改动点、2 拍时序、Mgu 旁路
  ALGORITHM.md      19 位归约推导、金模型与用例算法、性能测量定义
  CODING-STD.md     Chisel / C 代码规范
  verify/           金模型、1142 例断言测试、用例生成与清单、编码校验、形式 miter、面积脚本
core-package/       集群执行脚本（18 个）与部署/运行手册 README.md
results/            实测产物：difftest、yosys 面积、formal、lint、wave、coverage
stage1/             阶段一 1.1 环境验证 / 1.2 操作日志 / 1.3 向量加法执行过程
stage2/             阶段二 2.1 设计文档 / 2.2 RTL / 2.3.1–2.3.3 正、负、边界测试
stage3/             阶段三 3.1.1 NEMU / 3.1.2 协同仿真 / 3.2 基线 / 3.3 延迟分析
docx/               赛题原文与评分细则
versions.env        版本锚点：XiangShan / YunSuan / NEMU 的基线 commit
```

上游源码树不在本仓库内（`repos/` 与 `out/`、`downloads/` 一并被 `.gitignore` 排除），按下方复现步骤克隆。

## 复现

### 1. 取上游源码

| 仓 | 基线 | 上游 |
|---|---|---|
| XiangShan | `a4eeaab`（`kunminghu-v2`） | <https://github.com/OpenXiangShan/XiangShan> |
| YunSuan（XiangShan 子模块） | `9559211` | <https://github.com/OpenXiangShan/YunSuan> |
| rocket-chip（XiangShan 子模块） | `46f1efe` | <https://github.com/OpenXiangShan/rocket-chip> |
| NEMU | `a683e0b` | <https://github.com/OpenXiangShan/NEMU> |

```sh
git clone https://github.com/OpenXiangShan/XiangShan.git repos/XiangShan
git -C repos/XiangShan checkout a4eeaab
git -C repos/XiangShan submodule update --init --recursive   # yunsuan 9559211、rocket-chip 46f1efe
git clone https://github.com/OpenXiangShan/NEMU.git repos/NEMU
git -C repos/NEMU checkout a683e0b
```

构建工具链（mill、JDK、Verilator、RISC-V GCC）按上游仓库要求安装；`core-package/` 下的批量脚本按 SLURM 集群编写，落位与模块加载见 [`core-package/README.md`](core-package/README.md)。

### 2. 应用补丁

```sh
# 叶子仓先行：rocket-chip / yunsuan
git -C repos/XiangShan/rocket-chip apply -p1 "$PWD/patches/0001-X1-add-VDOT_VV-custom-encoding-funct6-001-rocketchip.patch"

git -C repos/XiangShan/yunsuan apply -p1 "$PWD/patches/0001-X6-X7-VimacOpcode.vdot-3-b111-and-VimacType.-yunsuan.patch"
git -C repos/XiangShan/yunsuan apply -p1 "$PWD/patches/0002-X15-export-sum_wo-walOut-fireS1-from-VIMac64-yunsuan.patch"
git -C repos/XiangShan/yunsuan apply -p1 "$PWD/patches/0003-X-new-VdotReduce-K-8-int8-dot-product-reduct-yunsuan.patch"
git -C repos/XiangShan/yunsuan apply -p1 "$PWD/patches/0005-X-new-P-2-VdotReduce-carry-save-retiming-yunsuan.patch"

# 主仓：译码、非法判定、wrapper、Chisel 单测（含子模块指针行）
git -C repos/XiangShan apply -p1 "$PWD/patches/0001-X1-X2-decode-VDOT_VV-as-OPMVV-F-vimac-Vima-xiangshan.patch"
git -C repos/XiangShan apply -p1 "$PWD/patches/0002-X14-vdot-legality-predicate-in-VecExceptio-xiangshan.patch"
git -C repos/XiangShan apply -p1 "$PWD/patches/0003-X8-wrapper-bypasses-Mgu-for-vdot-and-asser-xiangshan.patch"
git -C repos/XiangShan apply -p1 "$PWD/patches/0004-tests-VdotReduce-Chisel-B-19-200-xiangshan.patch"

# NEMU 参考模型
git -C repos/NEMU apply -p1 "$PWD/patches/0001-N1-N2-N3-vdot.vv-reference-model-decode-entry-E-nemu.patch"
```

三点注意事项：

- 补丁路径用绝对路径。`git -C <dir> apply` 会把相对路径解析到 `<dir>` 内，写成 `patches/…` 会直接报「无法打开补丁」并返回 128。
- `0005` 必须跟在 `0003` 之后：两者修改同一文件 `VdotReduce.scala`，顺序反了会冲突。
- 主仓补丁含 `rocket-chip` / `yunsuan` 子模块指针行。在已初始化子模块的检出中，`git apply` 会打印 `warning: unable to rmdir 'yunsuan': 目录非空` 并返回 0，文件改动照常应用。

上述 10 个补丁在 pin 的基线上前向应用，逐仓干净落地（各仓独立 worktree 实测）。

### 3. 金模型自检（本地，秒级）

```sh
python3 design/verify/vdot_model_test.py
# ALL TESTS PASSED (1142 cases)      退出码 0
```

金模型也可直接作为库调用：

```python
import sys; sys.path.insert(0, "design/verify")
import vdot_model

vdot_model.encode_vdot_vv(3, 2, 1)                            # 0x3a20a1d7
vdot_model.vdot_vv(0x0101010101010101, 0x0101010101010101)    # 0x8（8 个 lane，每 lane 1×1）
```

### 4. 30 例协同仿真

脚本以 `CORE_DIR` 为落位根目录（默认 `/public/home/$USER/core`），落位方法见 `core-package/README.md` §1。

```sh
export CORE_DIR="${CORE_DIR:-/public/home/$USER/core}"

# 4.1 构建 30 例镜像与探针（需 riscv64-unknown-elf-gcc 与 nexus-am 源码树）
AM_HOME=/path/to/nexus-am HOST_IP="$(hostname -I | awk '{print $1}')" \
  bash design/verify/cases/build_all.sh design/verify/cases

# 4.2 展开清单：把 @IMG_DIR@ 替换为镜像绝对路径
mkdir -p "$CORE_DIR/test"
bash design/verify/cases/make_manifest.sh "$PWD/design/verify/cases" > "$CORE_DIR/test/manifest.tsv"

# 4.3 构建香山 emu 与 NEMU 参照 .so
sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 "$CORE_DIR"/scripts/10-build-emu.sh --src-root "$CORE_DIR/src"

# 4.4 跑完整清单（30 例，含随机 1024 组、期望值反例与性能测量）
sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 "$CORE_DIR"/scripts/20-run-difftest.sh --full
```

判据见 `core-package/scripts/20-run-difftest.sh:14-21`：正例须 `HIT GOOD TRAP`、`ABORT=0` 且命中用例自检串；负例须双侧一致陷入非法；`cases_all_ran` 与 `cases_pass` 均要求 30/30。用例清单为 [`design/verify/cases/manifest.tsv`](design/verify/cases/manifest.tsv)（30 数据行，sha256 `a90d1071…`）。

> 本节命令按仓库脚本与 2026-11 的实跑记录整理，未在本次文档更新中重跑（本机无 RISC-V 工具链、mill 与 Verilator）。下方结果均取自 `results/` 下的作业产物。

## 实测结果

| 项目 | 结果 | 证据 |
|---|---|---|
| 30 例功能回归 | 30/30 通过，`regression_delta=0` | `results/difftest/20-full-20261107T104227.json` |
| 扩容用例 | 129/129 通过，负例 41/41 | `results/difftest/94-extra-20261107T104230.json` |
| 金模型 | 1142 例通过（三算法交叉） | `python3 design/verify/vdot_model_test.py` |
| 面积（Yosys 0.48） | `VdotReduce` 500 cells / 最长路径 14 级 | `results/yosys/40-area-20261107T104238.json` |
| 形式验证 | miter 正控 `SUCCESS`、负控 `FAIL`（仅数据通路） | `results/formal/50-miter-20261104T093531.json` |
| 依赖延迟 | `L_vdot = 4` cyc（`L_vmacc = 4`、`L_vadd = 3`） | `results/difftest/20-full-20261107T104227.json` → `metrics[]` |
| 背靠背吞吐 | `T_steady = 1` cyc/dot | 同上 |
| 基线组合每点开销 | `B1 = 6`、`B2 = 9` cyc/dot（内部自设的测量定义） | 同上；定义见 `stage3/3.3/report.md` §1 |

性能数字的测量定义互不可替代：`L_*` 是依赖链延迟，`T_steady` 与 `B1`/`B2` 是每点周期，两类不可混用；基线为"用已有向量指令组合实现同等功能"的自设序列（`vwmul.vv + vwredsum.vs` 与 `vwmul.vv + vwadd.vx + vredsum.vs`），非官方规定的测量定义。

## 材料索引

官方 12 项交付物的位置（编号对应 [`docx/02-赛题与评分细则.md`](docx/02-赛题与评分细则.md)）：

| 编号 | 内容 | 位置 |
|---|---|---|
| 1.1 | 环境部署验证 | `stage1/1.1-env/` |
| 1.2 | 部署与操作日志 | `stage1/1.2-log/timeline.md` |
| 1.3 | 向量加法执行过程（波形分析） | `stage1/1.3-vadd/` |
| 2.1 | 指令设计文档 | `stage2/2.1-design/` |
| 2.2 | RTL 实现 | `stage2/2.2-rtl/`（9 个基线补丁；P-2 重定时补丁另存 `patches/0005-X-new-P-2-…`） |
| 2.3.1 | 正数点积测试 | `stage2/2.3.1-pos/` |
| 2.3.2 | 负数点积测试 | `stage2/2.3.2-neg/` |
| 2.3.3 | 边界值测试 | `stage2/2.3.3-bound/` |
| 3.1.1 | NEMU 指令扩展 | `stage3/3.1.1-nemu/` |
| 3.1.2 | NEMU 与 RTL 协同仿真 | `stage3/3.1.2-difftest/` |
| 3.2 | 基线组合指令实现 | `stage3/3.2-baseline/` |
| 3.3 | 延迟与加速分析报告 | `stage3/3.3/report.md` |

设计与验证正文：[`design/SPEC.md`](design/SPEC.md)、[`design/ARCHITECTURE.md`](design/ARCHITECTURE.md)、[`design/ALGORITHM.md`](design/ALGORITHM.md)、[`design/CODING-STD.md`](design/CODING-STD.md)。

## 上游与致谢

本工作基于香山（XiangShan）昆明湖 V2 与 YunSuan 向量实现，参考模型基于 NEMU；编码空间核对使用 riscv-opcodes 快照 `f24ac23`。上游各组件的著作权与许可归其各自项目所有。