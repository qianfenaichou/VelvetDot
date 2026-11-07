# 1.1 环境部署验证

**结论（证据取自 2026-11-04 作业 `126758114`）：1.1 身份串已用「执行节点 IP」重跑并达标——`hello xiangshan, I am XinXiangXiangRong, IP: 10.1.3.35`（昆山作业 `126758114`，节点 `<node>`，`HIT GOOD TRAP=1`、`ABORT=0`、`BAD=0`，结果 JSON 7/7 criteria 达标），IP 由计算节点 `hostname -I` 第一个字段注入。**

> 交付物编号：官方 1.1（`docx/02-赛题与评分细则.md:45`：输出 `hello xiangshan, I am xxx, IP address`，xxx = 团队标识）
> 团队标识：`XinXiangXiangRong`（中文名「芯芯像绒」）
> 证据平台（当前）：华东一区【昆山】超算，分区 `kshcnormal`，作业 `126758114`，节点 `<node>`，镜像 md5 `ef1540e4…`
> 历史对照（2026-11-03，节点 `<node>` / IP `10.1.11.2`，作业 `126681977`）：仍留在 `raw/` 内作为对照，**不是**当前结论
> 更早一版（构建机 IP `192.168.0.4`，作业 `126630755`）：已移入 `raw/superseded-20261103T032307/`
> 打包日期：2026-11-03（2026-11-04 00:17 换入节点 IP 证据；2026-11-04 再换为作业 `126758114` 的结果）
> 说明：本文档中的集群节点名以 `<node>` 占位，实际值见同目录 `raw/` 下的作业日志原件。

---

## 1. 证据文件

### 1.1 当前证据（作业 `126758114`，2026-11-04 10:53:14→10:54:23）

| 文件 | 内容 | 大小 / 行数 | sha256 |
|---|---|---|---|
| `raw/nodeip-20261104T105314/10-smoke-20261104T105328.log` | **昆山 hello 冒烟的终端日志全文**（emu 原始输出） | 4,754,877 B / 29,873 行 | `e4bea3c950286751735342cb4c246d437ea0ddc39639979d7366d7b24d6b0e0b` |
| `raw/nodeip-20261104T105314/30-hello-nodeip-20261104T105314.log` | 节点 IP 取用 + 节点内重建镜像 + 冒烟过程日志（`30-hello-nodeip v2` 自写） | 1,247 B / 11 行 | `885164f6119f94beb2a404fd75e46fdd40c30a79800691dda7bb4870c26271f4` |
| `raw/nodeip-20261104T105314/hello-nodeip-126758114.out` | Slurm stdout 回传（与上一份**不逐字节相同**：`cmp` 在第 9 行起不同，Slurm 追加了作业收尾行） | 5,843 B / 93 行 | `3bdcdbae83fb48d4cdbe53d6981ce4ce3cd88bd1ef9bdf63d4c966c94ee42ee0` |
| `raw/nodeip-20261104T105314/10-build-20261104T105328.log` | 同作业的构建+冒烟过程日志（`10-build-emu.sh` 自写） | 1,355 B / 13 行 | `62598f5b3857d1dfcde965812a143e12949136414a08be121c8fbd8379887bea` |
| `raw/nodeip-20261104T105314/10-build-20261104T105328.json` | 同作业的结果 JSON（7 条 criteria 全 `达标`；`json.load` 通过，**无裸 CR**） | 1,877 B | `a84cea6d6d87dc31af25c0704a13f4f5a8b9ef9aaa4b9978ec453d7672589337` |
| `raw/nodeip-20261104T105314/hello_identity.nodeip.bin` | **本次实际运行的镜像**（节点内重编，`~/core/.upload/nodeimg/hello_identity.bin`） | 5,720 B | md5 `ef1540e40b010d98601556eac51c204c` |
| `screenshot/1.1-terminal-real-log-20261105.png` | **真实终端截屏**（非渲染）：本机 X11 gnome-terminal 窗口内实跑 `grep -n`/`sed -n`/`tail` 读上述冒烟日志后 `import -window <终端窗口ID>` 抓取；图中命令行是本次会话输入，其下输出行为日志原始字节（未增删改） | 1716×560 px / 105,741 B | `c4259774db0ab86ba7ea1ffad30a8c8a455006222a7ee0e4b4050c18c97a55fc` |
| `screenshot/README-screenshot.txt` | 截屏方式与素材源路径说明（一行） | 1 行 | — |

