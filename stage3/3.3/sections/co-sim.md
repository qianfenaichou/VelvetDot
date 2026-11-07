# 3.3 补充小节：软硬件协同验证机制图与 DIFFTEST 参数表

> **位置**：本文件是 `stage3/3.3/report.md` §5.6「软硬协同机制（NEMU 金模型 ↔ RTL difftest）」的配套材料。§5.6 已给出四条机制链的正文；本文件补两件它没有展开的东西：**一张把链条画全的机制图**、**一张可逐项核对的 DIFFTEST 参数/判据表**。报告侧只读引用，不改本文。
>
> **对应评分**：`docx/02-赛题与评分细则.md:94`「探索性（10 分）→ 软硬件协同理解」——指标描述「是否理解 NEMU 与 RTL 的协同仿真机制」，二级权重 5%、5 分。
>
> **标注约定**：【实读】= 本次逐行读到的代码、脚本或 JSON 字段；【实测】= 本次实际运行命令得到的输出；【历史记录】= 仓库内已有记录、本次未复跑；【未运行】= 没有对应产物。**本文件不新增任何机时、不新增作业**，所有运行数字都来自仓库内已有的结果 JSON。

---

## A. 机制图：一条 vdot 从语义到判据经过哪几层

```text
[语义源] design/SPEC.md §1.1/§1.3
  六条合法条件（SEW=8 ∧ LMUL=1 ∧ vm=1 ∧ vstart=0 ∧ vill=0 ∧ VS≠OFF）
  19 位有符号归约；vd[31:0]=sext32(S)，vd[127:32]=0
        │
        ├────────────────┬────────────────────┬──────────────────────┐
        ▼                ▼                    ▼                      ▼
  [金模型]          [NEMU 参照模型]       [RTL DUT]               [用例镜像]
  vdot_model.py     decode.h:371-373      VecDecoder.scala:385    gen.py / gen_extra.py
  illegal_reasons   vcompute.h:877-901    VecExceptionGen:178,    CASE <cid>: MATCH
  writeback         require_vector_vs     276-277,280             RAND_SUMMARY
                    check_vstart_exc     VdotReduce.scala:53-57  MIX verdict
        │                │                    │                      │
        │ 生成期望常量    │ 逐指令执行          │ 周期级执行            │ 内嵌自检
        └────────────────┴──────────┬─────────┴──────────────────────┘
                                    ▼
                 emu --diff <ref.so> -i <bin> --max-instr=N
                 difftest_nstep(step) → difftest_step()
                 RefProxy::compare: xrf + vrf + csr（memcmp）
                                    │
                     ┌──────────────┴──────────────┐
                     ▼                             ▼
           GOOD TRAP + 自检 MATCH            display + ABORT
```

**图里的五层（逐层一句话）**：

1. **语义源**：`design/SPEC.md` 是三条实现（金模型 / NEMU / RTL）的共同上游；六条合法条件与写回格式都只在这里定义一次（`design/SPEC.md:31-39`）。
2. **金模型**：`design/verify/vdot_model.py` 把 SPEC 写成可执行的 `illegal_reasons()` / `writeback()` / `execute_vdot()`（`:123-197`），并带**变异自检**（`design/verify/vdot_model_test.py:511-565`：写回泄漏旧 vd 高位、高 96 位写 1、删掉 `vill` 判定，三个变异体必须全部被判红）。
3. **NEMU 参照模型**：`decode.h:371-373` 把 `001110 1 ????? ????? ??? ????? ????? ??` 直接绑到 `vdot`（**vm 位固定为 1**）；`vcompute.h:877-901` 的 `def_EHelper(vdot)` 先 `require_vector(true)`（VS/vill），再独立判 `vm/sew/lmul`，再用 `check_vstart_exception(s)`，最后手写 8 lane 累加与高 96 位显式清零。
4. **RTL DUT**：`VecDecoder.scala:385` 的 `OPMVV(F, ..., vdRen=F, ...)` 决定“不读旧 vd”；`VecExceptionGen.scala:178/276-277/280` 与 `DecodeUnit.scala:908` 给出非法判定；`VdotReduce.scala:53-57` 用 19 位 CPA 收口并 `Cat(0.U(96.W), sext32)` 写回。
5. **difftest 比对环**：`emu.cpp:517-540` 每个仿真步取 `get_difftest_step()` 后调 `difftest_nstep(step, enable_diff)`；`difftest.cpp:114-138` 在内层循环逐步调 `difftest_step()`；`refproxy.cpp:186-224` 用 `memcmp` 比 `xrf` / `vrf` / `csr`；`difftest.cpp:695` 的 `proxy->compare(dut) || pc_mismatch` 是最终判据。

