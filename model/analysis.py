"""Benchmark of the EWMA+CUSUM brick against naive threshold alarms.  ALL DATA IS SIMULATED.

Detectors (all use the same calibration baseline = mean of the first 128 samples):
  raw    : alarm when sample > baseline + T          (classic fixed threshold on the raw ADC value)
  ewma   : alarm when EWMA output > baseline + T     (smoothed threshold, same EWMA as the RTL)
  cusum  : the brick's two-sided CUSUM (bit-exact model of the RTL)
Metrics: false alarms per 1M healthy samples, detection rate and latency (samples after fault onset).
Writes results/summary.json, results/*.png.
"""
import json, numpy as np
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from edge_model import Cfg, core, packets
from gen_signal import episode, healthy

cfg = Cfg(); W = 1 << cfg.calib_log2
rng = np.random.default_rng(2027)

def base_of(x): return x[:W].mean()

def rising(a):
    a = np.asarray(a, bool); r = a & ~np.r_[False, a[:-1]]; return np.flatnonzero(r)

def detect(x):
    """Return dict name -> boolean alarm array (post-calibration only)."""
    b = base_of(x); res = core(list(x), cfg)
    y = np.array([r[0] for r in res]); ap = np.array([r[1] for r in res]); an = np.array([r[2] for r in res])
    out = {"cusum": (ap | an).astype(bool)}
    for T in (18, 24, 30): out[f"raw>+{T}"] = (x > b + T)
    for T in (5, 6, 8):   out[f"ewma>+{T}"] = (y > b + T)
    for v in out.values(): v[:W] = False
    return out

names = None
# ---------- false alarms on healthy data (20 independent 100k runs = 2M samples) ----------
N_H, RUNS = 100_000, 20
fa = {}
for _ in range(RUNS):
    d = detect(healthy(rng, N_H))
    for k, v in d.items(): fa[k] = fa.get(k, 0) + len(rising(v))
total = N_H * RUNS
fa_rate = {k: v / total * 1e6 for k, v in fa.items()}

# ---------- latency on faulty episodes (300 drift + 300 step) ----------
lat = {"drift": {}, "step": {}}; early = {}; missed = {"drift": {}, "step": {}}
EPIS = 300
for kind in ("drift", "step"):
    for _ in range(EPIS):
        x, onset = episode(rng, kind=kind)
        for k, v in detect(x).items():
            pre = len(rising(v[:onset]))
            early[k] = early.get(k, 0) + pre
            hit = np.flatnonzero(v[onset:])
            if len(hit): lat[kind].setdefault(k, []).append(int(hit[0]))
            else: missed[kind][k] = missed[kind].get(k, 0) + 1

def stats(l, kind):
    a = np.array(l) if len(l) else np.array([np.nan])
    return dict(detected=f"{len(l)}/{EPIS}", median=float(np.median(a)), p90=float(np.percentile(a, 90)))
summary = {"samples_healthy": total, "false_alarms_per_1M": fa_rate,
           "drift": {k: stats(v, "drift") for k, v in lat["drift"].items()},
           "step":  {k: stats(v, "step")  for k, v in lat["step"].items()},
           "config": cfg.__dict__}

# ---------- bandwidth ----------
x = healthy(rng, 64 * 1000)
raw_b = len(packets(list(x), cfg, raw=True)); ev_b = len(packets(list(x), cfg, raw=False))
xe, onset = episode(rng, n=64 * 1000, kind="drift")
ev_fault_b = len(packets(list(xe), cfg, raw=False))
summary["bandwidth"] = dict(samples=len(x), raw_bytes=raw_b, event_bytes_healthy=ev_b,
                            reduction_healthy=raw_b / ev_b, event_bytes_with_fault=ev_fault_b,
                            reduction_with_fault=raw_b / ev_fault_b)
json.dump(summary, open("results/summary.json", "w"), indent=1)

# ---------- print ----------
print(f"healthy samples: {total:,}")
print(f"{'detector':10s} {'FA/1M':>8s} | drift: det  med   p90 | step: det  med   p90")
for k in fa_rate:
    d, s = summary["drift"].get(k), summary["step"].get(k)
    f = lambda z: f"{z['detected']:>7s} {z['median']:5.0f} {z['p90']:5.0f}" if z else "   -"
    print(f"{k:10s} {fa_rate[k]:8.1f} | {f(d)} | {f(s)}")
