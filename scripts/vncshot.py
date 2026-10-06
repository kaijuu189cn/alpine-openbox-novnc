#!/usr/bin/env python3
"""
vncshot.py -- save the framebuffer of a local VNC server as a PNG.

Companion to vncprobe.py: the probe counts colours (good for verify.sh), this
one writes an image you can actually look at, which is what you want when the
question is "the screen looks wrong -- what IS on it?".

Pure standard library (no numpy, no PIL); the image is written with zlib.

USAGE
    python3 vncshot.py [port] [out.png]      # defaults: 5901, /tmp/vncshot.png
"""
import socket
import struct
import sys
import zlib

HOST = "127.0.0.1"


def read_exact(sock, n):
    data = b""
    while len(data) < n:
        part = sock.recv(n - len(data))
        if not part:
            raise EOFError("connection closed after %d/%d bytes" % (len(data), n))
        data += part
    return data


def write_png(path, width, height, rgb_rows):
    """rgb_rows: list of bytes objects, one per row, 3 bytes per pixel."""
    raw = b"".join(b"\x00" + row for row in rgb_rows)

    def chunk(tag, payload):
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit truecolour
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", header))
        fh.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        fh.write(chunk(b"IEND", b""))


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5901
    out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/vncshot.png"

    s = socket.create_connection((HOST, port), timeout=20)
    s.recv(12)                       # server version
    s.sendall(b"RFB 003.008\n")
    n_types = s.recv(1)[0]
    types = s.recv(n_types)
    if 1 not in types:
        print("error=server does not offer the None security type")
        return 1
    s.sendall(b"\x01")               # None
    struct.unpack(">I", read_exact(s, 4))
    s.sendall(b"\x01")               # shared

    hdr = read_exact(s, 24)
    width, height = struct.unpack(">HH", hdr[0:4])
    name_len = struct.unpack(">I", hdr[20:24])[0]
    if name_len:
        s.recv(name_len)

    pixel_format = struct.pack(
        ">BBBBHHHBBBBBB",
        32, 24, 0, 1, 255, 255, 255, 16, 8, 0, 0, 0, 0,
    )
    s.sendall(b"\x00" + b"\x00\x00\x00" + pixel_format)
    s.sendall(struct.pack(">BBH", 2, 0, 1) + struct.pack(">i", 0))   # Raw only
    s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, width, height))    # full update

    msg = read_exact(s, 4)
    _mtype, _pad, n_rects = struct.unpack(">BBH", msg)

    # Paint the rectangles onto a black canvas; a Raw update may only cover part
    # of the screen.
    canvas = [bytearray(width * 3) for _ in range(height)]
    for _ in range(n_rects):
        x, y, rw, rh, _enc = struct.unpack(">HHHHi", read_exact(s, 12))
        data = read_exact(s, rw * rh * 4)
        for row in range(rh):
            if y + row >= height:
                break
            src = row * rw * 4
            dst = canvas[y + row]
            for col in range(rw):
                if x + col >= width:
                    break
                i = src + col * 4
                j = (x + col) * 3
                dst[j:j + 3] = data[i:i + 3]
    s.close()

    write_png(out, width, height, canvas)
    print("saved=%s size=%dx%d" % (out, width, height))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        print("error=%s" % exc)
        sys.exit(1)
