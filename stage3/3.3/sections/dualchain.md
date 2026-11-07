# 4.8 双链实验：三个口径分列、old_vd 机制归因与同口径对照（清单外独立测量）

> **小节归属**：本文件并入 `stage3/3.3/report.md` **§4.8**；编号即按 **§4.8.x** 书写，并入时按原样插入、编号不变。
>
> 定稿：2026-11-07 ｜ 作业：`127142843`（kshcnormal，`COMPLETED 00:16:46`，`ExitCode=0:0`，`status=通过`、12/12 criteria 达标）｜
> 用例：`design/verify/cases/vdot_dualchain.c`（**不进** `manifest.tsv`；主清单 `sha256 a90d1071…`、30 数据行未变）｜
> 构建：`design/verify/cases/build_dualchain.sh`（两镜像，`-DDC_G0=1` 为 G0 反例；本次 `source_sha256=d23b049b…`、xpack 13.2.0）｜ 运行：`core-package/scripts/96-run-dualchain.sh`
> emu：`md5=fd65ca4a…`；版本 `xiangshan=a4eeaab / yunsuan=9559211 / nemu=a683e0b`（作业日志头）。
> 远端证据：`~/core/results/difftest/dualchain/96-dualchain-20261107T124540.{log,json}`、
> `cases/vdot_dualchain.20261107T124540.log`、`cases/vdot_dualchain_g0.20261107T124540.log`；本地副本 `results/difftest/dualchain/`。
>
> **标记约定**：`【我方 emu 实测】`= 本作业日志读数；`【对方文档】`= 对手文档数字、本仓未复跑其镜像；`【推算】`/`【未运行】` 按字面。
> **口径约定**：本节把「吞吐」「依赖间隔」「T5-L」**三分列**，三者**不相除、不互引**；同口径比值只在「吞吐」列内部使用（两条链同窗相比）。
> 芯锐/Gloria 的「7 cyc」见其公开材料，本仓未复跑，相关处逐条标注。
> 本节**不写**「优于同题」「全场唯一」；芯锐/Gloria 的 7 cyc 均按【对方文档】处理。

---

## 4.8.1 结论先行：三个口径分列

> **口径约定**：A 吞吐、B 依赖间隔、C T5-L 是**三种不同窗口/不同单位**的量。
> **禁止**把 A 的数字除以 B 或 C 的数字得到「倍数」，也禁止用 B/C 的差去证明 A。下表每行只在自己的口径内读数。

| 口径 | 窗口与单位 | 本次实测【我方 emu 实测】 | 能说明什么 | 不能说明什么 |
|---|---|---|---|---|
| **A 吞吐** | 无依赖流（源常量、vd 不被读），差分商 q4/q8，**cyc/条** | 无依赖 `vdot`：M8 **0.890/1.011**、M3 **1.125/0.968**（q4/q8）；读旧 vd 的 `vmacc`：M5 **4.875/7.531** | 同测量形状下，无依赖 `vdot` ≈**1.0 cyc/条**，读旧 vd 的 `vmacc` ≈**7.5 cyc/条**（q8）；同窗比值：M5/M8 q8 **7.45**、q4 **5.48**（M5/M3 q8 7.78、q4 4.33）。机制见 §4.8.3：`vd_old=INT.X` ⇒ `vdRen=F`、旧 vd 不进归约 | 这是**每指令吞吐差，不是单条延迟、不是加速比**；不能与 B 的 5.7–7.5 或 C 的 4 相除/相减；两条链**指令不同**（vdot vs vmacc），不称「单一变量」 |
| **B 依赖间隔** | RAW 链，`rdcycle` 括窗差分中位数 q4/q8，**cyc/步** | M1 **5.687/7.031**、M2 **6.437/6.984**、M4 **4.812/7.531**、M5 **4.875/7.531**、M6 **2.000/4.375** | 依赖链的每步商落在 **4.8–7.5**；五条依赖链全部 `q8>q4`，差分模型 `q(R)=L+O/R` 反解 `O<0`（物理不可能）⇒ 只能读作**上界型参考** | **不能读作 `L`**（依赖间隔）；不能与 A 的吞吐、C 的 4 相除；不能据此否定 C 的 4 |
| **C T5-L** | `perf_vdot.bin` 的逐条 `rdcycle` 括窗（8 轮×2000 次，中位数），**cyc/步** | `L_vdot=4`、`L_vmacc=4`、`L_vadd=3`（既有口径）；同镜像全环 `L_vdot_loop=6.98`；三链「全环−括窗」= **2.9495/2.9730/2.9785** | 4 是**该镜像、该括窗口径**下的延迟读数；与全环 6.98 相差恒定的 ~2.97 拍（三条不同指令链互证） | 不是本次双链差分复现值（B 未复现 4，也未推翻）；不是跨实现/跨镜像稳定的常量；**不能与 A 相除** |

