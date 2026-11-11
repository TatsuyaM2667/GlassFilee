#!/usr/bin/env python3
"""Convert a GF_DUMP frame (premultiplied ARGB) to PNG, composited over a test wallpaper."""
import struct, sys, zlib

src, dst = sys.argv[1], sys.argv[2]
data = open(src, 'rb').read()
w, h = struct.unpack('<ii', data[:8])
px = data[8:]
rows = []
for y in range(h):
    row = bytearray([0])
    for x in range(w):
        b, g, r, a = px[(y * w + x) * 4:(y * w + x) * 4 + 4]
        # wallpaper: diagonal stripes so translucency is visible
        wr, wg, wb = ((230, 120, 60) if ((x + y) // 40) % 2 else (60, 160, 220))
        inv = 255 - a
        row += bytes((min(255, r + wr * inv // 255), min(255, g + wg * inv // 255), min(255, b + wb * inv // 255)))
    rows.append(bytes(row))
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows), 6)) + chunk(b'IEND', b'')
open(dst, 'wb').write(png)
