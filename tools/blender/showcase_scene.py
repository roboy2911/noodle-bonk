"""Builds an animated Noodle Bonk clip in Blender, ready to render as a vertical
(1080x1920) video for TikTok / Shorts.

The shot (about 4.5 seconds): a player stands near the edge of the pool deck,
winds up and spins, their bendy pink noodle whips around and BONKS another
player, who tumbles off the deck and splashes into the pool. Uses the game's
own models from assets/models (deck, umbrellas, palm trees, rubber duck...).

How to run (either way works):

  * In Blender: Scripting tab > Open > pick this file > Run Script (the play
    button). It builds the scene and saves renders/noodle_bonk_showcase.blend
    in the repo. Then Render > Render Animation (Ctrl+F12).

  * From a terminal, in the repo folder (builds, saves and renders the MP4):
      blender --background --python tools/blender/showcase_scene.py -- --render

The video goes to renders/noodle_bonk_bonk_0001-0135.mp4 next to the .blend.
Made for Blender 4.x with Eevee.
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

# ------------------------------------------------------------------ paths

def find_repo_root():
    """The noodle-bonk folder, whether this runs from a terminal or Blender's text editor."""
    candidates = []
    if "__file__" in globals() and os.path.isfile(__file__):
        candidates.append(os.path.dirname(os.path.abspath(__file__)))
    for text in bpy.data.texts:
        if text.filepath:
            candidates.append(os.path.dirname(bpy.path.abspath(text.filepath)))
    candidates.append(os.getcwd())
    for start in candidates:
        folder = start
        for _ in range(4):
            if os.path.isdir(os.path.join(folder, "assets", "models")):
                return folder
            folder = os.path.dirname(folder)
    raise RuntimeError(
        "Couldn't find the noodle-bonk folder (with assets/models). "
        "Run this from the repo folder, or open the script from tools/blender/."
    )

ROOT = find_repo_root()
MODELS = os.path.join(ROOT, "assets", "models")
OUT_DIR = os.path.join(ROOT, "renders")
os.makedirs(OUT_DIR, exist_ok=True)
RENDER_NOW = "--render" in sys.argv

FPS = 30
FRAME_END = 135
random.seed(7)

# ------------------------------------------------------------------ scene reset

# Clear the current scene (but keep this script's text, so it can run from
# Blender's text editor without pulling the rug out from under itself)
for datablocks in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.curves,
                   bpy.data.cameras, bpy.data.lights, bpy.data.worlds, bpy.data.actions):
    for item in list(datablocks):
        datablocks.remove(item)
scene = bpy.context.scene
collection = scene.collection

# ------------------------------------------------------------------ materials

