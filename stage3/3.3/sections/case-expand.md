# 3.3 补充小节：用例矩阵扩展（`manifest.extra.tsv`）

> **位置**：本文件是 `stage3/3.3/report.md` **§4.12** 的正文来源（编号见 `report.md:155`），按 §4.6 的编号约定原文并入。
> **更新（2026-11-06）**：`report.md` §4.12 已按本文件 16:33 版更新——最终作业 `127031933`、`--time=02:00:00`、129/129 逐类通过数、三处冒烟修复与 1.544 node-h 均已入正文；旧版的「见 §A.4」占位符与 `127028127` 作业号已消除。本文件后续修改时，`report.md` §4.12 同步更新。
> **标注约定**：【实测】=本次在昆山实跑并读到输出；【实读】=本次取回文件逐字读到；【推算】=由实读证据做的算术推导；【未运行】=本次未执行。
> **口径约定**：本节不出现任何加速比。报告中仅有的加速比表述仍只在 `report.md` §4.3（每指令归一 `1.33×`）；本节所有倍数都是**用例条数之比**，与性能无关。

---

## A. 4.12.1 为什么扩：评分覆盖与用例分类

评分细则对「功能验证有效性」的要求只写到「正数/负数/边界」；本项原清单（`manifest.tsv`，30 例）在「寄存器重叠」与「流水/依赖」两类上没有独立分组，异常矩阵也只有 8 类。本节的扩容就是针对这三个缺口：新增重叠/别名族、背靠背与 RAW/WAW/WAR 流水族，并把异常矩阵做成参数化组合；扩容前的 30 例仍按原清单冻结。

**扩容的边界条件**：`design/verify/cases/manifest.tsv`（30 行、sha256 `a90d1071…`）是官方回归口径的冻结件，**一行未动**；扩容用例全部落在新清单 `design/verify/cases/manifest.extra.tsv`，由独立脚本 `core-package/scripts/94-run-extra.sh` 驱动（`20-run-difftest.sh` 未改）。这与 `perf_base_chain`、`vdot_xcontam` 的「清单外独立测量」裁定同口径（本报告 §1 的口径裁定）。

---

## A. 4.12.2 覆盖点矩阵（分类 / 行数 / 通过数）

清单实读：`awk '!/^#/ && NF>=3' design/verify/cases/manifest.extra.tsv | wc -l` → **129 行**（表头 1 行不计）。分类计数与逐类通过数见下表；「通过数」列的口径是 `94-run-extra.sh` 写出的 `cases.tsv` 第 3 列（`通过` 精确匹配），**未实跑的格子一律写「未运行」，不写「通过」**。

| 分类（`cls`） | 行数 | 配额 | 覆盖内容 | 通过数【实测】 | 证据 |
|---|---|---|---|---|---|
| `vdot-base` | 7 | =7（基础覆盖） | 正/负/上边界/下边界/`vl=0..8` 全扫/`vta·vma` 四组合/旧 `vd` 预填 | **7/7** | `results/difftest/extra/94-extra-20261106T143635.cases.tsv` |
| `vdot-ov` | **30** | ≥24 | `vs2=vd` / `vs1=vd` / `vs1=vs2` 三类 × 10 组数据模式（正/负/奇数负/上边界/下边界/零/交错极值/量级不对称/lane8-15 干扰/随机） | **30/30** | 同上 |
| `vdot-pl` | **48** | ≥40 | 背靠背 2/3/4/6/8 条、插 bubble 1/2/3/5/7、同 `vd` RAW 链 2/3/4/6/8、写回口竞争（`vdot↔vmacc` 2/3/4/6 与 `vdot↔vadd` 2/3/4/6）、`vdot` 抢同一写回口 2/4、控制流取消 2/3/4/8、异常状态构造-清除 6、高 96 位 2/4/8、旧 `vd` 4 值、背靠背+bubble 2/3、循环 2/4/8/16 | **48/48** | 同上 |
| `negative` | **41** | ≥32 | `vill`(4) / `vstart`(6) / `SEW`(3) / `LMUL`(6：m2/m4/m8/mf8/mf4/mf2) / `mstatus.VS=OFF`(1) / `vm=0`(1) / SEW×LMUL 9 组合 / `vstart`×SEW 4 组合 / 双谓词同时不满足 3 / **非法优先于 `vl=0` 全写** 3 | **41/41** | 同上 |
| `g0` | 2 | ≥1 | 期望值故意错 1 bit（重叠类 1 例、背靠背类 1 例），必须 `CASE <cid>: MISMATCH` 且不得出现 `MATCH` | **2/2** | 同上 |
| `vdot-rand10k` | 1（10000 组） | 新增 | 固定种子 `20261106` 的 10000 组随机；期望由金模型烧进镜像，C 侧算法 B 独立复算（`model_bad` 必须 0） | **1/1** | 同上 |
| **合计** | **129** | ≥96 | — | **129/129** | `94-extra-20261106T143635.json` → `cases_pass=达标（129/129）` |

