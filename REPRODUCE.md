# 复现说明：在一台 Linux 机器上重做主要结果

本文给一个没接触过本项目的人用：从三份上游源码出发，构建香山模拟器，跑通 30 例与 224 例功能测试，再做面积、形式验证、时序与结构覆盖。每条命令都是仓库里真实存在的入口；**脚本不支持或输入不在仓库内的步骤会明写**，不会用「应该可以」代替。

先读一条边界：**时序（STA）没有可执行入口。** 仓库里只留了 Tcl 片段与报告（`stage3/3.3/report.md` §4.10.2），映射后的网表与 Nangate45 Liberty 没有归档（`stage3/3.3/report.md:958` 自述「两份输入 SV 与映射网表未归档」）。本文第 3.3 节给出当时的命令与缺件，复跑需要自备工艺库，标为「按本机环境调整」。

---

## 0 前置

### 0.1 机器

| 项 | 要求 | 依据 |
|---|---|---|
| 内存 | ≥32 GB（上游推荐 64 GB） | `repos/XiangShan-doc-docs/docs/tools/xsenv.md:40` |
| 磁盘 | ≥20 GB（上游要求）；本仓覆盖率一路实测再加约 1.5 GB（见 0.3） | `xsenv.md:41`；`stage3/3.3/report.md:1183` |
| 系统 | Ubuntu 22.04 / 24.04 或同代 Linux x86_64 | `xsenv.md:37-41` |
| 本项目实跑节点 | 32 核 / 126.5 GB（`kshcnormal` 分区） | `results/env/00-env-20261105T092724.log:5`（`sinfo … up 32 126500`） |

本机 `free -g` 实读内存总量 15 GiB，低于上面的 32 GB 下限，本文的构建与仿真步骤**没有在本机执行过**（本机只跑了第 1.3 节那两条自检）。第 1、2 节除这两条外，全部要在集群计算节点上执行。

### 0.2 工具链

版本取自一次真实探测（`results/env/00-env-20261105T092724.tools.tsv`）：

| 工具 | 版本 | 用途 |
|---|---|---|
| gcc / g++ | 13.3.0 | 编 Verilator 生成的 C++、编 NEMU |
| cmake | 3.25.0 | 探测到；`make emu` 路径未调用 |
| make | 4.2.1 | 构建驱动 |
| python3 | 3.8.13 | 参考模型、用例生成、结果解析 |
| java (OpenJDK) | 17.0.21 | Mill / Chisel |
| mill | 0.12.3 | Chisel 构建 |
| verilator | 5.053 | RTL → C++ 仿真器 |
| yosys | 0.48 | 综合、形式、等价检查 |
| riscv64-unknown-elf-gcc | 13.2.0（xPack） | 交叉编译裸机测试镜像 |
| sby / z3 | **MISSING** | 未使用；形式验证走 `yosys sat`，不依赖 sby |

Java、Mill、Verilator、Yosys、RISC-V GCC 装在用户目录 `$HOME/tools`，不在系统路径里。

### 0.3 磁盘

| 项 | 大小 | 来源 |
|---|---|---|
| 本仓工作树（不含 `.git`） | 911 MB | `du -sh --exclude=.git .` 实读 |
| 其中 `results/` | 252 MB | 同上，逐目录求和 |
| 覆盖率 emu（`EMU_COVERAGE=1` 构建产物） | 424 MB | `stage3/3.3/sections/coverage.md:100` |
| 30 个覆盖记录 `.dat` | 969 MB | `stage3/3.3/report.md:1183` |
| 合并后的 `coverage_SimTop.log` | 133 MB | `results/coverage/20261108T103732/` 下合并作业的 `slurm-merge30all-*.out` |

建议：只做第 1、2、3.1、3.2 节，按上游 20 GB 下限规划；加做第 3.4 节覆盖率，再额外留 2 GB 余量（依据是上表三行实测体积之和约 1.5 GB，未单独做空间实测）。

### 0.4 网络与源码

三份上游源码**不在本仓库内**（`.gitignore:6` 排除了 `/repos/`），要自己检出：

```sh
git clone https://github.com/OpenXiangShan/XiangShan.git repos/XiangShan
git -C repos/XiangShan checkout a4eeaab
git -C repos/XiangShan submodule update --init --recursive   # yunsuan 9559211、rocket-chip 46f1efe
git clone https://github.com/OpenXiangShan/NEMU.git repos/NEMU
git -C repos/NEMU checkout a683e0b
```

三个 pin 写在 `versions.env`（`XiangShan` / yunsuan / `NEMU=a683e0b` 三行）。检出后核对：

```sh
git -C repos/XiangShan rev-parse --short HEAD            # 期望 a4eeaab
git -C repos/XiangShan/yunsuan rev-parse --short HEAD   # 期望 9559211
git -C repos/NEMU rev-parse --short HEAD                          # 期望 a683e0b
```