def srgb(c):
    """Game colors are sRGB; Blender's node colors are linear."""
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def make_material(name, color, roughness=0.45, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    linear = (*srgb(color), 1.0)
    mat.diffuse_color = linear
    bsdf.inputs["Base Color"].default_value = linear
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = linear
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission
    return mat

INK_FLAT = make_material("InkFlat", (0.06, 0.06, 0.1), 0.8)  # dark, for the BONK! outline

PALETTE = {
    "Foam": (1.0, 0.41, 0.71), "Sand": (0.95, 0.9, 0.78), "Cyan": (0.31, 0.85, 1.0), "White": (0.97, 0.97, 0.97),
    "Wood": (0.67, 0.47, 0.29), "WoodDark": (0.47, 0.31, 0.18), "Red": (0.92, 0.24, 0.24), "Yellow": (1.0, 0.84, 0.2),
    "Orange": (1.0, 0.55, 0.12), "Black": (0.08, 0.08, 0.08), "Blue": (0.24, 0.55, 1.0), "Green": (0.35, 0.78, 0.35),
    "Leaf": (0.27, 0.67, 0.27), "Bark": (0.59, 0.43, 0.27), "Brown": (0.43, 0.27, 0.16), "Pink": (1.0, 0.41, 0.71),
    "Accent": (0.31, 0.78, 1.0),
}
_palette_mats = {}

def palette_material(token, color_a=None, color_b=None):
    if token == "ColorA" and color_a:
        key, color = f"ColorA{color_a}", color_a
    elif token == "ColorB" and color_b:
        key, color = f"ColorB{color_b}", color_b
    else:
        key, color = token, PALETTE.get(token, (0.9, 0.9, 0.9))
    if key not in _palette_mats:
        _palette_mats[key] = make_material(f"P_{key}", color)
    return _palette_mats[key]

def add_outline(obj, thickness=0.07):
    """Cartoon outlines come from Freestyle (set up at the end), so nothing to do per object."""
    return


# ------------------------------------------------------------------ game models

MODEL_SIZES = {  # same sizes the game uses (src/shared/ModelAssets.luau)
    "PoolDeck": ("Width", 333), "Umbrella": ("Height", 11.5), "LoungeChair": ("Width", 7),
    "BeachBall": ("Height", 4), "SwimRing": ("Width", 5.5), "RubberDuck": ("Height", 9),
    "PalmTree": ("Height", 21), "Crate": ("Height", 5), "LifeguardTower": ("Height", 16),
}

def place_model(name, location, angle_deg=0.0, scale=1.0, color_a=None, color_b=None, outline=True):
    """Imports assets/models/<name>.fbx, colors it, sizes it like the game, and stands it at `location`."""
    path = os.path.join(MODELS, f"{name}.fbx")
    if not os.path.isfile(path):
        print(f"[showcase] missing model {path}, skipping")
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for obj in meshes:
        token = obj.name.split("_")[0]
        obj.data.materials.clear()
        obj.data.materials.append(palette_material(token, color_a, color_b))
        if outline and name != "PoolDeck":
            add_outline(obj, 0.08)
    bpy.context.view_layer.update()

    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in meshes:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, world))
            hi = Vector(map(max, hi, world))
    measure, size = MODEL_SIZES.get(name, ("Height", 5))
    extent = (hi.z - lo.z) if measure == "Height" else max(hi.x - lo.x, hi.y - lo.y)
    s = size * scale / max(extent, 1e-6)
    offset = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, hi.z if name == "PoolDeck" else lo.z))

    holder = bpy.data.objects.new(f"{name}_Holder", None)
    collection.objects.link(holder)
    for obj in new:
        if obj.parent is None:
            world = obj.matrix_world.copy()
            obj.parent = holder
            obj.matrix_world = world
    holder.matrix_world = (
        Matrix.Translation(Vector(location))
        @ Matrix.Rotation(math.radians(angle_deg), 4, "Z")
        @ Matrix.Scale(s, 4)
        @ Matrix.Translation(-offset)
    )
    return holder

# ------------------------------------------------------------------ helpers

def empty(name, parent=None, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.parent = parent
    obj.location = location
    return obj

def link_new(obj, parent, location):
    obj.parent = parent
    obj.location = location
    return obj

def box(name, size, location, material, parent, bevel=0.14):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    mod = obj.modifiers.new("Round", "BEVEL")
    mod.width = bevel
    mod.segments = 3
    add_outline(obj)
    return link_new(obj, parent, location)

def ball(name, radius, location, material, parent, scale=(1, 1, 1), outline=True):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=radius)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    obj.scale = scale
    if outline:
        add_outline(obj, 0.04)
    return link_new(obj, parent, location)

def key(obj, path, frame, value):
    setattr(obj, path, value)
    obj.keyframe_insert(data_path=path, frame=frame)

# ------------------------------------------------------------------ characters

SKIN = make_material("Skin", (1.0, 0.81, 0.24))
WHITE = make_material("EyeWhite", (1, 1, 1), 0.3)
BLACK = make_material("Pupil", (0.05, 0.05, 0.08), 0.3)
MOUTH = make_material("Mouth", (0.45, 0.1, 0.15), 0.5)

