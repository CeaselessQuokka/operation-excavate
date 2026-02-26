--[[
	Deterministic sphere terrain generator with a chunk-based API.
	Designed to produce terrain compatible with Infinigrid's zero-based chunk indexing.
	Uses Infinigrid internally for all grid/index/position math.

	Usage:
		local planet = PlanetGenerator.new(masterSeed, chunkSize)
		local result = planet:GenerateChunk(chunkIndex) -- zero-based index matching Infinigrid

	The constructor yields during surface grid precomputation.
	ChunkSize is in studs and will be aligned to multiples of 8 to match Infinigrid.
	The internal Infinigrid is exposed as planet.Grid:

		planet.Grid -- direct access to the Infinigrid instance
]]

--!strict

--- Imports ---
local Biomes = require(script.Parent.Biomes)
local Infinigrid = require(script.Parent.Parent.Infinigrid)
local NoiseGenerator = require(script.Parent.NoiseGenerator)

--- Types ---
type Biome = Biomes.Biome
type NoiseGen = NoiseGenerator.NoiseGenerator

type ChannelOffset = {
	X: number,
	Y: number,
	Z: number,
}

export type GenerateChunkResult = {
	ChunkType: string, -- "Air" | "Deep" | "Surface"
	IsWater: boolean, -- Whether this chunk contains any water voxels
	ChunkSeed: number,
}

export type PeekChunkResult = {
	ChunkType: string, -- "Air" | "Surface" | "Buried"
	IsWater: boolean, -- Whether this chunk contains (or would contain) water voxels
	MinHeight: number?, -- Min terrain elevation relative to sea level (Surface only)
	MaxHeight: number?, -- Max terrain elevation relative to sea level (Surface only)
	Generated: boolean, -- Whether GenerateChunk has been called for this chunk
	ChunkSeed: number,
}

--- Variables ---
local RESOLUTION = 4
local INV_RESOLUTION = 1 / RESOLUTION
local DEEP_STRIDE = 4

local RADIUS = 8192
local SEA_LEVEL_OFFSET = 0
local MAX_HEIGHT_VARIATION = 512
local SEA_LEVEL = RADIUS + SEA_LEVEL_OFFSET

local TERRAIN_NOISE_SCALE = 6
local TEMPERATURE_NOISE_SCALE = 2.5
local MOISTURE_NOISE_SCALE = 3
local MOUNTAIN_NOISE_SCALE = 1.8
local MOUNTAIN_RIDGE_SCALE = 0.8
local CONTINENT_NOISE_SCALE = 1.2
local CONTINENT_LAND_BIAS = 0.02

local SNOW_LINE_ALTITUDE = 300
local TREELINE_ALTITUDE = 220

local SURFACE_DEPTH = 12
local SUBSURFACE_DEPTH = 48
local SHORE_PROXIMITY = 6

local CH_TERRAIN = 1
local CH_TEMPERATURE = 2
local CH_MOISTURE = 3
local CH_MOUNTAIN = 4
local CH_DETAIL = 5
local CH_CONTINENT = 6
local CH_CONTINENT2 = 7
local CH_OCEAN_FLOOR = 8
local CH_LAYER_VARIETY = 9
local CH_LAYER_VARIETY2 = 10

local LAYER_INNER_CORE_CENTER = 0.02
local LAYER_INNER_CORE = 0.16
local LAYER_OUTER_CORE = 0.35
local LAYER_LOWER_MANTLE = 0.55
local LAYER_MID_MANTLE = 0.70
local LAYER_UPPER_MANTLE = 0.82
local LAYER_LOWER_CRUST = 0.90
local LAYER_UPPER_CRUST = 0.95

local GRID_LAT = 256
local GRID_LON = 512
local PI = math.pi
local TWO_PI = 2 * math.pi

local mathClamp = math.clamp
local mathFloor = math.floor
local mathSqrt = math.sqrt
local mathAcos = math.acos
local mathAtan2 = math.atan2
local mathNoise = math.noise

--- Functions ---

