# 4.13 P-2 跨拍 CPA 重定时：`(sum, carry)` 冗余对过 `fireS1` 边界（实测量化）

> **小节归属**：本文件并入 `stage3/3.3/report.md` **§4.13**（§4.6 专题小节的第七件；本节编号按 `4.13.x` 书写）。**正文只写本节实测**，不引用未复跑的外部数字。
>
> 日期：2026-11-07 ｜ 设计依据：P-2 预登记（候选 A）
> 改动文件：`repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala`（**仅此一个**；`+19 / −6` 行，`git -C repos/XiangShan/yunsuan diff --stat` 实测）
> 昆山作业：重建 `127135641` ｜ 30 例 `--full` `127137638` ｜ 面积 K1 `127135437`、P-2 `127137643` ｜ extra 129 `127137640`
> 证据（本地副本，与远端同 sha256）：`results/emu/10-build-20261107T100125.{json,log}`、`results/difftest/20-full-20261107T104227.{json,log,cases.tsv}`、`results/difftest/94-extra-20261107T104230.{json,log,cases.tsv}`、`results/yosys/40-area-20261107T095404.*`（K1）、`results/yosys/40-area-20261107T104238.*`（P-2）、`results/yosys/vdot-{k1,p2}.{stat.json,ltp.txt,stat.cmos.txt}`
>
> **公开仓可复现性（2026-11-07 终检披露）**：P-2 的源码改动在本机子仓 `repos/XiangShan/yunsuan` @ `8942811`（父提交 `83059b5`），完整 diff 已按 `git -C repos/XiangShan/yunsuan format-patch -1 8942811` 原样落到根仓 `patches/0005-X-new-P-2-VdotReduce-carry-save-retiming-yunsuan.patch`（3,587 B，sha256 `2d25778c…`；在 `83059b5` 工作树上 `git apply --check` rc=0，在 `8942811` 上 `git apply -R --check` rc=0）。**公开仓 `origin/master=4e323d8` 不收录该 patch，且 `repos/` 被 `.gitignore` 排除**（`git ls-tree -r 4e323d8 | grep -c '^repos/'` = 0），故只按公开仓的 9 个基线 patch 复现得到 K1 的 **481 / 4,900 / 22**，**得不到本节的 500 / 4,900 / 14**；评审复现 500/14 须在 `0002-X15`、`0003-X-new` 之后应用 `patches/0005-…`，再按 §4.13.7 重跑。本节的 500/14 是**本地实测值**，其可复现性以该 patch 为准。

---

## 4.13.1 结论（先看这里）

| # | 结论 | 证据 |
|---|---|---|
| C1 | **改动面 = 一个文件、一处切点**：4:2 树的 `(sum, carry)` 冗余对（2×19 = **38 FF**）过 `io.fireS1` 边界，19 位 CPA 与 `Cat(96'b0, sext32(S))` 格式化移到寄存之后的**输出拍（S3）**；`VdotReduce` 的三个端口（`sum_wo`/`fireS1`/`vd`）、`VIMac64b`、共享 `VimacCfg`、wrapper `VIMacU.scala` **均未改**。 | `VdotReduce.scala:49-57`；生成的 SV：`reg [18:0] sumS2/carryS2`、`assign io_vd = {96'h0, {13{cpa[18]}}, cpa}`（§4.13.2） |
| C2 | **面积实测 481 → 500 cells（+19）**，组合部分 **458 → 458（不变）**，增量**恰好是 38−19 = 19 个 FF**；`VIMac64b` 对照 42,783 / ltp 100 逐值未变。 | `40-area-20261107T104238.json`；`vdot-p2.stat.json` 的 `$_DFFE_PP_ = 38`、`$scopeinfo = 4`（§4.13.3） |
| C3 | **最长组合路径 22 → 14 级（−8 级，−36.4%）**，且 ltp 报出的起点是 `\sumS2`（即寄存器之后的 CPA 段），说明 S2 侧树锥已不再是模块最长路径。 | `vdot-k1.ltp.txt` 22 级 vs `vdot-p2.ltp.txt` 14 级（起点 `\sumS2`） |
| C4 | **功能未被破坏**：30 例 `--full` `status=通过`、`cases_pass=30/30`、9/9 criteria 达标、`regression_delta=0`、自检串 21/21、G0 反例捕获 1/1；**`L_vdot` 仍为 4 cyc**（`T_steady=1`、`T_kernel=290`、`B1/B2=6/9` 均与 K1 同值）⇒ 2 拍契约与延迟口径未变。 | `20-full-20261107T104227.json`（§4.13.4） |
| C5 | **清单外补强同样通过**：extra 129 例 `status=通过`、129/129、8/8 criteria 达标，其中 **`golden_crosscheck=达标`（`EXTRA_CROSSCHECK verdict=MATCH`）**、自检串 86/86、G0 2/2、负例 41/41、`vdot_rand10k`（10,000 组随机）通过。 | `94-extra-20261107T104230.json`（V12） |
| C6 | **口径**：P-2 是**时序裕量/面积**方向的改动，**不是加速**；`ltp` 只作相对级数、不换 ps、不代表频率；全节**不写「收敛」**（无 STA/liberty）。 | 本节全部数字均为 Yosys 0.48 同脚本同口径实测 |

