# LLM 算子级内核对照：Q8_0 / INT8 attention QK 点积（3.3 §4.7 材料稿）

> 状态：**已实跑并复跑**（昆山作业 `127049777`，2026-11-06 17:07–17:21，节点 `<node>`（节点名占位）；复跑 `127051826`，
> 2026-11-06 17:23–17:45，`COMPLETED 00:22:12`、`ExitCode=0:0`、脚本 `status=通过` 9/9 criteria 达标）。
> **两次独立作业的全部数字逐值相同**（见文末「复跑」节）。
> 定位：本文件是 `stage3/3.3/report.md` §4.6 专题小节中的 **§4.7** 材料；
> 本节正文与报告 §4.7 一致（仅标题层级与用词统一）。
> 来源口径：BenchSpec 见 llama.cpp 的 `ggml_vec_dot_q8_0_q8_0`（`ggml-quants.c`）与 `block_q8_0` 定义；用例 `design/verify/cases/perf_llm_attn.c`；
> 金模型生成器 `design/verify/cases/gen_llm_attn.py`；运行脚本 `core-package/scripts/97-run-llm.sh`。

---

## 0. 口径声明（先读，防误读）

- **只报三轴**：静态指令数、动态拍数、内核吞吐。**不是**延迟加速比、**不是**官方 latency 口径、**不是**端到端 token/s。
- **主分母固定 `unfused_rvv_seq`**：每 K=8 子块 `vwmul.vv → vwadd.vx → vredsum.vs`（`design/ALGORITHM.md` §3.4 的定义）。
  `vwmacc_rvv_seq`（每子块 `vwmacc.vv + vwredsum.vs` 两条计算；累加器清零是 **body 级 9 条 `vmv.v.i`**，不是每子块 1 条）**只作敏感性**，两者不合并、不相除。
- **与 §4.3 的每指令 `1.33×` 分节、不相乘/不相除**：那是「`L_base_chain=16` 对 `L_vdot=4` 的依赖链归一」，
  本节是「Q8_0 attention tile 的批处理内核实测」。两者测量对象、口径、单位都不同。
- **emu ≠ 硅**：`mcycle`/`cycleCnt` 均为 Verilator 周期级仿真值，不是硅实测。
- 本节**不主张**对 llama.cpp 上游宽核（每 32 元素 2 条计算指令）的优势；理由见 §6。

## 1. 算子、形状与数据

| 项 | 值 |
|---|---|
| 算子 | INT8 attention QK 点积（与 `ggml_vec_dot_q8_0_q8_0` 的 block 内层点积同形） |
| 形状 | 8 query × 8 key × head_dim=64 ⇒ 64 个 score、**512 个 K=8 chunk dot** |
| 数据布局 | 每行 2 × `block_q8_0 { uint16_t d; int8_t qs[32]; }`（34 B/block，`qs` 在 `+2`），68 B/行 |
| 子块偏移 | `2, 10, 18, 26, 36, 44, 52, 60`（**刻意非 8 字节对齐**，测非对齐 `vle8.v`） |
| 量化 scale | 全部 block `d = 0x3800`（fp16 = 0.5）⇒ 去量化因子 `d_q·d_k = 0.25` **精确**，score = isum/4 |
| 期望值 | `gen_llm_attn.py` 用 `vdot_model.dot_product()`（任意精度）与 `vdot_model.vdot_vv()`（19 位模型）**逐 chunk 交叉核对**后生成头文件；用例内无手写期望常量 |
| 数据边界 | key 行 7 的 chunk 0/1/2 = 全 -128 / 全 +127 / 交替极值 ⇒ S = +131072 / +129032 / **-130048**（19 位模型上下沿） |
| 二进制 | nexus-am flat binary，链接 `0x80000000` 起；正常退出走 `0x5006b`（emu 打印 `HIT GOOD TRAP`） |

