--!strict
-- Draws every player's noodle as a bendy chain of foam segments. Each client
-- simulates every noodle itself, so they all look smooth with no network cost.
-- The real Tool is only an invisible handle in the hand.
--
-- After updating the local player's noodle, it calls the onLocalStep
-- callbacks so NoodleController can check for hits on the same frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local NoodleSim = require(script.Parent.NoodleSim)

type NoodleDef = Noodles.NoodleDef

export type Visual = {
	tool: Tool,
	handle: BasePart,
	character: Model,
	def: NoodleDef,
	sim: NoodleSim.Sim,
	segments: { BasePart },
	joints: { BasePart },
	scale: number,
}

-- Cylinders run along X; this turns one to run along a CFrame's look direction
local CYLINDER_TURN = CFrame.Angles(0, math.rad(90), 0)

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
		segment.Size = Vector3.new(segmentLength + thickness * 0.1, thickness, thickness)
	end
	for _, joint in visual.joints do
		joint.Size = Vector3.one * thickness
	end
	visual.sim:setSegmentLength(segmentLength)
end

local function create(tool: Tool, handle: BasePart, character: Model, def: NoodleDef): Visual
	local segments, joints = {}, {}
	for i = 1, Config.NoodleSegments do
		segments[i] = makePart(Enum.PartType.Cylinder, def.Color)
		joints[i] = makePart(Enum.PartType.Ball, def.Color)
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
	}
	applySize(visual)
	return visual
end

local function destroy(visual: Visual)
	for _, part in visual.segments do
		part:Destroy()
	end
	for _, part in visual.joints do
		part:Destroy()
	end
	visuals[visual.tool] = nil
end

-- Finds every noodle currently held by a character.
local function syncTools()
	local held: { [Tool]: boolean } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		local id = tool and tool:GetAttribute("NoodleId")
		local def = if type(id) == "string" then Noodles[id] else nil
		local handle = tool and tool:FindFirstChild("Handle")
		if character and tool and def and handle and handle:IsA("BasePart") then
			held[tool] = true
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

		local handleCFrame = visual.handle.CFrame
		visual.sim:step(dt, handleCFrame.Position, handleCFrame.LookVector * Config.GripSign)

		local points = visual.sim.points
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			if (b - a).Magnitude > 1e-3 then
				table.insert(moveParts, visual.segments[i])
				table.insert(moveCFrames, CFrame.lookAt((a + b) / 2, b) * CYLINDER_TURN)
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
