# vdot.vv：香山昆明湖 V2 上的 K=8 int8 点积指令

`vdot.vv` 是加在香山昆明湖 V2 向量后端上的一条自定义向量指令：SEW=8、LMUL=1、K=8，一条指令对两个源向量寄存器低 64 位的 8 对 int8 求点积，内部用 19 位有符号数累加，结果符号扩展到 32 位写回 `vd[31:0]`，`vd[127:32]` 恒零，不读旧 vd。

## 团队与项目信息

- **团队**：芯芯像绒（`XinXiangXiangRong`）
- **参赛单位**：南昌交通学院
- **指导老师**：徐婧
- **赛题**：面向边缘 AI 大语言模型推理的 RISC-V 自定义 vdot 指令设计——基于“香山”昆明湖 V2 处理器架构
- **交付物**：官方 12 项材料与十章技术正文

## 三个阶段完成了什么

**阶段一（[`stage1/`](stage1/README.md)）**：在集群上把香山模拟器从零部署起来，工具链探针 `status=通过`（gcc 13.3.0、Verilator 5.053、Yosys 0.48，2026-11-05），hello 程序打印团队标识与执行节点地址。部署与操作过程整理成带时间戳的时间线（[`stage1/1.2-log/timeline.md`](stage1/1.2-log/timeline.md)）。另用 `vadd.vv` 的 VCD 波形把向量加法逐拍拆到七级流水，逐级标出 RTL 行号，配波形截图（[`stage1/1.3-vadd/README.md`](stage1/1.3-vadd/README.md)）。

**阶段二（[`stage2/`](stage2/)）**：三份设计文档定下语义、19 位内部位宽、编码与非法判定（[`stage2/2.1-design/`](stage2/2.1-design/README.md)）。RTL 以补丁形式实现 8 处改动加 1 个 Chisel 单测（[`stage2/2.2-rtl/README.md`](stage2/2.2-rtl/README.md)）。正数、负数、边界三类功能测试各有独立用例与源码（[`stage2/2.3.1-pos/`](stage2/2.3.1-pos/README.md)）。

**阶段三（[`stage3/`](stage3/README.md)）**：NEMU 加入同语义的表项与执行函数，与 RTL 做逐指令差分验证：主回归 30/30、扩容 224/224（[`stage3/3.1.2-difftest/`](stage3/3.1.2-difftest/README.md)）。用已有 RVV 指令组合出等价基线：主链是三条串行指令（`vwmul.vv → vwadd.vx → vredsum.vs`，16 周期），另测两个基线内核 B1=6、B2=9 周期/点（[`stage3/3.2-baseline/`](stage3/3.2-baseline/README.md)）。延迟与加速分析报告给出三个计时定义和两个比值的完整推导（[`stage3/3.3/report.md`](stage3/3.3/report.md)）。

## 仓库内容

| 目录 | 放什么 | 从哪读起 |
|---|---|---|
| [`docs/正文/`](docs/正文/01_项目概述与任务对应.md) | 十章技术正文，从任务对应到形式验证与局限 | [`01_项目概述与任务对应.md`](docs/正文/01_项目概述与任务对应.md) |
| [`stage1/`](stage1/README.md) | 阶段一：环境部署验证、操作日志、vadd 波形文档 | [`stage1/README.md`](stage1/README.md) |
| [`stage2/`](stage2/) | 阶段二：设计文档、RTL 实现、三类功能测试 | [`stage2/2.1-design/README.md`](stage2/2.1-design/README.md) |
| [`stage3/`](stage3/README.md) | 阶段三：NEMU 扩展、差分验证、基线实现、延迟报告 | [`stage3/3.3/report.md`](stage3/3.3/report.md) |
| [`design/`](design/SPEC.md) | 规格、微架构、算法、代码规范，以及参考模型与用例 | [`design/SPEC.md`](design/SPEC.md) |
| [`patches/`](patches/) | 从上游基线到实现的全部代码改动 | [`stage2/2.2-rtl/CHANGES.md`](stage2/2.2-rtl/CHANGES.md) |
| [`results/`](results/) | 差分验证、性能、综合、时序、功耗、形式验证、覆盖的原始产物 | [`results/difftest/`](results/difftest/) |
| [`core-package/`](core-package/README.md) | 集群调度脚本、环境探针、落位手册 | [`core-package/README.md`](core-package/README.md) |
| [`docx/`](docx/02-赛题与评分细则.md) | 赛题原文与评分细则 | [`docx/02-赛题与评分细则.md`](docx/02-赛题与评分细则.md) |
| [`docs/口播/`](docs/口播/01_阶段一操作.md) | 三段录屏的分镜表与逐字稿（成片未产出） | [`01_阶段一操作.md`](docs/口播/01_阶段一操作.md) |

## 实现与主要结果

**语义**：`S = Σ(i=0..7) sext19(sext8(vs1[i]) × sext8(vs2[i]))`，只取 vs1、vs2 的低 64 位（lane 0–7），内部 19 位有符号——最坏正和 `8×(−128)×(−128) = 131072` 超出 18 位有符号上限 131071，所以第 19 位不能省。

**微架构**：复用 `VIMac64b` 在 SEW=8 下已算出的 8 个 16 位积，只补一级 4:2 压缩树加 19 位进位传播加法器（`VdotReduce`），不新增乘法阵列，共用的 `VimacCfg` 未改。基线版把压缩树、加法器与格式化都放在寄存器之前，结果在 `fireS1` 后寄存；交付版改用重定时，见下段。两版拍数相同，都是两拍。写回走 wrapper 的输出 Mux 旁路 Mgu，因为 Mgu 的 tail 处理会把旧 vd 带回或写 `0xFF`。