**与历史对照作业（`126681977`，IP `10.1.11.2`）的关系**：两份镜像 5,720 B 相同、`cmp -l` 只有 **4 字节不同（偏移 4942–4945）**，正是 IP 串 `10.1.11.2`→`10.1.3.35` 的注入差异（`cmp -l raw/hello_identity.nodeip.bin raw/nodeip-20261104T105314/hello_identity.nodeip.bin` 输出 4 行）。⇒ 两次作业是**同一份源码、同一构建链、只换注入 IP** 的等价重跑，不是换了实现。

### 1.2 历史对照（`126681977`，IP `10.1.11.2`；**不是**当前结论）

| 文件 | 内容 | 大小 / 行数 | sha256 |
|---|---|---|---|
| `raw/10-smoke-20261103T150714.log` | **昆山 hello 冒烟的终端日志全文**（emu 原始输出） | 4,754,877 B / 29,873 行 | `f70fe719d8dfd1654e0d7946b4ecacf0b862b211a30de42df969dc0a9c9927ba` |
| `raw/30-hello-nodeip-20261103T150703.log` | 该作业的**节点 IP 取用 + 节点内重建镜像 + 冒烟**过程日志（`30-hello-nodeip v2` 自写） | 4,753 B / 82 行 | `678eef75fd7bb2da18bc6d81688a89eaad5282e0bb9dad4c37ce6b49d8fe98bc` |
| `raw/126681977_t1c_hello_ip.out` | Slurm stdout 回传，与上一份**逐字节相同**（`cmp` 无输出） | 4,753 B | `678eef75fd7bb2da18bc6d81688a89eaad5282e0bb9dad4c37ce6b49d8fe98bc` |
| `terminal-excerpt.log` | 从冒烟日志全文按行号摘出的关键行（身份串 / 节点 IP / GOOD TRAP / 收尾统计） | 摘录 | — |
| `raw/10-build-20261103T150714.log` | 同一作业的构建+冒烟过程日志（`10-build-emu.sh` 自写） | 1,355 B / 13 行 | `89fb6a0412c3e728982f04e384741045fb5837a2fed2f0f3e753886678f8ac45` |
| `raw/10-build-20261103T150714.json` | 同一作业的结果 JSON（7 条 criteria 全 `达标`）**原件：仍含裸 CR、不是合法 JSON（见 §5.1）** | 1,878 B | `572bd29916a0f43b036e40fa8fea1a3e8b2e63ae07bdd5620a327bac52fffd08` |
| `raw/10-build-20261103T150714.clean.json` | 上一行的**清洗件**（原件一字节未改；只把字符串里的裸 CR 转义成 `\r`，键序/排版/数值不变）⇒ `python3 -c "import json;json.load(open(...))"` 通过 | 1,879 B | `f48f8007db78567a892b0ec04bbbb962065aeae699c69bccbdc2fb58949085ec` |
| `raw/hello_identity.nodeip.bin` | **历史对照作业（`126681977`）实际运行的镜像**（节点内重编，从昆山 `~/core/.upload/nodeimg/hello_identity.bin` 取回） | 5,720 B | md5 `0086e33b1739c297dc0c7ae685473e6b` |
| `raw/hello_identity.c` | 身份串源码（判据来源，与上一版同一份） | 4,242 B | — |
| `raw/hello_identity.bin` | 仓库内镜像（**含 `192.168.0.4`，不是当前作业 `126758114` 运行的那份**，见 §5.2） | 5,720 B | md5 `17614aa4a83e0e571f145d5008748db7` |

`raw/` 下各份逐份 `sha256sum`/`md5sum` 与源比对（作业 `126758114` 5 份、作业 `126681977` 6 份，命令见 §6）。

## 2. 身份串原文（作业 `126758114`，第 3 行，全文仅 1 处命中）

```
     3 | hello xiangshan, I am XinXiangXiangRong, IP: 10.1.3.35
```

出处：`stage1/1.1-env/raw/nodeip-20261104T105314/10-smoke-20261104T105328.log:3`；全文 `grep -c 'hello xiangshan, I am'` → **1**。

## 3. IP 口径：本次是「执行节点 IP」（与更早的构建机 IP 版本的关键区别）

节点侧日志摘录（作业 `126758114`，`raw/nodeip-20261104T105314/30-hello-nodeip-20261104T105314.log:2-5`；除账号、节点名以占位符替换外逐字保留）：