**Headline（口径 A，【我方 emu 实测】）**：无依赖 `vdot` **≈1.0 cyc/条**（本次 M8 0.890/1.011、M3 1.125/0.968，q4/q8；上一次 q8 = **1.03**），
而源为常量、**只读旧 vd** 的 `vmacc`（M5）**4.875/7.531 cyc/条** ⇒ 同窗**约 5.5 倍（q4）/ 约 7.5 倍（q8）**的每指令吞吐差。
机制归因：`vdot` 的 `vd_old=INT.X`，译码 `vdRen=F`、不申请旧 vd 读口、旧 vd 不进归约 ⇒ 背靠背 `vdot` 不形成写回环（§4.8.3）。
上一次作业 `127043684`（emu `md5=529c9abc…`）给 M8 **1.007/1.007**、M5 **5.625/7.531**，同一结论；两批 M5/M8 同窗比稳定在 **≈5.5（q4）/≈7.5（q8）**。
**该倍数只在口径 A 内部成立，不是加速比，不得与 B/C 的数字相除或互引。**

---

## 4.8.2 逐链实测（作业 `127142843`，VL=8 / SEW=8 / LMUL=1 / 同一组 `buf_a`/`buf_b`）

口径：**差分法中位数**。每轮测 `C(n)` 与 `C(2n)`：`n=4` 个 rep、每 rep 连发 R 条同型链指令
（R=4 与 R=8 各测一次），`rdcycle` 只在循环外括窗；逐轮商 `q(R)=(C(2n)−C(n))/(n·R)` 取 5 轮中位数（毫拍精度）。
M2 一步两条、M8 一步八条，均按「条」归一。

| 链 | 指令序列（汇编打印顺序） | 形状 | `q(R=4)` cyc/条 | `q(R=8)` cyc/条 | 判读 |
|---|---|---|---|---|---|
| **M1** | `vdot.vv v10,v10,v1` | vd==vs2 自别名，真 RAW | **5.687** | **7.031** | 有依赖 |
| **M2** | `vdot.vv v11,v10,v1` / `vdot.vv v10,v11,v1` 交替 | 跨寄存器真 RAW | **6.437** | **6.984** | 有依赖 |
| **M3** | `vdot.vv v3,v1,v2` ×N | **无任何数据依赖**（源常量、vd 固定不被读） | **1.125** | **0.968** | **≈1，无串行化** |
| **M4** | `vmacc.vv v10,v1,v10` | 对照：old_vd 是语义输入且 vd==vs2 | **4.812** | **7.531** | 有依赖 |
| **M5** | `vmacc.vv v10,v1,v2` | 对照：**串行源只有 old_vd**（vs2 常量） | **4.875** | **7.531** | **有依赖** |
| **M6** | `vadd.vv v10,v10,v1` | 非 vimac 的 ALU 参照链 | **2.000** | **4.375** | 有依赖（更短） |
| **M7** | `vadd.vv v3,v1,v2` | 无依赖地板（源常量、vd 固定） | **1.937** | **1.031** | ≈1，地板 |
| **M8** | `vdot.vv v8..v15` 轮流写、源常量 | 无依赖且**不同 vd**（释放同号 WAW 压力） | **0.890** | **1.011** | **≈1** |