---

## 4.13.2 改了什么（before / after 结构）

**before（K1，`83059b5`）**：`sum_wo[8×16b] → sext19 → 4:2 树(pipeLevel=0) → 19 位 CPA(+&) → Cat(96'b0, sext32) → RegEnable(·, fireS1)`。寄存器只有格式化后的 19 位（高 96 位恒零，被综合折叠），全模块最长组合路径 = 树 + CPA = 22 级。

**after（P-2）**：`sum_wo → sext19 → 4:2 树 → RegEnable(out_sum/out_car, fireS1) [38 FF] → 19 位 CPA(+&) → Cat(96'b0, sext32) → io.vd`。CPA 与格式化变成**寄存后组合输出**，在输出级与 `mgu.io.out.vd` 经 `Mux(outIsVdot, …)` 并联选路（该 Mux 在 K1 已存在，未改）。

代码锚点（`VdotReduce.scala`，改后 58 行）：

| 行 | 内容 |
|---|---|
| `:29-33` | IO：`sum_wo: Input(Vec(8, UInt(16.W)))`、`fireS1: Input(Bool())`、`vd: Output(UInt(128.W))` —— **三项与 K1 逐字相同** |
| `:40-43` | 4:2 树（`pipeLevel = 0`，`tree.io.fire := io.fireS1` 保留） |
| `:49-50` | `sumS2 = RegEnable(tree.io.out_sum, io.fireS1)`、`carryS2 = RegEnable(tree.io.out_car, io.fireS1)` —— 新增 38 FF |
| `:52-54` | `cpa = sumS2 +& carryS2`、`s19 = cpa(18,0)` —— CPA 移到此拍 |
| `:57` | `io.vd := Cat(0.U(96.W), s19.asSInt.pad(32).asUInt)` —— 格式化 + 直出（K1 这里还有一层 `RegEnable`） |

**生成的 SystemVerilog 逐行核对**（`build/rtl/VdotReduce.sv`，2026-11-07 10:17:39，`sumS2/carryS2` 命中 7 行）：

```
reg  [18:0] sumS2;
reg  [18:0] carryS2;
wire [18:0] cpa = 19'(sumS2 + carryS2);
      sumS2   <= _tree_io_out_sum;      // fireS1 使能
      carryS2 <= _tree_io_out_car;
assign io_vd = {96'h0, {13{cpa[18]}}, cpa};   // = Cat(96'h0, sext32(s19))，96+13+19 = 128
```

