# 2.2 vdot.vv RTL 实现 — 变更清单（CHANGES）

> 来源：本目录 9 个 patch 的 `From`/`Subject`/`diff --git` 行与 `git apply --numstat` 输出（2026-11-03 本机实测）。
> 每行 commit 已在本机子仓用 `git cat-file -e <sha>^{commit}` 逐个确认存在（9/9 OK）。
> 9 个 patch 已全部落到工作树：`git -C <repo> apply -R --check <patch>` 全部通过（9/9 R-OK）。

## 改动点 → commit 对照

| # | patch 文件 | 改动点 | 子仓 | commit | 改动文件（numstat） |
|---|---|---|---|---|---|
| 1 | `0001-X1-add-VDOT_VV-custom-encoding-funct6-001-rocketchip.patch` | X1 编码 | `repos/XiangShan/rocket-chip` | `c4d7616` | `src/main/scala/rocket/Instructions.scala` (+2/−0)：`VDOT_VV = BitPat("b0011101??????????010?????1010111")`，vm 位钉 1 |
| 2 | `0001-X6-X7-VimacOpcode.vdot-3-b111-and-VimacType.-yunsuan.patch` | X6/X7 opcode/type | `repos/XiangShan/yunsuan` | `3c9a91a` | `encoding/Opcode/VimacOpcode.scala` (+1/−0) `vdot = "b111"`；`package.scala` (+1/−0) `VimacType.vdot`（9 位 `0x067`，vd_old 位 `INT.X`） |
| 3 | `0002-X15-export-sum_wo-walOut-fireS1-from-VIMac64-yunsuan.patch` | X15 端口导出 | `repos/XiangShan/yunsuan` | `a3d68d0` | `vector/vectorIMAC/VIMac64b.scala` (+11/−0)：一次导出 `sum_wo` / `walOut` / `fireS1`，不改数据通路 |
| 4 | `0003-X-new-VdotReduce-K-8-int8-dot-product-reduct-yunsuan.patch` | X-new 归约单元 | `repos/XiangShan/yunsuan` | `83059b5` | **新增** `vector/vectorIMAC/VdotReduce.scala` (+45/−0)：`sext19` → `CSA_Nto2With3to2MainPipeline(8,19,pipeLevel=0)` 4:2 树 → 19 位 CPA → `Cat(96'b0, sext32(S))`，`RegEnable(·, io.fireS1)` |
| 5 | `0001-X1-X2-decode-VDOT_VV-as-OPMVV-F-vimac-Vima-xiangshan.patch` | X1/X2 译码 | `repos/XiangShan` | `8f1aeb3` | `backend/decode/VecDecoder.scala` (+1/−0)：OPMVV 表项 `OPMVV(F, vimac, VimacType.vdot, F, T, F, VEC_VVV)`（`vdRen=F`）；`rocket-chip` 子模块指针 `46f1efe` → `c4d7616` |
| 6 | `0002-X14-vdot-legality-predicate-in-VecExceptio-xiangshan.patch` | X14 非法谓词 | `repos/XiangShan` | `19e2526` | `backend/decode/VecExceptionGen.scala` (+7/−1)：`isVdot && (SEW =/= 0.U \|\| LMUL =/= 4.U)` → illegal |
| 7 | `0003-X8-wrapper-bypasses-Mgu-for-vdot-and-asser-xiangshan.patch` | X8 wrapper | `repos/XiangShan` | `6015224` | `backend/fu/wrapper/VIMacU.scala` (+19/−2)：实例化 `VdotReduce`，`res.data = Mux(outIsVdot, vdotReduce.io.vd, mgu.io.out.vd)`，`outIsVdot` 取 `outCtrl.fuOpType`；断言 M06（`vd[127:32]==0`）/ M07（valid 不被 hold）；`yunsuan` 子模块指针 `9559211` → `83059b5` |
| 8 | `0004-tests-VdotReduce-Chisel-B-19-200-xiangshan.patch` | Chisel 单测 | `repos/XiangShan` | `913ddd3` | **新增** `src/test/scala/yunsuan/vectortest/mac/VdotReduceSpec.scala` (+129/−0)：19 位边界、−130048、奇数负 lane、200 组随机（seed 42）、fireS1 保持 |
| 9 | `0001-N1-N2-N3-vdot.vv-reference-model-decode-entry-E-nemu.patch` | N1/N2/N3 参考模型 | `repos/NEMU` | `a9dca53` | `isa-all-instr.h` (+1/−1) `f(vdot)`；`rvv/decode.h` (+3/−0) `def_INSTR_TAB("001110 1 …", vdot)`；`rvv/vcompute.h` (+31/−0) `def_EHelper(vdot)`（`check_vstart_exception` + 手写 96 位清零） |