**上一次复现（作业 `127043684`，emu `md5=529c9abc…`，同源版本）**：M1 `5.687/7.531`、M2 `6.437/6.718`、M3 `1.000/1.031`、
M4 `5.562/7.218`、M5 `5.625/7.531`、M6 `4.125/4.343`、M7 `1.500/1.281`、M8 `1.007/1.007`。
两批在 M1/M2/M8 的 q4/q8 与 M5 的 q8 上一致到 ~0.5 拍内；M5 的 q4 两批为 4.875/5.625（差 0.75），M4/M6/M7 的批次间抖动更明显（emu 同一源码但重建、q 取 5 轮中位数）。
**结论（有依赖/无依赖、vdot/vmacc 的分离）两批一致；本文件主表用本次（与 M9/M10/M11 同一 emu、同一作业），上一次作复现记录。**

**交叉核对（仓内既有 `perf_*.bin`，2026-11-03 镜像；与本次不是同一 emu 构建）**
`perf_vdot.c` 自带的整段墙钟口径 `L_vdot_loop`：`13957 cycles / 2000 ops = 6.98 cyc/步`（`perf_vdot.20261103T075552.log:9`）；
`L_vmacc_loop = 13946/2000 = 6.97`（`perf_vmacc...:8`）、`L_vadd_loop = 11899/2000 = 5.95`（`perf_vadd...:8`）。
三条链的整段口径与本节差分口径**逐条同序**（vdot≈vmacc>vadd），说明本项测量与仓内既有口径不矛盾（跨镜像，仅作序关系核对）。

**本项差分法自身的缺陷（必须与上表并读）**：模型 `q(R)=L+O/R` 要求 `q4>q8`（O>0）。实测**五条依赖链全部 `q8>q4`**
（M1 `+1.344`、M4 `+2.719`、M5 `+2.656`、M2 `+0.547`、M6 `+2.375`），反解出的 `O` 为负，**物理上不可能**；
三条无依赖链（M3/M7/M8）的 `q4≈q8`（`−0.157/−0.906/+0.121`，均在 ~1 拍量级）。
⇒ 差分法只在「无依赖」时自洽，对依赖链**系统性高估**（队列深度效应随批大小放大）。
**所以本表的 `q` 只能读作「上界型参考值」，不能读作 `L`；本项不拿它去反推 `L` 或做跨口径运算——本项只在口径 A 的 M5/M8 使用同口径比值（q4 与 q8 各自同窗相比，已在 §4.8.1 标明）。**

**口径注解（表内 `q4/q8` 与作业 JSON 的 `L=2q8−q4`：两套数并存、用途分列）**：

- 表内 `q(R=4)`/`q(R=8)` 是**差分商原值**：每轮 `(C(2n)−C(n))/(n·R·I)` 取 5 轮中位数（`rdcycle` 只在循环外括窗的读数），是每指令拍数的原始观测量。
- 作业 JSON（`96-dualchain-20261107T124540.json` 的 `metrics[]`）里的 `M1=8/M2=8/M3=1/M4=10/M5=10/M6=7/M7=0/M8=1` 是**差分模型的派生量** `L=round(2q8−q4)`（毫拍版 `M1_milli=8375` 即 `2×7031−5687`），打印在 `design/verify/cases/vdot_dualchain.c:465/:468/:472-473`。
- 两者**不是两套独立测量**：`L` 由同一对 `q4/q8` 线性组合而来（可算但**不可当作独立证据**），且 `L=2q8−q4` 仅在 `q(R)=L+O/R` 成立时有物理意义——依赖链 `q8>q4`（上段）已使该前提失效，故 JSON 的 `L` 值只作产物留档，**正文一律引用 `q4/q8` 原值，不把 `L` 读作依赖间隔，也不做 `q ↔ L` 的换算引用**。
- 同窗比较示例（口径 A 内部）：`q4` 口径 M5/M8 = 4.875/0.890 ≈ **5.5 倍**，`q8` 口径 = 7.531/1.011 ≈ **7.5 倍**；旧稿的「7.5×」若指 `q8(M5)/q4(M3)` 则是跨窗相除，已废止。C1 一律用同窗值。

---

## 4.8.3 机制归因（file:line）