**还缺一份**：测试镜像的构建依赖 nexus-am（`https://github.com/OpenXiangShan/nexus-am`），本仓不含它，`versions.env` 也只锁了 XiangShan / yunsuan / NEMU 三行、没有它的 pin。本工作区里 `repos/xs-env/nexus-am` 是空目录（`ls` 无输出；`docs/正文/02_环境部署与运行验证.md:79` 也记了「仓库里的 nexus-am 源码树为空」）。缺它时 `build_all.sh:21`、`build_extra.sh:23` 会以 `AM_HOME` 硬退出——第 2 节里重建镜像的命令走不通，只能用仓内已有的 `.bin`（30 例全在，见 2.1）。

网络口径：下载/克隆在登录节点做；计算节点外网**未探测**（`core-package/README.md:333` 第 12 条），所以先取好源码与工具再提交作业。

### 0.5 落位

脚本按 `$CORE_DIR` 找源码、清单与产物，默认 `/public/home/$USER/core`（`10-build-emu.sh:23`；`94-run-extra.sh:46` 默认 `$HOME/core`）。落位（`core-package/README.md:32,54-60`）：

```sh
ssh kunshan 'mkdir -p /public/home/$USER/core'
rsync -av core-package/ kunshan:/public/home/$USER/core/
rsync -av --exclude build --exclude target --exclude .bloop repos/XiangShan kunshan:/public/home/$USER/core/src/
rsync -av --exclude build --exclude target repos/NEMU kunshan:/public/home/$USER/core/src/
ssh kunshan 'make -C /public/home/$USER/core/src/XiangShan init'   # 子模块，需外网，在登录节点做
ssh kunshan 'chmod +x /public/home/$USER/core/scripts/*.sh'
ssh kunshan 'test -f /public/home/$USER/core/scripts/00-env-check.sh && test -f /public/home/$USER/core/src/XiangShan/rocket-chip/cde/build.sc'
```

最后一条返回 0 才算落位完成。之后每个 shell 里先定好这一个变量：

```sh
export CORE_DIR=/public/home/$USER/core
```

下文集群命令里的脚本一律写成 `"$CORE_DIR"/scripts/<name>.sh`；还没 rsync 时，同一个脚本在仓库里的位置是 `core-package/scripts/<name>.sh`（两种布局脚本都能认，见 `core-package/README.md:79-84`）。

### 0.6 每次开新 shell 先做准备

```sh
module load compiler/gcc/13.3.0          # 裸写，不要接管道（截断 module 输出会静默失败）
module load compiler/cmake/3.25.0
module load apps/python/3.8.13
hash -r                                   # 否则命中旧路径缓存
[ -f "$HOME/tools/env.sh" ] && . "$HOME/tools/env.sh"   # verilator/yosys/mill/riscv-gcc 的 PATH
```

`module purge` 在昆山无效（站点在 `/etc/profile.d` 强制预加载，`core-package/README.md:108`）。各作业脚本内部已自带这三条 `module load` 与 `hash -r`（`10-build-emu.sh` 的 `module_init`），手工跑 `make` 时仍需自己执行。

环境自检（改机器、换版本后先跑）：

```sh
sbatch -p kshcnormal -N 1 -n 32 --time=00:05:00 "$CORE_DIR"/scripts/00-env-check.sh --probe
```

读 `$CORE_DIR/results/env/00-env-<runid>.json` 的 `status`；`criteria[tool_*]` 全「达标」才继续。

---

## 1 构建模拟器

### 1.1 打补丁

顺序有依赖（先叶子仓，再主仓，最后 NEMU），完整列表与依赖理由见 `stage2/2.2-rtl/CHANGES.md:21`（「应用顺序」一节）。九条基线补丁之外，重定时版 P-2 的 `patches/0005-…` **必须紧跟 `0003-…`**（两者改同一文件）：

```sh
# 叶子仓
git -C repos/XiangShan/rocket-chip apply -p1 "$PWD/patches/0001-X1-add-VDOT_VV-custom-encoding-funct6-001-rocketchip.patch"
git -C repos/XiangShan/yunsuan    apply -p1 "$PWD/patches/0001-X6-X7-VimacOpcode.vdot-3-b111-and-VimacType.-yunsuan.patch"
git -C repos/XiangShan/yunsuan    apply -p1 "$PWD/patches/0002-X15-export-sum_wo-walOut-fireS1-from-VIMac64-yunsuan.patch"
git -C repos/XiangShan/yunsuan    apply -p1 "$PWD/patches/0003-X-new-VdotReduce-K-8-int8-dot-product-reduct-yunsuan.patch"
git -C repos/XiangShan/yunsuan    apply -p1 "$PWD/patches/0005-X-new-P-2-VdotReduce-carry-save-retiming-yunsuan.patch"
# 主仓
git -C repos/XiangShan apply -p1 "$PWD/patches/0001-X1-X2-decode-VDOT_VV-as-OPMVV-F-vimac-Vima-xiangshan.patch"
git -C repos/XiangShan apply -p1 "$PWD/patches/0002-X14-vdot-legality-predicate-in-VecExceptio-xiangshan.patch"
git -C repos/XiangShan apply -p1 "$PWD/patches/0003-X8-wrapper-bypasses-Mgu-for-vdot-and-asser-xiangshan.patch"
git -C repos/XiangShan apply -p1 "$PWD/patches/0004-tests-VdotReduce-Chisel-B-19-200-xiangshan.patch"
# NEMU
git -C repos/NEMU apply -p1 "$PWD/patches/0001-N1-N2-N3-vdot.vv-reference-model-decode-entry-E-nemu.patch"
```

