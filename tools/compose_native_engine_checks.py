"""Compose the six actual GIANTS Editor native-cargo renders without changing the model images."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/native_ge_check_v2'


def main():
    target = OUT / 'native_products_six_checks_v1.png'
    if target.exists():
        raise SystemExit('Preserve the earlier comparison; choose a new version.')
    sheet = Image.new('RGB', (1800, 1350), '#edf1f3')
    draw = ImageDraw.Draw(sheet)
    def text(x, y, value, size=27, bold=False):
        font = 'C:/Windows/Fonts/segoeuib.ttf' if bold else 'C:/Windows/Fonts/segoeui.ttf'
        draw.text((x, y), value, font=ImageFont.truetype(font, size), fill='#263b35')
    text(35, 18, 'Actual product models — GIANTS Editor verification', 35, True)
    text(35, 68, 'Native cargo on the rebuilt depot carriers. Albedo view; gameplay physics remain untested.', 24)
    for row, product in enumerate(('lettuce', 'carrot_bags')):
        for col, (size, count, height) in enumerate(((1000, 1, '0.364'), (2500, 3, '0.804'), (5000, 6, '1.464'))):
            x, y = col * 600, 115 + row * 600
            draw.rounded_rectangle((x+12, y, x+588, y+585), 12, fill='white')
            name = 'Open lettuce crates' if product == 'lettuce' else 'Carrot bags'
            text(x+30, y+14, f'{name} — {size:,} L', 27, True)
            im = Image.open(OUT / 'renders' / f'{product}_{size}.png').convert('RGBA')
            im.thumbnail((565, 500), Image.Resampling.LANCZOS)
            sheet.paste(im, (x + (600-im.width)//2, y+52), im)
            text(x+30, y+545, f'{count} layer' + ('s' if count!=1 else '') + f' | {height} m including pallet', 24)
    text(35, 1320, 'Original meshes, UVs and material maps; no HUD pictures on substitute boxes.', 21)
    sheet.save(target)
    print(target)


if __name__ == '__main__':
    main()
