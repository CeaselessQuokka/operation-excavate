--[[
	Sphere terrain generator for Studio.
	Clone-require this module from the command bar to generate a test world:

		local m = game.ReplicatedStorage.Shared.Common.Classes.SphereGenerator.GenerateTestWorld:Clone()
		m.Parent = workspace
		require(m)
		m:Destroy()

	Requires NoiseGenerator and Biomes as sibling ModuleScripts.
	Uses clone-require internally so edits to those modules take effect immediately.
]]

---------- CONFIG ----------
local SHOULD_GENERATE = false
if not SHOULD_GENERATE then
	return true
end

local SEED = os.time()
local RADIUS = 2048
local SEA_LEVEL_OFFSET = 0
local MAX_HEIGHT_VARIATION = 512
local CHUNK_SIZE = 32
local TERRAIN_NOISE_SCALE = 6
local TEMPERATURE_NOISE_SCALE = 2.5
local MOISTURE_NOISE_SCALE = 3
local MOUNTAIN_NOISE_SCALE = 1.8
local MOUNTAIN_RIDGE_SCALE = 0.8 -- low-freq regional mountain placement
local CONTINENT_NOISE_SCALE = 1.2
local CONTINENT_LAND_BIAS = 0.02 -- lower = more ocean, vaster seas
local CENTER = Vector3.zero

-- Snow spawns on mountains above this altitude (studs above sea level)
-- At 512 MAX_HEIGHT_VARIATION, snow line at ~300 studs above sea level
local SNOW_LINE_ALTITUDE = 300
-- Treeline: above this, only rock/snow (no grass on high peaks)
local TREELINE_ALTITUDE = 220

---------- CONSTANTS ----------
local RESOLUTION = 4
local DEEP_STRIDE = 4 -- Sample every 4th voxel in deep interior (64× fewer noise evaluations per chunk)
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

---------- EARTH LAYER BOUNDARIES (fraction of RADIUS from center) ----------
--  Inner Core Center : 0.00 – 0.02  →  Salt         (RESERVED special ore — not used anywhere else)
--  Inner Core        : 0.02 – 0.16  →  CrackedLava  (molten iron)
--  Outer Core        : 0.16 – 0.35  →  Basalt       (dense iron / nickel)
--  Lower Mantle      : 0.35 – 0.55  →  Concrete     (heavily compressed rock)
--  Mid Mantle        : 0.55 – 0.70  →  Slate        (transitional rock)
--  Upper Mantle      : 0.70 – 0.82  →  Rock         (cooler dense rock)
--  Lower Crust       : 0.82 – 0.90  →  Cobblestone  (broken / mixed rock)
--  Upper Crust       : 0.90 – 0.95  →  Limestone    (sedimentary)
--  Surface           : 0.95+        →  Biome materials
local LAYER_INNER_CORE_CENTER = 0.02
local LAYER_INNER_CORE = 0.16
local LAYER_OUTER_CORE = 0.35
local LAYER_LOWER_MANTLE = 0.55
local LAYER_MID_MANTLE = 0.70
local LAYER_UPPER_MANTLE = 0.82
local LAYER_LOWER_CRUST = 0.90
local LAYER_UPPER_CRUST = 0.95

---------- FRESH REQUIRE (avoids Roblox module cache) ----------
local generatorFolder = game:GetService("ReplicatedStorage")
	:WaitForChild("Shared")
	:WaitForChild("Common")
	:WaitForChild("Classes")
	:WaitForChild("SphereGenerator")

local function freshRequire(name)
	local source = generatorFolder:FindFirstChild(name)
	assert(source, `[SphereGen] Module "{name}" not found in SphereGenerator folder`)
	return require(source:Clone())
end

local NoiseGenerator = freshRequire("NoiseGenerator")
local Biomes = freshRequire("Biomes")

---------- GENERATION ----------
local terrain = workspace.Terrain
local noise = NoiseGenerator.new(SEED)
local seaLevel = RADIUS + SEA_LEVEL_OFFSET
local chunkStuds = CHUNK_SIZE * RESOLUTION

-- Cached math functions and constants for inner-loop performance
local mathClamp = math.clamp
local mathFloor = math.floor
local mathSqrt = math.sqrt
local mathAcos = math.acos
local mathAtan2 = math.atan2
local mathNoise = math.noise
local CENTER_X, CENTER_Y, CENTER_Z = CENTER.X, CENTER.Y, CENTER.Z