**链路**：`vdot` 的 `vd_old` 字段取 `INT.X` ⇒ 译码不把旧 vd 当源 ⇒ 数据通路也不把旧 vd 并入归约 ⇒ 背靠背 `vdot`
在"源无依赖"时不形成写回环；而 `vmacc` 的 `vd_old` 取 `INT.S`、`isMacc(opcode)=true`，旧 vd 是**语义输入**，同形状链条即被串行化。

1. **`vd_old = INT.X`（类型编码）**：`repos/XiangShan/yunsuan/src/main/scala/yunsuan/package.scala:400`
   `def vdot = LiteralCat(0.U(2.W), INT.S, INT.S, INT.X, FMT.VVV, VimacOpcode.vdot)`——布局注释在 `:381`/`:383`
   （`pad | vs2 sign | vs1 sign | vd_old sign | format | opcode`）；同文件 `:391` 的 `vmacc` 该位是 `INT.S`。
2. **译码 `vdRen=F`（不申请旧 vd 读口）**：`repos/XiangShan/src/main/scala/xiangshan/backend/decode/VecDecoder.scala:385`
   `VDOT_VV -> OPMVV(F, FuType.vimac, VimacType.vdot, F, T, F, UopSplitType.VEC_VVV)`；`OPMVV` 的
   `private def src3: BitPat = if (vdRen) SrcType.vp else SrcType.X` 在 `:91`（`:108` 属另一个 case class）。
   `vdRen=F` ⇒ `src3=X` ⇒ 该 uop 不向寄存器堆要第三个操作数。
3. **`isMacc` 不含 `vdot`**：`repos/XiangShan/yunsuan/src/main/scala/yunsuan/encoding/Opcode/VimacOpcode.scala:18`
   `def isMacc(opcode) = Seq(vmacc, vnmsac, vmadd, vnmsub).map(_ === opcode).reduce(_ || _)`（`:14` 是 `def vdot = "b111"`，不在集合内）。
4. **旧 vd 不进入归约**：`repos/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VIMac64b.scala:125`
   `partProd(33) := Mux(io.isMacc, Mux(io.widen, Cat(oldVd, oldVd), Mux(io.isSub, ~oldVdReorg, oldVdReorg)), 0.U)`
   —— `isMacc=false` 时**恒 0**，旧 vd 只在被选中的那一支里出现。
5. **归约的寄存使能来自 `fireS1` 端口线**：`VIMac64b.scala:37` `val fireS1 = Output(Bool())`、`:219` `io.fireS1 := fireS1`
   （`:41` `val fireS1 = GatedValidRegNext(fire)`）；wrapper 侧只连 `vimacs(0)`：
   `repos/XiangShan/src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala:129` `vdotReduce.io.sum_wo := vimacs(0).io.sum_wo`、
   `:130` `vdotReduce.io.fireS1 := vimacs(0).io.fireS1`；输出旁路 Mgu 取 `outCtrl`：
   `VIMacU.scala:159` `outIsVdot = outCtrl.fuOpType === VimacType.vdot`、`:160` `res.data := Mux(outIsVdot, vdotReduce.io.vd, mgu.io.out.vd)`。

**实验侧的 A/B 对照（结论不是"读代码推的"）**：

- **M3 vs M5**：两条链**测量形状相同**（源为常量、vd 固定、无跨指令 RAW），但**指令不同**（`vdot` vs `vmacc`）、内部通路也不同 ⇒ 不能称「单一变量」。
  实测每指令吞吐 `1.125/0.968` vs `4.875/7.531` cyc/条（q4/q8）⇒ 读旧 vd 的链每指令代价高约 **5.5 倍（q4 同窗，M5/M8）/ 7.5 倍（q8 同窗，M5/M8）**（M5/M3 分别为 4.3/7.8 倍；q4 的 M3 本次偏高），与第 1–4 条的 RTL 机制（`vd_old=INT.X`、`isMacc` 不含 vdot、旧 vd 不进归约）**方向一致**；
  因果强度只到「一致」，不写成单变量证明。
- **M3 vs M8**：都无依赖，差别只在"写同一个 vd"(M3) 与"轮转 8 个 vd"(M8)。实测 `0.968–1.125` vs `0.890–1.011` ⇒ 同号 vd 的 WAW
  也被消化（全写 + 不读旧值），不是"靠换寄存器名躲开"。
