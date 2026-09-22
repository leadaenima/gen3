#!/usr/bin/env python3
"""Weather FX 8.2.1 native 3D snow hash-quality proof.
The mobile fast hash must stay statistically uniform and avoid identity collapse.
"""
import math, struct, sys
MASK=0xffffffff

def f32bits(v):
    return struct.unpack('<I',struct.pack('<f',float(v)))[0]
def mix32(x):
    x &= MASK
    x ^= x >> 16; x=(x*2146121005)&MASK
    x ^= x >> 15; x=(x*2221713035)&MASK
    x ^= x >> 16
    return x&MASK
def h(v): return (mix32(f32bits(v)) & 0x00ffffff)/16777216.0

def check(cond,msg):
    print(('PASS ' if cond else 'FAIL ')+msg)
    if not cond: failures.append(msg)
failures=[]
N=200000
vals=[h(i+1.0) for i in range(N)]
uniq=len(set(vals))
bins=[0]*10
for v in vals: bins[min(9,int(v*10))]+=1
expected=N/10
maxdev=max(abs(x-expected) for x in bins)/expected
mean=sum(vals)/N
# one-step correlation
mx=sum(vals[:-1])/(N-1); my=sum(vals[1:])/(N-1)
num=sum((a-mx)*(b-my) for a,b in zip(vals[:-1],vals[1:]))
denx=math.sqrt(sum((a-mx)**2 for a in vals[:-1]));deny=math.sqrt(sum((b-my)**2 for b in vals[1:]))
corr=num/(denx*deny)
check(uniq>=197000,'200k native snow identities retain >=98.5% unique 24-bit hash values')
check(maxdev<0.025,'native hash decile distribution stays within 2.5% of uniform')
check(abs(mean-.5)<.003,'native hash mean stays centered near 0.5')
check(abs(corr)<.02,'adjacent native snow identities have negligible lag-1 correlation')
# Exercise the actual multiplier/offset forms used by the shader.
for mul,off,name in [(1.371,3.1,'hA'),(3.917,1.9,'hC'),(11.17,6.8,'hF'),(41.3,0,'roll')]:
    sample=[h((i+1)*mul+off) for i in range(50000)]
    bb=[0]*10
    for v in sample: bb[min(9,int(v*10))]+=1
    dev=max(abs(x-5000) for x in bb)/5000
    check(dev<.04,f'{name} shader input stream stays visually uniform')
print(f'8.2.1 snow hash quality: {8-len(failures)}/8 PASS; unique={uniq}/{N}; max_decile_dev={maxdev:.4%}; corr={corr:.6f}')
raise SystemExit(1 if failures else 0)
