"""Validates the mod and zips it to build/FS25_PalletDepot.zip and build/FS25_LogisticsHub.zip (same content).

The mod is shown as "Logistics Hub" but keeps the zip name FS25_PalletDepot.zip: a new zip name would remove every
building already placed on the current map. FS25_LogisticsHub.zip is the same build under the new name, for the next
map. Never load both at once (same scripts, store items and key binding).

Runs tools/products.py, tools/gen_placeables.py and tools/gen_pallets.py first, then checks: every XML parses; every i3dMapping
resolves to a node of that name; no duplicate nodeIds; every referenced file exists; every $l10n_ key exists
in English and German; at most 255 production lines; Lua syntax and block structure; GIANTS limits
(at most 128 files, Lua files at most 0.5 MB).

    python tools/build_mod.py [--bump] [--ci]
        --bump  raises the last version number in modDesc.xml first
        --ci    skips products.py (it reads the game install and the FedMods zips); the committed
                build/products.json is used instead (GitHub Actions, .github/workflows/build.yml)
        --check-only  validates without creating either ZIP (source-only work)

Model and textures are built separately (make_textures.py, build_warehouse.py in Blender, finish_i3d.py,
render_store.py in Blender).
"""
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)
ZIP_NAMES = ["FS25_PalletDepot", "FS25_LogisticsHub"]     # current map's name first; see the docstring
ZIP = os.path.join(ROOT, "build", ZIP_NAMES[0] + ".zip")
SHIP = ["modDesc.xml", "icon_palletDepot.dds", "icon_palletDepot_clear.dds", "i3d/depot_food.i3d", "i3d/depot_goods.i3d", "i3d/depot.i3d.shapes"]
SHIP_DIRS = {"gui": (".xml",), "placeables": (".xml",), "scripts": (".lua",), "store": (".dds",), "textures": (".dds",),
             "vehicles": (".xml", ".i3d", ".shapes")}
MAX_FILES, MAX_LUA, MAX_LINES = 128, 512 * 1024, 255
BASE_TEXTS = {"typeDesc_pallet", "configuration_valueDefault", "unit_literShort"}     # the game's own texts

errors = []


def check(cond, msg):
    if not cond:
        errors.append(msg)


def bump_version():
    path = os.path.join(ROOT, "modDesc.xml")
    text = open(path, encoding="utf-8").read()
    m = re.search(r"<version>(\d+)\.(\d+)\.(\d+)\.(\d+)</version>", text)
    new = "%s.%s.%s.%d" % (m.group(1), m.group(2), m.group(3), int(m.group(4)) + 1)
    open(path, "w", encoding="utf-8", newline="").write(text.replace(m.group(0), "<version>%s</version>" % new))
    print("version", new, "- add a changelog line to modDesc.xml")


def files():
    out = list(SHIP)
    for d, ext in SHIP_DIRS.items():
        out += sorted("%s/%s" % (d, f) for f in os.listdir(os.path.join(ROOT, d)) if f.endswith(ext))   # ext: tuple
    return out


def i3d_paths(path):
    """Node name -> index path, plus duplicate-nodeId check."""
    root = ET.parse(path).getroot()
    ids = [n.get("nodeId") for n in root.find("Scene").iter() if n.get("nodeId")]
    check(len(ids) == len(set(ids)), "%s: duplicate nodeIds" % path)
    names = {}

    def walk(elem, prefix):
        kids = [c for c in elem if c.tag in ("TransformGroup", "Shape", "Light", "Camera")]
        for i, c in enumerate(kids):
            p = prefix + [str(i)]
            names.setdefault("0>" + "|".join(p), c.get("name"))
            walk(c, p)
    top = [c for c in root.find("Scene") if c.tag in ("TransformGroup", "Shape")]
    names["0>"] = top[0].get("name")
    walk(top[0], [])
    for f in root.find("Files"):
        name = f.get("filename")
        if not name.startswith("$"):
            check(os.path.exists(os.path.join(os.path.dirname(path), name)), "%s: missing %s" % (path, name))
    shapes = root.find("Shapes").get("externalShapesFile")
    check(os.path.exists(os.path.join(os.path.dirname(path), shapes)), "%s: missing %s" % (path, shapes))
    return names


def l10n_keys():
    root = ET.parse(os.path.join(ROOT, "modDesc.xml")).getroot()
    keys = {}
    for t in root.find("l10n"):
        check(t.get("name") not in keys, "modDesc l10n %s is defined twice (the game logs a warning)" % t.get("name"))
        keys[t.get("name")] = {c.tag for c in t if (c.text or "").strip()}
    return keys


