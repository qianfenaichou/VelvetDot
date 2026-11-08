# 12 源码与验证

这份附录收四样：改了哪些文件、三份实现各自在哪、用例清单怎么组织、每类检查用哪条命令。核对位置、加用例、复跑检查时来这里查表。路径相对仓库根，行号指当前工作树。

## 12.1 代码改动位置

改动分在四个仓：rocket-chip 给编码位模式，香山管译码与写回选择，yunsuan 放归约器与端口，NEMU 放参考模型。十个补丁合计 +272/−12 行，其中两个条目是子模块指针。

表 12-1　代码改动位置

| 文件:行 | 改了什么 | 为什么改 | 补丁前缀 |
|---|---|---|---|
| `repos/XiangShan/rocket-chip/src/main/scala/rocket/Instructions.scala:459` | 新增 `VDOT_VV` 位模式，`vm` 位钉 1 | 让指令在译码前端被识别。掩码形式不命中，落到默认非法分支 | `0001-X1` |
| `repos/XiangShan/src/main/scala/xiangshan/backend/decode/VecDecoder.scala:385` | 表项 `OPMVV(F, vimac, VimacType.vdot, …, VEC_VVV)`，`vdRen=F` | 归入既有向量乘加单元。第三源取 `X`，旧 `vd` 不参与 | `0001-X1-X2` |
| `repos/XiangShan/src/main/scala/xiangshan/backend/decode/VecExceptionGen.scala:276-277,299` | `isVdot` 与 `vdotIllegal` 并入 `illegalInst` | `SEW≠8` 或 `LMUL≠1` 在译码级拦下，异常保持精确 | `0002-X14` |
| `repos/XiangShan/yunsuan/src/main/scala/yunsuan/encoding/Opcode/VimacOpcode.scala:14` 与 `repos/XiangShan/yunsuan/src/main/scala/yunsuan/package.scala:400` | `vdot = "b111"`；九位类型码 `0x067` | 新操作码不复用旧值。类型码一次编进「有符号×有符号、不读旧 `vd`、VVV」 | `0001-X6-X7` |
| `repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VIMac64b.scala:35-37` | 导出 `sum_wo`、`walOut`、`fireS1` | 归约器取打拍前的八个乘积，使能只认这一根线，乘法阵列不动 | `0002-X15` |
| `repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala:28-58` | 新增 8→1 归约：19 位符号扩展、4:2 压缩树、19 位加法器、`Cat(96'b0, sext32(S))` | 点积只缺跨 lane 求和 | `0003-X-new` |
| 同文件 `:49-50,53` | 把 `(sum, carry)` 对寄存在 `fireS1` 上，加法器移到第二拍 | 第一拍只走符号扩展与压缩树，拍数不变 | `0005` |
| `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:66,129-130,159-160,165` | 例化归约器。输出级 `Mux(outIsVdot, …)` 旁路 Mgu，断言高 96 位为零 | Mgu 的 tail 路径留旧值、agnostic 路径写全 1，都给不出零 | `0003-X8` |
| `repos/NEMU/src/isa/riscv64/instr/rvv/decode.h:373` | 表项 `"001110 1 …"` | 参考模型按同一 funct6 与 `vm=1` 识别 | `0001-N1-N2-N3` |
| `repos/NEMU/src/isa/riscv64/instr/rvv/vcompute.h:877-901` | `def_EHelper(vdot)`：逐项累加到 `int64`，写 32 位后手写循环清 96 位 | 不走 `ARITH` 宏（形状不对），不用 `set_vreg_tail`（它写 `0xFF`） | `0001-N1-N2-N3` |
| `repos/NEMU/src/isa/riscv64/include/isa-all-instr.h:177` | `f(vdot)` 枚举注册 | 不注册则 `EXEC_ID_vdot` 不存在，编不过 | `0001-N1-N2-N3` |
| `repos/XiangShan/src/test/scala/yunsuan/vectortest/mac/VdotReduceSpec.scala:40-64,97` | 定向用例加固定种子 42 的 200 组随机 | 期望值来自独立算法 B，不重跑被测公式 | `0004-tests` |

