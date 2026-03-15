--[[
	Earth terrain generator test script for Studio.
	Clone-require this module from the command bar:

		local m = game.ReplicatedStorage.Shared.Common.Classes.SphereGenerator.GenerateTestEarth:Clone()
		m.Parent = workspace
		require(m)
		m:Destroy()

	Adjust the CONFIG section below to control radius, vertical exaggeration, etc.
	Set SHOULD_GENERATE = true before running.
]]

---------- CONFIG ----------
local SHOULD_GENERATE = true
if not SHOULD_GENERATE then
	return true
end

-- Game-world radius in studs.
-- Small values (256–512) are fast to generate and good for shape verification.
-- Medium values (1024–2048) show continents and elevation clearly.
-- Production values (4096+) give full detail.
local RADIUS = 4096

-- How many studs each chunk spans per axis (aligned to 8-stud multiples).
local CHUNK_SIZE = 64

-- Multiplier for terrain height differences (mountains, trenches).
-- 1.0 = proportional to real Earth (features are sub-voxel and invisible).
-- nil = auto-compute (targets ~300 studs for Everest at any radius — recommended).
-- Higher values make terrain tall er/deeper.  At radius 2048, auto gives ~105x.
local VERTICAL_EXAGGERATION = nil -- auto: leave nil for best results at any radius

-- If true, only generate surface-shell chunks (skip buried interior). Much faster.
local SURFACE_ONLY = true

---------- FRESH REQUIRE ----------
local generatorFolder = game:GetService("ReplicatedStorage")
	:WaitForChild("Shared")
	:WaitForChild("Common")
	:WaitForChild("Classes")
	:WaitForChild("SphereGenerator")

local function freshRequire(name: string)
	local source = generatorFolder:FindFirstChild(name)
	assert(source, `[TestEarth] Module "{name}" not found in SphereGenerator folder`)
	return require(source)
end

local EarthGenerator = freshRequire("EarthGenerator")

---------- GENERATE ----------
print("[TestEarth] Creating EarthGenerator...")
local earth = EarthGenerator.new(CHUNK_SIZE, RADIUS, VERTICAL_EXAGGERATION)

print(`[TestEarth] Sea level = {earth.SeaLevel}, Surface range = {earth.MinSurfaceRadius} – {earth.MaxSurfaceRadius}`)
print(`[TestEarth] Grid dimensions = {earth.Grid.GridSize}`)

local stats = earth:GenerateFullPlanet(SURFACE_ONLY)

print(
	"[TestEarth] ═══════════════════════════════════════"
)
print(`[TestEarth] Total chunks : {stats.TotalChunks}`)
print(`[TestEarth] Surface      : {stats.SurfaceChunks}`)
print(`[TestEarth] Deep/Buried  : {stats.DeepChunks}`)
print(`[TestEarth] Air (skipped): {stats.AirChunks}`)
print(`[TestEarth] Water        : {stats.WaterChunks}`)
print(`[TestEarth] Time         : {string.format("%.1f", stats.ElapsedSeconds)}s`)
print(
	"[TestEarth] ═══════════════════════════════════════"
)

-- Print some reference positions for verification
local landmarks = {
	{ "Mt. Everest", 27.99, 86.93 },
	{ "Mariana Trench", 11.35, 142.20 },
	{ "London", 51.51, -0.13 },
	{ "New York", 40.71, -74.01 },
	{ "Florida (Miami)", 25.76, -80.19 },
	{ "Los Angeles", 34.05, -118.24 },
	{ "Tokyo", 35.68, 139.69 },
	{ "Sydney", -33.87, 151.21 },
	{ "Cairo", 30.04, 31.24 },
	{ "Rio de Janeiro", -22.91, -43.17 },
	{ "Great Lakes (Chicago)", 41.88, -87.63 },
	{ "North Pole", 90, 0 },
	{ "South Pole", -90, 0 },
}

print("[TestEarth] Landmark world positions:")
for _, lm in landmarks do
	local name = lm[1] :: string
	local lat = lm[2] :: number
	local lon = lm[3] :: number
	local pos = earth:LatLonToWorldPosition(lat, lon)
	print(`  {name}: ({string.format("%.0f", pos.X)}, {string.format("%.0f", pos.Y)}, {string.format("%.0f", pos.Z)})`)
end

print("[TestEarth] Done!")
return true