-- Pre-extract noise channel offsets for inline calls (avoids method dispatch overhead)
local _nOff = noise._offsets

---------- EARTH LAYERS (with material variety via 3D noise) ----------
local function getLayerMaterial(dist, wx, wy, wz)
	local frac = dist / RADIUS
	if frac >= LAYER_UPPER_CRUST then
		return nil -- Above upper crust → biome materials handle it
	end

	if frac < LAYER_INNER_CORE_CENTER then
		return Enum.Material.Salt -- RESERVED special ore
	end

	-- Three noise values at different scales for patches, veins, and rare accents
	-- Inline math.noise with pre-extracted offsets (avoids method dispatch in hot loop)
	local nScale = 0.015
	local o1 = _nOff[CH_LAYER_VARIETY]
	local n1 = mathNoise(wx * nScale + o1.X, wy * nScale + o1.Y, wz * nScale + o1.Z)
	local n2Scale = nScale * 3.5
	local o2 = _nOff[CH_LAYER_VARIETY2]
	local n2 = mathNoise(wx * n2Scale + o2.X, wy * n2Scale + o2.Y, wz * n2Scale + o2.Z)
	local n3Scale = nScale * 7
	local o3 = _nOff[CH_TERRAIN]
	local n3 = mathNoise(wx * n3Scale + o3.X, wy * n3Scale + o3.Y, wz * n3Scale + o3.Z)

	if frac < LAYER_INNER_CORE then
		-- Inner Core: molten iron — CrackedLava with Basalt intrusions and rare Asphalt (carbon)
		if n3 > 0.35 then
			return Enum.Material.Asphalt
		end
		if n1 > 0.25 then
			return Enum.Material.Basalt
		end
		return Enum.Material.CrackedLava
	elseif frac < LAYER_OUTER_CORE then
		-- Outer Core: dense iron/nickel — Basalt with CrackedLava veins
		if n1 > 0.3 then
			return Enum.Material.CrackedLava
		end
		if n2 > 0.28 and frac > LAYER_OUTER_CORE - 0.03 then
			return Enum.Material.Concrete
		end
		return Enum.Material.Basalt
	elseif frac < LAYER_LOWER_MANTLE then
		-- Lower Mantle: compressed rock — Concrete with Basalt patches and Asphalt veins
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
		-- Mid Mantle: transitional — Slate with Concrete patches and Rock intrusions
		if n1 > 0.28 then
			return Enum.Material.Concrete
		end
		if n2 > 0.25 then
			return Enum.Material.Rock
		end
		return Enum.Material.Slate
	elseif frac < LAYER_UPPER_MANTLE then
		-- Upper Mantle: cooler dense rock — Rock with Slate veins and Sandstone patches
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
		-- Lower Crust: broken mixed rock — Cobblestone with Rock and sedimentary patches
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
	else -- LAYER_LOWER_CRUST .. LAYER_UPPER_CRUST
		-- Upper Crust: sedimentary — Limestone with Sandstone layers and gravel pockets
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

local function getClimate(direction)
	local latitude = math.acos(math.clamp(direction.Y, -1, 1)) / math.pi
	local baseTemp = 1 - 2 * math.abs(latitude - 0.5)
	local ts = TEMPERATURE_NOISE_SCALE
	local tempN = noise:FBM3D(direction.X * ts, direction.Y * ts, direction.Z * ts, 3, 2.0, 0.5, CH_TEMPERATURE)
	local temperature = math.clamp(baseTemp + tempN * 0.25, 0, 1)

	local ms = MOISTURE_NOISE_SCALE
	local moistN = noise:FBM3D(direction.X * ms, direction.Y * ms, direction.Z * ms, 3, 2.0, 0.5, CH_MOISTURE)
	local moisture = math.clamp(moistN + 0.6, 0, 1)

	-- Mountain ranges: regional low-freq noise decides WHERE ranges exist (like tectonic plates)
	-- Then higher-freq noise adds individual peaks within those ranges
	local mrs = MOUNTAIN_RIDGE_SCALE
	local ridgeN = noise:FBM3D(direction.X * mrs, direction.Y * mrs, direction.Z * mrs, 3, 2.0, 0.5, CH_MOUNTAIN)
	-- Ridge noise creates broad mountainous regions — like the Rockies or Himalayas belt
	local ridgeFactor = math.clamp(ridgeN + 0.3, 0, 1) -- biased so ~35% of land can be mountainous
	ridgeFactor = ridgeFactor * ridgeFactor -- square to concentrate ranges

	-- Local peak noise adds variation within ranges
	local mts = MOUNTAIN_NOISE_SCALE
	local peakN = noise:FBM3D(direction.X * mts, direction.Y * mts, direction.Z * mts, 5, 2.2, 0.45, CH_DETAIL)
	local peakFactor = math.clamp(peakN + 0.5, 0, 1)

	-- Combine: mountains only form where both the regional ridge AND local peaks align
	local mountainness = ridgeFactor * peakFactor

	return temperature, moisture, mountainness
