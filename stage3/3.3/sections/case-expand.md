# 3.3 补充小节：用例矩阵扩展（`manifest.extra.tsv`）

> **位置**：本文件是 `stage3/3.3/report.md` **§4.12** 的正文来源（编号见 `report.md` §4.6），按 §4.6 的编号约定原文并入。
> **状态（2026-11-08 终态）**：扩容清单 **224 数据行**，昆山整套实跑 **224/224**（作业 `127194011`，8/8 criteria）。上一轮 **129 例**（作业 `127031933`，2026-11-06）只作历史保留；本文凡写「上一轮」处均为 129 例快照。`report.md` §4.12 与本文同步。
> **标注约定**：【实测】=本次在昆山实跑并读到输出；【实读】=本次取回文件逐字读到；【推算】=由实读证据做的算术推导；【未运行】=本次未执行。
> **口径约定**：本节不出现任何性能加速比；加速比表述只在 `report.md` §4.3（整链 `4.0×` 与每指令归一 `1.33×` 并列）。本节所有倍数都是**用例条数之比**，与性能无关。

---

## A. 4.12.1 为什么扩：评分覆盖与用例分类

评分细则对「功能验证有效性」的要求只写到「正数/负数/边界」；本项原清单（`manifest.tsv`，30 例）在「寄存器重叠」与「流水/依赖」两类上没有独立分组，异常矩阵也只有 8 类。本节的扩容就是针对这三个缺口：新增重叠/别名族、背靠背与 RAW/WAW/WAR 流水族，并把异常矩阵做成参数化组合；扩容前的 30 例仍按原清单冻结。

**扩容的边界条件**：`design/verify/cases/manifest.tsv`（30 行、sha256 `a90d1071…`）是官方回归口径的冻结件，**一行未动**；扩容用例全部落在新清单 `design/verify/cases/manifest.extra.tsv`，由独立脚本 `core-package/scripts/94-run-extra.sh` 驱动（`20-run-difftest.sh` 未改）。这与 `perf_base_chain`、`vdot_xcontam` 的「清单外独立测量」裁定同口径（本报告 §1 的口径裁定）。

---

## A. 4.12.2 覆盖点矩阵（分类 / 行数 / 通过数）

清单实读：`awk -F'\t' '!/^#/ && NF>=3' design/verify/cases/manifest.extra.tsv | wc -l` → **224 行**（表头 1 行不计；`design/verify/cases/extra/spec.extra.json` 的 `rows=224`、`cases` 数组 224 条同值）。分类计数与逐类通过数见下表；「通过数」列的口径是 `94-run-extra.sh` 写出的 `cases.tsv` 第 3 列（`通过` 精确匹配），**未实跑的格子一律写「未运行」，不写「通过」**。本轮 `counters` 为 `selected=executed=pass=224`，且下表行数之和 = 224 ⇒ **逐类通过数 = 该类行数**（这是「全选全过」的算术结果；逐例 `cases.tsv` 本轮未取回本地，逐类数不是逐行读出来的）。

| 分类（`cls`） | 行数 | 配额 | 覆盖内容 | 通过数（按 `counters` 折算） | 证据 |
|---|---|---|---|---|---|
| `vdot-base` | 7 | =7（基础覆盖） | 正/负/上边界/下边界/`vl=0..8` 全扫/`vta·vma` 四组合/旧 `vd` 预填 | **7/7** | `out/audit/final/94-extra-20261108T014445.json`（`counters`） |
| `vdot-ov` | **56** | ≥24 | 原 30 例：`vs2=vd` / `vs1=vd` / `vs1=vs2` 三类 × 10 组数据模式（正/负/奇数负/上边界/下边界/零/交错极值/量级不对称/lane8-15 干扰/随机）；**新增 26 例**：`alias3` 9 / `alias-wb` 5 / `alias-vl` 4 / `alias-lanehi` 4 / `alias-hi96` 4（`cover.extra.tsv` 的 `family` 列实读） | **56/56** | 同上 |
| `vdot-pl` | **98** | ≥40 | 原 48 例：背靠背 2/3/4/6/8、bubble 1/2/3/5/7、同 `vd` RAW 链 2/3/4/6/8、写回口竞争、控制流取消、异常构造-清除、高 96 位、旧 `vd`、循环；**新增 50 例**：`vd-reuse` 7 / `rotate` 6 / `cross-class` 6 / `bb-distinct` 5 / `waw-x` 5 / `war` 5 / `vtype-imm` 5 / `vl-imm` 5 / `raw-mid` 4 / `raw-cross` 2 | **98/98** | 同上 |
| `negative` | **57** | ≥32 | 原 41 例：`vill`(4) / `vstart`(6) / `SEW`(3) / `LMUL`(6：m2/m4/m8/mf8/mf4/mf2) / `mstatus.VS=OFF`(1) / `vm=0`(1) / SEW×LMUL 9 组合 / `vstart`×SEW 4 组合 / 双谓词同时不满足 3 / **非法优先于 `vl=0` 全写** 3；**新增 16 例**（同族扩展，`family=illegal`） | **57/57** | 同上（`neg_req=57 / neg_ok=57`） |
| `negative-legal`（**新增类**） | 3 | — | `negative-control`：构造非法前置但按合法路径执行的对照例（3 例） | **3/3** | 同上 |
| `g0` | 2 | ≥1 | 期望值故意错 1 bit（重叠类 1 例、背靠背类 1 例），必须 `CASE <cid>: MISMATCH` 且不得出现 `MATCH` | **2/2** | 同上（`g0_req=2 / g0_caught=2`） |
| `vdot-rand10k` | 1（10000 组） | 新增 | 固定种子 `20261106` 的 10000 组随机；期望由金模型烧进镜像，C 侧算法 B 独立复算（`model_bad` 必须 0） | **1/1** | 同上 |
| **合计** | **224** | ≥96 | — | **224/224** | `94-extra-20261108T014445.json` → `cases_pass=达标（224/224）`、`status=通过` |