**三端不是两两直连**（这一点必须写清楚，防止把机制读成“有 golden↔NEMU 直连器”）：

```text
金模型 ──期望常量──▶ 用例内嵌自检 ──写回值──▶ RTL DUT
   │                                            ▲
   │ 三算法交叉（1142 例，本次实跑）              │ difftest vrf memcmp
   ▼                                            │
算法 B（gen.py）/ 金模型（gen_extra.py）      NEMU 参照
```

- **金模型/算法 B ↔ RTL**：由用例内嵌自检闭合——每条用例把期望常量烧进 `.bin`（30 例由 `gen.py` 的算法 B 生成，129 例由 `vdot_model.py` 生成；两者同语义，见 §F.3），执行后打印 `CASE <cid>: MATCH/MISMATCH`，同时断言 `hi=[0,0,0]`（例：`stage3/3.1.2-difftest/full-logs-20261103T142246/vdot_pos1.20261103T142246.log:3-4`）。
- **NEMU ↔ RTL**：由 difftest 的 `vrf`/`xrf`/`csr` 逐提交步 `memcmp` 闭合（`refproxy.cpp:186-224`、`difftest.cpp:695`）；不一致打印 `display + ABORT`，一致则继续到 `GOOD TRAP`。
- **金模型 ↔ NEMU**：**没有单独的直连比对器**。它由上面两条边传递闭合：金模型常量 ≡ RTL 写回值（用例自检），RTL 写回值 ≡ NEMU 写回值（difftest），故金模型/算法 B ≡ NEMU。这是“传递闭合”，不是“直接比对”，本节不把它写成直连。

---

## B. 逐环锚点表（图里每个框的 `file:line`）

