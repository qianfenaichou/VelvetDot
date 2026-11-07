# 2.2 vdot.vv RTL 实现

**结论：9 个 patch 覆盖 8 处 RTL 改动（X1/X2/X6/X7/X8/X14/X15/X-new）+ 1 个 Chisel 单测，全部已落到 `repos/` 工作树（`git apply -R --check` 9/9 通过）；**lint 已在昆山跑过**（作业 `126761068` 用 `-Wno-fatal`、作业 `126798101` 去掉 `-Wno-fatal`，两 top 均 `rc=0`/`%Error=0`；作业 `126803426` 加 `-Wall` 后有 13 条 `UNUSEDSIGNAL` 告警、`rc=1`，详见 §4）；本目录仍未重新编译，编译与测试结论只来自 patch 内提交信息。**

对应官方条目：`docx/02-赛题与评分细则.md:54`「2.2 vdot.vv RTL 实现：Verilog/Chisel 代码，实现 vdot.vv 指令功能单元扩展」。

## 1. 目录结构

| 路径 | 内容 |
|---|---|
| `0001-X1-add-VDOT_VV-…-rocketchip.patch` | X1：`Instructions.scala` 加 `VDOT_VV` BitPat（`+2/−0`） |
| `0001-X6-X7-VimacOpcode.vdot-…-yunsuan.patch` | X6/X7：`VimacOpcode.vdot=3'b111`、`VimacType.vdot`（9 位 `0x067`）（`+2/−0`） |
| `0002-X15-export-sum_wo-walOut-fireS1-…-yunsuan.patch` | X15：`VIMac64b` 一次导出 `sum_wo`/`walOut`/`fireS1`（`+11/−0`） |
| `0003-X-new-VdotReduce-…-yunsuan.patch` | X-new：新增 `VdotReduce.scala`（4:2 树 + 19 位 CPA）（`+45/−0`） |
| `0001-X1-X2-decode-VDOT_VV-as-OPMVV-…-xiangshan.patch` | X1/X2：`VecDecoder` OPMVV 表项（`vdRen=F`）+ `rocket-chip` 子模块指针（`+2/−1`） |
| `0002-X14-vdot-legality-predicate-…-xiangshan.patch` | X14：`VecExceptionGen` 非法谓词（`+7/−1`） |
| `0003-X8-wrapper-bypasses-Mgu-…-xiangshan.patch` | X8：`VIMacU` 旁路 Mgu + 断言 M06/M07 + `yunsuan` 指针（`+20/−3`） |
| `0004-tests-VdotReduce-Chisel-…-xiangshan.patch` | Chisel 单测 `VdotReduceSpec.scala`（`+129/−0`） |
| `0001-N1-N2-N3-vdot.vv-reference-model-…-nemu.patch` | N1/N2/N3：NEMU 参考模型（`+35/−1`） |
| `CHANGES.md` | 改动点 → commit → 改动文件对照表、应用顺序、基线/HEAD、未运行项 |

9 个 patch 与根 `patches/` 同名文件 **sha256 逐字节相同**（本机 `sha256sum` 9/9 OK）。

## 2. 改动点与 commit（详见 `CHANGES.md`）

