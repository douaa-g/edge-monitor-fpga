"""Simulated sensor signals (ADC counts). SIMULATED data: pressure-drop style
trend with noise and an injected slow drift (fouling-like) or step fault."""
import numpy as np

def episode(rng, n=4000, base=1200, sigma=6.0, kind="drift"):
    x = base + rng.normal(0, sigma, n)
    onset = int(rng.integers(1200, 2400))
    if kind == "drift":                       # slow ramp, 0.03..0.08 counts/sample
        slope = rng.uniform(0.03, 0.08)
        x[onset:] += slope * np.arange(n - onset)
    elif kind == "step":
        x[onset:] += rng.uniform(15, 40)
    return np.clip(np.rint(x), 0, 4095).astype(int), onset

def healthy(rng, n=100000, base=1200, sigma=6.0):
    return np.clip(np.rint(base + rng.normal(0, sigma, n)), 0, 4095).astype(int)