- **M1 vs M2**：`5.687/7.031` vs `6.437/6.984` ⇒ 自别名与跨寄存器两种真 RAW 的间隔同量级（差 <1.5 cyc），不是自别名假象。
- **M6**（`vadd` 自别名）本次 `2.000/4.375`（q4/q8），上一次 `4.125/4.343`——**批次间抖动明显**（q4 差 >2 拍），
  故只保留定性结论「vadd 链短于 vimac 链（乘 + 压缩树 + CPA 的流水级），不是 vdot 特有」，**不引用精确差值**。

---

## 4.8.4 关于「4 cyc」：本项能说什么、不能说什么

**(a) 本项未能复现 4。** 差分口径给 M1（`vdot.vv v10,v10,v1`，与 `perf_vdot.c` 的 `L_vdot` 同一条链）`5.687/7.031` cyc/步。

**(b) 但本项也没有推翻 4。** 差分模型在依赖链上自相矛盾（`q8>q4`，反解 `O<0`，§4.8.2 末段），
所以 `5.7–7.5` 只能当"上界型参考"，**不能作为 `L` 的反证**。诚实记法是「另一口径未复现 4」，不是「4 被证伪」。

**(c) 仓内的两个既有口径其实是互相印证的。** 把 `perf_*.c` 的整段口径减去括窗口径：

| 链 | `loop/N` | 括窗 `L` | 差 |
|---|---|---|---|
| vadd | 5.9495 | 3 | **2.9495** |
| vmacc | 6.9730 | 4 | **2.9730** |
| vdot | 6.9785 | 4 | **2.9785** |

三条**不同指令**的链给出同一个差值 **≈2.97 拍**（极差 0.03）。一个自然的解释是：`loop-total = 括窗延迟 + 每轮固定循环开销`，
而每轮循环开销（`addi`+`bne`+取指）与链类型无关。**因此 `L_vdot=4` 与 `L_vdot_loop=6.98` 不是矛盾，更像是同一事实的两种切法：
前者是"延迟"、后者是"延迟 + 环路开销"。** 这**不构成**对 4 的独立证明（差值恒定是拟合结果，不是预注册判据），但足以说明 §3.1 的 4 在本镜像内**不自相矛盾**。
本次 M9 的同口径 gross 斜率 **6.984** 与 `4 + 2.98`（C 的括窗 4 + 本条差值）在数值上吻合——**仅作「同一实现的两种切法」的解释，不把 C 与 M9 当同一量、不据此做跨口径运算**（§4.8.5）。

**(d) 逐条括窗的敏感性观测只能作方法学线索（证据来自被取代镜像）。** 本项 2026-11-06 交付源码已删逐条括窗（brk）代码；下列 7 行只存在于**被取代镜像**的日志
`results/difftest/dualchain/cases-vdot_dualchain.20261106T155006.log`（`expected_sha256=4fed31e3…` ≠ 当时交付头 `c1beda4b…`，`verdict=HAS_FAIL func_fails=4`），**仅作方法学记录**：

```
DUALCHAIN M1 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
DUALCHAIN M3 brk samples=112 len=128 median=2 mean=2 min=2 max=6 over=0
DUALCHAIN M4 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
DUALCHAIN M5 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
DUALCHAIN M6 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
DUALCHAIN M7 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
DUALCHAIN M8 brk samples=112 len=128 median=2 mean=2 min=2 max=5 over=0
```

**含完全无依赖的 M3/M7/M8 在内，七条链全部返回 median=2** ⇒ 该逐条括窗口径**疑似**对**二进制布局/调度**敏感
（`mcycle`/`cycle` 不在香山的有序读 CSR 白名单：`repos/XiangShan/src/main/scala/xiangshan/backend/fu/NewCSR/CSROoORead.scala:10-55`
的两个列表均不含它们，两层 `rdcycle` 可与中间的向量指令重排——同 `perf_kernel_cmp.c` 头注的判废结论）。
**结论（仅作方法学线索）**：这只是**方法学线索**，不是本次交付镜像上的实测结论；4 在 `perf_vdot.bin` 里自洽，但不是"换实现/换布局都成立"的常量；对外引用必须带"来自该镜像的括窗口径"这一限定。