def character(name, shirt, pants, hair):
    """A blocky avatar about 5.6 studs tall, facing +Y. Returns its moving parts.

    root  (at the feet: move / turn the whole character)
      pivot (at the chest: tumble around it)
        shoulders / hips (rotate on X to swing arms and legs; +90 = forward)"""
    shirt_m = make_material(f"{name}_Shirt", shirt)
    pants_m = make_material(f"{name}_Pants", pants)
    hair_m = make_material(f"{name}_Hair", hair)
    root = empty(f"{name}_Root")
    pivot = empty(f"{name}_Pivot", root, (0, 0, 3.0))

    box(f"{name}_Torso", (2.0, 1.0, 2.0), (0, 0, 0), shirt_m, pivot)
    head = box(f"{name}_Head", (1.5, 1.5, 1.5), (0, 0, 1.85), SKIN, pivot, bevel=0.4)
    box(f"{name}_Hair", (1.6, 1.6, 0.45), (0, -0.05, 2.55), hair_m, pivot, bevel=0.2)
    for x in (-0.33, 0.33):
        ball(f"{name}_Eye", 0.24, (x, 0.74, 1.98), WHITE, pivot, scale=(1, 0.5, 1.15))
        ball(f"{name}_Pupil", 0.11, (x, 0.86, 1.98), BLACK, pivot, outline=False)
    mouth = ball(f"{name}_Mouth", 0.3, (0, 0.74, 1.48), MOUTH, pivot, scale=(1.1, 0.4, 0.35))

    parts = {"root": root, "pivot": pivot, "head": head, "mouth": mouth}
    for side, label in ((-1, "L"), (1, "R")):
        shoulder = empty(f"{name}_Shoulder{label}", pivot, (side * 1.5, 0, 0.8))
        box(f"{name}_Arm{label}", (0.9, 0.9, 1.9), (0, 0, -0.85), shirt_m, shoulder)
        grip = empty(f"{name}_Grip{label}", shoulder, (0, 0, -1.85))
        hip = empty(f"{name}_Hip{label}", pivot, (side * 0.5, 0, -1.0))
        box(f"{name}_Leg{label}", (0.95, 0.95, 2.0), (0, 0, -1.0), pants_m, hip)
        parts[f"shoulder{label}"] = shoulder
        parts[f"grip{label}"] = grip
        parts[f"hip{label}"] = hip
    return parts

# ------------------------------------------------------------------ noodle

def noodle(name, parent, length=7.5, radius=0.45):
    """A pink foam noodle: a smooth NURBS curve with a round bevel, held at
    `parent` (a grip) and pointing along the grip's -Z (down the arm).
    Returns the spline so its points can be animated to bend."""
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.bevel_depth = radius
    data.bevel_resolution = 4
    data.resolution_u = 16
    data.use_fill_caps = True
    try:
        data.use_uv_as_generated = True  # lets the ridges run along the noodle
    except AttributeError:
        pass
    spline = data.splines.new("NURBS")
    count = 6
    spline.points.add(count - 1)
    for i, point in enumerate(spline.points):
        point.co = (0, 0, -length * i / (count - 1), 1)
    spline.order_u = 4
    spline.use_endpoint_u = True

    mat = bpy.data.materials.new(f"{name}_Foam")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.6
    coords = nodes.new("ShaderNodeTexCoord")
    wave = nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 9
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (*srgb((0.85, 0.2, 0.55)), 1)
    ramp.color_ramp.elements[1].position = 0.18
    ramp.color_ramp.elements[1].color = (*srgb((1.0, 0.42, 0.72)), 1)
    links.new(coords.outputs["Generated"], wave.inputs["Vector"])
    links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    data.materials.append(mat)

    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.parent = parent
    return spline

def bend(spline, frame, amount, length=7.5):
    """Bends the noodle sideways (local X) by `amount` studs at the tip, more toward the tip."""
    count = len(spline.points)
    for i, point in enumerate(spline.points):
        t = i / (count - 1)
        point.co = (amount * t * t, 0, -length * t, 1)
        point.keyframe_insert(data_path="co", frame=frame)

