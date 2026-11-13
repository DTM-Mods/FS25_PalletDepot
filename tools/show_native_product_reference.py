"""Show the former carton model beside actual installed product shop renders (reference, not runtime proof)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/native_product_assets_v1'


def main():
    target = OUT / 'native_product_reference_v2.png'
    if target.exists():
        raise SystemExit('Reference already exists; preserve it and use a new name.')
    sheet = Image.new('RGB', (1500, 1060), '#eff2f4')
    draw = ImageDraw.Draw(sheet)
    font = 'C:/Windows/Fonts/segoeui.ttf'
    bold = 'C:/Windows/Fonts/segoeuib.ttf'
    def text(x, y, value, size=25, color='#243341', strong=False):
        draw.text((x, y), value, font=ImageFont.truetype(bold if strong else font, size), fill=color)
    def picture(path, box):
        image = Image.open(path).convert('RGBA')
        image = image.crop(image.getbbox())
        image.thumbnail((box[2] - box[0], box[3] - box[1]), Image.Resampling.LANCZOS)
        sheet.paste(image, (box[0] + (box[2] - box[0] - image.width)//2,
                            box[1] + (box[3] - box[1] - image.height)//2), image)
    text(40, 22, 'Restore the actual product cargo', 36, strong=True)
    text(40, 76, 'Native asset reference — original lettuce shop render and carrot material, not a resized in-game test.', 22)
    cards = [(30, 130, 480, 640), (520, 130, 970, 640), (1010, 130, 1460, 640)]
    for card in cards:
        draw.rounded_rectangle(card, 15, fill='white')
    text(52, 150, 'BEFORE: generic cartons', 25, strong=True)
    text(542, 150, 'NATIVE: open lettuce crates', 24, strong=True)
    text(1032, 150, 'CARROT BAG: native texture', 24, strong=True)
    picture(ROOT / 'build/native_restore_originals_v1/src/store/store_depotPallet2500.png', (50, 205, 460, 540))
    picture(OUT / 'store/base/lettuceBoxPallet.png', (540, 205, 950, 540))
    picture(OUT / 'textures/FS25_Fed_Produktions_Pack/Pallets/textures/karottensack.dds', (1030, 205, 1440, 540))
    text(52, 558, 'HUD picture on a closed box.', 23)
    text(542, 558, 'Crates, heads and leaf geometry.', 23)
    text(1032, 558, 'Bag model also found in the pack.', 22)
    text(52, 598, 'Old 2.5K: four layers.', 22)
    text(542, 598, 'Original diffuse / normal / specular.', 21)
    text(1032, 598, 'Its supplied shop image is blank.', 21)
    text(40, 669, 'Corrected layer counts (diagram)', 29, strong=True)
    bottom = 948
    for x, size, count, height in [(165, '1,000 L', 1, '0.364 m'), (665, '2,500 L', 3, '0.804 m'),
                                   (1165, '5,000 L', 6, '1.464 m')]:
        for layer in range(count):
            for column in range(3):
                x0 = x - 60 + column * 53
                y0 = bottom - 20 - (layer + 1) * 28
                draw.rectangle((x0, y0, x0 + 50, y0 + 25), fill='#569879', outline='#214937', width=2)
        draw.rectangle((x-70, bottom-17, x+105, bottom), fill='#b08c60')
        text(x-60, 963, f'{size}: {count} layer' + ('s' if count != 1 else ''), 24, strong=True)
        text(x-60, 999, f'{height}, including wood', 21)
    sheet.save(target)
    print(target)


if __name__ == '__main__':
    main()