## 应用顺序（按子模块指针依赖）

patch 之间靠子模块指针串联：X1/X2 把 `rocket-chip` 从 `46f1efe` 抬到 `c4d7616`，X8 把 `yunsuan` 从 `9559211` 抬到 `83059b5`。因此按下面顺序应用，才能逐条 `git apply` 不冲突：

```sh
# 1) 叶子仓先行
git -C repos/XiangShan/rocket-chip apply -p1 stage2/2.2-rtl/0001-X1-add-VDOT_VV-custom-encoding-funct6-001-rocketchip.patch
git -C repos/XiangShan/yunsuan   apply -p1 stage2/2.2-rtl/0001-X6-X7-VimacOpcode.vdot-3-b111-and-VimacType.-yunsuan.patch
git -C repos/XiangShan/yunsuan   apply -p1 stage2/2.2-rtl/0002-X15-export-sum_wo-walOut-fireS1-from-VIMac64-yunsuan.patch
git -C repos/XiangShan/yunsuan   apply -p1 stage2/2.2-rtl/0003-X-new-VdotReduce-K-8-int8-dot-product-reduct-yunsuan.patch
# 2) 主仓（含两处子模块指针）
git -C repos/XiangShan apply -p1 stage2/2.2-rtl/0001-X1-X2-decode-VDOT_VV-as-OPMVV-F-vimac-Vima-xiangshan.patch
git -C repos/XiangShan apply -p1 stage2/2.2-rtl/0002-X14-vdot-legality-predicate-in-VecExceptio-xiangshan.patch
git -C repos/XiangShan apply -p1 stage2/2.2-rtl/0003-X8-wrapper-bypasses-Mgu-for-vdot-and-asser-xiangshan.patch
git -C repos/XiangShan apply -p1 stage2/2.2-rtl/0004-tests-VdotReduce-Chisel-B-19-200-xiangshan.patch
# 3) NEMU（独立）
git -C repos/NEMU apply -p1 stage2/2.2-rtl/0001-N1-N2-N3-vdot.vv-reference-model-decode-entry-E-nemu.patch
```

## 基线 / 实施 HEAD

| 仓 | 基线 pin | 实施 HEAD |
|---|---|---|
| `repos/XiangShan` | `kunminghu-v2` @ `a4eeaab` | `913ddd3` |
| `repos/XiangShan/yunsuan` | `9559211` | `83059b5` |
| `repos/XiangShan/rocket-chip` | `46f1efe` | `c4d7616` |
| `repos/NEMU` | `a683e0b` | `a9dca53` |

## 未运行 / 未验证（不得记为通过）

- **lint**：未运行。
- **可综合性**：只有 Yosys 面积侧证 + 形式 miter 正反例（`results/yosys/`、`results/formal/`），**STA 未跑**。
- **vmac 专项回归**：X15 端口改动未单列回归项。
- **本机复跑**：以上 `apply -R --check` 只证明 patch 与当前工作树一致，**不代表本机重新编译过**；编译结论来自 patch 内提交信息（昆山 `mill -i xiangshan.compile rc=0`、`VdotReduceSpec` 3/3）。
