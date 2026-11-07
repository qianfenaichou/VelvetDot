# 编码冻结前的冲突复核：Zvbc 占用确认与 C-enc1b 复核（2026-10-31）

## 结论

原 C-enc1（funct6=`001100`/0x0C）**已被 RISC-V 正式 Zvbc 扩展的 `vclmul.vv` 占用**。主线编码改为 **C-enc1b：funct6=`001110`/0x0E**，并在 riscv-opcodes `f24ac23` 全库（含 ratified 与 unratified）复核为 funct3=010 / opcode=0x57 下无占用。新机器码示例：`vdot.vv v3, v2, v1` = `0x3A20A1D7`。

## 复现命令与输出

### 1. 确认 Zvbc 占用原编码（0x0C）

```bash
git clone --depth 1 https://github.com/riscv/riscv-opcodes.git riscv-opcodes-check
cd riscv-opcodes-check
git log -1 --format='%H %cd'   # f24ac23ec9fa947011781a09cd6fd25a7c36dc45 Wed Oct 14 12:04:55 2026 -0700
cat extensions/rv_zvbc
```

输出：

```
vclmul.vv    31..26=0x0C         vm vs2 vs1     14..12=0x2 vd 6..0=0x57
vclmul.vx    31..26=0x0C         vm vs2 rs1     14..12=0x6 vd 6..0=0x57
vclmulh.vv   31..26=0x0D         vm vs2 vs1     14..12=0x2 vd 6..0=0x57
vclmulh.vx   31..26=0x0D         vm vs2 rs1     14..12=0x6 vd 6..0=0x57
```

即 `0x0C/010/0x57` 是 `vclmul.vv`；`0x0D/010/0x57` 是 `vclmulh.vv`。这与 NEMU `encoding.h:1642-1643` 的 `MATCH_VCLMUL_VV 0x30002057` 一致。原 C-enc1 的机器码 `0x3220A1D7` 与 `vclmul.vv v3,v2,v1` 位级相同：`(0x3220A1D7 & 0xfc00707f) == 0x30002057` → `True`。

### 2. 全库扫描候选编码（Python 精确扫描）

```python
# 对 extensions/** 下所有 rv*/opcodes* 文件，匹配
#   31..26=0xNN vm <op> <op> 14..12=0x2 vd 6..0=0x57
# 统计 funct3=0x2 且 opcode=0x57 的占用
```

结果：

| funct6 | 占用 |
|---|---|
| 0x0C (001100) | **占用**：Zvbc `vclmul.vv`（已正式） |
| 0x0D (001101) | **占用**：Zvbc `vclmulh.vv`（已正式） |
| 0x0E (001110) | **空闲** |
| 0x0F (001111) | **占用**：`rv_zvzip`（unratified） |
| 0x11 (010001) | **空闲** |
| 0x13 (010011) | **空闲** |
| 0x15 (010101) | **占用**：`rv_zvabd` `vabd.vv`（unratified） |
| 0x16 (010110) | **占用**：`rv_zvabd` `vabdu.vv`（unratified） |
| 0x28 (101000) | **占用**：`rv_zvdot4a` `vdot4au.vv`（unratified） |
| 0x2A (101010) | **占用**：`rv_zvdot4a` `vdot4asu.vv`（unratified） |
| 0x2C (101100) | **占用**：`rv_zvdot4a` `vdot4a.vv`（unratified） |
| 0x2E (101110) | **空闲** |
| 0x39 (111001) | **空闲** |
| 0x3E (111110) | **占用**：`rv_zvzip`（unratified） |

### 3. 新编码机器码计算

```python
funct6=0b001110; vm=1; vs2=2; vs1=1; funct3=0b010; vd=3; opcode=0b1010111
word = (funct6<<26)|(vm<<25)|(vs2<<20)|(vs1<<15)|(funct3<<12)|(vd<<7)|opcode
# -> 0x3A20A1D7，位域 001110_1_00010_00001_010_00011_1010111
# 与 vclmul 掩码比较：0x38002057 != 0x30002057 → 不冲突
```

## 对旧扫描结论的处理

更早一次扫描的「0 命中」结论有误（原扫描脚本或匹配方式对 `14..12=2` 形式不命中），**已由本记录推翻**。正式文档以 `design/SPEC.md` §2.6/§2.7 与本文档为准。

## 遗留

- 未来若 riscv-opcodes 将 `0x0E` 分配给其他扩展，以同脚本重跑；被占则回退 C-enc2。
- 新编码已同步到：`design/SPEC.md` §0/§1/§2、`design/ARCHITECTURE.md` §4.1 X1/§4.2 N1、`design/verify/vdot_model.py`、`design/verify/vdot_model_test.py`。