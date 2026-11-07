# 2.1 vdot.vv 设计文档

**现状与口径（2026-11-07）**：本目录交付 5 个文件——`SPEC.md`、`ARCHITECTURE.md`、`ALGORITHM.md` 三份正式文档，加 `encoding-gate.py` 与 `encoding-gate-zvbc-2026-10-31.md` 两件编码论证。三份正式文档由 `design/` 下同名文件复制而来，打包时二者逐字节相同；此后两处文件各自经过文字修订，已不再逐字节相同（行数与 sha256 均会变化）。复核时以本目录文件为准，并在同一时点用 `sha256sum <file> design/<file> stage2/2.1-design/<file>` 记录当次结果。 **结论：2.1 设计文档已按官方编号打包；编码论证的结论是 `funct6=001110`/0x0E 在 riscv-opcodes `f24ac23` 全库空闲，但 `encoding-gate.py` 在本机复跑返回 EXIT=1（落地后自检），该退出码不是「编码冲突」，见 §3。**

对应官方条目：`docx/02-赛题与评分细则.md:53`「2.1 vdot.vv 设计文档：包含指令语义、微架构设计、数据通路等完整设计说明」。

## 1. 文件清单

| 文件 | 来源 | 内容 |
|---|---|---|
| `SPEC.md` | 由 `design/SPEC.md` 复制 | 指令语义、内部位宽、合法条件六条、编码三元组、非法判定、对照表、§3.4 外部互证判定 |
| `ARCHITECTURE.md` | 由 `design/ARCHITECTURE.md` 复制 | 微架构、8 处改动（X1/X2/X6/X7/X8/X14/X15/X-new）、2 拍时序、Mgu 旁路、断言 M06/M07 |
| `ALGORITHM.md` | 由 `design/ALGORITHM.md` 复制 | 19 位归约算法、CSA 4:2 树、金模型与用例生成、性能口径 |
| `encoding-gate.py` | 由 `design/verify/encoding-gate.py` 复制 | 编码冲突检查脚本（离线、可复跑，退出码 0/1/2/3/4 五态语义） |
| `encoding-gate-zvbc-2026-10-31.md` | 本目录内的编码论证记录 | Zvbc 冲突确认与 C-enc1b（0x0E）复核记录 + 全库扫描表 |

复核方法：在同一时点对三份文档取 `sha256sum` 并与 `design/` 下同名文件比对，`encoding-gate.py` 与 `design/verify/encoding-gate.py` 比对；`encoding-gate-zvbc-2026-10-31.md` 为包内独立记录，无 `design/` 对应件可比。文件清单与内容以上表为准，哈希与行数以当次命令输出为准，不在文中固化。

2026-11-07 打包时五对文件曾逐字节相同（`cmp -s` EXIT=0）；此后的文字修订使两处文件不再逐字节相同，此前的固化值不再代表现文件，故不再列出。

## 2. 编码论证要点（摘自 `encoding-gate-zvbc-2026-10-31.md`）

- 原 C-enc1 `funct6=001100`(0x0C) **被 Zvbc `vclmul.vv` 正式占用**（`(0x3220A1D7 & 0xfc00707f) == 0x30002057` → True）。
- 改用 **C-enc1b `funct6=001110`**(0x0E)，机器码 `vdot.vv v3,v2,v1` = **`0x3A20A1D7`**。
- riscv-opcodes `f24ac23` 全库（ratified + unratified）funct3=010/opcode=0x57 下：0x0E 空闲；0x28/0x2A/0x2C 被 `rv_zvdot4a` 占用（这正是不能选 0x2C 的原因）。
- 阳性对照：0x0C→`vclmul.vv`、0x2C→`vdot4a.vv` 均命中。

## 3. `encoding-gate.py` 本机复跑结果（按原文读）

实跑两条命令，输出与退出码（第二条命令中的快照目录指 riscv-opcodes `f24ac23` 的本地检出，未随本目录交付；可用 `git clone https://github.com/riscv/riscv-opcodes "$OPCODES_SNAPSHOT" && git -C "$OPCODES_SNAPSHOT" checkout f24ac23ec9fa947011781a09cd6fd25a7c36dc45` 取得）：