local function getLayerMaterial(
	nOff: { ChannelOffset },
	dist: number,
	wx: number,
	wy: number,
	wz: number
): Enum.Material?
	local frac = dist / RADIUS
	if frac >= LAYER_UPPER_CRUST then
		return nil
	end
	if frac < LAYER_INNER_CORE_CENTER then
		return Enum.Material.Salt
	end

	local nScale = 0.015
	local o1 = nOff[CH_LAYER_VARIETY]
	local n1 = mathNoise(wx * nScale + o1.X, wy * nScale + o1.Y, wz * nScale + o1.Z)
	local n2Scale = nScale * 3.5
	local o2 = nOff[CH_LAYER_VARIETY2]
	local n2 = mathNoise(wx * n2Scale + o2.X, wy * n2Scale + o2.Y, wz * n2Scale + o2.Z)
	local n3Scale = nScale * 7
	local o3 = nOff[CH_TERRAIN]
	local n3 = mathNoise(wx * n3Scale + o3.X, wy * n3Scale + o3.Y, wz * n3Scale + o3.Z)

	if frac < LAYER_INNER_CORE then
		if n3 > 0.35 then
			return Enum.Material.Asphalt
		end
		if n1 > 0.25 then
			return Enum.Material.Basalt
		end
		return Enum.Material.CrackedLava
	elseif frac < LAYER_OUTER_CORE then
		if n1 > 0.3 then
			return Enum.Material.CrackedLava
		end
		if n2 > 0.28 and frac > LAYER_OUTER_CORE - 0.03 then
			return Enum.Material.Concrete
		end
		return Enum.Material.Basalt
	elseif frac < LAYER_LOWER_MANTLE then
		if n1 > 0.3 then
			return Enum.Material.Basalt
		end
		if n2 > 0.28 then
			return Enum.Material.Sandstone
		end
		if n3 > 0.38 then
			return Enum.Material.Asphalt
		end
		return Enum.Material.Concrete
	elseif frac < LAYER_MID_MANTLE then
		if n1 > 0.28 then
			return Enum.Material.Concrete
		end
		if n2 > 0.25 then
			return Enum.Material.Rock
		end
		return Enum.Material.Slate
	elseif frac < LAYER_UPPER_MANTLE then
		if n1 > 0.28 then
			return Enum.Material.Slate
		end
		if n2 > 0.25 then
			return Enum.Material.Sandstone
		end
		if n3 > 0.4 then
			return Enum.Material.Pavement
		end
		return Enum.Material.Rock
	elseif frac < LAYER_LOWER_CRUST then
		if n1 > 0.25 then
			return Enum.Material.Rock
		end
		if n2 > 0.25 then
			return Enum.Material.Sandstone
		end
		if n3 > 0.35 then
			return Enum.Material.Limestone
		end
		return Enum.Material.Cobblestone
	else
		if n1 > 0.22 then
			return Enum.Material.Sandstone
		end
		if n2 > 0.25 then
			return Enum.Material.Cobblestone
		end
		if n3 > 0.35 then
			return Enum.Material.Ground
		end
		return Enum.Material.Limestone
	end
end

local function getClimate(noise: NoiseGen, direction: Vector3): (number, number, number)
	local latitude = mathAcos(mathClamp(direction.Y, -1, 1)) / PI
	local baseTemp = 1 - 2 * math.abs(latitude - 0.5)
	local ts = TEMPERATURE_NOISE_SCALE
	local tempN = noise:FBM3D(direction.X * ts, direction.Y * ts, direction.Z * ts, 3, 2.0, 0.5, CH_TEMPERATURE)
	local temperature = mathClamp(baseTemp + tempN * 0.25, 0, 1)

	local ms = MOISTURE_NOISE_SCALE
	local moistN = noise:FBM3D(direction.X * ms, direction.Y * ms, direction.Z * ms, 3, 2.0, 0.5, CH_MOISTURE)
	local moisture = mathClamp(moistN + 0.6, 0, 1)

	local mrs = MOUNTAIN_RIDGE_SCALE
	local ridgeN = noise:FBM3D(direction.X * mrs, direction.Y * mrs, direction.Z * mrs, 3, 2.0, 0.5, CH_MOUNTAIN)
	local ridgeFactor = mathClamp(ridgeN + 0.3, 0, 1)
	ridgeFactor = ridgeFactor * ridgeFactor

	local mts = MOUNTAIN_NOISE_SCALE
	local peakN = noise:FBM3D(direction.X * mts, direction.Y * mts, direction.Z * mts, 5, 2.2, 0.45, CH_DETAIL)
	local peakFactor = mathClamp(peakN + 0.5, 0, 1)

	return temperature, moisture, ridgeFactor * peakFactor
end

local function getContinentValue(noise: NoiseGen, direction: Vector3): number
	local cs = CONTINENT_NOISE_SCALE
	local primary = noise:FBM3D(direction.X * cs, direction.Y * cs, direction.Z * cs, 4, 2.0, 0.45, CH_CONTINENT)
	local secondary =
		noise:FBM3D(direction.X * cs * 2.5, direction.Y * cs * 2.5, direction.Z * cs * 2.5, 3, 2.0, 0.5, CH_CONTINENT2)
	local base = primary * 0.75 + secondary * 0.25 + CONTINENT_LAND_BIAS

	local coastScale = cs * 8
	local coastNoise = noise:FBM3D(
		direction.X * coastScale,
		direction.Y * coastScale,
		direction.Z * coastScale,
		3,
		2.0,
		0.5,
		CH_TERRAIN
	)
	local coastProximity = mathClamp(1 - math.abs(base) / 0.12, 0, 1)
	base = base + coastNoise * 0.07 * coastProximity

	local lakeScale = cs * 3.5
	local lakeNoise = noise:FBM3D(
		direction.X * lakeScale,
		direction.Y * lakeScale,
		direction.Z * lakeScale,
		3,
		2.0,
		0.5,
		CH_OCEAN_FLOOR
	)
	if base > 0.06 and lakeNoise < -0.28 then
		local lakeStrength = mathClamp((-lakeNoise - 0.28) / 0.22, 0, 1)
		base = base - base * lakeStrength * 0.95
	end

	return base
end

