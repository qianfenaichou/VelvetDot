# 1.2 操作日志（从装依赖到跑通的时间线）

**结论：`results/` 下 18 份带时间戳的 `.log` 已全部复制入本目录 `raw/`（逐份 sha256 与原件一致），按运行时刻排序汇编为下面的时间线；装依赖阶段（2026-11-01）只留下 JSON 而无 `.log`，故该段以 JSON 的 `started_at/ended_at/criteria` 复述并标注来源，不冒充日志。**

> 交付物编号：官方 1.2（`docx/02-赛题与评分细则.md:46`：完整的开发环境部署与操作过程日志）
> 覆盖范围：2026-11-01 15:02（首次环境探测）→ 2026-11-03 08:05（T5 四例全通过）
> 平台：华东一区【昆山】超算，分区 `kshcnormal`，账号 `<account>`，工作根 `/public/home/<account>/core`（账号以占位符表示，原值见 `raw/` 日志原件）
> 打包日期：2026-11-03

---

## 1. 汇编方法与口径（先读这里）

- **原料**：`find results -name '*.log'` 命中 **18** 份（`results/{env,emu,difftest}/`），全部 `cp -p` 进 `raw/`，未改名、未清洗、未截断。逐份 `sha256sum` 与原件比对 → **18/18 一致**。
- **排序键**：优先用日志内嵌时间戳 `[YYYY-MM-DD HH:MM:SS]`（脚本自写的行首时间）；emu 原始输出（`10-smoke-*`、`perf_*`、`vdot_mix.*`、`vdot_g0_badexp.*`）**没有内嵌时间戳**，按文件名里的 `<runid>` 归属到其父作业，再按父作业的运行时刻排序。
- **两个时间要分清**：
  - `运行时刻` = 日志内嵌时间戳（远程作业真实执行时间）；
  - `本地落盘 mtime` = 文件被 `scp` 取回本工作区的时间，**晚于**运行时刻（11-03 的 16 份落盘于 05:56–08:14，而作业在 03:20–08:05 跑完）。两者不可混为一谈。
- **未覆盖（如实标注）**：11-01 的 env/build/formal/area 运行只有 JSON（`.log` 未被回传，见 §4）；11-03 的交叉工具链修复过程（xpack 13.2.0 下载、`patchelf` 改 interpreter、glibc 2.35 loader、`~/tools/env.sh` 追加 PATH、`build_all.sh` 重建 31 个用例镜像 + 4 个 perf 镜像、`scp` 40 个 bin 上传）**不在任何 `results/*.log` 里**：§3 第 6 条只概述了工具链切换一段（xpack + `patchelf` + glibc loader），`env.sh` 追加 PATH、`build_all.sh` 重建、`scp` 上传三步既无概述也无日志，本时间线不将其作为日志证据。

## 2. 时间线（按运行时刻升序）