补丁路径用绝对路径：`git -C <dir> apply` 会把相对路径解析到 `<dir>` 内，写 `patches/…` 报「无法打开补丁」（2026-11-08 本机实测：相对路径失败，绝对路径通过）。

只打九条基线补丁（不打 `0005`）得到 K1 树（481 cells / ltp 22）；十条约 500 cells / ltp 14。30 例主回归在两棵树上都跑过，数值相同。

### 1.2 构建

```sh
sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 "$CORE_DIR"/scripts/10-build-emu.sh --src-root "$CORE_DIR/src"
```

脚本做四件事：版本 preflight → NEMU `riscv64-xs-kmhv2-ref_defconfig` 并 `make`（产 `build/riscv64-nemu-interpreter-so`）→ `make emu -j32`（产 `build/emu`）→ 冒烟跑一张镜像（`10-build-emu.sh:227-328`）。

预期产物：

| 产物 | 路径 |
|---|---|
| NEMU 参照（difftest 的 `.so`） | `$CORE_DIR/src/NEMU/build/riscv64-nemu-interpreter-so` |
| 模拟器 | `$CORE_DIR/src/XiangShan/build/emu` |
| 结果 JSON / 日志 | `$CORE_DIR/results/emu/10-build-<runid>.{json,log}` |
| 冒烟日志 | `$CORE_DIR/results/emu/10-smoke-<runid>.log` |

耗时（同一脚本三次实跑的 `started_at`→`ended_at`）：**36 分 15 秒**（`results/emu/10-build-20261107T100125.json`，改了 yunsuan 后的全量重建）与 **21 分 11 秒**（`10-build-20261101T193750.json`）。若 `build/` 已是最新、`make emu` 无事可做，整份脚本约 1 分钟（`10-build-20261104T105328.json`，其中 `make emu` 只占 7 秒）。

判据（JSON 的 `criteria[]`）：`build_emu` 为 `make emu` 退出码 0 且 `build/emu` 可执行；`smoke_good_trap` 命中 `HIT GOOD TRAP`；`smoke_no_abort` 为 `ABORT=0`。整体 `status=通过` 才算过（`10-build-emu.sh:321-328`）。

**改了 yunsuan 子模块后 `make emu` 可能什么都不做**：`Makefile` 的 `SCALA_FILE` 只扫主仓 `src/main/scala`，不含子模块，于是 `build/rtl/SimTop.sv` 被当成最新，静默保留旧 RTL。处置是构建前删掉它：

```sh
rm -f "$CORE_DIR/src/XiangShan/build/rtl/SimTop.sv"
```

（`results/yosys/p2-build-wrap.sh:17-22`，该文件记录了这条坑的实测现象。）

### 1.3 不用集群就能跑的两条自检

这两条读仓库里的源码，秒级，本机即可：

```sh
python3 design/verify/vdot_model_test.py                    # → ALL TESTS PASSED (1142 cases)，退出码 0
python3 -I design/verify/cases/extra_crosscheck.py --quiet  # → EXTRA_CROSSCHECK cases=224 … problems=0 / verdict=MATCH，退出码 0
```

第一条是参考模型自检（三套独立算法交叉，1142 例）；第二条把 224 例镜像里烧进去的期望常量逐条对回金模型。2026-11-08 在本机实跑，输出与退出码如上。

---

## 2 功能测试

### 2.1 30 例主清单

清单是 `design/verify/cases/manifest.tsv`，30 数据行，sha256 `a90d1071…`（`sha256sum` 实读）。镜像路径写成 `@IMG_DIR@` 占位符，跑之前必须展开：

```sh
mkdir -p "$CORE_DIR/test"
bash design/verify/cases/make_manifest.sh "$PWD/design/verify/cases" > "$CORE_DIR/test/manifest.tsv"
awk '!/^#/ && NF>=3' "$CORE_DIR/test/manifest.tsv" | wc -l   # 期望 30
```

第一个位置参数就是镜像目录本身。注意两种写法的差别（2026-11-08 本机实测）：`bash make_manifest.sh /tmp/img` 给 `/tmp/img/microbench.bin`；`IMG_DIR=/tmp/img bash make_manifest.sh` 给 `/tmp/img/test/bin/microbench.bin`——环境变量那条会在后面再拼一层 `/test/bin`（`make_manifest.sh:8`）。