**规模说明（只记本仓数字）**：本项 224 例按四类计为基础 7、异常 57、重叠 56、流水/依赖 98；另有 `g0` 2、`negative-legal` 3、`vdot-rand10k` 1（10000 组）不计入这四类。条数不是同一量纲，本节不与任何外部清单的用例总数作对照，也不作「谁更强」的判读。

**这组数字怎么读（避免误读成「打平/超越」）**：
1. **条数与镜像数不是同一个量**。本项 224 是 `manifest.extra.tsv` 的**数据行数**，本轮实跑 `selected=executed=224`（逐例一个独立镜像）；但**本地 `design/verify/cases/extra/` 只有 129 个 `.bin`**（`*.c` 有 224 个），新增 95 例的二进制在远端构建、未取回本地。每份镜像内还有 1–9 个断言点（最多的是 `xb_vl_sweep`：`vl=0..8` 共 9 个读回点）（`cover.extra.tsv` 的 `note` 列写明每行覆盖什么）。
2. **分类口径也不是「一类一个语义」**。本项 `vdot-ov` 的 56 行 = 「3 种重叠形态 × 10 组数据」的 30 行 + 26 行 alias 族；`vdot-pl` 的 98 行按「形态 × 长度」展开（其中新增 50 行按新族展开）。
3. **仍存在的覆盖缺口（本仓口径）**：若要把每类的数据模式从 10 组扩到 20 组以上，还可继续加密，本次未做——每行都要独立编译 + 独立 difftest，224 行在 `--time=02:00:00` 内的实际墙钟为 **1:39:49**（作业 `127194011`，见 §4.12.4）。

---

## A. 4.12.3 期望值来源：全部由金模型生成（可机械复核）

本节要求「期望值全部由 `design/verify/vdot_model.py` 金模型生成」。落实方式是**生成期烧常量 + 事后机械复核**两道：

1. **生成期**：`design/verify/cases/gen_extra.py` 逐条重放用例的指令序列，每遇 `vdot` 就调 `M.vdot_vv(vs1_reg, vs2_reg)` 取完整 128 位 `vd`，把低 32 位写成 C 里的断言常量（`if (got[i] != 0x........u)`）。生成器里**没有第二套点积实现**。
2. **事后复核**：`design/verify/cases/extra_crosscheck.py` 从 `.c` 源解析 `//@OP` 注释重新重放一遍，与源里**实际烧进去的常量**逐条比对；同时用 `M.decode_vdot_vv()` 反解每条 `vdot` 的机器码，确认 `(vd, vs2, vs1)` 与注释一致。

复核实跑（**本轮本地实跑**；昆山侧的同一脚本由 `94-run-extra.sh` 的 `golden_crosscheck` 判据承担，JSON 记 `EXTRA_CROSSCHECK verdict=MATCH`）：

```
$ python3 -I design/verify/cases/extra_crosscheck.py --quiet
EXTRA_CROSSCHECK cases=224 reads_or_groups=10357 vdot_encs=415 problems=0
EXTRA_CROSSCHECK verdict=MATCH（全部期望常量与金模型逐条一致）
EXIT=0
```

