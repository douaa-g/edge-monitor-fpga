"""Bit-exact Python reference model of the edge condition-monitoring brick.

Mirrors rtl/vhdl/ewma_cusum.vhd (drift detector) and rtl/sv/packetizer.sv
(packet format). Integer arithmetic only, so the RTL can be compared bit for bit.
"""
from dataclasses import dataclass

@dataclass(frozen=True)
class Cfg:
    data_w: int = 12        # ADC resolution
    frac: int = 4           # fixed-point fractional bits
    calib_log2: int = 7     # baseline = mean of 2**calib_log2 samples
    ewma_k: int = 3         # smoothing factor alpha = 2**-ewma_k
    cusum_k: int = 96       # CUSUM allowance (fixed-point units, 16 = 1 ADC count)
    cusum_h: int = 720     # CUSUM decision threshold (fixed-point units)
    summary_n: int = 64     # one summary packet every summary_n samples

    @property
    def clamp(self):        # CUSUM statistics saturate here (bounded registers)
        return 4 * self.cusum_h

def core(samples, cfg=Cfg()):
    """Returns per-sample tuples (ewma_out, alarm_pos, alarm_neg)."""
    w = 1 << cfg.calib_log2
    out, acc, base, ew, sp, sn = [], 0, 0, 0, 0, 0
    maxv = (1 << cfg.data_w) - 1
    for n, x in enumerate(samples):
        if n < w:                       # calibration: pass-through, no alarms
            acc += x
            if n == w - 1:
                base = (acc << cfg.frac) >> cfg.calib_log2
                ew = base
            out.append((x, 0, 0))
            continue
        xf = x << cfg.frac
        ew = ew + ((xf - ew) >> cfg.ewma_k)          # arithmetic (floor) shift
        e = xf - base
        sp = min(max(0, sp + e - cfg.cusum_k), cfg.clamp)
        sn = min(max(0, sn - e - cfg.cusum_k), cfg.clamp)
        y = (ew + (1 << (cfg.frac - 1))) >> cfg.frac
        y = min(max(y, 0), maxv)
        out.append((y, int(sp > cfg.cusum_h), int(sn > cfg.cusum_h)))
    return out

def packets(samples, cfg=Cfg(), raw=False):
    """Byte stream the UART must emit. raw: 3 B/sample; event: summaries + alarm events."""
    res = core(samples, cfg)
    stream, prev = bytearray(), 0
    for idx, (x, (y, ap, an)) in enumerate(zip(samples, res)):
        if raw:
            stream += bytes([0xA5, x >> 8, x & 0xFF])
            continue
        flags = ap | (an << 1)
        now = int(flags != 0)
        if now and not prev:
            stream += bytes([0xC7, (idx >> 8) & 0xFF, idx & 0xFF, y >> 8, y & 0xFF, flags])
        prev = now
        if idx % cfg.summary_n == cfg.summary_n - 1:
            stream += bytes([0xB6, (idx >> 8) & 0xFF, idx & 0xFF, y >> 8, y & 0xFF, flags])
    return bytes(stream)
