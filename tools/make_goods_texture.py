"""Write the opaque carton backing used beneath the product-picture labels.
GoodsLook swaps only the label material's diffuse map when the pallet is filled.

    python -I tools/make_goods_texture.py
"""
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ROOT = os.path.dirname(HERE)
TEXTURE_TOOL = r"C:\Program Files\GIANTS Software\GIANTS_Editor_10.0.14\tools\textureTool.exe"


def main():
    for kind in ("diffuse", "specular"):
        # Opaque carton backing; the product's HUD diffuse replaces this on fill.
        # No stretch-wrap pattern remains, even while the empty pallet loads.
        color = (249, 246, 237, 255) if kind == "diffuse" else (20, 20, 0, 255)
        img = Image.new("RGBA", (512, 512), color)
        png = os.path.join(ROOT, "src", "textures", "pallet_goods_%s.png" % kind)
        os.makedirs(os.path.dirname(png), exist_ok=True)
        img.save(png)
        dds = os.path.join(ROOT, "textures", "pallet_goods_%s.dds" % kind)
        r = subprocess.run([TEXTURE_TOOL, "-inputs", png, "-targetFile", dds, "-ignoreTimestamp", "-silent"],
                           capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(dds):
            sys.exit("textureTool failed for %s:\n%s%s" % (png, r.stdout, r.stderr))
        print("wrote", dds, "opaque carton backing")


if __name__ == "__main__":
    main()