- `reads_or_groups=10357` = `vdot_rand10k` 的 10000 组 + 其余 223 例的 357 个断言读点（10357−10000=357，224−1=223；脚本只打印合计数，逐例分解本轮未打印）；`vdot_encs=415` = 清单里 `vdot.vv` 机器码的条数（含被 `jal` 跳过的边角条目）。上一轮 129 例的历史读数为 `10162 / 191`，只作历史对照。
- **负例不靠期望值**：57 个 `negative` 行的判据是「DUT/NEMU 双侧一致陷入非法」，由 `M.illegal_reasons()` 在复核阶段确认「该状态在模型里确实非法」（`extra_crosscheck.py` 的 `check_negative()`），运行时判据是 difftest 日志的 `HIT CRITICAL ERROR`；本轮 JSON `negatives_illegal=达标（57/57）`。
- **`vdot_rand10k` 的双算**：镜像里 `want10k[]` 由金模型生成；C 侧再用算法 B（`long long` 逐项累加）独立复算一遍并比对，不一致就打 `model_bad`。这样「Python 的 LCG 流」与「C 的 LCG 流」一旦分叉，`model_bad>0` 立刻判负，不会出现「DUT 与期望同时错」的假通过。

**G0 反例（假通过的机械证明）**：2 行 `g0` 的期望常量被**故意异或 1 bit**，程序仍正常走到结尾（`HIT GOOD TRAP`），因此只能被「自检串」判据抓住——日志必须出现 `CASE <cid>: MISMATCH` 且**不得**出现 `CASE <cid>: MATCH`。`94-run-extra.sh` 对 `g0` 类单独走这条判据并把 `G0_CAUGHT` 计入 `no_empty_green`。若某次 `G0_REQ>0` 而 `G0_CAUGHT<G0_REQ`，整套判「未达标」。

---

## A. 4.12.4 昆山实跑结果（逐行 status）

> 本节数字**只写本轮实读到的**。作业号、`cases.tsv` 路径与逐类计数在下表；未跑完的格子写「未运行」。

**作业（当前终态，2026-11-08）**：`127194011`（`P3-full`，分区 `kshcnormal`，宿主 `a07r1n09`，清单 `/public/home/scnsokdzoq/core/vdot-254/manifests/manifest.full.tsv`，`rows=224`、远端 `sha256 ad787baa…`），`started_at=2026-11-08T01:44:45+0800` → `ended_at=03:24:34+0800` ⇒ 墙钟 **1:39:49**；JSON `status=通过`、`counters={selected:224, executed:224, pass:224, not_run:0, reg_size_bad:0, selfcheck_req:162, selfcheck_ok:162, g0_req:2, g0_caught:2, neg_req:57, neg_ok:57}`；8/8 criteria `达标`（含 `golden_crosscheck=达标 :: EXTRA_CROSSCHECK verdict=MATCH`、`no_empty_green=达标`（自检串 162/162、G0 捕获 2/2）、`negatives_illegal=达标（57/57）`）。**证据边界（如实记）**：逐例日志与 `.cases.tsv` 留在远端 `…/vdot-254/results/difftest/extra/94-extra-20261108T014445.{log,cases.tsv}`，**本地只回传了 JSON**（`out/audit/final/94-extra-20261108T014445.json`）⇒ 逐类「通过」数按 `selected=executed=pass=224` 与该类行数推得，**不是逐行读 `cases.tsv`**；自检串 162/162、G0 2/2、负例 57/57 取自 JSON `criteria[].actual`，不是本地 grep 日志。

**同轮提交的 30 例整份 `--full` 未跑通**：提交 exit=1，但 `find results -name '*20261108*'` 只命中 `results/difftest/perf-repeat/`、**零份 30 例产物**，`sacct -S 2026-11-08T00:00` 亦无对应 full 作业 ⇒ 记【未运行（无产物）】；30/30 仍以历史作业 `126676734`（`142246`）/ `127137638`（`104227`）为准，**不因本轮 extra 通过而更新**。

| 分类 | 行数 | 通过 | 未通过 | 未运行 |
|---|---|---|---|---|
| `vdot-base` | 7 | 7 | 0 | 0 |
| `vdot-ov` | 56 | 56 | 0 | 0 |
| `vdot-pl` | 98 | 98 | 0 | 0 |
| `negative` | 57 | 57 | 0 | 0 |
| `negative-legal` | 3 | 3 | 0 | 0 |
| `g0` | 2 | 2 | 0 | 0 |
| `vdot-rand10k` | 1 | 1 | 0 | 0 |
| **合计** | **224** | **224** | **0** | **0** |

**上一轮（2026-11-06，129 例，历史记录）**：作业 `127031933`（`-p kshcnormal -N 1 -n 32 --time=02:00:00`，脚本 `core-package/scripts/94-run-extra.sh --manifest ~/core/test/manifest.extra.abs.tsv --timeout 600`），`COMPLETED`、`Elapsed=01:32:48`；`status=通过`、`cases_pass=129/129`、8/8 criteria（自检串 86/86、G0 2/2、负例 41/41）。该轮逐类计数（`vdot-ov` 30 / `vdot-pl` 48 / `negative` 41 等）只对 129 例清单成立，**已被 224 例取代，不作现行规模**。
**被取消的前序作业（如实记）**：`127028127`（129 例全套，跑到第 50 例时被 `CANCELLED by 276820`，作业内 50/50 全通过）与 `127030078`（单跑 rand10k，3 分钟后同样被取消）。两次取消都发生在 14:26:03，同一账号下其它并行作业（`127029615`/`127030411` 等）也在同一分钟被取消 ⇒ 属**账号级并发回收**，与本用例无关；本次不把取消原因归给用例，也不把中途结果计入通过数。