**与「加一级流水」的区别（本节的定义口径）**：寄存器使能仍是从 `VIMac64b` 端口取来的 `io.fireS1`（`design/CODING-STD.md` §3.4 的约定不变），寄存器边界与 K1 同一拍；变的只是**过边界的数据表示**（解析后的和 → 冗余 `(sum, carry)` 对）与**边界后的算术位置**。因此 `VimacCfg` 的 latency=2 与外部看到的拍数不变（§4.13.4 的 `L_vdot=4` 是实测复核，不是推断）。

**未动清单（逐项，均可 grep 复核）**：`VIMac64b.scala` 与 `VimacCfg` 未改——`git -C repos/XiangShan/yunsuan status --porcelain` 只列 ` M …/VdotReduce.scala` 一行；`VIMacU.scala`（含死代码副本 `fu/vector/VIMacU.scala`）未改——`git -C repos/XiangShan status --porcelain -- <两个 VIMacU 路径>` → **0 行**；superproject 侧只多出 ` M yunsuan`（子模块指针/工作树变动，`git -C repos/XiangShan diff --submodule=short` 可复核）；`repos/YunSuan/` 零改动；30 例主清单 `design/verify/cases/manifest.tsv`（sha256 `a90d1071…`）未变。

---

## 4.13.3 面积与级数（同一 Yosys 0.48 脚本，before / after）

口径与官方面积作业一致：`core-package/scripts/40-yosys-area.sh`（`synth → flatten → stat -json → stat -tech cmos → ltp -noff`），**只综合数据通路模块、无工艺库**；两版用同一脚本、同一节点类型（`kshcnormal`），各自作业独立。

| 版本 | 作业 | cells | 其中组合 | `$_DFFE_PP_` | `$scopeinfo` | 晶体管估算 | ltp |
|---|---|---:|---:|---:|---:|---:|---:|
| **K1（基线，重跑 sanity）** | `127135437` | **481** | 458 | **19** | 4 | 4,900 | **22** |
| **P-2（本次改动）** | `127137643` | **500** | 458 | **38** | 4 | 4,900 | **14** |
| 差值 | — | **+19（+3.95% vs 481）** | 0 | +19 | 0 | 0 | **−8（−36.4%）** |
| 对照：`VIMac64b` | 同两作业 | 42,783 / 42,783 | — | — | — | 293,640 | 100 |

- **基线 sanity 成立**：K1 重跑逐值复现官方作业 `126752216`（`results/yosys/40-area-20261104T094144.json` 的 `481 / 4900 / 22`，`vdot.stat.json` 的 `$_DFFE_PP_=19`）⇒ 本次 500/14 与官方 481/22 是**同一把尺子**上的两个点，可直接相减。
- **与模型预期的对照（诚实差异）**：P-2 预登记的模型预期是 `cells=500`、`max(S2,S3)=15`；**实测 cells 逐值一致（500）**，ltp **比模型少 1 级（14 vs 15）**。模型只作相对增量，绝对值以本节实测为准。
- **占比（分母口径各自标注、不相减混用）**：P-2 的 500 cells 占 `VIMac64b` 全口径 42,783 的 **1.169%**（K1 为 481/42,783 = **1.124%**，差 **+0.044 个百分点**）；组合口径分母 41,945 时，P-2 组合仍为 458，**组合增量 0**。
- **DFF 指纹**：19 → **38**，与 P-2 预登记的 38 FF 预算一致（`38` 是判据值，不是估计）。

---

## 4.13.4 验证清单（逐项，命令 + 输出）