# ------------------------------------------------------------------ the set

# Deck (its top is at z = 0) and the pool below
place_model("PoolDeck", (0, 0, 0))
WATER_Z = -30
water_mesh = bpy.data.meshes.new("Water")
bm = bmesh.new()
bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1500)
bm.to_mesh(water_mesh)
bm.free()
water = bpy.data.objects.new("Water", water_mesh)
water.location = (0, 0, WATER_Z)
collection.objects.link(water)
water_mat = bpy.data.materials.new("Water")
water_mat.use_nodes = True
wn, wl = water_mat.node_tree.nodes, water_mat.node_tree.links
wb = wn.get("Principled BSDF")
wb.inputs["Base Color"].default_value = (*srgb((0.12, 0.55, 0.9)), 1)
wb.inputs["Roughness"].default_value = 0.08
noise = wn.new("ShaderNodeTexNoise")
noise.inputs["Scale"].default_value = 0.6
bump = wn.new("ShaderNodeBump")
bump.inputs["Strength"].default_value = 0.25
wl.new(noise.outputs["Fac"], bump.inputs["Height"])
wl.new(bump.outputs["Normal"], wb.inputs["Normal"])
water_mesh.materials.append(water_mat)

# Props around the shot (the action happens near the deck edge at y ~ 150)
place_model("Umbrella", (22, 118, 0), 20, color_a=(1.0, 0.41, 0.71), color_b=(1, 1, 1))
place_model("Umbrella", (-26, 108, 0), -15, color_a=(0.31, 0.78, 1.0), color_b=(1, 1, 1))
place_model("LoungeChair", (-12, 126, 0), 70)
place_model("LoungeChair", (-6.5, 127, 0), 70)
place_model("BeachBall", (-6, 149, 0), 30)
place_model("SwimRing", (5, 155, 0), 0, color_a=(1.0, 0.3, 0.3), color_b=(1, 1, 1))
place_model("PalmTree", (-15, 159, 0), 40)
place_model("PalmTree", (-27, 150, 0), 160)
place_model("Umbrella", (-9, 140, 0), 10, color_a=(1.0, 0.84, 0.2), color_b=(1, 1, 1))
place_model("Crate", (-13, 146, 0), 15)
place_model("Crate", (-16, 143.5, 0), -10)
place_model("RubberDuck", (-34, 150, 0), 200)
place_model("LifeguardTower", (60, 110, 0), 210)

# ------------------------------------------------------------------ the players

attacker = character("Bonker", shirt=(0.35, 0.8, 0.45), pants=(0.2, 0.24, 0.36), hair=(0.25, 0.16, 0.1))
victim = character("Bonked", shirt=(0.3, 0.55, 1.0), pants=(0.2, 0.24, 0.36), hair=(0.9, 0.47, 0.16))

A_POS = Vector((0, 145, 0))
V_POS = Vector((0, 153.4, 0))
attacker["root"].location = A_POS
victim["root"].location = V_POS
victim["root"].rotation_euler = (0, 0, math.pi)  # facing the attacker

# Attacker: arm out holding the noodle, other arm relaxed
attacker["shoulderR"].rotation_euler = (math.radians(85), 0, 0)
attacker["shoulderL"].rotation_euler = (math.radians(20), 0, math.radians(-15))
spline = noodle("Noodle", attacker["gripR"])

# The swing is a fast spin of the whole body (that's how you swing in the game).
# Wind up turning one way, then whip around the other way; the noodle lags behind.
turns = [(1, 0.0), (26, -0.25), (40, -1.7), (47, 0.5), (52, 1.4), (58, 1.6), (78, 0.7), (FRAME_END, 0.55)]
for frame, angle in turns:
    key(attacker["root"], "rotation_euler", frame, Euler((0, 0, angle)))
bends = [(1, 0.0), (26, 0.4), (40, -1.6), (44, 2.6), (47, 3.4), (50, 2.2), (54, -2.4), (59, 1.3), (65, -0.7), (72, 0.3), (80, 0.0)]
for frame, amount in bends:
    bend(spline, frame, amount)