---

## 4.8.5 同口径对照：Gloria/GEMwhu 的依赖链口径（M9/M10/M11）

**口径原文**（对手公开材料 `相关证明材料/performance/README.md:35`，【对方文档】）：

> 「72个程序各三次，共216次；循环次数为0、64、256、1024。输入预先存于寄存器，结果描述重复计算，不包含每次重新装载输入的应用成本。**依赖链参照为20.991935对7.008065周期/点积，周期比2.995。**」

**归属更正（按证据就近修正）**：该 `performance/README.md:35` 路径属于 **Gloria-Deng/GEMwhu**
（其公开仓库的 `相关证明材料/performance/` 目录），**不是香山芯锐**；芯锐的「7 cyc/次」在
`docs/正文/09_延迟测量与软件优化分析.md:95-97`，是**另一套口径**（N=1/8/32 的增量斜率、空窗口 74 拍、RVV-m1 55 / mf2 47）。
**芯锐的 7 cyc 与本项 M9 口径不可比**（对方【对方文档】；其程序 `apps/vdot-chain-v1/cases.S` 虽公开，但本次未复跑，
且 N 集/拟合方式与 M9 的 N=0/64/256/1024 四点 OLS 不同）。本节的 M9/M10/M11 复现的是 **Gloria 的
「依赖链 w1、N=0/64/256/1024、每点 3 次重复、4 点 OLS 斜率（含循环开销）」** 口径；芯锐的 7 cyc 不与 M9 直接比较。

**可复现性判定**：可复现。对方仓库公开了方法链：`相关证明材料/experiments/throughput/study.py`（`line_fit`/`summarize`：
同 N 取 3 次中位数、4 点 OLS、`gross=slope/width`、`adjusted=(slope−control)/width`）与
`verified/generated_source/dependent_w1_{vdot,rvv,control}_n{0,64,256,1024}.S`（依赖链 w1：vd 同时是源 v30 + 目的；
其 vdot 编码 `funct6=0b101100`、vs1=30/vs2=31/vd=30）。本项用**同链形状 + 同 N 集 + 同拟合**在**本项编码（0x0E）**上复现。
**M9/M10/M11 是独立的第四口径（对方依赖链，含循环开销），不与 §4.8.1 的 A/B/C 相除或互引。**

- **M9**：`vdot.vv v30, v31, v30`（vd=30、vs1=30、vs2=31；v30 既源又目的）；
- **M10**：标准 RVV 五指令等价链（`vwmul.vv v16,v31,v30` / `vsetivli e16` / `vmv.v.i v30,0` / `vwredsum.vs v30,v16,v30` / `vsetivli e8`）——对方 `dependent_w1_rvv` 的同构基线，本项独立重写；
- **M11**：空循环 control（对方 `control` 臂，用于 `adjusted` 估计）。

**实测（作业 `127142843`，【我方 emu 实测】；对方列为【对方文档】）**：

| 臂 | 本项 gross（cyc/点积） | 本项 adjusted（减 M11） | 对方 gross【对方文档】 | 对方 adjusted【对方文档】 | 差（gross / adjusted） |
|---|---:|---:|---:|---:|---:|
| **M9 vdot 依赖链** | **6.984** | **6.006** | **7.008065** | **5.979839** | −0.024 / +0.026 |
| **M10 标准 RVV 五指令链** | **20.994** | **20.016** | **20.991935** | **19.963710** | +0.002 / +0.052 |
| **M11 空循环 control** | **0.978** | — | 1.028226 | — | −0.050 |

原始读数（`DUALCHAIN_G44` 行，3 次重复的中位数）：M9 `N=0/64/256/1024 → 36/514/1824/7200` 拍；M10 `36/1382/5407/21534` 拍；
M11 `36/183/305/1073` 拍。斜率由 4 点 OLS 计算，R²（独立恒等式与残差式互证）= M9 **0.99998**、M10 **0.9999999**、M11 **0.99387**。

**结论（同口径量级对照，不做优势论证）**：

