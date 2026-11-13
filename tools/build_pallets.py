"""Build our layered 1,000/2,500/5,000 L pallets and built-in compound collisions.

    blender --background --factory-startup --python tools/build_pallets.py
"""
import os
import sys
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_warehouse as W
import pallet_layout as L

for game_dir in (os.environ.get("FS25_GAME_DIR", ""), W.GAME_DIR,
                 "G:/SteamLibrary/steamapps/common/Farming Simulator 25/"):
    if game_dir and os.path.isfile(os.path.join(game_dir, "data", "shaders", "buildingShader.xml")):
        W.GAME_DIR = game_dir.replace("\\", "/").rstrip("/") + "/"
        break
# Pallets use an ordinary opaque material, without the building weather shader.
W.MATERIALS["depot_stock"] = ("depot_stock_diffuse", None, "depot_stock_specular", False, None)

COL_PALLET = ("0x10004", "0xfe3ffb83")
COL_FLOOR = ("0x10000", "0xfe3dfb83")
COL_TRIGGER = ("0x20000000", "0x20000")


def build_pallet(size):
    hx, hz = L.WIDTH / 2, L.DEPTH / 2
    full_height = L.height(size)
    name = "depotPallet%d" % size
    # The rigid body's own box is only the deck. Forks pass below it between the runners.
    mesh = W.Mesh()
    mesh.box((-hx, L.DECK - 0.022, -hz), (hx, L.DECK, hz), None, False)
    root = W.attrs(mesh.to_object(name + "_component1", None), dynamic=True, compound=True,
                   staticFriction=1.0, dynamicFriction=1.0, density=0.0,
                   collisionFilterGroup=COL_PALLET[0], collisionFilterMask=COL_PALLET[1],
                   nonRenderable=True, castsShadows=False, receiveShadows=False, clipDistance=150.0)
    W.box_shape("dynamicMountTrigger", root, (0, full_height / 2, 0),
                (L.WIDTH + 0.1, full_height + 0.1, L.DEPTH + 0.1),
                kinematic=True, trigger=True, nonRenderable=True,
                collisionFilterGroup=COL_TRIGGER[0], collisionFilterMask=COL_TRIGGER[1])
    mesh = W.Mesh()
    runners = (-hz + 0.06, 0, hz - 0.06)
    for i in range(5):
        z = -hz + 0.07 + i * (L.DEPTH - 0.14) / 4
        mesh.box((-hx, L.DECK - 0.022, z - 0.065), (hx, L.DECK, z + 0.065), W.WOOD, True)
    for z in runners:
        mesh.box((-hx, 0, z - 0.055), (hx, L.DECK - 0.022, z + 0.055), W.WOOD, True)
    W.attrs(mesh.to_object("palletVisual", root), clipDistance=150.0, collision=False)
    content = W.node("content", root)
    # Empty layer holders receive the product's real I3D cargo at runtime.
    # Never substitute a closed carton carrying the HUD icon for product geometry.
    for layer in range(L.LAYERS[size]):
        W.node("goodsLayer%02d" % (layer + 1), content)
    collisions = W.node("collisions", root)
    for index, z in enumerate(runners, 1):
        W.box_shape("floorCollision%02d" % index, collisions, (0, (L.DECK - 0.022) / 2, z),
                    (L.WIDTH, L.DECK - 0.022, 0.11), compoundChild=True,
                    staticFriction=1.0, dynamicFriction=1.0, density=0.0, nonRenderable=True,
                    collisionFilterGroup=COL_FLOOR[0], collisionFilterMask=COL_FLOOR[1])
    # Origin at the bottom: the game's fill animation scales height only.
    mesh = W.Mesh()
    mesh.box((-hx + 0.042, L.DECK, -hz + 0.022),
             (hx - 0.042, full_height, hz - 0.022), None, False)
    W.attrs(mesh.to_object("contentCollision", collisions, location=(0, L.DECK, 0)),
            compoundChild=True, staticFriction=1.0, dynamicFriction=1.0, density=0.0,
            nonRenderable=True, cpuMesh=True, castsShadows=False, receiveShadows=False,
            collisionFilterGroup=COL_PALLET[0], collisionFilterMask=COL_PALLET[1])
    return name


def main():
    for size in L.LAYERS:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.preferences.filepaths.file_preview_type = 'NONE'
        blend = os.path.join(W.ROOT, "build", "depotPallet%d.blend" % size)
        os.makedirs(os.path.dirname(blend), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        W.make_materials()
        name = build_pallet(size)
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        out = os.path.join(W.ROOT, "vehicles", name + ".i3d")
        W.export(out)
        print("EXPORTED", name, "height", L.height(size), "layers", L.LAYERS[size])


if __name__ == "__main__":
    main()
