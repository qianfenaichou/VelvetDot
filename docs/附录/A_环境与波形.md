# 11 环境与波形

这份附录收三样原始材料：环境与版本记录、vadd 的七级波形图、vdot 的两拍波形。正文第 2、3、5 章给结论与读法，这里只回答文件在哪、看什么、换一台机器怎么重看。路径相对仓库根。

## 11.1 环境记录

表 11-1　环境与构建记录

| 项目 | 位置 | 说明 |
|---|---|---|
| 工具链版本 | `results/env/00-env-20261105T092724.tools.tsv` | 17 行「工具、路径、版本串」 |
| 自检结论 | `results/env/00-env-20261105T092724.json` | 13 条检查，12 条达标；sby 未运行 |
| 版本锚点 | `versions.env` | 香山 `a4eeaab`、yunsuan `9559211`、NEMU `a683e0b` |
| 实施后提交 | 三仓 `git rev-parse --short HEAD` | `913ddd3` / `8942811` / `a9dca53`，与上行不可混用 |
| 构建入口 | `core-package/scripts/10-build-emu.sh` | 编参考模型再 `make emu` |
| 身份串入口 | `core-package/scripts/30-hello-nodeip.sh` | 节点内重编 hello 镜像 |
| 身份输出 | `stage1/1.1-env/raw/nodeip-20261104T105314/10-smoke-20261104T105328.log:3` | `hello xiangshan, I am XinXiangXiangRong, IP: 10.1.3.35` |
| 冒烟收尾 | 同文件 `:29847` | `HIT GOOD TRAP at pc = 0x8000015c` |

工具表只读版本；构建成功的凭据是 `results/emu/10-build-20261104T105328.json` 的 7 条检查全达标，含 `nm` 命中 `exec_vdot`。地址在编译期注入，nexus-am 无网络栈，复看身份串须在执行节点内重编镜像。

## 11.2 vadd 的七级波形

八张图在 `stage1/1.3-vadd/waveform/`，由 `stage1/1.3-vadd/raw/vadd_stages_curated.tsv`（61 列、21 拍）经 `stage1/1.3-vadd/cases/wave_render.py` 渲染；全部 109 拍在 `stage1/1.3-vadd/raw/vadd_stages.tsv`（68 列）。图只画 8408–8420 与 8493–8500，中间 72 拍是发射队列驻留期。

表 11-2　七级波形图与看点

| 项目 | 图 | 看什么 |
|---|---|---|
| 取指 | `vadd_7stage_IF.png` | `0x021101D7` 在 8410、8411、8416 三端口依次出现 |
| 译码 | `vadd_7stage_ID.png` | 8417 拍类型与 `vsew`、`vlmul`、`vm` 同时定格 |
| 重命名 | `vadd_7stage_RN.png` | 8418 拍出现物理号 `0x33` 与 ROB 项 `0x41` |
| 派发 | `vadd_7stage_DP.png` | 8419 拍字段与上一站相同 |
| 发射 | `vadd_7stage_IS.png` | 入队 8419、出队 8494、旁路 8497 |
| 执行 | `vadd_7stage_EX.png` | 8498 拍两源与 `lane_sum=0x8877665544332211` 同拍 |
| 写回 | `vadd_7stage_WB.png` | 8499 拍高 64 位全 `F`，属 tail 填充 |
| 总览 | `vadd_overview_all.png` | 七站各取一个信号 |

表注：即正文第 3 章的图 03-1 至图 03-8。锚点靠指令字定位：窗口内出现 11 次，只有 8416 拍 2 号槽 `valid=1`。

横轴是拍号不是时间。读图先找两个号：`0x33` 与 `0x41`，它们在重命名、派发、发射、写回四站同值，是同一条指令的凭据。八张图都止于写回，提交级信号没抽进逐拍表。

## 11.3 vdot 的两拍波形

vdot 没有分站图，只有摘录与窄窗归档，都在 `stage2/2.2-rtl/wave/`；摘录 49 个信号，覆盖译码到写回与 8 条 `sum_wo`。

表 11-3　vdot 波形文件

| 项目 | 文件 | 说明 |
|---|---|---|
| 标签到路径 | `vcd-scopes-20261105T091811.txt` | 每行「标签、位宽、完整层次名」 |
| 关键信号摘录 | `vdot_wave_20261105T091811.key.vcd` | 14,156 B，拍号沿用源波形不重编号 |
| 窄窗波形 | `vdot_wave_20261105T091811.vcd.gz` | 解压 131,077,177 B，1 ps，8365–8577 |
| 体检结论 | `vdot_wave_20261105T091811.health.json` | 8 项全过：锚点 8417、类型码 `0x067` |

两拍这样排：8499 拍 `fireS1` 为 1，`tree_sum` 与 `tree_car` 更新；8500 拍 `vdot_vd` 变 `0x8780`。两条链可互核：8 个 `sum_wo` 按有符号 16 位相加得 34688；`tree_sum=0x55250` 与 `tree_car=0x33530` 相加为 558976，取低 19 位得 34688，即 `0x8780`。这两条只说明归约这一段自洽，`sum_wo` 是乘法单元给的输入，乘法阵列本身不在核对范围内。摘录里 `clock` 是采样域时钟，恒为 1，查看器中不翻转。

## 11.4 换一台机器复看

先核哈希再重跑，两条链的输出与归档件逐字节相同。

```sh
gzip -dc stage1/1.3-vadd/raw/vadd_wave_20261103T164323.vcd.gz > vadd.vcd
python3 -I stage1/1.3-vadd/cases/vadd_stage_extract.py --vcd vadd.vcd \
  --out-tsv s.tsv --out-md s.md --out-index s.index.txt
gzip -dc stage2/2.2-rtl/wave/vdot_wave_20261105T091811.vcd.gz > vdot.vcd
python3 -I core-package/verify/vdot_wave_probe.py --vcd vdot.vcd \
  --excerpt k.vcd --head h.txt --scopes sc.txt --summary su.txt --json h.json
```

解压后哈希为 `1db87513…` 与 `ef0a6fdb…`。抽取器默认参数即归档时用的：`0x021101D7`、锚点前 8 拍后 100 拍；体检程序默认按 `0x3A20A1D7` 找锚点、按 `0x00008780` 核对低 32 位。两个程序直接读 VCD 文本，查看器不是必需项。

两条链都跑过：vadd 重抽的 TSV 与归档逐字节相同；vdot 体检 8 项全过，回读 9,849 拍无差异；八张图重渲染后与归档 PNG 哈希相同。重跑模拟器出波形需集群与已构建的模拟器，未做。
