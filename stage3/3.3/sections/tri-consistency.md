# 3.3 补充小节：三端一致性对照表（金模型 / NEMU / RTL）

> **位置**：本文件是 `stage3/3.3/report.md` §5.6（软硬协同机制）与 §4.11/§4.12（功能验证、用例扩容）的配套材料。它只回答一个问题：**同一条用例、同一条非法条件、同一个边界语义，三端是否给出同一结论**；不新增性能数字、不新增机时，也不重复覆盖率矩阵。
>
> **对应评分**：`docx/02-赛题与评分细则.md:92`「可行性 → 功能验证有效性」（指标含「测试用例是否覆盖正数、负数、边界值，协同仿真是否通过」）与 `:94`「探索性 → 软硬件协同理解」。
>
> **三端定义（本文只用这三个）**：
> | 端 | 实现 | 角色 |
> |---|---|---|
> | **金模型** | `design/verify/vdot_model.py`（共同语义源 `design/SPEC.md`） | 给出语义 / 生成扩容期望 / 给出非法原因 |
> | **NEMU** | `repos/NEMU/src/isa/riscv64/instr/rvv/vcompute.h:877-901` 的 `def_EHelper(vdot)` + `decode.h:371-373` | difftest 参照模型 |
> | **RTL** | `VecDecoder.scala` / `VecExceptionGen.scala` / `VdotReduce.scala` / `VIMacU.scala` | DUT（Verilator `build/emu`） |
>
> **标注约定**：【实读】= 本次逐行读到的代码/日志/JSON；【实测】= 本次实际运行命令得到的输出；【历史记录】= 仓库内已有记录、本次未复跑；【未运行】= 没有对应产物。**本文件不新增任何作业。**

---

## A. 三端是怎么闭合的（先看这条链，再看表）

```text
金模型 ──期望常量──▶ 用例内嵌自检 ──写回值──▶ RTL DUT
   │                                            ▲
   │ 三算法交叉（1142 例，本次实跑）              │ difftest: vrf/xrf/csr memcmp
   ▼                                            │
算法 B（gen.py）/ 金模型（gen_extra.py）      NEMU 参照
```

- **金模型/算法 B ↔ RTL**：由用例内嵌自检闭合。每条用例把期望常量烧进 `.bin`，执行后打印 `CASE <cid>: MATCH/MISMATCH`，并同时断言 `hi=[0,0,0]`（例：`stage3/3.1.2-difftest/full-logs-20261103T142246/vdot_pos1.20261103T142246.log:3-4`）。
- **NEMU ↔ RTL**：由 difftest 的 `vrf`/`xrf`/`csr` 逐提交步 `memcmp` 闭合（`repos/XiangShan/difftest/src/test/csrc/difftest/refproxy.cpp:186-224`、`difftest.cpp:695`）；不一致打印 `display + ABORT`，一致则继续到 `GOOD TRAP`。
- **金模型 ↔ NEMU**：**没有单独的直连比对器**。它由上面两条边**传递闭合**：金模型常量 ≡ RTL 写回值（用例自检），RTL 写回值 ≡ NEMU 写回值（difftest），故金模型/算法 B ≡ NEMU。本文把它写成“传递闭合”，不写成“直接比对”。

**两条不同的期望值生成路径（必须分开写）**：

| 用例集 | 期望值来源 | 复核方式 | 本次证据 |
|---|---|---|---|
| 主清单 30 例 | `design/verify/cases/gen.py:23-25` 的**算法 B**（逐项 `int64` 累加后截 32 位） | 用例内嵌断言 `result==expect && hi==0` | 30/30 通过；`CASE <cid>: MATCH` 逐例实读（§B） |
| 扩容 129 例 | `design/verify/cases/gen_extra.py` 调 `vdot_model.vdot_vv()` 生成常量 | `extra_crosscheck.py` 从 `.c` 源重放并**再算一遍**（`:284-291`） | 作业 `127031933`：`golden_crosscheck=达标`；`EXTRA_CROSSCHECK … problems=0`（仓库记录，见 `sections/case-expand.md` §4.12.3） |

> 主清单的 30 个常量**不是** `vdot_model.py` 生成的，而是 `gen.py` 的算法 B；金模型自测（`vdot_model_test.py`，本次实跑 1142 例）证明算法 A/B 与 19 位模型交叉一致。两者不要混写成“30 例期望全部由金模型生成”。