**score 级不是单指令**：一条 `vdot.vv` 只完成一个 K=8 子块；一个 head_dim=64 的 score 需要 **8 条 vdot + 7 条 `vadd.vv`**。
本节的「dot」一律指一个 **K=8 子块**（8 个 int8 对、8 次乘加），不是 score。
**术语换算（防 8× 误读）**：1 个 K=8 dot = 8 个 int8 对；1 个 score = 8 个 K=8 dot = 64 个 int8 对。
用例日志字段 `dots=` 与拟合 x 计的是 **int8 对数**（`perf_llm_attn.c:111-113` 的 `LLM_DPS=64`，窗口内 `x = 64n`）；
本报告引用时一律换算并标明口径（cyc/dot、dot/cyc、int8 对/cyc 三套并列）。

## 2. 三个臂与静态指令数（objdump 逐条计数）

| 臂 | 分母名 | 每 K=8 子块 | 每 score（8 子块） | 静态总数 |
|---|---|---|---:|---:|
| A | **`unfused_rvv_seq`（主分母）** | `vsetivli`·2×`vle8.v`·`vwmul.vv`·`li`·`vsetvli`·`vwadd.vx`·`li`·`vsetvli`·`vredsum.vs`（+2 `addi` 取址） | 计算段 **24** | **100** |
| B | `vwmacc_rvv_seq`（敏感性） | `vsetivli`·2×`vle8.v`·`vwmacc.vv`·`li`·`vsetvli`·`vwredsum.vs`（+2 `addi`；body 级另有 13 条，见下） | 计算段 **16** | **85** |
| C | `vdot_seq` | `vsetivli`·2×`vle8.v`·`vdot.vv`（+2 `addi`） | 计算段 **8 vdot + 7 vadd = 15** | **58** |

- **macc 臂的清零是 body 级 9 条 `vmv.v.i`**（`perf_llm_attn.c:214-224`）：分别清 8 个独立宽化累加器
  （v4/v6/v8/v12/v14/v16/v18/v20）+ 链式累加器 v10，**不是每子块 1 条**。
  body 级合计 13 条（`vsetivli` + 9×`vmv.v.i` + `li` + `vsetvli` + `vmv.x.s`）；8 子块 × 9 条 + 13 = **85**（与 `N_macc=85` 一致）。
- **objdump 别名**：源里的 `vwadd.vx v6, v4, zero` 被 binutils 2.41 反汇编为别名 `vwcvt.x.x.v v6, v4`
  （同一编码 `0xc6406357`，见 `results/difftest/llm/llm_attn_static_base.txt:10`）；逐条列表以 objdump 输出为准，指令种类仍按 `vwadd.vx` 计。
- **计数范围**：`[<llm_*_begin>, <llm_*_end)`，即 C 源里 asm 文本自身；**不含** gcc 补的 `sext.w`/`ret`、
  不含 gcc 在函数入口给 `"r"` 操作数做的 `mv`、不含 C 运行时/printf。
- **地址形成单列**：三个臂每子块各有 2 条 `addi`（共 16 条/score）。原因是本机 binutils 2.41 不接受
  向量访存的非零立即数偏移（`vle8.v v1,2(a5)` → `illegal operands`，实测），故地址一律显式形成。
  该项三臂相同，**不进入「计算段」比较**。
- **裸比值**（不是加速比）：`N_base/N_vdot = 100/58 = 1.724`；`N_macc/N_vdot = 85/58 = 1.466`；
  计算段 `24/15 = 1.600`、`16/15 = 1.067`。
- 逐条列表：`results/difftest/llm/llm_attn_static_{base,macc,vdot}.txt`（各 100 / 85 / 58 行）。
- **静态↔动态交叉核对**：`minstret` 差分（route2，见 §3）给出的每 score 指令数
  **逐值等于**静态计数：`static_base=100 measured_base=100 base=OK`、
  `static_macc=85 measured_macc=85 macc=OK`、`static_vdot=58 measured_vdot=58 vdot=OK`。

## 3. 动态拍数：4 点规模拟合（含斜率与 R²）

测量方式（详见用例头注）：`mcycle` 三点差分族。**拍数拟合用 route1 `I(n)−I(0)`**
（`perf_llm_attn.c:486-504`：每轮先测一个 n=0 空批点，再逐点测 n>0），逐轮原始增量取中位数。
`ROUNDS=3`、`N_WARMUP=1` ⇒ **只有 2 个有效样本**，`median_u64` 取 `a[n/2]` = **上中位数**（较大者）。
route2（`I(n_max)−I(n_min)`）**只用于 §2/§5 的静态↔动态指令数核对**，不用于拍数拟合。
`n` = 每次调用的 score 数；拟合 x = 窗口内 **int8 对数** `64n`（每 K=8 dot = 8 个 int8 对 ⇒ K=8 dot 数 = `8n`）。

