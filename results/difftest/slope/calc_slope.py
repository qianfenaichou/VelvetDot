#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# calc_slope.py — perf_base_slope 日志的重算脚本（可复算，独立于用例内整数拟合）
#
# 输入：98-run-slope.sh 的作业日志（`SLOPE point` / `SLOPE fit` / `SLOPE fit2` 行都在其中，
#       因为 98-run-slope.sh 把 `SLOPE *` 全部 grep 进主日志）。
# 输出：stdout 表格 + `--json` 指定的 JSON（与 98-run-slope.sh 的 JSON 合并/覆盖指标字段）；
#       退出码 0 = 斜率/截距与用例内拟合一致，且 R² 两式（1−SSres/SStot 与恒等式）精确同值，
#       且 case R² 等于改正值、或等于旧式值（旧式仅用于识别公式修正前二进制写出的日志）；
#       1 = 上述任一不成立。
#
# 复算口径（与 perf_base_slope.c 的 fit_points 逐式一致，整数运算）：
#   · 每点 y = median(rounds 个窗口周期)。C 侧偶数轮取两中位值的**整数除法**平均（向下取整），
#     Python 侧 statistics.median 返回 float 平均 ⇒ 偶数轮两者不等义；本轮 ROUNDS=3（奇数）
#     逐值一致，若改偶数轮须先统一取整口径。
#   · x = N（8/64/512）；b = (n·Sxy − Sx·Sy)/(n·Sxx − Sx²)；a = (Sy·den − num·Sx)/(n·den)
#   · R² = 1 − SSres/SStot，SSres = Σy² − a·Σy − b·Σxy（原始和展开）
#     ⇒ R² = 1 − (den·(n·Syy − Sy²) − num²)/(den·(n·Syy − Sy²))
#   · 交叉验证（独立恒等式）：R² = (n·Σxy − Σx·Σy)² /
#     ((n·Σxx − (Σx)²)·(n·Σyy − (Σy)²))；两式须精确同值（整数交叉相乘比较）并同时打印。
#   · slope_milli = round(1000·b)；intercept_milli = round(1000·a)；r2_micro = round(1e6·R²)
#   · 旧式（2026-11-07 修正前，仅用于识别旧日志的 `SLOPE fit` 行）：
#     ssres_old = Syy·den − num·Sxy；r2_old = 1e6 − round(1e6·n·ssres_old/(den·(n·Syy − Sy²)))
#
# 注意：N=8 的窗口只有 8–24 条指令，rdcycle 括窗可被 OoO 重排（`perf_base_slope.c` 头注），
#   该点的绝对周期不可作结论引用；**两点斜率（fit2，只用 N=64/512）**是稳健性披露，
#   脚本一并打印，告警「三点/两点不一致」不判失败。
import sys
import re
import json
import statistics
import argparse


def parse_log(path):
    """返回 { (ch, cls): { n: [cyc...] } } 与 fit 行字典"""
    raw = {}
    fit_lines = {}
    with open(path, "r", errors="replace") as f:
        for line in f:
            # 现格式：一点一行，`cyc=` 后是逗号分隔的窗口周期 CSV
            m = re.match(r"^SLOPE point ch=(\S+) cls=(\S+) n=(\d+) rounds=(\d+) .*?cyc=(\S+)", line)
            if m:
                ch, cls, n, rounds, csv = m.groups()
                vals = [int(x) for x in csv.split(",") if x != ""]
                raw.setdefault((ch, cls), {})[int(n)] = vals
                continue
            # 兼容旧格式（一窗口一行；早期冒烟镜像是这个格式）
            m = re.match(r"^SLOPE raw ch=(\S+) cls=(\S+) n=(\d+) round=(\d+) cyc=(\d+)", line)
            if m:
                ch, cls, n, r, cyc = m.groups()
                raw.setdefault((ch, cls), {}).setdefault(int(n), []).append(int(cyc))
                continue
            m = re.match(r"^SLOPE fit ch=(\S+) cls=(\S+) .*?slope_milli=(-?\d+) intercept_milli=(-?\d+) r2_micro=(-?\d+) .*?slope_status=(\S+)", line)
            if m:
                ch, cls, sm, im, r2, st = m.groups()
                fit_lines.setdefault((ch, cls), {})["fit"] = (int(sm), int(im), int(r2), st)
                continue
            m = re.match(r"^SLOPE fit2 ch=(\S+) cls=(\S+) .*?slope_milli=(-?\d+)", line)
            if m:
                ch, cls, sm = m.groups()
                fit_lines.setdefault((ch, cls), {})["fit2"] = int(sm)
    return raw, fit_lines


