#!/usr/bin/env python3
# 在 VCD 里按**操作数数值**反查：找出 vadd.vv 的 vs1/vs2/结果真正流经的信号与拍号。
# 用于纠正「按端口号猜」的错误（io_in_2_0 只是固定端口，不一定是本指令走的那个）。
import sys, re
from collections import OrderedDict

def parse_header(fh):
    names=OrderedDict(); cur=[]
    while True:
        line=fh.readline()
        if not line: break
        t=line.strip()
        if t.startswith("$scope"):
            p=t.split()
            if len(p)>=3: cur.append(p[2])
        elif t.startswith("$upscope"):
            if cur: cur.pop()
        elif t.startswith("$var"):
            p=t.split()
            if len(p)>=5: names["/".join(cur+[p[4]])]=p[3]
        elif t.startswith("$enddefinitions"): break
    return names

def blocks(fh):
    t=None; ch=[]
    for line in fh:
        s=line.strip()
        if not s or s[0]=="$": continue
        if s[0]=="#":
            if t is not None: yield t,ch
            t=int(s[1:]); ch=[]
        elif t is not None:
            if s[0]=="b":
                p=s.split()
                if len(p)>=2: ch.append((p[1],p[0][1:]))
            else: ch.append((s[1:],s[0]))
    if t is not None: yield t,ch

def vint(v):
    if not v: return None
    if set(v)<={"0","1"}: return int(v,2)
    if set(v.lower())<=set("0123456789abcdef"): return int(v,16)
    return None

vcd=sys.argv[1]
VA=0x0807060504030201
VB=0x8070605040302010
RES=0x8877665544332211
lo=int(sys.argv[2]) if len(sys.argv)>2 else 0
hi=int(sys.argv[3]) if len(sys.argv)>3 else 1<<62
targets={VA:"vs1",VB:"vs2",RES:"result"}

with open(vcd, errors="replace") as fh:
    names=parse_header(fh)
    code2name={}
    for n,c in names.items(): code2name.setdefault(c,[]).append(n)
    hitcodes={c for c,ns in code2name.items() if any(("vpu" not in n) for n in ns)}
    found=[]
    for t,ch in blocks(fh):
        if t<lo or t>hi: continue
        for c,v in ch:
            iv=vint(v)
            if iv in targets:
                for n in code2name.get(c,[]):
                    if "/vfExuBlock/" in n or "/VialuFix/" in n or "/wbDataPath/" in n or "/dataPath/" in n:
                        found.append((t, targets[iv], iv, n))
print("hits:", len(found))
seen=set()
for t,k,iv,n in found:
    key=(k,n)
    if key in seen: continue
    seen.add(key)
    print("t=%d %-7s %032X %s" % (t,k,iv,n))
