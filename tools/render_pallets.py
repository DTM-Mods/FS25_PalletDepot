"""Renders the shop pictures of our pallets (512 x 512, transparent) from build/depotPallet<size>.blend and converts
them to store/store_depotPallet<size>.dds. The Spawn goods window shows them, and they are the pallets' store
images (vehicles/depotPallet*.xml, tools/gen_pallets.py).

    blender --background build/depotPallet1000.blend --python tools/render_pallets.py
    blender --background build/depotPallet5000.blend --python tools/render_pallets.py
    blender --background build/depotPallet1000.blend --python tools/render_pallets.py -- --bare

--bare renders the empty wooden pallet (512 x 256) to textures/ui_palletBase.dds: the Spawn goods window puts the
product's icon on it for pallets without a shop picture of their own (e.g. the Fed packs'), so the picture shows
what is on the pallet.

(tools/build_pallets.py writes the .blend files.)
"""
import os
import subprocess
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(bpy.data.filepath)))
TEXTURE_TOOL = r"C:\Program Files\GIANTS Software\GIANTS_Editor_10.0.14\tools\textureTool.exe"
NAME = os.path.splitext(os.path.basename(bpy.data.filepath))[0]        # depotPallet1000 / depotPallet5000
BARE = "--bare" in sys.argv

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
shading = scene.display.shading
shading.light = "STUDIO"
shading.color_type = "TEXTURE"
shading.show_shadows = True
shading.shadow_intensity = 0.35
shading.show_cavity = True
scene.view_settings.view_transform = "Standard"

# only what the game draws: no collisions, triggers or other helpers
visible = []
for obj in bpy.data.objects:
    hidden = obj.type != "MESH" or bool(obj.get("i3D_nonRenderable", False)) or bool(obj.get("i3D_trigger", False)) \
        or obj.get("i3D_collision", None) is not None and not obj.data.materials or (BARE and obj.name == "goods")
    obj.hide_render = hidden
    if not hidden:
        visible.append(obj)
corners = [obj.matrix_world @ Vector(c) for obj in visible for c in obj.bound_box]

cam = bpy.data.objects.new("storeCam", bpy.data.cameras.new("storeCam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.lens = 50


def frame(direction, margin):
    """Places the camera along direction (from the pallet) so the pallet fills the frame up to margin."""
    d = Vector(direction).normalized()
    target = sum(corners, Vector()) / len(corners)
    for _ in range(6):
        lo, hi = 0.5, 60.0
        for _ in range(40):
            mid = (lo + hi) / 2
            cam.location = target + d * mid
            cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
            bpy.context.view_layer.update()
            pts = [world_to_camera_view(scene, cam, c) for c in corners]
            span = max(max(p.x for p in pts) - min(p.x for p in pts), max(p.y for p in pts) - min(p.y for p in pts))
            lo, hi = (lo, mid) if span < 1 - 2 * margin else (mid, hi)
        cx = (max(p.x for p in pts) + min(p.x for p in pts)) / 2 - 0.5
        cy = (max(p.y for p in pts) + min(p.y for p in pts)) / 2 - 0.5
        right = cam.matrix_world.to_3x3() @ Vector((1, 0, 0))
        up = cam.matrix_world.to_3x3() @ Vector((0, 1, 0))
        target = target + (right * cx + up * cy) * hi * 0.7


scene.render.resolution_x = 512        # before framing: the aspect decides the fit
scene.render.resolution_y = 256 if BARE else 512
frame((-0.62, -0.75, 0.48), 0.04 if BARE else 0.06)     # front-left from above (Blender: z up), like the game's
scene.render.film_transparent = True                       # pallet pictures
scene.render.image_settings.color_mode = "RGBA"
if BARE:
    png = os.path.join(ROOT, "src", "textures", "ui_palletBase.png")
else:
    png = os.path.join(ROOT, "src", "store", "store_%s.png" % NAME)
os.makedirs(os.path.dirname(png), exist_ok=True)
scene.render.filepath = png
bpy.ops.render.render(write_still=True)

dds = os.path.join(ROOT, "textures", "ui_palletBase.dds") if BARE else os.path.join(ROOT, "store", "store_%s.dds" % NAME)
r = subprocess.run([TEXTURE_TOOL, "-inputs", png, "-targetFile", dds, "-ignoreTimestamp", "-silent"],
                   capture_output=True, text=True)
if r.returncode != 0 or not os.path.exists(dds):
    sys.exit("textureTool failed for %s:\n%s%s" % (png, r.stdout, r.stderr))
print("PALLET IMAGE DONE", dds)
