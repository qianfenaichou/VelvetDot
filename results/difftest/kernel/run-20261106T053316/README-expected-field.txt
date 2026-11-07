run-20261106T053316 / 93-kcmp-20261106T053316.json 的 static_xcheck.expected 字段说明
=============================================================================
结论：该 JSON 的 `expected` 字符串是**旧格式**，与本轮日志的实际打印行不符；
`actual` 与 `status` 正确，数字不受影响。**原件不改**（它是当时脚本的输出，改字段即篡改记录）。

1. 该件第 25 行（`grep -n '"static_xcheck"' 93-kcmp-20261106T053316.json`）：
     "expected": "KCMP static_xcheck delta=OK"
2. 同一轮日志实际打印（`zcat perf_kernel_cmp.20261106T053316.log.gz | grep 'static_xcheck'`）：
     KCMP static_xcheck static_base=18 measured_base=18 base=OK static_vdot=11 measured_vdot=11 vdot=OK
   ⇒ 行内**没有** `delta=` 字段。用例源码 `design/verify/cases/perf_kernel_cmp.c` 的打印语句
   只有 `static_base/measured_base/base/static_vdot/measured_vdot/vdot` 六项。
3. 根因：`expected` 是 `core-package/scripts/93-run-kcmp.sh` 里写死的字面串。该串在 053316
   那一版还是旧格式（`… delta=OK`）；同一缺陷也是判废轮 `126986221` 被判 `status=未运行`
   的原因（`XCH_ST` 正则匹配了不存在的 `delta=`）。修复后（现行 `:187`）该串为
   `KCMP static_xcheck … base=OK … vdot=OK`，判据改为对 `*base=OK*vdot=OK*` 匹配。
4. 下一轮 `run-20261106T060159/93-kcmp-20261106T060159.json:25` 的 `expected` 已是新格式
   （`KCMP static_xcheck … base=OK … vdot=OK`）⇒ 修复在 060159 之前已落到远端脚本。
5. 因此本件只作「旧脚本输出」引用：引用判据时以日志行（第 2 条）为准，不以 `expected` 为准。
