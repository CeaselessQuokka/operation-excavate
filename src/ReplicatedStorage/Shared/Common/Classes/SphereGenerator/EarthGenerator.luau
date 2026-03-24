--[[
	Deterministic Earth terrain generator with a chunk-based API.
	Produces a 1:1 proportional replica of Earth at any given radius.
	Uses real geographic data (continent boundaries, mountains, ocean trenches)
	to generate terrain that is always identical for a given radius.

	Usage:
		local earth = EarthGenerator.new(chunkSize, radius?, verticalExaggeration?, quiet?)
		local result = earth:GenerateChunk(chunkIndex)
		local peek   = earth:PeekChunk(chunkIndex)

	The constructor yields during surface grid precomputation.
	ChunkSize is in studs and will be aligned to multiples of 8.
	The internal Infinigrid is exposed as earth.Grid.

	Coordinate convention:
		- North pole at +Y, South pole at -Y
		- Prime Meridian (0° longitude) at +X direction
		- 90°E at +Z direction
]]

--!strict

--- Imports ---
local Biomes = require(script.Parent.Biomes)
local EarthData = require(script.Parent.EarthData)
local Grid = require(script.Parent.Parent.Grid)

--- Types ---
type Biome = Biomes.Biome

export type GenerateChunkResult = {
	ChunkType: string, -- "Air" | "Deep" | "Surface"
	IsWater: boolean,
	ChunkSeed: number,
}

export type PeekChunkResult = {
	ChunkType: string, -- "Air" | "Surface" | "Buried"
	IsWater: boolean,
	MinHeight: number?,
	MaxHeight: number?,
	Generated: boolean,
	ChunkSeed: number,
}

--- Constants ---
local RESOLUTION = 4
local INV_RESOLUTION = 1 / RESOLUTION
local DEEP_STRIDE = 4

local DEFAULT_RADIUS = 16384
-- Auto-computed vertical exaggeration:
-- Chosen so that total relief (Everest – Mariana ≈ 20 km) is visible regardless of
-- radius.  Formula targets ~300 studs for Everest at any radius.
-- Users can override this by passing a verticalExaggeration to .new().
local function defaultVertExag(radius: number): number
	return math.ceil(300 * EarthData.EARTH_RADIUS_M / (EarthData.EVEREST_HEIGHT_M * radius))
end

local GRID_LAT = 256
local GRID_LON = 512
local PI = math.pi
local TWO_PI = 2 * math.pi
local RAD = math.rad

local SURFACE_DEPTH = 12
local SUBSURFACE_DEPTH = 48

-- Underground water reservoir constants.
-- Water pools form in the upper crust where 3D noise exceeds a threshold.
-- AQUIFER_FRAC_MIN/MAX: fraction of radius range where pools can form.
-- (roughly upper crust through lower crust — the groundwater zone)
local AQUIFER_FRAC_MIN = 0.975 -- ~160 km below surface (scaled)
local AQUIFER_FRAC_MAX = 0.996 -- just below biome surface layer
local AQUIFER_NOISE_SCALE = 0.06 -- spatial frequency of pool shapes
local AQUIFER_THRESHOLD = 0.38 -- noise must exceed this → water (~12% of volume)

local mathClamp = math.clamp
local mathFloor = math.floor
local mathSqrt = math.sqrt
local mathAcos = math.acos
local mathAtan2 = math.atan2
local mathNoise = math.noise
local mathAbs = math.abs
local mathMax = math.max
local mathMin = math.min
local mathExp = math.exp
local mathSin = math.sin
local mathCos = math.cos

--- Geometry Helpers ---

-- Point-in-polygon test (ray casting algorithm, lat/lon space).
local function pointInPolygon(lat: number, lon: number, poly: { { number } }): boolean
	local inside = false
	local n = #poly
	local j = n
	for i = 1, n do
		local yi, xi = poly[i][1], poly[i][2]
		local yj, xj = poly[j][1], poly[j][2]
		if ((yi > lat) ~= (yj > lat)) and (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) then
			inside = not inside
		end
		j = i
	end
	return inside
end

-- AABB for a polygon.
local function computeAABB(poly: { { number } }): (number, number, number, number)
	local minLat, maxLat = math.huge, -math.huge
	local minLon, maxLon = math.huge, -math.huge
	for _, v in poly do
		if v[1] < minLat then
			minLat = v[1]
		end
		if v[1] > maxLat then
			maxLat = v[1]
		end
		if v[2] < minLon then
			minLon = v[2]
		end
		if v[2] > maxLon then
			maxLon = v[2]
		end
	end
	return minLat, maxLat, minLon, maxLon
end

-- Shortest distance from a point to a line segment in degree space.
-- Accounts for longitude compression at higher latitudes.
local function pointToSegmentDist(lat: number, lon: number, p1: { number }, p2: { number }): number
	local cosLat = mathCos(RAD(lat))
	local dx = (p2[2] - p1[2]) * cosLat
	local dy = p2[1] - p1[1]
	local len2 = dx * dx + dy * dy
	if len2 < 1e-10 then
		local ex = (lon - p1[2]) * cosLat
		local ey = lat - p1[1]
		return mathSqrt(ex * ex + ey * ey)
	end
	local px = (lon - p1[2]) * cosLat
	local py = lat - p1[1]
	local t = mathClamp((px * dx + py * dy) / len2, 0, 1)
	local projX = t * dx
	local projY = t * dy
	local ex = px - projX
	local ey = py - projY
	return mathSqrt(ex * ex + ey * ey)
end

-- Catmull-Rom cubic interpolation weights.
local function catmullRom(t: number): (number, number, number, number)
	local t2 = t * t
	local t3 = t2 * t
	return -0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1, -1.5 * t3 + 2 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2
end

--- Layer Material ---