表注：行数取自各补丁 diffstat，含注释与空行。补丁在 `patches/`。`stage2/2.2-rtl/` 下九份同名文件与之逐字节相同，`0005` 只在根目录。

两处容易改错。`repos/XiangShan/src/main/scala/xiangshan/backend/fu/vector/VIMacU.scala` 是死代码，75 行里 `vdot` 零命中，改它不影响仿真，活文件在 `wrapper/` 下。`VdotReduce.scala` 的包声明是 `yunsuan.vector.mac`，与目录名 `vectorIMAC` 不同，按 import 找文件。

## 12.2 三端对应与互相验证

三份实现各自独立：RTL 是硬件，NEMU 是差分参照，Python 金模型从规格直接写出。

表 12-2　三端在六个字段上的对应

| 字段 | RTL（香山） | NEMU | Python 金模型 |
|---|---|---|---|
| 编码 | `Instructions.scala:459` 的位模式 | `decode.h:373` 的字符串表项 | `vdot_model.py:232` 的 `decode_vdot_vv` |
| 求和 | `VdotReduce.scala:41,53` 的压缩树与加法器 | `vcompute.h:885-891` 的 `int64` 累加 | `vdot_model.py:116` 的 `dot_product` |
| 取哪些 lane | `VIMacU.scala:129` 只接 `vimacs(0)` | `vcompute.h:886-889` 只循环 `i<8` | `vdot_model.py:107` 的 `lanes_int8` 只读 `[63:0]` |
| 写回 | `VdotReduce.scala:57` 拼 `96'b0` | `vcompute.h:895-897` 四个字，首字结果其余 0 | `vdot_model.py:148` 的 `writeback` |
| 旧 `vd` | `VecDecoder.scala:385` 的 `vdRen=F` | 函数不读旧 `vd` | 入参保留、`_ = old_vd` 丢弃 |
| 非法条件 | `VecExceptionGen.scala:277` 判 SEW/LMUL，其余四项用既有项 | `require_vector(true)`、`vm/vsew/vlmul` 检查、`check_vstart_exception` | `vdot_model.py:123` 的 `illegal_reasons` 六条有序 |

表注：路径省略各仓前缀，`vdot_model.py` 指 `design/verify/vdot_model.py`。归约器与乘法单元在 yunsuan 的 `vector/vectorIMAC/` 下，其余 Scala 在香山 `backend/` 下。

互相验证分三条线。RTL 与 NEMU 靠差分验证：同一镜像两边各跑一遍，每条指令退休时比较向量寄存器，通过数见第 7 章。金模型不参与运行，只生成期望常量：扩容 224 例的断言常量全由它算出，`design/verify/cases/extra_crosscheck.py` 再把常量与金模型逐条重算。金模型另有 1142 例自检，用位级算法与解包算法两套路径重算同一组输入。RTL 与行为级规格之间有一条形式等价检查，只覆盖归约数据通路、三拍有界，见第 10 章。

三端结构一致不等于行为等价。规格读错时三端一起错，差分验证不会报错，只能靠对照 `design/SPEC.md` 发现。

## 12.3 测试清单怎么组织

清单分两份，互不合并。主清单 `design/verify/cases/manifest.tsv` 30 行，是固定回归集。扩容清单 `design/verify/cases/manifest.extra.tsv` 224 行，单独一次运行。两份用例名交集为 0，并集 254 个条目，254 不是任何一次运行的用例数。清单四列制表符文本：用例名、类别、镜像路径（`@IMG_DIR@` 占位，由 `make_manifest.sh` 换绝对路径）、附加参数（四个性能用例写 `--no-diff`）。

一条用例含四件东西：C 源、期望常量（烧进源里的断言值）、自检串（程序末尾打印 `CASE <用例名>: MATCH`，这是「比对确实发生」的凭据）、清单行。判负用例把期望值故意写错，要求打印 `MISMATCH`。非法输入用例不比较结果，只要求两侧停在同一处陷阱。

表 12-3　新增一条用例要改的文件

