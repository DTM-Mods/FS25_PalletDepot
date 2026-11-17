"""Cuts the mipmap chain of a block-compressed .dds (DXT1/DXT5/BC4-BC7, also DX10 headers) to its first levels.

GIANTS' TestRunner wants shop images with at most 3 mipmaps ("has 8 mips but only up to 3 are required");
textureTool writes the full chain. The kept levels are copied unchanged, so nothing is re-encoded.

    python tools/dds_mips.py <file.dds> [...] [--keep 3]
render_store.py calls trim() after textureTool.
"""
import struct

SHOP_IMAGE_MIPS = 3
DDSD_MIPMAPCOUNT = 0x20000
BLOCK8 = {b"DXT1", b"ATI1", b"BC4U", b"BC4S"}
BLOCK8_DXGI = {70, 71, 72, 79, 80, 81}               # BC1, BC4


def trim(path, keep=SHOP_IMAGE_MIPS):
    """Keeps the first `keep` mip levels of `path`; returns the number of levels it had."""
    data = open(path, "rb").read()
    if data[:4] != b"DDS ":
        raise ValueError("%s: not a .dds" % path)
    height, width = struct.unpack_from("<II", data, 12)
    flags = struct.unpack_from("<I", data, 8)[0]
    count = struct.unpack_from("<I", data, 28)[0] if flags & DDSD_MIPMAPCOUNT else 1
    fourcc = data[84:88]
    head = 128
    if fourcc == b"DX10":
        head += 20
        block = 8 if struct.unpack_from("<I", data, 128)[0] in BLOCK8_DXGI else 16
    else:
        block = 8 if fourcc in BLOCK8 else 16
    if count <= keep:
        return count
    size = 0
    w, h = width, height
    for _ in range(keep):
        size += max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * block
        w, h = max(1, w // 2), max(1, h // 2)
    out = bytearray(data[:head + size])
    struct.pack_into("<I", out, 28, keep)
    open(path, "wb").write(bytes(out))
    return count


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--keep", type=int, default=SHOP_IMAGE_MIPS)
    a = ap.parse_args()
    for f in a.files:
        had = trim(f, a.keep)
        print("%s: %d -> %d mipmaps" % (f, had, min(had, a.keep)))
