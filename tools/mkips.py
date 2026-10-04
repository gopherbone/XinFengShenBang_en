#!/usr/bin/env python3
"""Write an IPS patch (with size-extension record) from original -> built ROM."""
import sys
def make_ips(a, b):
    out = bytearray(b"PATCH"); i = 0; n = len(b)
    a = a + b"\0" * (n - len(a))
    while i < n:
        if a[i] == b[i]: i += 1; continue
        j = i
        while j < n and j - i < 0xFFFF and (a[j] != b[j] or (j + 1 < n and a[j + 1] != b[j + 1] and j + 2 < n)):
            j += 1
        if i == 0x454F46: i -= 1                     # avoid the "EOF" offset
        out += i.to_bytes(3, "big") + (j - i).to_bytes(2, "big") + b[i:j]
        i = j
    out += b"EOF" + n.to_bytes(3, "big")
    return bytes(out)
if __name__ == "__main__":
    a = open(sys.argv[1], "rb").read(); b = open(sys.argv[2], "rb").read()
    open(sys.argv[3], "wb").write(make_ips(a, b))