local function getSurfaceRadius(
	noise: NoiseGen,
	direction: Vector3,
	heightScale: number,
	mountainness: number,
	continentValue: number
): number
	local maxH = MAX_HEIGHT_VARIATION
	local baseElev
	if continentValue > 0 then
		local lf = math.sqrt(math.min(continentValue * 2, 1))
		baseElev = lf * maxH * 0.15
	else
		local od = math.min(math.abs(continentValue) * 2, 1)
		local depthCurve: number
		if od < 0.15 then
			depthCurve = (od / 0.15) * 0.10
		elseif od < 0.35 then
			local t = (od - 0.15) / 0.2
			t = t * t * (3 - 2 * t)
			depthCurve = 0.10 + t * 0.70
		else
			local t = (od - 0.35) / 0.65
			depthCurve = 0.80 + t * 0.20
		end

		local ofs = TERRAIN_NOISE_SCALE * 1.2
		local oceanFloorNoise =
			noise:FBM3D(direction.X * ofs, direction.Y * ofs, direction.Z * ofs, 3, 2.0, 0.5, CH_OCEAN_FLOOR)
		local trenchScale = mathClamp((od - 0.3) / 0.3, 0, 1)
		local trenchBonus = mathClamp(oceanFloorNoise, -0.95, 0.1) * maxH * 0.4 * trenchScale
		baseElev = -depthCurve * maxH * 1.0 + trenchBonus

		if od > 0.5 then
			local ridgeOceanScale = TERRAIN_NOISE_SCALE * 0.4
			local ridgeN = noise:FBM3D(
				direction.X * ridgeOceanScale,
				direction.Y * ridgeOceanScale,
				direction.Z * ridgeOceanScale,
				3,
				2.0,
				0.5,
				CH_MOUNTAIN
			)
			if ridgeN > 0.15 then
				local ridgeStrength = mathClamp((ridgeN - 0.15) / 0.35, 0, 1)
				baseElev = baseElev + ridgeStrength * ridgeStrength * maxH * 0.3
			end
		end
	end

	local s = TERRAIN_NOISE_SCALE
	local hN = noise:FBM3D(direction.X * s, direction.Y * s, direction.Z * s, 4, 2.0, 0.5, CH_TERRAIN)
	local ds = s * 3
	local dN = noise:FBM3D(direction.X * ds, direction.Y * ds, direction.Z * ds, 2, 2.0, 0.5, CH_DETAIL)

	local isLand = continentValue > 0
	local oceanFlatness = if isLand then 1 else mathClamp(1 - math.abs(continentValue) * 4, 0.02, 1)
	local tAmp = if isLand then maxH * heightScale * 0.3 else maxH * 0.03 * oceanFlatness
	local dAmp = if isLand then maxH * heightScale * 0.1 else maxH * 0.01 * oceanFlatness
	local tOff = hN * tAmp + dN * dAmp

	if isLand and mountainness > 0.1 then
		local valleyScale = TERRAIN_NOISE_SCALE * 0.7
		local valleyN = noise:Sample3D(
			direction.X * valleyScale,
			direction.Y * valleyScale,
			direction.Z * valleyScale,
			CH_OCEAN_FLOOR
		)
		local ridged = 1 - 2 * math.abs(valleyN)
		ridged = math.max(ridged, 0)
		ridged = ridged * ridged
		local valleyInfluence = mathClamp(mountainness / 0.3, 0, 1) * maxH * 0.1
		tOff = tOff + (ridged - 0.25) * valleyInfluence
	end

	local mBonus = 0
	if isLand and mountainness > 0.08 then
		local ms = mathClamp(mountainness / 0.8, 0, 1)
		ms = ms * ms * ms
		mBonus = ms * maxH * 0.85
	end

	return RADIUS + baseElev + tOff + mBonus
end

local function getMaterial(
	nOff: { ChannelOffset },
	depth: number,
	surfR: number,
	dist: number,
	biome: Biome,
	wx: number,
	wy: number,
	wz: number
): Enum.Material
	if dist / RADIUS < LAYER_INNER_CORE_CENTER then
		return Enum.Material.Salt
	end

	local isUnderwater = surfR < SEA_LEVEL
	local altitude = surfR - SEA_LEVEL

	local oVar = nOff[CH_LAYER_VARIETY]
	local nVar = mathNoise(wx * 0.04 + oVar.X, wy * 0.04 + oVar.Y, wz * 0.04 + oVar.Z)

	if depth < SURFACE_DEPTH then
		if isUnderwater then
			local waterDepth = -altitude
			if waterDepth < 30 then
				return Enum.Material.Sand
			elseif waterDepth < 100 then
				return if nVar > 0.0 then Enum.Material.Sand else Enum.Material.Mud
			elseif waterDepth < 250 then
				return if nVar > 0.3 then Enum.Material.Ground else Enum.Material.Mud
			elseif waterDepth < 400 then
				return if nVar > 0.1 then Enum.Material.Mud else Enum.Material.Rock
			else
				return if nVar > 0.2 then Enum.Material.Slate else Enum.Material.Rock
			end
		end
		if altitude > SNOW_LINE_ALTITUDE then
			return if depth < 4 then Enum.Material.Snow else Enum.Material.Ice
		end
		if altitude > TREELINE_ALTITUDE then
			return if nVar > 0.3 then Enum.Material.Ground else Enum.Material.Rock
		end
		if math.abs(dist - SEA_LEVEL) < SHORE_PROXIMITY then
			return biome.ShoreMaterial
		end
		return biome.SurfaceMaterial
	end

	if depth < SUBSURFACE_DEPTH then
		if isUnderwater then
			local waterDepth = -altitude
			if waterDepth < 80 then
				return Enum.Material.Sandstone
			elseif waterDepth < 250 then
				return Enum.Material.Rock
			else
				return Enum.Material.Slate
			end
		end
		if math.abs(dist - SEA_LEVEL) < SHORE_PROXIMITY + 8 then
			return Enum.Material.Sandstone
		end
		return biome.SubsurfaceMaterial
	end

	local layerMat = getLayerMaterial(nOff, dist, wx, wy, wz)
	if layerMat then
		return layerMat
	end
	return biome.DeepMaterial