```
$ python3 design/verify/encoding-gate.py ; echo EXIT=$?
  无 [U] 段（未给 --snapshot）；末尾「!!! 检出冲突/漂移 3 条」+「结论: 检出冲突/文档漂移（退出码 1 …）」
  EXIT=1

$ python3 design/verify/encoding-gate.py --snapshot "$OPCODES_SNAPSHOT" ; echo EXIT=$?
  [U] riscv-opcodes 本地快照 …: 文件 141 / 指令行 1521（32 位 1459）-> 与冻结三元组重叠 0 条
  [U]   阳性对照: 0x0C->['vclmul.vv'] 0x2C->['vdot4a.vv'] ; 0x0E(本编码)->FREE ; 判定=管线有效
  EXIT=1
```

两次均 `EXIT=1`（`encoding-gate.py:531-533` 中 `if r.conflicts: … return 1` 优先于 `return 4`），三条命中是：

```
[SCALA-BITPAT] repos/XiangShan/rocket-chip/…/Instructions.scala: 0011101??????????010?????1010111 mask=0xFE00707F val=0x3A002057
[NEMU-DECODE-H] vopmvv 表项 vdot (pattern 0011101?????????????????????????)
[VECDECODER] opmvv 表项 VDOT_VV
```

**这三条命中是 vdot 自己落地的三处表项**，不是外部编码撞车：`VecDecoder.scala:385` 的 `VDOT_VV -> OPMVV(...)`、`repos/NEMU/src/isa/riscv64/instr/rvv/decode.h:373` 的 `def_INSTR_TAB("001110 1 …", vdot)`、`rocket-chip` 的 `VDOT_VV` BitPat。检查脚本 `scan_scala_bitpats`/`scan_nemu_decode_h`/`scan_vecdecoder_opmvv`（`encoding-gate.py` 内三个同名函数）扫描的是**工作区快照**，落地后必然扫到本指令自身，脚本没有「排除自身表项」的开关。

- 因此：**上游归属维度（`[U]`）0 重叠、0x0E FREE 是本次可用的编码论证结论**；工作区维度 `EXIT=1` 是「落地后自检」的预期表现，**不得**据此宣称编码冲突，也**不得**把 `EXIT=1` 记为检查通过。
- 该脚本的退出码是完成判据之一（见 `design/SPEC.md` §5），口径为：未落地 vdot 的干净树按脚本定义为 exit 0；在已落地 vdot 的工作区复跑为 `EXIT=1`（命中本指令自身表项，原因见上）。后者只反映落地后自检，**不得**据此宣称编码冲突，也**不得**记作检查通过。 **2026-11-06 的记录**：`vdot_model_test.py` **未运行**，不得记为通过。

## 4. 未包含 / 未验证

- riscv-opcodes `f24ac23` 本地快照（目录 1.2 MB，含 `extensions/`）**未收录**进本目录；要复跑 `[U]` 维度需按同一 commit 另取快照，原快照的取源记录为：`commit=f24ac23…`、`fetched=2026-11-01`、`how=curl … archive/f24ac23.tar.gz`。本目录只放脚本与复核记录两件。
- 本目录只收 3 份正式文档 + 2 件编码论证，对应的交付证据为：`design/SPEC.md` + `design/ARCHITECTURE.md` + `design/ALGORITHM.md`，编码论证 = `encoding-gate.py` + `encoding-gate-zvbc-2026-10-31.md` + 快照。`design/CODING-STD.md`（代码规范）**未收**——它是内部工程文档；为避免文档增殖，不另建评委向的设计文档。
- 2.1 的提交形态：本次为目录级打包，**未生成 PDF/单文件合集**。

## 5. 指令对比表（每行 = 官方一手定义 + 官方 URL + 授权状态）

**取源规则**（本表只为一件事：避免「转述失真」）：

