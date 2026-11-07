#!/usr/bin/env python3
"""解析 perf 镜像在 emu 里打印的 PERF 行，算三口径与 B1/B2 加速比（ALGORITHM §3.4）。

用法：
    python3 design/verify/perf/parse.py 日志1 [日志2 ...] [--json 输出.json]
判据：必须同时出现 L_vdot / T_steady / T_kernel / B1 / B2 五类行，缺任一类退出码 1。

口径约束（2026-11-03 修订：旧版把均值当 L_vdot、且给出跨口径比值）：
  * `median=` 才是 L_*（延迟）口径；`mean=` 是附报的平均值；`cycles_per_op=` 在用例里
    已被定义为 **median 的别名**（见 perf_vdot.c/perf_vadd.c/perf_vmacc.c 的
    print_chain_line）。
  * 旧版优先读 `cycles_per_op` 并把它当延迟 —— 一旦用例把它写成均值，L_vdot 会被
    静默替换成 mean，且与 `VDOT_METRIC L_vdot`（median）不一致。现在显式优先 `median`，
    并**交叉校验** `cycles_per_op == median`，不一致直接报错退出。
  * 不再输出 `L_vdot_over_B1/B2`：那是「依赖链延迟 ÷ 单点整段开销」，两者口径不同、
    不可相除（口径表见 stage3/3.3/report.md §1）。只保留同口径的
    `T_steady_over_B1/B2`（back-to-back 吞吐 ÷ 每点开销，两者都是 per-dot 周期）。
"""
import json
import re
import sys

LINE2 = re.compile(r"PERF\s+(?P<tag>L_vdot|L_vdot_alt|T_steady|T_kernel|B1|B2)\s*:(?P<body>.*)$")
KV = re.compile(
    r"(ops|cycles|cycles_per_op|mean|median|min|max|over|result)"
    r"=(0x[0-9A-Fa-f]+|\d+)"
)
METRIC = re.compile(r"^VDOT_METRIC\s+(?P<name>\S+)\s+(?P<value>\d+)\s*$")


def collect(paths):
    rows = {}
    vd_metrics = {}
    for p in paths:
        with open(p, "r", errors="replace") as f:
            for ln in f:
                m = METRIC.search(ln.strip())
                if m:
                    # VDOT_METRIC 是用例自报的**主指标**（L_* = median）
                    vd_metrics[m.group("name")] = int(m.group("value"))
                    continue
                m = LINE2.search(ln)
                if not m:
                    continue
                kv = dict(KV.findall(m.group("body")))
                rec = {}
                for k, v in kv.items():
                    rec[k] = int(v, 0) if k == "result" else int(v)
                if rec:
                    rows[m.group("tag")] = rec
    return rows, vd_metrics


def pick_latency(tag, rec):
    """延迟口径：median 优先；无 median 时退回 cycles_per_op；两者都在则必须相等。"""
    med = rec.get("median")
    cpo = rec.get("cycles_per_op")
    if med is not None and cpo is not None and med != cpo:
        raise SystemExit(
            "[FATAL] %s 的 median=%d 与 cycles_per_op=%d 不一致：用例把 cycles_per_op "
            "写成了均值？延迟口径必须唯一（median）。" % (tag, med, cpo)
        )
    val = med if med is not None else cpo
    if val is None:
        c, o = rec.get("cycles"), rec.get("ops")
        if c is not None and o:
            val = c // o
    return val


def pick_mean(tag, rec):
    """均值口径：mean 优先；无 mean 时退回 cycles_per_op/整段，再退回 cycles/ops。"""
    if rec.get("mean") is not None:
        return rec["mean"]
    if rec.get("cycles_per_op") is not None:
        return rec["cycles_per_op"]
    c, o = rec.get("cycles"), rec.get("ops")
    if c is not None and o:
        return c // o
    return None


def main(argv):
    paths = [a for a in argv if not a.startswith("--")]
    out_json = None
    if "--json" in argv:
        out_json = argv[argv.index("--json") + 1]
    if not paths:
        print(__doc__)
        return 2
    rows, vd_metrics = collect(paths)
    need = ["L_vdot", "T_steady", "T_kernel", "B1", "B2"]
    missing = [t for t in need if t not in rows]
    if missing:
        print("[未运行] 缺少口径行：%s（日志=%s）" % (",".join(missing), ",".join(paths)))
        return 1

    res = {t: rows[t] for t in need}
    lv = pick_latency("L_vdot", rows["L_vdot"])
    ts = pick_latency("T_steady", rows["T_steady"])
    # B1/B2 是「单点整段开销」：每点周期，无 median 概念，用 cycles_per_op / cycles/ops
    b1 = rows["B1"].get("cycles_per_op") or rows["B1"]["cycles"] // max(rows["B1"].get("ops", 1), 1)
    b2 = rows["B2"].get("cycles_per_op") or rows["B2"]["cycles"] // max(rows["B2"].get("ops", 1), 1)

    # VDOT_METRIC 交叉校验：用例自报的主指标必须与解析出的 median 一致
    metric_mismatch = []
    for name, parsed in (("L_vdot", lv), ("T_steady", ts), ("B1", b1), ("B2", b2)):
        if name in vd_metrics and vd_metrics[name] != parsed:
            metric_mismatch.append("%s: VDOT_METRIC=%d vs PERF行=%d" % (name, vd_metrics[name], parsed))

    summary = {
        "schema": "vdot-perf/2",
        "raw": res,
        "latency_median": {t: pick_latency(t, rows[t]) for t in ("L_vdot", "T_steady")},
        "latency_mean": {t: pick_mean(t, rows[t]) for t in ("L_vdot", "T_steady")},
        "per_dot_overhead": {"B1": b1, "B2": b2},
        # 只保留同口径比值（吞吐 per-dot ÷ 每点开销）；不输出延迟÷开销
        "speedup_same_scope": {
            "T_steady_over_B1": round(b1 / ts, 2) if ts else None,
            "T_steady_over_B2": round(b2 / ts, 2) if ts else None,
        },
        "vd_metrics": vd_metrics,
        "metric_mismatch": metric_mismatch,
        "result_consistency": {
            "vdot_raw": rows["L_vdot"].get("result"),
            "vdot_steady": rows["T_steady"].get("result"),
            "B1": rows["B1"].get("result"),
            "B2": rows["B2"].get("result"),
        },
        "note": "L_vdot 取 median（延迟口径）；B1/B2 为同 VL=8 单点整段开销，"
                "两者口径不同、不可相除（口径表见 stage3/3.3/report.md §1）。result 一致性只作提示，正式比对在 difftest。",
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if out_json:
        with open(out_json, "w") as f:
            json.dump(summary, f, ensure_ascii=False, indent=2)
        print("写入 %s" % out_json)
    if metric_mismatch:
        print("[FATAL] VDOT_METRIC 与 PERF 行解析不一致：" + "; ".join(metric_mismatch))
        return 1
    vals = list(summary["result_consistency"].values())
    if len(set(vals)) != 1:
        print("[警告] 各实现的 result 不一致：核对是否口径/数据不同（正式判据走 difftest）")
    # 加速比解析本身成功即 0（result 一致性只作提示，不影响退出码）
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