end

local function surfaceLookup(
	gridSR: { [number]: { [number]: number } },
	gridBiomeTable: { [number]: { [number]: Biome } },
	dx: number,
	dy: number,
	dz: number
): (number, Biome)
	local theta = mathAcos(mathClamp(dy, -1, 1))
	local phi = mathAtan2(dz, dx)
	if phi < 0 then
		phi += TWO_PI
	end

	local latF = theta / PI * GRID_LAT
	local lonF = phi / TWO_PI * GRID_LON

	local lat0 = mathClamp(mathFloor(latF), 0, GRID_LAT - 1)
	local lat1 = lat0 + 1
	local lon0 = mathFloor(lonF) % GRID_LON
	local lon1 = (lon0 + 1) % GRID_LON

	local tLat = latF - lat0
	local tLon = lonF - mathFloor(lonF)
	local oLat = 1 - tLat
	local oLon = 1 - tLon

	local srRow0 = gridSR[lat0]
	local srRow1 = gridSR[lat1]
	local sr = srRow0[lon0] * oLat * oLon
		+ srRow0[lon1] * oLat * tLon
		+ srRow1[lon0] * tLat * oLon
		+ srRow1[lon1] * tLat * tLon

	local nearLat = if tLat < 0.5 then lat0 else lat1
	local nearLon = if tLon < 0.5 then lon0 else lon1

	return sr, gridBiomeTable[nearLat][nearLon]
end

local function surfaceRadiusLookup(
	gridSR: { [number]: { [number]: number } },
	dx: number,
	dy: number,
	dz: number
): number
	local theta = mathAcos(mathClamp(dy, -1, 1))
	local phi = mathAtan2(dz, dx)
	if phi < 0 then
		phi += TWO_PI
	end
	local latF = theta / PI * GRID_LAT
	local lonF = phi / TWO_PI * GRID_LON
	local lat0 = mathClamp(mathFloor(latF), 0, GRID_LAT - 1)
	local lat1 = lat0 + 1
	local lon0 = mathFloor(lonF) % GRID_LON
	local lon1 = (lon0 + 1) % GRID_LON
	local tLat = latF - lat0
	local tLon = lonF - mathFloor(lonF)
	local srRow0 = gridSR[lat0]
	local srRow1 = gridSR[lat1]
	return srRow0[lon0] * (1 - tLat) * (1 - tLon)
		+ srRow0[lon1] * (1 - tLat) * tLon
		+ srRow1[lon0] * tLat * (1 - tLon)
		+ srRow1[lon1] * tLat * tLon
end

--- Planet Generator Class ---
local PlanetGenerator = {}
PlanetGenerator.__index = PlanetGenerator

export type PlanetGenerator = typeof(setmetatable(
	{} :: {
		MasterSeed: number,
		Grid: Infinigrid.Grid<any>, -- Internal Infinigrid instance for all grid/index/position math.
		Radius: number, -- The base radius constant (terrain can extend beyond this).
		SeaLevel: number,
		MaxSurfaceRadius: number, -- Actual maximum distance from center to any terrain surface point. Use this as the true bounding radius.
		MinSurfaceRadius: number, -- Actual minimum distance from center to any terrain surface point (deepest ocean trench).
		_voxelsPerAxis: number,
		_deepStride: number,
		_noise: NoiseGen,
		_nOff: { ChannelOffset },
		_gridSR: { [number]: { [number]: number } },
		_gridBiome: { [number]: { [number]: Biome } },
		_outerBound: number,
		_innerBound: number,
		_sizeYZ: number, -- Cached from Grid.GridSize for hot-path performance.
		_sizeZ: number, -- Cached from Grid.GridSize for hot-path performance.
		Resolution: number,
		_reuseMats: { { { Enum.Material } } },
		_reuseOccs: { { { number } } },
		_generated: { [number]: true },
	},
	PlanetGenerator
))