1. **M10 与对方文档的 RVV 基线差 0.002 cyc/点积**（20.994 vs 20.991935）⇒ 该口径在本 emu 上**复现成功**，M9 与对方 vdot 的比较有共同标尺。
2. **M9 与对方文档的 vdot 依赖链差 −0.024 cyc/点积（−0.3%）**（6.984 vs 7.008065）；adjusted 差 +0.026（+0.4%）。
   即：**同口径下两者是同一量级（≈7 cyc/点积），本项不主张任何优势**。上一稿「我方 4 vs 对方 7」是**跨口径**
   （C 的括窗 `L_vdot=4` 对 A/对方含循环的 gross 7），已按三分列废止；M9 的 6.984 与 `4 + 2.98` 环路开销数值吻合，
   **仅作口径切法的解释，不把 C 与 M9 当同一量、不做跨口径运算**（§4.8.4c）。
3. **残余口径差（如实）**：对方 vdot 编码位置 `funct6=0b101100` vs 本项 `0x0E`；对方 emu 构建未知 vs 本项 `md5=fd65ca4a…`
   （`a4eeaab/9559211/a683e0b`）；对方 cycle 网格 8 拍、每次重复单独启动 emu、计时窗口含循环后 store/fence/比较，
   本项 `rdcycle` 精确到 1 拍、同进程 3 重复、窗口只括循环。M10 的 0.002 差说明这些差异对斜率的影响 <0.01 cyc/点积。
4. **硬性约束**：对方 7.008065/20.991935 是【对方文档】、本仓未复跑其镜像；本节只做**同口径量级对照**，不写「优于同题」「全场唯一」，
   不把 M9/M10 与对方数字相除当加速比（表中比值仅用于核对复现，不是性能主张）。

---

## 4.8.6 诚实边界

1. **本项没有独立复现「4 cyc」**，也没有推翻它（§4.8.4）。任何"vdot 依赖间隔 = 4 cyc，已由双链实验独立验证"的表述**不成立**；
   正确的表述是"`perf_vdot.bin` 的逐条括窗口径给 4，且与同镜像全环口径 6.98 相差恒定的 ~2.97 拍环路开销（三条链互证）"。
2. **本项不主张优于任何对手**。竞品 7.008/20.992 是其文档、未复跑；§4.8.5 的同口径对照只说明「量级相同、口径已对齐」，不做减法。
3. **机制归因（口径 A）的论证以 RTL 为准，不靠单变量 A/B**：M3/M5 是同一程序、同一 VL、同一操作数、同一测量法下的两条链，但**指令不同**（`vdot` vs `vmacc`）、通路不同，因此 1.125/0.968 vs 4.875/7.531 cyc/条（q4/q8）只描述这两条链的**每指令吞吐差**（同窗约 5.5/7.5 倍，M5/M8），**不写成"单一变量"**；机制成立性以 §4.8.3 的 file:line（`vd_old=INT.X`、`vdRen=F`、`isMacc` 不含 vdot、旧 vd 不进归约）为准，测量仅作方向一致的佐证。
4. **未测**：真实硅后时序（emu 是 RTL 仿真，`rdcycle` 是模型周期）；带负载下的依赖间隔；`LMUL>1`/`SEW≠8` 按规定非法，不在本节范围。
5. **机时台账**（远端 `~/core/results/budget-log.tsv`，2026-11-07 复核）：本项正式作业两行——
   `127039614`（`1233 s`，`2.740 core-h`，超时作业）、`127043684`（`843 s`，`1.873 core-h`）——加本次 `127142843`
   （`988 s`，`2.196 core-h`，`COMPLETED 00:16:46`），**记账合计 `6.809 core-h`（`0.851 node-h`）**。
   另有**未记账**三次：`127030411`（外部取消，`23 s`）、`127031493`（初次超时）、`127142422`（本次为放宽
   `CASE_TIMEOUT_S` 主动取消，`4:44`、8 核 ≈`0.63 core-h`）——这三次的实际消耗不在台账里，如实披露。