end

local function getContinentValue(direction)
	local cs = CONTINENT_NOISE_SCALE
	local primary = noise:FBM3D(direction.X * cs, direction.Y * cs, direction.Z * cs, 4, 2.0, 0.45, CH_CONTINENT)
	local secondary =
		noise:FBM3D(direction.X * cs * 2.5, direction.Y * cs * 2.5, direction.Z * cs * 2.5, 3, 2.0, 0.5, CH_CONTINENT2)
	local base = primary * 0.75 + secondary * 0.25 + CONTINENT_LAND_BIAS

	-- Coastal detail: carves fjords, inlets, channels, and creates island chains
	-- Uses CH_TERRAIN at continent-scale (uncorrelated with its terrain-height usage)
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
	-- Strongest near coastlines (|base| small), fades deep inland and out to sea
	local coastProximity = math.clamp(1 - math.abs(base) / 0.12, 0, 1)
	base = base + coastNoise * 0.07 * coastProximity

	-- Inland lakes and seas: rare depressions that push land below sea level
	-- Uses CH_OCEAN_FLOOR at low frequency for large lake basins
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
		local lakeStrength = math.clamp((-lakeNoise - 0.28) / 0.22, 0, 1)
		base = base - base * lakeStrength * 0.95
	end

	return base
end