# A little bounce in the step
for frame, z in [(1, 0.0), (38, -0.25), (47, 0.3), (60, 0.0)]:
    key(attacker["pivot"], "location", frame, Vector((0, 0, 3.0 + z)))
# Grin the whole time
attacker["mouth"].scale = (1.3, 0.4, 0.3)

# Victim: idle, then launched at the hit (frame 47)
IMPACT = 47
GRAVITY = 60.0
launch = Vector((-15.0, 42.0, 40.0))  # studs per second
for frame in (1, IMPACT - 1):
    key(victim["root"], "location", frame, V_POS.copy())
    key(victim["pivot"], "rotation_euler", frame, Euler((0, 0, 0)))
landed_frame = IMPACT
landing = V_POS.copy()
for frame in range(IMPACT, FRAME_END + 1, 2):
    t = (frame - IMPACT) / FPS
    pos = V_POS + Vector((launch.x * t, launch.y * t, launch.z * t - 0.5 * GRAVITY * t * t))
    if pos.z <= WATER_Z:
        landed_frame, landing = frame, Vector((pos.x, pos.y, WATER_Z))
        key(victim["root"], "location", frame, landing - Vector((0, 0, 8)))  # under the surface
        # Gone once they're in the water (so no outline shows through it)
        key(victim["root"], "scale", 1, Vector((1, 1, 1)))
        key(victim["root"], "scale", frame - 1, Vector((1, 1, 1)))
        key(victim["root"], "scale", frame, Vector((0, 0, 0)))
        break
    key(victim["root"], "location", frame, pos)
    spin = t * 7.5
    key(victim["pivot"], "rotation_euler", frame, Euler((-spin, spin * 0.35, 0)))

# Shocked face at the hit, and flailing arms and legs while flying
for frame, scale in [(1, (1.2, 0.4, 0.28)), (IMPACT - 1, (1.2, 0.4, 0.28)), (IMPACT + 1, (0.7, 0.4, 0.75))]:
    key(victim["mouth"], "scale", frame, scale)
for limb, phase in (("shoulderL", 0), ("shoulderR", 1), ("hipL", 1), ("hipR", 0)):
    is_arm = limb.startswith("shoulder")
    key(victim[limb], "rotation_euler", 1, Euler((0, 0, 0)))
    key(victim[limb], "rotation_euler", IMPACT - 1, Euler((0, 0, 0)))
    for i, frame in enumerate(range(IMPACT + 2, landed_frame + 1, 4)):
        wave_angle = (2.7 if is_arm else 0.9) * (1 if (i + phase) % 2 == 0 else 0.55)
        side = (1 if limb.endswith("L") else -1) * (0.6 if is_arm else 0.25)
        key(victim[limb], "rotation_euler", frame, Euler((wave_angle, side, 0)))

# ------------------------------------------------------------------ BONK!

impact_point = V_POS + Vector((-1.5, -1.0, 7.0))
fx = empty("BonkFx", None, impact_point)

def flat_star(name, outer, inner, points, material, z):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rnd = random.Random(3)
    verts = []
    for i in range(points * 2):
        a = i * math.pi / points
        r = (outer * rnd.uniform(0.85, 1.1)) if i % 2 == 0 else inner
        verts.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
    bm.faces.new(verts)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = fx
    return obj

flat_star("BurstOutline", 4.9, 3.1, 13, INK_FLAT, -0.12)
flat_star("Burst", 4.5, 2.8, 13, make_material("BurstYellow", (1.0, 0.87, 0.24), 0.5, emission=0.6), -0.06)
for label, offset, material, z in (
    ("BonkTextOutline", 0.16, INK_FLAT, 0.0),
    ("BonkText", 0.0, make_material("BonkPink", (1.0, 0.28, 0.48), 0.4, emission=0.6), 0.12),
):
    text = bpy.data.curves.new(label, "FONT")
    text.body = "BONK!"
    text.size = 2.6
    text.extrude = 0.08
    text.offset = offset
    text.align_x = "CENTER"
    text.align_y = "CENTER"
    text.materials.append(material)
    obj = bpy.data.objects.new(label, text)
    collection.objects.link(obj)
    obj.parent = fx
    obj.location = (0, 0, z)
    obj.rotation_euler = (0, 0, math.radians(10))