**原始点（每臂 4 点，中位数；`R_LOOP=1`、2 个有效样本取上中位数）**

| 臂 | n=2 / 128 int8 对（16 K=8 dot） | n=8 / 512 int8 对（64 K=8 dot） | n=16 / 1024 int8 对（128 K=8 dot） | n=32 / 2048 int8 对（256 K=8 dot） |
|---|---:|---:|---:|---:|
| base（`unfused_rvv_seq`） | 218 cyc | 758 cyc | 1479 cyc | 2918 cyc |
| macc（`vwmacc_rvv_seq`） | 188 cyc | 654 cyc | 1277 cyc | 2518 cyc |
| vdot（`vdot_seq`） | 136 cyc | 422 cyc | 806 cyc | 1566 cyc |

**拟合（最小二乘，x = 窗口内 int8 对数，y = 窗口内 mcycle 增量）**

| 臂 | Σx | Σy | Σxy | Σx² | Σy² | A | B | C |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| base | 3712 | 5373 | 7906560 | 5521408 | 11324253 | 11681664 | 8306688 | 16427883 |
| macc | 3712 | 4637 | 6823424 | 5521408 | 8434113 | 10081152 | 8306688 | 12234683 |
| vdot | 3712 | 2930 | 4265984 | 5521408 | 3298572 | 6187776 | 8306688 | 4609388 |

| 臂 | 斜率 = A/B（cyc/int8 对） | 每 K=8 dot 周期 = 8·A/B | 每 score 周期 = 64·A/B | 截距（cyc/窗口） | R² = A²/(B·C) |
|---|---:|---:|---:|---:|---:|
| base | `30421/21632 = 1.406296` | **11.250** | **90.00** | 38.21 | **0.99999982** |
| macc | `26253/21632 = 1.213619` | **9.709** | **77.67** | 33.01 | **0.99999932** |
| vdot | `8057/10816 = 0.744915` | **5.959** | **47.67** | 41.22 | **0.99999540** |

**裸比值（同一轴 = cyc/int8 对）**：`slope_base/slope_vdot = 1.406296/0.744915 = 1.888`；`slope_macc/slope_vdot = 1.630`。
截距含「窗口边缘 + 循环控制」的固定开销（三个臂同一量级 33–41 cyc/窗口），**不进斜率**。

> **复算方法**（报告里的数字全部可由上表两行复算，不需要任何私有中间量）：
> ```
> A = 4·Σxy − Σx·Σy ;  B = 4·Σx² − (Σx)² ;  C = 4·Σy² − (Σy)²
> cyc_per_int8pair = A/B      # 拟合 x 是 int8 对数
> cyc_per_dot      = 8·A/B    # dot = K=8 子块 = 8 个 int8 对
> dot_per_cyc      = B/(8·A)
> int8pair_per_cyc = B/A
> int8op_per_cyc   = 2·B/A    # 每个 int8 对含 2 个操作数
> per_score        = 64·A/B
> intercept = (Σy·B − A·Σx)/(4·B) ;  R² = A²/(B·C)
> ```
> 一键复算（把三行 Σ 值抄进去即可）：
> ```sh
> python3 -c "A=11681664;B=8306688;C=16427883;s=A/B;print('cyc/int8pair',s,'cyc/dot',8*s,'dot/cyc',1/(8*s),'int8pair/cyc',1/s,'per-score',64*s,'R2',A*A/(B*C))"
> python3 -c "A=6187776;B=8306688;C=4609388;s=A/B;print('cyc/int8pair',s,'cyc/dot',8*s,'dot/cyc',1/(8*s),'int8pair/cyc',1/s,'per-score',64*s,'R2',A*A/(B*C))"
> ```
> 实算结果：base `cyc/int8pair 1.406296228, cyc/dot 11.250370, dot/cyc 0.088886, int8pair/cyc 0.711088, per-score 90.0030, R2 0.99999982`；
> vdot `cyc/int8pair 0.744914941, cyc/dot 5.959320, dot/cyc 0.167804, int8pair/cyc 1.342435, per-score 47.6746, R2 0.99999540`。