def median_of(xs):
    return statistics.median(xs)


def lsq(xs, ys):
    """与 C fit_points 同式。返回
    (slope_milli, intercept_milli, r2_micro, r2_ident_micro, r2_legacy_micro, cross_ok, num, den)"""
    n = len(xs)
    sx = sum(xs); sxx = sum(x * x for x in xs)
    sy = sum(ys); syy = sum(y * y for y in ys)
    sxy = sum(x * y for x, y in zip(xs, ys))
    num = n * sxy - sx * sy        # n·Sxy
    den = n * sxx - sx * sx        # n·Sxx
    if den == 0:
        return (0, 0, 0, 0, 0, False, num, den)
    slope_milli = _round_ratio(num, den, 1000)
    intercept_milli = _round_ratio(sy * den - num * sx, n * den, 1000)
    sstot_num = n * syy - sy * sy  # n·Syy
    if sstot_num == 0:
        return (slope_milli, intercept_milli, 1000000, 1000000, 1000000, True, num, den)
    # 式 A（定义式）：SSres = Σy² − a·Σy − b·Σxy，代入 a、b 后 n·den·SSres 的原始和展开
    ssres_num = n * den * syy - den * sy * sy + num * sx * sy - n * num * sxy
    r2_micro = 1000000 - _round_ratio(ssres_num, den * sstot_num, 1000000)
    # 式 B（独立恒等式）：num²/(den·Syy)，不经过 SSres
    r2_ident_micro = _round_ratio(num * num, den * sstot_num, 1000000)
    # 恒等式精确同值检查（整数交叉相乘；微值舍入方向可能差 1uu，故比较精确值）
    cross_ok = (ssres_num + num * num == den * sstot_num)
    # 旧式（2026-11-07 修正前代码）：仅用于识别旧二进制写出的 `SLOPE fit` 行
    ssres_old = syy * den - num * sxy
    r2_legacy_micro = 1000000 - _round_ratio(n * ssres_old, den * sstot_num, 1000000)
    return (slope_milli, intercept_milli, r2_micro, r2_ident_micro, r2_legacy_micro,
            cross_ok, num, den)


