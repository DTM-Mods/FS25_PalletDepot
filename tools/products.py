"""Builds the product lists of the four Pallet Depot buildings from game data and tools/product_map.csv.

Sources (read as data only):
  * the game's data/maps/maps_fillTypes.xml: every fill type with a <pallet> entry
  * the FedMods packs in the mods folder (standard and ProEdition): their pallet fill types; a Fed
    building gets the Fed products of EITHER edition (lines of the edition that is not loaded are dropped at load)
  * the Beans & Alpacas and Highlands Fishing DLCs (pdlc_beansAndAlpacasPack, pdlc_highlandsFishingPack): .dlc files
    are encrypted, so DLC_FILLTYPES lists their products by hand (from the game log, "Mod 'pdlc_...': N fill type(s)
    requested")

tools/product_map.csv is the reviewable mapping table: one row per pallet fill type with its building
(food = Food & Drinks, goods = Textiles & Goods, or exclude) and an English name. The English name is only the sort key (lines are listed A-Z
by English name); in game every line shows the fill type's own translated title.

The build fails when a pallet fill type is missing from the table, when a table row matches no source,
or when a building would get more than 255 production lines (the game syncs line indices as one byte).

    python tools/products.py          -> build/products.json
"""
import csv
import json
import os
import sys
import xml.etree.ElementTree as ET
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME_FILLTYPES = r"C:\Program Files (x86)\Steam\steamapps\common\Farming Simulator 25\data\maps\maps_fillTypes.xml"
MODS = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "My Games", "FarmingSimulator2025", "mods")
FED_EDITIONS = {
    "standard": ["FS25_Fed_Mods_Pack.zip", "FS25_Fed_Produktions_Pack.zip"],
    "pro": ["Fed_Mods_Pack_ProEdition.zip", "Fed_Produktions_Pack_ProEdition.zip"],
}
# Beans & Alpacas products (no live animals) plus the fill types of its two crops. Which of them come on pallets
# cannot be read from the encrypted DLC: at load the depots drop every product without a pallet
# (PalletDepotOptionalProducts.lua), so bulk ones (ores, coffee cherries?) simply do not appear.
DLC_FILLTYPES = [
    "BANANA", "BANANABOX", "BANANAFRIEDBOX", "BANANACHIPS", "BANANACANDY", "BANANACAKE", "BANANAJAM", "BANANAMILK",
    "COFFEECHERRIES", "COFFEEBAGS", "COFFEEPACKED", "COFFEECAPSULES", "COFFEEYOGURT", "COFFEEBEVERAGE", "TIRAMISU",
    "ALPACAWOOL", "ALPACAFLEECE", "ALPACASOCKS", "ALPACAPILLOW", "ALPACAPLUSH", "ALPACACHAIR", "ALPACAARMCHAIR",
    "IRONORE", "COPPERORE", "PIGMENTS", "RESIN", "PAINTBUCKETS", "FUNGICIDE",
    # Highlands Fishing (pdlc_highlandsFishingPack, 13 fill types); FISHFOOD, SALMON, TROUT, FRIEDONION, ONIONBAG,
    # ONIONSALT and ONIONSOUP are also Fed products, so they are already listed under that name
    "COAL", "STONEBIG", "CASTLEROCK", "SHINGLEROOF", "SALMONYOUNG", "TROUTYOUNG",
    "FISHFOOD", "SALMON", "TROUT", "FRIEDONION", "ONIONBAG", "ONIONSALT", "ONIONSOUP",
]
MAX_LINES = 255
BUILDINGS = {   # store item -> (building of the mapping table, includes Fed/DLC products); those lines are
    "food": ("food", True),     # dropped at load when their mod is missing (PalletDepotOptionalProducts.lua)
    "goods": ("goods", True),
}


def pallet_types(xml_bytes):
    root = ET.fromstring(xml_bytes.decode("utf-8-sig"))
    return {ft.get("name").upper(): ft.get("title") for ft in root.iter("fillType") if ft.find("pallet") is not None}


def load_sources():
    base = pallet_types(open(GAME_FILLTYPES, "rb").read())
    editions = {}
    for edition, zips in FED_EDITIONS.items():
        types = {}
        for name in zips:
            with zipfile.ZipFile(os.path.join(MODS, name)) as zf:
                types.update(pallet_types(zf.read("fillTypes.xml")))
        editions[edition] = types
    titles = {n: t for types in editions.values() for n, t in types.items()}
    fed = {n: titles[n] for n in sorted(set(titles) - set(base))}
    dlc = {n: None for n in DLC_FILLTYPES if n not in base and n not in fed}
    return base, fed, dlc


def main():
    base, fed, dlc = load_sources()
    rows = list(csv.DictReader(open(os.path.join(HERE, "product_map.csv"), encoding="utf-8")))
    table = {r["fillType"]: r for r in rows}
    errors = []
    if len(table) != len(rows):
        errors.append("duplicate rows in product_map.csv")
    for source, types in (("base", base), ("fed", fed), ("dlc", dlc)):
        for name in types:
            row = table.get(name)
            if row is None:
                errors.append("%s pallet fill type %s is not in product_map.csv" % (source, name))
            elif row["source"] != source:
                errors.append("%s: source should be %s" % (name, source))
    for name, row in table.items():
        if name not in base and name not in fed and name not in dlc:
            errors.append("%s is in product_map.csv but in no source (game update or Fed edition change?)" % name)
        if row["building"] not in ("food", "goods", "exclude"):
            errors.append("%s: unknown building %r" % (name, row["building"]))

    out = {}
    for item, (building, with_fed) in BUILDINGS.items():
        lines = []
        for name, row in table.items():
            if row["building"] != building or (row["source"] == "fed" and not with_fed):
                continue
            title = {"base": base, "fed": fed, "dlc": dlc}[row["source"]].get(name)
            lines.append({"fillType": name, "title": title, "english": row["english"], "source": row["source"]})
        lines.sort(key=lambda l: (l["english"].casefold(), l["fillType"]))
        if len(lines) > MAX_LINES:
            errors.append("%s has %d production lines, the limit is %d" % (item, len(lines), MAX_LINES))
        out[item] = lines

    if errors:
        sys.exit("product lists failed:\n  " + "\n  ".join(errors))
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    with open(os.path.join(ROOT, "build", "products.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1)
    excluded = sum(1 for r in rows if r["building"] == "exclude")
    print("products: " + ", ".join("%s %d" % (k, len(v)) for k, v in out.items()) + " (excluded %d)" % excluded)


if __name__ == "__main__":
    main()
