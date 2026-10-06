#!/usr/bin/env python3
"""
vncprobe.py -- connect to a local VNC server and report what it actually serves.

Used by scripts/verify.sh. Speaks just enough RFB (3.x, security type "None")
to fetch one raw framebuffer update and count the distinct colours in it. That
colour count is the proof that the desktop is really rendering rather than
handing back a blank screen.

Prints lines that verify.sh greps for:
    server_version=RFB 003.008
    framebuffer=1280x800
    unique_colors=1816
"""
import socket
import struct
import sys

HOST = "127.0.0.1"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 5901


def main():
    s = socket.create_connection((HOST, PORT), timeout=20)

    version = s.recv(12).decode(errors="replace").strip()
    print("server_version=%s" % version)

    s.sendall(b"RFB 003.008\n")
    n_types = s.recv(1)[0]
    types = s.recv(n_types)
    if 1 not in types:
        print("error=server does not offer the None security type")
        return 1

    s.sendall(b"\x01")               # choose None
    struct.unpack(">I", s.recv(4))   # security result
    s.sendall(b"\x01")               # ClientInit: shared

    hdr = s.recv(24)
    width, height = struct.unpack(">HH", hdr[0:4])
    name_len = struct.unpack(">I", hdr[20:24])[0]
    name = s.recv(name_len).decode(errors="replace")
    print("framebuffer=%dx%d" % (width, height))
    print("desktop_name=%s" % name)

    # 32bpp, depth 24, little-endian, true colour.
    pixel_format = struct.pack(
        ">BBBBHHHBBBBBB",
        32, 24, 0, 1,          # bpp, depth, big-endian flag, true colour
        255, 255, 255,         # max r, g, b
        16, 8, 0,              # shifts
        0, 0, 0,               # padding
    )
    s.sendall(b"\x00" + b"\x00\x00\x00" + pixel_format)
    # SetEncodings: only Raw(0)
    s.sendall(struct.pack(">BBH", 2, 0, 1) + struct.pack(">i", 0))
    # FramebufferUpdateRequest: incremental=0, whole screen
    s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, width, height))

    msg = s.recv(4)
    if len(msg) < 4:
        print("error=no framebuffer update received")
        return 1
    _mtype, _pad, n_rects = struct.unpack(">BBH", msg)

    colors = {}
    for _ in range(n_rects):
        chunk = s.recv(12)
        if len(chunk) < 12:
            break
        _x, _y, rw, rh, _enc = struct.unpack(">HHHHi", chunk)
        nbytes = rw * rh * 4
        data = b""
        while len(data) < nbytes:
            part = s.recv(min(65536, nbytes - len(data)))
            if not part:
                break
            data += part
        # Count distinct colours across the whole rectangle. Reading every
        # pixel of a 1280x800 screen is ~1M lookups, which is fine in CPython
        # and far more reliable than sampling: sampling can miss the sparse
        # text/icon pixels and wrongly report a drawn desktop as blank.
        for i in range(0, len(data) - 3, 4):
            c = data[i:i + 3]
            colors[c] = colors.get(c, 0) + 1

    print("unique_colors=%d" % len(colors))
    top = sorted(colors.items(), key=lambda kv: -kv[1])[:3]
    print("top_colors=%s" % [(c.hex(), n) for c, n in top])

    s.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001 - probe should never crash verify.sh
        print("error=%s" % exc)
        sys.exit(1)
