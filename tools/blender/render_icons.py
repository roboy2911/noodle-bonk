"""Renders the 3D parts of the shop icons (transparent PNGs) with Cycles.

blender --background --factory-startup --python tools/blender/render_icons.py -- assets/models out_dir

tools/make_icons.py then adds backgrounds and text. Renders:
  skins.png  - gold, rainbow and galaxy noodles fanned out
  vip.png    - a gold crown with gems
  double.png - a big pink noodle swooshing
  party.png  - rubber duck, beach ball and swim ring with confetti
"""

import math
import os
import random
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
MODELS, OUT = args[0], args[1]
os.makedirs(OUT, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = False
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.view_settings.view_transform = "Standard"  # punchy colors, not washed-out Filmic
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.75, 0.88, 1.0, 1)
    bg.inputs["Strength"].default_value = 0.35
    scene.world = world
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(40), math.radians(-20), math.radians(30))
    scene.collection.objects.link(sun)
    fill_data = bpy.data.lights.new("fill", "AREA")
    fill_data.energy = 600
    fill_data.size = 8
    fill = bpy.data.objects.new("fill", fill_data)
    fill.location = (-6, -6, 4)
    fill.rotation_euler = (math.radians(60), 0, math.radians(-45))
    scene.collection.objects.link(fill)


def camera(location, target, lens=50):
    data = bpy.data.cameras.new("cam")
    data.lens = lens
    cam = bpy.data.objects.new("cam", data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = location
    cam.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam


def render(name):
    bpy.context.scene.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)
    print("ICON RENDERED", name)


def principled(name, color, metallic=0.0, roughness=0.45, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def rainbow_material():
    """Hue runs along the noodle (object X)."""
    mat = bpy.data.materials.new("Rainbow")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coords = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    scale = nodes.new("ShaderNodeMath")
    scale.operation = "MULTIPLY"
    scale.inputs[1].default_value = 0.12
    frac = nodes.new("ShaderNodeMath")
    frac.operation = "FRACT"
    ramp = nodes.new("ShaderNodeValToRGB")
    stops = [(0.0, (1, 0.15, 0.2)), (0.2, (1, 0.6, 0.1)), (0.4, (1, 0.95, 0.2)), (0.6, (0.2, 0.9, 0.3)), (0.8, (0.2, 0.5, 1)), (1.0, (0.7, 0.3, 1))]
    ramp.color_ramp.elements[0].position = stops[0][0]
    ramp.color_ramp.elements[0].color = (*stops[0][1], 1)
    ramp.color_ramp.elements[1].position = stops[-1][0]
    ramp.color_ramp.elements[1].color = (*stops[-1][1], 1)
    for pos, col in stops[1:-1]:
        el = ramp.color_ramp.elements.new(pos)
        el.color = (*col, 1)
    links.new(coords.outputs["Object"], sep.inputs[0])
    links.new(sep.outputs["X"], scale.inputs[0])
    links.new(scale.outputs[0], frac.inputs[0])
    links.new(frac.outputs[0], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.3
    return mat


def galaxy_material():
    """Deep purple with glowing star speckles."""
    mat = bpy.data.materials.new("Galaxy")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.12, 0.04, 0.3, 1)
    bsdf.inputs["Roughness"].default_value = 0.25
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 40
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.7
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (1, 0.9, 1, 1)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 6
    return mat


def ridged_profile(radius=0.5, ridges=8, depth=0.08):
    """A closed curve shaped like a pool-noodle cross-section, for bevelling a path."""
    curve = bpy.data.curves.new("profile", "CURVE")
    curve.dimensions = "2D"
    spline = curve.splines.new("POLY")
    count = ridges * 8
    spline.points.add(count - 1)
    for i in range(count):
        a = 2 * math.pi * i / count
        r = radius - depth / 2 + depth / 2 * math.cos(ridges * a)
        spline.points[i].co = (math.cos(a) * r, math.sin(a) * r, 0, 1)
    spline.use_cyclic_u = True
    obj = bpy.data.objects.new("profile", curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.hide_render = True
    return obj


def noodle(points, material, radius=0.5):
    """A bent foam noodle along `points`, with rounded end caps."""
    profile = ridged_profile(radius)
    curve = bpy.data.curves.new("noodle", "CURVE")
    curve.dimensions = "3D"
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for i, p in enumerate(points):
        spline.points[i].co = (*p, 1)
    spline.use_endpoint_u = True
    spline.order_u = 4
    curve.bevel_mode = "OBJECT"
    curve.bevel_object = profile
    curve.use_fill_caps = True
    curve.resolution_u = 24
    obj = bpy.data.objects.new("noodle", curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    for end in (points[0], points[-1]):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius * 0.93, location=end, segments=24, ring_count=12)
        cap = bpy.context.active_object
        cap.data.materials.append(material)
        bpy.ops.object.shade_smooth()
    return obj


def arc(center, radius, a0, a1, z_wave=0.0, steps=8, tilt=0.0):
    pts = []
    for i in range(steps):
        t = i / (steps - 1)
        a = math.radians(a0 + (a1 - a0) * t)
        pts.append((center[0] + math.cos(a) * radius, center[1] + math.sin(a) * radius * math.cos(tilt), center[2] + math.sin(t * math.pi) * z_wave + math.sin(a) * radius * math.sin(tilt)))
    return pts


def import_model(name, location, scale, rotation_z=0.0, colors=None):
    bpy.ops.import_scene.fbx(filepath=os.path.join(MODELS, f"{name}.fbx"))
    objs = list(bpy.context.selected_objects)
    palette = colors or {}
    for o in objs:
        token = o.name.split("_")[0]
        col = palette.get(token, (1, 1, 1))
        o.data.materials.clear()
        o.data.materials.append(principled(o.name, col, roughness=0.35))
        o.scale = (scale, scale, scale)
        o.rotation_euler.z += rotation_z
        o.location = (o.location.x * scale + location[0], o.location.y * scale + location[1], o.location.z * scale + location[2])
    return objs


# ------------------------------------------------------------- skins pack
reset()
# Three wavy noodles stacked diagonally, facing the camera
noodle([(-3.6, 0.8, -2.8), (-1.2, 0.8, -0.8), (1.2, 0.8, -1.6), (3.6, 0.8, 0.2)], principled("Gold", (1.0, 0.68, 0.12), metallic=1.0, roughness=0.22), 0.6)
noodle([(-3.6, 0, -1.0), (-1.2, 0, 1.0), (1.2, 0, 0.2), (3.6, 0, 2.0)], rainbow_material(), 0.6)
noodle([(-3.6, -0.8, 0.8), (-1.2, -0.8, 2.8), (1.2, -0.8, 2.0), (3.6, -0.8, 3.8)], galaxy_material(), 0.6)
camera((0, -12, 0.5), (0, 0, 0.5), lens=40)
render("skins.png")

# ------------------------------------------------------------------- VIP
reset()
gold = principled("Gold", (1.0, 0.72, 0.15), metallic=1.0, roughness=0.2)
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=2.2, depth=1.2, location=(0, 0, 0))
band = bpy.context.active_object
band.data.materials.append(gold)
bpy.ops.object.shade_smooth()
mod = band.modifiers.new("hollow", "SOLIDIFY")
mod.thickness = 0.25
for i in range(6):  # crown points
    a = 2 * math.pi * i / 6
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.75, radius2=0.05, depth=1.8, location=(math.cos(a) * 2.05, math.sin(a) * 2.05, 1.4), rotation=(0, 0, a + math.pi / 4))
    spike = bpy.context.active_object
    spike.data.materials.append(gold)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(math.cos(a) * 2.05, math.sin(a) * 2.05, 2.35))
    ball = bpy.context.active_object
    ball.data.materials.append(gold)
    bpy.ops.object.shade_smooth()