function PlanetGenerator.new(masterSeed: number, chunkSize: number, quiet: boolean?): PlanetGenerator
	-- Align chunk size to 8 to match Infinigrid's alignment behavior
	local alignedChunkSize = math.ceil(chunkSize / 8) * 8
	local voxelsPerAxis = alignedChunkSize / RESOLUTION
	local deepStride = math.min(DEEP_STRIDE, voxelsPerAxis)

	-- Create noise generator from the master seed (globally coherent across all chunks)
	local noise = NoiseGenerator.new(masterSeed)
	local nOff = noise._offsets

	-- Precompute spherical surface lookup grid (lat/lon → surface radius + biome)
	-- This must happen BEFORE grid bounds so we can size the grid to the actual planet extent.
	local gridSR: { [number]: { [number]: number } } = table.create(GRID_LAT + 1) :: any
	local gridBiomeTable: { [number]: { [number]: Biome } } = table.create(GRID_LAT + 1) :: any
	local globalMinSR = math.huge
	local globalMaxSR = -math.huge

	if not quiet then
		print(`[PlanetGenerator] Precomputing surface grid ({GRID_LAT + 1}x{GRID_LON})...`)
	end
	local gridStart = os.clock()
	for latI = 0, GRID_LAT do
		local theta = PI * latI / GRID_LAT
		local sinTheta = math.sin(theta)
		local cosTheta = math.cos(theta)

		local srRow: { [number]: number } = table.create(GRID_LON) :: any
		local biomeRow: { [number]: Biome } = table.create(GRID_LON) :: any

		for lonI = 0, GRID_LON - 1 do
			local phi = TWO_PI * lonI / GRID_LON
			local dir = Vector3.new(sinTheta * math.cos(phi), cosTheta, sinTheta * math.sin(phi))

			local cv = getContinentValue(noise, dir)
			local temp, moist, mt = getClimate(noise, dir)
			local biome = Biomes.GetBiome(temp, moist, mt)
			local sr = getSurfaceRadius(noise, dir, biome.HeightScale, mt, cv)

			srRow[lonI] = sr
			biomeRow[lonI] = biome

			if sr < globalMinSR then
				globalMinSR = sr
			end
			if sr > globalMaxSR then
				globalMaxSR = sr
			end
		end

		gridSR[latI] = srRow
		gridBiomeTable[latI] = biomeRow

		-- Yield periodically to avoid freezing the main thread during grid precomputation.
		-- Skipped in worker mode (quiet) since workers run in parallel and cannot yield.
		if not quiet and latI % 32 == 0 then
			task.wait()
		end
	end
	if not quiet then
		print(
			`[PlanetGenerator] Surface grid computed in {string.format("%.1f", os.clock() - gridStart)}s`
				.. ` (range: {string.format("%.0f", globalMinSR)} to {string.format("%.0f", globalMaxSR)})`
		)
	end

	local outerBound = math.max(globalMaxSR, SEA_LEVEL) + RESOLUTION * 2
	local innerBound = globalMinSR - SUBSURFACE_DEPTH - RESOLUTION * 2

	-- Grid bounds derived from actual observed surface data so they match Infinigrid exactly.
	-- Infinigrid aligns world size to 8 and ceils grid size, so we replicate that here.
	local maxExtent = math.max(globalMaxSR, SEA_LEVEL)
	local rawWorldSize = math.ceil(maxExtent / 8) * 8 * 2
	local worldSpaceSize = math.ceil(rawWorldSize / 8) * 8

	local center = Vector3.zero
	local gridWorldSize = Vector3.one * worldSpaceSize

	-- Create an Infinigrid instance for all grid/index/position math.
	local grid = Infinigrid.new(center, gridWorldSize, alignedChunkSize)

	-- Cache sizeYZ and sizeZ from the grid for hot-path performance in _ComputeChunkData/PeekChunk.
	local cachedSizeYZ = grid.GridSize.Y * grid.GridSize.Z
	local cachedSizeZ = grid.GridSize.Z

	-- Pre-allocate reusable voxel arrays (safe for sequential single-chunk generation)
	local reuseMats: { { { Enum.Material } } } = table.create(voxelsPerAxis) :: any
	local reuseOccs: { { { number } } } = table.create(voxelsPerAxis) :: any
	for ix = 1, voxelsPerAxis do
		reuseMats[ix] = table.create(voxelsPerAxis) :: any
		reuseOccs[ix] = table.create(voxelsPerAxis) :: any
		for iy = 1, voxelsPerAxis do
			reuseMats[ix][iy] = table.create(voxelsPerAxis) :: any
			reuseOccs[ix][iy] = table.create(voxelsPerAxis) :: any
		end
	end

	local self: PlanetGenerator = setmetatable({
		MasterSeed = masterSeed,
		Grid = grid,
		Radius = RADIUS,
		SeaLevel = SEA_LEVEL,
		MaxSurfaceRadius = maxExtent,
		MinSurfaceRadius = globalMinSR,
		Resolution = RESOLUTION,
		_voxelsPerAxis = voxelsPerAxis,
		_deepStride = deepStride,
		_noise = noise,
		_nOff = nOff,
		_gridSR = gridSR,
		_gridBiome = gridBiomeTable,
		_outerBound = outerBound,
		_innerBound = innerBound,
		_sizeYZ = cachedSizeYZ,
		_sizeZ = cachedSizeZ,
		_reuseMats = reuseMats,
		_reuseOccs = reuseOccs,
		_generated = {},
	}, PlanetGenerator)

	return self
end

function PlanetGenerator.ChunkIndexToGridPosition(self: PlanetGenerator, chunkIndex: number): Vector3
	return self.Grid:ChunkIndexToGridPosition(chunkIndex)
end

function PlanetGenerator.GridPositionToChunkIndex(self: PlanetGenerator, gridPosition: Vector3): number
	return self.Grid:GridPositionToChunkIndex(gridPosition)
end