def check_placeable(rel, keys):
    path = os.path.join(ROOT, rel)
    text = open(path, encoding="utf-8").read()
    root = ET.fromstring(text.encode("utf-8"))
    i3d = os.path.join(ROOT, root.findtext("base/filename"))
    check(os.path.exists(i3d), "%s: missing i3d %s" % (rel, i3d))
    paths = i3d_paths(i3d) if os.path.exists(i3d) else {}
    for m in root.iter("i3dMapping"):
        check(paths.get(m.get("node")) == m.get("id"),
              "%s: i3dMapping %s -> %s is %r" % (rel, m.get("id"), m.get("node"), paths.get(m.get("node"))))
    check(os.path.exists(os.path.join(ROOT, root.findtext("storeData/image"))), "%s: missing store image" % rel)
    prods = root.findall("productionPoint/productions/production")
    check(len(prods) <= MAX_LINES, "%s: %d production lines (limit %d)" % (rel, len(prods), MAX_LINES))
    ids = [p.get("id") for p in prods]
    check(len(ids) == len(set(ids)), "%s: duplicate production ids" % rel)
    caps = {c.get("fillType") for c in root.iter("capacity")}
    outs = {o.get("fillType") for o in root.iter("output")}
    check(caps == outs, "%s: storage capacities do not match the production lines" % rel)
    for key in set(re.findall(r"\$l10n_([A-Za-z0-9_]+)", text)):
        if key.startswith("fillType_"):
            continue                    # base-game fill type titles
        check(keys.get(key, set()) >= {"en", "de"}, "%s: l10n key %s missing in en/de" % (rel, key))
    return len(prods)


def check_vehicle(rel, keys):
    text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    root = ET.fromstring(text.encode("utf-8"))
    i3d = os.path.join(ROOT, root.findtext("base/filename"))
    check(os.path.exists(i3d), "%s: missing i3d %s" % (rel, i3d))
    paths = i3d_paths(i3d) if os.path.exists(i3d) else {}
    for m in root.iter("i3dMapping"):
        check(paths.get(m.get("node")) == m.get("id"),
              "%s: i3dMapping %s -> %s is %r" % (rel, m.get("id"), m.get("node"), paths.get(m.get("node"))))
    check(os.path.exists(os.path.join(ROOT, root.findtext("storeData/image"))), "%s: missing store image" % rel)
    for key in set(re.findall(r"\$l10n_([A-Za-z0-9_]+)", text)):
        if key in BASE_TEXTS:
            continue
        check(keys.get(key, set()) >= {"en", "de"}, "%s: l10n key %s missing in en/de" % (rel, key))
    if os.path.basename(rel).startswith("depotPallet"):
        import pallet_layout as layout
        capacity = int(root.find("fillUnit/fillUnitConfigurations/fillUnitConfiguration/fillUnits/fillUnit").get("capacity"))
        size = root.find("base/size")
        check(capacity in layout.LAYERS, "%s: unknown capacity" % rel)
        check(abs(float(size.get("height")) - layout.height(capacity)) < 0.000001, "%s: incorrect full height" % rel)
        check(float(size.get("width")) == layout.WIDTH and float(size.get("length")) == layout.DEPTH,
              "%s: incorrect footprint" % rel)
        check(root.find("base/components").get("maxMass") == "400", "%s: missing 400 kg cap" % rel)
        check(len(root.findall("pallet/content/object")) == layout.LAYERS[capacity], "%s: incomplete layer list" % rel)
        part = root.find("animations/animation[@name='fillAnimation']/part")
        check(part is not None and part.get("node") == "contentCollision", "%s: missing fill collision animation" % rel)
        if part is not None:
            check(float(part.get("startScale").split()[1]) == layout.MIN_COLLISION_SCALE,
                  "%s: collision animation minimum differs from the layer controller" % rel)
        scene = ET.parse(i3d).getroot()
        nodes = {n.get("name"): n for n in scene.find("Scene").iter()}
        collision = nodes.get("contentCollision")
        body = scene.find("Scene/Shape")
        check(collision is not None and collision.get("compoundChild") == "true", "%s: no built-in compound child" % rel)
        if collision is not None:
            check(collision.get("collisionFilterGroup") == body.get("collisionFilterGroup")
                  and collision.get("collisionFilterMask") == body.get("collisionFilterMask"), "%s: collision filters differ" % rel)
            check(abs(float(collision.get("translation").split()[1]) - layout.DECK) < 0.000001,
                  "%s: collision origin differs from deck height" % rel)
        check(all("floorCollision%02d" % i in nodes for i in range(1, 4)), "%s: missing fork runner collision" % rel)
        for layer in range(1, layout.LAYERS[capacity] + 1):
            holder = nodes["goodsLayer%02d" % layer]
            check(holder.tag == "TransformGroup" and not list(holder),
                  "%s: native cargo holder contains replacement geometry" % rel)