30 例的镜像全部在仓库内（`design/verify/cases/*.bin` 共 39 个，清单引用的 30 个逐个 `test -f` 均命中），展开后直接可用；要重新编译镜像才需要 nexus-am（见 0.4）。若在集群上跑，先把这 30 个 `.bin` 同步到集群同一路径，或者用 `$CORE_DIR/test/bin` 作为镜像目录展开清单（`95-coverage.sh:430` 就假定镜像在 `$CORE_DIR/test/bin`）。

```sh
sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 "$CORE_DIR"/scripts/20-run-difftest.sh --full
```

默认输入（`20-run-difftest.sh:366-368`）：清单 `$CORE_DIR/test/manifest.tsv`、emu `$CORE_DIR/src/XiangShan/build/emu`、参照 `$CORE_DIR/src/NEMU/build/riscv64-nemu-interpreter-so`；任一缺失记「未运行」（退出码 2），不会假装通过。

判据（`20-run-difftest.sh:14-21` 的头注，实现见同文件 `:199-326`、`:569-584`）：

| 判据 | 要求 |
|---|---|
| 正例 | 日志含 `HIT GOOD TRAP` 且 `ABORT=0`、`HIT BAD TRAP=0`，**并命中本用例的自检通过串**（如 `CASE vdot_pos1: MATCH`） |
| 负例（8 例 `vdot_ill_*`） | 出现 `HIT CRITICAL ERROR`（双侧一致地按非法指令陷入）、无失配串、`ABORT=0`、无哨兵串 |
| 反例（`vdot_g0_badexp`） | `GOOD TRAP` + `CASE … MISMATCH`，且不出现 `MATCH` —— 证明「只看 GOOD TRAP」会假通过 |
| 全局 | 选中用例全部执行（`cases_all_ran`）、`nm` 能在 `.so` 里找到 `exec_vdot`、`difftest-state.h` 含 `CONFIG_DIFFTEST_ARCHVECREGSTATE`、三口径指标齐全、`t5_delta_latency` 达标 |
| `--full` 追加 | `regression_delta == 0`（与基线逐例比较） |

**基线要预先放好**，否则 `regression_delta` 记「未运行」、整份结论变成「未运行」而不是通过（`20-run-difftest.sh:533-552`）：

```sh
mkdir -p "$CORE_DIR/results/difftest"
cp results/difftest/baseline.tsv "$CORE_DIR/results/difftest/baseline.tsv"   # 仓内已带 30 行基线
```

输出：`$CORE_DIR/results/difftest/20-full-<runid>.{json,log,cases.tsv}` 与逐例日志 `results/difftest/cases/<cid>.<runid>.log`。

耗时：**29 分 50 秒**（`results/difftest/20-full-20261107T104227.json` 的 `started_at`→`ended_at`）。预期 `status=通过`、`cases_pass=30/30`、`regression_delta=0`。

一个已知的可变性：2026-11-08 有一次复跑以退出码 1 结束且没有产物（`stage3/3.1.2-difftest/README.md:59` 如实登记）。同一清单在 11-03 与 11-07 两次都跑出 30/30，本文以 `20-full-20261107T104227.json` 为参照。

### 2.2 224 例扩容清单

清单 `design/verify/cases/manifest.extra.tsv`，224 数据行（`9e72b97b…`），**不进** 30 例主清单，也不参与 `regression_delta`。跑法与 30 例同构，但用独立脚本：

```sh
bash design/verify/cases/make_manifest.sh "$PWD/design/verify/cases/extra" design/verify/cases/manifest.extra.tsv \
  > "$CORE_DIR/test/manifest.extra.tsv"
sbatch -p kshcnormal -N 1 -n 32 --time=02:30:00 "$CORE_DIR"/scripts/94-run-extra.sh \
  --manifest "$CORE_DIR/test/manifest.extra.tsv" --timeout 600
```

第二个位置参数是源清单（`make_manifest.sh:9`）。`94-run-extra.sh` 自己**不**替换 `@IMG_DIR@`（脚本内该占位符出现 0 次），所以必须先展开再传。

镜像现状：仓内 `design/verify/cases/extra/*.bin` 只有 **129** 个，清单 224 行里有 **95** 个镜像不在本地（`test -f` 逐行统计）。缺镜像时该例记「未运行(缺镜像)」，整体 `status=未运行`（退出码 2）。两条路：从实跑侧 rsync 回来，或在有 nexus-am 与 RISC-V GCC 的机器上重建：

```sh
AM_HOME=<nexus-am 源码树> CROSS_COMPILE=riscv64-unknown-elf- bash design/verify/cases/build_extra.sh
```

默认输入（`94-run-extra.sh:47-50`）：emu、NEMU `.so`、清单、金模型对拍脚本 `$CORE_DIR/verify/cases/extra_crosscheck.py`（不在位时 `golden_crosscheck` 记「未运行」）。

判据（`94-run-extra.sh:13-24` 的头注，实现见同文件 `:192-322`）：正例 `GOOD TRAP` + `CASE <cid>: MATCH`；随机例 `RAND10K verdict=ALL_OK groups=10000 mism=0 …`；`g0` 两类必须 `MISMATCH` 且不 `MATCH`；57 个负例双侧一致陷入；`nm_exec_vdot`、`vec_reg_compare`、`cases_all_ran` 同 30 例口径；另加 `golden_crosscheck`（期望常量与金模型逐条一致）。