| # | 检查 | 命令（昆山） | 实测输出 | 判定 |
|---|---|---|---|---|
| V1 | 重新 elaborate + 编译 | `sbatch … 10-build-emu.sh --src-root ~/core/src`（前置 `rm -f build/rtl/SimTop.sv`，原因见 §4.13.5） | JSON `status=通过`；`build_emu: rc=0`；`nm_exec_vdot=命中 2 行` | 达标 |
| V2 | 构建冒烟 | 同上（脚本内置） | `rc=0 HIT_GOOD_TRAP=1 ABORT=0 BAD=0`；镜像 `microbench(fallback)` ⇒ `hello_evidence=no`（**不冒充 1.1 证据**） | 达标（仅构建冒烟） |
| V3 | 30 例 `--full` 用例 | `sbatch … 20-run-difftest.sh --full --manifest ~/core/test/manifest.p2-30.abs.tsv --emu ~/core-p2/emu-p2 --ref-so ~/core-p2/ref-p2.so` | `status=通过`、`cases_pass=30/30`、`cases_all_ran=30/30` | 达标 |
| V4 | 回归基线 | 同上（`--full` 自动比对 `results/difftest/baseline.tsv`） | `regression_delta=0` | 达标 |
| V5 | 防假通过（自检串） | 同上 | `selfcheck_req=21 / selfcheck_ok=21` | 达标 |
| V6 | G0 反例被判负 | 同上 | `g0_req=1 / g0_caught=1`（GOOD TRAP 但 `CASE …: MISMATCH`） | 达标 |
| V7 | 三口径 / T5 ΔL | 同上 | `L_vdot=4`、`T_steady=1`、`T_kernel=290`、`B1=6`、`B2=9`、`L_vadd=3`、`L_vmacc=4`（ΔL_mv=1） | 达标 |
| V8 | 面积 K1 sanity | `sbatch … 40-yosys-area.sh --vdot-rtl ~/core-p2/k1/vdot_dp.sv …` | `VdotReduce 481 / 4900 / 22`、`$_DFFE_PP_=19`（复现官方 `126752216`） | 达标 |
| V9 | 面积 P-2 | `sbatch … 40-yosys-area.sh --vdot-rtl ~/core-p2/rtl/area/vdot_dp.sv …` | `VdotReduce 500 / 4900 / 14`、`$_DFFE_PP_=38` | 达标 |
| V10 | 非 vdot 通路未回归 | V3 的 30 例含 `vadd-microbench`（vadd/vmacc 通路） | 该例 `通过`，且 `L_vadd=3`/`L_vmacc=4` 与 K1 同值 | 达标 |
| V11 | 清单未被改动 | 本地 `sha256sum design/verify/cases/manifest.tsv` | `a90d107118773ebb0de5c1518846680b174b03cf0eb0cdf8be333e582dddbab1`（30 数据行） | 未变 |
| V12 | extra 129（清单外补强） | `sbatch … 94-run-extra.sh --emu ~/core-p2/emu-p2 --ref-so ~/core-p2/ref-p2.so --manifest ~/core/test/manifest.extra.abs.tsv` | 作业 `127137640` `status=通过`：`cases_pass=129/129`、8/8 criteria 达标、**`golden_crosscheck=达标`（`EXTRA_CROSSCHECK verdict=MATCH`）**、自检串 86/86、G0 2/2、负例 41/41、`vdot_rand10k` 通过；墙钟 10:42:30→11:43:54 | 达标 |

> **关于「golden_crosscheck」**：`20-run-difftest.sh` **没有**这个 criterion 名（`grep -n golden_crosscheck core-package/scripts/20-run-difftest.sh` → 0 命中）；30 例里金模型的作用体现在 V5 的 21 条自检串——它们的期望值由 `design/verify/vdot_model.py` 金模型生成、编进镜像。带 `golden_crosscheck` 这个名字的判据在 `94-run-extra.sh`（extra 129 用 `extra_crosscheck.py` 逐条对拍金模型），V12 的结果为 `达标`。

---

## 4.13.5 诚实边界（必须与数字同页出现）