local function getLayerMaterial(frac: number, wx: number, wy: number, wz: number): Enum.Material?
	-- Noise for variety within layers (fixed offsets, no seed needed)
	local n1 = mathNoise(wx * 0.015 + 73.1, wy * 0.015 + 19.7, wz * 0.015 + 42.3)
	local n2 = mathNoise(wx * 0.05 + 11.2, wy * 0.05 + 88.4, wz * 0.05 + 55.9)

	if frac >= EarthData.LAYER_UPPER_CRUST then
		return nil -- Handled by surface biome material
	end

	-- Inner core: solid iron-nickel
	if frac < EarthData.LAYER_INNER_CORE then
		if frac < 0.02 then
			return Enum.Material.Salt -- Very center marker
		end
		return if n1 > 0.25 then Enum.Material.Basalt else Enum.Material.CrackedLava
	end

	-- Outer core: liquid iron-nickel
	if frac < EarthData.LAYER_OUTER_CORE then
		if n1 > 0.3 then
			return Enum.Material.CrackedLava
		end
		return Enum.Material.Basalt
	end

	-- Lower mantle: silicate rock
	if frac < EarthData.LAYER_LOWER_MANTLE then
		if n1 > 0.3 then
			return Enum.Material.Basalt
		end
		if n2 > 0.28 then
			return Enum.Material.Sandstone
		end
		return Enum.Material.Concrete
	end

	-- Mid mantle: denser silicate
	if frac < EarthData.LAYER_MID_MANTLE then
		if n1 > 0.28 then
			return Enum.Material.Concrete
		end
		return Enum.Material.Slate
	end

	-- Upper mantle: peridotite
	if frac < EarthData.LAYER_UPPER_MANTLE then
		if n1 > 0.28 then
			return Enum.Material.Slate
		end
		if n2 > 0.25 then
			return Enum.Material.Sandstone
		end
		return Enum.Material.Rock
	end

	-- Lower crust: basaltic
	if frac < EarthData.LAYER_LOWER_CRUST then
		if n1 > 0.25 then
			return Enum.Material.Rock
		end
		if n2 > 0.25 then
			return Enum.Material.Sandstone
		end
		return Enum.Material.Cobblestone
	end

	-- Upper crust: granitic/sedimentary
	if n1 > 0.22 then
		return Enum.Material.Sandstone
	end
	if n2 > 0.25 then
		return Enum.Material.Cobblestone
	end
	return Enum.Material.Limestone
end

--- Surface Material ---

local function getMaterial(
	depth: number,
	surfR: number,
	dist: number,
	biome: Biome,
	seaLevel: number,
	radius: number,
	wx: number,
	wy: number,
	wz: number
): Enum.Material
	local frac = dist / radius
	if frac < 0.02 then
		return Enum.Material.Salt
	end

	local isUnderwater = surfR < seaLevel
	local nVar = mathNoise(wx * 0.04 + 73.1, wy * 0.04 + 19.7, wz * 0.04 + 42.3)

	if depth < SURFACE_DEPTH then
		if isUnderwater then
			local waterDepth = seaLevel - surfR
			if waterDepth < 30 then
				return Enum.Material.Sand
			elseif waterDepth < 100 then
				return if nVar > 0.0 then Enum.Material.Sand else Enum.Material.Mud
			elseif waterDepth < 250 then
				return if nVar > 0.3 then Enum.Material.Ground else Enum.Material.Mud
			else
				return if nVar > 0.2 then Enum.Material.Slate else Enum.Material.Rock
			end
		end
		return biome.SurfaceMaterial
	end

	if depth < SUBSURFACE_DEPTH then
		if isUnderwater then
			return Enum.Material.Rock
		end
		return biome.SubsurfaceMaterial
	end

	local layerMat = getLayerMaterial(frac, wx, wy, wz)
	if layerMat then
		return layerMat
	end
	return biome.DeepMaterial
end

--- Surface Lookup (bicubic interpolation, identical to PlanetGenerator) ---

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

	local latBase = mathFloor(latF)
	local lonBase = mathFloor(lonF)
	local tLat = latF - latBase
	local tLon = lonF - lonBase

	local wLa, wLb, wLc, wLd = catmullRom(tLat)
	local wMa, wMb, wMc, wMd = catmullRom(tLon)

	local la = mathClamp(latBase - 1, 0, GRID_LAT)
	local lb = mathClamp(latBase, 0, GRID_LAT)
	local lc = mathClamp(latBase + 1, 0, GRID_LAT)
	local ld = mathClamp(latBase + 2, 0, GRID_LAT)

	local ma = (lonBase - 1) % GRID_LON
	local mb = lonBase % GRID_LON
	local mc = (lonBase + 1) % GRID_LON
	local md = (lonBase + 2) % GRID_LON

	local row
	row = gridSR[la]
	local ra = wMa * row[ma] + wMb * row[mb] + wMc * row[mc] + wMd * row[md]
	row = gridSR[lb]
	local rb = wMa * row[ma] + wMb * row[mb] + wMc * row[mc] + wMd * row[md]
	row = gridSR[lc]
	local rc = wMa * row[ma] + wMb * row[mb] + wMc * row[mc] + wMd * row[md]
	row = gridSR[ld]
	local rd = wMa * row[ma] + wMb * row[mb] + wMc * row[mc] + wMd * row[md]

	local sr = wLa * ra + wLb * rb + wLc * rc + wLd * rd

	local nearLat = mathClamp(if tLat < 0.5 then latBase else latBase + 1, 0, GRID_LAT)
	local nearLon = (if tLon < 0.5 then lonBase else lonBase + 1) % GRID_LON

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
	local latBase = mathFloor(latF)
	local lonBase = mathFloor(lonF)
	local tLat = latF - latBase
	local tLon = lonF - lonBase

	local wLa, wLb, wLc, wLd = catmullRom(tLat)
	local wMa, wMb, wMc, wMd = catmullRom(tLon)

	local la = mathClamp(latBase - 1, 0, GRID_LAT)
	local lb = mathClamp(latBase, 0, GRID_LAT)
	local lc = mathClamp(latBase + 1, 0, GRID_LAT)
	local ld = mathClamp(latBase + 2, 0, GRID_LAT)

	local ma = (lonBase - 1) % GRID_LON
	local mb = lonBase % GRID_LON
	local mc = (lonBase + 1) % GRID_LON
	local md = (lonBase + 2) % GRID_LON

	local row
	row = gridSR[la]
	local ra = wMa * row[ma] + wMb * row[mb] + wMc * row[mc] + wMd * row[md]
	row = gridSR[lb]
	local rb = wMa * row[ma] + wMb * row[mb] + wMc * row[mc] + wMd * row[md]
	row = gridSR[lc]
	local rc = wMa * row[ma] + wMb * row[mb] + wMc * row[mc] + wMd * row[md]
	row = gridSR[ld]
	local rd = wMa * row[ma] + wMb * row[mb] + wMc * row[mc] + wMd * row[md]

	return wLa * ra + wLb * rb + wLc * rc + wLd * rd