1. 每行给 **一句定义 + 官方 URL + 授权状态**；URL 带固定 commit 或规范栏目定位，便于逐字复核；定义句能逐字引就逐字引，不能逐字引的必须标【转述】。
2. **网页正文取不到时降级，不编造**：Arm DDI0602 指令页是 JS 渲染 —— 本次 `curl` 只得 8,434 B 空壳、指令名关键词 `grep -c` → `0` ⇒ Arm 两行的定义句**只引 Arm 官方 ACLE 映射表原文**（`SMMLA Vd.4S,Vn.16B,Vm.16B`、`r -> Vd.4S` 等），**不引 Arm 伪代码**。
3. 本次 `github.com` 网页版在本机超时（`curl` rc=28），因此四份 RISC-V 一手文件按**同 commit 裸文件**取回，并逐件记录 sha256（记录未随本目录交付，见 §4）；URL 仍写 `github.com/…/blob/<commit>` 的规范地址，**离线可复核件与规范地址一一对应**。
4. 授权状态四档：`ratified`（已批准标准）/ `experimental`（上游明示尚未 ratify）/ `未批准提案`（RISC-V 提案仓，未进标准）/ `厂商`（Arm / Intel / NVIDIA 的厂商架构，本就不是 RISC-V 标准）。

### 5.1 对比表