gem_colors = [(0.9, 0.05, 0.15), (0.1, 0.4, 1.0), (0.1, 0.8, 0.3)]
for i in range(6):
    a = 2 * math.pi * (i + 0.5) / 6
    bpy.ops.mesh.primitive_ico_sphere_add(radius=0.32, subdivisions=1, location=(math.cos(a) * 2.32, math.sin(a) * 2.32, 0.0))
    gem = bpy.context.active_object
    col = gem_colors[i % 3]
    gem.data.materials.append(principled("Gem", col, roughness=0.05, emission=col, strength=0.6))
camera((0, -8.0, 1.9), (0, 0, 0.9), lens=42)
render("vip.png")

# --------------------------------------------------------------- 2x bonks
reset()
noodle(arc((0.5, 0, -2.6), 4.4, 150, 20, z_wave=1.0, tilt=0.5), principled("Pink", (1.0, 0.25, 0.6), roughness=0.4), 0.75)
camera((0, -10, 1.2), (0.2, 0, 0.2), lens=40)
render("double.png")

# ------------------------------------------------------------- pool party
reset()
import_model("RubberDuck", (0.0, 0.0, -2.2), 0.55, rotation_z=math.radians(-35),
             colors={"Yellow": (1, 0.82, 0.12), "Orange": (1, 0.45, 0.05), "White": (1, 1, 1), "Black": (0.02, 0.02, 0.02)})
import_model("BeachBall", (2.6, -1.0, -2.2), 0.55,
             colors={"Red": (0.95, 0.15, 0.15), "White": (1, 1, 1), "Blue": (0.15, 0.4, 1), "Yellow": (1, 0.85, 0.1), "Green": (0.2, 0.8, 0.3)})
import_model("SwimRing", (-2.4, -0.6, -2.2), 0.6, colors={"ColorA": (1, 0.3, 0.65), "ColorB": (1, 1, 1)})
random.seed(4)
confetti_colors = [(1, 0.3, 0.6), (0.3, 0.8, 1), (1, 0.85, 0.2), (0.4, 0.9, 0.4), (0.8, 0.4, 1)]
for i in range(70):
    loc = (random.uniform(-4.5, 4.5), random.uniform(-2.5, 2.5), random.uniform(-0.5, 4.2))
    bpy.ops.mesh.primitive_plane_add(size=0.32, location=loc, rotation=(random.uniform(0, 6), random.uniform(0, 6), random.uniform(0, 6)))
    piece = bpy.context.active_object
    piece.data.materials.append(principled("Confetti", random.choice(confetti_colors), roughness=0.4))
camera((0, -10.5, 2.2), (0, 0, 0.2), lens=38)
render("party.png")
print("ICONS DONE")