```
[2026-11-04 10:53:15] hostname=<node> partition=kshcnormal nodelist=<node>
[2026-11-04 10:53:15] hostname -I 输出：10.1.3.35 11.1.3.35 173.1.111.0 173.1.111.1 
[2026-11-04 10:53:15] NODE_IP = 10.1.3.35（IP 来源口径：执行节点 hostname -I 第一个字段；与构建机 IP 无关——即使两者同值，口径仍是「取执行节点」）
```

- 取 IP 的动作发生在**计算节点内**（作业步里），不是构建机：同一份日志 `:7` 记 `应用 Makefile：HOST_IP=10.1.3.35（CFLAGS += -DTARGET_IP）`，`:9-10` 记 `节点内重建：5720 字节 md5=ef1540e4…`、`镜像内含 IP 字符串 10.1.3.35：是`。
- 因此「运行环境 IP」这一读法成立：镜像在节点内编译、IP 取自该节点，冒烟也在同一节点跑。
- 仍然保留的技术限制（不夸大）：nexus-am 是裸机环境、无网络栈，运行期拿不到本机地址，IP 只能**编译期**注入（理由见 `design/verify/cases/hello_identity.c:10` 的注释）；本次把「编译期」从构建机挪到了执行节点。

## 4. 同作业其余判据（作业 `126758114`，`raw/nodeip-20261104T105314/10-build-20261104T105328.{json,log}`）

| 判据 | 状态 | 实测 |
|---|---|---|
| `version_pin` | 达标 | `a4eeaab / 9559211 / a683e0b` |
| `nemu_ref_so` | 达标 | `…/NEMU/build/riscv64-nemu-interpreter-so` 存在 |
| `nm_exec_vdot` | 达标 | `nm` 命中 `exec_vdot` 2 行 |
| `build_emu` | 达标 | `rc=0`，`…/XiangShan/build/emu` |
| `smoke_good_trap` | 达标 | `HIT GOOD TRAP` 1 次（`raw/nodeip-20261104T105314/10-smoke-20261104T105328.log:29847`，pc=`0x8000015c`） |
| `smoke_no_abort` | 达标 | `ABORT=0 BAD=0`（全文 `grep -cE 'ABORT\|HIT BAD TRAP'` → 0） |
| `smoke_hello_identity` | 达标 | `hello xiangshan, I am XinXiangXiangRong, IP: 10.1.3.35`（全文仅 1 处命中，非占位 IP） |

`python3 -I -c "import json;d=json.load(open('stage1/1.1-env/raw/nodeip-20261104T105314/10-build-20261104T105328.json'));print(d['status'],d['slurm_job_id'],[(c['name'],c['status']) for c in d['criteria']])"` → `通过 126758114 [('version_pin','达标'),('nemu_ref_so','达标'),('nm_exec_vdot','达标'),('build_emu','达标'),('smoke_good_trap','达标'),('smoke_no_abort','达标'),('smoke_hello_identity','达标')]`（7/7）。

作业信息：`sbatch -p kshcnormal -N 1 -n 32`，`30-hello-nodeip` v2 脚本（节点内重编 `hello_identity` → `10-build-emu.sh --image` 冒烟），起止 `10:53:14 → 10:54:23`（69 s）；机时记账 `results/budget-log.tsv`：`126758114 … 69 s / 0.613 core-h / 0.019 node-h / P0-emu`。

### 4.1 历史对照作业判据（`126681977`，IP `10.1.11.2`；**不是**当前结论）

| 判据 | 状态 | 实测 |
|---|---|---|
| `smoke_good_trap` | 达标 | `HIT GOOD TRAP` 1 次（`raw/10-smoke-20261103T150714.log:29847`，pc=`0x8000015c`） |
| `smoke_hello_identity` | 达标 | `hello xiangshan, I am XinXiangXiangRong, IP: 10.1.11.2`（全文仅 1 处命中，非占位 IP） |
| 其余 5 项 | 达标 | 同表结构，见 `raw/10-build-20261103T150714.clean.json` |

作业信息（历史）：`15:07:03 → 15:07:58`（55 s）；机时 `126681977 … 56 s / 0.498 core-h / 0.016 node-h / P0-emu`。

冒烟收尾（作业 `126758114`，`raw/nodeip-20261104T105314/10-smoke-20261104T105328.log:29848,29872-29873`）：`instrCnt = 1,775, cycleCnt = 14,024, IPC = 0.126569`、`Guest cycle spent: 14,030`、`Host time spent: 22,952ms`（历史对照作业 `raw/10-smoke-20261103T150714.log` 同位置为 `16,784ms`——host 时间随节点负载变化，**不是** DUT 性能口径）。