print("bandwidth:", {k: round(v, 2) if isinstance(v, float) else v for k, v in summary["bandwidth"].items()})

# ---------- figures ----------
C = {"cusum": "#2a78d6", "raw": "#eb6834", "ewma": "#1baf7a"}
INK, GRID = "#0b0b0b", "#e4e3df"
plt.rcParams.update({"font.size": 10, "axes.edgecolor": GRID, "axes.labelcolor": "#52514e",
                     "xtick.color": "#52514e", "ytick.color": "#52514e", "axes.spines.top": False,
                     "axes.spines.right": False, "axes.grid": True, "grid.color": GRID, "grid.linewidth": .6})

# Fig 1: one drift episode
rng2 = np.random.default_rng(7); xs, on = episode(rng2, kind="drift")
res = core(list(xs), cfg); y = np.array([r[0] for r in res]); d = detect(xs)
t_c = np.flatnonzero(d["cusum"][on:])[0] + on; t_r = np.flatnonzero(d["raw>+24"][on:])[0] + on
fig, ax = plt.subplots(2, 1, figsize=(9, 5.4), sharex=True, gridspec_kw={"height_ratios": [3, 1.3]})
ax[0].plot(xs, color="#b8b7b0", lw=.8, label="raw ADC samples (simulated)")
ax[0].plot(np.arange(W, len(y)), y[W:], color=C["ewma"], lw=1.6, ls="--", label="EWMA output (RTL model)")
ax[0].axvline(on, color=INK, lw=1, ls=":"); ax[0].text(on - 20, xs.min() - 2, "drift starts", color="#52514e", va="top", ha="right")
ax[0].axvline(t_c, color=C["cusum"], lw=1.6); ax[0].axvline(t_r, color=C["raw"], lw=1.6, ls="-.")
ax[0].text(t_c - 20, xs.max(), f"CUSUM alarm (+{t_c-on})", color=C["cusum"], ha="right", va="top")
ax[0].text(t_r + 20, xs.max(), f"raw +4σ alarm (+{t_r-on})", color=C["raw"], va="top")
ax[0].set_ylabel("ADC counts"); ax[0].legend(loc="upper left", bbox_to_anchor=(0, 0.88), frameon=False)
# CUSUM statistic (recompute from the model definition)
sp, S = 0, []
b = base_of(xs) * 16
for n, v in enumerate(xs):
    if n < W: S.append(0); continue
    sp = min(max(0, sp + (v * 16 - b) - cfg.cusum_k), cfg.clamp); S.append(sp)
ax[1].plot(np.array(S) / 16, color=C["cusum"], lw=1.4); ax[1].axhline(cfg.cusum_h / 16, color=INK, lw=1, ls=":")
ax[1].text(10, cfg.cusum_h / 16 + 2, "decision threshold h", color="#52514e")
ax[1].set_ylabel("CUSUM (counts)"); ax[1].set_xlabel("sample index")
fig.suptitle("Slow drift: CUSUM flags it earlier than a fixed threshold (simulated signal)", x=.01, ha="left", color=INK)
fig.tight_layout(); fig.savefig("results/fig_example_drift.png", dpi=160); plt.close(fig)

# Fig 2: false alarms vs median drift latency (trade-off)
fig, ax = plt.subplots(figsize=(7.2, 4.4))
for k in fa_rate:
    fam = k.split(">")[0]
    lat_k = summary["drift"].get(k)
    if not lat_k: continue
    ax.scatter(max(fa_rate[k], 0.5), lat_k["median"], s=70, color=C[fam], edgecolor="#fcfcfb", linewidth=1.5,
               marker={"cusum": "o", "raw": "s", "ewma": "^"}[fam], zorder=3)
    ax.annotate(k, (max(fa_rate[k], 0.5), lat_k["median"]), textcoords="offset points", xytext=(7, 9 if k=="cusum" else -11), fontsize=8, color="#52514e")
ax.set_xscale("log"); ax.set_xlabel("false alarms per 1M healthy samples (log; 0 plotted at 0.5)")
ax.set_ylabel("median drift detection delay (samples)")
ax.set_title("Detection speed vs false-alarm rate (lower-left is better; simulated)", loc="left", color=INK)
fig.tight_layout(); fig.savefig("results/fig_tradeoff.png", dpi=160); plt.close(fig)
print("figures written")
