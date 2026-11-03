--!strict
-- Draws every noodle (players' and fighting dummies') as a bendy chain of foam segments (the ridged
-- Blender foam mesh once it has loaded, cylinders before that). Each client
-- simulates every noodle itself, so they all look smooth with no network cost.
-- The real Tool is only an invisible handle in the hand.
--
-- After updating the local player's noodle, it calls the onLocalStep
-- callbacks so NoodleController can check for hits on the same frame.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local NoodleMesh = require(Shared.NoodleMesh)
local Skins = require(Shared.Skins)
local NoodleSim = require(script.Parent.NoodleSim)
local Vanish = require(script.Parent.Vanish)

type NoodleDef = Noodles.NoodleDef

export type Visual = {
	tool: Tool,
	handle: BasePart,
	character: Model,
	def: NoodleDef,
	sim: NoodleSim.Sim,
	segments: { NoodleMesh.Piece },
	joints: { BasePart },
	scale: number,
	usesMesh: boolean, -- built with the foam mesh (else rebuilt once it loads)
	skin: string?, -- skin currently drawn (the Tool's "Skin" attribute)
	transparency: number, -- 0 normal, 1 hidden (Invisible noodle, Vanish)
}

local player = Players.LocalPlayer

local NoodleVisuals = {}

local visuals: { [Tool]: Visual } = {}
local localStepCallbacks: { (Visual, number) -> () } = {}
local folder: Folder
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function makePart(shape: Enum.PartType, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Shape = shape
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder
	return part
end

local function applySize(visual: Visual)
	local segmentLength = visual.def.Length * visual.scale / Config.NoodleSegments
	local thickness = visual.def.Thickness * visual.scale
	for _, segment in visual.segments do
		-- A little overlap hides the seams where the noodle bends
		NoodleMesh.setSize(segment, segmentLength * 1.12, thickness)
	end
	for _, joint in visual.joints do
		-- Joints fill the gap on the outside of bends; slightly thinner than the ridges
		joint.Size = Vector3.one * thickness * 0.88
	end
	visual.sim:setSegmentLength(segmentLength)
end

-- Colors the noodle for its skin, or the noodle's own color with no skin.
local function applySkin(visual: Visual, skinId: string?)
	visual.skin = skinId
	local skin = if skinId then Skins.ById[skinId] else nil
	local color = if skin then skin.Color else visual.def.Color
	local material = if skin then skin.Material else Enum.Material.SmoothPlastic
	for _, piece in visual.segments do
		piece.part.Color = color
		piece.part.Material = material
	end
	for _, joint in visual.joints do
		joint.Color = color
		joint.Material = material
	end
end

local INVISIBLE_SELF = 0.7 -- your own Invisible noodle, faint so you can aim

-- Invisible noodles and vanished players: hidden from others, faint to yourself.
local function transparencyOf(visual: Visual): number
	if visual.tool:GetAttribute("Thrown") then
		return 1 -- the Boomerang noodle is out flying
	end
	local mine = visual.character == player.Character
	local amount = Vanish.transparencyFor(visual.character)
	if visual.def.Invisible then
		amount = math.max(amount, if mine then INVISIBLE_SELF else 1)
	end
	return amount
end

local function applyTransparency(visual: Visual, amount: number)
	visual.transparency = amount
	for _, piece in visual.segments do
		piece.part.Transparency = amount
	end
	for i, joint in visual.joints do
		joint.Transparency = if i == #visual.joints then 1 else amount
	end
end

local function skinOf(tool: Tool): string?
	local skin = tool:GetAttribute("Skin")
	return if type(skin) == "string" and Skins.ById[skin] then skin else nil
end

local function create(tool: Tool, handle: BasePart, character: Model, def: NoodleDef): Visual
	local segments, joints = {}, {}
	for i = 1, Config.NoodleSegments do
		local piece = NoodleMesh.newPiece(i == Config.NoodleSegments, def.Color)
		piece.part.Parent = folder
		segments[i] = piece
		joints[i] = makePart(Enum.PartType.Ball, def.Color)
		if i == Config.NoodleSegments then
			joints[i].Transparency = 1 -- nothing to join after the tip
		end
	end
	local visual: Visual = {
		tool = tool,
		handle = handle,
		character = character,
		def = def,
		sim = NoodleSim.new(
			Config.NoodleSegments,
			def.Length / Config.NoodleSegments,
			def.Stiffness,
			Config.NoodleDamping,
			Config.NoodleSag
		),
		segments = segments,
		joints = joints,
		scale = 1,
		usesMesh = NoodleMesh.isMeshReady(),
		skin = nil,
		transparency = 0,
	}
	applySize(visual)
	applySkin(visual, skinOf(tool))
	return visual
end

local function destroy(visual: Visual)
	for _, piece in visual.segments do
		piece.part:Destroy()
	end
	for _, part in visual.joints do
		part:Destroy()
	end
	visuals[visual.tool] = nil
end

-- Player characters, plus dummies (they hold noodles in dummy fight mode).
local function noodleHolders(): { Model }
	local list = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	for _, dummy in CollectionService:GetTagged(Config.DummyTag) do
		if dummy:IsA("Model") then
			table.insert(list, dummy)
		end
	end
	return list
end

-- Finds every noodle currently held by a character.
local function syncTools()
	local held: { [Tool]: boolean } = {}
	for _, character in noodleHolders() do
		local tool = character and character:FindFirstChildOfClass("Tool")
		local id = tool and tool:GetAttribute("NoodleId")
		local def = if type(id) == "string" then Noodles[id] else nil
		local handle = tool and tool:FindFirstChild("Handle")
		if tool and def and handle and handle:IsA("BasePart") then
			held[tool] = true
			local existing = visuals[tool]
			if existing and not existing.usesMesh and NoodleMesh.isMeshReady() then
				destroy(existing) -- the foam mesh just loaded; rebuild with it
			end
			if not visuals[tool] then
				visuals[tool] = create(tool, handle, character, def)
			end
		end
	end
	for tool, visual in visuals do
		if not held[tool] then
			destroy(visual)
		end
	end
end

local function step(dt: number)
	syncTools()
	table.clear(moveParts)
	table.clear(moveCFrames)

	for tool, visual in visuals do
		-- Smoothly grow or shrink for the Inflate ability
		local scaleAttribute = tool:GetAttribute("Scale")
		local targetScale = if type(scaleAttribute) == "number" then scaleAttribute else 1
		if visual.scale ~= targetScale then
			visual.scale += (targetScale - visual.scale) * math.min(1, dt * 8)
			if math.abs(targetScale - visual.scale) < 0.01 then
				visual.scale = targetScale
			end
			applySize(visual)
		end

		-- Skin changes (picked from the menu) and the rainbow skin's moving colors
		local skinId = skinOf(tool)
		if skinId ~= visual.skin then
			applySkin(visual, skinId)
		end
		local transparency = transparencyOf(visual)
		if transparency ~= visual.transparency then
			applyTransparency(visual, transparency)
		end

		local skin = if skinId then Skins.ById[skinId] else nil
		if skin and skin.Rainbow then
			local now = os.clock()
			local count = #visual.segments
			for i, piece in visual.segments do
				local color = Skins.rainbowAt(i / count, now)
				piece.part.Color = color
				visual.joints[i].Color = color
			end
		end

		local handleCFrame = visual.handle.CFrame
		visual.sim:step(dt, handleCFrame.Position, handleCFrame.LookVector * Config.GripSign)

		local points = visual.sim.points
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			if (b - a).Magnitude > 1e-3 then
				local piece = visual.segments[i]
				table.insert(moveParts, piece.part)
				table.insert(moveCFrames, NoodleMesh.cframeBetween(piece, a, b))
			end
			table.insert(moveParts, visual.joints[i])
			table.insert(moveCFrames, CFrame.new(b))
		end

		if visual.character == player.Character then
			for _, callback in localStepCallbacks do
				callback(visual, dt)
			end
		end
	end

	workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Runs `callback(visual, dt)` every frame after the local player's noodle moves.
function NoodleVisuals.onLocalStep(callback: (Visual, number) -> ())
	table.insert(localStepCallbacks, callback)
end

function NoodleVisuals.start()
	folder = Instance.new("Folder")
	folder.Name = "NoodleVisuals"
	folder.Parent = workspace

	-- After the camera has turned the character this frame
	RunService:BindToRenderStep("NoodleVisuals", Enum.RenderPriority.Camera.Value + 2, step)
end

return NoodleVisuals