## 5. 已知缺陷（如实记录，未修复）

1. **原件 `raw/10-build-20261103T150714.json` 仍不是合法 JSON（原件按「只复制不修改」保留原样）**：`python3 -c "json.load(open(...))"` 报 `Invalid control character at: line 24 column 175 (char 1611)`——第 24 行 `smoke_hello_identity` 的 `actual` 字符串里嵌了裸 CR（`10.1.11.2` 后紧跟 `\r`，源头是冒烟日志第 3 行的 CRLF）。**两条处置已落地（2026-11-04）**：
   - **生成端已修**：`core-package/scripts/10-build-emu.sh` 的 `json_escape` 改成「先删裸控制字符、再转义引号/反斜杠」（与同包 `20-run-difftest.sh` 2026-11-02 的同一修法），此后新出的结果 JSON 不再带裸 CR。
   - **历史件出清洗件**：`core-package/verify/json_sanitize.py`（原件只读、清洗件另存）生成本目录的 `raw/10-build-20261103T150714.clean.json`，`json.load` 通过、与原件**解析等价**（读原件时以 `newline=''` 关闭换行转换后，`json.loads(原件, strict=False) == json.loads(清洗件)` → `True`；默认模式会把原件的裸 CR 读成 LF，该等式为 `False`，见 §6.2）；原件 sha256 仍为 `76163825…`（未改）。
2. **仓库内镜像 ≠ 本次运行镜像**：`raw/nodeip-20261104T105314/hello_identity.nodeip.bin`（作业 `126758114` 节点内编，md5 `ef1540e4…`；历史对照作业 `raw/hello_identity.nodeip.bin` 为 `0086e33b…`）与 `raw/hello_identity.bin`（`design/verify/cases/hello_identity.bin`，md5 `17614aa4…`，字符串里仍是 `192.168.0.4`）是不同产物。仓库这份**不能**用来复现本次身份串；要复现必须按 §7 在节点内重编。
3. **~~生成该日志的脚本不在仓库里~~（2026-11-04 已补）**：原状态是 `core-package/scripts/` 只有 7 个脚本（`00/10/20/30/40/50/90`）、没有 `30-hello-nodeip`，本目录只有它产出的日志。现已按归档日志 `raw/30-hello-nodeip-20261103T150703.log` 逐条复述入库为 **`core-package/scripts/30-hello-nodeip.sh`**（节点内 `hostname -I` 取首字段 → ccwrap `-mabi=lp64` 重编 `hello_identity` → 调 `10-build-emu.sh` 冒烟），复跑路径见 §7。
4. **~~不是终端截图~~（2026-11-04 已补，仅静态截屏）**：`screenshot/1.1-terminal-real-log-20261105.png` 是**真实 X11 终端窗口截屏**（`DISPLAY=:1` gnome-terminal 内实跑 `grep -n 'hello xiangshan' …`、`sed -n '1,3p' … | cat -v`、`sed -n '29844,29848p' …`、`tail -n 2 …` 后由 `import -window <窗口ID>` 抓取）；图中可见身份串 `hello xiangshan, I am XinXiangXiangRong, IP: 10.1.3.35` 与 `Core 0: HIT GOOD TRAP at pc = 0x8000015c`。日志内容未增删改，仅 ANSI 色码由终端渲染成颜色。**动态录屏仍未产出**（截至 2026-11-04 列为待补项）。
5. **本次作业没有重建 emu**：作业 `126758114` 的 `raw/nodeip-20261104T105314/10-build-20261104T105328.log` 显示 `make emu` 走的是既有产物（冒烟日志首行 `emu compiled at Nov  3 2026, 16:19:22`），`build_emu=达标` 只证明 `build/emu` 存在且可跑，不代表该作业从源码重编。

## 6. 打包时实跑的命令与输出

### 6.0 作业 `126758114`（本机，2026-11-04 实跑）