> **route1 披露（指令数口径）**：`I(n)−I(0)` 的指令数含有与 n 无关的常量边缘项（实测 +2 条/调用，
> `route1_disclosure=102/87/60`），除以 n 后会随 n 漂移，故**只披露、不作判据**；
> route2 把该常量精确消掉，才得到与静态计数逐值相等的 100/85/58。
> （拍数拟合仍用 route1；常量边缘项落在截距里，不进斜率——见上表。）

## 4. 内核吞吐（三套单位并列，不换算 token/s）

| 臂 | cyc/dot（dot=K=8，8 乘加） | dot/cyc（K=8） | int8 对/cyc | int8 操作数/cyc | 每 score 周期 |
|---|---:|---:|---:|---:|---:|
| base | **11.250** | **0.0889** | **0.7111** | **1.422** | 90.00 |
| macc | **9.709** | **0.1030** | **0.8240** | **1.648** | 77.67 |
| vdot | **5.959** | **0.1678** | **1.3424** | **2.685** | 47.67 |

- **口径换算（三套数同源、并列，不互引）**：拟合 x 是 int8 对数 ⇒ `cyc/int8 对 = A/B`；
  `cyc/dot = 8·A/B`；`dot/cyc = 1/(cyc/dot)`；`int8 对/cyc = 1/(cyc/int8 对)`；
  `int8 操作数/cyc = 2 × int8 对/cyc`（每个 int8 对含 2 个操作数）。三套数的精确值与复算见 §3。
- 吞吐裸比值（**同一轴内相除，不是加速比**）：`(int8 对/cyc)_vdot/(int8 对/cyc)_base = 1.3424/0.7111 = 1.888`；
  `(int8 对/cyc)_vdot/(int8 对/cyc)_macc = 1.630`。该比值在 cyc/dot 轴与 dot/cyc 轴数值相同，
  但本节只按所标轴各写一次，不与其它节互引。
- **不折算 GOP/s**：emu 没有可外推的真实频率；任何 GOP/s 都会是假定频率下的【推算】，本节不给。
- **load 形态披露**：计时窗口内重复读同一 chunk（resident/L1-hot），**不含跨 block 指针推进与流式访存**；
  功能校验另走完整 512 chunk（34 B 步长、`+2` 偏移）的真实布局。故本节的拍数是「内核 resident」口径，
  不是 memory-bound 口径（后者未运行）。

## 5. 自检与防「假通过」

| 检查 | 实测 |
|---|---|
| 编码自检 | `enc_check=0x3A20A1D7 expect=0x3A20A1D7 OK`（body 实际发射 `0x3A20A657` = `VDOT_ENC(12,1,2)`，解出 **vd=12**；与首条 `vdot.vv v12` 一致） |
| vl 自检 | `vl base=8 macc=8 vdot=8 expect=8 OK` |
| 金模型逐 score | `golden isum_fnv=0xAE617E159015FC18 expect=0xAE617E159015FC18 chunks=512 scores=64 arms_ok=64/64/64 OK` |
| 第三条独立路径 | `scalar_ref ref_vs_header_bad=0 OK`（纯标量参考和与头文件逐 score 相等） |
| 长度可分辨 | `base_alt accum_n=0xFFF3472F accum_nm1=0xFFF3DFEC alt_differs=yes` |
| 正常镜像 | `LLM_ATTN verdict=ALL_OK … enc_ok=OK vl_ok=OK golden_ok=OK alt_differs=yes fit=OK static_xcheck=OK` |
| G0 反例 | `LLM_ATTN verdict=HAS_FAIL reason=golden_mismatch score=0,0 got=0x0000D73D want=0x0000D73E arms_bad=1/1/1`（把期望值 `[0][0]` 故意 +1；仅该 score 被判负，其余 63 个仍 OK ⇒ 判负逻辑有分辨力） |
| 陷阱 | 两个镜像均 `HIT GOOD TRAP`；`ABORT=0`、`HIT BAD TRAP=0` |