---

## B. 正向用例对照（数值定向 + 随机/不变量）

### B.1 数值定向（主清单 13 例，日志逐例实读）

> 共同口径：VL=8、`e8,m1`、`vd=3`（`vdot.vv v3,v1,v2`，机器码 `0x3A20A1D7`）；用例先 `vle8.v` 装 `v1/v2`，执行后切 `e32` 视图 `vse32.v` 存 4 个 32 位字，断言 `w0==expect` 且 `w1=w2=w3=0`。下表的 `result` / `hi` 都是用例日志 `CASE <cid>: result=… expect=… hi=[…]` 行原值。

| 用例 | 期望 `vd[31:0]` | 日志实测 `result` | `hi`（`vd[127:32]`） | 判定 |
|---|---|---|---|---|
| `vdot_pos1` | `0x00000024` | `0x00000024` | `[0,0,0]` | `MATCH` |
| `vdot_pos2` | `0xFFFFFFFC` | `0xFFFFFFFC` | `[0,0,0]` | `MATCH` |
| `vdot_pos3` | `0xFFFFFFFF` | `0xFFFFFFFF` | `[0,0,0]` | `MATCH` |
| `vdot_neg1` | `0xFFFFFFDC` | `0xFFFFFFDC` | `[0,0,0]` | `MATCH` |
| `vdot_neg_odd1` | `0x00000054` | `0x00000054` | `[0,0,0]` | `MATCH` |
| `vdot_neg_odd3` | `0x0000000C` | `0x0000000C` | `[0,0,0]` | `MATCH` |
| `vdot_neg_odd5` | `0xFFFFFFC4` | `0xFFFFFFC4` | `[0,0,0]` | `MATCH` |
| `vdot_neg_odd7` | `0xFFFFFF7C` | `0xFFFFFF7C` | `[0,0,0]` | `MATCH` |
| `vdot_bound1` | `0x00020000` | `0x00020000` | `[0,0,0]` | `MATCH` |
| `vdot_bound2` | `0xFFFE0400` | `0xFFFE0400` | `[0,0,0]` | `MATCH` |
| `vdot_bound3` | `0x00000000` | `0x00000000` | `[0,0,0]` | `MATCH` |
| `vdot_bound4` | `0x0001F808` | `0x0001F808` | `[0,0,0]` | `MATCH` |
| `vdot_bound5` | `0x00000001` | `0x00000001` | `[0,0,0]` | `MATCH` |

**三端在这 13 行上各自做了什么**：

1. **金模型/算法 B**：`gen.py` 用 `sum(x*y for x,y in zip(a,b)) & 0xFFFFFFFF` 算常量（`:23-25`）；金模型的 `dot_product()` + `writeback()` 是同一语义的另一种写法（`vdot_model.py:116-120,148-156`）。金模型自测用算法 A（任意精度）与算法 B（位级）两条独立路径交叉（`vdot_model_test.py:59-91`，本次 1142 例通过，§E）；`gen.py` 的常量与金模型没有逐例直接对拍（§F.3）。
2. **NEMU**：`def_EHelper(vdot)` 取 `vs1/vs2` 的低 8 个 lane（`get_vreg` 的 `vsew=0, is_signed=1`），`int64_t` 累加，`result=(uint32_t)(int32_t)sum`，再写 4 个 32 位字（`vcompute.h:885-897`）。
3. **RTL**：`VdotReduce` 把 8 个 16 位有符号积符号扩展到 19 位，4:2 CSA 树 + 19 位 CPA，`Cat(0.U(96.W), s19.asSInt.pad(32))` 写回（`VdotReduce.scala:47-57`）；`VIMacU.scala:165` 对 `outIsVdot` 断言高 96 位全零。
4. **一致性由谁判**：RTL 的 `result` 与期望常量（30 例为 `gen.py` 算法 B）比（用例自检，`MATCH`）；RTL 的 `vrf` 与 NEMU 的 `vrf` 逐提交步 `memcmp`（difftest，`cases_pass=30/30`）。两条边都过，才记这一行“一致”。

### B.2 随机 / 不变量 / 反例（主清单 4 例）

