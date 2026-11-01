"""Builds every Noodle Bonk 3D model in Blender and exports each as an FBX.

Run headless:
    blender --background --factory-startup --python tools/blender/build_models.py -- assets/models

Each object's name starts with a palette token (e.g. "Wood_Leg", "ColorA_Canopy").
The game colors MeshParts by that token (see src/shared/ModelAssets.luau), so
the FBX files don't need materials or textures. Models are built roughly in
studs, but the game rescales every model to an exact size anyway.

Blender is Z-up; FBX export converts to Roblox's Y-up. Long things that the
game stretches along an axis (the noodle segment) are built along Blender X,
which stays X in Roblox.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"
os.makedirs(OUT_DIR, exist_ok=True)


# ----------------------------------------------------------------- helpers

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def add_modifier_bevel(obj, width, segments=2):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    return mod


def shade_auto(obj, angle_deg=40):
    """Smooth shading with sharp edges kept sharp (Blender 4.1+ style)."""
    mod = obj.modifiers.new("Smooth", "NODES")
    try:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle_deg))
        obj.modifiers.remove(mod)
    except Exception:
        obj.modifiers.remove(mod)


def prim(kind, name, location=(0, 0, 0), rotation=(0, 0, 0), scale=(1, 1, 1), **kwargs):
    ops = {
        "cube": bpy.ops.mesh.primitive_cube_add,
        "cylinder": bpy.ops.mesh.primitive_cylinder_add,
        "uv_sphere": bpy.ops.mesh.primitive_uv_sphere_add,
        "cone": bpy.ops.mesh.primitive_cone_add,
        "torus": bpy.ops.mesh.primitive_torus_add,
    }
    ops[kind](location=location, rotation=rotation, **kwargs)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def join(objects, name):
    """Joins objects that share a color into one mesh (fewer MeshParts in game)."""
    objects = [o for o in objects if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    return obj


def smooth(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True


def export(model_name):
    bpy.ops.object.select_all(action="SELECT")
    # Bake modifiers and transforms so the FBX is exactly what we see
    for obj in bpy.context.scene.objects:
        bpy.context.view_layer.objects.active = obj
        for mod in list(obj.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=mod.name)
            except Exception:
                pass
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    path = os.path.join(OUT_DIR, f"{model_name}.fbx")
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        bake_anim=False,
    )
    tris = sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH")
    print(f"EXPORTED {model_name}: {len(bpy.context.scene.objects)} parts, ~{tris} faces -> {path}")


# ----------------------------------------------------------------- models

def noodle_segment(name="NoodleSegment", length=2.0, ridges=8, outer=0.5, valley=0.43, core=0.16, tip=False):
    """A foam pool-noodle tube: ridged outside, hollow core, along X.

    It's twice as long as it is wide so the game can tell which axis is the
    length from the part's size (NoodleMesh stretches it to any length)."""
    reset()
    bm = bmesh.new()
    count = ridges * 8  # several points per ridge so each ridge is a smooth bump
    ends = [-length / 2, length / 2]
    outer_rings, inner_rings = [], []
    for x in ends:
        ring = []
        for i in range(count):
            a = 2 * math.pi * i / count
            # Rounded ridges: radius rises and falls smoothly around the tube
            r = (outer + valley) / 2 + (outer - valley) / 2 * math.cos(ridges * a)
            ring.append(bm.verts.new((x, math.cos(a) * r, math.sin(a) * r)))
        outer_rings.append(ring)
        inner = []
        for i in range(count):
            a = 2 * math.pi * i / count
            inner.append(bm.verts.new((x, math.cos(a) * core, math.sin(a) * core)))
        inner_rings.append(inner)
    for i in range(count):
        j = (i + 1) % count
        # outside skin and the hollow core
        bm.faces.new((outer_rings[0][i], outer_rings[0][j], outer_rings[1][j], outer_rings[1][i]))
        bm.faces.new((inner_rings[0][j], inner_rings[0][i], inner_rings[1][i], inner_rings[1][j]))
        # end caps (rings between outside and core)
        bm.faces.new((outer_rings[0][j], outer_rings[0][i], inner_rings[0][i], inner_rings[0][j]))
        bm.faces.new((outer_rings[1][i], outer_rings[1][j], inner_rings[1][j], inner_rings[1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object("Foam_Segment", bm)  # smooth-shaded ridges, like real foam
    if tip:
        # Rounded far end: a low dome over the +X cap
        cap = prim("uv_sphere", "Foam_Cap", location=(length / 2 - 0.04, 0, 0), scale=(0.22, valley * 0.98, valley * 0.98), segments=16, ring_count=8)
        smooth(cap)
        join([obj, cap], "Foam_Tip")
    export(name)


def pool_deck():
    """The arena: a big round deck slab, a rounded cyan coping lip, and tile rings."""
    reset()
    radius, thickness = 165, 6
    slab = prim("cylinder", "Sand_Deck", location=(0, 0, -thickness / 2), vertices=128, radius=radius - 1.5, depth=thickness)
    add_modifier_bevel(slab, 0.6, 2)
    lip = prim("torus", "Cyan_Coping", location=(0, 0, -0.4), major_radius=radius - 1.5, minor_radius=1.6, major_segments=128, minor_segments=12)
    lip.scale = (1, 1, 0.55)
    bpy.ops.object.transform_apply(scale=True)
    smooth(lip)
    # Decorative tile bands set into the deck surface
    bands = []
    for r, w in ((52, 1.2), (98, 1.2), (140, 1.6)):
        outer = prim("cylinder", f"White_Band{r}", location=(0, 0, 0.03), vertices=128, radius=r + w / 2, depth=0.08)
        inner = prim("cylinder", "cut", location=(0, 0, 0.03), vertices=128, radius=r - w / 2, depth=0.4)
        mod = outer.modifiers.new("Cut", "BOOLEAN")
        mod.object = inner
        mod.operation = "DIFFERENCE"
        bpy.context.view_layer.objects.active = outer
        bpy.ops.object.modifier_apply(modifier="Cut")
        bpy.data.objects.remove(inner)
        bands.append(outer)
    join(bands, "White_Bands")
    export("PoolDeck")


def spawn_pad():
    reset()
    base = prim("cylinder", "White_Base", location=(0, 0, 0.5), vertices=64, radius=7, depth=1)
    add_modifier_bevel(base, 0.25, 2)
    ring = prim("torus", "Cyan_Ring", location=(0, 0, 1.0), major_radius=6.2, minor_radius=0.35, major_segments=64, minor_segments=8)
    smooth(ring)
    # A pink star in the middle
    bm = bmesh.new()
    points = 5
    top, low = [], []
    for i in range(points * 2):
        a = math.pi / 2 + i * math.pi / points
        r = 3.6 if i % 2 == 0 else 1.6
        top.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 1.15)))
        low.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.95)))
    bm.faces.new(top)
    bm.faces.new(list(reversed(low)))
    for i in range(points * 2):
        j = (i + 1) % (points * 2)
        bm.faces.new((low[i], low[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh_object("Pink_Star", bm)
    export("SpawnPad")


def umbrella():
    """Beach umbrella: pole, 8-panel scalloped canopy in two alternating colors."""
    reset()
    pole = prim("cylinder", "White_Pole", location=(0, 0, 5.5), vertices=12, radius=0.22, depth=11)
    finial = prim("uv_sphere", "White_Finial", location=(0, 0, 11.25), radius=0.45, segments=12, ring_count=8)
    smooth(finial)
    join([pole, finial], "White_Pole")
    panels = 8
    radius, peak, rim = 7.0, 11.0, 9.2
    for color in ("ColorA", "ColorB"):
        bm = bmesh.new()
        for p in range(panels):
            if (p % 2 == 0) != (color == "ColorA"):
                continue
            a0 = 2 * math.pi * p / panels
            a1 = 2 * math.pi * (p + 1) / panels
            apex = bm.verts.new((0, 0, peak))
            steps = 8
            edge = []
            for s in range(steps + 1):
                t = s / steps
                a = a0 + (a1 - a0) * t
                droop = math.sin(t * math.pi) * 0.45  # scallop between ribs
                r = radius * (1 - 0.04 * math.sin(t * math.pi))
                edge.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, rim + droop)))
            # mid ring gives the canopy a dome curve
            mid = []
            for s in range(steps + 1):
                t = s / steps
                a = a0 + (a1 - a0) * t
                mid.append(bm.verts.new((math.cos(a) * radius * 0.55, math.sin(a) * radius * 0.55, peak - 0.9)))
            for s in range(steps):
                bm.faces.new((mid[s], mid[s + 1], edge[s + 1], edge[s]))
                bm.faces.new((apex, mid[s + 1], mid[s]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        obj = mesh_object(f"{color}_Canopy", bm)
        solid = obj.modifiers.new("Thick", "SOLIDIFY")
        solid.thickness = 0.15
    export("Umbrella")


def lounge_chair():
    reset()
    frame = []
    for x in (-3.2, 3.2):
        for y in (-1.3, 1.3):
            frame.append(prim("cylinder", "White_Leg", location=(x, y, 0.6), vertices=8, radius=0.13, depth=1.2))
    for y in (-1.3, 1.3):
        frame.append(prim("cylinder", "White_Rail", location=(0, y, 1.2), rotation=(0, math.pi / 2, 0), vertices=8, radius=0.13, depth=6.6))
    join(frame, "White_Frame")
    seat = prim("cube", "Accent_Seat", location=(0.9, 0, 1.4), scale=(2.4, 1.25, 0.18))
    add_modifier_bevel(seat, 0.12, 3)
    back = prim("cube", "Accent_Back", location=(-2.35, 0, 2.25), rotation=(0, math.radians(-38), 0), scale=(1.2, 1.25, 0.18))
    add_modifier_bevel(back, 0.12, 3)
    join([seat, back], "Accent_Cushion")
    export("LoungeChair")


def lifeguard_tower():
    reset()
    wood = []
    for x in (-1.6, 1.6):
        for y in (-1.6, 1.6):
            wood.append(prim("cube", "Wood_Leg", location=(x * 1.15, y * 1.15, 4), rotation=(math.radians(-y * 2.5), math.radians(x * 2.5), 0), scale=(0.25, 0.25, 4.1)))
    platform = prim("cube", "Wood_Platform", location=(0, 0, 8.2), scale=(2.4, 2.4, 0.2))
    wood.append(platform)
    for z in (2.4, 4.8, 7.0):  # ladder rungs on the front
        wood.append(prim("cube", "Wood_Rung", location=(0, -2.15, z), scale=(1.1, 0.12, 0.12)))
    for x in (-1.1, 1.1):
        wood.append(prim("cube", "Wood_Rail", location=(x, -2.15, 4.2), scale=(0.12, 0.12, 4.2)))
    join(wood, "Wood_Frame")
    seat = prim("cube", "Red_Seat", location=(0, 0.6, 8.9), scale=(1.3, 1.0, 0.25))
    add_modifier_bevel(seat, 0.08)
    back = prim("cube", "Red_Back", location=(0, 1.55, 10.0), scale=(1.3, 0.15, 1.2))
    add_modifier_bevel(back, 0.08)
    join([seat, back], "Red_Seat")
    # Little striped roof
    for color, start in (("Red", 0), ("White", 1)):
        bm = bmesh.new()
        sides = 8
        apex = bm.verts.new((0, 0, 14.2))
        for i in range(sides):
            if i % 2 != start:
                continue
            a0, a1 = 2 * math.pi * i / sides, 2 * math.pi * (i + 1) / sides
            v0 = bm.verts.new((math.cos(a0) * 3.2, math.sin(a0) * 3.2, 12.6))
            v1 = bm.verts.new((math.cos(a1) * 3.2, math.sin(a1) * 3.2, 12.6))
            bm.faces.new((apex, v0, v1))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        roof = mesh_object(f"{color}_Roof", bm)
        roof.modifiers.new("Thick", "SOLIDIFY").thickness = 0.15
    post = prim("cylinder", "White_Post", location=(0, 1.55, 11.3), vertices=8, radius=0.12, depth=3)
    export("LifeguardTower")


def beach_ball():
    """Six colored wedges plus white caps."""
    reset()
    colors = ["Red", "White", "Blue", "Yellow", "White", "Green"]
    radius = 2.0
    for idx, color in enumerate(colors):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=36, v_segments=18, radius=radius)
        keep = set()
        for f in bm.faces:
            c = f.calc_center_median()
            ang = (math.atan2(c.y, c.x) + 2 * math.pi) % (2 * math.pi)
            wedge = int(ang / (2 * math.pi / 6))
            if wedge == idx and abs(c.z) < radius * 0.85:
                keep.add(f)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
        mesh_object(f"{color}_Wedge{idx}", bm)
    caps = bmesh.new()
    bmesh.ops.create_uvsphere(caps, u_segments=36, v_segments=18, radius=radius * 1.003)
    bmesh.ops.delete(caps, geom=[f for f in caps.faces if abs(f.calc_center_median().z) < radius * 0.85], context="FACES")
    mesh_object("White_Caps", caps)
    whites = [o for o in bpy.context.scene.objects if o.name.startswith("White")]
    join(whites, "White_Ball")
    export("BeachBall")


def swim_ring():
    reset()
    for color, start in (("ColorA", 0), ("ColorB", 1)):
        bm = bmesh.new()
        bmesh.ops.create_cone  # noqa: B018 (keep bmesh import obviously used)
        major, minor, seg, rings = 2.2, 0.85, 48, 16
        stripes = 8
        verts = {}
        for i in range(seg + 1):
            for j in range(rings):
                u = 2 * math.pi * i / seg
                v = 2 * math.pi * j / rings
                x = (major + minor * math.cos(v)) * math.cos(u)
                y = (major + minor * math.cos(v)) * math.sin(u)
                z = minor * math.sin(v)
                verts[(i, j)] = bm.verts.new((x, y, z))
        per = seg // stripes
        for i in range(seg):
            if (i // per) % 2 != start:
                continue
            for j in range(rings):
                k = (j + 1) % rings
                bm.faces.new((verts[(i, j)], verts[(i + 1, j)], verts[(i + 1, k)], verts[(i, k)]))
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh_object(f"{color}_Ring", bm)
    export("SwimRing")


def rubber_duck():
    """A giant inflatable rubber duck."""
    reset()
    body = prim("uv_sphere", "Yellow_Body", location=(0, 0, 2.2), scale=(3.0, 2.3, 1.9), segments=32, ring_count=16)
    tail = prim("cone", "Yellow_Tail", location=(-2.9, 0, 3.2), rotation=(0, math.radians(-60), 0), vertices=16, radius1=1.0, radius2=0.1, depth=1.8)
    head = prim("uv_sphere", "Yellow_Head", location=(1.8, 0, 5.0), scale=(1.55, 1.5, 1.5), segments=32, ring_count=16)
    wings = [prim("uv_sphere", "Yellow_Wing", location=(-0.3, y, 2.8), scale=(1.5, 0.45, 0.8), segments=16, ring_count=8) for y in (-2.0, 2.0)]
    for o in [body, head, tail, *wings]:
        smooth(o)
    join([body, head, tail, *wings], "Yellow_Duck")
    beak = prim("uv_sphere", "Orange_Beak", location=(3.35, 0, 4.7), scale=(0.9, 0.85, 0.35), segments=16, ring_count=8)
    smooth(beak)
    eyes = []
    for y in (-0.62, 0.62):
        white = prim("uv_sphere", "White_Eye", location=(2.95, y, 5.45), radius=0.38, segments=16, ring_count=8)
        smooth(white)
        eyes.append(white)
    join(eyes, "White_Eyes")
    pupils = [prim("uv_sphere", "Black_Pupil", location=(3.27, y, 5.5), radius=0.18, segments=12, ring_count=6) for y in (-0.6, 0.6)]
    for p in pupils:
        smooth(p)
    join(pupils, "Black_Pupils")
    export("RubberDuck")


def palm_tree():
    reset()
    trunk_parts = []
    height, sections = 18.0, 9
    for i in range(sections):
        t = i / sections
        bend = math.sin(t * math.pi * 0.5) * 2.4  # leans to one side
        z = height * t + height / sections / 2
        r = 0.75 - 0.25 * t
        trunk_parts.append(prim("cylinder", "Bark_Ring", location=(bend, 0, z), rotation=(0, math.radians(8 * t), 0), vertices=10, radius=r, depth=height / sections * 1.05, end_fill_type="NGON"))
        trunk_parts.append(prim("cylinder", "Bark_Lip", location=(bend, 0, z + height / sections * 0.45), vertices=10, radius=r * 1.12, depth=0.25))
    join(trunk_parts, "Bark_Trunk")
    top = Vector((2.4, 0, height + 0.3))
    leaves = []
    for k in range(8):
        a = 2 * math.pi * k / 8 + 0.2
        bm = bmesh.new()
        length, width = 7.5, 1.4
        segs = 8
        left, right, mid = [], [], []
        for s in range(segs + 1):
            t = s / segs
            d = length * t
            droop = -2.8 * t * t
            w = width * math.sin(t * math.pi) * (1 - 0.3 * t)
            dirv = Vector((math.cos(a), math.sin(a), 0))
            side = Vector((-math.sin(a), math.cos(a), 0))
            centre = top + dirv * d + Vector((0, 0, droop + 0.6 * math.sin(t * math.pi)))
            mid.append(bm.verts.new(centre + Vector((0, 0, 0.15))))
            left.append(bm.verts.new(centre + side * w))
            right.append(bm.verts.new(centre - side * w))
        for s in range(segs):
            bm.faces.new((mid[s], mid[s + 1], left[s + 1], left[s]))
            bm.faces.new((mid[s], right[s], right[s + 1], mid[s + 1]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        leaf = mesh_object(f"Leaf_{k}", bm)
        leaf.modifiers.new("Thick", "SOLIDIFY").thickness = 0.12
        leaves.append(leaf)
    join(leaves, "Leaf_Fronds")
    nuts = []
    for k in range(3):
        a = 2 * math.pi * k / 3
        nut = prim("uv_sphere", "Brown_Coconut", location=(top.x + math.cos(a) * 0.6, math.sin(a) * 0.6, height - 0.4), radius=0.5, segments=12, ring_count=8)
        smooth(nut)
        nuts.append(nut)
    join(nuts, "Brown_Coconuts")
    export("PalmTree")


def crate():
    reset()
    box = prim("cube", "Wood_Box", scale=(2.35, 2.35, 2.35), location=(0, 0, 2.5))
    add_modifier_bevel(box, 0.08)
    frame = []
    s = 2.5
    for axis in range(3):
        for a in (-1, 1):
            for b in (-1, 1):
                loc = [0, 0, 0]
                loc[(axis + 1) % 3] = a * (s - 0.18)
                loc[(axis + 2) % 3] = b * (s - 0.18)
                size = [0.22, 0.22, 0.22]
                size[axis] = s - 0.24 if axis != 2 else s - 0.15  # no overlap at the corners
                frame.append(prim("cube", "WoodDark_Edge", location=(loc[0], loc[1], loc[2] + 2.5), scale=tuple(size)))
    # Diagonal brace on each side
    for rot_z in (0, math.pi / 2, math.pi, -math.pi / 2):
        brace = prim("cube", "WoodDark_Brace", location=(0, 0, 2.5), scale=(3.1, 0.18, 0.2), rotation=(0, math.radians(45), 0))
        brace.location = Matrix.Rotation(rot_z, 4, "Z") @ Vector((0, -s - 0.05, 2.5))
        brace.rotation_euler = (0, math.radians(45), rot_z)
        frame.append(brace)
    join(frame, "WoodDark_Frame")
    export("Crate")


MODELS = {
    "NoodleSegment": lambda: noodle_segment(),
    "NoodleTip": lambda: noodle_segment("NoodleTip", tip=True),
    "PoolDeck": pool_deck,
    "SpawnPad": spawn_pad,
    "Umbrella": umbrella,
    "LoungeChair": lounge_chair,
    "LifeguardTower": lifeguard_tower,
    "BeachBall": beach_ball,
    "SwimRing": swim_ring,
    "RubberDuck": rubber_duck,
    "PalmTree": palm_tree,
    "Crate": crate,
}

only = os.environ.get("ONLY_MODELS")
for model_name, build in MODELS.items():
    if only and model_name not in only.split(","):
        continue
    build()
print("ALL DONE")