| 环 | 做什么 | 代码锚点 | 本次读到的事实 |
|---|---|---|---|
| 金模型·合法性 | 六条条件按固定顺序给原因 | `design/verify/vdot_model.py:123-145`（顺序 `vs_off → vill → sew → lmul → vm → vstart`） | 顺序由 `vdot_model_test.py:499-509` 断言 |
| 金模型·写回 | `vd[31:0]=S`，高 96 位清零，旧 vd 忽略 | `design/verify/vdot_model.py:148-156` | `WRITE_MASK=0x00000000FFFFFFFF`（`:58`） |
| 金模型·执行 | 先判非法，再算 `dot_product`，19 位范围断言 | `design/verify/vdot_model.py:159-197` | `vl/vta/vma/old_vd` 显式忽略（`:186-187`） |
| 金模型·编码 | 编码/反解 `vdot.vv` | `design/verify/vdot_model.py:216-250` | `0x3A20A1D7` 可由 `encode_vdot_vv(3,2,1)` 复算 |
| NEMU·译码 | `funct6=001110` + `vm=1` 固定 | `repos/NEMU/src/isa/riscv64/instr/rvv/decode.h:371-373` | 掩码编码匹配不到 ⇒ 非法 |
| NEMU·执行 | 8×int8 累加 + 显式清零高 96 位 | `repos/NEMU/src/isa/riscv64/instr/rvv/vcompute.h:877-901` | 循环 `i<8`、`set_vreg` 四个 32 位字（`:885-897`） |
| NEMU·VS/vill | `require_vector(true)` | `repos/NEMU/src/isa/riscv64/instr/rvv/vcompute_impl.c:358-363`；`require_vector_vs` `:266-269` | `mstatus->vs==0` 或 `vill!=0` → `EX_II` |
| NEMU·vstart | `check_vstart_exception` | `repos/NEMU/src/isa/riscv64/instr/rvv/vcommon.c:20-24` | `vstart->val > 0` → `EX_II` |
| NEMU·参照状态 | `DIFFTEST_REG_SIZE` 由 `offsetof` 算出 | `repos/NEMU/src/isa/riscv64/difftest/ref.c:28-29` | 大小不匹配时 `:471-473` 打 different-states 串 |
| RTL·译码 | `VDOT_VV` BitPat 固定 bit25=1 | `repos/XiangShan/rocket-chip/src/main/scala/rocket/Instructions.scala:459` | `b0011101??????????010?????1010111` |
| RTL·译码 | `OPMVV(..., vdRen=F, ...)`；`src3=X` | `repos/XiangShan/src/main/scala/xiangshan/backend/decode/VecDecoder.scala:385`、`:91` | 不读旧 vd |
| RTL·非法 | SEW/LMUL、vill、vstart、VS=OFF | `VecExceptionGen.scala:178,276-277,280`；`DecodeUnit.scala:908` | `io.illegalInst` 汇总（`:299`） |
| RTL·执行 | 19 位 CSA 树 + CPA + 高 96 位清零 | `repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala:53-57` | `Cat(0.U(96.W), s19.asSInt.pad(32))` |
| RTL·接线 | `fireS1` 只从 `VIMac64b` 端口取；输出级选路 | `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:130,158-160` | 高 96 位恒零断言 `:165` |
| difftest·步进 | 每仿真步取 DUT 的 `difftest_step`，内层逐步比 | `repos/XiangShan/difftest/src/test/csrc/emu/emu.cpp:522,540`；`difftest.cpp:114-138` | `difftest_nstep(step, enable_diff)` |
| difftest·比对 | `xrf` + `vrf`（宏）+ `csr` 逐字段 `memcmp` | `repos/XiangShan/difftest/src/test/csrc/difftest/refproxy.cpp:186-224` | `vrf` 在 `CONFIG_DIFFTEST_ARCHVECREGSTATE` 下（`:192-194`） |
| difftest·判定 | compare 失败或 PC 不一致即失配 | `difftest.cpp:695`；失配显示 `refproxy.cpp`；负例临界事件 `traps.cpp:139-151` | 两侧都 critical error 才打印 `HIT CRITICAL ERROR` 并 `GOOD TRAP` |

---

## C. DIFFTEST 参数表

> 口径：下表只列**构建与运行脚本里真实存在的参数**。取值一列写“脚本默认值”或“本次运行 JSON 实读值”，两者不混。**“本次状态”一列的三份 JSON 分别是：主清单 `results/difftest/20-full-20261103T142246.json`（作业 `126676734`）、P-2 主清单 `results/difftest/20-full-20261107T104227.json`（作业 `127137638`）、扩容 `results/difftest/extra/94-extra-20261106T143635.json`（作业 `127031933`）。**