| 改动点 | 子仓 | commit | 一句话 |
|---|---|---|---|
| X1 | `rocket-chip` | `c4d7616` | `VDOT_VV` BitPat，vm 位钉 1（掩码形式不解码） |
| X6/X7 | `yunsuan` | `3c9a91a` | `vdot=3'b111`（不进 `isMacc`/`isFixP`）、`VimacType.vdot=9'h067` |
| X15 | `yunsuan` | `a3d68d0` | 三信号一次导出，纯输出端口，不改数据通路 |
| X-new | `yunsuan` | `83059b5` | `sext19` → `CSA_Nto2With3to2MainPipeline(8,19,pipeLevel=0)` → 19 位 CPA → `Cat(96'b0, sext32(S))`，`RegEnable(·, io.fireS1)` |
| X1/X2 | `XiangShan` | `8f1aeb3` | OPMVV 表项 + rocket-chip 指针 `46f1efe→c4d7616` |
| X14 | `XiangShan` | `19e2526` | `isVdot && (SEW=/=0.U \|\| LMUL=/=4.U)` → illegal |
| X8 | `XiangShan` | `6015224` | `Mux(outIsVdot, vdotVd, mgu.out)`；`outIsVdot` 取 `outCtrl.fuOpType`；断言 M06/M07；yunsuan 指针 `9559211→83059b5` |
| tests | `XiangShan` | `913ddd3` | 19 位边界、−130048、奇数负 lane、200 组随机（seed 42）、fireS1 保持 |
| N1/N2/N3 | `NEMU` | `a9dca53` | `f(vdot)` 枚举 + `def_INSTR_TAB("001110 1 …")` + `def_EHelper(vdot)`（`check_vstart_exception`，手写 96 位清零） |

## 3. 已执行的校验（命令 + 结果）

```
# 1) commit 存在性：9 个 sha 逐个 git cat-file -e <sha>^{commit}
a9dca53 NEMU=OK / c4d7616 rocket-chip=OK / 8f1aeb3 xiangshan=OK / 3c9a91a yunsuan=OK
19e2526 xiangshan=OK / a3d68d0 yunsuan=OK / 6015224 xiangshan=OK / 83059b5 yunsuan=OK
913ddd3 xiangshan=OK                                     → 9/9 OK

# 2) patch 与工作树一致（反向应用检查，按 CHANGES.md 的仓归属逐个跑）
git -C <repo> apply -p1 -R --check <stage2/2.2-rtl/xxx.patch>   → 9/9 OK(-R)

# 3) 字节一致
sha256sum patches/<p> stage2/2.2-rtl/<p>                 → 9/9 相同

# 4) 金模型自检（打包后）
python3 design/verify/vdot_model_test.py                → 「ALL TESTS PASSED (1142 cases)」EXIT=0
```

打包时另执行文档体系检查，输出「文档体系检查全部 OK」、EXIT=0（检查脚本随内部工程仓维护，不在本交付包内）。

## 4. 未运行 / 未验证（不得记为通过）

- **编译**：本目录**未在本机重新编译**。`xiangshan.compile rc=0`、`VdotReduceSpec 3/3` 均来自 patch 内提交信息（昆山登录节点，Verilator 5.053）。
- **lint**：**已跑（2026-11-04），三档结论分列**：
  1. `verilator --lint-only -Wno-fatal`（作业 `126761068`）：`VdotReduce`(+两级 CSA) 与 `VIMac64b` 均 `rc=0`、`%Error=0`。**该次 `-Wno-fatal` 把 warning 降级 ⇒ `%Warning=0` 不构成「无告警」证据**（`results/lint/25-rtl-lint-20261104T113051.json`）。
  2. 去掉 `-Wno-fatal`（作业 `126798101`，脚本 `results/lint/strict-lint2.sh`）：两 top 均 `rc=0`、`%Error=0`、`%Warning=0`。**注意该档未加 `-Wall`** ⇒ 只等于「不把 warning 当 fatal」，告警集合仍是 Verilator 默认集。
  3. 加 `-Wall`（作业 `126803426`，脚本 `results/lint/wall-lint.sh`）：`VdotReduce` `rc=1`/`%Warning=1`（`_RANDOM` 未驱动未使用，`VdotReduce.sv:113`）、`VIMac64b` `rc=1`/`%Warning=12`（11 条 `UNUSEDSIGNAL` 为 Chisel 生成的未用位/未用 `_bits_T_*`，1 条 `_RANDOM`）。**全部 13 条是 `UNUSEDSIGNAL` 类（未用信号/未用位），`%Error` 每 top 各 1 行（`Exiting due to 1/12 warning(s)`，合计 2 行，均为汇总行、非缺陷类 error）；无 `LATCH`/`WIDTH`/`CASEINCOMPLETE` 等实质缺陷类告警**；该 13 条为 Chisel 生成物既有形态（`VdotReduce.sv` 的 `_RANDOM` 与 `VIMac64b` 的 `io_srcType_*` 高位均属基线已有）。
  - **未由本地复跑**：本机无 verilator、无 `build/rtl`；三档结论均来自远端作业日志（已回仓 `results/lint/`，provenance 见 `results/lint/provenance-strict-lint.txt`）。
  - **2.2 判据（`lint 通过`）的口径**：按入库脚本的 `rc=0 ∧ %Error=0` 判据成立；若评委把「`-Wall` 下 0 告警」当判据，则**未达标**（13 条 `UNUSEDSIGNAL`）。本目录不把第 3 档写成「通过」。