end

--- Grid Precomputation Helpers ---

-- Convert grid indices to geographic lat/lon.
local function gridToLatLon(latI: number, lonI: number): (number, number)
	local lat = 90 - latI * (180 / GRID_LAT)
	local lon = lonI * (360 / GRID_LON)
	if lon >= 180 then
		lon -= 360
	end
	return lat, lon
end

-- Precompute AABBs for all polygons.
type PolyAABB = { poly: { { number } }, minLat: number, maxLat: number, minLon: number, maxLon: number }

local function buildAABBList(polygons: any): { PolyAABB }
	local list: { PolyAABB } = {}
	for _, poly in polygons :: { [string]: { { number } } } do
		local minLat, maxLat, minLon, maxLon = computeAABB(poly)
		table.insert(list, { poly = poly, minLat = minLat, maxLat = maxLat, minLon = minLon, maxLon = maxLon })
	end
	return list
end

-- Check if a lat/lon falls inside any polygon in the AABB list.
local function isInsideAny(lat: number, lon: number, aabbList: { PolyAABB }): boolean
	for _, entry in aabbList do
		if lat >= entry.minLat and lat <= entry.maxLat and lon >= entry.minLon and lon <= entry.maxLon then
			if pointInPolygon(lat, lon, entry.poly) then
				return true
			end
		end
	end
	return false
end

-- Compute elevation (in meters) at a geographic point.
local function computeElevation(lat: number, lon: number, isLand: boolean, coastDist: number): number
	local elevation: number

	if isLand then
		-- Coastal plains → gentle inland rise
		local d = coastDist
		if d <= 1 then
			elevation = 5
		elseif d <= 3 then
			elevation = 5 + (d - 1) * 25
		elseif d <= 6 then
			elevation = 55 + (d - 3) * 50
		elseif d <= 12 then
			elevation = 205 + (d - 6) * 30
		else
			elevation = 385 + mathMin(d - 12, 10) * 15
		end
	else
		-- Real ocean bathymetry.
		-- Earth average ocean depth ≈ 3688 m. Deep basins reach 5000-6000 m.
		-- Continental shelf: 0-200 m, ~200 km wide ≈ 2 grid steps at equator.
		local d = mathAbs(coastDist)
		if d <= 2 then
			-- Continental shelf: very shallow, gently sloping (0 → 200 m)
			elevation = -10 - d * 95
		elseif d <= 5 then
			-- Continental slope: steep drop from 200 m → 3500 m
			local slopeT = (d - 2) / 3
			slopeT = slopeT * slopeT * (3 - 2 * slopeT) -- smoothstep
			elevation = -200 - slopeT * 3300
		elseif d <= 12 then
			-- Continental rise → abyssal plain: 3500 → 4500 m
			elevation = -3500 - (d - 5) * 143
		else
			-- Deep abyssal plain & basins: 4500 → 5500 m for very remote ocean
			elevation = -4500 - mathMin(d - 12, 20) * 50
		end
	end

	-- Lowland basin depressions (Amazon, Mississippi, etc.)
	if isLand then
		for _, basin in EarthData.LowlandBasins do
			local dlat = (lat - basin.CenterLat) / basin.RadiusLat
			local dlon = (lon - basin.CenterLon) / basin.RadiusLon
			local dist2 = dlat * dlat + dlon * dlon
			if dist2 < 1 then
				local t = 1 - mathSqrt(dist2)
				t = t * t
				elevation = elevation - basin.Depth * t
				if elevation < 5 then
					elevation = 5
				end
			end
		end
	end

	-- Plateau contributions (take max with current elevation for land features)
	for _, p in EarthData.Plateaus do
		local dlat = (lat - p.CenterLat) / p.RadiusLat
		local dlon = (lon - p.CenterLon) / p.RadiusLon
		local dist2 = dlat * dlat + dlon * dlon
		if dist2 < 1 then
			local t = 1 - mathSqrt(dist2)
			t = t * t
			elevation = mathMax(elevation, p.Height * t)
		end
	end

	-- Mountain range contributions
	-- Use t^1.3 falloff instead of t^2 for broader, more natural mountain silhouettes.
	for _, range in EarthData.MountainRanges do
		local pts = range.Points
		local minD = math.huge
		for i = 1, #pts - 1 do
			local d = pointToSegmentDist(lat, lon, pts[i], pts[i + 1])
			if d < minD then
				minD = d
			end
		end
		if minD < range.Width then
			local t = 1 - (minD / range.Width)
			t = t * mathSqrt(t) -- t^1.5: gentler falloff → wider visible mountains
			local contrib = range.PeakHeight * t
			if contrib > elevation then
				elevation = contrib
			end
		end
	end

	-- Individual peak contributions (Gaussian)
	for _, peak in EarthData.Peaks do
		local dlat = lat - peak.Lat
		local dlon = (lon - peak.Lon) * mathCos(RAD(lat))
		local dist = mathSqrt(dlat * dlat + dlon * dlon)
		local cutoff = peak.Radius * 3
		if dist < cutoff then
			local sigma = peak.Radius
			local contrib = peak.Height * mathExp(-dist * dist / (2 * sigma * sigma))
			if contrib > elevation then
				elevation = contrib
			end
		end
	end

	-- Ocean features (only for water cells)
	if not isLand then
		-- Trenches (deepen)
		for _, trench in EarthData.OceanTrenches do
			local pts = trench.Points
			local minD = math.huge
			for i = 1, #pts - 1 do
				local d = pointToSegmentDist(lat, lon, pts[i], pts[i + 1])
				if d < minD then
					minD = d
				end
			end
			if minD < trench.Width then
				local t = 1 - (minD / trench.Width)
				t = t * t
				local contrib = -(trench.Depth :: number) * t
				if contrib < elevation then
					elevation = contrib
				end
			end
		end

		-- Ridges (shallow uplift from abyssal floor)
		for _, ridge in EarthData.OceanRidges do
			local pts = ridge.Points
			local minD = math.huge
			for i = 1, #pts - 1 do
				local d = pointToSegmentDist(lat, lon, pts[i], pts[i + 1])
				if d < minD then
					minD = d
				end
			end
			if minD < ridge.Width then
				local t = 1 - (minD / ridge.Width)
				t = t * t
				elevation = elevation + ridge.Height * t
			end
		end
	end

	-- Add small-scale procedural detail for natural roughness.
	-- Use 3D cartesian coords (not lat/lon) to avoid polar pinch artifacts.
	local theta = RAD(90 - lat)
	local phi = RAD(lon)
	local sinT = mathSin(theta)
	local detailScale = 8 -- feature size in degree-equivalent units
	local nx = sinT * mathCos(phi) * detailScale
	local ny = mathCos(theta) * detailScale
	local nz = sinT * mathSin(phi) * detailScale
	local detail = mathNoise(nx + 31.7, ny + 57.3, nz + 13.2)
	-- Second octave for mountain roughness
	local detail2 = mathNoise(nx * 2.1 + 88.4, ny * 2.1 + 12.9, nz * 2.1 + 63.7) * 0.4
	local combinedDetail = detail + detail2
	if isLand then
		-- Mountains get proportionally more roughness to look jagged
		elevation = elevation + combinedDetail * mathMax(80, elevation * 0.1)
	else
		elevation = elevation + detail * 40
	end

	return elevation
