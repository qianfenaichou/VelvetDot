# 06 整核接入与 NEMU 扩展

一条 `vdot.vv` 从译码到写回要经过香山向量后端的哪些既有模块，是本章回答的问题。这个问题的答案决定了整核接入的实际改动量：若译码、非法判定、发射、写回都沿用既有通道，新增硬件就只有一个归约模块和一个输出端的选择器，其余是表项、端口和断言。本章同时说明 NEMU 侧加的三处改动与 Python 金模型的约束，因为这三端只要有一端把 `vl=0` 或旧 `vd` 解释得不一样，差分验证就会在无声处失真。

## 6.1 译码与类型码

译码器把 32 位指令字拆成「这是哪条指令、读写哪些寄存器」。识别 `vdot.vv` 的第一步，是在 rocket-chip 的指令表里给它一条位模式（`repos/XiangShan/rocket-chip/src/main/scala/rocket/Instructions.scala:459`）。位模式是一串 32 位匹配模板，`?` 表示这一位取任意值都算命中。模板写死了 opcode `1010111`、funct3 `010`、funct6 `001110`，以及第 25 位的 `vm=1`（编码的选择与推导见第 4 章）。掩码形式（`vm=0`）的同 funct6 编码不命中这条表项，落到默认非法分支，所以「`vm` 必须为 1」不需要在译码之后再判一次。

命中后，`vdot.vv` 归入 OPMVV 大类，交给向量乘加单元。`VecDecoder.scala:385` 的表项是 `OPMVV(F, FuType.vimac, VimacType.vdot, F, T, F, UopSplitType.VEC_VVV)`。第一个参数 `vdRen=F` 决定第三源操作数的类型：`OPMVV` 的 `src3` 在该参数为假时取 `SrcType.X`（`VecDecoder.scala:91`），即不存在第三个源。于是「不读旧 `vd`」在译码这一步成立，不依赖执行单元自觉。语义上也该如此：`vdot.vv` 是覆盖写，`vd` 的旧值不参与运算，与 `vmacc` 的累加不同。`VEC_VVV` 是拆分方式，指两个向量源、一个向量目的。

执行单元看的是 9 位类型码。`VimacOpcode.vdot` 的取值是 3 位操作码 `3'b111`（`yunsuan/encoding/Opcode/VimacOpcode.scala:14`）。`VimacType.vdot` 把它与符号位、格式拼成 `0b00_110_0_111`，即 `0x067`（`yunsuan/package.scala:400`）。这 9 位一次说清三件事：两个源按有符号解释、旧 `vd` 位取 `X`、格式是 VVV。

类型码里「不读旧 `vd`」这一位必须与另外两个开关同时成立。`vdot` 不进 `VimacOpcode.isMacc`（同文件 `:18` 只列 vmacc、vnmsac、vmadd、vnmsub），也不登记进 `vmaInsts`。三个开关任意一个写反，执行单元会读到无效的第三源，或者把累加项混进结果。

## 6.2 非法判定放在译码层

六条必要条件里只有两条需要新代码。`SEW=8` 与 `LMUL=1` 由 `VecExceptionGen` 新增的谓词判定（`VecExceptionGen.scala:276-277`）：`isVdot && ((SEW =/= 0.U) || (LMUL =/= 4.U))`。

这里有一处容易写错。香山把 `vlmul` 字段映射成 `LMUL = Cat(~vlmul(2), vlmul(1,0))`（同文件 `:58`），字段值 `000` 对应的内部 `LMUL` 是 4，代表架构上的 LMUL=1。判定写成 `LMUL =/= 4` 是对的。若照字面写 `vlmul === 1`，放行的会是 LMUL=2。源码注释与补丁说明都把这一条单独标出。

其余四条不新增代码，各由既有项覆盖。`vm=1` 由位模式保证。`vstart=0` 落在既有 `vstartIllegal`（`:280`），因为 `vdot` 的 fuType 是 `vimac`，属于向量算术类。`vill=0` 由 `villIllegal`（`:178`）覆盖。`mstatus.VS≠OFF` 由 `DecodeUnit.scala:908` 统一拦截所有向量指令。新增的 `vdotIllegal` 并入 `illegalInst`（`:299`），并加 `dontTouch`（`:306`）保留可观测性。

