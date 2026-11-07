# vdot.vv 算法验证包 · 运行手册（README）

> **状态：2026-11-07 交付快照。** 各脚本的实跑记录见其头注与 `results/*.json`；未产出 JSON 的项记「未运行」。下面未注明已执行的命令仍是待执行模板。
>
> 部署目标：昆山 `/public/home/$USER/core`（唯一可写共享位置）。

---

## 0. 三条红线（先读再看命令）

1. **登录节点禁跑重计算。** 站点 `/etc/motd`：*「登录节点用于编译和编辑工作，请勿在登录节点直接运行程序」*；会话 cpuset 只有 2 核。登录节点只允许：`module` / `which` / 读写文件 / `sbatch` 提交。`10/20/40/50` 以及 `00` 的安装段在脚本里硬性检查 `SLURM_JOB_ID`，没有就退出码 3。
2. **必须显式 `-p`**：集群 4 个分区全无默认值，CPU 作业一律 `-p kshcnormal`。
3. **禁止写 `--qos=`**（分区自带 QOS，显式指定报 `Invalid qos specification`）。DCU 分区才需要 `--gres=dcu:N`，**当前交付不排 DCU**。

另：**不写 `/work`、`/work1`、`/public/share`**（不可写）；所有脚本的 `guard_path()` 会拒绝这三个前缀。

**实施开跑顺序（照此走，不要跳步）**：`00 → 10 →（RTL/NEMU 侧实现完成后）20 → 30 → 40/50 → 20 --full`。每步先看 `results/<area>/*.json` 的 `status`，非「通过」不进下一步。

---

## 1. 落位（一次性，是 §3 全部远端命令的前置）

> 完成判据（落位后立即执行，可复跑）：`ssh kunshan 'test -f /public/home/$USER/core/scripts/00-env-check.sh'` 返回 0。当前远端 `core/` 已按 `core-package/` 布局存在（`~/core/core-package/scripts/`，见下文布局说明），扁平布局 `~/core/scripts/` 尚未创建，下面的命令用于建立扁平布局。

在本地工作区执行（只用到 SSH 别名，不涉及任何密钥内容）：

```sh
# 1) 建远端 core 目录（探测时不存在）
ssh kunshan 'mkdir -p /public/home/$USER/core'

# 2) 落位验证包（core-package/ 的内容 → core/）
rsync -av core-package/ kunshan:/public/home/$USER/core/

# 3) 建产物/日志目录（sbatch 的 -o 要求目录先存在；逐个列出，不依赖远端 shell 的 brace expansion）
ssh kunshan 'mkdir -p /public/home/$USER/core/results/logs \
                          /public/home/$USER/core/results/env \
                          /public/home/$USER/core/results/emu \
                          /public/home/$USER/core/results/difftest/cases \
                          /public/home/$USER/core/results/golden \
                          /public/home/$USER/core/results/yosys \
                          /public/home/$USER/core/results/formal'

# 4) 授权
ssh kunshan 'chmod +x /public/home/$USER/core/scripts/*.sh'

# 5) 完成判据（返回 0 才算落位完成）
ssh kunshan 'test -f /public/home/$USER/core/scripts/00-env-check.sh'
```

源码树（可选，`10` 和 `20` 的构建步骤需要）：

```sh
# 从本地工作区把香山 / NEMU 源树同步到 core/src（保留 .git：mill 的 VcsVersion 依赖它）
rsync -av --exclude build --exclude target --exclude .bloop \
      repos/XiangShan kunshan:/public/home/$USER/core/src/
rsync -av --exclude build --exclude target \
      repos/NEMU kunshan:/public/home/$USER/core/src/

# 子模块必须在登录节点初始化（登录节点外网实测可达；计算节点外网未探测，不能留到作业里做）
ssh kunshan 'make -C /public/home/$USER/core/src/XiangShan init'
# 完成判据：关键文件存在（rocket-chip/cde 与 hardfloat 不能是空目录）
ssh kunshan 'test -f /public/home/$USER/core/src/XiangShan/rocket-chip/cde/build.sc \
          && test -f /public/home/$USER/core/src/XiangShan/rocket-chip/hardfloat/build.sc'
```

