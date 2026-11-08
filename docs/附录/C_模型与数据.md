# 13 模型与数据

本附录收三样东西。一是 Python 参考模型怎么调用，自检覆盖哪些检查。二是性能、面积、时序、功耗、结构覆盖与形式验证的原始数据各在哪个文件，字段是什么意思。三是正文里的比值和百分比怎样从这些原始数据一步步算出来。要核一个数、复看一次测量或加一个用例时从这里进。结论、成立条件与边界仍以正文各章为准，本附录不重复论证。

## 13.1 参考模型

参考模型 `design/verify/vdot_model.py` 是规格 `design/SPEC.md` 的第三份独立实现，不从 RTL 或 NEMU 翻译而来。它按整寄存器工作：输入输出都是 128 位整数，RTL 与 NEMU 的寄存器转储可以直接传入，不需要拆 lane 的适配层。

表 13-1　参考模型的入口与自检项

| 项目 | 位置 | 说明 |
|---|---|---|
| 单次求值 | `design/verify/vdot_model.py:200-213` | `vdot_vv(vs1, vs2)` 返回完整 128 位 `vd`，高 96 位为零 |
| 全状态求值 | `design/verify/vdot_model.py:159-197` | `execute_vdot(...)` 返回 `(vd, vs_dirty, vstart_next, vxsat_next)`，非法时抛 `IllegalInstruction` |
| 非法原因 | `design/verify/vdot_model.py:123-145` | 六条，顺序固定 `VS=OFF → vill → SEW → LMUL → vm → vstart` |
| 写回 | `design/verify/vdot_model.py:148-156` | `writeback(result32, old_vd)` 接收旧 `vd` 后丢弃，把「旧 `vd` 不影响结果」变成可测性质 |
| 编解码 | `design/verify/vdot_model.py:216-250` | `vdot.vv v3, v2, v1` 编码为 `0x3A20A1D7`，`vm=0` 的字不命中 |
| 三算法交叉 | `design/verify/vdot_model_test.py:59-91,141-162` | 算法 B 走 16 位补码 → 19 位符号扩展 → 模 2^19 累加。算法 C 用 `struct` 解包后无限精度累加。两者不一致即失败 |
| 边界常量 | `design/verify/vdot_model_test.py:165-185` | `131072` 与 `−130048` 以字面常量断言，18 位累加器会把前者绕成负数 |
| `vl`/`vta`/`vma` 不变量 | `design/verify/vdot_model_test.py:311-331` | 取 `vl=0,1,4,7,16` 与 `vta`/`vma` 四种组合，结果必须不变 |
| 非法集 | `design/verify/vdot_model_test.py:338-365` | `SEW`、`LMUL`、`vm`、`vstart` 的单条与组合违例 |
| 固定种子随机 | `design/verify/vdot_model_test.py:372-379` | 种子 42，1000 组，高位填随机干扰 |
| 结构与编码 | `design/verify/vdot_model_test.py:386-460` | lane 取位、原始字节 `0x80` 必须解成 −128、32³ 组编解码往返 |
| 状态 | `design/verify/vdot_model_test.py:467-508` | 旧 `vd` 三种预填、`vill`、`mstatus.VS`、`vxsat` 保持 |
| 变异自检 | `design/verify/vdot_model_test.py:511-565` | 三个变异体（旧 `vd` 高位并回、高 96 位写 1、删 `vill`）必须被判失败 |
| 防空过 | `design/verify/vdot_model_test.py:581-601` | 四个被破坏的输出必须被比较函数拒绝，否则整份自检算空过 |

自检的跑法是一条命令：`python3 -I design/verify/vdot_model_test.py`。本地实跑输出 `ALL TESTS PASSED (1142 cases)`，退出码 0。它只回答期望值算得对不对，不验 RTL。RTL 与参考模型是否一致，由差分验证回答。

扩容用例的期望常量另有一道核对：`design/verify/cases/extra_crosscheck.py`。本地实跑输出 `EXTRA_CROSSCHECK cases=224 reads_or_groups=10357 vdot_encs=415 problems=0` 与 `verdict=MATCH`，退出码 0。

## 13.2 数据文件

表 13-2 按测量类别列出原始数据的位置。同一类别里，机读文件与报告文件并存时，取数一律用机读文件。报告文件只用于核对。

表 13-2　原始数据文件与字段