判定必须放在译码层，不能下放给执行单元。Mgu 的非法输出恒为 `false.B`（`Mgu.scala:131`），执行单元不会替译码器报错。若放到后面判，非法指令会先占用发射槽和物理寄存器，再在写回时抛异常，异常就不精确。

## 6.3 发射与写回沿用既有通道

`vdot` 的 fuType 是 `FuType.vimac`，因此发射到既有的向量乘加单元 `VIMacU`，复用 `VimacCfg` 的两拍流水（流水定义见第 5 章）。没有新增 `FuType`，没有新增功能单元配置，也没有新增流水级。重命名、发射队列、重排序缓冲（ROB，保证指令按序退休的队列）与退休逻辑都没有改动。

数据从既有乘法阵列里取。`VIMac64b` 原本就把 8 个 16 位乘积放在内部信号 `sum_wo` 上，把第一级 fire 放在 `fireS1` 上。X15 把这两根线连同 `walOut` 一次性导出为端口（`yunsuan/vector/vectorIMAC/VIMac64b.scala:35-37`）。`VdotReduce` 只在 `fireS1` 为高时寄存归约结果，与 `walOut` 同拍，所以没有拖长流水。

写回在 wrapper 输出端做一次选择（`VIMacU.scala:160`）：`Mux(outIsVdot, vdotReduce.io.vd, mgu.io.out.vd)`。Mgu 是向量后端统一处理尾元素的模块，它逐字节选择：活跃字节取新结果，非活跃字节在 agnostic 策略下写 `0xFF`，否则保留旧 `vd`（`Mgu.scala:90-94`）。两种取值都不等于 0。`vdot` 要求 `vd[127:32]` 恒为零，只能在自己的输出上给常量零。

选择信号 `outIsVdot` 取自 `outCtrl.fuOpType`（`VIMacU.scala:159`），即输出级的控制位。这里不能用输入级。控制位流水按 `VimacCfg` 的 `latency=2` 建了 3 级（`FuncUnit.scala:76`），`outCtrl` 取末级（`VecPipedFuncUnit.scala:68`），所以输入级与输出级相差两拍。背靠背混合流里，`vdot` 后面紧跟一条 `vmacc` 时，用输入级会把别的指令的结果选给这一条。wrapper 另加两条断言（`VIMacU.scala:165`、`:167`）：一条检查写回值的 [127:32] 位全零，一条检查输出 valid 不会在没有 ready 时保持。

向量状态方面，`vdot` 改写两处：`vd` 的低 32 位写结果、高 96 位写零；`mstatus.VS` 置 Dirty。`vstart` 在合法执行时本来就是 0，RTL 不写它（写使能条件要求 `vstart` 非零）；NEMU 侧则在执行函数里显式置 0。`vxsat` 不被改写，也不产生置位，保持执行前的值。`VIMac64b` 对非定点指令输出 0（`VIMac64b.scala:306`），CSR 侧按位或累积（`Unprivileged.scala:107`），所以预置的 1 读回还是 1，不是恒为 0。

## 6.4 NEMU 侧的三处改动

NEMU 是差分验证的参照物：同一段程序分别在 RTL 与 NEMU 上执行，逐条比对架构状态。它和 RTL 由两套独立代码写成，同错成一样的概率低。NEMU 侧一共三处改动，合计 3 个文件、+35/−1 行（按补丁 diffstat 统计，含注释与空行）。

第一处是译码表项（`repos/NEMU/src/isa/riscv64/instr/rvv/decode.h:373`），写成 `"001110 1 ????? ????? ??? ????? ????? ??"`。这条表项自己只钉住 funct6 `001110` 与 `vm=1`。funct3 `010` 由 `def_THelper(OP_V)` 的表项在分发到 `vopmvv` 时钉住（`decode.h:539`）；opcode 的高 5 位由 `OP_V` 表项钉住（`instr/decode.c:100`），低 2 位由指令长度判定保证（只有以 `11` 结尾的指令才进主表）。字符串里的 `?` 不只在寄存器号上，还留给 funct3 的 3 位与 opcode 的 7 位。掩码编码不命中这张表，落到 `EXEC_ID_inv`，与 RTL 的默认非法分支一致。

