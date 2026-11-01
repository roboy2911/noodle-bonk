--!strict
-- A bendy foam noodle: a chain of points that each spring back toward a
-- straight "rest" line out of the hand. Points near the hand are stiffer, so
-- fast turns make the tip lag behind and whip around, then wobble to a stop.
--
-- points[1] is the hand; points[#points] is the tip.

local NoodleSim = {}
NoodleSim.__index = NoodleSim

local MAX_STEP = 1 / 60
local RESET_DISTANCE = 25 -- the hand jumped (respawn, teleport): snap straight

export type Sim = typeof(setmetatable(
	{} :: {
		points: { Vector3 },
		previous: { Vector3 }, -- positions last frame, for hit sweeps
		velocities: { Vector3 },
		segmentLength: number,
		stiffness: number,
		damping: number,
		sag: number,
		initialized: boolean,
	},
	NoodleSim
))

function NoodleSim.new(segments: number, segmentLength: number, stiffness: number, damping: number, sag: number): Sim
	local self = setmetatable({
		points = {},
		previous = {},
		velocities = {},
		segmentLength = segmentLength,
		stiffness = stiffness,
		damping = damping,
		sag = sag,
		initialized = false,
	}, NoodleSim)
	for i = 1, segments + 1 do
		self.points[i] = Vector3.zero
		self.previous[i] = Vector3.zero
		self.velocities[i] = Vector3.zero
	end
	return self
end

function NoodleSim.setSegmentLength(self: Sim, length: number)
	self.segmentLength = length
end

local function reset(self: Sim, base: Vector3, direction: Vector3)
	for i = 1, #self.points do
		local rest = base + direction * self.segmentLength * (i - 1)
		self.points[i] = rest
		self.previous[i] = rest
		self.velocities[i] = Vector3.zero
	end
	self.initialized = true
end

-- Advances the simulation. `base` is the hand, `direction` the way the noodle points.
function NoodleSim.step(self: Sim, dt: number, base: Vector3, direction: Vector3)
	if not self.initialized or (base - self.points[1]).Magnitude > RESET_DISTANCE then
		reset(self, base, direction)
		return
	end

	local count = #self.points
	for i = 1, count do
		self.previous[i] = self.points[i]
	end

	local steps = math.clamp(math.ceil(dt / MAX_STEP), 1, 4)
	local h = dt / steps
	local gravity = Vector3.new(0, -self.sag, 0)
	local decay = math.exp(-self.damping * h)
	local predicted = table.create(count, Vector3.zero)

	for _ = 1, steps do
		predicted[1] = base

		-- Springs toward the straight rest line, stiffer near the hand
		for i = 2, count do
			local rest = base + direction * self.segmentLength * (i - 1)
			local stiffness = self.stiffness * (1 - 0.6 * (i - 2) / (count - 1))
			local velocity = self.velocities[i] + ((rest - self.points[i]) * stiffness + gravity) * h
			predicted[i] = self.points[i] + velocity * decay * h
		end

		-- Keep every segment the same length so the noodle never stretches
		for i = 2, count do
			local offset = predicted[i] - predicted[i - 1]
			local length = offset.Magnitude
			if length > 1e-4 then
				predicted[i] = predicted[i - 1] + offset * (self.segmentLength / length)
			end
		end

		for i = 2, count do
			self.velocities[i] = (predicted[i] - self.points[i]) / h
			self.points[i] = predicted[i]
		end
		self.points[1] = base
	end
end

-- Kicks a point (and a little of its neighbours), e.g. bouncing off a hit.
function NoodleSim.impulse(self: Sim, index: number, impulse: Vector3)
	for i = math.max(2, index - 1), math.min(#self.points, index + 1) do
		local weight = if i == index then 1 else 0.5
		self.velocities[i] += impulse * weight
	end
end

return NoodleSim