| 指令 / 平台 | 官方一手定义（一句） | K / 结果粒度 | 是否读旧目标累加 | 授权状态 | 官方 URL |
|---|---|---|---|---|---|
| **本项目 `vdot.vv`** | `S = Σ_{i=0..7} sext19(sext8(vs1[i]) × sext8(vs2[i]))`，写 `vd[31:0]=sext32(S)`、`vd[127:32]=0`；K=8 与「写 `vd[0]`、其余清零」逐字来自赛题官方伪代码 `for i in range(8)` / `vd[1..VLEN-1] = 0` | 8 / 每条指令 **1 个** 32 位结果 | **否**（`vdRen=F`） | 自定义指令（非 RISC-V 标准编码；语义按赛题官方伪代码） | `https://rv.cie.org.cn/direction?id=8`（赛题页；本仓转录 `docx/02-赛题与评分细则.md:24-33`） |
| RISC-V `Zvdot4a8i` → `vdot4a.vv`（LLVM） | 逐字：`def VDOT4A_VV : VDOT4AVV<0b101100, OPMVV, "vdot4a.vv">;`，其类声明 `(outs VR:$vd_wb), (ins VR:$vd, VR:$vs2, VR:$vs1, VMaskOp:$vm)` 且 `let Constraints = "$vd = $vd_wb";` ⇒ **`vd` 既是输出又是输入（累加器）**；同文件注明 "This version is still experimental as the 'Zvdot4a8i' extension hasn't been ratified yet." | `funct6=0b101100`、`OPMVV`；td **未写 K**，K=4 属【转述：由扩展名 `vdot4a`（4-way dot + accumulate）与同族 `vqdot` 的 "the four products" 推得】；向量逐元素结果 | **是**（`vd` 兼 `vd_wb`） | `experimental`（未 ratify；riscv-opcodes 归 `extensions/unratified/`） | `https://github.com/llvm/llvm-project/blob/8635f9042c2a42d15844b0bc4b2e8e27b06f3f54/llvm/lib/Target/RISCV/RISCVInstrInfoZvdot4a8i.td#L41`；编码旁证 `https://github.com/riscv/riscv-opcodes/blob/f24ac23ec9fa947011781a09cd6fd25a7c36dc45/extensions/unratified/rv_zvdot4a` |
| RISC-V `vqdot`（riscv-dot-product 仓） | 逐字："`vqdot` performs a partial dot product of two vectors of 8-bit signed integers, accumulating the partial sums into a vector of 32-bit signed integers."；"each 32-bit element of `vs1` and `vs2` is interpreted as a list of four 8-bit signed integer sub-elements"；"the four products are accumulated into the associated element of `vd`, wrapping on signed overflow."；funct6 表逐字："`| 101100 |V|X| \`vqdot\``"（第二组即 `OPMVV`）⇒ **`funct6=101100`（`0x2C`）/ `OPMVV`（funct3 `010`）** | **4** / 每个 32 位元素 1 个（一条指令出 VLEN/32 个结果） | **是**（Arguments 表 `vd` direction = `input`，`vector of 32-bit signed accumulator sources`） | `未批准提案`（`intro.adoc:4-5` 注明 "proposed … extensions"；且 `riscv-opcodes@f24ac23` 快照内 **0 命中**，实测） | `https://github.com/riscv/riscv-dot-product/blob/813cba14c9f0a731b4904925851a2820a6320b5b/insns/vqdot.adoc#L37`；funct6 表 `https://github.com/riscv/riscv-dot-product/blob/813cba14c9f0a731b4904925851a2820a6320b5b/vector-dot-product-inst-table.adoc#L25` |
| Arm `SMMLA`（A64） | ACLE 原文映射：`int32x4_t vmmlaq_s32(int32x4_t r, int8x16_t a, int8x16_t b)` → `r -> Vd.4S`、`a -> Vn.16B`、`b -> Vm.16B`、`SMMLA Vd.4S,Vn.16B,Vm.16B`、`Vd.4S -> result` ⇒ 16 字节源产生 **4 个 int32**，并把旧 `Vd.4S` 作为累加输入 | 每 32 位输出 8 对乘积【转述：2×8 × 8×2 矩阵乘，每输出 8 路点积；Arm DDI0602 指令页正文未取得，仅 ACLE 映射为原文】；一次出 **4 个** 结果 | **是**（`r -> Vd.4S`，`Vd.4S -> result`） | `厂商`（Arm 架构指令；ACLE 架构列 `A32/A64`，具体架构版本本档未取得） | `https://github.com/ARM-software/acle/blob/main/neon_intrinsics/advsimd.md#L5895`；指令页（JS 渲染，正文未取得）`https://developer.arm.com/documentation/ddi0602/latest/SIMD-FP-Instructions/SMMLA--Signed-8-bit-integer-matrix-multiply-accumulate-?lang=en` |
| Arm `SDOT`（NEON dot） | ACLE 原文映射：`int32x4_t vdotq_s32(int32x4_t r, int8x16_t a, int8x16_t b)` → `r -> Vd.4S`、`a -> Vn.16B`、`b -> Vm.16B`、`SDOT Vd.4S,Vn.16B,Vm.16B`、`Vd.4S -> result` | **4** / 每个 32 位元素 1 个【由 ACLE 类型 `int8x16_t`→`int32x4_t` 推得，故为 4 对/元素】 | **是**（`r -> Vd.4S`） | `厂商`（Arm 架构指令；ACLE 架构列 `A32/A64`） | `https://github.com/ARM-software/acle/blob/main/neon_intrinsics/advsimd.md#L5660`；指令页 `https://developer.arm.com/documentation/ddi0602/latest/SIMD-FP-Instructions/SDOT--Signed-integer-dot-product-?lang=en` |
| x86 `VPDPBUSD`（AVX-VNNI / AVX512_VNNI） | SDM 原文："Multiplies the individual unsigned bytes of the first source operand by the corresponding signed bytes of the second source operand, producing intermediate signed word results. The word results are then summed and accumulated in the destination dword element size operand."；指令表："Multiply groups of 4 pairs of signed bytes … summing those products and adding them to doubleword result." | **4** / 每个 dword 1 个 | **是**（"adding them to doubleword result"） | `厂商`（Intel；CPUID flag `AVX-VNNI` / `AVX512_VNNI`） | `https://cdrdv2-public.intel.com/825743/325462-sdm-vol-1-2abcd-3abcd-4.pdf#page=2413`（PDF 锚 `#page=2413` = 印刷页码 Vol. 2C 5-459；Order 325462-084US，本机 `pdftotext` 分页实测） |
| NVIDIA `dp4a`（PTX，**不是 x86**） | PTX 原文："Four-way byte dot product which is accumulated in 32-bit result."；"Operand `a` and `b` are 32-bit inputs which hold 4 byte inputs in packed form for dot product."；语义 `d = c; for (i = 0; i < 4; ++i) d += Va[i] * Vb[i];` | **4** / 每 32 位 1 个 | **是**（累加到第三操作数 `c`） | `厂商`（NVIDIA PTX ISA；PTX 5.0 起，需 `sm_61` 或更高） | `https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#integer-arithmetic-instructions-dp4a`（§9.7.1.24） |
| Intel AMX `TDPBSSD` | SDM 原文："Matrix multiply signed byte elements from tmm2 by signed byte elements from tmm3 and accumulate the dword elements in tmm1."；"Each dword in input tiles tmm2 and tmm3 is interpreted as four byte elements." | **4** / 每个 tile dword 1 个（tile 矩阵乘） | **是**（累加进 `tmm1`） | `厂商`（Intel；CPUID flag `AMX-INT8`） | `https://cdrdv2-public.intel.com/825743/325462-sdm-vol-1-2abcd-3abcd-4.pdf#page=1914`（PDF 锚 `#page=1914` = 印刷页码 Vol. 2B 4-701；同一 Order 325462-084US，本机 `pdftotext` 分页实测） |