| 项目 | 位置 | 说明 |
|---|---|---|
| 性能汇总 | `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.json` | `summary.<用例>.<指标>` 下有 `values`（四次值）、`median`、`min`、`max`、`range` |
| 性能原始行 | 同上 `runs[].raw_perf_lines[]` | 逐行保留内核打印，如 `PERF L_vdot : ops=1984 cycles=8378 mean=4 median=4 …` |
| 性能汇总表 | `results/difftest/perf-repeat/99-perf-repeat-4x-20261108.summary.tsv` | 表头 1 行 + 数据 13 行，列为 `case / metric / n / values / median / min / max / range` |
| 加速比算式 | 同上 JSON 的 `caliber` | `formula`、`denominator`、`numerator`、`primary`、`integer_print`、`limitations` |
| 基线链 | `results/difftest/b3/91-b3-20261104T115624.log` | `rounds=8 samples=16000 median=16`，逐轮 `chain_free_round` 行可逐轮核对 |
| 面积（两版） | `results/yosys/vdot-k1.stat.json`、`vdot-p2.stat.json` | `modules` 下 `VdotReduce` 一项的 `num_cells` 为通用门数，`num_cells_by_type` 里的 `$_DFFE_PP_` 为触发器数 |
| 最长拓扑路径 | `results/yosys/vdot-k1.ltp.txt`、`vdot-p2.ltp.txt` | 第 3 行 `Longest topological path in VdotReduce (length=22)` / `(length=14)`。长度单位是单元级跳数，不是 ps |
| 晶体管粗估 | `results/yosys/vdot-k1.stat.cmos.txt`、`vdot-p2.stat.cmos.txt` | 末行 `Estimated number of transistors: 4900+`，两版都打印同一档，精度不足以做差值 |
| 向量乘法单元面积 | `results/yosys/vmac_only.stat.json` | 42783 门。触发器为 `$_DFFE_PP_` 709、`$_DFFE_PP0P_` 1、`$_SDFFCE_PN0P_` 128，合计 838 |
| 面积与扩展索引 | `results/yosys/40-area-20261107T095404.json`、`40-area-20261107T104238.json`、`ext-127231914.json` | 前两份的 `metrics[]` 给 `top / cells / transistors_est / longest_path`。`ext-*.json` 另有 `k / width / dff / structure` |
| 时序 | `results/sta/20261108/worst_slack_20261108.tsv` | 列为 `variant / top / clock_ps / worst_slack_ps / path_delay_ps / startpoint / endpoint / rc` |
| 闭合扫描 | `results/sta/20261108/worst_slack_closure_20261108.tsv` | 同上列，周期取 700–1300 ps 六个点 |
| 时序报告 | `results/sta/20261108/reports/*.rpt`、`results/sta/20261108/reports_closure/*.rpt` | 每条路径给 `data arrival time`、`data required time`、`slack` 三行 |
| 功耗 | `results/sta/20261108/power_summary_20261108.tsv` | 列为 `variant / top / mode / clock_ps / input_activity / input_duty / internal_W / switching_W / leakage_W / total_W / note`。`mode` 分 `leakage-only` 与 `synthetic` |
| 结构覆盖 | `results/coverage/20261108T103732/merged30all.coverage/verilator_coverage-summary.txt` | 按 line、toggle、branch 等类别分别给比例与分子分母。`line` 一行即整核顶层行覆盖 |
| 模块级覆盖 | `results/coverage/20261108T103732/merged30all.coverage/coverage_SimTop.log:8772-8776,11167-11171,13262-13266` | 三处 `- <模块名>` 段下的 `tree_line` / `self_line` 行。`tree` 含子模块，`self` 只算本模块 |
| 覆盖输入 | `results/coverage/20261108T103732/merged30all.coverage/dats.list`（30 行）、`results/coverage/20261108T103732/manifest.30.tsv`（表头 1 行 + 数据 30 行） | 前者是合并的 30 份记录文件清单，后者是这 30 例的用例清单 |
| 形式验证 | `results/formal/50-miter-20261104T093531.json` | `criteria[]` 两行：正向 `SUCCESS`、负控 `FAIL`。`scope` 写明只证数据通路 |
| 形式日志 | `results/formal/miter.20261104T093531.yosys.log`、`miter.mutant.20261104T093531.yosys.log` | 含 `Import proof for assert`、`-seq 3`、`24354 variables and 64752 clauses` |

## 13.3 复算方法

表 13-3 给出正文每个比值与百分比的复算步骤。左列是要复算的量，中列是输入，右列是算式与复算所得的值。中间步骤保留原始值，只在最后一步取整。

表 13-3　正文比值与百分比的复算