> 若外网可用，也可以在计算节点用 `git clone` 直接拉取 `a4eeaab` / `a683e0b`；但**计算节点外网未探测**，所以默认走同步。

落位后目录：

```
core/
├── README.md
├── scripts/00-env-check.sh … 90-budget-log.sh   # 含 25-rtl-lint.sh（2.2 verilator --lint-only）、30-hello-nodeip.sh（1.1 节点 IP 重建）、91-run-b3.sh（B3/基线链）
├── verify/vdot_model.py  vdot_model_test.py  json_sanitize.py
├── src/XiangShan/  src/NEMU/            # 可选
└── results/                             # 产物，脚本自建子目录
```

> **落位路径有两种，脚本都能认**（2026-11-04 实测修）：① 昆山**实际**布局是 `~/core/core-package/scripts/`
> （验证包整体落位；作业 `126681977` 的提交行也是
> `core-package/scripts/10-build-emu.sh`）；② 本节 §1 的 `rsync -av core-package/ …:core/` 命令
> 产出的是**扁平**布局 `~/core/scripts/`。`scripts/` 下各脚本的 EXIT trap 现在按
> `$CORE_DIR/core-package/scripts/90-budget-log.sh` → `$CORE_DIR/scripts/90-budget-log.sh` →
> 与脚本同目录 三处依次探测（`[ -x ]` 判定），机时记账在两种布局下都能落盘。
> 旧写法只探第 ② 处 ⇒ 昆山布局下**恒不命中 ⇒ auto 记账从未落盘**（已修，见 §7 第 13 条）。

---

## 2. 每次登录后的环境准备

```sh
cd /public/home/$USER/core

# 模块必须裸写（不要接管道——截断 module 的输出会导致静默加载失败）
module load compiler/gcc/13.3.0
module load compiler/cmake/3.25.0
module load apps/python/3.8.13
hash -r                                  # 否则 bash 仍命中旧路径缓存（:451）

# 工具安装后的 PATH（00 --install 会写这个文件）
[ -f "$HOME/tools/env.sh" ] && . "$HOME/tools/env.sh"

gcc --version | head -1        # 期望 13.3.0
cmake --version | head -1      # 期望 3.25.0
python3 -V                     # 期望 3.8.13
```

> `module purge` **无效**（站点在 `/etc/profile.d` 强制预加载 devtoolset-7 + hpcx + dtk-22.10.1）。gcc 13 编 C++20 若报 `__int_traits` 相关错误，用 `env -u CPLUS_INCLUDE_PATH -u C_INCLUDE_PATH`。

---

## 3. sbatch 模板（提交命令统一格式）

```sh
sbatch -p kshcnormal -N 1 -n 32 --time=<HH:MM:SS> <脚本> [脚本参数]
```

带输出重定向与作业名的完整版：

```sh
sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 \
       -J vdot-emu -o results/logs/%x-%j.out -e results/logs/%x-%j.err \
       scripts/10-build-emu.sh --src-root "$PWD/src"
```

逐项模板（`--time` 一律 ≤ 该项预算，见 §6；提交前可先跑 `90-budget-log.sh check-submit --item <键> --time <HH:MM:SS>`）：

| 验证项 | 提交命令 | 时限（= 预算上限） |
|---|---|---|
| P0-1 环境 | `sbatch -p kshcnormal -N 1 -n 32 --time=02:00:00 scripts/00-env-check.sh --install` | 2:00 |
| P0-2 emu 构建 | `sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 scripts/10-build-emu.sh --src-root "$PWD/src"` | 3:00 |
| P0-3 difftest 冒烟 | `sbatch -p kshcnormal -N 1 -n 32 --time=01:00:00 scripts/20-run-difftest.sh --smoke --write-baseline` | 1:00 |
| P1 金模型 | `sbatch -p kshcnormal -N 1 -n 2 --time=00:06:00 scripts/30-golden-regress.sh` | 0:06（预算 0.1） |
| P2-1 面积 | `sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 scripts/40-yosys-area.sh` | 0:45 |
| P2-2 形式 | `sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 scripts/50-formal-miter.sh` | 0:45 |
| 2.2 lint | `sbatch -p kshcnormal -N 1 -n 4 --time=00:15:00 core-package/scripts/25-rtl-lint.sh --rtl-dir "$CORE_DIR/src/XiangShan/build/rtl"` | 0:15 |
| P3 全量 | `sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 scripts/20-run-difftest.sh --full` | 3:00 |