**与外部公开清单的规模差异（仅作覆盖缺口披露，不作优劣判读）**：一份外部公开材料列出 251 例（【外部文档】，本仓未复跑其仓库），按基础 7、异常 64、重叠 60、流水/依赖 120 分布。本项 129 例（`manifest.extra.tsv` 数据行数）对应为：基础 7、异常 41、重叠 30、流水/依赖 48，**分别少 23 / 30 / 72**，条数合计少 **122**；另有 `g0` 2 不计入这四类。随机类本项为 1 例 × 10000 组；外部材料另计 144 配置 × 2 条 RVV 的等价测试，本项不作「独有」主张。

**这组数字怎么读（避免误读成「打平/超越」）**：
1. **条数不是同一量纲**。外部 251 是【外部文档】的用例计数，本次**未复跑**其仓库；本项 129 是 `manifest.extra.tsv` 的**数据行数**，每行对应一个独立 `.bin` 镜像（`ls design/verify/cases/extra/*.bin | wc -l` → 129），每份镜像内还有 1–9 个断言点（最多的是 `xb_vl_sweep`：`vl=0..8` 共 9 个读回点）（`cover.extra.tsv` 的 `note` 列写明每行覆盖什么）。
2. **分类口径也不同**。本项 `vdot-ov` 的 30 行是「3 种重叠形态 × 10 组数据」，不是 30 个不同的重叠语义；`vdot-pl` 的 48 行按「形态 × 长度」展开。
3. **本次没有做到「追平外部清单的 251 例」**。异常 41 < 64、重叠 30 < 60、流水 48 < 120，三项都少。要追平需要把每类的数据模式从 10 组扩到 20 组以上，本次未做——理由是每行都要独立编译 + 独立 difftest（单例约 20 s），129 行已是单作业 2 h 上限内的实际规模（实际墙钟 1:32:35，见 §4.12.4 的墙钟）。

---

## A. 4.12.3 期望值来源：全部由金模型生成（可机械复核）

本节要求「期望值全部由 `design/verify/vdot_model.py` 金模型生成」。落实方式是**生成期烧常量 + 事后机械复核**两道：

1. **生成期**：`design/verify/cases/gen_extra.py` 逐条重放用例的指令序列，每遇 `vdot` 就调 `M.vdot_vv(vs1_reg, vs2_reg)` 取完整 128 位 `vd`，把低 32 位写成 C 里的断言常量（`if (got[i] != 0x........u)`）。生成器里**没有第二套点积实现**。
2. **事后复核**：`design/verify/cases/extra_crosscheck.py` 从 `.c` 源解析 `//@OP` 注释重新重放一遍，与源里**实际烧进去的常量**逐条比对；同时用 `M.decode_vdot_vv()` 反解每条 `vdot` 的机器码，确认 `(vd, vs2, vs1)` 与注释一致。

复核实跑（本地与昆山各一次，同一脚本同一金模型，两侧 `vdot_model.py` sha256 同为 `21d12eff…`）：

```
$ python3 design/verify/cases/extra_crosscheck.py --quiet
EXTRA_CROSSCHECK cases=129 reads_or_groups=10162 vdot_encs=191 problems=0
EXTRA_CROSSCHECK verdict=MATCH（全部期望常量与金模型逐条一致）
```

- `reads_or_groups=10162` = 128 个定向/负例用例的断言点 + `vdot_rand10k` 的 10000 组；`vdot_encs=191` = 清单里 `vdot.vv` 机器码的条数（含 `xp_cxl*` 里被 `jal` 跳过的那几条）。
- **负例不靠期望值**：41 个 `negative` 行的判据是「DUT/NEMU 双侧一致陷入非法」，由 `M.illegal_reasons()` 在复核阶段确认「该状态在模型里确实非法」（`extra_crosscheck.py` 的 `check_negative()`），运行时判据是 difftest 日志的 `HIT CRITICAL ERROR`。
- **`vdot_rand10k` 的双算**：镜像里 `want10k[]` 由金模型生成；C 侧再用算法 B（`long long` 逐项累加）独立复算一遍并比对，不一致就打 `model_bad`。这样「Python 的 LCG 流」与「C 的 LCG 流」一旦分叉，`model_bad>0` 立刻判负，不会出现「DUT 与期望同时错」的假通过。