| # | 参数 | 取值 / 口径 | 锚点 | 本次状态 |
|---|---|---|---|---|
| 1 | DUT 可执行文件 | `$NOOP_HOME/build/emu`（Verilator 5.053，`EMU_THREADS=8`） | `core-package/scripts/20-run-difftest.sh:365`；构建日志 `results/emu/10-build-20261103T032307.log:4` | 三份 JSON 均按 `build/emu` + NEMU `.so` 口径运行；未逐份记录二进制 sha256【历史记录】 |
| 2 | 参照模型 `.so` | `$NEMU_HOME/build/riscv64-nemu-interpreter-so` | `20-run-difftest.sh:366`；`10-build-emu.sh:227` | `nm_exec_vdot=达标（命中 2 行）` ×3 |
| 3 | NEMU 分层配置 | `riscv64-xs-kmhv2-ref_defconfig` | `10-build-emu.sh:229-230`；`design/ALGORITHM.md:173` | 构建日志 `:7`【历史记录】 |
| 4 | emu 调用 | `--diff <ref.so> -i <bin> --max-instr=N` | `20-run-difftest.sh:234` | 主 30/30、扩容 129/129 执行 |
| 5 | 参照状态大小 | `DIFFTEST_REG_SIZE`；判据文本按 **1400 B** 口径，实际检查日志不出现 different-states 串 | `repos/NEMU/src/isa/riscv64/difftest/ref.c:28-29`；`20-run-difftest.sh:463`；`design/ALGORITHM.md:174` | `reg_size_match=达标（0 次）` ×3 |
| 6 | 参照状态初始化 | `ref_init_v2(sizeof(ref_state_t))` | `refproxy.cpp:88-89` | 同上（大小不匹配会在此 assert） |
| 7 | 比对步长 | DUT 输出 `difftest_step`；emu 取 `get_difftest_step()` → `difftest_nstep(step, enable_diff)` | `verilator.h:70-72`；`emu.cpp:522,540`；`difftest.cpp:114-138` | 机制已核；**步长数值本次未从 JSON 解析**（见 §F.4） |
| 8 | 比对字段·标量 | `xrf` 恒比 | `refproxy.cpp:186-190` | 主 30/30、扩容 129/129 |
| 9 | 比对字段·向量 | `vrf` 在 `CONFIG_DIFFTEST_ARCHVECREGSTATE` 下参与 `memcmp` | `refproxy.cpp:192-194`；判据 `20-run-difftest.sh:384-387` | `vec_reg_compare=达标` ×3 |
| 10 | 比对字段·CSR | `csr` 恒比；`vcsr` 另受 `CONFIG_DIFFTEST_VECCSRSTATE` 控制 | `refproxy.cpp:195-197,224` | `csr` 已比；**`vcsr` 开关本次未单独核**（见 §F.5） |
| 11 | 单例指令上限 | `MAX_INSTR=200000000`（默认） | `20-run-difftest.sh:37` | 本次 JSON 未记录覆盖值（见 §F.4） |
| 12 | 单例超时 | `TIMEOUT_S=1800`（默认），并按作业剩余时间收紧 | `20-run-difftest.sh:38,423-431` | 同上 |
| 13 | 性能用例口径 | 4 例 `--no-diff`（`perf_vdot`/`perf_base`/`perf_vadd`/`perf_vmacc`） | `stage3/3.1.2-difftest/manifest.tsv:27-30` | 这 4 例**不计入** difftest 逐位比对（口径声明） |
| 14 | 清单指纹 | 本地占位版：30 数据行、`sha256 a90d1071…`；远端绝对路径版：30 行、`e12470e6…` | 本地 `sha256sum stage3/3.1.2-difftest/manifest.tsv`（本次【实测】）；JSON `manifest` 字段 | 两份 30 例 JSON 的 hash 同为 `e12470e6…` |
| 15 | 负例判据 | `HIT CRITICAL ERROR` ≥ 1 ∧ 无 `diff REF`/`Different operands` ∧ `ABORT=0` ∧ 无哨兵串 | `20-run-difftest.sh:248-260`；`94-run-extra.sh:239-246` | 主清单 8 个 negative 通过；扩容 `negatives_illegal=41/41` |
| 16 | G0 反例 | 期望值故意错 1 bit，必须 `MISMATCH` | `design/verify/cases/vdot_g0_badexp.c:1-2`；`20-run-difftest.sh:470-481` | 主 `G0 捕获 1/1`；扩容 `2/2` |
| 17 | 正例自检串 | 每个正例必须命中类专属 ERE（例：`CASE <cid>: MATCH`、`RAND_SUMMARY … mism=0 ab_bad=0`、`MIX verdict=ALL_OK`） | `20-run-difftest.sh:194-220` | 主 `自检串 21/21`；扩容 `86/86` |
| 18 | 结果 JSON schema | `vdot-verify/1` | `20-run-difftest.sh:91`；三份 JSON 首字段 | 三份均带 `schema` |

---

## D. 判据表：每条判据堵的是哪一种“假绿”

> “假绿”= 用例跑到 `HIT GOOD TRAP` 但结果其实错、或参照模型其实没比。判据名与 `criteria[].name` 逐字一致，取值来自三份 JSON 的 `criteria[]`。