for frame, s in [(1, 0.0), (IMPACT - 1, 0.0), (IMPACT + 2, 0.75), (IMPACT + 5, 0.55), (IMPACT + 14, 0.55), (IMPACT + 18, 0.0)]:
    key(fx, "scale", frame, Vector((s, s, s)))

# ------------------------------------------------------------------ splash

DROP = make_material("Splash", (0.88, 0.97, 1.0), 0.2, emission=0.2)
for i in range(36):
    mesh = bpy.data.meshes.new(f"Drop{i}")
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.materials.append(DROP)
    drop = bpy.data.objects.new(f"Drop{i}", mesh)
    collection.objects.link(drop)
    angle = random.uniform(0, math.pi * 2)
    speed = random.uniform(6, 18)
    up = random.uniform(22, 42)
    size = random.uniform(0.5, 1.3)
    key(drop, "scale", 1, Vector((0, 0, 0)))
    key(drop, "scale", landed_frame - 1, Vector((0, 0, 0)))
    for frame in range(landed_frame, FRAME_END + 1, 2):
        t = (frame - landed_frame) / FPS
        pos = landing + Vector((math.cos(angle) * speed * t, math.sin(angle) * speed * t, up * t - 0.5 * GRAVITY * t * t))
        key(drop, "location", frame, pos)
        fade = max(0.0, 1 - t / 1.4)
        key(drop, "scale", frame, Vector((size, size, size * 1.3)) * fade)

# A flat foam ring that spreads out on the water
ring_mesh = bpy.data.meshes.new("SplashRing")
bm = bmesh.new()
segments = 40
outer = [bm.verts.new((math.cos(i / segments * math.tau), math.sin(i / segments * math.tau), 0)) for i in range(segments)]
inner = [bm.verts.new((0.8 * math.cos(i / segments * math.tau), 0.8 * math.sin(i / segments * math.tau), 0)) for i in range(segments)]
for i in range(segments):
    j = (i + 1) % segments
    bm.faces.new((outer[i], outer[j], inner[j], inner[i]))
bm.to_mesh(ring_mesh)
bm.free()
ring = bpy.data.objects.new("SplashRing", ring_mesh)
collection.objects.link(ring)
ring.location = landing + Vector((0, 0, 0.1))
ring_mesh.materials.append(DROP)
for frame, s in [(1, 0.0), (landed_frame - 1, 0.0), (landed_frame + 2, 2.0), (landed_frame + 25, 7.0), (landed_frame + 32, 0.0)]:
    key(ring, "scale", frame, Vector((s, s, 1)))

# ------------------------------------------------------------------ camera

cam_data = bpy.data.cameras.new("Camera")
cam_data.lens = 28
cam = bpy.data.objects.new("Camera", cam_data)
collection.objects.link(cam)
scene.camera = cam
focus = empty("CameraFocus")
track = cam.constraints.new("TRACK_TO")
track.target = focus
track.track_axis = "TRACK_NEGATIVE_Z"
track.up_axis = "UP_Y"

face = fx.constraints.new("TRACK_TO")  # BONK! always faces the camera
face.target = cam
face.track_axis = "TRACK_Z"
face.up_axis = "UP_Y"

# A 3/4 view of both players, then a chase of the flight down to the splash.
# The focus follows the victim through the air.
def victim_at(frame):
    t = max(0, frame - IMPACT) / FPS
    return V_POS + Vector((launch.x * t, launch.y * t, launch.z * t - 0.5 * GRAVITY * t * t)) + Vector((0, 0, 3))