end

-- Determine biome at a geographic point.
local function determineBiome(lat: number, lon: number, elevation: number, isLand: boolean, coastDist: number): Biome
	if not isLand then
		-- Use a generic underwater "biome" — pick Grassland for material compatibility
		-- (actual underwater materials are handled in getMaterial)
		return Biomes.GetBiomeByName("Grassland") :: Biome
	end

	local absLat = mathAbs(lat)

	-- Temperature (0 = cold, 1 = hot)
	local temperature: number
	if absLat > 75 then
		temperature = 0.02
	elseif absLat > 60 then
		temperature = 0.05 + (75 - absLat) / 15 * 0.2
	elseif absLat > 45 then
		temperature = 0.25 + (60 - absLat) / 15 * 0.25
	elseif absLat > 25 then
		temperature = 0.5 + (45 - absLat) / 20 * 0.2
	else
		temperature = 0.7 + (25 - absLat) / 25 * 0.3
	end
	-- Altitude cooling
	temperature = mathClamp(temperature - elevation / 8000 * 0.3, 0, 1)

	-- Moisture (base: wetter near coast)
	local moisture: number
	local d = coastDist
	if d <= 3 then
		moisture = 0.7
	elseif d <= 10 then
		moisture = 0.7 - (d - 3) / 7 * 0.35
	else
		moisture = 0.35
	end

	-- Desert region override
	for _, desert in EarthData.DesertRegions do
		local dlat = (lat - desert.CenterLat) / desert.RadiusLat
		local dlon = (lon - desert.CenterLon) / desert.RadiusLon
		if dlat * dlat + dlon * dlon < 1 then
			moisture = moisture * 0.15
			break
		end
	end
	moisture = mathClamp(moisture, 0, 1)

	-- Mountainness
	local mountainness = 0
	if elevation > 1500 then
		mountainness = mathClamp((elevation - 1500) / 3500, 0, 0.8)
	end

	return Biomes.GetBiome(temperature, moisture, mountainness)
end

--- Earth Generator Class ---
local EarthGenerator = {}
EarthGenerator.__index = EarthGenerator

export type EarthGenerator = typeof(setmetatable(
	{} :: {
		Grid: Grid.Grid<any>,
		Radius: number,
		SeaLevel: number,
		VerticalExaggeration: number,
		MaxSurfaceRadius: number,
		MinSurfaceRadius: number,
		Resolution: number,
		_voxelsPerAxis: number,
		_deepStride: number,
		_gridSR: { [number]: { [number]: number } },
		_gridBiome: { [number]: { [number]: Biome } },
		_outerBound: number,
		_innerBound: number,
		_sizeYZ: number,
		_sizeZ: number,
		_reuseMats: { { { Enum.Material } } },
		_reuseOccs: { { { number } } },
		_generated: { [number]: true },
		_elevScale: number,
	},
	EarthGenerator
))

