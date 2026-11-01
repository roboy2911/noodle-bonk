"""Renders a quick colored preview PNG of every FBX in a folder (for checking models).

blender --background --factory-startup --python tools/blender/render_previews.py -- assets/models out_dir
"""

import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
os.makedirs(OUT, exist_ok=True)

PALETTE = {
    "Foam": (1.0, 0.41, 0.71), "Sand": (0.92, 0.88, 0.78), "Cyan": (0.31, 0.78, 1.0), "White": (0.96, 0.96, 0.96),
    "Wood": (0.67, 0.47, 0.29), "WoodDark": (0.47, 0.31, 0.18), "Red": (0.92, 0.24, 0.24), "Yellow": (1.0, 0.84, 0.2),
    "Orange": (1.0, 0.55, 0.12), "Black": (0.08, 0.08, 0.08), "Blue": (0.24, 0.55, 1.0), "Green": (0.35, 0.78, 0.35),
    "Leaf": (0.27, 0.67, 0.27), "Bark": (0.59, 0.43, 0.27), "Brown": (0.43, 0.27, 0.16), "Pink": (1.0, 0.41, 0.71),
    "Accent": (0.31, 0.78, 1.0), "ColorA": (1.0, 0.41, 0.71), "ColorB": (1.0, 1.0, 1.0),
}

for file in sorted(f for f in os.listdir(SRC) if f.endswith(".fbx")):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(SRC, file))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for obj in meshes:
        token = obj.name.split("_")[0]
        mat = bpy.data.materials.new(obj.name)
        color = (*PALETTE.get(token, (1, 0, 1)), 1)
        mat.diffuse_color = color
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = color
            bsdf.inputs["Roughness"].default_value = 0.5
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    # Frame everything
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in meshes:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, world))
            hi = Vector(map(max, hi, world))
    center = (lo + hi) / 2
    size = (hi - lo).length
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    direction = Vector((1.0, -1.3, 0.8)).normalized()
    cam.location = center + direction * size * 1.25
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.clip_end = size * 10
    bpy.context.scene.camera = cam
    scene = bpy.context.scene
    # Cycles on the CPU works without a GPU (Workbench/Eevee need one)
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = scene.render.resolution_y = 360
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.78, 0.95, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    scene.collection.objects.link(sun)
    scene.render.filepath = os.path.join(OUT, file[:-4] + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", file)