| # | 运行时刻（起→止） | 日志（`raw/` 内） | 作业号 | 做了什么 | 结果（原文判据行） |
|---|---|---|---|---|---|
| — | 11-01 15:02:22 → 15:11:18 | **无 .log**（仅 JSON） | 126523888 | 环境探测 → 取工具 → 装工具 | 见 §4.1：`install` **失败**（verilator/yosys/riscv 工具链缺失、java 8） |
| — | 11-01 17:45:37 → 19:59:01 | **无 .log**（仅 JSON） | 126530785…126534905 | emu 构建 7 连跑（6 败 1 成） | 见 §4.2：第 7 次 `126534905` **通过**（`microbench(fallback)`） |
| — | 11-01 20:24:37 → 21:06:14 | **无 .log**（仅 JSON） | 126536502 / 126536746 / 126537392 | difftest 冒烟 3 连跑 | 见 §4.3：前两次 `失败`（负例「空绿风险」），第 3 次 **通过 13/13** |
| — | 11-01 21:07:24 → 21:54:27 | **无 .log**（仅 JSON） | 126537629…126538478 | 形式 miter 5 连跑 | 见 §4.4：4 次 `失败`（miter 空转），`126538478` **通过**（prove=SUCCESS / mutant=FAIL） |
| — | 11-01 21:07:31 → 21:17:56 | **无 .log**（仅 JSON） | 126537633 / 126537819 | Yosys 面积 2 连跑 | 见 §4.4：第 1 次解析失败，第 2 次 **通过**（`vmac_only + VdotReduce`） |
| — | 11-01 21:58:44 → 22:17:10 | **无 .log**（仅 JSON） | 126538633 | emu 构建 + hello 冒烟 | 见 §4.5：**通过**，`smoke_image=hello:hello-riscv64-xs.bin`、`hello_evidence=yes` |
| 1 | 11-02 00:05:17 → 00:26:28 | `20-full-20261102T000517.log` | 126542079 | difftest 全量 20 例 | `判据：达标（20/20）`，`status=通过`；metrics `L_vdot=6 / T_steady=1 / T_kernel=289 / B1=6 / B2=9` |
| 2 | 11-02 00:31:37 → 00:31:48 | `00-env-20261102T003137.log` | —（登录节点直跑） | 环境复测 `--probe` | `判据：存在未达标项（probe 模式尚未安装）`；verilator 5.053 / yosys 0.48 / mill 0.12.3 / JDK17 转 `达标`，`riscv_toolchain` 仍 `MISSING` |
| 3 | 11-03 03:20:17 → 03:21:22 | `20-smoke-20261103T032017.log` | 126630485 | 冒烟：单例 `vdot_mix` | `判据：存在未运行项（1/1…）`；用例 `MIX verdict=ALL_OK` 通过，但 `smoke_classes`/`no_empty_green` 记未运行 |
| 4 | 11-03 03:23:07 → 03:24:06 | `10-build-20261103T032307.log` | 126630755 | emu 构建 + **1.1 hello 身份冒烟** | `判据：构建与冒烟达标（镜像标签=hello:hello_identity.bin）`；`status=通过` |
| 5 | （同作业 4 的 emu 原始输出） | `10-smoke-20261103T032307.log` | 126630755 | 上一行的冒烟 stdout 全文 | 第 3 行身份串；第 29847 行 `HIT GOOD TRAP at pc = 0x8000015c`；host 17,449 ms |
| 6 | 11-03 03:23:37 → 03:28:36 | `20-smoke-20261103T032337.log` | 126630806 | 冒烟：5 例（vadd/pos1/neg1/bound1/mix） | `判据：未达标（5/5）`：**5 例全过，但 `nm_exec_vdot` 命中 0 行 → 整体判失败** |
| 7 | （同作业 6 的用例 stdout） | `vdot_mix.20261103T032337.log` | 126630806 | `vdot_mix` 用例 emu 输出 | `MIX verdict=ALL_OK fails=0`（第 10 行） |
| 8 | 11-03 03:33:28 → 03:42:42 | `20-full-20261103T033328.log` | 126631414 | T5 三链 perf（3 例） | `判据：存在未运行项（3/3…）`；`L_vadd=3 / L_vmacc=4 / L_vdot=4`、`T_steady=1`、`T_kernel=290` |
| 9 | （同作业 8 的用例 stdout） | `perf_vadd.20261103T033328.log` | 126631414 | vadd 延迟链 | `PERF_VADD verdict=ALL_OK`（第 10 行）；`L_vadd median=3` |
| 10 | （同作业 8） | `perf_vmacc.20261103T033328.log` | 126631414 | vmacc 延迟链 | `PERF_VMACC verdict=ALL_OK`（第 10 行）；`L_vmacc median=4` |
| 11 | （同作业 8） | `perf_vdot.20261103T033328.log` | 126631414 | vdot 三口径 | `PERF_VDOT verdict=ALL_OK`（第 15 行）；`enc_check=0x3A20A1D7` 一致；`T_steady=1`、`T_kernel=290` |
| 12 | 11-03 06:24:32 → 06:32:22 | `20-full-20261103T062432.log` | 126642005 | R13 专项 6 例 | `判据：存在未运行项（6/6…）`；6/6 通过、`no_empty_green=达标`（G0 捕获 1/1） |
| 13 | （同作业 12 的用例 stdout） | `vdot_mix.20261103T062432.log` | 126642005 | `vdot_mix` 用例 emu 输出 | `MIX verdict=ALL_OK fails=0`；`hi96_bad=0` |
| 14 | 11-03 07:55:52 → 08:05:54 | `20-full-20261103T075552.log` | 126646321 | T5 + G0 4 例 | `判据：达标（4/4）`；`status=通过`；`t5_delta_latency=达标` |
| 15 | （同作业 14） | `perf_vadd.20261103T075552.log` | 126646321 | vadd 延迟链（复跑） | `PERF_VADD verdict=ALL_OK`；`L_vadd median=3` |
| 16 | （同作业 14） | `perf_vmacc.20261103T075552.log` | 126646321 | vmacc 延迟链（复跑） | `PERF_VMACC verdict=ALL_OK`；`L_vmacc median=4` |
| 17 | （同作业 14） | `perf_vdot.20261103T075552.log` | 126646321 | vdot 三口径（复跑） | `PERF_VDOT verdict=ALL_OK`；`L_vdot median=4`、`T_steady=1`、`T_kernel=290` |
| 18 | （同作业 14） | `vdot_g0_badexp.20261103T075552.log` | 126646321 | G0 反例（期望值被故意改错） | `CASE vdot_g0_badexp: MISMATCH`（第 4 行）+ `HIT GOOD TRAP` ⇒ **防空绿判据被证伪成功** |

