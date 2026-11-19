"""Generate golden vectors: stimulus + expected core outputs + expected UART byte streams.
Run from the repo root:  PYTHONPATH=model python3 model/gen_vectors.py [outdir]"""
import sys, numpy as np
import edge_model as m, gen_signal as g

out = sys.argv[1] if len(sys.argv) > 1 else "results"
rng = np.random.default_rng(2026)
xs = []
for k in ("drift", "step", "drift"):
    x, _ = g.episode(rng, kind=k); xs += list(x)
xs += [0] * 200 + [4095] * 200 + list(rng.integers(0, 4096, 500))   # saturation / edge cases
xs = [int(v) for v in xs]
res = m.core(xs)
with open(f"{out}/vec_core.txt", "w") as f:
    for x, (y, ap, an) in zip(xs, res): f.write(f"{x} {y} {ap} {an}\n")
open(f"{out}/stim.hex", "w").write("\n".join(f"{x:03x}" for x in xs) + "\n")
for name, raw in (("event", False), ("raw", True)):
    open(f"{out}/expected_{name}.hex", "w").write("\n".join(f"{b:02x}" for b in m.packets(xs, m.Cfg(), raw=raw)) + "\n")
print(len(xs), "samples written to", out)