第二处是执行函数 `def_EHelper(vdot)`（`vcompute.h:872-901`）。其一，不复用 `ARITH` 宏。那组宏按 `vl` 逐 lane 散布，写出的结果与元素一一对应；`vdot` 是 8 个 lane 求和后只写一个 32 位结果，形状不对。其二，vstart 检查用 `check_vstart_exception`，不用 `check_vstart_ignore`。后者在 `vstart >= vl`（含 `vl=0`）时跳过写回，而本指令在任意 `vl` 下都全写，跳过就错。其三，高 96 位用 `set_vreg` 逐字写 0，不用 `set_vreg_tail`，因为后者把每个 64 位字都写成全 1（`0xffffffffffffffff`）。

第三处是枚举（`isa-all-instr.h:177`），在 `VECTOR_INSTR_TERNARY(f)` 里加 `f(vdot)`。不加这一项，`EXEC_ID_vdot` 不存在，NEMU 编译不过。三处必须同一个提交。执行函数收尾时做三件事：`vp_set_dirty()` 把 `mstatus.VS` 置 Dirty，`vstart->val = 0`，`vxsat` 不动。

构建产物上查得到实现：`nm` 命中 `exec_vdot` 2 行（2026-11-03 在构建树上复跑，`t exec_vdot` 与 `t exec_vdot.part.0`）。差分验证侧另开了架构向量寄存器比对（`difftest-state.h` 含 `CONFIG_DIFFTEST_ARCHVECREGSTATE`），比的是向量寄存器，不只是通用寄存器。

## 6.5 金模型与三端结构对照

Python 金模型（`design/verify/vdot_model.py`）是从 `design/SPEC.md` 直接写出的第三份实现，不是 NEMU 的翻译。三份实现各自独立，比对才有意义。

模型用四个手段把语义钉住。第一，接口按整寄存器：输入输出都是 128 位整数，RTL 与 NEMU 的寄存器转储可以直接传入，不需要拆 lane 的适配层；`lanes_int8` 只读 `[63:0]`，高位不碰。第二，非法判定写成有序列表 `illegal_reasons`，顺序固定为 `VS=OFF → vill → SEW → LMUL → vm → vstart`。这个分组与 NEMU 入口检查一致：`require_vector(true)` 先判 VS 与 vill，再判 vtype，`check_vstart_exception` 收尾。第三，写回函数显式接收旧 `vd` 再丢弃（`writeback` 里 `_ = old_vd`），把「旧 `vd` 不影响结果」变成可测性质；变异自检把旧 `vd` 混进结果或改坏高位，测试必须报错。第四，内部和超出 19 位有符号范围时断言失败，防止以后改 K 或改位宽时静默溢出（19 位的推导见第 4 章）。

表 06-1 把三端在同一批字段上的做法并排。列是三个实现，行是编码、写回、旧 `vd`、非法判定与 `vstart` 后置。表里只放结构与常量，不放测量值；读表时按行看三端是否说同一件事，不按字面逐格比对字符串。

表 06-1　三端在五个字段上的对照

| 字段 | RTL（香山） | NEMU | Python 金模型 |
|---|---|---|---|
| 编码 | `VDOT_VV` 位模式，`vm` 位写死 1（`Instructions.scala:459`） | `"001110 1 …"` 表项，`vm` 位写死 1（`decode.h:373`） | `decode_vdot_vv` 固定 opcode、funct3、funct6、vm 共 17 位，vd/vs1/vs2 不约束 |
| 写回 | `Mux(outIsVdot, …)`，高 96 位取常量零（`VIMacU.scala:160`） | 4 个 32 位字，首字结果、其余 0（`vcompute.h:894-897`） | `writeback` 返回 32 位结果，高位为 0 |
| 旧 `vd` | `vdRen=F`，第三源取 `X`（`VecDecoder.scala:385,91`） | 函数不读旧 `vd`，写满 4 字 | 入参保留、结果忽略 |
| 非法判定 | SEW/LMUL 用新增谓词，其余四项用既有项（`VecExceptionGen.scala:277,299`） | `require_vector(true)` 加 `vm/vsew/vlmul` 检查加 `check_vstart_exception` | `illegal_reasons` 六条，顺序固定 |
| `vstart` 之后 | 正常路径为 0 | `vstart->val = 0` | 返回 `vstart_next = 0` |