| 用例 | 覆盖内容 | 日志实测 | 三端含义 |
|---|---|---|---|
| `vdot_rand` | 固定种子 42 的 **1024 组**随机；lane 8–15 也填随机干扰 | `RAND_SUMMARY groups=1024 mism=0 ab_bad=0`（`vdot_rand.20261103T142246.log:3`） | 每组的 C 侧算法 B 与 RTL 写回一致（`mism=0`）；高 96 位全零（`ab_bad=0`）；RTL 与 NEMU 仍由 difftest 兜底 |
| `vdot_matrix` | ① `vl=0/1/4/7/8` 不变性 ② `vta/vma` 四组合 ③ `vxsat` 前后一致 ④ 旧 `vd` 预填 ⑤ `vd==vs1` 重叠 ⑥ 背靠背 4 条 | `MATRIX verdict=ALL_OK fails=0`（`vdot_matrix.20261103T142246.log:29`；逐项 `:21-28`） | 六条不变量在三端都没有被写成“依赖旧 vd / 依赖 vl / 依赖 vta-vma”的实现 |
| `vdot_mix` | `vdot → vmacc → vdot` 三种气泡数（0/1/2）；输出级选路与写回口竞争 | `MIX verdict=ALL_OK fails=0`（`vdot_mix.20261103T142246.log:10`） | vdot 与 vmacc 共用写回口时，RTL 选路正确；NEMU 逐指令语义正确；两侧 difftest 一致 |
| `vdot_g0_badexp` | **G0 反例**：期望值故意错 1 bit（`0x24 → 0x25`） | `CASE vdot_g0_badexp: result=0x00000024 expect=0x00000025(MUTATED)` → `MISMATCH` | 证明“只有用例内嵌自检能抓住值错误”；difftest 仍会 `GOOD TRAP`（DUT 与 NEMU 都没错），所以 `no_empty_green` 必须把 G0 计入（主 1/1、扩容 2/2） |

**`vdot_matrix` 的逐项日志（`vdot_matrix.20261103T142246.log:21-28`）**：

```text
MATRIX vta=0 vma=0 vtype=0x00 r=0xFFFFFC4C OK
MATRIX vta=0 vma=1 vtype=0x80 r=0xFFFFFC4C OK
MATRIX vta=1 vma=0 vtype=0x40 r=0xFFFFFC4C OK
MATRIX vta=1 vma=1 vtype=0xC0 r=0xFFFFFC4C OK
MATRIX vxsat before=0x0 after=0x0 OK
MATRIX oldvd_prefill r=0xFFFFFC4C OK
MATRIX overlap_vd_eq_vs1 r=0xFFFFFC4C OK
MATRIX back_to_back v4=0xFFFFFC4C v5=0xFFFFFC4C v6=0xFFFFFC4C v7=0xFFFFFC4C OK
```

> `vdot_matrix` 只覆盖 `vd==vs1` 这一种重叠；`vd==vs2` 在 `perf_vdot` 里以 `vdot.vv v10,v10,v1` 的形态出现（覆盖矩阵记 F14 `partial`，因为它走 `--no-diff` 自检）；`vs1==vs2` 在 30 例内是 **F15 gap**，由扩容的 `xo_v12_*` 10 例补齐（`manifest.extra.tsv` 的 `vdot-ov` 类）。这三条在 §D 表第 6 行列全。

---

## C. 负向用例对照（六条非法条件 + 组合 + 非法优先）

### C.1 三端判定锚点

> 关键区别：`vm=0` 在**编码层**就被过滤（RTL BitPat / NEMU 译码表 / 金模型 `decode_vdot_vv` 都要求 vm 位=1），其余五条在**状态层**判定。两张表不能混读。