function EarthGenerator.new(
	chunkSize: number,
	radius: number?,
	verticalExaggeration: number?,
	quiet: boolean?
): EarthGenerator
	local gameRadius = radius or DEFAULT_RADIUS
	local vertExag = verticalExaggeration or defaultVertExag(gameRadius)
	local seaLevel = gameRadius

	local alignedChunkSize = math.ceil(chunkSize / 8) * 8
	local voxelsPerAxis = alignedChunkSize / RESOLUTION
	local deepStride = mathMin(DEEP_STRIDE, voxelsPerAxis)

	-- Scale factor: meters → studs, with vertical exaggeration
	local elevScale = (gameRadius / EarthData.EARTH_RADIUS_M) * vertExag

	-- ──────────── Precompute polygon AABBs ────────────
	local landAABBs = buildAABBList(EarthData.LandPolygons)
	local carveAABBs = buildAABBList(EarthData.WaterCarveOuts)

	-- ──────────── Build land mask grid ────────────
	if not quiet then
		print(`[EarthGenerator] Building land mask ({GRID_LAT + 1}x{GRID_LON})...`)
	end
	local maskStart = os.clock()

	-- Flat array: landMask[latI * GRID_LON + lonI] = true/false
	local totalCells = (GRID_LAT + 1) * GRID_LON
	local landMask: { boolean } = table.create(totalCells, false) :: any
	landMask[0] = false -- Ensure 0-based index 0 is initialized (table.create fills 1..N)

	for latI = 0, GRID_LAT do
		for lonI = 0, GRID_LON - 1 do
			local lat, lon = gridToLatLon(latI, lonI)
			local isLand = isInsideAny(lat, lon, landAABBs)
			if isLand then
				isLand = not isInsideAny(lat, lon, carveAABBs)
			end
			landMask[latI * GRID_LON + lonI] = isLand
		end
		if not quiet and latI % 32 == 0 then
			task.wait()
		end
	end

	if not quiet then
		print(`[EarthGenerator] Land mask computed in {string.format("%.1f", os.clock() - maskStart)}s`)
	end

	-- ──────────── Distance from coast (BFS) ────────────
	if not quiet then
		print("[EarthGenerator] Computing distance from coast...")
	end
	local distStart = os.clock()

	local distGrid: { number } = table.create(totalCells, 999) :: any
	distGrid[0] = 999 -- Ensure 0-based index 0 is initialized (table.create fills 1..N)

	-- Queue: flat list of indices. Use two arrays for BFS layers.
	local currentQueue: { number } = {}
	local nextQueue: { number } = {}

	-- Find coast cells (land cells adjacent to water or vice versa)
	for latI = 0, GRID_LAT do
		for lonI = 0, GRID_LON - 1 do
			local idx = latI * GRID_LON + lonI
			local isLand = landMask[idx]
			local isCoast = false

			-- Check 4 neighbors
			if latI > 0 and landMask[(latI - 1) * GRID_LON + lonI] ~= isLand then
				isCoast = true
			end
			if not isCoast and latI < GRID_LAT and landMask[(latI + 1) * GRID_LON + lonI] ~= isLand then
				isCoast = true
			end
			if not isCoast then
				local lonL = (lonI - 1) % GRID_LON
				if landMask[latI * GRID_LON + lonL] ~= isLand then
					isCoast = true
				end
			end
			if not isCoast then
				local lonR = (lonI + 1) % GRID_LON
				if landMask[latI * GRID_LON + lonR] ~= isLand then
					isCoast = true
				end
			end

			if isCoast then
				distGrid[idx] = 0
				table.insert(currentQueue, idx)
			end
		end
	end

	-- BFS expansion
	local curDist = 0
	while #currentQueue > 0 do
		curDist += 1
		for _, idx in currentQueue do
			local latI = idx // GRID_LON
			local lonI = idx % GRID_LON

			-- 4 neighbors
			local neighbors = {
				if latI > 0 then (latI - 1) * GRID_LON + lonI else -1,
				if latI < GRID_LAT then (latI + 1) * GRID_LON + lonI else -1,
				latI * GRID_LON + ((lonI - 1) % GRID_LON),
				latI * GRID_LON + ((lonI + 1) % GRID_LON),
			}

			for _, nIdx in neighbors do
				if nIdx >= 0 and distGrid[nIdx] > curDist then
					distGrid[nIdx] = curDist
					table.insert(nextQueue, nIdx)
				end
			end
		end

		-- Swap queues
		currentQueue, nextQueue = nextQueue, {}
	end

	-- Apply sign: negative for water cells
	for i = 0, totalCells - 1 do
		if not landMask[i] then
			distGrid[i] = -distGrid[i]
		end
	end

	if not quiet then
		print(`[EarthGenerator] Distance field computed in {string.format("%.1f", os.clock() - distStart)}s`)
	end

	-- ──────────── Compute elevation & biome grids ────────────
	if not quiet then
		print("[EarthGenerator] Computing elevation & biome grids...")
	end
	local elevStart = os.clock()

	local gridSR: { [number]: { [number]: number } } = table.create(GRID_LAT + 1) :: any
	local gridBiomeTable: { [number]: { [number]: Biome } } = table.create(GRID_LAT + 1) :: any
	local globalMinSR = math.huge
	local globalMaxSR = -math.huge

	for latI = 0, GRID_LAT do
		local srRow: { [number]: number } = table.create(GRID_LON) :: any
		local biomeRow: { [number]: Biome } = table.create(GRID_LON) :: any

		for lonI = 0, GRID_LON - 1 do
			local lat, lon = gridToLatLon(latI, lonI)
			local idx = latI * GRID_LON + lonI
			local isLand = landMask[idx]
			local coastDist = distGrid[idx]

			local elevMeters = computeElevation(lat, lon, isLand, coastDist)
			local biome = determineBiome(lat, lon, elevMeters, isLand, coastDist)

			-- Convert elevation to surface radius in game units
			local sr = seaLevel + elevMeters * elevScale
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

		if not quiet and latI % 32 == 0 then
			task.wait()
		end
	end

	if not quiet then
		print(
			`[EarthGenerator] Elevation grid computed in {string.format("%.1f", os.clock() - elevStart)}s`
				.. ` (range: {string.format("%.0f", globalMinSR)} to {string.format("%.0f", globalMaxSR)})`
		)
	end

	-- ──────────── Bounds ────────────
	local maxExtent = mathMax(globalMaxSR, seaLevel)
	local outerBound = maxExtent + RESOLUTION * 2
	local innerBound = globalMinSR - SUBSURFACE_DEPTH - RESOLUTION * 2

	local rawWorldSize = math.ceil(maxExtent / 8) * 8 * 2
	local worldSpaceSize = math.ceil(rawWorldSize / 8) * 8

	local grid = Grid.new(Vector3.zero, Vector3.one * worldSpaceSize, alignedChunkSize)

	local cachedSizeYZ = grid.GridSize.Y * grid.GridSize.Z
	local cachedSizeZ = grid.GridSize.Z

	-- Pre-allocate reusable voxel arrays
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

	local self: EarthGenerator = setmetatable({
		Grid = grid,
		Radius = gameRadius,
		SeaLevel = seaLevel,
		VerticalExaggeration = vertExag,
		MaxSurfaceRadius = maxExtent,
		MinSurfaceRadius = globalMinSR,
		Resolution = RESOLUTION,
		_voxelsPerAxis = voxelsPerAxis,
		_deepStride = deepStride,
		_gridSR = gridSR,
		_gridBiome = gridBiomeTable,
		_outerBound = outerBound,
		_innerBound = innerBound,
		_sizeYZ = cachedSizeYZ,
		_sizeZ = cachedSizeZ,
		_reuseMats = reuseMats,
		_reuseOccs = reuseOccs,
		_generated = {},
		_elevScale = elevScale,
	}, EarthGenerator)

	if not quiet then
		print(
			`[EarthGenerator] Earth ready. Radius={gameRadius} VertExag={vertExag}x`
				.. ` Grid={grid.GridSize.X}x{grid.GridSize.Y}x{grid.GridSize.Z}`
		)
	end

	return self
