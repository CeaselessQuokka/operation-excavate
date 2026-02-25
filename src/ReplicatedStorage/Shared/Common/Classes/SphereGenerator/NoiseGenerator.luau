--[[
	Deterministic noise generation module.
	Wraps math.noise with seed-based offsets and provides Fractal Brownian Motion (FBM)
	for natural-looking terrain. Multiple independent channels are derived from a single seed
	so different noise purposes (terrain height, temperature, moisture, etc.) produce
	uncorrelated results while remaining deterministic.
]]

--!strict

--- Types ---
type ChannelOffset = {
	X: number,
	Y: number,
	Z: number,
}

--- Variables ---
local CHANNEL_COUNT = 10
local mathNoise = math.noise

--- Noise Generator Class ---
local NoiseGenerator = {}
NoiseGenerator.__index = NoiseGenerator

export type NoiseGenerator = typeof(setmetatable(
	{} :: {
		_offsets: { ChannelOffset },
	},
	NoiseGenerator
))

function NoiseGenerator.new(seed: number): NoiseGenerator
	local rng = Random.new(seed)
	local offsets: { ChannelOffset } = table.create(CHANNEL_COUNT) :: any

	for i = 1, CHANNEL_COUNT do
		offsets[i] = {
			X = rng:NextNumber(-10000, 10000),
			Y = rng:NextNumber(-10000, 10000),
			Z = rng:NextNumber(-10000, 10000),
		}
	end

	local self: NoiseGenerator = setmetatable({
		_offsets = offsets,
	}, NoiseGenerator)

	return self
end

function NoiseGenerator.Sample3D(self: NoiseGenerator, x: number, y: number, z: number, channel: number?): number
	local offset = self._offsets[channel or 1]
	return math.noise(x + offset.X, y + offset.Y, z + offset.Z)
end

function NoiseGenerator.FBM3D(
	self: NoiseGenerator,
	x: number,
	y: number,
	z: number,
	octaves: number,
	lacunarity: number,
	persistence: number,
	channel: number?
): number
	local offset = self._offsets[channel or 1]
	local ox, oy, oz = offset.X, offset.Y, offset.Z
	local total = 0
	local amplitude = 1
	local frequency = 1
	local maxValue = 0

	for _ = 1, octaves do
		total += mathNoise(x * frequency + ox, y * frequency + oy, z * frequency + oz) * amplitude
		maxValue += amplitude
		amplitude *= persistence
		frequency *= lacunarity
	end

	return total / maxValue
end

return table.freeze(NoiseGenerator)