### 5.2 命名与口径纠偏（三处最容易「转述失真」的地方）

1. **「x86 dp4a」不是 x86 指令**：`dp4a` 是 **NVIDIA PTX** 的指令名（PTX ISA §9.7.1.24，原文见上表）；x86 侧 4×int8 点积的对应物是 AVX-VNNI 的 `VPDPBUSD`。本表按事实**分两行**，不合并、不互称。
2. **`VPDPBUSD` 是 unsigned×signed，不是我方的 signed×signed**（SDM 原文 "unsigned bytes of the first source operand by the corresponding signed bytes of the second"）。x86 的 s8×s8 兄弟是 `VPDPBSSD`（AVX-VNNI-INT8），但本版 SDM（Order 325462-084US，2024-06）**全文无该串**（本次 `grep -c 'VPDPBSSD'` → `0`）⇒ 该指令正文【未取得】，本 README 不引、不写它的语义。
3. **Arm 的 K 与结果粒度不能混写**：`SMMLA` 每个 32 位输出的乘积数是 8、但一条指令出 4 个结果并读旧 `Vd`；`SDOT` 是 K=4。我方 `vdot.vv` 是 **K=8 + 一条指令只出 1 个结果 + 不读旧 vd**；与 `SMMLA` 的差异在「单结果 / 不累加」，**不在 K 值本身** —— 因此**不得**把差异写成「K=8 世界首创」「首个点积指令」这类绝对化表述（`SMMLA` 已是 8 路点积，见上表）。

### 5.3 与 `design/SPEC.md` §2 编码三元组的一致性（逐字段）

上表出现的 `funct6=0b101100`（`0x2C`）**只属于 `vqdot` / `vdot4a`**，不是我方取值；我方编码三元组与本 README 及 SPEC §2.1 逐字段相同：

| 字段 | 本 README 写值 | `design/SPEC.md` §2.1 |
|---|---|---|
| opcode | `1010111`（`0x57`, OP-V） | `design/SPEC.md:75` 同值 |
| funct3 | `010`（OPMVV） | `design/SPEC.md:76` 同值 |
| funct6 | `001110`（`0x0E`） | `design/SPEC.md:77` 同值 |
| vm | `1`（无掩码；掩码版非法） | `design/SPEC.md:78` 同值 |
| 机器码示例 | `vdot.vv v3, v2, v1` = `0x3A20A1D7` | `design/SPEC.md:79` 同值 |

§5 与 §6 **不引入任何新的编码断言**：`0x0C`（`vclmul.vv`）、`0x28`/`0x2A`/`0x2C`（`rv_zvdot4a`）只在「其他指令已占用的编码」语境出现，与我方 `0x0E` 无重叠。

> **一处需读清的细节（不构成与 SPEC 的矛盾）**：`101100/010`（`0x2C`）被**两个未批准提案同时占用** —— `riscv-dot-product` 的 `vqdot`（`vector-dot-product-inst-table.adoc:25`）与 Zvdot4a 的 `vdot4a.vv`（`rv_zvdot4a:1`）。`design/SPEC.md` §2.3/§2.4 只写了 Zvdot4a 一侧（"`101100/010` 是上游未批准提案 Zvdot4a 的 `vdot4a.vv` 官方分配"），本表补上 `vqdot` 一侧；两处结论同向且更强：**`0x2C` 不是空闲编码，主线不得占用**。
>
> **本文件不改 SPEC 正文**：本节内容只写入本 README；`design/SPEC.md` 与 `stage3/3.3/report.md` 未改动。**打包记录（2026-11-07）**：2026-11-06 曾实测 `a8b468f3…b86e86` / `8997ad33…e699bf` 两件不同（`design/SPEC.md` 追加 §3.4「外部互证」，`+120` 行）；SPEC 定稿后重新打包时 `sha256sum` 两件同值 `9289b501…b4d765`（388 行）。此后两处文件各自经过文字修订，已不再逐字节相同，复核方法见 §1。§2.1 编码三元组表的内容逐值未变，可直接对照 `design/SPEC.md` §2.1。