下表的「基线版」指未重定时的实现，「重定时版」把进位保存的 `(sum, carry)` 跨拍寄存、把进位传播加法器后移一级，是交付实现。

| 测量 | 结果 | 条件 | 证据 |
|---|---|---|---|
| 主回归 30 例 | 30/30 通过，`regression_delta=0` | 30 行固定清单，整份 `--full`，重定时版树，2026-11-07 | [`20-full-20261107T104227.json`](results/difftest/20-full-20261107T104227.json) |
| 扩容 224 例 | 224/224 通过，负例 57/57 如期陷入非法 | 224 行独立清单，不与主回归合并 | [`94-extra-20261108T014445.json`](results/difftest/extra/94-extra-20261108T014445.json) |
| 依赖链延迟 `L_vdot` | 4 周期/次，4 次重复 4/4/4/4，极差 0 | 真 RAW 依赖链，emu 的 `rdcycle`，非硅 | [`99-perf-repeat-4x-20261108.json`](results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json) |
| 稳态吞吐 `T_steady` | 1 周期/次，4 次重复均为 1 | 背靠背独立操作，与 `L_vdot` 不是同一段时间 | [`99-perf-repeat-4x-20261108.json`](results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json) |
| 每指令归一加速比 | 1.333×，`(16/3)/4`，4 次重复同值 | 分子 `L_base_chain=16` 来自同一基线链的另一次测量，分母 4 是这批重测的 `L_vdot` | [`99-perf-repeat-4x-20261108.json`](results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json) |
| 点积单元规模 | 481 cells（基线版）/ 500 cells（重定时版），占 `VIMac64b` 42783 cells 的 1.12% / 1.17% | Yosys 通用门计数，不是硅面积 | [`vdot-k1.stat.json`](results/yosys/vdot-k1.stat.json)、[`vdot-p2.stat.json`](results/yosys/vdot-p2.stat.json) |
| 模块级时序 | 最差路径 1084.3 ps（基线版）/ 658.8 ps（重定时版），333 ps 与 500 ps 约束下 slack 均为负 | Nangate45 代理库、预布局、理想时钟；两版起点终点不同，数值不可相减 | [`worst_slack_20261108.tsv`](results/sta/20261108/worst_slack_20261108.tsv) |
| 形式等价 | 正控 `SUCCESS`，变异负控 `FAIL` | 3 拍有界，只证 `vdot_dp` 数据通路，不含流水与旁路 | [`50-miter-20261104T093531.json`](results/formal/50-miter-20261104T093531.json) |

依赖链延迟与稳态吞吐的起止点不同，不能相减或相除。表里的加速比按每条指令归一（`(16/3)/4`），分子 `16` 是三条串行指令的整链周期，除以 3 平摊到每条指令后，再除以分母 `L_vdot`。

结构覆盖只采到行覆盖：30 个 `.dat` 覆盖文件合并后，SimTop 顶层行覆盖 67.5%（113628/168283），这个分母绝大部分与 vdot 无关；vdot 三个模块的条件行计数是 1/1、3/3、3/3，toggle 与 branch 未采集（[`verilator_coverage-summary.txt`](results/coverage/20261108T103732/merged30all.coverage/verilator_coverage-summary.txt)）。K=16 扩展只做了独立数据通路的综合与一次 2 拍有界的等价检查尝试（未成立），977 cells，未集成进 `VIMacU`，不能当作整核面积增量。

## 编译与复现

完整步骤、每步成功标志与已知问题见 [`REPRODUCE.md`](REPRODUCE.md)。最短的三条：

```sh
python3 design/verify/vdot_model_test.py                       # 参考模型自检 → ALL TESTS PASSED (1142 cases)
python3 -I design/verify/cases/extra_crosscheck.py --quiet     # 224 例期望值交叉核对 → verdict=MATCH
sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 "$CORE_DIR"/scripts/20-run-difftest.sh --full   # 30 例主回归 → cases_pass=30/30
```

前两条在本机秒级完成，成功标志分别是 `ALL TESTS PASSED (1142 cases)` 与 `verdict=MATCH`。第三条要在集群上执行，需先按 [`REPRODUCE.md`](REPRODUCE.md) 落位源码树、镜像与清单。

## 材料与证据入口

- [`docs/README.md`](docs/README.md)：正文、附录与口播稿的入口，含评委二十分钟与一小时的两种阅读顺序
- [`EVIDENCE_INDEX.md`](EVIDENCE_INDEX.md)：一行一条证据，给出文件、它证明什么、生成方式与对应结论
- [`VALIDATION.md`](VALIDATION.md)：每条结论的验证方式、结果、以及明确没做什么

## 版本与许可

基线为香山昆明湖 V2 `a4eeaab`、yunsuan `9559211`、NEMU `a683e0b`，锚点写在 [`versions.env`](versions.env)；补丁按 `a4eeaab` 检出的上游代码生成。实现共 10 个补丁、15 个文件条目、+272/−12 行（按各补丁 diffstat 相加）。香山主仓、yunsuan 子模块与 NEMU 的上游 `LICENSE` 均为木兰宽松许可证第 2 版，rocket-chip 子模块自带 `LICENSE.SiFive`、`LICENSE.Berkeley`、`LICENSE.jtag` 三份许可文件；上游源码树在 `repos/`，不随本仓库提交，按 [`REPRODUCE.md`](REPRODUCE.md) 检出即含各自许可证文件。本仓库的改动以补丁形式提供，补丁所含上游代码的著作权归各上游项目所有。