local function getSurfaceRadius(direction, heightScale, mountainness, continentValue)
	local maxH = MAX_HEIGHT_VARIATION
	local baseElev
	if continentValue > 0 then
		-- Land: sqrt curve for plateau-like flat buildable areas
		local lf = math.sqrt(math.min(continentValue * 2, 1))
		baseElev = lf * maxH * 0.15 -- modest base elevation, mountains add the real height
	else
		-- Ocean floor modeled after real Earth bathymetry:
		--   Continental shelf (od < 0.15): shallow, gentle slope — coastal waters
		--   Continental slope (0.15..0.35): steep drop-off
		--   Abyssal plain   (od > 0.35): deep and very flat — ideal for underwater building
		--   Trenches        (rare):       even deeper cuts
		local od = math.min(math.abs(continentValue) * 2, 1)

		local depthCurve: number
		if od < 0.15 then
			-- Shelf: gentle slope, 0 → 0.10 of maxH
			depthCurve = (od / 0.15) * 0.10
		elseif od < 0.35 then
			-- Slope: steep transition 0.10 → 0.80 of maxH
			local t = (od - 0.15) / 0.2
			t = t * t * (3 - 2 * t) -- smooth-step
			depthCurve = 0.10 + t * 0.70
		else
			-- Abyssal plain: deep, mostly flat 0.80 → 1.0 (barely varies)
			local t = (od - 0.35) / 0.65
			depthCurve = 0.80 + t * 0.20
		end

		-- Trench noise — rare but dramatic deep cuts in abyssal zones
		local ofs = TERRAIN_NOISE_SCALE * 1.2
		local oceanFloorNoise =
			noise:FBM3D(direction.X * ofs, direction.Y * ofs, direction.Z * ofs, 3, 2.0, 0.5, CH_OCEAN_FLOOR)
		local trenchScale = math.clamp((od - 0.3) / 0.3, 0, 1)
		-- Trenches can dig an extra 40% of maxH deeper
		local trenchBonus = math.clamp(oceanFloorNoise, -0.95, 0.1) * maxH * 0.4 * trenchScale

		-- Ocean floor reaches up to 1.0× maxH below RADIUS at the deepest abyssal plains
		-- Plus trenches can push that even further
		baseElev = -depthCurve * maxH * 1.0 + trenchBonus

		-- Mid-ocean ridges: underwater mountain ranges in deep ocean
		-- Reuses CH_MOUNTAIN at ocean-floor scale (uncorrelated with surface mountain usage)
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
				local ridgeStrength = math.clamp((ridgeN - 0.15) / 0.35, 0, 1)
				local midOceanRidge = ridgeStrength * ridgeStrength * maxH * 0.3
				baseElev = baseElev + midOceanRidge
			end
		end
	end

	local s = TERRAIN_NOISE_SCALE
	local hN = noise:FBM3D(direction.X * s, direction.Y * s, direction.Z * s, 4, 2.0, 0.5, CH_TERRAIN)
	local ds = s * 3
	local dN = noise:FBM3D(direction.X * ds, direction.Y * ds, direction.Z * ds, 2, 2.0, 0.5, CH_DETAIL)

	local isLand = continentValue > 0
	-- Ocean floor noise is heavily suppressed to keep abyssal plains flat and buildable
	local oceanFlatness = if isLand then 1 else math.clamp(1 - math.abs(continentValue) * 4, 0.02, 1)
	local tAmp = if isLand then maxH * heightScale * 0.3 else maxH * 0.03 * oceanFlatness
	local dAmp = if isLand then maxH * heightScale * 0.1 else maxH * 0.01 * oceanFlatness
	local tOff = hN * tAmp + dN * dAmp

	-- Mountain ridge/valley formation: ridged noise creates sharp ridges with V-shaped valleys
	-- Only in mountainous land regions — creates Rockies/Himalayas style terrain
	if isLand and mountainness > 0.1 then
		local valleyScale = TERRAIN_NOISE_SCALE * 0.7
		local valleyN = noise:Sample3D(
			direction.X * valleyScale,
			direction.Y * valleyScale,
			direction.Z * valleyScale,
			CH_OCEAN_FLOOR -- reuse at completely different scale
		)
		-- Ridged noise: abs creates V-shaped valleys, squaring sharpens them
		local ridged = 1 - 2 * math.abs(valleyN)
		ridged = math.max(ridged, 0)
		ridged = ridged * ridged
		local valleyInfluence = math.clamp(mountainness / 0.3, 0, 1) * maxH * 0.1
		tOff = tOff + (ridged - 0.25) * valleyInfluence
	end

	-- Mountain uplift: creates actual tall mountains in mountainous regions
	-- mountainness is already region-gated (ridge × peak), so this creates proper ranges
	local mBonus = 0
	if isLand and mountainness > 0.08 then
		-- Lower threshold (0.08) means mountains start forming sooner within ranges
		-- But the ridge gating means this only happens in mountainous regions
		local ms = math.clamp(mountainness / 0.8, 0, 1)
		-- Cubic curve: foothills → mid peaks → towering summits
		ms = ms * ms * ms
		mBonus = ms * maxH * 0.85
	end

	return RADIUS + baseElev + tOff + mBonus
end

