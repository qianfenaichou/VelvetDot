vdot-structural-fixture-selftest.tsv —— 结构覆盖解析器的**合成 fixture 自测**，不是真实覆盖率。
用途：验证 gen_hits.py --statistics 能按 AllCoverage 树取出 6 个模块的 tree_line/tree_toggle。
输入：/tmp/covstat2/coverage_SimTop.log（按 difftest/scripts/coverage/statistics.py 的五段格式手写；
      副本 evidence/coverage_SimTop-fixture.log，便于复核）。
命令：python3 -I stage3/3.1.2-difftest/coverage/gen_hits.py --statistics /tmp/covstat2/coverage_SimTop.log --out /tmp/covstat2
结论：6/6 模块解析成功（VdotReduce 10/10、VIMac64b 50/100、VIMacU 30/40、VIMacSrcTypeModule 8/8、
      VecExceptionGen 20/25、DecodeUnit 300/1000）。真实 RTL 覆盖率【未运行】——预算闸拒绝，见
      evidence/90-budget-summary-kunshan.txt 与 stage3/3.3/sections/coverage.md §D。

2026-11-07 更正（实跑前）：statistics.py:309-315 的元组语义是 (covered, NOT_covered, pct)，
第二项是未覆盖数不是总数；旧解析器把第二项当 line_total，真实数据会把总数算错。现输出列
line_covered / line_not_covered / line_total(=covered+not_covered) / line_pct / toggle 同构；
上表数字按新口径重算（total = covered + not_covered），百分比与元组一致。