## 6. 我方选型理由

### 6.1 K=8 单结果：来自官方伪代码，不是自选

- K=8 与「单结果 + 其余位清零」逐字来自赛题官方伪代码（`for i in range(8)`、`vd[0]=result`、`vd[1..VLEN-1]=0`，`docx/02-赛题与评分细则.md:24-33`）。伪代码未定义 `vd[0]` 位宽，本项目裁决为 32 位容器（`vd[31:0]=sext32(S)`、`vd[127:32]=0`），见 `design/SPEC.md` §3.1。
- 与 §5 外部指令的真实差异是 **「K=8 + 单结果 + 不累加」**：外部各家要么 K=4（`vqdot`/`SDOT`/`VPDPBUSD`/`dp4a`/`TDPBSSD`），要么 K=8 但一次出 4 个结果并累加（`SMMLA`）。
- 由 K=8 导出的 19 位内部位宽是**算术下界**（`8×(−128)×(−128)=131072 > 2^17−1=131071`），**无外部规范依据**；外部一律 32 位累加器，故此处只主张「相容」，不主张「有规范支撑」。

### 6.2 不读旧 `vd`：与 Zvdot4a 的「`vd` 兼累加」是两种语义

- LLVM `RISCVInstrInfoZvdot4a8i.td:20-27,41` 把 `vd` 同时放进 `outs` 与 `ins`，并固定 `Constraints = "$vd = $vd_wb"` ⇒ **`vd` 是读-改-写累加器**；`vqdot.adoc:33` 的 `vd` 在 Arguments 表 direction = `input`（`accumulator sources`）⇒ 同为累加。
- 本项目 `vdRen=F`、不进 `isMacc`、不登记 `vmaInsts`（`design/SPEC.md:32,49,188`），旧 `vd` **不是语义输入**；高 96 位清零由数据通路 `Cat(96'b0, …)` 保证，不依赖 Mgu。
- 这是**任务语义要求**（官方伪代码里累加器 `result` 从 0 起算，`vd` 初值不参与），不是性能取舍；它换来更短的旧值依赖链，代价是写回必须整寄存器全写（见 `design/SPEC.md` §1.2 第 3 条）。

### 6.3 编码 `0x0E` 全库无占用（引证据文件，不引二手结论）

- 结论级证据：`encoding-gate-zvbc-2026-10-31.md:5`（原 `0x0C` 被正式 Zvbc 的 `vclmul.vv` 占用 ⇒ 改 `001110`/`0x0E`，机器码 `0x3A20A1D7`）；占用表在 `:41-53`，其中 `:43`「`0x0E (001110)` → **空闲**」、`:51`「`0x2C (101100)` → 占用：`rv_zvdot4a` `vdot4a.vv`（unratified）」。
- 本次**独立复扫**（不复用该文件的转述，直接扫 riscv-opcodes `f24ac23` 快照的 `extensions/**`）：`funct3=010` 且 `opcode=0x57` 的指令行共 **82** 条，其中 `funct6=0x0E` **0 条**；`funct6=0x2C` 只命中 1 条 `rv_zvdot4a:vdot4a.vv`（命令与输出见 §7 第 2 条）。
- **口径边界**：`0x0E` 空闲只说明「截至该快照（commit `f24ac23`，`fetched=2026-11-01`）无官方分配」；上游若改分配须以同脚本重扫（`design/SPEC.md` §2.7），**不写成「永远空闲」**。
- **退出码口径**：`design/verify/encoding-gate.py` 在本工作区复跑返回 `EXIT=1`，命中的是本仓自身已落地的三处表项（`[SCALA-BITPAT]` / `[NEMU-DECODE-H]` / `[VECDECODER]`），不是外部撞车 —— 见本 README §3；该退出码**不得**记作「检查通过」，也**不得**记作「编码冲突」。

## 7. 取证命令与输出（按当时工作区原样记录）

