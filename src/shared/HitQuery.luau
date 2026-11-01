--!strict
-- Shared hit geometry. The client uses it to pick targets when it swings, and
-- the server uses the same cone check (with extra tolerance) to validate them.

local Config = require(script.Parent.Config)

local HitQuery = {}

-- Walks up from a part to the model that owns a Humanoid.
function HitQuery.getCharacter(part: Instance): (Model?, Humanoid?)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return model :: Model, humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

-- True if targetPos is within range and inside a flat (ignoring height) arc
-- in front of origin.
function HitQuery.isInCone(origin: CFrame, targetPos: Vector3, range: number, arcDeg: number): boolean
	local offset = targetPos - origin.Position
	if offset.Magnitude > range then
		return false
	end

	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local look = origin.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatOffset.Magnitude < 0.5 or flatLook.Magnitude < 0.01 then
		return true -- standing on top of each other
	end

	local halfArc = math.rad(math.min(arcDeg, 360) / 2)
	return flatLook.Unit:Dot(flatOffset.Unit) >= math.cos(halfArc)
end

-- Living characters in front of `character`, closest first.
function HitQuery.findTargets(character: Model, range: number, arcDeg: number, maxTargets: number): { Model }
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return {}
	end

	local reach = range + Config.BodyRadius
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local found: { { model: Model, distance: number } } = {}
	local seen: { [Model]: boolean } = {}

	for _, part in workspace:GetPartBoundsInRadius(root.Position, reach, params) do
		local model, humanoid = HitQuery.getCharacter(part)
		if model and humanoid and not seen[model] and humanoid.Health > 0 then
			seen[model] = true
			local targetRoot = model:FindFirstChild("HumanoidRootPart")
			if
				targetRoot
				and targetRoot:IsA("BasePart")
				and HitQuery.isInCone(root.CFrame, targetRoot.Position, reach, arcDeg)
			then
				table.insert(found, {
					model = model,
					distance = (targetRoot.Position - root.Position).Magnitude,
				})
			end
		end
	end

	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)

	local result = {}
	for i = 1, math.min(maxTargets, #found) do
		result[i] = found[i].model
	end
	return result
end

return HitQuery