```
$ L=stage1/1.1-env/raw/nodeip-20261104T105314/10-smoke-20261104T105328.log
$ grep -c 'hello xiangshan, I am XinXiangXiangRong, IP: 10.1.3.35' $L
1
$ grep -c 'WARN hello_identity' $L
0
$ grep -c 'HIT GOOD TRAP' $L
1
$ grep -cE 'ABORT|HIT BAD TRAP' $L
0
$ sha256sum stage1/1.1-env/raw/nodeip-20261104T105314/*
e4bea3c950286751735342cb4c246d437ea0ddc39639979d7366d7b24d6b0e0b  …/10-smoke-20261104T105328.log
62598f5b3857d1dfcde965812a143e12949136414a08be121c8fbd8379887bea  …/10-build-20261104T105328.log
a84cea6d6d87dc31af25c0704a13f4f5a8b9ef9aaa4b9978ec453d7672589337  …/10-build-20261104T105328.json
885164f6119f94beb2a404fd75e46fdd40c30a79800691dda7bb4870c26271f4  …/30-hello-nodeip-20261104T105314.log
1d8bf26bec7154180b64b7910f38ca65334a573837a8b986a030646448b97d4c  …/hello_identity.nodeip.bin
3bdcdbae83fb48d4cdbe53d6981ce4ce3cd88bd1ef9bdf63d4c966c94ee42ee0  …/hello-nodeip-126758114.out
$ md5sum stage1/1.1-env/raw/nodeip-20261104T105314/hello_identity.nodeip.bin
ef1540e40b010d98601556eac51c204c  …/hello_identity.nodeip.bin
$ cmp -l stage1/1.1-env/raw/hello_identity.nodeip.bin stage1/1.1-env/raw/nodeip-20261104T105314/hello_identity.nodeip.bin
   4942  61  63
   4943  61  56
   4944  56  63
   4945  62  65
# ↑ 仅 4 字节差异 = IP 串 10.1.11.2 -> 10.1.3.35（其余逐字节相同）
$ python3 -I -c "import json;d=json.load(open('stage1/1.1-env/raw/nodeip-20261104T105314/10-build-20261104T105328.json'));print(d['status'],d['slurm_job_id'],[(c['name'],c['status']) for c in d['criteria']])"
通过 126758114 [('version_pin', '达标'), ('nemu_ref_so', '达标'), ('nm_exec_vdot', '达标'), ('build_emu', '达标'), ('smoke_good_trap', '达标'), ('smoke_no_abort', '达标'), ('smoke_hello_identity', '达标')]
```

### 6.1 历史对照作业 `126681977`（本机，2026-11-04 00:17）

```
$ grep -c 'hello xiangshan, I am XinXiangXiangRong, IP: 10.1.11.2' stage1/1.1-env/raw/10-smoke-20261103T150714.log
1
$ grep -c 'WARN hello_identity' stage1/1.1-env/raw/10-smoke-20261103T150714.log
0
$ grep -c 'HIT GOOD TRAP' stage1/1.1-env/raw/10-smoke-20261103T150714.log
1
$ grep -cE 'ABORT|HIT BAD TRAP' stage1/1.1-env/raw/10-smoke-20261103T150714.log
0
$ sha256sum results/emu/10-smoke-20261103T150714.log stage1/1.1-env/raw/10-smoke-20261103T150714.log
# 两行同值 f70fe719d8dfd1654e0d7946b4ecacf0b862b211a30de42df969dc0a9c9927ba
# 其余 3 份（10-build.log / 10-build.json / 30-hello-nodeip.log）逐份 sha256 与源比对 → 3/3 OK
# 126681977_t1c_hello_ip.out 与 results/logs/ 源件同值 95173125…（上一条 cmp 已证）
$ cmp results/emu/30-hello-nodeip-20261103T150703.log results/logs/126681977_t1c_hello_ip.out && echo HELLO_LOG_EQ_SLURM
HELLO_LOG_EQ_SLURM
$ md5sum stage1/1.1-env/raw/hello_identity.nodeip.bin
0086e33b1739c297dc0c7ae685473e6b  stage1/1.1-env/raw/hello_identity.nodeip.bin
# 与远端 ~/core/.upload/nodeimg/hello_identity.bin 的 md5 相同
```

### 6.2 JSON 清洗的命令与输出（本机，2026-11-04 02:2x）