function PlanetGenerator.GridPositionToWorldPosition(self: PlanetGenerator, gridPosition: Vector3): Vector3
	return self.Grid:GridPositionToWorldPosition(gridPosition)
end

function PlanetGenerator.GetChunkSeed(self: PlanetGenerator, chunkIndex: number): number
	local gridPos = self:ChunkIndexToGridPosition(chunkIndex)
	return tonumber(`{self.MasterSeed}{gridPos.X}{gridPos.Y}{gridPos.Z}`) :: number
end

function PlanetGenerator._ComputeChunkData(
	self: PlanetGenerator,
	chunkIndex: number
): (string, number, boolean, Region3?)
	-- Inline grid position computation (avoids Vector3 creation from ChunkIndexToGridPosition)
	local sizeYZ = self._sizeYZ
	local sizeZ = self._sizeZ
	local remainder = chunkIndex % sizeYZ
	local gx = chunkIndex // sizeYZ
	local gy = remainder // sizeZ
	local gz = remainder % sizeZ

	-- Inline chunk seed (avoids GetChunkSeed re-deriving grid position)
	local chunkSeed = tonumber(`{self.MasterSeed}{gx}{gy}{gz}`) :: number

	-- Min corner in world space (Center is zero so GenerationOrigin - ChunkSize/2 = -GridWorldSize/2)
	local halfWorld = self.Grid.GridWorldSize.X / 2
	local cs = self.Grid.ChunkSize
	local cx = -halfWorld + gx * cs
	local cy = -halfWorld + gy * cs
	local cz = -halfWorld + gz * cs

	local vpa = self._voxelsPerAxis
	local nOff = self._nOff
	local gSR = self._gridSR
	local gBiome = self._gridBiome
	local innerBound = self._innerBound
	local outerBound = self._outerBound

	-- Chunk center distance from planet center (center is origin)
	local cdx = cx + cs * 0.5
	local cdy = cy + cs * 0.5
	local cdz = cz + cs * 0.5
	local cd = mathSqrt(cdx * cdx + cdy * cdy + cdz * cdz)
	local halfDiag = cs * 0.866

	-- Quick rejection: entirely outside the sphere
	if cd - halfDiag > outerBound then
		return "Air", chunkSeed, false, nil
	end

	local region = Region3.new(Vector3.new(cx, cy, cz), Vector3.new(cx + cs, cy + cs, cz + cs))

	-- Deep interior: stride-sampled generation (far below the surface)
	if cd + halfDiag <= innerBound then
		local mats = self._reuseMats
		local occs = self._reuseOccs

		-- Single pass: fill both materials and occupancy together.
		-- The block-fill inner loops visit every (bx,by,bz) so we set occs here
		-- instead of a separate 4096-entry loop.
		local stride = self._deepStride
		local deepMid = (stride - 1) * 0.5
		for sx = 1, vpa, stride do
			local exEnd = math.min(sx + stride - 1, vpa)
			for sy = 1, vpa, stride do
				local eyEnd = math.min(sy + stride - 1, vpa)
				for sz = 1, vpa, stride do
					local ezEnd = math.min(sz + stride - 1, vpa)
					-- Sample at center of the stride block
					local wx = cx + (sx + deepMid - 0.5) * RESOLUTION
					local wy = cy + (sy + deepMid - 0.5) * RESOLUTION
					local wz = cz + (sz + deepMid - 0.5) * RESOLUTION
					local dist = mathSqrt(wx * wx + wy * wy + wz * wz)
					local mat = getLayerMaterial(nOff, dist, wx, wy, wz) or Enum.Material.Rock

					for bx = sx, exEnd do
						local matsX = mats[bx]
						local occsX = occs[bx]
						for by = sy, eyEnd do
							local matsXY = matsX[by]
							local occsXY = occsX[by]
							for bz = sz, ezEnd do
								matsXY[bz] = mat
								occsXY[bz] = 1
							end
						end
					end
				end
			end
		end

		return "Deep", chunkSeed, true, region
	end

	-- Surface shell: full-resolution generation
	local mats = self._reuseMats
	local occs = self._reuseOccs
	local hasContent = false

	-- Pre-compute approximate surface radius at chunk center for fast per-voxel air rejection
	local quickAirThreshold
	if cd > 0.001 then
		local invCd = 1 / cd
		local approxSR = surfaceRadiusLookup(gSR, cdx * invCd, cdy * invCd, cdz * invCd)
		quickAirThreshold = math.max(approxSR, SEA_LEVEL) + cs
	else
		quickAirThreshold = outerBound
	end

	-- Hoist wx/wy computation and precompute partial squared sums.
	-- wx depends only on ix (outer), wy only on iy (middle) — no need to recompute in innermost loop.
	local invRes = INV_RESOLUTION
	for ix = 1, vpa do
		local wx = cx + (ix - 0.5) * RESOLUTION
		local wx2 = wx * wx
		for iy = 1, vpa do
			local wy = cy + (iy - 0.5) * RESOLUTION
			local wx2wy2 = wx2 + wy * wy
			for iz = 1, vpa do
				local wz = cz + (iz - 0.5) * RESOLUTION
				local dist = mathSqrt(wx2wy2 + wz * wz)

				-- Fast path: definitely deep underground
				if dist < innerBound then
					mats[ix][iy][iz] = getLayerMaterial(nOff, dist, wx, wy, wz) or Enum.Material.Rock
					occs[ix][iy][iz] = 1
					hasContent = true
					continue
				end

				-- Fast path: clearly above the surface
				if dist > quickAirThreshold then
					mats[ix][iy][iz] = Enum.Material.Air
					occs[ix][iy][iz] = 0
					continue
				end

				-- Edge case: at the exact center
				if dist < 0.001 then
					mats[ix][iy][iz] = Enum.Material.Salt
					occs[ix][iy][iz] = 1
					hasContent = true
					continue
				end

				local invDist = 1 / dist
				local sr, biome = surfaceLookup(gSR, gBiome, wx * invDist, wy * invDist, wz * invDist)

				if dist <= sr then
					local depth = sr - dist
					occs[ix][iy][iz] = mathClamp(0.5 + depth * invRes, 0, 1)
					mats[ix][iy][iz] = getMaterial(nOff, depth, sr, dist, biome, wx, wy, wz)
					hasContent = true
				elseif dist <= SEA_LEVEL then
					local wd = SEA_LEVEL - dist
					occs[ix][iy][iz] = mathClamp(0.5 + wd * invRes, 0, 1)
					mats[ix][iy][iz] = Enum.Material.Water
					hasContent = true
				else
					mats[ix][iy][iz] = Enum.Material.Air
					occs[ix][iy][iz] = 0
				end
			end
		end
	end

	if not hasContent then
		return "Air", chunkSeed, false, nil
	end
	return "Surface", chunkSeed, true, region