camera_path = [
    (1, (14.0, 137.0, 10.0), Vector((-1.0, 150.5, 3.0))),
    (IMPACT - 2, (12.0, 139.0, 9.5), Vector((-0.5, 151.5, 3.5))),
]
for frame in range(IMPACT + 4, landed_frame + 1, 6):
    target = victim_at(frame)
    camera_path.append((frame, tuple(target + Vector((13, -15, 5))), target))
camera_path.append((landed_frame + 3, tuple(landing + Vector((14, -18, 9))), landing + Vector((0, 0, 3))))
camera_path.append((FRAME_END, tuple(landing + Vector((15, -20, 10))), landing + Vector((0, 0, 4))))
for frame, where, look in camera_path:
    key(cam, "location", frame, Vector(where))
    key(focus, "location", frame, Vector(look))

# ------------------------------------------------------------------ light, sky, render settings

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 4.0
sun_data.angle = math.radians(3)
sun = bpy.data.objects.new("Sun", sun_data)
collection.objects.link(sun)
sun.rotation_euler = Euler((math.radians(40), math.radians(10), math.radians(150)))

world = bpy.data.worlds.new("Sky")
scene.world = world
world.use_nodes = True
wnodes = world.node_tree.nodes
background = wnodes.get("Background")
gradient = wnodes.new("ShaderNodeTexGradient")
mapping = wnodes.new("ShaderNodeMapping")
coords = wnodes.new("ShaderNodeTexCoord")
sky_ramp = wnodes.new("ShaderNodeValToRGB")
mapping.inputs["Rotation"].default_value = (0, math.radians(-90), 0)  # gradient goes bottom to top
sky_ramp.color_ramp.elements[0].color = (*srgb((0.75, 0.93, 1.0)), 1)
sky_ramp.color_ramp.elements[1].color = (*srgb((0.25, 0.62, 0.98)), 1)
world.node_tree.links.new(coords.outputs["Generated"], mapping.inputs["Vector"])
world.node_tree.links.new(mapping.outputs["Vector"], gradient.inputs["Vector"])
world.node_tree.links.new(gradient.outputs["Fac"], sky_ramp.inputs["Fac"])
world.node_tree.links.new(sky_ramp.outputs["Color"], background.inputs["Color"])
background.inputs["Strength"].default_value = 1.2

for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
for owner in (scene.render, getattr(scene, "eevee", None)):
    if owner is not None and hasattr(owner, "use_motion_blur"):
        owner.use_motion_blur = True  # makes the swing feel fast
try:
    scene.view_settings.view_transform = "Standard"  # bright cartoon colors
except TypeError:
    pass

# Cartoon outlines around everything (Freestyle draws them in any renderer)
scene.render.use_freestyle = True
scene.render.line_thickness_mode = "ABSOLUTE"
scene.render.line_thickness = 2.2
lineset = scene.view_layers[0].freestyle_settings.linesets[0] if scene.view_layers[0].freestyle_settings.linesets else scene.view_layers[0].freestyle_settings.linesets.new("Outlines")
lineset.select_silhouette = True
lineset.select_border = True
lineset.select_crease = False
lineset.linestyle.color = (0.02, 0.02, 0.04)
lineset.linestyle.thickness = 2.2

scene.render.resolution_x = 1080
scene.render.resolution_y = 1920
scene.render.resolution_percentage = 100
scene.render.fps = FPS
scene.frame_start = 1
scene.frame_end = FRAME_END
scene.frame_set(1)
scene.render.image_settings.file_format = "FFMPEG"
scene.render.ffmpeg.format = "MPEG4"
scene.render.ffmpeg.codec = "H264"
scene.render.ffmpeg.constant_rate_factor = "HIGH"
scene.render.filepath = "//noodle_bonk_bonk_"

blend_path = os.path.join(OUT_DIR, "noodle_bonk_showcase.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
print(f"[showcase] Saved {blend_path}. Render > Render Animation (Ctrl+F12) to make the video.")

if RENDER_NOW:
    bpy.ops.render.render(animation=True)
    print(f"[showcase] Rendered to {OUT_DIR}")