| 非法条件 | RTL 判定 | NEMU 判定 | 金模型判定 |
|---|---|---|---|
| `vm=0`（编码层） | `VDOT_VV` BitPat 固定 bit25=1（`rocket-chip/.../Instructions.scala:459`）⇒ 掩码字不匹配 | `decode.h:371-373` 模式 `001110 1 …` ⇒ 不匹配，返回 `EXEC_ID_inv` | `decode_vdot_vv()` 校验 vm 位（`vdot_model.py:245-246`）⇒ `None`；运行时 `illegal_reasons(vm=0)` 也能给原因（`:141-142`） |
| `SEW≠8` | `VecExceptionGen.scala:277` `SEW =/= 0.U` | `vcompute.h:879` `vtype->vsew != 0` | `vdot_model.py:137-138` |
| `LMUL≠1` | 同 `:277` `LMUL =/= 4.U`（`vlmul=000` ↔ LMUL=1） | 同 `:879` `vtype->vlmul != 0` | `vdot_model.py:139-140` |
| `vstart≠0` | `VecExceptionGen.scala:280` `isVArith && io.vstart =/= 0.U` | `vcompute.h:883` + `vcommon.c:20-24`（`vstart->val > 0` → `EX_II`） | `vdot_model.py:143-144` |
| `vill=1` | `VecExceptionGen.scala:178` `io.vtype.illegal && isVArithMem` | `require_vector(true)`（`vcompute_impl.c:358-363`） | `vdot_model.py:135-136` |
| `mstatus.VS=OFF` | `DecodeUnit.scala:908` `vsIsOff && FuTypeOrR(fuType, vecAll)` | `require_vector_vs`（`vcompute_impl.c:266-269`） | `vdot_model.py:131-134` |
| 非法优先于 `vl=0` | 译码 `io.illegalInst` 在发射前（`VecExceptionGen.scala:299`） | EHelper 在循环/写回前判（`vcompute.h:878-883`） | `illegal_reasons` 在 `dot_product` 前（`vdot_model.py:180-184`） |

**一个容易误读的点**：`vm=0` 的用例（`vdot_ill_vm0` / `xn_vm0`）在 RTL 和 NEMU 里都**不是**走到 `s->vm == 0` 的运行时分支，而是**编码根本不匹配**；只有金模型同时保留了两条路径（`decode_vdot_vv` 返回 `None`，`illegal_reasons(vm=0)` 返回原因）。`extra_crosscheck.py:171-174` 对 `vm=0` 的负例正是按“机器码不得解成 vdot”检查的。

### C.2 用例覆盖与运行时判据

| 非法条件 | 主清单（8 个 negative） | 扩容（41 个 negative 中对应组） | 运行时判据（主/扩容同口径） |
|---|---|---|---|
| `SEW≠8` | `vdot_ill_sew` | `xn_sew_e16` / `xn_sew_e32` / `xn_sew_e64` | `HIT CRITICAL ERROR` ≥1 ∧ 无 `diff REF`/`Different operands` ∧ `ABORT=0` ∧ 无哨兵串（`20-run-difftest.sh:248-260`；`94-run-extra.sh:239-246`） |
| `LMUL≠1` | `vdot_ill_lmul2` / `lmul4` / `lmul8` | `xn_lmul_m2` / `m4` / `m8` / `mf8` / `mf4` / `mf2` | 同上 |
| `vm=0` | `vdot_ill_vm0` | `xn_vm0` / `xn_vm0_sew16` | 同上（实际走编码不匹配路径） |
| `vstart≠0` | `vdot_ill_vstart` | `xn_vstart1` / `2` / `3` / `4` / `7` / `15`；`xn_vstart1_e16` / `e32`；`xn_vstart8_e16` / `e32` | 同上 |
| `vill=1` | `vdot_ill_vill` | `xn_vill_38` / `20` / `3a` / `24` | 同上 |
| `mstatus.VS=OFF` | `vdot_ill_vs` | `xn_vs_off` | 同上 |
| 组合（SEW×LMUL、双谓词） | — | `xn_e16_m2/m4/m8`、`xn_e32_m2/m4/m8`、`xn_e64_m2/m4/m8`；`xn_lmulm8_vstart1`、`xn_vs_off_vstart1`、`xn_vill_vstart1` | 同上 |
| 非法优先于 `vl=0` | — | `xn_sew16_vl0`、`xn_vs_off_vl0`、`xn_vstart1_vl0` | 同上 |

**实际日志（本次实读）**：`vdot_ill_vstart` 与 `vdot_ill_sew` 的日志都在第 29848 行打印 `HIT CRITICAL ERROR: please check if software cause a double trap.`，第 29849 行打印 `HIT GOOD TRAP at pc = 0xe`（`full-logs-20261103T142246/vdot_ill_vstart.20261103T142246.log:29848-29849`；`…/vdot_ill_sew.…log:29848-29849`）。扩容整套的 `negatives_illegal=41/41` 记在 `results/difftest/extra/94-extra-20261106T143635.json` 的 `criteria[]`。

> **数量口径**：主清单 8 个 negative 是冻结件（`manifest.tsv` 30 数据行、`sha256 a90d1071…`）；扩容 41 个 negative 是作业 `127031933` 的 129 行清单快照。工作区 `manifest.extra.tsv` 后续有扩充，行数已大于 129；本文的 41 与 129 都以该作业 JSON 为准，不引用工作区当前行数。

