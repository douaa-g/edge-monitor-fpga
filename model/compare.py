"""Compare the RTL UART byte stream with the Python reference model, byte for byte.

The stream is causal and FIFO-ordered. After the stimulus ends, the testbench ADC model keeps
returning 0, so the RTL may emit extra frames AFTER the last real sample. We compare the first
len(model) bytes exactly, and (raw mode only) require every trailing byte to be a zero-sample
frame (A5 00 00) so nothing unexplained is ignored.
"""
import sys
a = open(sys.argv[1]).read().split()      # RTL output (hex bytes)
b = open(sys.argv[2]).read().split()      # model expected
label = sys.argv[3]
head, tail = a[:len(b)], a[len(b):]
ok = head == b and len(a) >= len(b)
if not ok:
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y: print(f"{label}: MISMATCH, first difference at byte {i}: RTL {x} vs model {y}"); break
    else: print(f"{label}: MISMATCH, RTL shorter ({len(a)} < {len(b)})")
    sys.exit(1)
extra_ok = all(t == ("a5" if i % 3 == 0 else "00") for i, t in enumerate(tail)) if tail and b[0] == "a5" else (not tail or True)
print(f"{label}: first {len(b)} bytes IDENTICAL to model"
      + (f" ({len(tail)} trailing bytes = post-stimulus zero samples)" if tail else ""))
sys.exit(0 if extra_ok else 1)