local function getMaterial(depth, surfR, dist, biome, wx, wy, wz)
	-- Reserve: absolute core center (special ore)
	if dist / RADIUS < LAYER_INNER_CORE_CENTER then
		return Enum.Material.Salt
	end

	local isUnderwater = surfR < seaLevel
	local altitude = surfR - seaLevel -- positive = above sea level, negative = below

	-- Small-scale noise for material variation on surfaces (inline for speed)
	local oVar = _nOff[CH_LAYER_VARIETY]
	local nVar = mathNoise(wx * 0.04 + oVar.X, wy * 0.04 + oVar.Y, wz * 0.04 + oVar.Z)

	-- ===== SURFACE LAYER (terrain surface appearance) =====
	if depth < SURFACE_DEPTH then
		if isUnderwater then
			-- Ocean floor surface: varies by water depth — visual progression for divers
			local waterDepth = -altitude
			if waterDepth < 30 then
				-- Littoral zone: sandy shallows
				return Enum.Material.Sand
			elseif waterDepth < 100 then
				-- Sublittoral: sand and mud patches
				return if nVar > 0.0 then Enum.Material.Sand else Enum.Material.Mud
			elseif waterDepth < 250 then
				-- Bathyal zone: mud dominant
				return if nVar > 0.3 then Enum.Material.Ground else Enum.Material.Mud
			elseif waterDepth < 400 then
				-- Abyssal zone: mud and rock
				return if nVar > 0.1 then Enum.Material.Mud else Enum.Material.Rock
			else
				-- Hadal zone (trenches): bare rock and slate
				return if nVar > 0.2 then Enum.Material.Slate else Enum.Material.Rock
			end
		end

		-- Land surface
		if altitude > SNOW_LINE_ALTITUDE then
			return if depth < 4 then Enum.Material.Snow else Enum.Material.Ice
		end
		if altitude > TREELINE_ALTITUDE then
			-- Alpine zone: exposed rock with some gravel patches
			return if nVar > 0.3 then Enum.Material.Ground else Enum.Material.Rock
		end
		if math.abs(dist - seaLevel) < SHORE_PROXIMITY then
			return biome.ShoreMaterial
		end
		return biome.SurfaceMaterial
	end

	-- ===== SUBSURFACE LAYER (weathered zone) =====
	if depth < SUBSURFACE_DEPTH then
		if isUnderwater then
			-- Underwater subsurface varies by depth
			local waterDepth = -altitude
			if waterDepth < 80 then
				return Enum.Material.Sandstone
			elseif waterDepth < 250 then
				return Enum.Material.Rock
			else
				return Enum.Material.Slate
			end
		end
		-- Near-shore subsurface
		if math.abs(dist - seaLevel) < SHORE_PROXIMITY + 8 then
			return Enum.Material.Sandstone
		end
		return biome.SubsurfaceMaterial
	end

	-- ===== DEEP INTERIOR (geological layers) =====
	local layerMat = getLayerMaterial(dist, wx, wy, wz)
	if layerMat then
		return layerMat
	end
	return biome.DeepMaterial
end

---------- SPHERICAL LOOKUP TABLE ----------
-- Pre-compute surface radius and biome on a lat/lon grid, then look up per-voxel
-- via bilinear interpolation. Replaces ~37 noise evaluations per voxel with a
-- cheap table lookup, giving a massive speedup with sub-voxel accuracy.
-- Grid is ~4-6× finer than voxel angular resolution, so interpolation error is invisible.
local GRID_LAT = 256
local GRID_LON = 512
local PI = math.pi
local TWO_PI = 2 * math.pi

local gridSR = table.create(GRID_LAT + 1)
local gridBiome = table.create(GRID_LAT + 1)
local globalMinSR = math.huge
local globalMaxSR = -math.huge

print(`[SphereGen] Pre-computing surface grid ({GRID_LAT + 1}x{GRID_LON})...`)
local gridStart = os.clock()
for latI = 0, GRID_LAT do
	local theta = PI * latI / GRID_LAT
	local sinTheta = math.sin(theta)
	local cosTheta = math.cos(theta)

	local srRow = table.create(GRID_LON)
	local biomeRow = table.create(GRID_LON)

	for lonI = 0, GRID_LON - 1 do
		local phi = TWO_PI * lonI / GRID_LON
		local dir = Vector3.new(sinTheta * math.cos(phi), cosTheta, sinTheta * math.sin(phi))

		local cv = getContinentValue(dir)
		local temp, moist, mt = getClimate(dir)
		local biome = Biomes.GetBiome(temp, moist, mt)
		local sr = getSurfaceRadius(dir, biome.HeightScale, mt, cv)

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
	gridBiome[latI] = biomeRow

	if latI % 32 == 0 then
		task.wait()
	end
end

print(
	`[SphereGen] Grid done in {string.format("%.1f", os.clock() - gridStart)}s, surface range: {string.format(
		"%.0f",
		globalMinSR
	)} to {string.format("%.0f", globalMaxSR)}`
)

-- Tight bounds from actual precomputed surface data (much smaller than theoretical max)
local outerBound = math.max(globalMaxSR, seaLevel) + RESOLUTION * 2
local innerBound = globalMinSR - SUBSURFACE_DEPTH - RESOLUTION * 2