end

-- ══════════════════════════════════════════════════════════════════
-- Public API (matches PlanetGenerator)
-- ══════════════════════════════════════════════════════════════════

function EarthGenerator.ChunkIndexToGridPosition(self: EarthGenerator, chunkIndex: number): Vector3
	return self.Grid:ChunkIndexToGridPosition(chunkIndex)
end

function EarthGenerator.GridPositionToChunkIndex(self: EarthGenerator, gridPosition: Vector3): number
	return self.Grid:GridPositionToChunkIndex(gridPosition)
end

function EarthGenerator.GridPositionToWorldPosition(self: EarthGenerator, gridPosition: Vector3): Vector3
	return self.Grid:GridPositionToWorldPosition(gridPosition)
end

function EarthGenerator.GetChunkSeed(self: EarthGenerator, chunkIndex: number): number
	local gridPos = self:ChunkIndexToGridPosition(chunkIndex)
	-- Fixed seed component (Earth is always the same; use a constant instead of masterSeed)
	return tonumber(`42{gridPos.X}{gridPos.Y}{gridPos.Z}`) :: number
end

-- ══════════════════════════════════════════════════════════════════
-- Internal: compute chunk voxel data
-- ══════════════════════════════════════════════════════════════════

function EarthGenerator._ComputeChunkData(self: EarthGenerator, chunkIndex: number): (string, number, boolean, Region3?)
	local sizeYZ = self._sizeYZ
	local sizeZ = self._sizeZ
	local remainder = chunkIndex % sizeYZ
	local gx = chunkIndex // sizeYZ
	local gy = remainder // sizeZ
	local gz = remainder % sizeZ

	local chunkSeed = tonumber(`42{gx}{gy}{gz}`) :: number

	local halfWorld = self.Grid.GridWorldSize.X / 2
	local cs = self.Grid.ChunkSize
	local cx = -halfWorld + gx * cs
	local cy = -halfWorld + gy * cs
	local cz = -halfWorld + gz * cs

	local vpa = self._voxelsPerAxis
	local gSR = self._gridSR
	local gBiome = self._gridBiome
	local innerBound = self._innerBound
	local outerBound = self._outerBound
	local gameRadius = self.Radius
	local sl = self.SeaLevel

	-- Chunk center distance
	local cdx = cx + cs * 0.5
	local cdy = cy + cs * 0.5
	local cdz = cz + cs * 0.5
	local cd = mathSqrt(cdx * cdx + cdy * cdy + cdz * cdz)
	local halfDiag = cs * 0.866

	-- Quick air rejection
	if cd - halfDiag > outerBound then
		return "Air", chunkSeed, false, nil
	end

	local region = Region3.new(Vector3.new(cx, cy, cz), Vector3.new(cx + cs, cy + cs, cz + cs))

	-- Deep interior: stride-sampled
	if cd + halfDiag <= innerBound then
		local mats = self._reuseMats
		local occs = self._reuseOccs
		local stride = self._deepStride
		local deepMid = (stride - 1) * 0.5

		for sx = 1, vpa, stride do
			local exEnd = mathMin(sx + stride - 1, vpa)
			for sy = 1, vpa, stride do
				local eyEnd = mathMin(sy + stride - 1, vpa)
				for sz = 1, vpa, stride do
					local ezEnd = mathMin(sz + stride - 1, vpa)
					local wx = cx + (sx + deepMid - 0.5) * RESOLUTION
					local wy = cy + (sy + deepMid - 0.5) * RESOLUTION
					local wz = cz + (sz + deepMid - 0.5) * RESOLUTION
					local dist = mathSqrt(wx * wx + wy * wy + wz * wz)
					local frac = dist / gameRadius
					local mat: Enum.Material

					-- Underground water reservoir (aquifer pocket)
					if frac >= AQUIFER_FRAC_MIN and frac <= AQUIFER_FRAC_MAX then
						local aq = mathNoise(
							wx * AQUIFER_NOISE_SCALE + 200.7,
							wy * AQUIFER_NOISE_SCALE + 311.3,
							wz * AQUIFER_NOISE_SCALE + 97.1
						)
						if aq > AQUIFER_THRESHOLD then
							mat = Enum.Material.Water
						else
							mat = getLayerMaterial(frac, wx, wy, wz) or Enum.Material.Rock
						end
					else
						mat = getLayerMaterial(frac, wx, wy, wz) or Enum.Material.Rock
					end

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

	-- Surface shell: full-resolution
	local mats = self._reuseMats
	local occs = self._reuseOccs
	local hasContent = false

	local quickAirThreshold
	if cd > 0.001 then
		local invCd = 1 / cd
		local approxSR = surfaceRadiusLookup(gSR, cdx * invCd, cdy * invCd, cdz * invCd)
		quickAirThreshold = mathMax(approxSR, sl) + cs
	else
		quickAirThreshold = outerBound
	end

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

				-- Fast path: deep underground
				if dist < innerBound then
					local frac = dist / gameRadius
					local mat: Enum.Material
					if frac >= AQUIFER_FRAC_MIN and frac <= AQUIFER_FRAC_MAX then
						local aq = mathNoise(
							wx * AQUIFER_NOISE_SCALE + 200.7,
							wy * AQUIFER_NOISE_SCALE + 311.3,
							wz * AQUIFER_NOISE_SCALE + 97.1
						)
						if aq > AQUIFER_THRESHOLD then
							mat = Enum.Material.Water
						else
							mat = getLayerMaterial(frac, wx, wy, wz) or Enum.Material.Rock
						end
					else
						mat = getLayerMaterial(frac, wx, wy, wz) or Enum.Material.Rock
					end
					mats[ix][iy][iz] = mat
					occs[ix][iy][iz] = 1
					hasContent = true
					continue
				end

				-- Fast path: clearly above surface
				if dist > quickAirThreshold then
					mats[ix][iy][iz] = Enum.Material.Air
					occs[ix][iy][iz] = 0
					continue
				end

				-- Edge case: exact center
				if dist < 0.001 then
					mats[ix][iy][iz] = Enum.Material.Salt
					occs[ix][iy][iz] = 1
					hasContent = true
					continue
				end

				local invDist = 1 / dist
				local sr, biome = surfaceLookup(gSR, gBiome, wx * invDist, wy * invDist, wz * invDist)

				local terrainOcc = mathClamp(0.5 + (sr - dist) * invRes, 0, 1)

				if terrainOcc > 0 then
					occs[ix][iy][iz] = terrainOcc
					local depth = sr - dist
					local depthPos = if depth > 0 then depth else 0
					-- Underground water reservoir check (only below subsurface)
					local frac = dist / gameRadius
					if depthPos > SUBSURFACE_DEPTH and frac >= AQUIFER_FRAC_MIN and frac <= AQUIFER_FRAC_MAX then
						local aq = mathNoise(
							wx * AQUIFER_NOISE_SCALE + 200.7,
							wy * AQUIFER_NOISE_SCALE + 311.3,
							wz * AQUIFER_NOISE_SCALE + 97.1
						)
						if aq > AQUIFER_THRESHOLD then
							mats[ix][iy][iz] = Enum.Material.Water
						else
							mats[ix][iy][iz] = getMaterial(depthPos, sr, dist, biome, sl, gameRadius, wx, wy, wz)
						end
					else
						mats[ix][iy][iz] = getMaterial(depthPos, sr, dist, biome, sl, gameRadius, wx, wy, wz)
					end
					hasContent = true
				else
					local waterOcc = mathClamp(0.5 + (sl - dist) * invRes, 0, 1)
					if waterOcc > 0 then
						occs[ix][iy][iz] = waterOcc
						mats[ix][iy][iz] = Enum.Material.Water
						hasContent = true
					else
						mats[ix][iy][iz] = Enum.Material.Air
						occs[ix][iy][iz] = 0
					end
				end
			end
		end
	end

	if not hasContent then
		return "Air", chunkSeed, false, nil
	end
	return "Surface", chunkSeed, true, region