> 全部 `--time` 上限之和 = 2.0+3.0+1.0+0.1+0.75+0.75+0.25+3.0 = **10.85 机时** ≤ 总额 11.0，但**超出「不含缓冲」的 10.6 上限 0.25** ⇒ 这 0.25 只能从缓冲（0.4）里出，缓冲剩余 0.15。
> 归口：2.2 lint 的 0.25 记在 `P2-yosys-formal` 类目下，而该类预算 1.5 已被面积 0.75 + 形式 0.75 占满 ⇒ 上限口径上**超 0.25**；实测 lint 仅耗 0.008 node-h（`results/budget-log.tsv` 的 `126761068` 行；严格模式 `126797720`/`126798101` 另计 0.002 node-h），实际未挤占。

> **基线口径**：P0-3 的 `--write-baseline` 在全部用例执行后写 `results/difftest/baseline.tsv`，P3 的 `--full` 与之单遍对比即可得 `regression_delta`——无需跑两遍 `--full`（两遍 6.0 机时会超预算）。`--dry-run` 一律不写基线（防空跑污染）。

> 显式 `--mem=120G` 是可选的：`DefMemPerCPU=3500`，`-n 32` 默认已拿到约 112 GB；emu 构建若因内存被杀，再补 `--mem=120G`。

**DCU（当前交付不排，留作后续算法优化实验）**

```sh
sbatch -p kshdnormal -N 1 -n 8 --gres=dcu:1 --time=00:45:00 <脚本>   # 缺 --gres 会被 QOS 拒绝
```

---

## 4. 逐脚本用法

所有脚本都支持 `--help`；未识别参数退出码 3。统一退出码：**0 达标 / 1 未达标 / 2 前置缺失=未运行 / 3 用法或环境错误**。

### 00-env-check.sh（P0-1，预计 2.0 机时）

```sh
bash scripts/00-env-check.sh --probe            # 登录节点可跑：只读探测（module/which/版本/分区/可写性）
bash scripts/00-env-check.sh --fetch            # 登录节点可跑：只下载到 $HOME/tools/dist，不编译
sbatch ... scripts/00-env-check.sh --install    # 计算节点：编译/安装到 $HOME/tools（装一次，全局复用）
bash scripts/00-env-check.sh --dry-run          # 只打印计划执行的命令
```

- 工具清单：`gcc/cmake/make/python3/java(≥11)/git`、`verilator`、`yosys`、`sby`、`mill`、`riscv64-*-gcc`、`apptainer`。
- 安装优先级：① **conda-forge**（`yosys`/`verilator`/`openjdk`/`z3`；RISC-V GCC 用 `-c antmicro gcc-riscv64-elf-newlib`，包名与包内容已于 2026-10-30 查证，conda solve 未实测）→ ② **源码编译**到 `$HOME/tools`（`--fetch` 已下载的 yosys/verilator/sby 源码树）→ ③ **Apptainer（人工回退，脚本不自动接管）**：`module load apps/apptainer/1.3.4` 后 `apptainer exec "$VDOT_EDA_IMAGE" <命令>`；设了 `VDOT_EDA_IMAGE` 时 `--install` 只探测镜像内 `yosys`/`verilator` 是否存在，**不把镜像内工具注入 PATH**。
- 外网：`--install` 的 conda 档与首次 `make emu` 的 mill/coursier 依赖都需要计算节点外网；`--fetch` 不预取这两类（计算节点外网未探测）。
- 产物：`results/env/00-env-<runid>.log|json`、`$HOME/tools/env.sh`。
- 判据：JSON 里 `criteria[tool_*]` 全部 `达标` 且 `riscv_toolchain` 达标（`apptainer` 为可选，不计入总计）。

