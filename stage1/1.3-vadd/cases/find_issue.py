#!/usr/bin/env python3
# 按 robIdx/pdest 反查：找出 vadd.vv 在发射级（vfScheduler / bypass）真正流经的信号与拍号。
import sys
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
vcd=sys.argv[1]; ROB=int(sys.argv[2],0); PD=int(sys.argv[3],0)
lo=int(sys.argv[4]) if len(sys.argv)>4 else 0
hi=int(sys.argv[5]) if len(sys.argv)>5 else 1<<62
with open(vcd, errors="replace") as fh:
    names=parse_header(fh)
    c2n={}
    for n,c in names.items(): c2n.setdefault(c,[]).append(n)
    # 只看发射/执行区、且名字里带 robIdx_value 或 pdest 的信号
    cand={c for c,ns in c2n.items() if any(("/inner_vfScheduler/" in n or "/inner_vfExuBlock/" in n or "/inner_bypassNetwork" in n) and ("robIdx_value" in n or n.endswith("_pdest")) for n in ns)}
    last={}
    out=[]
    for t,ch in blocks(fh):
        if t>hi: break
        for c,v in ch:
            if c in cand: last[c]=vint(v)
        if t<lo: continue
        for c,v in ch:
            if c not in cand: continue
            iv=vint(v)
            if iv is None: continue
            for n in c2n[c]:
                if "/inner_vfScheduler/" in n and ("robIdx_value" in n or n.endswith("_pdest")):
                    if iv==ROB and "robIdx" in n:
                        out.append((t,"rob",iv,n))
                if "/inner_bypassNetwork" in n and n.endswith("_pdest") and iv==PD:
                    out.append((t,"pdest",iv,n))
                if "/inner_vfExuBlock/" in n and n.endswith("_pdest") and iv==PD:
                    out.append((t,"pdest",iv,n))
print("rob=0x%X pdest=0x%X hits=%d"%(ROB,PD,len(out)))
seen=set()
for t,k,iv,n in out:
    if (k,n) in seen: continue
    seen.add((k,n)); print("t=%d %s %s"%(t,k,n))