end

-- ══════════════════════════════════════════════════════════════════
-- PeekChunk: classify a chunk without generating voxels
-- ══════════════════════════════════════════════════════════════════

function EarthGenerator.PeekChunk(self: EarthGenerator, chunkIndex: number): PeekChunkResult
	local sizeYZ = self._sizeYZ
	local sizeZ = self._sizeZ
	local remainder = chunkIndex % sizeYZ
	local gx = chunkIndex // sizeYZ
	local gy = remainder // sizeZ
	local gz = remainder % sizeZ

	local chunkSeed = tonumber(`42{gx}{gy}{gz}`) :: number

	local halfWorld = self.Grid.GridWorldSize.X / 2
	local cs = self.Grid.ChunkSize
	local x0 = -halfWorld + gx * cs
	local y0 = -halfWorld + gy * cs
	local z0 = -halfWorld + gz * cs
	local x1 = x0 + cs
	local y1 = y0 + cs
	local z1 = z0 + cs

	local clX = mathClamp(0, x0, x1)
	local clY = mathClamp(0, y0, y1)
	local clZ = mathClamp(0, z0, z1)
	local minDist = mathSqrt(clX * clX + clY * clY + clZ * clZ)

	local fX = if mathAbs(x0) > mathAbs(x1) then x0 else x1
	local fY = if mathAbs(y0) > mathAbs(y1) then y0 else y1
	local fZ = if mathAbs(z0) > mathAbs(z1) then z0 else z1
	local maxDist = mathSqrt(fX * fX + fY * fY + fZ * fZ)

	local generated = self._generated[chunkIndex] == true
	local sl = self.SeaLevel

	if minDist > self._outerBound then
		return { ChunkType = "Air", IsWater = false, Generated = generated, ChunkSeed = chunkSeed }
	end

	if maxDist <= self._innerBound then
		return { ChunkType = "Buried", IsWater = false, Generated = generated, ChunkSeed = chunkSeed }
	end

	-- Sample surface radius at chunk center + 8 corners
	local gridSR = self._gridSR
	local minSR = math.huge
	local maxSR = -math.huge

	-- Inline 9 sample points (center + 8 corners) to avoid table allocation.
	local half = cs * 0.5
	local function sampleSR(px: number, py: number, pz: number)
		local d = mathSqrt(px * px + py * py + pz * pz)
		if d > 0.001 then
			local invD = 1 / d
			local sr = surfaceRadiusLookup(gridSR, px * invD, py * invD, pz * invD)
			if sr < minSR then
				minSR = sr
			end
			if sr > maxSR then
				maxSR = sr
			end
		end
	end
	sampleSR(x0 + half, y0 + half, z0 + half) -- center
	sampleSR(x0, y0, z0)
	sampleSR(x1, y0, z0)
	sampleSR(x0, y1, z0)
	sampleSR(x0, y0, z1)
	sampleSR(x1, y1, z0)
	sampleSR(x1, y0, z1)
	sampleSR(x0, y1, z1)
	sampleSR(x1, y1, z1)

	local effectiveMax = mathMax(maxSR, sl)

	if minDist > effectiveMax then
		return { ChunkType = "Air", IsWater = false, Generated = generated, ChunkSeed = chunkSeed }
	end

	if maxDist < minSR then
		return { ChunkType = "Buried", IsWater = false, Generated = generated, ChunkSeed = chunkSeed }
	end

	local isWater = minSR < sl and minDist <= sl

	if minDist > maxSR and minDist <= sl and maxSR < sl then
		return {
			ChunkType = "Surface",
			IsWater = true,
			MinHeight = minSR - sl,
			MaxHeight = maxSR - sl,
			Generated = generated,
			ChunkSeed = chunkSeed,
		}
	end

	return {
		ChunkType = "Surface",
		IsWater = isWater,
		MinHeight = minSR - sl,
		MaxHeight = maxSR - sl,
		Generated = generated,
		ChunkSeed = chunkSeed,
	}