---

## D. 边界与语义不变量对照

> 这张表回答“最坏值、全写、旧 vd、重叠、lane 选择、sticky 位”这些**容易三端各写一套**的点，是否真的同口径。表里的“证据”列只写已实读的日志/JSON/源文件行。

| 不变量 | SPEC | 金模型 | NEMU | RTL | 用例 | 证据（本次实读） |
|---|---|---|---|---|---|---|
| **高 96 位恒零** | `design/SPEC.md:31,48` | `writeback()` 只保留低 32 位（`vdot_model.py:148-156`） | 手写 `set_vreg(..., (w==0)?result:0, ...)` 四个字（`vcompute.h:893-897`） | `Cat(0.U(96.W), s19.asSInt.pad(32))`（`VdotReduce.scala:57`）+ 输出断言（`VIMacU.scala:165`） | 13 条数值正例 + `vdot_rand`/`vdot_matrix` | 13 条 `CASE … hi=[0x00000000 0x00000000 0x00000000]`（§B.1）；`RAND_SUMMARY … ab_bad=0` |
| **只取低 64 位 lane 0–7** | `design/SPEC.md:27` | `lanes_int8()` 只读 bits[63:0]（`vdot_model.py:107-113`） | 循环 `i<8`、`get_vreg(..., 0, ...)`（`vcompute.h:885-891`） | `VIMac64b` 的 `sum_wo` lane 0–7（`VIMacU.scala:125-130`） | `vdot_rand`（F27）、`xb_pos_lanehi`、`xo_*_lanehi` | `RAND_SUMMARY … mism=0 ab_bad=0`；`xb_pos_lanehi` 的 lane 8–15 填 `-128/127` 极值 |
| **`vl` 不影响结果 / `vl=0` 全写** | `design/SPEC.md:34` | `execute_vdot()` 显式忽略 `vl`（`vdot_model.py:186-187`） | 循环与写回都不读 `vl`（`vcompute.h:885-897`） | 数据通路无 `vl` 门控（`VdotReduce.scala:47-57`） | `vdot_matrix` ①（`vl=0/1/4/7/8`）；`xb_vl_sweep`（`vl=0..8`） | `MATRIX verdict=ALL_OK fails=0`；`xb_vl_sweep` 逐档读回 |
| **`vta/vma` 不影响结果** | `design/SPEC.md:36` | 显式忽略（`vdot_model.py:186-187`） | 写回 4 个字不读 `vta/vma` | 写回不接 `vta/vma` | `vdot_matrix` ②；`xb_vta_vma` | 四组 `MATRIX vta=… vma=… OK`（`vdot_matrix.…log:21-24`） |
| **旧 `vd` 不是语义输入** | `design/SPEC.md:32,38` | `writeback()` 接收但忽略 `old_vd`（`vdot_model.py:148-156`） | EHelper 不读旧 vd，直接覆盖 4 字 | `vdRen=F`（`VecDecoder.scala:385`）+ `isMacc` 不含 vdot（`VimacOpcode.scala:18`）+ `partProd(33)` 恒 0（`VIMac64b.scala:125`） | `vdot_matrix` ④；`xb_oldvd` | `MATRIX oldvd_prefill r=0xFFFFFC4C OK` |
| **`vd==vs1` / `vd==vs2` / `vs1==vs2`** | `design/SPEC.md:38` | `dot_product()` 先从两个操作数取值，再写回（Python 值语义） | EHelper 先读两个源，再写 `id_dest` | 源操作数在写回前读出；写回级才 `Mux(outIsVdot, …)` | 主：`vdot_matrix` ⑤（`vd==vs1`）、`perf_vdot`（`vd==vs2`，F14 partial）；扩容：`xo_vs1_*` / `xo_vs2_*` / `xo_v12_*` | `MATRIX overlap_vd_eq_vs1 r=0xFFFFFC4C OK`；F15 在 30 例内为 gap，`xo_v12_*` 10 例补齐 |
| **`vxsat` sticky 不变** | `design/SPEC.md:37` | `vxsat_next = vxsat_in`（`vdot_model.py:197`） | EHelper 不写 `vxsat` | `io.vxsat := Mux(isFixPS2, vxsat, 0.U)`（`VIMac64b.scala:306`） | `vdot_matrix` ③（仅 1 例，F25 thin） | `MATRIX vxsat before=0x0 after=0x0 OK` |
| **非法优先于 `vl=0` 全写** | `design/SPEC.md:17,33` | `illegal_reasons` 先于 `dot_product`（`vdot_model.py:180-184`） | 先判 `vm/sew/lmul` 与 `vstart`，再进循环（`vcompute.h:878-883`） | 译码 `io.illegalInst` 先于发射（`VecExceptionGen.scala:299`） | `xn_sew16_vl0`、`xn_vs_off_vl0`、`xn_vstart1_vl0` | 三例均 `HIT CRITICAL ERROR`（扩容 `negatives_illegal=41/41` 含这三例） |