1. **无 STA / 无 liberty**：`ltp` 是 Yosys 拓扑级数，不是 ps、不是频率。因此本节只能说「最长组合路径从 22 级降到 14 级」，**不能**说「2 拍已收敛」「频率提升」——这属于禁止表述③的范围。
2. **S2 / S3 锥没有分开探**：`M-S2`/`M-S3` 切段探针本次**未建、未跑**；`ltp=14` 是**模块级**最长组合路径（起点 `\sumS2`），不能据此反推「S2 树锥 = 8 级」。
3. **面积只覆盖数据通路**：两版都是 `VdotReduce` 模块闭包、无标准单元库、无布线/时钟树；42,783 是 `VIMac64b` 对照口径，不含 `VIMacU` 其余部分。
4. **延迟不变是实测**：`L_vdot=4` 来自 30 例里的 `perf_vdot`（RAW ×2000 逐次 rdcycle），与 K1 的 4 同值；这支持「2 拍契约未被破坏」，但不等于「时序闭合」。
5. **构建系统陷阱（复现必读）**：`repos/XiangShan/Makefile:54` 的 `SCALA_FILE = $(shell find ./src/main/scala -name '*.scala')` **不覆盖 yunsuan 子模块**，所以只改子模块源码时 `make emu` 会报 `对"emu-mk"无需做任何事` 并**沿用旧 RTL**（本次首个作业 `127135545` 实测踩到，已 `scancel`、无证据价值）。复现本结果必须先 `rm -f build/rtl/SimTop.sv` 强制 re-elaborate，并在构建后 `grep sumS2 build/rtl/VdotReduce.sv` 校验。
6. **共享树并发**：本次与覆盖率作业共用 `~/core/src`（`build/emu` 曾被 `95-coverage.sh` 移走）。为免二进制被并发重建替换，构建成功后立刻把 `build/emu`、NEMU `.so` 快照到 `~/core-p2/`，30 例与 extra 作业都用**快照**跑（`--emu/--ref-so` 显式指定）。
7. **清单等价性**：昆山 30 例用的是 `manifest.p2-30.abs.tsv`——由冻结清单只做 `@IMG_DIR@ → /public/home/<account>/core/test/bin` 替换得到（`<account>` 为集群账号占位，执行时替换为实际账号）；数据行 `(cid, cls)` 投影与 `design/verify/cases/manifest.tsv` **完全一致**（两文件 `awk` 抽取后 sha256 同为 `c98eafcd…`），30 条镜像逐条 `test -f` 通过。
8. **不做跨实现优劣比较**：本节不做跨队优劣断言，也不引用其它实现的数字进入本节的数字论证。
9. **形式 miter 未跑【未运行】**：本次验证未要求 `50-formal-miter.sh`；且 P-2 把 `io.vd` 从「寄存器输出」改成「寄存器后组合」，miter 的 `-seq` 拍数需按 P-2 预登记的重定时口径重新校准后才能用，直接沿用旧结论不算证据。
10. **共享树的后续影响（后续注意项）**：本次把 `~/core/src/XiangShan` 的 `build/rtl` 与 `build/emu` 更新成了 P-2 版本；覆盖率作业若要在同一棵树上继续跑，需先把 `VdotReduce.scala` 判回/重编到其所需版本，或直接用其自己的 `emu.nocov` 快照（`~/core-p2/` 下的 K1 源码备份 `VdotReduce.k1.bak.scala` 仅供回滚，未回写）。
11. **机时（如实记）**：本项共 7 个作业，远端台账 `~/core/results/budget-log.tsv` 逐行合计 **2.315 node-h**（`127135437` 0.010 / `127135641` 0.604 / `127137599` 0.001 / `127137611` 0.002 / `127137643` 0.176 / `127137638` 0.498 / `127137640` 1.024），在预估的 3–4 h 验证预算内；其中两个失败作业（清单路径问题）合计 0.003 node-h。

---

## 4.13.6 评分对应