| criterion | 堵的假绿 | 实现位置 | `126676734` | `127137638` | `127031933` |
|---|---|---|---|---|---|
| `nm_exec_vdot` | 参照 `.so` 还是旧版、根本不含 vdot | `20-run-difftest.sh:376-381` | 2 行 | 2 行 | 2 行 |
| `vec_reg_compare` | 向量寄存器没参与比较 | `20-run-difftest.sh:382-388` | 达标 | 达标 | 达标 |
| `cases_all_ran` | 清单里有用例没跑 | `20-run-difftest.sh:442-445` | 30/30 | 30/30 | 129/129 |
| `cases_pass` | 有用例失败 | `20-run-difftest.sh:451-455` | 30/30 | 30/30 | 129/129 |
| `reg_size_match` | NEMU 与 DUT 的 state 不配套 | `20-run-difftest.sh:461-465` | 0 次 | 0 次 | 0 次 |
| `no_empty_green` | 正例没有自检串 / G0 反例没被判负 | `20-run-difftest.sh:470-481` | 21/21 + 1/1 | 21/21 + 1/1 | 86/86 + 2/2 |
| `metrics_three` | 三口径数字缺项 | `20-run-difftest.sh:507-512` | 齐备 | 齐备 | —（非 perf 清单） |
| `t5_delta_latency` | `L_vmacc==L_vdot` 且 `ΔL_mv=1` 不成立 | `20-run-difftest.sh:522-529` | 达标 | 达标 | — |
| `negatives_illegal` | 负例没有双侧一致陷入 | `94-run-extra.sh:316-320` | — | — | 41/41 |
| `golden_crosscheck` | 扩容期望常量与金模型不一致 | `94-run-extra.sh:322`；`extra_crosscheck.py:284-291` | — | — | MATCH |
| `regression_delta` | 新增失败 | `20-run-difftest.sh:538-547` | `0` | `0` | — |

**这张表怎么读**：`cases_pass` 只说明“程序都跑到 `GOOD TRAP`”；真正防“结果错但程序正常结束”的是 `no_empty_green`（自检串 + G0 反例）与 `vec_reg_compare`（向量寄存器真的比了）。两者缺一，`cases_pass=30/30` 都可能只是空绿。`reg_size_match` 堵的是“参照模型不配套”——它不会让用例失败，只会让比对结果不可信。

---

## E. 三份运行的参数快照（JSON 实读）

| 项 | 主清单 `126676734` | P-2 主清单 `127137638` | 扩容 `127031933` |
|---|---|---|---|
| 结果文件 | `results/difftest/20-full-20261103T142246.json` | `results/difftest/20-full-20261107T104227.json` | `results/difftest/extra/94-extra-20261106T143635.json` |
| `status` | 通过 | 通过 | 通过 |
| 起止 | `2026-11-03T14:22:46+0800` → `14:51:47`（29:01） | `2026-11-07T10:42:27+0800` → `11:12:17`（29:50） | `2026-11-06T14:36:35+0800` → `16:09:10`（1:32:35） |
| 清单 | `manifest.tsv`，30 行，`e12470e6…` | `manifest.p2-30.abs.tsv`，30 行，`e12470e6…` | `manifest.extra.abs.tsv`，129 行，`84680ef6…` |
| 用例 | 30/30 | 30/30 | 129/129 |
| criteria | 9/9 达标 | 9/9 达标 | 8/8 达标 |
| `regression_delta` | `0` | `0` | — |

**清单指纹为什么有两个值**：本地冻结件 `stage3/3.1.2-difftest/manifest.tsv` 的 image 列写的是 `@IMG_DIR@` 占位符，`sha256sum` = `a90d1071…`（本次【实测】）；远端运行时 `make_manifest.sh` 把占位符替换成绝对路径，所以 JSON 里记的是替换后的 `e12470e6…`。两者**都是 30 数据行**，不是清单漂移；两份 30 例 JSON（`142246` 与 `104227`）的 hash 相同，也说明两次运行用的是同一份替换后清单。**但当前远端清单已不是这一份**：`stage3/3.1.2-difftest/README.md:56` 记录远端 `test/manifest.tsv` 现为 `413b5796…`/31 行（2026-11-06 实读，多一行 `perf_base_chain`），与 `142246` 运行时的 30 行版不同；再跑 `--full` 会选 31 例，“30/30”不能按当前远端清单复现（该漂移在 HANDOFF §0 O4 登记为未收敛）。