```bash
# 1) 编码三元组 → 机器码复算（funct6=001110 / vm=1 / funct3=010 / opcode=1010111）
python3 -c 'f6=0b001110;vm=1;vs2=2;vs1=1;f3=0b010;vd=3;op=0b1010111;w=(f6<<26)|(vm<<25)|(vs2<<20)|(vs1<<15)|(f3<<12)|(vd<<7)|op;print(hex(w),(w>>26)&0x3f,(w>>25)&1,(w>>12)&7,w&0x7f)'
# 实测输出：0x3a20a1d7 14 1 2 87   （funct6=14=0x0E、vm=1、funct3=2、opcode=0x57）

# 2) funct3=010 / opcode=0x57 全库复扫（按字段解析，不做字符串近似匹配）
python3 - <<'EOF'
import os, re, glob
from collections import Counter
root = os.path.join(os.environ['OPCODES_SNAPSHOT'], 'extensions')   # 快照目录未随本目录交付（见 §4）
def val(line, field):
    m = re.search(r'\b' + re.escape(field) + r'=(\S+)', line)
    if not m: return None
    try: return int(m.group(1), 0)
    except ValueError: return None
hits = []
for p in glob.glob(root + '/**', recursive=True):
    if not os.path.isfile(p): continue
    for ln in open(p, errors='replace'):
        if ln.startswith('#') or not ln.strip(): continue
        op6, op7, op62 = val(ln, '6..0'), val(ln, '7..0'), val(ln, '6..2')
        if not (op6 == 0x57 or op7 == 0x57 or op62 == 0x15): continue
        if val(ln, '14..12') != 0x2: continue
        f6a, f6b = val(ln, '31..26'), val(ln, '31..25')
        f6 = f6a if f6a is not None else (f6b >> 1 if f6b is not None else None)
        hits.append((f6, os.path.basename(p), ln.split()[0] if ln.split() else ''))
c = Counter(h[0] for h in hits)
print('funct3=010 & opcode=0x57 total lines:', len(hits))
print('0x0E(14) occupancy:', c.get(0x0E, 0))
print('0x2C(44) entries:', [h[1] + ':' + h[2] for h in hits if h[0] == 0x2C])
EOF
# 实测输出：
#   funct3=010 & opcode=0x57 total lines: 82
#   0x0E(14) occupancy: 0
#   0x2C(44) entries: ['rv_zvdot4a:vdot4a.vv']

# 3) 表内每行 ≥1 个官方 URL（只统计 §5.1 数据行，跳过表头与分隔线）
python3 - <<'EOF'
lines = open('stage2/2.1-design/README.md', encoding='utf-8').read().split('\n')
start = lines.index('### 5.1 对比表')
rows, in_table = [], False
for ln in lines[start + 1:]:
    if ln.startswith('### '):
        break
    if not ln.startswith('|'):
        continue
    if set(ln.replace('|', '').replace('-', '').strip()) <= set():
        continue                                   # 分隔线
    rows.append(ln)
data = rows[1:]                                    # 去掉表头
bad = [r for r in data if 'http' not in r]
print('§5.1 数据行:', len(data), '缺 URL:', len(bad))
EOF
# 实测输出：§5.1 数据行: 8 缺 URL: 0
```

### 7.1 未取得 / 未验证（如实记，不得补写）

- **Arm DDI0602 指令页正文【未取得】**：JS 渲染，本次取回 8,434 B 空壳、关键词计数 0；Arm 两行的 K 与「读旧 Vd」结论来自 ACLE 映射表原文 + 【转述】标注，**不冒充 Arm 伪代码**。
- **`VPDPBSSD`（x86 s8×s8）正文【未取得】**：本版 SDM 无该串，未换版本核对。
- **`vqdot` 的 Operation 伪代码不可引**：`insns/vqdot.adoc:58-66` 自身有笔误（`let res : bits (SEW) = …` 算完未用、`set_velem(vd, i, product)` 的 `product` 未定义）⇒ 只引 Description 段。
- **URL 可达性**：`rv.cie.org.cn`、`docs.nvidia.com`、`developer.arm.com`、`cdrdv2-public.intel.com` 本次 `curl` 均得 200；**`github.com` 网页版在本机超时（rc=28）**，故未直接打开 `blob/<commit>` 页面，其内容以**同 commit 裸文件**为准（逐件 sha256 记录未随本目录交付，见 §4）。