> 第 1 行的「11-02 20/20」用的是**旧口径**（旧 VL=16 镜像、旧 20 例清单），**不能直接引用**；当前口径数来自第 8/14–17 行（`L_vdot=4`、`T_kernel=290`）。

## 3. 阶段小结（这条线为什么这么长）

1. **装依赖（11-01 15:02–15:11）**：平台自带 gcc 13.3 / cmake 3.25 / make 4.2.1 / python 3.8 / git，但 **java 8、无 verilator、无 yosys、无 RISC-V 交叉工具链** → `00-env-check.sh --install` 失败。
2. **装工具（11-01 17:45–21:54）**：6 次 emu 构建失败 → 第 7 次成（仍只有 `microbench` 兜底镜像）；冒烟前两次因负例「空绿风险」判失败 → 第 3 次 13/13；形式 4 次 miter 空转 → 第 5 次正反例双达标；面积第 1 次解析失败 → 第 2 次达标。**这一段只有 JSON，无 `.log`**。
3. **首次 hello（11-01 21:58）**：`126538633` 首次带 `hello-riscv64-xs.bin` 冒烟，`hello_evidence=yes`（但当时身份串判据只 grep `Hello,`，不是官方 1.1 格式）。
4. **全量绿（11-02 00:05）**：20/20 通过，三口径齐备（旧 VL=16 口径）。
5. **镜像口径升级（11-02 白天–11-03 凌晨，本地侧）**：VL=16→8、均值→median、清单 20→30 行、新增 `vdot_mix`/`perf_vadd`/`perf_vmacc` 等，全部本地重编后 `scp` 上传；**此段无 `results/*.log`**。
6. **工具链崩溃与重建（11-03 凌晨，本地+远程侧）**：站点 CentOS 7.6 / glibc 2.17 跑不了随附 `riscv-toolchain.tar.gz`（要求 GLIBC 2.38，`--version` 段错误 139）→ 改 xpack `riscv-none-elf-gcc 13.2.0` + 静态 `patchelf` 改 9 个 ELF 的 interpreter 到 glibc 2.35 loader。**该过程没有 `.log` 留存**。
7. **取回当前口径三证（11-03 03:20–08:05）**：1.1 身份串（#4/#5）、R13 交叉污染（#12/#13）、T5 三链 + G0 反例（#14–#18）全部跑出；中间 #6 因 `nm` 撞上 `.so` 重写窗口误判失败。

## 4. 只有 JSON、没有 `.log` 的运行（`results/` 原件路径）

> 本节内容**来自 JSON 的 `started_at`/`ended_at`/`status`/`criteria`，不是日志**。JSON 在本工作区 `results/{env,emu,formal,yosys}/`，未复制进本目录。

### 4.1 环境（`results/env/`）
- `00-env-20261101T150222.json`｜15:02:22→15:02:25｜`probe`｜`未运行`：verilator/yosys/mill 缺失、java 8、`riscv_toolchain` MISSING。
- `00-env-20261101T150244.json`｜15:02:44→15:07:37｜`fetch`｜`未运行`：同上。
- `00-env-20261101T151045.json`｜15:10:45→15:11:18｜`install`｜**`失败`**｜job `126523888`：verilator/yosys 仍 MISSING、`java_version` major=8（要求 ≥11）、`riscv_toolchain` MISSING。

### 4.2 emu 构建（`results/emu/`，11-01）
| JSON | 起→止 | job | status | 关键 criteria |
|---|---|---|---|---|
| `10-build-20261101T174537.json` | 17:45:37→17:46:25 | 126530785 | 失败 | `version_pin=警告(unknown)`、`nemu_ref_so=未达标`、`build_emu=未达标 rc=2` |
| `10-build-20261101T175916.json` | 17:59:16→18:07:30 | 126531156 | 失败 | `build_emu=未达标 rc=2`（`nm_exec_vdot=警告 0 行`） |
| `10-build-20261101T182026.json` | 18:20:26→18:47:06 | 126531659 | 失败 | 同上 |
| `10-build-20261101T185442.json` | 18:54:42→19:21:49 | 126533246 | 失败 | `nm_exec_vdot=达标 2 行`，但 `build_emu=未达标 rc=2` |
| `10-build-20261101T192747.json` | 19:27:47→19:28:20 | 126534603 | 失败 | 同上 |
| `10-build-20261101T193131.json` | 19:31:31→19:32:22 | 126534740 | 失败 | 同上 |
| `10-build-20261101T193750.json` | 19:37:50→19:59:01 | 126534905 | **通过** | `build_emu=达标 rc=0`、`smoke_good_trap=达标`、`smoke_hello_identity=不适用（microbench(fallback)）` |