---

## F. 边界与未验证项（不得写成已证）

1. **平台边界**：这是 **QEMU 级 difftest**（NEMU 参考 `.so` vs Verilator `build/emu`），不是硅片实测；平台为 `kshcnormal`（`stage3/3.3/report.md` §2）。
2. **没有 golden↔NEMU 直连**：如 §A 所述，三端一致性是“金模型/算法 B ↔ RTL（用例自检）+ NEMU ↔ RTL（difftest）”传递闭合，不是单独一条直连器。不得把传递闭合写成“已直接比对”。
3. **负例只判“是否陷入”**：主清单与扩容的 negative 判据都是 `HIT CRITICAL ERROR` + 无失配 + 无哨兵（§C 第 15 行）。`cause` / `epc` / `mtval` 三个字段**没有逐例断言**——本次实跑 `grep -rn "mcause\|mepc\|mtval" design/verify core-package | wc -l` → **0**。因此可主张“两侧一致地陷入非法”，不可主张“异常字段逐字段相等”。
4. **步长/上限的实际取值未从 JSON 解析**：`MAX_INSTR`、`TIMEOUT_S`、`difftest_step` 只在脚本里有默认值或机制，JSON 未记录本次实际生效值；本节只写“脚本默认值 + 机制”，不把默认值写成实测值。
5. **`vcsr` 比对开关未单独核**：`vrf` 的开关有 `vec_reg_compare` 判据兜底；`vcsr`（`CONFIG_DIFFTEST_VECCSRSTATE`）本次没有对应判据，只从 `refproxy.cpp:195-197` 读到“宏打开才比”。不得写成“向量 CSR 已比”。
6. **4 个性能用例 `--no-diff`**：`perf_vdot`/`perf_base`/`perf_vadd`/`perf_vmacc` 只在自检口径下运行，不参与 difftest 逐位比对（`manifest.tsv:27-30`）。引用它们的数字时必须带这条限定。
7. **结构覆盖未运行**：RTL line/toggle 覆盖在 2026-11-07 实跑受阻（`--diff` 退出段 SIGSEGV、`.coverage.dat` 0 B），本节不引用任何结构覆盖数字；状态见 `stage3/3.3/sections/coverage.md` §D。
8. **金模型自测的范围**：`vdot_model_test.py` 本次实跑 `ALL TESTS PASSED (1142 cases)`（EXIT=0），证明的是**模型自身**的三算法交叉（金模型 / 算法 A 任意精度 / 算法 B 位级）与三变异自检；它不等于“模型与 NEMU 逐例比对”。

---

## G. 复现命令（零机时）

```bash
# 1) 金模型自测（本次实跑：ALL TESTS PASSED (1142 cases)，EXIT=0）
python3 -I design/verify/vdot_model_test.py

# 2) 本地清单与远端清单指纹（本次实跑）
sha256sum stage3/3.1.2-difftest/manifest.tsv    # a90d1071…（@IMG_DIR@ 占位版）
python3 -I -c "import json;d=json.load(open('results/difftest/20-full-20261103T142246.json'));print(d['manifest'])"

# 3) 读三份 JSON 的判据（不重跑仿真）
python3 -I -c "import json;d=json.load(open('results/difftest/20-full-20261103T142246.json'));print([(c['name'],c['status'],c['actual']) for c in d['criteria']])"

# 4) 抽查负例日志（本次实跑读到 29848-29849 行）
grep -n 'HIT CRITICAL ERROR\|HIT GOOD TRAP' \
  stage3/3.1.2-difftest/full-logs-20261103T142246/vdot_ill_vstart.20261103T142246.log
```

---

**来源与状态**：本文件 2026-11-08 编写；所有 `file:line` 均为本次逐行实读（`repos/XiangShan` 实施 HEAD `913ddd3`、`repos/XiangShan/yunsuan` `8942811`、`repos/NEMU` `a9dca53`）；所有运行数字来自仓库内已有 JSON，**本轮未创建任何作业**。与 `report.md` §5.6 的分工：§5.6 给四环正文，本文件给图、参数表与判据表；两处的数字口径一致，若后续更新以 `report.md` §5.6 的来源注为准。