6. **M3/M7/M8 的 `≈1.0 cyc/条` 是吞吐不是延迟**：VL=8 单结果、128b 通路全宽下的发射率；**M5 的 7.531（q8）也是同一差分口径的每步商，不是单条指令延迟**。上述数字均不可与"依赖间隔"混读，也不得与 §4.8.4 的 5.7–7.5 依赖链口径或 T5-L 的 4 相除/互引。
7. **JSON 产物**：本次 `96-dualchain-20261107T124540.json` 可被严格 `json.load` 解析（`status=通过`、12 criteria、19 metrics，含 M9/M10/M11 斜率）；上一次的 CR 缺陷已由 `metric_rows()` 的 `tr -d '\r'` 修复。本节数字取自用例日志的 `DUALCHAIN ... dep` 与 `DUALCHAIN_G44 ... fit` 行。
8. **M9/M10 的功能自检只覆盖「跑 1 步」**（结果 = 单次 dot(a,b)，与金模型 `DCW_M3` 逐字节一致，两条链均 `bytes_bad=0`）；N 步的最终值不在功能判据内（它们是计时臂）。完整 16 条功能链（M1–M8 及 alt）仍由金模型逐行复核（`LOG_MATCH chains=16 dep_lines=8`）。
9. **emu 重建差**：两批源版本相同（`a4eeaab/9559211/a683e0b`），但 emu `md5` 由 `529c9abc…` 变为 `fd65ca4a…`；M1–M8 有 ~0.5 拍级抖动（M4/M6/M7 更明显），M9/M10/M11 只在本次测量。跨批次引用 M1–M8 时以本次主表为准，上一次作复现记录。

---

## 4.8.7 复现命令

```sh
# 1) 金模型生成期望头 + 构建两镜像（昆山登录节点；必须先 source env.sh，
#    否则 PATH 里的旧工具链会段错误——本次实测：不 source 时连 trivial .c 都 rc=139）
ssh kunshan
source ~/tools/env.sh
export PATH=/public/software/apps/python/3.8.13/bin:$PATH
cd ~/core
AM_HOME=$HOME/core/src/nexus-am CROSS_COMPILE=riscv64-unknown-elf- \
  bash verify/cases/build_dualchain.sh "$HOME/core/results/difftest/dualchain/build"
# 2) 把 build 产物两个 bin 放到作业脚本读取的位置（96-run-dualchain.sh 默认 IMG=~/core/test/bin/）
cp ~/core/results/difftest/dualchain/build/vdot_dualchain.bin \
   ~/core/results/difftest/dualchain/build/vdot_dualchain_g0.bin ~/core/test/bin/
# 3) 提交单例作业（清单外；自动走 90-budget-log.sh 记账）。
#    本次三臂 M9/M10/M11 使主镜像约 11–12 min；为留余量用 CASE_TIMEOUT_S=2400、作业墙钟 50 min
#    （实测 127142843：COMPLETED 00:16:46、ExitCode 0:0；默认 900 s 未在本次直接验证是否够用）
CASE_TIMEOUT_S=2400 sbatch --time=00:50:00 -p kshcnormal -N 1 -n 8 \
  ~/core/core-package/scripts/96-run-dualchain.sh
# 4) 取数 + 金模型逐行复核
grep -a '^DUALCHAIN M[0-9] dep ' ~/core/results/difftest/dualchain/cases/vdot_dualchain.<runid>.log
grep -a '^DUALCHAIN_G44 '        ~/core/results/difftest/dualchain/cases/vdot_dualchain.<runid>.log
python3 -I ~/core/verify/cases/dualchain_check.py --check-log <case_log>   # 期望 LOG_MATCH
# 5) G0 反例判负（必须 MISMATCH，不得 MATCH）
grep -a 'CASE vdot_dualchain_g0:' ~/core/results/difftest/dualchain/cases/vdot_dualchain_g0.<runid>.log
```

**用词核对**（2026-11-07 复核，逐条如实）：`grep -nE "优于同题|全场唯一|唯一.*优势" stage3/3.3/sections/dualchain.md`
→ 命中均为**禁止性说明句本身**（本节首注、§4.8.5 硬性约束、§4.8.6 第 2 条），**无一处作为结论使用**。
`grep -nE "延迟加速 ?(6|9)"` → **0 命中（rc=1）**。`grep -n "7 cyc"` → 全部在【对方文档】/口径说明语境，逐处带标记。