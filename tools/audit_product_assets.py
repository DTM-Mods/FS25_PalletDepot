"""Inventory/copy readable pallet material maps for reference; never read shapes or DLC archives.

The runtime uses the installed originals, not this development-only cache.
    python -I tools/audit_product_assets.py
"""
from pathlib import Path
import hashlib
import io
import json
import posixpath
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT.parents[1]
GAME = Path('G:/SteamLibrary/steamapps/common/Farming Simulator 25')
OUT = ROOT / 'build/native_product_assets_v1'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    packages = {p.stem: zipfile.ZipFile(p) for p in (PROFILE / 'mods').glob('*Fed*Pack.zip')}
    indexes = {key: {n.casefold(): n for n in z.namelist()} for key, z in packages.items()}
    copied = {}
    records = []

    def resolve(name, package=None, parent=''):
        if name.startswith('$data/'):
            return None, 'data/' + name[6:]
        return package, posixpath.normpath(posixpath.join(parent, name))

    def read(package, name):
        candidates = [name]
        if Path(name).suffix.lower() == '.png':
            candidates.append(str(Path(name).with_suffix('.dds')).replace('\\', '/'))
        for candidate in candidates:
            if package is None:
                p = GAME / candidate
                if p.is_file():
                    return p.read_bytes(), candidate
            else:
                actual = indexes[package].get(candidate.casefold())
                if actual is not None:
                    return packages[package].read(actual), actual
        return None, name

    def cache(package, name):
        data, actual = read(package, name)
        if data is None:
            return {'source': package or 'base', 'path': name, 'exists': False}
        key = (package or 'base') + '/' + actual
        if key not in copied:
            # Keep original paths in the manifest; new on-disk folders use English names.
            cache_key = key.replace('/Paletten/', '/Pallets/')
            target = OUT / 'textures' / cache_key
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            copied[key] = {'source': package or 'base', 'path': actual, 'exists': True,
                           'cachePath': target.relative_to(ROOT).as_posix(),
                           'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
        return copied[key]

    sources = [(None, p.relative_to(GAME).as_posix(), p.read_bytes())
               for folder in ('pallets', 'bigBagPallet', 'bigBag')
               for p in (GAME / 'data/objects' / folder).rglob('*.xml')]
    for key, z in packages.items():
        sources.extend((key, n, z.read(n)) for n in z.namelist()
                       if n.lower().startswith('paletten/') and n.lower().endswith('.xml'))
    for package, name, data in sources:
        try:
            vehicle = ET.fromstring(data)
        except ET.ParseError:
            continue
        if vehicle.tag != 'vehicle' or vehicle.get('type') not in ('pallet', 'bigBag'):
            continue
        model = vehicle.findtext('base/filename')
        if not model:
            continue
        owner, model = resolve(model, package)
        model_data, model_path = read(owner, model)
        record = {'source': package or 'base', 'vehicle': name, 'model': model_path,
                  'fillTypes': sorted({ft for unit in vehicle.findall('.//fillUnit')
                                       for ft in unit.get('fillTypes', '').split()}),
                  'contentObjects': len(vehicle.findall('pallet/content/object')), 'textures': []}
        if model_data is not None:
            model_xml = ET.fromstring(model_data)
            for file in model_xml.findall('Files/File'):
                texture = file.get('filename', '')
                if Path(texture).suffix.lower() in ('.png', '.dds', '.jpg', '.tga'):
                    source, texture = resolve(texture, owner, posixpath.dirname(model_path))
                    record['textures'].append(cache(source, texture))
        else:
            record['missingModel'] = True
        image = vehicle.findtext('storeData/image')
        if image:
            source, image_path = resolve(image, package)
            picture, actual = read(source, image_path)
            if picture:
                from PIL import Image
                target = OUT / 'store' / (package or 'base') / (Path(name).stem + '.png')
                target.parent.mkdir(parents=True, exist_ok=True)
                Image.open(io.BytesIO(picture)).save(target)
                record['storePreview'] = target.relative_to(ROOT).as_posix()
        records.append(record)

    # Include loose pallet maps even if no current vehicle XML references them.
    for folder in ('pallets', 'bigBagPallet', 'bigBag'):
        for path in (GAME / 'data/objects' / folder).rglob('*.dds'):
            if not path.name.startswith('store_'):
                cache(None, path.relative_to(GAME).as_posix())
    report = {'vehicles': records, 'textureCount': len(copied),
              'textureBytes': sum(v['bytes'] for v in copied.values()),
              'missingTextures': [dict(vehicle=r['vehicle'], **t) for r in records
                                  for t in r['textures'] if not t['exists']],
              'note': 'Readable XML and textures only; no shapes or paid DLC archive extraction.'}
    (OUT / 'inventory.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    for z in packages.values():
        z.close()
    print(f"{len(records)} native pallet definitions; {len(copied)} material maps; "
          f"{report['textureBytes']:,} bytes; {len(report['missingTextures'])} unresolved texture references")
    print(OUT / 'inventory.json')


if __name__ == '__main__':
    main()