**最坏值三端对照（同一组输入）**：

| 输入 | `S`（精确） | `vd[31:0]` | 用例 | 日志 |
|---|---|---|---|---|
| 8×`-128 × -128` | `+131072` | `0x00020000` | `vdot_bound1` | `result=0x00020000 expect=0x00020000` |
| 4×`-128×127` + 4×`127×-128` | `-130048` | `0xFFFE0400` | `vdot_bound2` | `result=0xFFFE0400 expect=0xFFFE0400` |
| 8×`127 × 127` | `+129032` | `0x0001F808` | `vdot_bound4` | `result=0x0001F808 expect=0x0001F808` |
| 一侧全零 | `0` | `0x00000000` | `vdot_bound3` | `result=0x00000000 expect=0x00000000` |

> `+131072` 是 19 位有符号的上边界（18 位上限 `131071` 装不下），`-130048` 是下边界；两值都由 `design/SPEC.md:39` 给出，并由 `vdot_model.py:190-195` 的 `ACC_MIN/ACC_MAX` 断言保护。

---

## E. 一致性是怎么被机械证明的（不是靠“看起来对”）

| 机制 | 做什么 | 本次实跑/实读/历史记录 | 防的是哪种假通过 |
|---|---|---|---|
| `vdot_model_test.py` | 三算法交叉（金模型 / 算法 A 任意精度 / 算法 B 位级）、19 位边界、六条非法顺序、三变异自检、四腐化反假通过 | **本次实跑**：`ALL TESTS PASSED (1142 cases)`，EXIT=0 | 金模型自己写错（`design/verify/vdot_model_test.py:511-565,581-604`） |
| `extra_crosscheck.py` | 从 `.c` 源重放每条 `vdot`，用 `vdot_model.vdot_vv()` 再算一遍常量；反解机器码 | 作业 `127031933` 的 `golden_crosscheck=达标`；仓库记录 `problems=0`（`sections/case-expand.md` §4.12.3；本次未重跑 crosscheck） | 扩容常量与金模型不一致、编码注释与机器码不一致 |
| `vdot_rand` 1024 组 | C 侧算法 B 独立复算 + 高 96 位检查 | `RAND_SUMMARY groups=1024 mism=0 ab_bad=0`（本次实读日志） | 只测几个手算值、随机覆盖不足 |
| difftest `vrf` 比对 | 每个提交步 `memcmp` 向量寄存器堆 | `vec_reg_compare=达标`；`cases_pass=30/30`、129/129 | 向量寄存器没比、只看 PC/标量 |
| G0 反例 | 期望值故意错 1 bit，必须 `MISMATCH` | 主 `G0 捕获 1/1`；扩容 `2/2`（`no_empty_green`） | 用例没有自检、`HIT GOOD TRAP` 被当成通过 |
| 负例临界事件 | 两侧都 critical error 才 `HIT CRITICAL ERROR` + `GOOD TRAP` | 主 8/8、扩容 41/41；日志 29848-29849 实读 | 只有 DUT 陷入、NEMU 没陷入（或反之） |

---

## F. 不覆盖 / 不得主张（先读这一节再引用）