def lua_texts(rel, keys):
    src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    # whole literal keys only; keys built with ".." (e.g. "pdo_month" .. period) are checked by their full names
    used = set(re.findall(r'getText\(\s*"([A-Za-z0-9_]+)"\s*[,)]', src)) | set(re.findall(r'"((?:depot|pdo)_[A-Za-z0-9_]+)"(?!\s*\.\.)', src))
    for key in used - BASE_TEXTS:
        check(keys.get(key, set()) >= {"en", "de"}, "%s: l10n key %s missing in en/de" % (rel, key))


def lua_ok(rel):
    path = os.path.join(ROOT, rel)
    check(os.path.getsize(path) <= MAX_LUA, "%s: larger than 0.5 MB" % rel)
    src = open(path, encoding="utf-8").read()
    try:
        import lupa
        lua = lupa.LuaRuntime()
        ok, err = lua.eval("function(s, n) local f, e = load(s, n) return f ~= nil, e end")(src, rel)
        check(ok, "%s: %s" % (rel, err))
    except ImportError:
        errors.append("lupa not installed, cannot check Lua syntax")
    # block balance (Lua 5.1 keywords), ignoring strings and comments
    code = re.sub(r"--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|\"(\\.|[^\"\\])*\"|'(\\.|[^'\\])*'", " ", src,
                  flags=re.S)
    opens = len(re.findall(r"\b(function|if|do|repeat)\b", code))
    closes = len(re.findall(r"\b(end|until)\b", code))
    loops = len(re.findall(r"\b(for|while)\b", code))       # their 'do' is already counted
    check(opens == closes, "%s: block keywords unbalanced (%d open, %d close, %d loops)" % (rel, opens, closes, loops))


def main():
    if "--bump" in sys.argv:
        bump_version()
    scripts = ["gen_placeables.py", "gen_pallets.py"] if "--ci" in sys.argv else ["products.py", "gen_placeables.py",
                                                                                     "gen_pallets.py"]
    for script in scripts:
        r = subprocess.run([sys.executable, os.path.join(HERE, script)], capture_output=True, text=True)
        print(r.stdout.strip())
        if r.returncode != 0:
            sys.exit(r.stderr or r.stdout)

    keys = l10n_keys()
    mod = ET.parse(os.path.join(ROOT, "modDesc.xml")).getroot()
    for t, k in keys.items():
        check(k >= {"en", "de"}, "modDesc l10n %s missing en/de" % t)
    ship = files()
    for f in ship:
        check(os.path.exists(os.path.join(ROOT, f)), "missing " + f)
    for item in mod.iter("storeItem"):
        check(item.get("xmlFilename") in ship, "storeItem not shipped: " + item.get("xmlFilename"))
    for src in mod.iter("sourceFile"):
        check(src.get("filename") in ship, "sourceFile not shipped: " + src.get("filename"))
    lines = {f: check_placeable(f, keys) for f in ship if f.startswith("placeables/")}
    for f in ship:
        if f.startswith("vehicles/") and f.endswith(".xml"):
            check_vehicle(f, keys)
    for f in ship:
        if f.startswith("gui/"):
            src = open(os.path.join(ROOT, f), encoding="utf-8").read()
            ET.fromstring(src.encode("utf-8"))
            for key in set(re.findall(r"\$l10n_([A-Za-z0-9_]+)", src)):
                check(keys.get(key, set()) >= {"en", "de"}, "%s: l10n key %s missing in en/de" % (f, key))
        if f.endswith(".lua"):
            lua_ok(f)
            lua_texts(f, keys)
    check(len(ship) <= MAX_FILES, "%d files (limit %d)" % (len(ship), MAX_FILES))
    if errors:
        sys.exit("BUILD FAILED\n  " + "\n  ".join(errors))

    if "--check-only" in sys.argv:
        print("VALIDATION PASSED | version", mod.findtext("version"), "| files", len(ship), "| no archives created")
        return

    os.makedirs(os.path.dirname(ZIP), exist_ok=True)
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in ship:
            zf.write(os.path.join(ROOT, f), f)            # arcname with forward slashes
    print("version", mod.findtext("version"), "| files", len(ship), "| lines",
          ", ".join("%s %d" % (os.path.basename(k)[6:-4], v) for k, v in lines.items()))
    for name in ZIP_NAMES[1:]:
        shutil.copyfile(ZIP, os.path.join(os.path.dirname(ZIP), name + ".zip"))
    for name in ZIP_NAMES:
        path = os.path.join(os.path.dirname(ZIP), name + ".zip")
        print("built", path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    main()