### 10-build-emu.sh（P0-2，预计 3.0 机时）

```sh
sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 scripts/10-build-emu.sh --src-root "$PWD/src"
```

- 前置：`src/XiangShan`（@ `a4eeaab` / yunsuan `9559211`）、`src/NEMU`（@ `a683e0b`）、`verilator`、`mill`、JDK≥11；子模块 `rocket-chip/cde`、`rocket-chip/hardfloat` **非空**（落位阶段在登录节点跑 `make -C src/XiangShan init`，见 §1）。
- `--src-root` 默认 `$CORE_DIR/src`，可省略；`--image` 省略时若 `src/XiangShan/ready-to-run/microbench.bin` 存在则自动回退（`--fallback-microbench` 保留为显式开关，不作必要条件）。
- 步骤：版本 preflight → `make init`（仅当 cde/hardfloat 为空；仍为空则记「未运行」并退出）→ NEMU `riscv64-xs-kmhv2-ref_defconfig` + `make`（产出 `build/riscv64-nemu-interpreter-so`）→ `make emu -j32` → 冒烟运行。
- 冒烟：默认 `--image` 指向的镜像；日志必须含 `HIT GOOD TRAP` 且不含 `ABORT`。
  - 正式的 1.1 证据要的是 **hello** 镜像（`hello xiangshan, I am …`），由 `AM_HOME` 下的 nexus-am `apps/hello` 构建；本工作区 `repos/xs-env/nexus-am` 为空目录，需先取源码。缺 hello 时会回退 `ready-to-run/microbench.bin`，JSON 记 `smoke_image=microbench(fallback)`，**不得**当作 1.1 的证据。
- 产物：`results/emu/10-build-<runid>.log|json`。

### 20-run-difftest.sh（P0-3 冒烟 1.0 机时 / P3 全量 3.0 机时）

```sh
sbatch -p kshcnormal -N 1 -n 32 --time=01:00:00 scripts/20-run-difftest.sh --smoke
sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 scripts/20-run-difftest.sh --full
```

- 前置：`build/emu`、NEMU `.so`、`test/manifest.tsv`（清单格式见下）。
- 冒烟 `--smoke` 跑清单里 `class` 为 `vadd` / `vdot-pos` / `vdot-neg` / `vdot-bound` 的用例；`--full` 跑全部（含 `rand` / `perf`）。
- 清单格式（`test/manifest.tsv`，空白分隔——空格或 Tab 均可，`#` 开头为注释）：

```
# case_id       class        image_path                     extra_args
vadd-01         vadd         test/build/vadd.bin
vdot-pos-01     vdot-pos     test/build/vdot_pos_01.bin
vdot-neg-01     vdot-neg     test/build/vdot_neg_01.bin
vdot-bound-01   vdot-bound   test/build/vdot_bound_01.bin
vdot-rand-0001  rand         test/build/vdot_rand_0001.bin
vdot-perf-001   perf         test/build/vdot_perf_001.bin   --max-instr=200000
```

- 每个用例的判定：日志含 `HIT GOOD TRAP`、`ABORT` 计数 0、无 `different states than DUT` 报错。
- 选中但镜像缺失的用例**计入总数并判「未运行」**：`criteria[cases_all_ran]` 要求 selected 数量 == 执行数量；`--smoke` 还要求 `vadd`/`vdot-pos`/`vdot-neg`/`vdot-bound` 四类各 ≥1 例（`criteria[smoke_classes]`）。任一未满足，整体 `status=未运行`（不是通过）。
- `perf` 类用例的程序需向 stdout 打印 `VDOT_METRIC <名字> <数值>`（名字取 `L_vdot` / `T_steady` / `T_kernel`）；脚本把它们解析进 JSON 的 `metrics[]`，并要求三口径齐全（`criteria[metrics_three]`）。
- `reg_size_match`：所有用例日志都不含 `is configured with different states than DUT`（NEMU `ref.c:471-473`）才算达标；`DIFFTEST_REG_SIZE=1400 B` 的口径见 `design/ALGORITHM.md:164`（`20` 只按运行日志判，不直接读 `.so` 里的常量）。
- 单例 timeout：`--timeout`（默认 1800 s）会被收紧到 `min(1800, 作业剩余秒数 / 剩余用例数)`（`SLURM_JOB_END_TIME` 可得时），避免作业被 Slurm 在时限处杀掉而丢 JSON。
- `--full` 会与 `results/difftest/baseline.tsv` 逐用例比较得出 `regression_delta`；基线缺失时该判据记「未运行」。只有在**全部选中用例都执行**后才写基线（有缺镜像用例时不写）。
- 产物：`results/difftest/20-<mode>-<runid>.log|json`、`results/difftest/cases/`。