| 官方指标 | 本报告位置 | 本节提供的证据 |
|---|---|---|
| 创新性 → **设计优化独特性（5 分，优秀 4–5）**（`docx/02:95`） | 把内部评委「无实测 PPA」的扣分点补成**可复算的 PPA**：同一把尺子上的 481→500 cells、22→14 级、DFF 19→38，且改动只有一个文件、不碰共享模块 | §4.13.3 |
| 探索性 → **微架构优化分析（5 分）**（`docx/02:93`） | 时序轴：切点选在树的冗余表示上（carry-save retiming），并把「为什么不加流水级」写成可核对的结构事实（同一 `fireS1` 使能、同一拍边界） | §4.13.2 |
| 阶段三 → 报告完整性 | `L_vdot=4` 等口径与 K1 同值 ⇒ 性能结论不受本次改动影响，报告的既有数字无需改写 | §4.13.4 V7 |

> 不承诺档位：本节只提交实测 PPA 与结构说明，不给「几分」的预测；无 STA/功耗数据，按调研口径**不承诺 5 分**。

---

## 4.13.7 复现（逐条可复制）

```sh
# 0) 前提：昆山 ~/core 已落位（`<account>` 为集群账号占位）；改动文件在 repos/XiangShan/yunsuan（本地 = 远端同 sha256）
scp repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala \
    kunshan:~/core/src/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala
#    从公开仓复现：先按 stage2/2.2-rtl/CHANGES.md 应用 9 个基线 patch，再在 yunsuan 仓应用
#    patches/0005-X-new-P-2-VdotReduce-carry-save-retiming-yunsuan.patch（基于 83059b5；改的就是上面这个文件）

# 1) 强制 re-elaborate（见 §4.13.5 第 5 条）+ 构建
ssh kunshan 'rm -f ~/core/src/XiangShan/build/rtl/SimTop.sv'
ssh kunshan 'cd ~/core && sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 \
    core-package/scripts/10-build-emu.sh --src-root /public/home/<account>/core/src'
ssh kunshan 'grep -c "sumS2\|carryS2" ~/core/src/XiangShan/build/rtl/VdotReduce.sv'   # 期望 7

# 2) 30 例 --full（用冻结清单的绝对路径版；数据行与冻结件等价）
ssh kunshan 'cd ~/core && sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 \
    core-package/scripts/20-run-difftest.sh --full \
    --manifest /public/home/<account>/core/test/manifest.p2-30.abs.tsv \
    --emu /public/home/<account>/core-p2/emu-p2 --ref-so /public/home/<account>/core-p2/ref-p2.so'

# 3) 面积：K1 sanity（用 ~/core-p2/k1/ 下的 K1 闭包）与 P-2（用 build_area_rtl.sh 从当次 build/rtl 生成）
ssh kunshan 'cd ~/core && sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 \
    core-package/scripts/40-yosys-area.sh \
    --vdot-rtl /public/home/<account>/core-p2/k1/vdot_dp.sv --vdot-top VdotReduce \
    --vmac-rtl /public/home/<account>/core-p2/k1/vmac_only.sv --vmac-top VIMac64b'
ssh kunshan 'bash ~/core/design_verify/area/build_area_rtl.sh ~/core/src/XiangShan ~/core-p2/rtl/area'
ssh kunshan 'cd ~/core && sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 \
    core-package/scripts/40-yosys-area.sh \
    --vdot-rtl /public/home/<account>/core-p2/rtl/area/vdot_dp.sv --vdot-top VdotReduce \
    --vmac-rtl /public/home/<account>/core-p2/rtl/area/vmac_only.sv --vmac-top VIMac64b'

# 4) DFF 指纹 / ltp
python3 -c 'import json;d=json.load(open("vdot.stat.json"));m=list(d["modules"].values())[0];print(m["num_cells"],m["num_cells_by_type"]["$_DFFE_PP_"])'
head -3 vdot.ltp.txt
```

**回滚点**：`repos/XiangShan/yunsuan` @ `83059b5`；被改文件改前 blob `4fbaff570e80f45f2613d8e22ee9f64fff0a4122`；回滚命令 `git -C repos/XiangShan/yunsuan checkout -- src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala`。**四个验证面（重建 / 30 例 `--full` / 面积 before-after / extra 129）均达标，未触发回滚。**