def _round_ratio(num, den, scale):
    """round(num/den · scale)，与 C round_ratio 同义（|num|·scale 远小于 2^63 的范围内精确）"""
    if den == 0:
        return 0
    neg = (num < 0) != (den < 0)
    an, ad = abs(num), abs(den)
    q = (an * scale + ad // 2) // ad
    return -q if neg else q


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True, help="98-run-slope.sh 主日志（含 SLOPE 行）")
    ap.add_argument("--json", default=None, help="可选：要合并的 JSON 路径（98-run-slope.sh 产物）")
    ap.add_argument("--out-json", default=None, help="可选：写出的 JSON 路径")
    ap.add_argument("--tolerance-slope", type=int, default=2, help="斜率容差（permille）")
    ap.add_argument("--tolerance-r2", type=int, default=2, help="R² 容差（micro）")
    args = ap.parse_args()

    raw, fit_lines = parse_log(args.log)
    if not raw:
        print("[FATAL] 日志里没有 SLOPE point/raw 行（不是 perf_base_slope 的作业日志？）", file=sys.stderr)
        sys.exit(2)

    n_list = sorted({n for k in raw for n in raw[k]})
    groups = sorted(raw.keys())
    ok_all = True
    legacy_groups = []
    rows = []
    for (ch, cls) in groups:
        ys = {}
        for n, cyc in raw[(ch, cls)].items():
            ys[n] = median_of(cyc)
        xs = sorted(ys)
        (slope_milli, intercept_milli, r2_micro, r2_ident_micro, r2_legacy_micro,
         cross_ok, num, den) = lsq(xs, [ys[x] for x in xs])
        rows.append({
            "ch": ch, "cls": cls,
            "points": [{"n": x, "median_cyc": ys[x]} for x in xs],
            "slope_milli": slope_milli, "intercept_milli": intercept_milli,
            "r2_micro": r2_micro, "r2_ident_micro": r2_ident_micro,
            "r2_legacy_micro": r2_legacy_micro, "r2_crosscheck_ok": cross_ok,
            "num": num, "den": den,
        })
        # 用例内拟合对照（斜率/截距严格；R² 允许等于改正值或旧式值）
        fl = fit_lines.get((ch, cls), {})
        if "fit" in fl:
            csm, cim, cr2, cst = fl["fit"]
            d_s = abs(slope_milli - csm)
            if abs(r2_micro - cr2) <= args.tolerance_r2:
                case_formula = "correct"
                r2_tag = ""
            elif abs(r2_legacy_micro - cr2) <= args.tolerance_r2:
                case_formula = "legacy"
                r2_tag = " [LEGACY:日志由公式修正前二进制产出]"
                legacy_groups.append(f"{ch}/{cls}")
            else:
                case_formula = "mismatch"
                r2_tag = " [MISMATCH]"
            rows[-1]["case_r2_micro"] = cr2
            rows[-1]["case_r2_formula"] = case_formula
            ok = ((d_s <= args.tolerance_slope) and (case_formula != "mismatch")
                  and cst == "computed" and cross_ok)
            ok_all = ok_all and ok
            flag = "OK" if ok else "DIFF"
            print(f"[{flag}] {ch}/{cls}: slope={slope_milli/1000:.3f} cyc/dot "
                  f"(case {csm/1000:.3f}) intercept={intercept_milli/1000:.3f} cyc | "
                  f"r2={r2_micro/1e6:.6f} ident={r2_ident_micro/1e6:.6f} "
                  f"(Δ{abs(r2_micro - r2_ident_micro)}uu, cross={'OK' if cross_ok else 'FAIL'}) "
                  f"case_r2={cr2/1e6:.6f}{r2_tag} | rawΔslope={d_s}pp")
        else:
            ok_all = False
            print(f"[NOCASE] {ch}/{cls}: 日志无 SLOPE fit 对照行")
        if "fit2" in fl:
            f2 = fl["fit2"]
            print(f"  fit2（N=64/512 两点）: slope_milli={f2}（用例）"
                  f" | 三点 slope_milli={slope_milli} → 检查是否同量级（不一致只告警不判失败）")

    if legacy_groups:
        print(f"[NOTE] case_r2 与旧式逐值一致的组：{', '.join(legacy_groups)} —— 这些日志的 "
              f"`SLOPE fit` R² 由 2026-11-07 公式修正前的二进制产出；上报 R² 以上行 "
              f"r2=（按原始五阶矩重算）为准。")

    if not (set(n_list) >= {8, 64, 512}):
        print("[WARN] N 集合缺 8/64/512 之一", file=sys.stderr)

    merged = {}
    if args.json:
        try:
            with open(args.json, "r", errors="replace") as f:
                merged = json.load(f)
        except Exception as e:  # noqa: BLE001
            print(f"[WARN] 读 {args.json} 失败：{e}", file=sys.stderr)
    merged["slope_recalc"] = {
        "n_list": n_list,
        "groups": rows,
        "tolerances": {"slope_permille": args.tolerance_slope, "r2_micro": args.tolerance_r2},
        "r2_formula": "1-SSres/SStot; cross-checked with (n*Sxy-Sx*Sy)^2/((n*Sxx-Sx^2)*(n*Syy-Sy^2))",
        "all_r2_crosscheck_ok": all(r.get("r2_crosscheck_ok", False) for r in rows),
        "case_r2_legacy_groups": legacy_groups,
        "all_match_case_fit": ok_all,
    }
    if args.out_json:
        with open(args.out_json, "w") as f:
            json.dump(merged, f, ensure_ascii=False, indent=2)
        print(f"[OK] 已写 {args.out_json}")

    if not ok_all:
        print("[FAIL] 复算与用例内拟合不一致（见上 DIFF/NOCASE 行）")
        sys.exit(1)
    if legacy_groups:
        print(f"[OK] 全部 {len(groups)} 组：三点斜率/截距复算与用例内拟合一致；"
              f"R² 两式（1−SSres/SStot 与恒等式）精确同值；case R² 为旧式（{len(legacy_groups)} 组，"
              f"日志二进制早于公式修正），改正值以上行 r2= 为准")
    else:
        print(f"[OK] 全部 {len(groups)} 组：三点斜率/R² 复算与用例内拟合逐值一致"
              f"（R² 两式交叉同值）")
    sys.exit(0)


if __name__ == "__main__":
    main()