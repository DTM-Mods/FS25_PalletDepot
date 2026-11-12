"""Draws the icons of the Spawn goods window (gui/PalletDepotSpawn.xml) and converts them to textures/ui_*.dds.

    ui_pallet   a full pallet (the Partial pallet line: full pallets only; any pallet without a shop picture)
    ui_partial  a pallet loaded half way, the rest outlined (the Partial pallet line: the last one takes the rest)
    ui_farm     a barn, white so the window can tint it (the For farm line in single player; in multiplayer the
                game's farm icon is used)
Everything else in the window uses the game's pictures: product icons, the pallet's shop picture.

PNG sources go to src/textures/, like make_textures.py.

    python tools/make_ui_icons.py
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_textures import SRC, convert  # noqa: E402

N = 512                 # drawn large, scaled down for smooth edges
SIZE = 128
WOOD, WOOD_DARK = (205, 160, 104, 255), (150, 108, 64, 255)
GOODS, GOODS_LIGHT = (46, 140, 61, 255), (92, 196, 104, 255)
WHITE = (255, 255, 255, 255)


def canvas():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def pallet(d, x, y, w, h):
    """A loaded pallet seen from the front, its top left corner at x, y."""
    base = h * 0.26
    gx, gw, gh = x + w * 0.06, w * 0.88, h - base
    d.rounded_rectangle([gx, y, gx + gw, y + gh], radius=w * 0.05, fill=GOODS)
    d.rounded_rectangle([gx, y, gx + gw, y + gh * 0.16], radius=w * 0.05, fill=GOODS_LIGHT)
    d.line([gx + gw * 0.5, y + gh * 0.16, gx + gw * 0.5, y + gh], fill=(30, 105, 44, 255), width=max(2, int(w * 0.02)))
    by = y + gh
    board = base * 0.32
    d.rectangle([x, by, x + w, by + board], fill=WOOD)
    for bx in (x, x + w * 0.42, x + w * 0.84):
        d.rectangle([bx, by + board, bx + w * 0.16, by + base - board], fill=WOOD_DARK)
    d.rectangle([x, by + base - board, x + w, by + base], fill=WOOD)


def icon_pallet():
    img, d = canvas()
    pallet(d, N * 0.1, N * 0.16, N * 0.8, N * 0.7)
    return img


def icon_partial():
    img, d = canvas()
    x, y, w, h = N * 0.1, N * 0.16, N * 0.8, N * 0.7
    base = h * 0.26
    gx, gw, gh = x + w * 0.06, w * 0.88, h - base
    # the missing part: a dashed outline
    dash, t = N * 0.045, int(N * 0.018)
    top, mid = y, y + gh * 0.5
    xx = gx
    while xx < gx + gw:
        d.line([xx, top, min(xx + dash, gx + gw), top], fill=GOODS_LIGHT, width=t)
        xx += dash * 1.8
    yy = top
    while yy < mid:
        for sx in (gx, gx + gw):
            d.line([sx, yy, sx, min(yy + dash, mid)], fill=GOODS_LIGHT, width=t)
        yy += dash * 1.8
    # the goods on it and the pallet
    pallet(d, x, mid, w, h - (mid - y))
    return img


def icon_farm():
    img, d = canvas()
    # barn: walls, gambrel roof, door with a cross; the door is cut out so the tint shows its shape
    d.polygon([(N * 0.12, N * 0.44), (N * 0.22, N * 0.22), (N * 0.5, N * 0.08), (N * 0.78, N * 0.22),
               (N * 0.88, N * 0.44), (N * 0.88, N * 0.9), (N * 0.12, N * 0.9)], fill=WHITE)
    door = [N * 0.34, N * 0.52, N * 0.66, N * 0.9]
    d.rectangle(door, fill=(0, 0, 0, 0))
    t = N * 0.035
    d.rectangle([door[0], door[1], door[2], door[1] + t], fill=WHITE)
    d.line([door[0], door[1], door[2], door[3]], fill=WHITE, width=int(t))
    d.line([door[2], door[1], door[0], door[3]], fill=WHITE, width=int(t))
    d.rectangle([N * 0.44, N * 0.27, N * 0.56, N * 0.39], fill=(0, 0, 0, 0))    # loft window
    return img


def main():
    os.makedirs(SRC, exist_ok=True)
    paths = []
    for name, fn in (("ui_pallet", icon_pallet), ("ui_farm", icon_farm), ("ui_partial", icon_partial)):
        path = os.path.join(SRC, name + ".png")
        fn().resize((SIZE, SIZE), Image.LANCZOS).save(path)     # RGBA: the background stays clear
        paths.append(path)
    convert(paths)
    print("wrote", ", ".join("textures/%s.dds" % os.path.splitext(os.path.basename(p))[0] for p in paths))


if __name__ == "__main__":
    main()