**G0 反例（假通过的机械证明）**：2 行 `g0` 的期望常量被**故意异或 1 bit**，程序仍正常走到结尾（`HIT GOOD TRAP`），因此只能被「自检串」判据抓住——日志必须出现 `CASE <cid>: MISMATCH` 且**不得**出现 `CASE <cid>: MATCH`。`94-run-extra.sh` 对 `g0` 类单独走这条判据并把 `G0_CAUGHT` 计入 `no_empty_green`。若某次 `G0_REQ>0` 而 `G0_CAUGHT<G0_REQ`，整套判「未达标」。

---

## A. 4.12.4 昆山实跑结果（逐行 status）

> 本节数字**只写本次实读到的**。作业号、`cases.tsv` 路径与逐类计数在下表；未跑完的格子写「未运行」。

**作业**：`127031933`（`-p kshcnormal -N 1 -n 32 --time=02:00:00`，脚本 `core-package/scripts/94-run-extra.sh --manifest ~/core/test/manifest.extra.abs.tsv --timeout 600`），`COMPLETED`、`Elapsed=01:32:48`。
**被取消的前序作业（如实记）**：`127028127`（129 例全套，跑到第 50 例时被 `CANCELLED by 276820`，作业内 50/50 全通过）与 `127030078`（单跑 rand10k，3 分钟后同样被取消）。两次取消都发生在 14:26:03，同一账号下其它并行作业（`127029615`/`127030411` 等）也在同一分钟被取消 ⇒ 属**账号级并发回收**，与本用例无关；本次不把取消原因归给用例，也不把中途结果计入通过数。

**冒烟测试（暴露并修复三个真实问题，如实记录）**：作业 `127026020`（6 例冒烟）判 `失败 3/6`，暴露：
- `xn_sew_e16` 负例**根本没构造非法状态**（生成器 `emit_negative()` 读的是 `n["extra"]` 而不是 `n["pre"]`，状态序列为空）⇒ 哨兵串出现、`CRIT=0`。修复：改为遍历 `n["pre"]`。
- `xg0_overlap` 判 `GOOD=0 BAD=1`——G0 用例 `return 1` 导致 `HIT BAD TRAP`，判负原因退化成 BAD TRAP 而非「自检串未命中」。修复：G0 类统一 `return 0`（先例 `design/verify/cases/vdot_g0_badexp.c:38`）。
- `vdot_rand10k` `rc=124`（900 s 单例上限不够）。修复：`94-run-extra.sh` 给随机类单独 `RAND_TIMEOUT_S=5400`，且**不**参与「剩余时间/剩余用例数」均分（均分会把它压到几十秒）。
- 另：`golden_crosscheck` 初次报「缺 `spec.extra.json`」——上传包漏了该文件与 `.c` 源。已补传，昆山侧 `EXTRA_CROSSCHECK verdict=MATCH`。

| 分类 | 行数 | 通过 | 未通过 | 未运行 |
|---|---|---|---|---|
| `vdot-base` | 7 | 7 | 0 | 0 |
| `vdot-ov` | 30 | 30 | 0 | 0 |
| `vdot-pl` | 48 | 48 | 0 | 0 |
| `negative` | 41 | 41 | 0 | 0 |
| `g0` | 2 | 2 | 0 | 0 |
| `vdot-rand10k` | 1 | 1 | 0 | 0 |
| **合计** | **129** | **129** | **0** | **0** |