### 30-golden-regress.sh（P1，预计 0.1 机时）

```sh
sbatch -p kshcnormal -N 1 -n 2 --time=00:06:00 scripts/30-golden-regress.sh
bash scripts/30-golden-regress.sh --local        # 仅本项允许：纯 Python、秒级；JSON 记 platform=login-node
```

- 跑 `verify/vdot_model_test.py`，判据：退出码 0 且 stdout 含 `ALL TESTS PASSED (1142 cases)`。
- **边界说明**：`30` 只跑金模型自测，**不生成任何用例的期望值/向量**；2.3.x 用例的期望值需在 `test/` 用例侧用 `verify/vdot_model.py` 生成（`test/` 尚未产出，属本包范围外）。

### 30-hello-nodeip.sh（1.1 证据：执行节点 IP 重建 hello 镜像 + 冒烟，随 P0-emu 记账）

```sh
sbatch -p kshcnormal -N 1 -n 32 --time=02:00:00 -J hello-nodeip \
       -o results/logs/%x-%j.out \
       scripts/30-hello-nodeip.sh --src-root "$PWD/src" --am-home "$PWD/src/nexus-am"
```

- **必须在计算节点作业步里跑**：脚本硬检查 `SLURM_JOB_ID`，登录节点直接退出 3。IP 取自**执行节点**
  `hostname -I` 的第一个字段（不是构建机地址），写进应用 Makefile 的 `HOST_IP` → `-DTARGET_IP`。
- **两个必须绕过的坑**（脚本已内建处置，理由写在脚本头）：
  1. nexus-am 的 `am/arch/isa/riscv64.mk` 只给 `-march=$(MARCH)`、**不带 `-mabi`**，而 xpack
     `riscv-none-elf-gcc` 13.2.0 默认 `ilp32`（rv32）⇒ 只给 `-march=rv64gcv_*` 会报
     `cc1: error: ABI requires '-march=rv32'`。处置：脚本生成 `ccwrap` 包装器（按 `basename $0`
     分派 `gcc/g++/ld/ar/objcopy/objdump/readelf`），给编译调用强制前置 `-mabi=lp64`。
  2. AM 静态库缓存是**按 ABI 编**的 ⇒ 重建前清 `am/build`、`libs/klib/build`（`--keep-am-cache` 可关）。
- 产物：`results/emu/30-hello-nodeip-<runid>.log`（本脚本）+ `results/emu/10-build-<runid>.{log,json}`
  与 `10-smoke-<runid>.log`（子脚本 `10-build-emu.sh`）。
- 记账：父脚本记一次（P0-emu），调子脚本时带 `BUDGET_LOG_SKIP=1` ⇒ 同一 job_id 不记两遍
  （`90-budget-log.sh` 的 `record` 不按 job_id 去重）。

### 40-yosys-area.sh（P2-1，预计 0.75 机时）

```sh
sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 scripts/40-yosys-area.sh \
       --vdot-rtl rtl/area/vdot_dp.sv --vdot-top vdot_dp \
       --vmac-rtl rtl/area/vmac_only.sv --vmac-top vimac64b_only
```

- 同一段 yosys 脚本跑两版：`read_verilog -sv <top>.v; synth -top <top>; flatten; stat -json; ltp -noff`（顺序取自 `design/ALGORITHM.md` §3.5）。
- 报告口径必须写明：**仅对数据通路模块综合，未含 VIMacU 其余部分，未含工艺库**。
- `--self-test` 只测解析器：写出的 JSON 是 `item=P2-yosys-selftest`、文件名 `40-selftest-<runid>.json`（`mode=self-test`），**不会**写成 `40-area-*.json`，不能当作 P2-1 证据。
- 产物：`results/yosys/40-area-<runid>.log|json`（含 cells / 晶体管估算（`stat -tech cmos`）/ `ltp -noff` 最长路径级数三列对比）。