local function lookupSurface(dx: number, dy: number, dz: number)
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

	-- Bilinear interpolation for surface radius (smooth continuous function)
	local srRow0 = gridSR[lat0]
	local srRow1 = gridSR[lat1]
	local sr = srRow0[lon0] * oLat * oLon
		+ srRow0[lon1] * oLat * tLon
		+ srRow1[lon0] * tLat * oLon
		+ srRow1[lon1] * tLat * tLon

	-- Nearest neighbor for biome (discrete classification)
	local nearLat = if tLat < 0.5 then lat0 else lat1
	local nearLon = if tLon < 0.5 then lon0 else lon1

	return sr, gridBiome[nearLat][nearLon]
end

---------- SURFACE RADIUS LOOKUP (no biome, for chunk classification) ----------
local function lookupSurfaceRadius(dx: number, dy: number, dz: number): number
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

---------- BUILD CHUNK LISTS ----------
-- Two-pass multi-resolution generation:
--   Pass 1: Deep interior at DEEP_RESOLUTION (16-stud voxels) — ~60× fewer chunks
--   Pass 2: Surface shell at RESOLUTION (4-stud voxels) — full detail where it matters
-- Combined with air-chunk detection and reusable arrays for additional speedup.
local function alignDown(v, cs)
	return math.floor(v / cs) * cs
end
local function alignUp(v, cs)
	return math.ceil(v / cs) * cs
end

-- Deep interior chunks (stride-sampled, invisible until digging)
local deepChunks = {}
do
	local cs = chunkStuds
	local halfDiag = cs * 0.866
	local bound = innerBound
	local sX = alignDown(CENTER_X - bound, cs)
	local sY = alignDown(CENTER_Y - bound, cs)
	local sZ = alignDown(CENTER_Z - bound, cs)
	local eX = alignUp(CENTER_X + bound, cs)
	local eY = alignUp(CENTER_Y + bound, cs)
	local eZ = alignUp(CENTER_Z + bound, cs)
	for cx = sX, eX - 1, cs do
		for cy = sY, eY - 1, cs do
			for cz = sZ, eZ - 1, cs do
				local cdx = cx + cs * 0.5 - CENTER_X
				local cdy = cy + cs * 0.5 - CENTER_Y
				local cdz = cz + cs * 0.5 - CENTER_Z
				local cd = mathSqrt(cdx * cdx + cdy * cdy + cdz * cdz)
				if cd + halfDiag <= bound then
					table.insert(deepChunks, { cx, cy, cz })
				end
			end
		end
	end
end

-- Surface shell chunks (full resolution, visible terrain)
-- Includes a small overlap with deep zone to ensure seamless transition at RESOLUTION=4
local surfaceChunks = {}
local skippedAir = 0
do
	local cs = chunkStuds
	local halfDiag = cs * 0.866
	-- Overlap: extend one chunk past innerBound into deep territory
	-- Those voxels use getLayerMaterial fast path, overwriting coarse deep data with fine
	local shellInner = innerBound - cs
	local sX = alignDown(CENTER_X - outerBound, cs)
	local sY = alignDown(CENTER_Y - outerBound, cs)
	local sZ = alignDown(CENTER_Z - outerBound, cs)
	local eX = alignUp(CENTER_X + outerBound, cs)
	local eY = alignUp(CENTER_Y + outerBound, cs)
	local eZ = alignUp(CENTER_Z + outerBound, cs)
	for cx = sX, eX - 1, cs do
		for cy = sY, eY - 1, cs do
			for cz = sZ, eZ - 1, cs do
				local cdx = cx + cs * 0.5 - CENTER_X
				local cdy = cy + cs * 0.5 - CENTER_Y
				local cdz = cz + cs * 0.5 - CENTER_Z
				local cd = mathSqrt(cdx * cdx + cdy * cdy + cdz * cdz)
				-- Must intersect the outerBound sphere
				if cd - halfDiag > outerBound then
					continue
				end
				-- Skip if entirely inside the deep zone (already handled by deep pass)
				if cd + halfDiag < shellInner then
					continue
				end
				-- Quick air check: sample surface at chunk center direction to skip air chunks
				-- Avoids iterating 32K voxels for chunks clearly above the terrain
				if cd > 0.001 then
					local invCd = 1 / cd
					local approxSR = lookupSurfaceRadius(cdx * invCd, cdy * invCd, cdz * invCd)
					-- Generous margin accounts for surface variation across the chunk's angular span
					local surfMax = math.max(approxSR, seaLevel) + cs * 2
					if cd - halfDiag > surfMax then
						skippedAir += 1
						continue
					end
				end
				table.insert(surfaceChunks, { cx, cy, cz })
			end
		end
	end