end

-- ══════════════════════════════════════════════════════════════════
-- GenerateChunk: produce terrain and write voxels
-- ══════════════════════════════════════════════════════════════════

function EarthGenerator.GenerateChunk(self: EarthGenerator, chunkIndex: number): GenerateChunkResult
	local chunkType, chunkSeed, hasContent, region = self:_ComputeChunkData(chunkIndex)
	local isWater = false

	if hasContent then
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

-- ══════════════════════════════════════════════════════════════════
-- Utility: convert geographic coordinates to world position
-- ══════════════════════════════════════════════════════════════════

-- Convert (latitude, longitude) in degrees to a world-space Vector3 on the terrain surface.
-- North pole = +Y, Prime Meridian = +X, 90°E = +Z.
function EarthGenerator.LatLonToWorldPosition(self: EarthGenerator, lat: number, lon: number): Vector3
	local theta = RAD(90 - lat)
	local phi = RAD(lon)
	local sinT = mathSin(theta)
	local dx = sinT * mathCos(phi)
	local dy = mathCos(theta)
	local dz = sinT * mathSin(phi)

	local sr = surfaceRadiusLookup(self._gridSR, dx, dy, dz)
	local r = mathMax(sr, self.SeaLevel)
	return Vector3.new(dx * r, dy * r, dz * r)
end

-- Convert a world-space Vector3 to (latitude, longitude) in degrees.
function EarthGenerator.WorldPositionToLatLon(self: EarthGenerator, position: Vector3): (number, number)
	local dist = position.Magnitude
	if dist < 0.001 then
		return 0, 0
	end
	local dx = position.X / dist
	local dy = position.Y / dist
	local dz = position.Z / dist

	local lat = 90 - math.deg(mathAcos(mathClamp(dy, -1, 1)))
	local lon = math.deg(mathAtan2(dz, dx))
	return lat, lon
end

-- ══════════════════════════════════════════════════════════════════
-- GenerateFullPlanet: generate every non-Air chunk on the surface shell.
-- Pass surfaceOnly=true to skip Deep interior chunks (much faster for visual preview).
-- Returns stats about the generation.
-- ══════════════════════════════════════════════════════════════════

function EarthGenerator.GenerateFullPlanet(
	self: EarthGenerator,
	surfaceOnly: boolean?
): {
	TotalChunks: number,
	SurfaceChunks: number,
	DeepChunks: number,
	AirChunks: number,
	WaterChunks: number,
	ElapsedSeconds: number,
}
	local skipDeep = surfaceOnly == true
	local grid = self.Grid
	local gridSize = grid.GridSize
	local totalX = gridSize.X
	local totalY = gridSize.Y
	local totalZ = gridSize.Z
	local totalChunks = totalX * totalY * totalZ

	local surfaceCount = 0
	local deepCount = 0
	local airCount = 0
	local waterCount = 0
	local processed = 0

	print(`[EarthGenerator] Generating full planet ({totalChunks} total chunks, surfaceOnly={skipDeep})...`)
	local startTime = os.clock()
	local lastYield = startTime

	-- Pre-compute bounds for fast chunk rejection without calling PeekChunk.
	local halfWorld = grid.GridWorldSize.X / 2
	local cs = grid.ChunkSize
	local halfDiag = cs * 0.866 -- half of chunk diagonal
	local outerBound = self._outerBound
	local innerBound = self._innerBound

	for chunkIndex = 0, totalChunks - 1 do
		-- Inline cheap distance check: skip chunks entirely outside the sphere.
		-- This avoids calling PeekChunk (which does 9 surface lookups) on distant air.
		local remainder = chunkIndex % (totalY * totalZ)
		local gx = chunkIndex // (totalY * totalZ)
		local gy = remainder // totalZ
		local gz = remainder % totalZ
		local cx = -halfWorld + gx * cs + cs * 0.5
		local cy = -halfWorld + gy * cs + cs * 0.5
		local cz = -halfWorld + gz * cs + cs * 0.5
		local cd = mathSqrt(cx * cx + cy * cy + cz * cz)

		if cd - halfDiag > outerBound then
			-- Entirely outside the sphere → Air, skip immediately
			airCount += 1
		elseif skipDeep and cd + halfDiag < innerBound then
			-- Entirely buried inside the sphere → skip when surfaceOnly
			deepCount += 1
		else
			-- Near the surface shell: classify properly
			local peek = self:PeekChunk(chunkIndex)

			if peek.ChunkType == "Air" then
				airCount += 1
			elseif peek.ChunkType == "Buried" then
				if skipDeep then
					deepCount += 1
				else
					self:GenerateChunk(chunkIndex)
					deepCount += 1
				end
			else
				-- Surface chunk: always generate
				local result = self:GenerateChunk(chunkIndex)
				surfaceCount += 1
				if result.IsWater then
					waterCount += 1
				end
			end
		end

		processed += 1

		-- Yield periodically to avoid freezing
		local now = os.clock()
		if now - lastYield > 0.1 then
			lastYield = now
			local elapsed = now - startTime
			local pct = processed / totalChunks * 100
			local rate = processed / mathMax(elapsed, 0.001)
			local remaining = (totalChunks - processed) / mathMax(rate, 1)
			print(
				`[EarthGenerator] {string.format("%.1f", pct)}%`
					.. ` ({processed}/{totalChunks})`
					.. ` Surface={surfaceCount} Deep={deepCount} Air={airCount}`
					.. ` ~{string.format("%.0f", remaining)}s remaining`
			)
			task.wait()
		end
	end

	local elapsed = os.clock() - startTime
	print(
		`[EarthGenerator] Generation complete in {string.format("%.1f", elapsed)}s.`
			.. ` Surface={surfaceCount} Deep={deepCount} Air={airCount} Water={waterCount}`
	)

	return {
		TotalChunks = totalChunks,
		SurfaceChunks = surfaceCount,
		DeepChunks = deepCount,
		AirChunks = airCount,
		WaterChunks = waterCount,
		ElapsedSeconds = elapsed,
	}
end

return table.freeze(EarthGenerator)
