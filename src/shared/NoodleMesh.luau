--!strict
-- Noodle pieces built from the Blender foam mesh (ReplicatedStorage.ModelLibrary)
-- when it has loaded, or plain cylinders if not. Used by the live noodles
-- (client/NoodleVisuals) and the thumbnail scene.
--
-- The mesh is longer than it is wide, so its longest side tells us which of
-- the part's axes runs along the noodle, whatever way the import turned it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Piece = {
	part: BasePart,
	axis: "X" | "Y" | "Z", -- the part's axis that runs along the noodle
	turn: CFrame, -- lines that axis up with a CFrame's look direction
}

local NoodleMesh = {}

local TURNS = {
	X = CFrame.Angles(0, math.rad(90), 0),
	Y = CFrame.Angles(math.rad(90), 0, 0),
	Z = CFrame.identity,
}

local function templatePart(name: string): BasePart?
	local library = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local model = library and library:FindFirstChild(name)
	if model then
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") then
				return child
			end
		end
	end
	return nil
end

-- True once the foam mesh is available (it loads a few seconds after the server starts).
function NoodleMesh.isMeshReady(): boolean
	return templatePart("NoodleSegment") ~= nil
end

-- A new piece in `color`. `isTip` gives the rounded end piece if there is one.
function NoodleMesh.newPiece(isTip: boolean, color: Color3): Piece
	local template = (if isTip then templatePart("NoodleTip") else nil) or templatePart("NoodleSegment")
	local part: BasePart
	local axis: "X" | "Y" | "Z" = "X"
	if template then
		part = template:Clone()
		local size = part.Size
		axis = if size.X >= size.Y and size.X >= size.Z then "X" elseif size.Y >= size.Z then "Y" else "Z"
	else
		local cylinder = Instance.new("Part")
		cylinder.Shape = Enum.PartType.Cylinder -- runs along X
		part = cylinder
	end
	part.Name = if isTip then "NoodleTip" else "NoodleSegment"
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return { part = part, axis = axis, turn = TURNS[axis] }
end

-- Stretches the piece to `length` along the noodle and `thickness` across it.
function NoodleMesh.setSize(piece: Piece, length: number, thickness: number)
	local t = thickness
	piece.part.Size = if piece.axis == "X"
		then Vector3.new(length, t, t)
		elseif piece.axis == "Y" then Vector3.new(t, length, t)
		else Vector3.new(t, t, length)
end

-- Where the piece goes to span from point `a` to point `b`.
function NoodleMesh.cframeBetween(piece: Piece, a: Vector3, b: Vector3): CFrame
	return CFrame.lookAt((a + b) / 2, b) * piece.turn
end

return NoodleMesh