### 4.3 difftest 冒烟（11-01）
- `20-smoke-20261101T202437.json`｜20:24:37→20:29:40｜126536502｜**失败**｜`cases_pass=9/12`；失败 3 例 `vdot_ill_sew` / `vdot_ill_lmul` / `vdot_ill_lmul8`，状态原文 `失败(空绿风险)`（GOOD TRAP 但自检未判负）。
- `20-smoke-20261101T203515.json`｜20:35:15→20:41:16｜126536746｜**失败**｜`cases_pass=9/13`；失败 4 例（多 `vdot_ill_vs`），同样 `失败(空绿风险)`。
- `20-smoke-20261101T205850.json`｜20:58:50→21:06:14｜126537392｜**通过**｜13/13。

### 4.4 形式与面积（11-01，`results/formal/`、`results/yosys/`）
- miter `50-miter-20261101T205852` 未运行（无 yosys）；`…T210724`/`T211658`/`T211909`/`T212219` 四次 **失败**（`miter_prove=未达标 未出现 SUCCESS`、`miter_mutant=未达标 未出现 FAIL`）；`50-miter-20261101T215106`｜21:51:06→21:54:27｜126538478｜**通过**（prove=SUCCESS、mutant=FAIL）。
- 面积 `40-area-20261101T210731` 失败（`two_tops=未达标`）；`40-area-20261101T211702`｜21:17:02→21:17:56｜126537819｜**通过**（`vmac_only + VdotReduce`）。

### 4.5 首次 hello 构建（11-01）
- `10-build-20261101T215844.json`｜21:58:44→22:17:10｜126538633｜**通过**｜`smoke_image=hello:hello-riscv64-xs.bin`、`hello_evidence=yes`、`smoke_hello_identity=达标`（当时判据只认 `Hello,` 串，非官方 1.1 身份串格式）。

### 4.6 其它 difftest JSON（11-01 三次 `20-full`，`.log` 未回传）
- `20-full-20261101T215707.json`、`20-full-20261101T232357.json`、`20-full-20261101T234136.json`：均**不是合法 JSON**（`json.load` 报 `Invalid control character`），故本时间线不引用其内容。

## 5. 附件（Slurm stdout，`results/difftest/*.out`，未复制进 `raw/`）

6 份 `.out` 是作业 stdout，比脚本自写日志多出 `make` 子命令回显：

| 文件 | 对应作业 | 与脚本日志比对（本机 `diff -q`） |
|---|---|---|
| `126630485_t3_mix.out` | 126630485 | 与 `20-smoke-20261103T032017.log` **完全相同** |
| `126630755_t4_hello.out` | 126630755 | 比 `10-build-20261103T032307.log` 多 16 行（`make` 进入/离开目录、`+ g++` 等），末尾判据行相同 |
| `126630806_t3_mix_smoke.out` | 126630806 | 与 `20-smoke-20261103T032337.log` **完全相同** |
| `126631414_t5_perf3.out` | 126631414 | 与 `20-full-20261103T033328.log` **完全相同** |
| `126642005_t3b_r13_full.out` | 126642005 | 与 `20-full-20261103T062432.log` **完全相同** |
| `126646321_t5_t5g0.out` | 126646321 | 与 `20-full-20261103T075552.log` **完全相同** |

## 6. 打包时实跑的命令与输出

```
$ find results -type f -name '*.log' | wc -l
18
$ for f in $(find results -name '*.log'); do b=$(basename $f); a=$(sha256sum "$f"|cut -d' ' -f1); \
    c=$(sha256sum "stage1/1.2-log/raw/$b"|cut -d' ' -f1); [ "$a" = "$c" ] && echo "OK   $b" || echo "DIFF $b"; done
# 输出 18 行全 OK，无 DIFF
```

## 7. 已知缺口（如实记录）

1. **11-01 全部运行无 `.log`**：只有 JSON，且其中 3 份 `20-full` JSON 语法非法（见 §4.6）。因此「装依赖」段的证据强度低于 11-03 段。
2. **11-03 工具链修复过程无 `.log`**：xpack 下载、`patchelf` 改 interpreter、glibc loader 软链、`build_all.sh` 重建、`scp` 上传均无 `.log` 留存。若要补，需把远程 `~/tmpwork/*.log` 取回。
3. **`raw/10-build-20261103T032307.json` 非法 JSON**（裸 CR，`line 24 column 177`），本目录按原样保留未修（详见 `stage1/1.1-env/README.md` §6）。
4. **本目录不构成「录屏」**：官方提交形式要求录屏，对应目录 `stage1/videos/` 截至 2026-11-04 未产出。