> **实跑抓到过一个真 bug**：作业 `127039889`（15:53 的作业，FAILED）中 macc 臂 64 个 score **全错**（`arms_ok=64/0/64`）。
> 根因：`vwmacc.vv` 在 SEW=8 时目的组是 EEW=16/EMUL=2（两个寄存器），而累加器清零写在 e8 视图下
> 只清了 64 位（半个组），高 64 位是脏值。改为 e16 视图逐条清零 8 个独立累加器后，
> 复跑 `127049777` 的 G0 显示 `arms_bad=1/1/1`（只有被故意改错的那个 score 错），macc 臂通过。
> 这条留在这里是证据链的一部分：**G0 + 三臂互比确实抓得住实现错误**。

## 6. 这个基准能主张什么、不能主张什么

**能主张（限本节口径）**

1. 同一 Q8_0 attention tile、同一 VL=8、同一计时区下，**主分母** `unfused_rvv_seq` 的每 score
   计算指令 24 条、静态总数 100 条；`vdot_seq` 计算段 15 条、静态总数 58 条（裸比值 1.600 / 1.724）。
2. 同一数据与同一差分口径下，**每 K=8 dot 周期** `11.250` vs `5.959`；**每 int8 对周期** `1.406296` vs `0.744915`
   （两套各自同轴相除，裸比值均为 `1.888`；R² 分别为 `0.99999982` / `0.99999540`，4 个规模点）。
3. **敏感性**：对 `vwmacc_rvv_seq`（每子块 2 条计算指令，比主分母更省），vdot 的计算段优势只有
   `16/15 = 1.067`，同轴（int8 对/cyc）拍数裸比值 `1.630`。即 **vdot 的收益主要来自「把 3 条未融合序列压成 1 条」**，
   而不是「比任何 RVV 写法都省」。
4. K=8 语义的**固定代价**：一个 head_dim=64 的 score 需要 8 条 vdot + 7 条 vadd；
   「vdot 单指令」只在 **K=8 子块**级成立，**score/block 级不是单指令**。

**不能主张**

- **对 llama.cpp 上游宽核的优势**：上游 Q8_0 RVV 核每 32 元素只有 2 条计算指令（宽 LMUL 装载 + 宽化归约），
  本节的 `unfused_rvv_seq` 是 12 条/32 元素。两者分母不同；本节**不主张** VDOT 对上游宽核占优。
- **端到端 token/s / LLM 推理加速 N×**：昆明湖 emu 跑 AM flat binary，不是 Linux 进程，跑不了 llama.cpp；
  本节只有 kernel 级数字。
- **与 §4.3 的 `1.33×` 混称**：本节不引用、不相乘、不相除。
- **硅上性能**：全部拍数为 Verilator 仿真周期（`Core-0 cycleCnt=453,987` 是整程序口径，含 printf 与自检，
  不可当 kernel 数字；kernel 数字来自窗口内 `mcycle` 差分）。

## 7. 与评分表的映射

| 评分项 | 官方出处 | 本节位置 |
|---|---|---|
| 阶段三 25 分（3.3 报告） | `docx/02-赛题与评分细则.md:90` | 真实 LLM 算子（Q8_0 attention QK）的第二组证据；不替代 §4.3 |
| 探索性 5 分（微架构优化分析） | `docx/02:93` | 三轴（静态指令 / 动态拍 / 吞吐）+ 4 点拟合斜率与 R² |
| 创新性 5 分（扩展应用潜力） | `docx/02:96` | `16/15 = 1.067` 的敏感性结果 **直接量化**「K=8 单结果语义在 head_dim=64 上的映射损失」，与 §7 的「K=16 / np 多结果」扩展路线图衔接 |
| 可行性 | `docx/02:91-92` | 全部复用现有 AM/emu/金模型/差分口径；改动面 = 一个用例 + 一个生成器 + 两个构建/运行脚本，**无 RTL 改动** |

## 8. 证据路径（全部在库）

