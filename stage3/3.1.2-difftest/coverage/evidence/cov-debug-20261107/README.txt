结构覆盖实跑诊断证据（2026-11-07，昆山）
========================================

目的：95-coverage.sh 实跑时，覆盖构建的 emu 在 `--diff` 用例退出段 SIGSEGV（rc=139），
`.coverage.dat` 为 0 字节。本目录保存复现实验与定位证据。

实验（均为作业内实跑；作业号见 slurm-covdbg*-*.out）：
- dbg1（作业 127126206，已 scancel；日志 slurm-covdbg-127126206.out）
  p1  `--no-diff -i microbench.bin -C 100 --dump-coverage` → **rc=0**，.dat **3 320 861 425 B（3.09 GiB）**
  p2  `--no-diff -i microbench.bin -C 100`（不 dump）        → **rc=0**
  p3  `--diff -i vdot_pos1.bin --dump-coverage`（全跑）      → **rc=139**（SIGSEGV），.dat **0 B**
  p4  gdb（--no-diff，作废：未复现崩溃）
- dbg2（作业 127127119，COMPLETED 17:52；日志 slurm-covdbg2-127127119.out）
  q1  `--diff -i vdot_pos1.bin`（**不 dump**，全跑）          → 用例本身跑完（日志含 `HIT GOOD TRAP` 1 次、
      `Host time spent: 56266ms`），但进程退出段 **rc=139**
  q2  `--diff -i vdot_pos1.bin -C 100 --dump-coverage`       → **rc=0**（截断到 100 条即可正常退出）
  q3  gdb 全跑 + dump 的栈（q3.log）：
        #0 std::_Rb_tree_insert_and_rebalance
        #1 std::_Rb_tree<...>::_Auto_node::_M_insert
        #2 std::map<int, std::string>::operator[]
        #3 VerilatedCovImp::write(std::string const&)
        #4 Emulator::save_coverage()
        #5 Emulator::~Emulator()
        #6 main()

结论（实测，不外推）：
1. 崩溃点不在 difftest 比对、也不在用例执行：q1 用例正常跑完并打印 HIT GOOD TRAP，崩溃发生在退出析构段。
2. `--coverage-toggle` 的 dat 规模不可用：100 条指令即 3.3 GB（全设计 toggle 点，`vtransform.py`
   只认 `.v`、香山为 `.sv`，SRAM/Difftest 的 `coverage_off` 过滤不生效 —— 配方档 T2）。
3. 短跑（-C 100）不崩、全跑崩 ⇒ 与运行规模/线程数相关；gdb 栈显示崩在 VerilatedCovImp::write
   内部的红黑树插入（堆已损坏或线程归并路径有缺陷）。

修复实验（dbg3，作业 127128086）：把 verilator.mk 的 `--coverage-line --coverage-toggle` 改为
`--coverage-line`（备份 verilator.mk.pre-lineonly-20261107，diff 见本目录 dbg3/verilator-mk-lineonly.diff），
重建后跑同样两个冒烟（s1 = vdot_pos1 --diff + dump；s2 = microbench --diff + dump、限 200 万条），
结果见 dbg3/ 与 95-coverage 实跑记录。

日志裁剪说明：p1/p2/q1/q2 原日志各约 4.6 MB（含 3 万行 PERF dump），本目录只保留 head 30 + tail 30，
首行注明原始字节数；q3.log（gdb 栈）完整保留。