### 50-formal-miter.sh（P2-2，预计 0.75 机时）

```sh
# 前置：miter 源 design/verify/formal/vdot_dp_miter.sv 无 DUT 子模块定义，不能直接喂 yosys
bash design/verify/formal/build_miter.sh            # 产出 rtl/formal/vdot_dp_miter_full.sv 与 rtl/formal/vdot_dp_miter_bug_full.sv（脚本在工作区 design/，整包落位后随 core/design/ 同在）
# 正向 + 负控（--mutant 是通过的必要条件）；DUT=VdotReduce、REF=vdot_dp_spec 为脚本内建默认
sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 scripts/50-formal-miter.sh \
       --miter rtl/formal/vdot_dp_miter_full.sv --dut VdotReduce --ref vdot_dp_spec \
       --mutant rtl/formal/vdot_dp_miter_bug_full.sv
# 流程自检（不依赖任何 vdot RTL）：正确微模块必须 SUCCESS、坏微模块必须 FAIL
sbatch -p kshcnormal -N 1 -n 8 --time=00:06:00 scripts/50-formal-miter.sh --self-check
```

- 正向：输出含 `no model found: SUCCESS!`。负控（`--mutant` 指向的坏 miter）：必须含 `model found: FAIL!`。**`--mutant` 是通过的必要条件：不给 `--mutant` 时脚本整体写 `status=未运行` 并退出码 2**（正向 SUCCESS 只记入 criteria，不写通过）。
- `--self-check` 用脚本内建的两个 8 位加法器微模块验证 yosys SAT 流程本身能区分对/错，不涉及 vdot RTL；它不能代替负控。
- 不做整条路径 BMC（depth>3 不收敛，`design/ALGORITHM.md` §4 A-5）。
- 产物：`results/formal/50-miter-<runid>.log|json`。

### 90-budget-log.sh（不占机时）

```sh
bash scripts/90-budget-log.sh balance                     # 开跑前：sacct 拉本账号用量，对照 11 机时
bash scripts/90-budget-log.sh record --item P0-emu --job 123456 --partition kshcnormal \
     --cores 32 --elapsed 02:41:13 --purpose "emu 构建冒烟"
bash scripts/90-budget-log.sh auto --item P0-emu          # 在作业内跑：自动读 SLURM_* 与 sacct
bash scripts/90-budget-log.sh summary                     # 各 item 用量 vs 预算；超 50% / 总额 >10.6 / 动用缓冲 / P0 未通过却用 P2/P3 → 退出码 1
bash scripts/90-budget-log.sh check-submit --item P0-emu --time 03:00:00   # 提交前核对 --time 上限
```

- 记账文件：`results/budget-log.tsv`，列：`时间 作业号 分区 核数 墙钟(秒) 核时 节点时 item 用途`。
- 1 机时 = 1 节点 × 1 小时；节点时 = 墙钟(h) × 节点数（本包固定 1）。
- `summary` 的判定规则：任一 `item` > 1.5 × 预算、合计（不含缓冲）> 10.6 机时、缓冲被动用、或 **P0 的 `results/{env,emu,difftest}/*.json` 最新 status 不是全部「通过」而 P2/P3 已有消耗** → 退出码 1。P0 是否完成只看 JSON 的 `status`，不看「已用机时是否用满」。

---

## 5. 产物落位与回填

- 全部落 `core/results/`，
- 每个脚本结束时自动调 `90-budget-log.sh auto`（作业内）记一次账。
- 回填到工作区：`rsync -av kunshan:/public/home/$USER/core/results/ ./results/`，再把「未开始/未运行」改成有证据的状态。
- **回填前不得在任何文档里把待跑写成结果。**

---

## 6. 机时预算速查