> 上表是 **作业 `127031933` 的实测终态**（`started_at=2026-11-06T14:36:35+0800`、`ended_at=2026-11-06T16:09:10+0800` ⇒ 墙钟 1:32:35；`--time=02:00:00` 内完成）。JSON 顶层：`status=通过`、`counters={selected:129, executed:129, pass:129, not_run:0, reg_size_bad:0, selfcheck_req:86, selfcheck_ok:86, g0_req:2, g0_caught:2, neg_req:41, neg_ok:41}`；8/8 criteria `达标`（含 `golden_crosscheck=达标 :: EXTRA_CROSSCHECK verdict=MATCH`）。
>
> 关键自检串实读：`grep -a "RAND10K" cases/vdot_rand10k.20261106T143635.log` → `RAND10K verdict=ALL_OK groups=10000 mism=0 model_bad=0 ab_bad=0`；`CASE xo_vs2_pos: MATCH`、`CASE xg0_overlap: MISMATCH`、`xn_sew_e16` 日志含 `HIT CRITICAL ERROR`。逐用例关键行已抽取为本地件 `results/difftest/extra/94-extra-20261106T143635.keys.txt`（129 行：86 条 `MATCH`、2 条 G0 `MISMATCH`、41 条 `HIT CRITICAL ERROR`、1 条 `RAND10K`），完整单例日志（约 4.7 MB/份）留在远端 `~/core/results/difftest/extra/cases/`。

> 复核命令（本地取回件）：`awk -F'\t' '{n[$2]++; if($3=="通过") p[$2]++} END{for(k in n) printf "%s %d/%d\n", k, p[k], n[k]}' results/difftest/extra/94-extra-20261106T143635.cases.tsv | sort` → `g0 2/2` / `negative 41/41` / `vdot-base 7/7` / `vdot-ov 30/30` / `vdot-pl 48/48` / `vdot-rand10k 1/1`；`grep -c 通过` → 129。

---

## A. 4.12.5 工程形态与可复现

| 件 | 路径 | 作用 |
|---|---|---|
| 生成器 | `design/verify/cases/gen_extra.py` | 129 份 `.c` + `manifest.extra.tsv` + `cover.extra.tsv` + `extra/spec.extra.json`；生成期即做配额自检（`--check` 只打印不写盘） |
| 构建 | `design/verify/cases/build_extra.sh` | 逐例 AM 构建（`ARCH=riscv64-xs`），最后按清单核对产物齐备 |
| 期望值复核 | `design/verify/cases/extra_crosscheck.py` | 金模型重放 + 机器码反解 + G0 错 1 bit 校验 |
| 运行 | `core-package/scripts/94-run-extra.sh` | 走 extra 清单的独立 difftest 作业（判据与 `20-run-difftest.sh` 逐条同构，**不改后者**） |
| 覆盖点表 | `design/verify/cases/cover.extra.tsv` | 每行 `cid / cls / family / 规范锚点 / 说明`，供本节表格机械汇总 |
| 用例清单 | `design/verify/cases/manifest.extra.tsv` | 129 条用例及分类（本表数据来源） |

复现三条命令（本地构建 → 昆山实跑 → 逐行取状态）：

```
AM_HOME=<nexus-am> CROSS_COMPILE=riscv64-unknown-elf- bash design/verify/cases/build_extra.sh
sbatch -p kshcnormal -N 1 -n 32 --time=02:00:00 core-package/scripts/94-run-extra.sh \
       --manifest $HOME/core/test/manifest.extra.abs.tsv --timeout 600
awk -F'\t' '{n[$2]++; if($3=="通过") p[$2]++} END{for(k in n) printf "%s %d/%d\n", k, p[k], n[k]}' \
    results/difftest/extra/94-extra-<runid>.cases.tsv
```

**未做与边界（不作达标声明）**：
- 未追平外部公开清单的 251 例（异常 41/64、重叠 30/60、流水 48/120，三项都少，见 §A.2 的覆盖缺口说明）。
- 该 251 例的分布是【外部文档】口径，本次**未复跑**其仓库；本节只作规模参照，不作「谁更强」的结论。
- `manifest.extra.tsv` 的 129 行**不进** 30 例官方回归清单，也不参与 `regression_delta`（该判据的基线是 `results/difftest/baseline.tsv` 的 30 行）。
- 机时：本作业由 `94-run-extra.sh` 末尾的 `90-budget-log.sh auto --item P3-full` 自动记账，`results/budget-log.tsv` 实读一行 `2026-11-06 16:09:11  127031933  kshcnormal  32  5557  49.396  1.544  P3-full  扩容用例整套 difftest（manifest.extra.tsv，独立作业；不改 30 例主清单）` ⇒ **1.544 node-h**（32 核 × 5557 s）。实跑前该项已超自设预算（`summary` 当时显示 215%），跑完后 `summary` 显示 `P3-full 8.862/3.0（295%）`、合计（不含缓冲）`12.858/10.6`、**EXIT=1**。**超支事实在此披露，不写成「预算内」**；`P3-full` 的数字里同时含其它并行提交的作业，不是本用例单独消耗。