**冒烟测试（暴露并修复三个真实问题，如实记录）**：作业 `127026020`（6 例冒烟）判 `失败 3/6`，暴露：
- `xn_sew_e16` 负例**根本没构造非法状态**（生成器 `emit_negative()` 读的是 `n["extra"]` 而不是 `n["pre"]`，状态序列为空）⇒ 哨兵串出现、`CRIT=0`。修复：改为遍历 `n["pre"]`。
- `xg0_overlap` 判 `GOOD=0 BAD=1`——G0 用例 `return 1` 导致 `HIT BAD TRAP`，判负原因退化成 BAD TRAP 而非「自检串未命中」。修复：G0 类统一 `return 0`（先例 `design/verify/cases/vdot_g0_badexp.c:38`）。
- `vdot_rand10k` `rc=124`（900 s 单例上限不够）。修复：`94-run-extra.sh` 给随机类单独 `RAND_TIMEOUT_S=5400`，且**不**参与「剩余时间/剩余用例数」均分（均分会把它压到几十秒）。
- 另：`golden_crosscheck` 初次报「缺 `spec.extra.json`」——上传包漏了该文件与 `.c` 源。已补传，昆山侧 `EXTRA_CROSSCHECK verdict=MATCH`。

---

## A. 4.12.5 工程形态与可复现

| 件 | 路径 | 作用 |
|---|---|---|
| 生成器 | `design/verify/cases/gen_extra.py` | 224 份 `.c` + `manifest.extra.tsv` + `cover.extra.tsv` + `extra/spec.extra.json`；生成期即做配额自检（`--check` 只打印不写盘） |
| 构建 | `design/verify/cases/build_extra.sh` | 逐例 AM 构建（`ARCH=riscv64-xs`），最后按清单核对产物齐备（**新增 95 例的 `.bin` 本轮未取回本地**，本地 `extra/*.bin` 仍 129 个） |
| 期望值复核 | `design/verify/cases/extra_crosscheck.py` | 金模型重放 + 机器码反解 + G0 错 1 bit 校验 |
| 运行 | `core-package/scripts/94-run-extra.sh` | 走 extra 清单的独立 difftest 作业（判据与 `20-run-difftest.sh` 逐条同构，**不改后者**） |
| 覆盖点表 | `design/verify/cases/cover.extra.tsv` | 每行 `cid / cls / family / 规范锚点 / 说明`，供本节表格机械汇总 |
| 用例清单 | `design/verify/cases/manifest.extra.tsv` | **224 条**用例及分类（本表数据来源；本地 `sha256 9e72b97b…`） |

复现三条命令（本地构建 → 昆山实跑 → 逐行取状态；`<runid>` 本轮为 `20261108T014445`）：

```
AM_HOME=<nexus-am> CROSS_COMPILE=riscv64-unknown-elf- bash design/verify/cases/build_extra.sh
sbatch -p kshcnormal -N 1 -n 32 --time=02:00:00 core-package/scripts/94-run-extra.sh \
       --manifest $HOME/core/test/manifest.extra.abs.tsv --timeout 600
awk -F'\t' '{n[$2]++; if($3=="通过") p[$2]++} END{for(k in n) printf "%s %d/%d\n", k, p[k], n[k]}' \
    results/difftest/extra/94-extra-20261108T014445.cases.tsv
```

**未做与边界（不作达标声明）**：
- 覆盖缺口只按本仓分类披露（异常 57 行、重叠 56 行、流水/依赖 98 行，见 §4.12.2），不引用外部清单条数作对照。
- 本节只作本仓覆盖规模说明，不作跨实现优劣结论。
- `manifest.extra.tsv` 的 224 行**不进** 30 例官方回归清单，也不参与 `regression_delta`（该判据的基线是 `results/difftest/baseline.tsv` 的 30 行）。
- 机时（本轮）：作业 `127194011` 的 `started_at`→`ended_at` 实算墙钟 **1:39:49（=1.664 h，1 节点）**；**远端 `90-budget-log.sh` 台账本轮未读取【未运行】**，故只写墙钟、不写「已入账 X node-h」；按上一轮同口径（32 核 × 5557 s ⇒ 1.544 node-h）折算，若本轮核数同为 32 则约 1.664 node-h —— 该折算**依赖未核实的核数**，只作量级参考。上一轮（历史）：`127031933` 由 `90-budget-log.sh auto` 记 `1.544 node-h`。