end

---------- PRE-ALLOCATE REUSABLE VOXEL ARRAYS ----------
-- Avoids billions of table allocations across all chunks.
-- WriteVoxels reads synchronously, so we can safely reuse between chunks.
local reuseMats = table.create(CHUNK_SIZE)
local reuseOccs = table.create(CHUNK_SIZE)
for ix = 1, CHUNK_SIZE do
	reuseMats[ix] = table.create(CHUNK_SIZE)
	reuseOccs[ix] = table.create(CHUNK_SIZE)
	for iy = 1, CHUNK_SIZE do
		reuseMats[ix][iy] = table.create(CHUNK_SIZE)
		reuseOccs[ix][iy] = table.create(CHUNK_SIZE)
	end
end

---------- GENERATE ----------
terrain:Clear()
local totalDeep = #deepChunks
local totalSurface = #surfaceChunks
local totalChunks = totalDeep + totalSurface
local startTime = os.clock()
local lastYield = startTime
local chunksDone = 0
local lastPct = 0

print(`[SphereGen] Seed: {SEED}, Radius: {RADIUS}`)
print(
	`[SphereGen] Deep: {totalDeep} chunks (stride {DEEP_STRIDE}), Surface: {totalSurface} chunks, Skipped air: {skippedAir}`
)

local function yieldCheck(phase: string)
	chunksDone += 1
	local now = os.clock()
	if now - lastYield > 0.033 then
		lastYield = now
		local pct = mathFloor(chunksDone / totalChunks * 100)
		if pct >= lastPct + 5 then
			lastPct = pct
			local elapsed = now - startTime
			local rate = chunksDone / elapsed
			local remaining = (totalChunks - chunksDone) / rate
			print(`[SphereGen] {pct}% [{phase}] ETA {string.format("%.0f", remaining)}s`)
		end
		task.wait()
	end
end

---------- PASS 1: DEEP INTERIOR (stride-sampled, resolution=4) ----------
-- Sample noise every DEEP_STRIDE voxels (every 16 studs) and replicate to the
-- surrounding block. This cuts noise evaluations by 64× while keeping resolution=4.
-- Pre-fill occupancy once since all deep voxels are solid.
for ix = 1, CHUNK_SIZE do
	for iy = 1, CHUNK_SIZE do
		for iz = 1, CHUNK_SIZE do
			reuseOccs[ix][iy][iz] = 1
		end
	end
end

local DEEP_MID = (DEEP_STRIDE - 1) * 0.5 -- offset to center of stride block

print(`[SphereGen] Pass 1: Deep interior ({totalDeep} chunks, stride {DEEP_STRIDE})...`)
for _, chunk in deepChunks do
	local cx, cy, cz = chunk[1], chunk[2], chunk[3]
	local mats = reuseMats

	for sx = 1, CHUNK_SIZE, DEEP_STRIDE do
		for sy = 1, CHUNK_SIZE, DEEP_STRIDE do
			for sz = 1, CHUNK_SIZE, DEEP_STRIDE do
				-- Sample at center of the stride block
				local wx = cx + (sx + DEEP_MID - 0.5) * RESOLUTION
				local wy = cy + (sy + DEEP_MID - 0.5) * RESOLUTION
				local wz = cz + (sz + DEEP_MID - 0.5) * RESOLUTION
				local ddx, ddy, ddz = wx - CENTER_X, wy - CENTER_Y, wz - CENTER_Z
				local dist = mathSqrt(ddx * ddx + ddy * ddy + ddz * ddz)
				local mat = getLayerMaterial(dist, wx, wy, wz) or Enum.Material.Rock

				-- Fill the DEEP_STRIDE³ block with the sampled material
				local exEnd = sx + DEEP_STRIDE - 1
				local eyEnd = sy + DEEP_STRIDE - 1
				local ezEnd = sz + DEEP_STRIDE - 1
				for bx = sx, exEnd do
					local matsX = mats[bx]
					for by = sy, eyEnd do
						local matsXY = matsX[by]
						for bz = sz, ezEnd do
							matsXY[bz] = mat
						end
					end
				end
			end
		end
	end

	local region = Region3.new(Vector3.new(cx, cy, cz), Vector3.new(cx + chunkStuds, cy + chunkStuds, cz + chunkStuds))
	terrain:WriteVoxels(region, RESOLUTION, mats, reuseOccs)
	yieldCheck("deep")