五行的写法不同，语义一一对应。对应的判断标准是每行三端指向同一件事：编码行三端都要求 opcode `1010111`、funct3 `010`、funct6 `001110` 且 `vm=1`；写回行三端都是「低 32 位为结果、高 96 位为 0」；旧 `vd` 行三端都不读旧值；非法判定行三端都覆盖同一组六条条件；`vstart` 行三端都在执行后归零。这不等于行为等价。三端是否在每条用例上给出相同结果，由差分验证的通过数回答（第 7 章）。

## 6.6 改动位置

表 06-2 按仓库列出本章涉及的改动。列依次是文件与行、改了什么、对应补丁、这一处证明什么。行数取自各补丁的 diffstat，含注释与空行。

表 06-2　本章涉及的改动位置

| 文件:行 | 改动 | 补丁（diffstat） | 证明什么 |
|---|---|---|---|
| rocket-chip `Instructions.scala:459` | 新增 `VDOT_VV` 位模式，`vm` 位写死 1 | X1，1 文件 +2 | 编码在译码前端被识别 |
| 香山 `VecDecoder.scala:385` | 表项归入 OPMVV/vimac，`vdRen=F`，`VEC_VVV` | X1/X2，2 文件 +2/−1 | 不读旧 `vd`；发射目标确定 |
| 香山 `VecExceptionGen.scala:276-277,299,306` | SEW/LMUL 谓词并入 `illegalInst`，加 `dontTouch` | X14，1 文件 +7/−1 | 非法在派发前被拦 |
| yunsuan `VimacOpcode.scala:14`、`package.scala:400` | `vdot = 3'b111`；9 位类型码 `0x067` | X6/X7，2 文件 +2 | 执行单元认得出这条指令 |
| yunsuan `VIMac64b.scala:35-37` | 导出 `sum_wo`、`walOut`、`fireS1` | X15，1 文件 +11 | 归约模块有数据与使能 |
| yunsuan `VdotReduce.scala`（新增） | 8→1 归约、19 位加法器、输出高 96 位为零 | X-new，1 文件 +45 | 高位零由数据通路产生 |
| 香山 `wrapper/VIMacU.scala:66,129-130,159-160,165,167` | 例化归约模块，输出 Mux 旁路 Mgu，两条断言 | X8，2 文件 +20/−3 | 写回值不再经过 Mgu |
| NEMU `isa-all-instr.h:177`、`decode.h:373`、`vcompute.h:872-901` | 枚举、表项、执行函数 | N1/N2/N3，3 文件 +35/−1 | 参考模型可执行 |

表里三个标 +2 的补丁内容不同：X1 只加一条位模式，X6/X7 只加两个常量，X1/X2 在 `VecDecoder` 新增一行表项。X1/X2 的 −1 不是删表项，是 rocket-chip 子模块指针那一行的替换。这些行数含注释与空行，不能当代码复杂度用。X8 的「2 文件」里有一项也是子模块指针，不是源码。

应用顺序由编译依赖决定，不由补丁编号决定。yunsuan 必须最先：X8 的补丁带子模块指针更新，指针指向带 X6/X7 与 X15 的那个提交，主仓编译时按这个指针取 yunsuan 代码。第二是 rocket-chip 的位模式，`VecDecoder` 引用 `VDOT_VV` 之前它必须存在。再是香山的译码、异常与 wrapper。NEMU 与前三者没有编译依赖，可以并行。

## 6.7 本章没有证明的部分

本章没有做 ISA 级的形式证明。已有的等价 miter（把两份设计并联、用 SAT 证明输出恒等的电路）只比对归约数据通路与行为级规格，不覆盖发射、旁路和写回选择。因此「三端结构一致」不能升级成「三端等价已证明」，行为等价只有差分验证的通过数支撑（第 7 章）。

`vl=0` 的处理是对 RVV 常规的有意偏离：常规做法是不写回，本项目按全写处理。NEMU 与金模型都按同一份规格实现，三端一起偏离，差分验证不会把它判成错误。这条只能靠对照规格发现。

非法路径执行后的 `mstatus.VS` 取值没有测。现有用例 `vdot_ill_vs.c` 只让非法指令陷入陷阱，没有在陷阱处理后读回 `mstatus`（`design/verify/cases/vdot_ill_vs.c:22-25`）。所以本章不写「不变」，也不写具体值。这一项空着，不能支撑结论。