输出：`$CORE_DIR/results/difftest/extra/94-extra-<runid>.{json,log,cases.tsv}`。

耗时：**1 小时 39 分 49 秒**（`results/difftest/extra/94-extra-20261108T014445.json`）。预期 `status=通过`，`counters` 里 `selected=executed=pass=224`、`selfcheck_req=ok=162`、`g0_req=caught=2`、`neg_req=ok=57`。

### 2.3 两套清单的关系

| | 30 例 | 224 例 |
|---|---|---|
| 清单 | `manifest.tsv`（冻结件） | `manifest.extra.tsv` |
| 驱动脚本 | `20-run-difftest.sh --full` | `94-run-extra.sh` |
| 基线 / 回归比较 | 有（`baseline.tsv`） | 无 |
| 自检串 | 21 例要求 | 162 例要求 |
| 镜像是否全在仓内 | 是（30/30） | 否（129/224） |

两套都跑，合计 254 个镜像；**不要**把 224 例并进 30 例清单——主清单是冻结件，改它会让历史结果失去可比性。

---

## 3 面积、时序、形式验证、结构覆盖

### 3.1 面积（Yosys）

两步：先从生成 RTL 的 `build/rtl` 拼出两块「同口径数据通路」闭包，再综合。

```sh
bash design/verify/area/build_area_rtl.sh "$CORE_DIR/src/XiangShan" "$CORE_DIR/rtl/area"
```

它读 `build/rtl/`（先跑第 1 节，或 `make verilog`），产出 `vdot_dp.sv`（`VdotReduce` 闭包）与 `vmac_only.sv`（VIMac64b 闭包），并打印下一步命令。顶层名用**模块名** `VdotReduce` / VIMac64b，不是文件名（`build_area_rtl.sh:44-47`；实测 JSON 的 `metrics[].top` 正是这两个名字）：

```sh
sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 "$CORE_DIR"/scripts/40-yosys-area.sh \
  --vdot-rtl "$CORE_DIR/rtl/area/vdot_dp.sv" --vdot-top VdotReduce \
  --vmac-rtl "$CORE_DIR/rtl/area/vmac_only.sv" --vmac-top VIMac64b
```

综合脚本是 `read_verilog -sv; synth -top <top>; flatten; stat -json; stat -tech cmos; ltp -noff`（`40-yosys-area.sh:253-254`）；路径参数不加引号（yosys 0.48 不剥单引号，`40-yosys-area.sh:16` 记录了这条实测坑）。

预期（`results/yosys/40-area-20261107T104238.json` 的 `metrics[]`）：

| top | cells | 最长拓扑路径（ltp） | 触发器 |
|---|---:|---:|---:|
| `VdotReduce`（P-2，打 `0005`） | 500 | 14 | 38 |
| `VdotReduce`（K1，不打 `0005`） | 481 | 22 | 19 |
| `VIMac64b` | 42,783 | 100 | 838 |

`cells` 与 `longest_path` 来自该 JSON 的 `metrics[]`；触发器数不在 `metrics[]` 里，按同次综合落下的 `results/yosys/vdot-k1.stat.json`、`vdot-p2.stat.json`、`vmac_only.stat.json` 的 `num_cells_by_type` 加总（分别是 `$_DFFE_PP_`=19、`$_DFFE_PP_`=38、709+1+128=838，2026-11-08 本机实读）。

耗时：**10 分 29 秒**（`results/yosys/40-area-20261107T104238.json` 的起止）；同一脚本跑 K1 版 RTL 的一次是 33 秒（`results/yosys/40-area-20261107T095404.json`）。

顺带一条同族结果（K=16 扩展格，**独立数据通路、未集成进 `VIMacU`**）：生成器 `python3 design/verify/area/gen_ext.py` 产出 `ext/*.sv`，作业脚本 `design/verify/area/run_ext_yosys.sh` 用同一段 yosys 命令综合 K8/K16 两个 top 并做 2 拍有界等价检查；`EXT_RTL_DIR` / `REF_RTL` 两个环境变量按你放 RTL 的位置调整。结果 977 cells / ltp 26（K8 对照 481/22，同一流程复现），记录在 `results/yosys/` 的 `ext-*.json` 与 `ext-*/`。

口径必须与数一起读：只综合数据通路模块，未含 `VIMacU` 其余部分、未含工艺库，`cells` 是 Yosys 通用门计数，不是硅面积（`40-yosys-area.sh:16-17`）。

本机可以先验解析器（不需要 yosys，也不写面积证据）：

```sh
bash core-package/scripts/40-yosys-area.sh --self-test
```

2026-11-08 本机实跑：`cells=123 transistors=1750 path=17`，`self-test 通过`，退出码 0。它写出的是 `40-selftest-*.json`，不是 `40-area-*.json`。

### 3.2 形式验证（Yosys SAT miter）

