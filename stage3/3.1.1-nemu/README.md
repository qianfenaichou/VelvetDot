# 3.1.1 NEMU 指令扩展（vdot.vv）

> 计划完成日：2026-11-02（非官方截止日）
> 结论：NEMU 侧 `vdot.vv` 参考模型已提交（`a9dca53`，3 文件 +35/−1），并在昆山构建产物上实测 `nm build/riscv64-nemu-interpreter-so | grep exec_vdot` **命中 2 行**（`t exec_vdot`、`t exec_vdot.part.0`，退出码 0）；该判据在**当前 30 例整份 `--full`**（作业 `126676734`）里同样记 `达标`（`nm_exec_vdot` = 「命中 2 行」），且同次运行的 `vec_reg_compare=达标`（`difftest-state.h` 含 `CONFIG_DIFFTEST_ARCHVECREGSTATE`）证明参考模型与 RTL 的向量寄存器状态是对齐的。

## 1. 交付内容

| 文件 | 说明 |
|---|---|
| `patches/0001-N1-N2-N3-vdot.vv-reference-model-decode-entry-E-nemu.patch` | 相对基线 `a683e0b` 的完整 NEMU 扩展 patch（N1 译码表 / N2 `def_EHelper(vdot)` / N3 `VECTOR_INSTR_TERNARY`） |
| `evidence/nm-exec_vdot.txt` | 2026-11-03 09:04 CST 在昆山登录节点复跑 `nm` 的原始记录（命令、输出、退出码、`.so` 指纹） |
| `evidence/10-build-20261103T032307.{json,log}` | 作业 `126630755` 的构建结果（`criteria[nm_exec_vdot] = {"actual":"命中 2 行","status":"达标"}`）。**可读性限制（2026-11-04 实测）**：该 JSON 含裸 CR，`python3 -I -c "import json;json.load(open(...))"` → `JSONDecodeError: Invalid control character at: line 24 column 177 (char 1610)`；与 `results/emu/`、`stage1/1.1-env/raw/superseded-20261103T032307/` 三份 `md5sum` 同值 `65b030377ebadf9fec61eae3dae70075`，仓内**无 clean 件**。故本行只能以文本命中复现：`grep -a -c 'nm_exec_vdot' …/10-build-20261103T032307.json` → `1`；按 `json.load` 读法**不可复现**，不记通过。判据的当前证据以同表下一行的 `20-full-20261103T142246.json`（合法 JSON、`nm_exec_vdot=达标`）为准 |
| `evidence/20-full-20261103T142246.json` | **当前 30 例整份 `--full`** 的结果 JSON（作业 `126676734`）：`criteria[nm_exec_vdot]=达标`（命中 2 行）、`criteria[vec_reg_compare]=达标` |

## 2. 版本与 patch 一致性（本次实测）

- NEMU 实施 HEAD：`git -C repos/NEMU log --oneline -1` → `a9dca53 N1/N2/N3: vdot.vv reference model (decode entry, EHelper, enum)`；基线 pin `a683e0b` 仍在历史中。
- patch 与工作树一致：`git -C repos/NEMU apply --check --reverse patches/0001-N1-N2-N3-*.patch` → **RC=0**（可逆即已应用；同一命令正向应用到 `a683e0b` 为本次未跑，属未运行项）。
- 改动面：`git -C repos/NEMU diff --stat a683e0b..a9dca53` → 3 files changed, 35 insertions(+), 1 deletion(-)（`src/isa/riscv64/include/isa-all-instr.h` / `src/isa/riscv64/instr/rvv/decode.h` / `src/isa/riscv64/instr/rvv/vcompute.h`，实测）。

## 3. `nm | grep exec_vdot` 证据（2026-11-03 实测）

命令与输出（完整记录见 `evidence/nm-exec_vdot.txt`）：

```text
$ ssh kunshan 'cd ~/core/src/NEMU && nm build/riscv64-nemu-interpreter-so | grep exec_vdot'
0000000000031a20 t exec_vdot
000000000002c6e0 t exec_vdot.part.0
RC=0
```

命中 **2 行**，满足「≥1 行」判据。被测 `.so`：9,068,656 B，mtime `2026-11-03 03:23:39 +0800`，sha256 `6e10e810669d511c9a2e7d1abe5cc93837f61bb4dc94727878986dcf83ce1b0c`（远端 `sha256sum` 实测）。

**口径边界**：本机 `repos/NEMU` 没有 `build/` 目录（`find repos/NEMU -name 'riscv64-nemu-interpreter-so'` 无命中），所以该命令只能在昆山源码树复跑，本地离线不可复现；记录里的输出是远端实跑结果，不是本地生成。

**已知陷阱（任务记录第 4 条）**：`nm -D` 读不到该符号；必须用普通 `nm`（静态符号表）。作业 `126630806` 曾在 `10-build-emu.sh` 原地重写 `.so` 的时间窗内跑 `nm`，得到 0 行并把整份结果判失败；同一 `.so` 事后复跑为 2 行。`10-build-emu.sh` 与 `20-run-difftest.sh` 不得重叠。

## 4. 与 3.1.2 的衔接

- `126676734` 的 `criteria[]` 里 `nm_exec_vdot=达标`、`vec_reg_compare=达标`、`reg_size_match=达标`（0 次 state 尺寸不一致）——三项合起来说明：NEMU 里确有 `vdot.vv` 实现、difftest 打开了架构向量寄存器比对、且两侧 state 结构配套。
- 该次运行的 30 例全 `通过`（含 `vdot_g0_badexp` 反例被自检判负），详见 `../3.1.2-difftest/README.md` §2。
- 仍未做：**patch 正向应用回 `a683e0b` 的独立复验**（只在工作树做了 `--check --reverse`）。

## 5. 核对命令与输出（2026-11-04）

```
$ python3 -I -c "import json;d=json.load(open('results/difftest/20-full-20261103T142246.json'));print([(c['name'],c['status'],c['actual']) for c in d['criteria'] if c['name'] in ('nm_exec_vdot','vec_reg_compare','reg_size_match')])"
[('nm_exec_vdot','达标','命中 2 行'), ('vec_reg_compare','达标','/public/home/$USER/core/src/XiangShan/build/generated-src/difftest-state.h'), ('reg_size_match','达标','0 次（1400 B 口径）')]
$ grep -c 'exec_vdot' stage3/3.1.1-nemu/evidence/nm-exec_vdot.txt
4
# 其中 2 行是 `nm` 原始输出（`t exec_vdot` / `t exec_vdot.part.0`），另 2 行是注释与命令文本
```