| 加到哪 | 改哪些文件 | 之后做什么 |
|---|---|---|
| 主清单 | `design/verify/cases/gen.py` 加一条 `src(...)` 或 `illegal(...)`。`manifest.tsv` 没有生成脚本，需自行加一行 | 跑 `build_all.sh` 重编镜像。改行会变 `a90d1071…` 这个哈希 |
| 扩容清单 | `design/verify/cases/gen_extra.py` 的 `CASES`、`LOOP_CASES` 或 `NEG` 表加一条 | 跑 `gen_extra.py`，它同时写 `extra/*.c`、`manifest.extra.tsv`、`cover.extra.tsv`。再跑 `build_extra.sh` 编镜像 |

表注：`gen_extra.py` 的三类配额在 `CLASS_QUOTA`（重叠 24、流水 40、异常 32），不足时生成自报失败。

自检串要与运行脚本认的串对上。`core-package/scripts/20-run-difftest.sh:199-226` 按类别给串：`vdot-pos`、`vdot-neg`、`vdot-bound` 认 `CASE <用例名>: MATCH`，`vdot-matrix` 认 `MATRIX verdict=ALL_OK`，`vdot-rand` 认 `RAND_SUMMARY … mism=0`，性能类认 `PERF_* verdict=ALL_OK`。新用例落在新类别时这条映射也要加，否则程序正常结束也不判通过。

## 12.4 复现命令

表 12-4　按检查类别取命令

| 跑什么 | 命令 | 产物或成功标志 |
|---|---|---|
| 金模型自检 | `python3 -I design/verify/vdot_model_test.py` | 打印 `ALL TESTS PASSED (1142 cases)`，退出码 0 |
| 扩容期望值复核 | `python3 -I design/verify/cases/extra_crosscheck.py --quiet` | 打印 `verdict=MATCH`，退出码 0 |
| 扩容配额自检 | `python3 -I design/verify/cases/gen_extra.py --check` | 打印各类行数与配额比较，不写文件 |
| 清单展开 | `bash design/verify/cases/make_manifest.sh <镜像目录>` | 标准输出为绝对路径清单 |
| 编用例镜像 | `AM_HOME=<nexus-am> bash design/verify/cases/build_all.sh` | 逐个 `.bin` 落到输出目录 |
| 主回归差分 | `sbatch … core-package/scripts/20-run-difftest.sh --full` | `results/difftest/20-full-20261107T104227.json` |
| 扩容差分 | `sbatch … core-package/scripts/94-run-extra.sh` | `results/difftest/extra/94-extra-20261108T014445.json` |
| 性能重复测量 | `sbatch … core-package/scripts/99-run-perf-repeat.sh --repeats 4` | `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json` |
| 结构覆盖 | `sbatch … core-package/scripts/95-coverage.sh` | `results/coverage/20261108T103732/` |
| 综合面积 | `sbatch … core-package/scripts/40-yosys-area.sh` | `results/yosys/40-area-20261107T104238.json` |
| 形式等价 | `sbatch … core-package/scripts/50-formal-miter.sh` | `results/formal/50-miter-20261104T093531.json` |
| RTL lint | `sbatch … core-package/scripts/25-rtl-lint.sh --rtl-dir <生成 RTL 目录>` | `results/lint/25-rtl-lint-20261104T113051.log` |
| Chisel 单测 | `cd repos/XiangShan/yunsuan && mill YunSuan.test.test` | 测试通过 |
| 单条指令波形 | `sbatch … core-package/scripts/62-wave-vdot.sh` | `results/wave/62-wave-20261105T091811.json` |

表注：前四行本地可跑，其余需集群与已构建的模拟器。`sbatch` 行省略分区与资源参数，见 `--help`。

前四行本地实跑过：金模型自检打印 `ALL TESTS PASSED (1142 cases)`、退出码 0。扩容复核打印 `cases=224 … problems=0` 与 `verdict=MATCH`、退出码 0。配额自检打印 224 行、退出码 0。清单展开把占位符换成给定目录。其余十行未运行，结论只引用已归档结果，命令取自脚本头注。表里的 30、224、1142、254、+272/−12 是文件或清单行数，不是测量值。