同样两步：先拼 miter 源，再跑 SAT。

```sh
bash design/verify/formal/build_miter.sh "$CORE_DIR/src/XiangShan" "$CORE_DIR/rtl/formal"
sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 "$CORE_DIR"/scripts/50-formal-miter.sh \
  --miter "$CORE_DIR/rtl/formal/vdot_dp_miter_full.sv" --top vdot_dp_miter \
  --dut VdotReduce --ref vdot_dp_spec \
  --mutant "$CORE_DIR/rtl/formal/vdot_dp_miter_bug_full.sv"
```

`build_miter.sh` 从 `build/rtl` 拼 `VdotReduce` 闭包，配 `design/verify/formal/vdot_dp_spec.sv` 里的位级金模型，产出正向与负控两份 miter（`build_miter.sh:39-61`）。`--top` 只影响日志文件名（`50-formal-miter.sh:225`）。

判据：正向输出含 `no model found: SUCCESS!`，负控输出含 `model found: FAIL!`。**`--mutant` 是通过的必要条件**——不给时脚本只记正向结果、整体写「未运行」、退出码 2（`50-formal-miter.sh:255-266`）。SAT 链是 3 拍有界（`50-formal-miter.sh:129`）：`chformal -skip 1; sat -verify -prove-asserts -seq 3 -set-at 1..3 in_io_fireS1 1`。

预期：`miter_prove=SUCCESS`、`miter_mutant=FAIL`（`results/formal/50-miter-20261104T093531.json` 的 `criteria[]`）。耗时 **3 分 23 秒**（同文件起止）。

口径：只证 `vdot_dp` 数据通路，不覆盖流水、发射与旁路；有界检查，不是无界等价证明（JSON 的 `scope` 字段）。

### 3.3 时序（STA）：仓库里没有可执行入口

**这一节不能一条命令重跑。** 事实是：

- 仓库里没有 STA 脚本，也没有 `.tcl` 文件（`find . -name '*.tcl' -not -path './repos/*'` 无输出；`report_worst_slack` 只出现在报告文本与结果 `.log` 里）。
- 映射后的网表与 Nangate45 Liberty 未归档，`stage3/3.3/report.md:958` 自述「两份输入 SV 与映射网表未归档」；本仓 `find . -name '*.lib'` 零命中。
- 留存的只有报告里的 Tcl 片段（`stage3/3.3/report.md:944-947` 的约束、`:999-1003` 的读入序列）与 8 份逐 run 报告 `results/sta/20261108/reports/*.rpt`。

要重做，得自己补齐三件：**Nangate45 `typical` Liberty**、**Yosys 映射后的门级网表**、**OpenSTA 3.2.0**。当时的映射链是 `read_verilog -sv -DSYNTHESIS → hierarchy -check -top → synth -top -flatten → dfflibmap -liberty → abc -liberty → opt -fast → clean → write_verilog -noattr`（`stage3/3.3/report.md:945`）。读入与报告的 Tcl（按本机环境调整路径与顶层名）：

```tcl
read_liberty $LIB
read_verilog $NETLIST
link_design $TOP
set clk [get_ports clock]
create_clock -name core_clock -period $PERIOD $clk
set_input_delay  0.05 -clock core_clock [all_inputs -no_clocks]
set_output_delay 0.05 -clock core_clock [all_outputs]
report_worst_slack -max -digits 6
report_checks -path_delay max -format full_clock_expanded -digits 6
```

留存的结果（**模块级、代理工艺、预布局、理想时钟，未闭合**）：`VdotReduce` 最差路径 K1 1084.3 ps、P-2 658.8 ps；333 ps 与 500 ps 两个约束下 slack 全负（`results/sta/20261108/worst_slack_20261108.tsv`，逐条路径原文在同目录 `reports/*.rpt`）。两版起点/终点不同（K1 是输入口 → DFF，P-2 是 DFF → 输出口），**数值不能相减**。

只读复核可以直接看表：

```sh
cat results/sta/20261108/worst_slack_20261108.tsv
```

### 3.4 结构覆盖（Verilator line coverage）

```sh
# 30 行冻结件：先展开成绝对路径，再随作业传进去
bash design/verify/cases/make_manifest.sh "$PWD/design/verify/cases" > "$CORE_DIR/test/manifest.30.tsv"
awk '!/^#/ && NF>=3' "$CORE_DIR/test/manifest.30.tsv" | wc -l   # 期望 30

sbatch -p kshcnormal -N 1 -n 32 --time=04:00:00 \
  --export=ALL,CORE_DIR=$CORE_DIR,SIM_VFLAGS=-Wno-UNOPTTHREADS \
  "$CORE_DIR"/scripts/95-coverage.sh \
  --manifest "$CORE_DIR/test/manifest.30.tsv" \
  --ref-so "$CORE_DIR/src/NEMU/build/riscv64-nemu-interpreter-so" \
  --timeout 2400 --expect-rows 30 --restore-emu --no-budget-guard
```

要点：