- **波形（`wave/`）**：`vdot.vv` 自身波形已产出（2026-11-05，作业 `126875390`，`kshcnormal` 队列，节点名略，`verdict=OK`、`stage_rc` A–F 全 0）：`vdot_wave_20261105T091811.key.vcd`（窄窗关键信号摘录，14 KB）+ `.vcd.gz`（完整窄窗 VCD，17 MB）+ `vdot_wave_20261105T091811.health.json`（体检 8/8 PASS）+ `vcd-head/scopes/summary` + `SHA256SUMS-20261105T091811.txt`。**口径限制（必读）**：① `key.vcd` 的 `clock` 是**采样域时钟**（Verilator 每拍 dump 一次 ⇒ 全 VCD 只变化 1 次、摘录里恒高），GTKWave 打开不会翻转，属采样语义而非缺驱动；② `exu_in_fuOpType` 与 `vimac_fuOpType` 共用同一 VCD 标识符（同一网线），值必然相同、**不是两个独立观测点**；③ **摘录自校验缺口已修并留两份**：作业原件 `vdot_wave_20261105T091811.key.vcd` 的 `excerpt_verify=checked=9648`（=48×201），根因是探针用 `code2label` 一对一映射，`exu_in_fuOpType` 与 `vimac_fuOpType` 共用 VCD 标识符 `z+9` ⇒ 前者整条无值、被 `exp is None and got is None` 静默跳过（该信号在摘录里 0 次驱动，实测）；**探针已修**（`code→标签列表` + 「有值信号必须全覆盖」判据 + `aliased_label_groups`/`clock_note` 字段），对同一源 VCD（sha256 `ef0a6fdb…`）复跑得到 `…probefix-20261106.key.vcd` 与 `…probefix-20261106.health.json`：`checked=9849/9849 mismatches=0 unseeded=0`、`verdict=OK`；**原件保留不改**（它是那次作业的真实产物），修正件单列并注明「同一源 VCD 的探针修复后重算」；④ 本波形用例 `vdot_wave` **不在** 30 例 `manifest.tsv` 内（独立测量口径），因此它**不能**替代 2.3.x 各用例的波形位；⑤ `.gitignore` 已为交付件开例外（2026-11-06）：`!stage2/2.2-rtl/wave/*.key.vcd` ⇒ `.key.vcd` 与 `.vcd.gz` 均可直接 `git add`（实测 `git check-ignore` rc=1、`git add -An` 命中 1 件）；裸完整 `.vcd` 仍被 `*.vcd` 排除（只保留 `.gz` 归档）。
- **可综合性**：仅 Yosys 面积侧证 + 形式 miter 正反例（`results/yosys/`、`results/formal/`，非本目录）；**STA 未跑**。
- **vmac 专项回归**：X15 端口改动未单列回归项。
- **逐文件完整源码**：本目录只放 patch，**不含** `repos/` 下的完整 `.scala` 文件；评委需按 `CHANGES.md` 的应用顺序把 patch 打到基线 pin（`a4eeaab`/`9559211`/`a683e0b`）上复现。