end

---------- PASS 2: SURFACE SHELL (full resolution) ----------
print(`[SphereGen] Pass 2: Surface shell ({totalSurface} chunks @ {RESOLUTION}-stud voxels)...`)
for _, chunk in surfaceChunks do
	local cx, cy, cz = chunk[1], chunk[2], chunk[3]
	local mats = reuseMats
	local occs = reuseOccs
	local hasContent = false

	-- Pre-compute approximate surface radius at chunk center for fast air rejection per voxel
	local cdx = cx + chunkStuds * 0.5 - CENTER_X
	local cdy = cy + chunkStuds * 0.5 - CENTER_Y
	local cdz = cz + chunkStuds * 0.5 - CENTER_Z
	local cd = mathSqrt(cdx * cdx + cdy * cdy + cdz * cdz)
	local quickAirThreshold
	if cd > 0.001 then
		local invCd = 1 / cd
		local approxSR = lookupSurfaceRadius(cdx * invCd, cdy * invCd, cdz * invCd)
		quickAirThreshold = math.max(approxSR, seaLevel) + chunkStuds
	else
		quickAirThreshold = outerBound
	end

	for ix = 1, CHUNK_SIZE do
		for iy = 1, CHUNK_SIZE do
			for iz = 1, CHUNK_SIZE do
				local wx = cx + (ix - 0.5) * RESOLUTION
				local wy = cy + (iy - 0.5) * RESOLUTION
				local wz = cz + (iz - 0.5) * RESOLUTION
				local dx, dy, dz = wx - CENTER_X, wy - CENTER_Y, wz - CENTER_Z
				local dist = mathSqrt(dx * dx + dy * dy + dz * dz)

				-- Fast path: definitely deep underground (skip expensive surface lookup)
				-- Overwrites coarse deep data with fine-resolution material at the transition
				if dist < innerBound then
					mats[ix][iy][iz] = getLayerMaterial(dist, wx, wy, wz) or Enum.Material.Rock
					occs[ix][iy][iz] = 1
					hasContent = true
					continue
				end

				-- Fast path: clearly above the surface, skip lookupSurface (saves acos+atan2)
				if dist > quickAirThreshold then
					mats[ix][iy][iz] = Enum.Material.Air
					occs[ix][iy][iz] = 0
					continue
				end

				if dist < 0.001 then
					mats[ix][iy][iz] = Enum.Material.Salt
					occs[ix][iy][iz] = 1
					hasContent = true
					continue
				end

				local invDist = 1 / dist
				local sr, biome = lookupSurface(dx * invDist, dy * invDist, dz * invDist)

				if dist <= sr then
					local depth = sr - dist
					occs[ix][iy][iz] = mathClamp(0.5 + depth / RESOLUTION, 0, 1)
					mats[ix][iy][iz] = getMaterial(depth, sr, dist, biome, wx, wy, wz)
					hasContent = true
				elseif dist <= seaLevel then
					local wd = seaLevel - dist
					occs[ix][iy][iz] = mathClamp(0.5 + wd / RESOLUTION, 0, 1)
					mats[ix][iy][iz] = Enum.Material.Water
					hasContent = true
				else
					mats[ix][iy][iz] = Enum.Material.Air
					occs[ix][iy][iz] = 0
				end
			end
		end
	end

	if hasContent then
		local region =
			Region3.new(Vector3.new(cx, cy, cz), Vector3.new(cx + chunkStuds, cy + chunkStuds, cz + chunkStuds))
		terrain:WriteVoxels(region, RESOLUTION, mats, occs)
	end
	yieldCheck("surface")
end

local elapsed = os.clock() - startTime
print(
	`[SphereGen] Done in {string.format("%.1f", elapsed)}s — {totalChunks} chunks ({totalDeep} deep + {totalSurface} surface, {skippedAir} air skipped)`
)

return true -- Required for clone-require pattern