1. **负例只判“是否陷入”，不判异常字段**：主清单与扩容的 negative 判据都是 `HIT CRITICAL ERROR` + 无失配 + 无哨兵（§C.2）。`cause` / `epc` / `mtval` **没有逐例断言**——本次实跑 `grep -rn "mcause\|mepc\|mtval" design/verify core-package | wc -l` → **0**。可主张“三端一致地判非法”，不可主张“三端异常字段逐字段相等”。
2. **没有 golden↔NEMU 直连**：如 §A 所述，是“金模型/算法 B ↔ RTL（用例自检）+ NEMU ↔ RTL（difftest）”传递闭合。不得写成“已直接比对”。
3. **主清单 30 例的期望不是金模型生成的**：是 `gen.py` 的算法 B；金模型自测只证明算法 A/B 与 19 位模型交叉一致（§A 表）。两者不要混写。
4. **`vs1==vs2` 在 30 例内是 gap**：覆盖矩阵 F15 `gap`（0 命中），由扩容 `xo_v12_*` 10 例补齐；引用“覆盖”时必须区分 30 例冻结件与 129 例扩容。
5. **4 个性能用例 `--no-diff`**：`perf_vdot`/`perf_base`/`perf_vadd`/`perf_vmacc` 只在自检口径下运行，不参与 difftest 逐位比对（`manifest.tsv:27-30`）。`vdot_matrix` 里的 `vd==vs2` 也不在 30 例中被 difftest 覆盖（F14 记 `partial`）。
6. **平台边界**：QEMU 级 difftest（NEMU `.so` vs Verilator `build/emu`），不是硅片实测；平台为 `kshcnormal`（`stage3/3.3/report.md` §2）。
7. **结构覆盖未运行**：RTL line/toggle 覆盖在 2026-11-07 实跑受阻（`--diff` 退出段 SIGSEGV、`.coverage.dat` 0 B），本文不引用任何结构覆盖数字；状态见 `sections/coverage.md` §D。
8. **扩容清单行数漂移**：工作区 `manifest.extra.tsv` 当前行数大于 129；本文的 129/41 都以作业 `127031933` 的 JSON 快照为准，不用工作区当前行数替换。
9. **单点依赖的回归风险**：`vdot_matrix` 是 F05/F08/F09/F10/F13/F24/F25 的仅有来源，`vdot_rand` 是 F03/F22/F27 的仅有来源（`stage3/3.1.2-difftest/coverage/matrix.md` §1）；漏跑任一例，对应 CP 会回落为 gap。这是覆盖风险，不是本文的一致性结论。

---

## G. 复现命令（零机时）

```bash
# 1) 金模型自测（本次实跑：ALL TESTS PASSED (1142 cases)，EXIT=0）
python3 -I design/verify/vdot_model_test.py

# 2) 逐例读正向日志的 result/expect/hi（本次实跑，13 例）
for f in vdot_pos1 vdot_pos2 vdot_pos3 vdot_neg1 vdot_neg_odd1 vdot_neg_odd3 \
         vdot_neg_odd5 vdot_neg_odd7 vdot_bound1 vdot_bound2 vdot_bound3 \
         vdot_bound4 vdot_bound5; do
  grep -h "CASE $f: result=" \
    stage3/3.1.2-difftest/full-logs-20261103T142246/$f.20261103T142246.log
done

# 3) 读负例的临界事件（本次实跑，29848-29849 行）
grep -n 'HIT CRITICAL ERROR\|HIT GOOD TRAP' \
  stage3/3.1.2-difftest/full-logs-20261103T142246/vdot_ill_vstart.20261103T142246.log

# 4) 读主清单/扩容的判据（本次实读）
python3 -I -c "import json;d=json.load(open('results/difftest/20-full-20261103T142246.json'));print([(c['name'],c['status'],c['actual']) for c in d['criteria']])"
python3 -I -c "import json;d=json.load(open('results/difftest/extra/94-extra-20261106T143635.json'));print([(c['name'],c['status'],c['actual']) for c in d['criteria']])"

# 5) 核对“异常字段未断言”（本次实跑，输出 0）
grep -rn "mcause\|mepc\|mtval" design/verify core-package | wc -l
```

---

**来源与状态**：本文件 2026-11-08 编写；代码锚点为本次逐行实读（`repos/XiangShan` 实施 HEAD `913ddd3`、`repos/XiangShan/yunsuan` `8942811`、`repos/NEMU` `a9dca53`）；运行数字全部来自仓库内已有日志与 JSON，**本轮未创建任何作业**。与 `report.md` §5.6 的分工：§5.6 讲机制链，本文件讲“三端在同一批用例上是否同结论”；与 `sections/coverage.md` 的分工：coverage 讲“覆盖了哪些点”，本文件讲“被覆盖的点三端是否一致”。