| 复算目标 | 输入（位置） | 算式与结果 |
|---|---|---|
| `L_vdot` 的逐次中位数 | `design/verify/perf/perf_vdot.c:107-140`，原始行 `ops=1984 cycles=8378` | 逐次 `rdcycle` 差分进直方图，取前缀和跨过 `n/2` 的那个 bin。`mean=4` 是 `8378/1984=4.2228` 的整数商，不是中位数 |
| 整段测量的商 | 同批原始行 | `T_steady`：`4234/4000=1.0585`（打印 1）。`L_vdot_loop`：`13957/2000=6.9785`（打印 6）。`B1`：`12002/2000=6.001`（打印 6）。`B2`：`19335/2000=9.6675`（打印 9） |
| 链级比值 4.0 | 基线链中位数 16，`L_vdot` 中位数 4 | `16/4=4.0`。16 来自 `results/difftest/b3/91-b3-20261104T115624.log` 的 `median=16`，本批 4 次 vdot 运行只重测分母 4 |
| 每指令归一 1.333333 | 同上 | `(16/3)/4=5.333333/4=1.333333`。整数打印为 `5/4=1.25` |
| 面积差值 3.95% | 481 与 500 | `500−481=19`，`19/481=3.9501%`，取 3.95%。触发器 `38−19=19`，新增单元全在触发器 |
| 面积占比 1.12% / 1.17% | 481、500、42783 | `481/42783=1.1243%`、`500/42783=1.1687%`，取 1.12% 与 1.17% |
| 晶体管占比 1.67% | 4900 与 293640 | `4900/293640=1.6687%`，取 1.67%。分子分母都是粗估值 |
| 时序裕量 | `results/sta/20261108/reports_closure/*.rpt` 的 arrival 与 required 两行 | 裕量 = required − arrival。基线版 1100 ps：`1.059468−1.084304=−0.024836 ns=−24.836 ps`。重定时版 700 ps：`0.650−0.658839=−0.008839 ns=−8.839 ps`。750 ps：`0.700−0.658839=0.041161 ns=41.161 ps` |
| 为什么基线版不能用周期减 50 ps | `results/sta/20261108/reports_closure/K1_VdotReduce_1.100ns_20261108.rpt:43-44`、`results/sta/20261108/reports_closure/P2_VdotReduce_0.700ns_20261108.rpt:35-36` | 基线版 required 从周期里扣的是库建立时间 `0.040532 ns`（`1.100−0.040532=1.059468`）。重定时版扣的是输出外部延迟 `0.05 ns`（`0.700−0.05=0.650`）。两版构成不同，不能用同一个减法验算 |
| 动态功耗 | `results/sta/20261108/power_summary_20261108.tsv:4,6,8` | `dynamic = internal + switching`：基线版 `5.527636e-4+3.343002e-4=8.870638e-4 W`。重定时版 `6.113455e-4+3.235936e-4=9.349391e-4 W` |
| 合成档总功耗 | 同上 | `total = dynamic + 合成档 leakage`：基线版 `8.870638e-4+1.778420e-5=9.048480e-4 W=0.904848 mW`。重定时版 `9.349391e-4+1.974309e-5=9.546821e-4 W=0.9546821 mW`。向量乘法单元 `3.524805e-2+7.461944e-4=3.599424e-2 W=35.99424 mW` |
| 漏电换算 | 同表 `leakage_W` 列 | `1.778420e-5 W=17.78420 µW`、`1.974276e-5 W=19.74276 µW`、`7.462668e-4 W=746.2668 µW` |
| 整核行覆盖 67.5% | `113628` 与 `168283` | `113628/168283=67.5220%`，取 67.5% |
| 标注汇总 72.7% | `603019` 与 `829473` | `603019/829473=72.6991%`，取 72.7%。分母与行覆盖不同，两数不可互换 |
| 模块覆盖 1/1、3/3 | `results/coverage/20261108T103732/merged30all.coverage/coverage_SimTop.log` 三处 `tree_line` | 报告打印 `tree_line(1, 0, 100.00)` 与 `tree_line(3, 0, 100.00)`：第一个数是已覆盖计数点、第二个是未覆盖计数点。正文的 1/1 与 3/3 即此比例，不是源码行数 |
| 19 位与 20 位 | `design/SPEC.md:60-63`、`design/verify/area/gen_ext.py:48-51` | `8×(−128)×(−128)=131072 > 2^18−1=131071`，故 K=8 用 19 位。`16×16384=262144 > 2^18−1`，故 K=16 用 20 位。通式 `W=2·SEW+⌊log2 K⌋` |

表中「打印 1」「打印 6」这类整数商来自内核把浮点商截断后打印，复算时要读回原始 `cycles` 与 `ops` 两列，不能把打印值当精确商。

本附录的两次本地实跑是 `python3 -I design/verify/vdot_model_test.py` 与 `python3 -I design/verify/cases/extra_crosscheck.py --quiet`，结果见 13.1。远程的差分验证、时序、功耗、覆盖采集与形式验证都没有重跑，13.2 的路径只指向已归档的原始数据。表 13-3 的算式用这些归档值复算，复算结果与正文一致，但不构成新的测量。