| item 键 | 预算（机时） | 归属 |
|---|---|---|
| `P0-env` | 2.0 | 00 |
| `P0-emu` | 3.0 | 10 |
| `P0-difftest-smoke` | 1.0 | 20 --smoke |
| `P1-golden` | 0.1 | 30 |
| `P2-yosys-formal` | 1.5 | 40 + 50 |
| `P3-full` | 3.0 | 20 --full |
| `buffer` | 0.4 | 重跑/排队 |
| **合计** | **11.0** | — |

---

## 7. 已知坑（全部来自昆山实测）

| # | 坑 | 处理 |
|---|---|---|
| 1 | `module load X \| head` 会截断 `eval`，静默加载失败 | 脚本里 `module load` 一律裸写 |
| 2 | `module load` 后不 `hash -r` 会命中旧路径 | 每个脚本 module 段后都有 `hash -r` |
| 3 | `module purge` 无效（站点强制预加载 3 个模块） | 不调用 `module purge` |
| 4 | gcc 13 + 预加载 DTK 22.10.1 的 include 冲突（C++20） | `env -u CPLUS_INCLUDE_PATH -u C_INCLUDE_PATH`（C++17 不受影响） |
| 5 | 默认 cmake 2.8.12.2 太旧 | `module load compiler/cmake/3.25.0` |
| 6 | `DefMemPerCPU=3500`，只写 `-n` 时内存按 3.5 GB/核给 | 需要满内存时补 `--mem=120G` |
| 7 | 无默认分区，忘写 `-p` 直接失败 | 所有模板都带 `-p kshcnormal` |
| 8 | 登录节点只有 2 核、139 人在线 | 重计算一律 `sbatch`；脚本硬检查 `SLURM_JOB_ID` |
| 9 | DCU 在登录节点不可见 | 当前交付不排 DCU |
| 10 | verilator 版本决定 `EMU_THREADS`（≥5.050 建议 8，旧版 16，`emu.yml:401-409`） | `10` 自动探测版本后选线程数，并记进 JSON |
| 11 | `exec_vdot` 由 `def_EHelper` 宏拼接（`include/cpu/exec.h:30`），源码 `grep` 永不命中 | 判据只看构建产物 `nm`；`nm` 也找不到时（`static inline` 被内联）脚本会明确记「未命中，待人工复核」，不当通过 |
| 12 | 计算节点外网未探测 | 下载（`--fetch`）在登录节点做，安装（`--install`）在计算节点做 |
| 13 | **机时记账 trap 探错了路径**：`90-budget-log.sh` 实际落位在 `~/core/core-package/scripts/`，而 trap 只探 `$CORE_DIR/scripts/` ⇒ `[ -x ]` 恒假 ⇒ **auto 记账从未落盘** | 6 个脚本的 trap 改为三处依次探测（`core-package/scripts/` → `scripts/` → 与脚本同目录），见 §1 落位路径说明 |
| 14 | 结果 JSON 里出现裸控制字符（AM printf 的 CRLF 之 `\r`）⇒ `json.load` 报 `Invalid control character`，整份 JSON 不可解析 | `10-build-emu.sh` 的 `json_escape` 先删裸控制字符再转义（与 `20-run-difftest.sh` 同修法）；历史件用 `verify/json_sanitize.py` 清洗（原件只读、清洗件另存） |

---

## 8. 安全与到期提醒

- 全程只用 SSH 别名 `kunshan` / `zzeshell`；脚本、日志、JSON 里**不出现任何密钥内容**，也不读取 `~/.ssh/*`。
- **华东密钥 2026-11-22 22:44 到期**：到期前在官网「重置秘钥」并更新 `~/.ssh/scnet_key`。本包不处理密钥本身。
- 华中（`zzeshell`，2026-12-19 到期）仅备用，作业由用户本人提交。

---

## 9. 状态声明

- 各脚本的实跑状态见脚本头注与 `results/*.json`；未产出 JSON 的项一律记「未运行」。
- 执行后若任一步失败，把失败原样留在 `results/`，按统一退出码语义分类，**不得**用「重跑一次看起来没问题」替代记录。
- 任何写进交付文档的数字，都必须能在 `results/*.json` 里找到来源。