```
$ python3 -c "import json;json.load(open('stage1/1.1-env/raw/10-build-20261103T150714.json'))"
json.decoder.JSONDecodeError: Invalid control character at: line 24 column 175 (char 1611)
# 原件（按「只复制不修改」保留原样，sha256 76163825… 未变）

$ python3 -I core-package/verify/json_sanitize.py \
      stage1/1.1-env/raw/10-build-20261103T150714.json \
      -o stage1/1.1-env/raw/10-build-20261103T150714.clean.json
[OK] …/10-build-20261103T150714.json：转义 1 处裸控制字符 -> …/10-build-20261103T150714.clean.json（原件未改）

$ python3 -c "import json;json.load(open('stage1/1.1-env/raw/10-build-20261103T150714.clean.json'))"
# 无输出、退出码 0 ⇒ 合法 JSON
$ python3 -I -c "import json;a=json.loads(open('stage1/1.1-env/raw/10-build-20261103T150714.json',newline='').read(),strict=False);b=json.load(open('stage1/1.1-env/raw/10-build-20261103T150714.clean.json'));print(a==b, b['status'], [c['status'] for c in b['criteria']])"
True 通过 ['达标', '达标', '达标', '达标', '达标', '达标', '达标']
# 读原件必须带 newline=''：默认换行转换会把裸 CR 归一成 LF，字符串级比较得 False（与 json_sanitize.py:85-89 同一理由）
# 清洗件与原件解析等价，status=通过、7 条 criteria 全达标
$ sha256sum stage1/1.1-env/raw/10-build-20261103T150714.json
572bd29916a0f43b036e40fa8fea1a3e8b2e63ae07bdd5620a327bac52fffd08  …/10-build-20261103T150714.json
# 原件 sha256 与 §1 表里记的一致 ⇒ 原件确实一个字节都没动
```

## 7. 复跑命令（昆山 `kshcnormal`，节点内取 IP）

一条命令即可（脚本已入库，节点内取 IP + 重编 + 冒烟一并完成；集群账号以 `<account>` 占位，按本机实际账号替换）：

```sh
sbatch -p kshcnormal -N 1 -n 32 --time=02:00:00 \
  -J hello-nodeip -o results/logs/%x-%j.out \
  core-package/scripts/30-hello-nodeip.sh \
  --src-root /public/home/<account>/core/src \
  --am-home   /public/home/<account>/core/src/nexus-am
```

脚本内部三步与作业 `126758114` 的日志 `raw/nodeip-20261104T105314/30-hello-nodeip-20261104T105314.log` 的**步骤序列**对应。
（历史注记：更早的归档日志 `raw/30-hello-nodeip-20261103T150703.log` 由**旧版**脚本产出，缺 ccwrap 生成与
「清 AM 静态库缓存」两行；**这两步已在作业 `126758114` 的计算节点内实跑并留痕**——该日志 `:6` 记
`ccwrap 已就绪：…ccwrap-20261104T105314（-mabi=lp64…）`、`:8` 记 `已清空 AM 静态库缓存（am/build、libs/klib/build）`，
故旧注记「尚未在计算节点实跑」**已失效**。）：
① 节点内 `hostname -I` 取首字段 → `NODE_IP`（日志第 3–4 行）；
② 用 ccwrap 包装器强制 `-mabi=lp64` 重编 `hello_identity`（坑：AM 的 `am/arch/isa/riscv64.mk` 只给
`-march=$(MARCH)`、**不带 `-mabi`**，而 xpack `riscv-none-elf-gcc` 13.2.0 默认 `ilp32` ⇒ 只给
`-march=rv64gcv_*` 会报 `cc1: error: ABI requires '-march=rv32'`；同时先清 `am/build`、`libs/klib/build`
缓存，避免旧 ABI 的静态库混链），产物落到 `~/core/.upload/nodeimg/hello_identity.bin`（日志第 6–9 行）；
③ 调 `10-build-emu.sh --image` 冒烟（日志第 10 行往后），结果 JSON 由子脚本产出。

手工等价步骤（脚本缺位时的兜底，与脚本内做的是同一件事）：

```sh
# 在计算节点内（srun/sbatch 作业步里）执行，不要只在登录节点跑：
NODE_IP=$(hostname -I | awk '{print $1}')
cd ~/core/src/nexus-am/apps/hello_identity && make ARCH=riscv64-xs HOST_IP="$NODE_IP"
mkdir -p ~/core/.upload/nodeimg && cp build/hello_identity-riscv64-xs.bin ~/core/.upload/nodeimg/hello_identity.bin
sbatch -p kshcnormal -N 1 -n 32 --time=02:00:00 \
  core-package/scripts/10-build-emu.sh \
  --src-root /public/home/<account>/core/src \
  --image /public/home/<account>/core/.upload/nodeimg/hello_identity.bin
```

产物：`results/emu/30-hello-nodeip-<runid>.log`（本脚本）、`results/emu/10-build-<runid>.json|log`、
`results/emu/10-smoke-<runid>.log`（子脚本）。
注意：手工兜底步骤**不带 ccwrap**，只有在 AM 树已按 `-mabi=lp64` 编译过时才能直接用；否则请用脚本。