| 证据 | 路径 |
|---|---|
| 用例源码 | `design/verify/cases/perf_llm_attn.c` |
| 金模型生成器 / 头文件 | `design/verify/cases/gen_llm_attn.py`、`design/verify/cases/llm_attn_vectors.h`（sha256 `60914c8e…`） |
| 静态计数（逐条 + 汇总） | `results/difftest/llm/llm_attn_static_{base,macc,vdot,summary}.txt`、`llm_attn_static_diff.txt` |
| 镜像与构建摘要 | `results/difftest/llm/llm_attn.bin`、`llm_attn_g0.bin`、`llm_attn_build_summary{,_g0}.txt` |
| 实跑（主） | `results/difftest/llm/run-20261106T170716/`（`97-llm-*.log/json` + 正常/G0 两份 case log） |
| 运行脚本 | `core-package/scripts/97-run-llm.sh` |
| 构建/计数脚本 | `design/verify/cases/build_llm_attn.sh`、`design/verify/cases/objdump_llm_attn.sh` |
| 口径修订复算（20261107） | 按 §3 的 `python3 -c` 两行与 §2 的 objdump 计数可直接重跑（三套单位复算 + 编码解码 + 核对输出） |

## 9. 用词核对（对照 `stage3/3.3/report.md` §9）

- 本节不写「延迟加速」与「每点开销倍数」的组合表述；该组合涉及的每点开销数字在本节**未引用**。
- 本节不写「2 拍已收敛」「SEW=16/LMUL=2 已支持」「比竞品快 N 倍」。
- 本节把「加速」类词汇只用于**禁止性说明**（§0/§6）；所有比值一律写成裸比值 `A/B`。
- 所有未实测项（端到端 token/s、memory-bound 口径、GOP/s、硅上周期）**明写未运行**。

## 10. 复跑（独立作业 `127051826`）

| 项 | 实测 |
|---|---|
| 作业 | `127051826` / `kshcnormal` / `COMPLETED 00:22:12` / `ExitCode=0:0` / 8 核 |
| 脚本判据 | `status=通过`，9/9 criteria 达标（`normal_all_ok`、`g0_has_fail`、`good_trap`、`no_abort`、`no_bad_trap`、`llm_fields`、`no_mismatch_line`、`emu_rc`、`static_xcheck` 全 `达标`） |
| 正常镜像 | `LLM_ATTN verdict=ALL_OK … enc_ok=OK vl_ok=OK golden_ok=OK alt_differs=yes fit=OK static_xcheck=OK` |
| G0 镜像 | `LLM_ATTN verdict=HAS_FAIL reason=golden_mismatch score=0,0 got=0x0000D73D want=0x0000D73E arms_bad=1/1/1` |
| 逐点拍数 | base `218 / 758 / 1479 / 2918`、macc `188 / 654 / 1277 / 2518`、vdot `136 / 422 / 806 / 1566`（**与 `127049777` 逐值相同**） |
| 拟合 | base `A/B = 11681664/8306688`、macc `10081152/8306688`、vdot `6187776/8306688`（**与 `127049777` 逐值相同**） |
| 静态↔动态 | `static_base=100 measured_base=100 base=OK static_macc=85 measured_macc=85 macc=OK static_vdot=58 measured_vdot=58 vdot=OK div=OK` |

结论：本节的数字是**可复现的**（两次独立作业、同一镜像 sha256、emu 确定性行为），不是单次偶然。

## 11. 机时（如实记账）

昆山 `results/budget-log.tsv` 实读（`90-budget-log.sh`）：

| 作业 | 状态 | elapsed | node-h |
|---|---|---:|---:|
| `127039889` | FAILED（暴露 macc 臂 bug 的作业，不构成结论） | 215 s | 0.060 |
| `127042412` | TIMEOUT（用例 1200 s 超时，不构成结论） | 1344 s | 0.373 |
| `127046416` | 主动 `scancel`（分支阶梯与点表不一致，不构成结论） | 891 s | 0.248 |
| `127049777` | COMPLETED（用例侧 `verdict=ALL_OK`；脚本 CR 解析误判） | 867 s | 0.241 |
| `127051826` | COMPLETED（`status=通过` 9/9 criteria） | 1330 s | 0.369 |
| **合计** | | | **1.291** |

该项落在 **P3-full** 科目下；远端 `90-budget-log.sh summary` 显示 **P3-full 与合计均已超线**
（`P3-full 10.819/3.0`、`合计 14.815/10.6`，含其它并行批次的用量）。本节如实记账，不做冲销，也不作辩解。