end

function PlanetGenerator.PeekChunk(self: PlanetGenerator, chunkIndex: number): PeekChunkResult
	-- Inline grid position from chunk index
	local sizeYZ = self._sizeYZ
	local sizeZ = self._sizeZ
	local remainder = chunkIndex % sizeYZ
	local gx = chunkIndex // sizeYZ
	local gy = remainder // sizeZ
	local gz = remainder % sizeZ

	local chunkSeed = tonumber(`{self.MasterSeed}{gx}{gy}{gz}`) :: number

	-- Chunk AABB in world space (center is origin)
	local halfWorld = self.Grid.GridWorldSize.X / 2
	local cs = self.Grid.ChunkSize
	local x0 = -halfWorld + gx * cs
	local y0 = -halfWorld + gy * cs
	local z0 = -halfWorld + gz * cs
	local x1 = x0 + cs
	local y1 = y0 + cs
	local z1 = z0 + cs

	-- Min distance from origin to AABB (clamp origin into box)
	local clX = mathClamp(0, x0, x1)
	local clY = mathClamp(0, y0, y1)
	local clZ = mathClamp(0, z0, z1)
	local minDist = mathSqrt(clX * clX + clY * clY + clZ * clZ)

	-- Max distance from origin to AABB (farthest corner)
	local fX = if math.abs(x0) > math.abs(x1) then x0 else x1
	local fY = if math.abs(y0) > math.abs(y1) then y0 else y1
	local fZ = if math.abs(z0) > math.abs(z1) then z0 else z1
	local maxDist = mathSqrt(fX * fX + fY * fY + fZ * fZ)

	local generated = self._generated[chunkIndex] == true

	-- Fast path: entirely outside the outer bound -> Air
	if minDist > self._outerBound then
		return { ChunkType = "Air", IsWater = false, Generated = generated, ChunkSeed = chunkSeed }
	end

	-- Fast path: entirely inside the inner bound -> Buried
	if maxDist <= self._innerBound then
		return { ChunkType = "Buried", IsWater = false, Generated = generated, ChunkSeed = chunkSeed }
	end

	-- Sample surface radius at chunk center + 8 corners (9 lookups, zero allocation)
	local gridSR = self._gridSR
	local minSR = math.huge
	local maxSR = -math.huge
	local half = cs * 0.5
	local d, invD, sr

	-- Center
	local mx, my, mz = x0 + half, y0 + half, z0 + half
	d = mathSqrt(mx * mx + my * my + mz * mz)
	if d > 0.001 then
		invD = 1 / d
		sr = surfaceRadiusLookup(gridSR, mx * invD, my * invD, mz * invD)
		minSR = sr
		maxSR = sr
	end

	-- Corner (x0, y0, z0)
	d = mathSqrt(x0 * x0 + y0 * y0 + z0 * z0)
	if d > 0.001 then
		invD = 1 / d
		sr = surfaceRadiusLookup(gridSR, x0 * invD, y0 * invD, z0 * invD)
		if sr < minSR then
			minSR = sr
		end
		if sr > maxSR then
			maxSR = sr
		end
	end

	-- Corner (x1, y0, z0)
	d = mathSqrt(x1 * x1 + y0 * y0 + z0 * z0)
	if d > 0.001 then
		invD = 1 / d
		sr = surfaceRadiusLookup(gridSR, x1 * invD, y0 * invD, z0 * invD)
		if sr < minSR then
			minSR = sr
		end
		if sr > maxSR then
			maxSR = sr
		end
	end

	-- Corner (x0, y1, z0)
	d = mathSqrt(x0 * x0 + y1 * y1 + z0 * z0)
	if d > 0.001 then
		invD = 1 / d
		sr = surfaceRadiusLookup(gridSR, x0 * invD, y1 * invD, z0 * invD)
		if sr < minSR then
			minSR = sr
		end
		if sr > maxSR then
			maxSR = sr
		end
	end

	-- Corner (x0, y0, z1)
	d = mathSqrt(x0 * x0 + y0 * y0 + z1 * z1)
	if d > 0.001 then
		invD = 1 / d
		sr = surfaceRadiusLookup(gridSR, x0 * invD, y0 * invD, z1 * invD)
		if sr < minSR then
			minSR = sr
		end
		if sr > maxSR then
			maxSR = sr
		end
	end

	-- Corner (x1, y1, z0)
	d = mathSqrt(x1 * x1 + y1 * y1 + z0 * z0)
	if d > 0.001 then
		invD = 1 / d
		sr = surfaceRadiusLookup(gridSR, x1 * invD, y1 * invD, z0 * invD)
		if sr < minSR then
			minSR = sr
		end
		if sr > maxSR then
			maxSR = sr
		end
	end

	-- Corner (x1, y0, z1)
	d = mathSqrt(x1 * x1 + y0 * y0 + z1 * z1)
	if d > 0.001 then
		invD = 1 / d
		sr = surfaceRadiusLookup(gridSR, x1 * invD, y0 * invD, z1 * invD)
		if sr < minSR then
			minSR = sr
		end
		if sr > maxSR then
			maxSR = sr
		end
	end

	-- Corner (x0, y1, z1)
	d = mathSqrt(x0 * x0 + y1 * y1 + z1 * z1)
	if d > 0.001 then
		invD = 1 / d
		sr = surfaceRadiusLookup(gridSR, x0 * invD, y1 * invD, z1 * invD)
		if sr < minSR then
			minSR = sr
		end
		if sr > maxSR then
			maxSR = sr
		end
	end

	-- Corner (x1, y1, z1)
	d = mathSqrt(x1 * x1 + y1 * y1 + z1 * z1)
	if d > 0.001 then
		invD = 1 / d
		sr = surfaceRadiusLookup(gridSR, x1 * invD, y1 * invD, z1 * invD)
		if sr < minSR then
			minSR = sr
		end
		if sr > maxSR then
			maxSR = sr
		end
	end

	-- Effective visible boundary: terrain or sea level, whichever is higher
	local effectiveMax = math.max(maxSR, SEA_LEVEL)

	-- Air: entire chunk is above the visible surface
	if minDist > effectiveMax then
		return { ChunkType = "Air", IsWater = false, Generated = generated, ChunkSeed = chunkSeed }
	end

	-- Buried: entire chunk is below the terrain surface.
	-- Exception: if terrain is below sea level in any sampled direction (water column),
	-- and the chunk overlaps that water region, force it to Surface so water renders.
	if maxDist < minSR then
		if minSR < SEA_LEVEL and maxDist > minSR - SUBSURFACE_DEPTH then
			-- Chunk is under ocean floor but close enough that water may be adjacent;
			-- still buried (water is above terrain, not below). True buried.
			do
			end
		end
		return { ChunkType = "Buried", IsWater = false, Generated = generated, ChunkSeed = chunkSeed }
	end

	-- Determine if this chunk contains water: terrain is below sea level somewhere
	-- in the chunk's angular footprint AND the chunk's radial range reaches the water column.
	local isWater = minSR < SEA_LEVEL and minDist <= SEA_LEVEL

	-- Water check: if terrain is below sea level and the chunk sits between terrain and
	-- sea level (entirely within the water column), force Surface so water is rendered.
	-- This catches chunks that are fully submerged but contain no solid terrain.
	if minDist > maxSR and minDist <= SEA_LEVEL and maxSR < SEA_LEVEL then
		return {
			ChunkType = "Surface",
			IsWater = true,
			MinHeight = minSR - SEA_LEVEL,
			MaxHeight = maxSR - SEA_LEVEL,
			Generated = generated,
			ChunkSeed = chunkSeed,
		}
	end

	-- Surface: chunk intersects the visible surface shell
	return {
		ChunkType = "Surface",
		IsWater = isWater,
		MinHeight = minSR - SEA_LEVEL,
		MaxHeight = maxSR - SEA_LEVEL,
		Generated = generated,
		ChunkSeed = chunkSeed,
	}
end

function PlanetGenerator.GenerateChunk(self: PlanetGenerator, chunkIndex: number): GenerateChunkResult
	local chunkType, chunkSeed, hasContent, region = self:_ComputeChunkData(chunkIndex)
	local isWater = false
	if hasContent then
		-- Scan for water voxels before writing
		local mats = self._reuseMats
		local vpa = self._voxelsPerAxis
		for ix = 1, vpa do
			for iy = 1, vpa do
				for iz = 1, vpa do
					if mats[ix][iy][iz] == Enum.Material.Water then
						isWater = true
						break
					end
				end
				if isWater then
					break
				end
			end
			if isWater then
				break
			end
		end
		workspace.Terrain:WriteVoxels(region :: Region3, RESOLUTION, self._reuseMats, self._reuseOccs)
	end
	self._generated[chunkIndex] = true
	return { ChunkType = chunkType, IsWater = isWater, ChunkSeed = chunkSeed }
end

return table.freeze(PlanetGenerator)
