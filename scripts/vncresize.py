#!/usr/bin/env python3
"""
vncresize.py -- ask a local VNC server to resize its desktop (RFB SetDesktopSize).

This is exactly what noVNC's "resize=remote" mode does: the client advertises the
ExtendedDesktopSize pseudo-encoding and then sends a SetDesktopSize message.
Whether anything happens is entirely up to the server, so scripts/verify.sh uses
this to prove the image's adaptive resolution really works:

    Xvnc 1.15       1280x800 -> 1600x900   (honoured: the desktop resizes)
    x11vnc 0.9.17   1280x800 -> 1280x800   (discarded: why v2 could not do it)

Prints what the server reports before and after. Exit status is 0 only when the
server actually adopted the requested size.

USAGE
    python3 vncresize.py [width] [height] [port]
"""
import socket
import struct
import sys

WIDTH = int(sys.argv[1]) if len(sys.argv) > 1 else 1600
HEIGHT = int(sys.argv[2]) if len(sys.argv) > 2 else 900
PORT = int(sys.argv[3]) if len(sys.argv) > 3 else 5901

EXTENDED_DESKTOP_SIZE = -308


def read_exact(sock, n):
    data = b""
    while len(data) < n:
        part = sock.recv(n - len(data))
        if not part:
            raise EOFError("closed after %d/%d bytes" % (len(data), n))
        data += part
    return data


def server_size(sock):
    """Read one FramebufferUpdate header; return (w, h) or None."""
    try:
        head = read_exact(sock, 4)
    except EOFError:
        return None
    mtype, _pad, nrects = struct.unpack(">BBH", head)
    if mtype != 0:
        return ("msg-type-%d" % mtype, nrects)
    if nrects == 0:
        return (0, 0)
    x, y, w, h, enc = struct.unpack(">HHHHi", read_exact(sock, 12))
    if enc == 0:  # Raw: drain the pixels
        left = w * h * 4
        while left > 0:
            chunk = sock.recv(min(65536, left))
            if not chunk:
                break
            left -= len(chunk)
    return (w, h)


def main():
    s = socket.create_connection(("127.0.0.1", PORT), timeout=15)
    print("server_version=%s" % s.recv(12).decode(errors="replace").strip())
    s.sendall(b"RFB 003.008\n")
    n_types = s.recv(1)[0]
    types = s.recv(n_types)
    if 1 not in types:
        print("error=no None security type")
        return 1
    s.sendall(b"\x01")
    read_exact(s, 4)
    s.sendall(b"\x01")

    hdr = read_exact(s, 24)
    width, height = struct.unpack(">HH", hdr[0:4])
    name_len = struct.unpack(">I", hdr[20:24])[0]
    name = read_exact(s, name_len).decode(errors="replace") if name_len else ""
    print("before=%dx%d name=%s" % (width, height, name))

    # ask for Raw + ExtendedDesktopSize
    s.sendall(struct.pack(">BBH", 2, 0, 2) + struct.pack(">ii", 0, EXTENDED_DESKTOP_SIZE))

    # SetDesktopSize: type 251, pad, w, h, nscreens, pad, then per screen
    msg = struct.pack(">BBHHBB", 251, 0, WIDTH, HEIGHT, 1, 0)
    msg += struct.pack(">IHHHHI", 0, 0, 0, WIDTH, HEIGHT, 0)
    s.sendall(msg)
    print("sent_rect=%dx%d" % (WIDTH, HEIGHT))

    # ask for a full update and see what the server now believes the size is
    s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, width, height))
    size = server_size(s)
    print("after=%s" % (size,))

    s.close()

    if size == (WIDTH, HEIGHT):
        print("resize=honoured")
        return 0
    print("resize=ignored")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        print("error=%s: %s" % (type(exc).__name__, exc))
        sys.exit(1)