- **清单必须是 30 行冻结件**。远端 `test/manifest.tsv` 后来漂到 31 行（`stage3/3.1.2-difftest/README.md:57`）；脚本用 `--expect-rows 30` 卡住，行数不符直接记「未运行」（`95-coverage.sh:349-352`）。
- 探针镜像默认 `$CORE_DIR/test/bin/microbench.bin`（`95-coverage.sh:338`），缺了就「未运行」。
- `SIM_VFLAGS=-Wno-UNOPTTHREADS` 不是可选项：Verilator 把 `UNOPTTHREADS` 警告当错误，首次构建因此失败（`results/coverage/20261108T103732/` 里主作业的 slurm 输出第 12 行，verilator 命令行可见该开关；失败史见 `stage3/3.3/report.md:1218`）。
- `--restore-emu` 结束后把 `build/emu` 恢复成非覆盖版本，避免后续 difftest 误用覆盖构建。
- `--no-budget-guard` 只在预算台账已经超自设上限、且你接受这个前提时用；该开关把判据记「已越过」而不是「达标」（`95-coverage.sh:376-381`）。

产物：`$CORE_DIR/results/coverage/<runid>/`，含逐例 `.dat`、`cases.tsv`、合并目录。

**已知脚本缺陷**：脚本自带的合并步骤会把 30 个 `.dat` 一次塞进 `make coverage` 的变量里，第 2 个起被 shell 当命令执行，`coverage_report` 判据失败（`95-coverage.sh:479-481`，实跑 rc=2/127，`stage3/3.3/report.md:1183`）。补救是用**同一套**管线手工重做合并——`verilator_coverage --annotate-all` → `coverage.py` → `statistics.py`（`repos/XiangShan/difftest/verilator.mk:167-171`），或一次只传一个 `.dat`。加 `--annotate-all` 才会产出被 Verilator inline 的 `VdotReduce.sv`。

耗时：构建约 **1 小时 40 分**（`10:37:33` 起、`12:18:22` 出 emu），整份作业 **2 小时 21 分**（`slurm_script-20261108T103732.log` 首尾时间戳）。

预期（`results/coverage/20261108T103732/merged30all.coverage/verilator_coverage-summary.txt`）：

| 项 | 值 |
|---|---|
| 顶层行覆盖（SimTop） | 67.5%（113628/168283） |
| `VdotReduce` / `VIMacU` / `VIMac64b` 的 `tree_line` | 1/1、3/3、3/3（分母是条件行，不是源码行数） |
| toggle / branch / expr / fsm | 0/0，即**未采集**（构建只开了 `--coverage-line`） |

67.5% 是全 SoC 顶层的背景值，不是 vdot 的覆盖率；模块的 1/1、3/3、3/3 分母极小，也不能读成「源码全覆盖」（`stage3/3.3/report.md` §4.11.4 有两条口径的完整说明）。

---

## 4 已知坑

按踩到的顺序排，全部来自本仓实测记录。

**环境与工具链**

1. 必须先 `module load` + `hash -r` + `source $HOME/tools/env.sh`，否则 verilator / yosys / mill / riscv-gcc 不在 PATH。作业脚本内部自带，手工跑 `make` 时必须自己来。
2. `module load` 不能接管道（`| head` 会截断 `eval`，静默失败）；`module purge` 无效；gcc 13 编 C++20 若报 `__int_traits`，用 `env -u CPLUS_INCLUDE_PATH -u C_INCLUDE_PATH`（`core-package/README.md:322-325`）。
3. 计算节点 PATH 里没有 `python3`（实测 `rc=127`），脚本用站点路径 `/public/software/apps/python/3.8.13/bin/python3`（`stage1/1.3-vadd/scripts/61-extract-stages.sh:13-15`）。自定义脚本要照做。

**必须在集群上做 / 可以在本机做**

| 步骤 | 能否在登录节点或本机跑 |
|---|---|
| `00-env-check.sh --probe` / `--fetch` | 可以（只读探测、只下载） |
| `00-env-check.sh --install` | 不行——`--install` 硬检查 `SLURM_JOB_ID`，登录节点退出 3（`00-env-check.sh:334-336`） |
| `10-build-emu.sh`、`20-run-difftest.sh`、`25-rtl-lint.sh`、`40-yosys-area.sh`、`50-formal-miter.sh` | 不行——均在 `SLURM_JOB_ID` 为空时 `exit 3`（`10-build-emu.sh:155`、`20-run-difftest.sh:347`、`25-rtl-lint.sh:123`、`40-yosys-area.sh:234`、`50-formal-miter.sh:198`）。**`--dry-run` 也不放行**：`20-run-difftest.sh --full --dry-run` 在登录节点实测退出码 3 |
| `40-yosys-area.sh --self-test` | 可以（自检在 SLURM 检查之前执行，实测退出码 0） |
| `50-formal-miter.sh --self-check` | 不行（检查在自检之前，实测退出码 3） |
| `94-run-extra.sh`、`95-coverage.sh` | `--dry-run` 可以；真跑不行（`94-run-extra.sh:81`、`95-coverage.sh:315`） |
| `30-golden-regress.sh --local` | 可以（纯 Python，秒级；`CORE_DIR` 要指向含 `verify/` 的目录，例如 `CORE_DIR=$PWD/core-package`，2026-11-08 本机实测 4/4 判据达标） |
| 第 1.3 节的两条、`make_manifest.sh` | 可以 |
| 登录节点 | 只有 2 核且多人共用（`core-package/README.md:329`），只做编辑、`sbatch` 提交与轻量脚本；重计算一律 `sbatch -p kshcnormal`，且必须显式写 `-p`（无默认分区），**不要写 `--qos=`** |

**数据与镜像**

4. `make emu` 感知不到 yunsuan 子模块的改动，会保留旧 RTL；改子模块后先 `rm -f build/rtl/SimTop.sv`（`results/yosys/p2-build-wrap.sh:17-22`）。
5. `10-build-emu.sh` 与 `20-run-difftest.sh` 不能重叠：前者原地重写 NEMU `.so` 时后者 `nm` 读到 0 行，整份结果被判失败（`stage3/3.1.1-nemu/README.md:36`）。查 `vdot` 符号必须用普通 `nm`，`nm -D` 读不到。
6. 224 例只有 129 个 `.bin` 在仓内，95 个缺失（第 2.2 节）。缺镜像的例会计入「未运行」，不会静默跳过。
7. nexus-am 不在仓库内，`versions.env` 里也没有它的 pin；`build_all.sh` / `build_extra.sh` 缺 `AM_HOME` 时直接退出。仓内已有的 `.bin` 可以绕过重建，但只要涉及重编镜像就必须补这份源码。
8. 清单里的 `@IMG_DIR@` 必须展开：`20-run-difftest.sh` 与 `94-run-extra.sh` 都**不**在脚本内替换占位符；`95-coverage.sh` 会替换成 `$CORE_DIR/test/bin`（`95-coverage.sh:430`）。展开时注意位置参数与环境变量两种写法的差别（第 2.1 节）。
9. 30 例 `--full` 的 `regression_delta` 依赖 `results/difftest/baseline.tsv`；不给基线时该判据记「未运行」，整份 `status=未运行`——不是失败，但也不是通过。
10. 结果 JSON 里出现裸控制字符（AM 的 `printf` 带 CRLF）会让 `json.load` 报错。历史件用 `core-package/verify/json_sanitize.py` 清洗；现行脚本已自带过滤（`core-package/README.md:335`）。

**证据口径**

11. 时序（STA）没有可执行入口，网表与 Liberty 未归档（第 3.3 节）。只读复核看 `results/sta/20261108/`；不要把它写成「时序已收敛」——两版在两个周期下 slack 均为负。
12. 覆盖率的 `coverage_report` 判据会失败（脚本自身的合并缺陷），但 30/30 用例与 30/30 `.dat` 是真跑出来的；合并要手工重做（第 3.4 节）。另外 toggle 从未采集，`0/0` 不等于「覆盖率 0%」。
13. 面积是 Yosys 通用门计数，没有µm²、没有工艺库；`ltp` 是拓扑级数，不能当 ps 用。
14. 形式验证是 3 拍有界的 miter，只证数据通路；`SUCCESS` 不能写成「全流水等价证明」。

---

## 5 最短核对清单

全做完之后，用这几条对齐仓库里已有的结果（都在 `results/` 下，均已入库）：

```sh
python3 -I -c "import json;d=json.load(open('results/difftest/20-full-20261107T104227.json'));print(d['status'],len(d['cases']),sum(1 for c in d['cases'] if c['status']=='通过'),d['regression_delta'])"
python3 -I -c "import json;d=json.load(open('results/difftest/extra/94-extra-20261108T014445.json'));print(d['status'],d['counters'])"
python3 -I -c "import json;d=json.load(open('results/yosys/40-area-20261107T104238.json'));print([(m['top'],m['cells'],m['longest_path']) for m in d['metrics']])"
python3 -I -c "import json;d=json.load(open('results/formal/50-miter-20261104T093531.json'));print(d['status'],[(c['name'],c['status']) for c in d['criteria']])"
cat results/coverage/20261108T103732/merged30all.coverage/verilator_coverage-summary.txt
cat results/sta/20261108/worst_slack_20261108.tsv
```

预期输出依次为：`通过 30 30 0`；`通过 {'selected': 224, 'executed': 224, 'pass': 224, …}`；两条 `(top, cells, ltp)`（`VdotReduce` 500/14、`VIMac64b` 42783/100；这一份 JSON 是 P-2 树跑的）；`通过` 且两条判据「达标」；line 67.5% 与五行 `0.0% (0/0)`；八行最差 slack（`VdotReduce` 与 `VIMac64b` 各两版 × 两个周期）。

哪一步的实跑输出与这里不符，先查该脚本 `--help` 与对应的 `results/*.json` 自述，再查 `core-package/README.md` §7 的坑表——不要用「重跑一次就好了」覆盖掉差异。
