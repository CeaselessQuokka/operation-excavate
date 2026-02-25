--!strict

--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Infinigrid = require(ReplicatedStorage.Shared.Common.Classes.Infinigrid)
local Knit = require(ReplicatedStorage.Packages.Knit)
local ParallelChunkScheduler = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.ParallelChunkScheduler)
local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)

--- Load Services ---
local servicesFolder = script:FindFirstChild("Services")
assert(servicesFolder, "[Server] Services folder not found")

for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") and module:GetAttribute("Enabled") ~= false then
		local success, err = pcall(require, module :: ModuleScript)
		if not success then
			warn(`[Server] Failed to load service "{module.Name}": {err}`)
		end
	end
end

--- Start Knit ---
Knit.Start():expect()

-- do
-- 	return
-- end

for t = 3, 1, -1 do
	print(`[Server] Starting in {t}...`)
	task.wait(1)
end

local s = os.clock()
local planet = PlanetGenerator.new(67, 64)
local planetRadius = math.ceil(planet.MaxSurfaceRadius / 8) * 8
print(os.clock() - s, planet.MaxSurfaceRadius, planetRadius)
local s = os.clock()
local planetGrid = Infinigrid.new(planet.Center, planet.GridWorldSize, planet.ChunkSize)
print(os.clock() - s, planet.Center, planet.GridWorldSize, planet.ChunkSize)

local scheduler = ParallelChunkScheduler.new()
scheduler:SetPlanet(planet)

task.wait(2)

local chunkIndices = {
	-- planet:GridPositionToChunkIndex(Vector3.new(129, 258, 129)),
}
for x = 129, 0, -1 do
	for y = 257, 257, -1 do
		for z = 129, 0, -1 do
			table.insert(chunkIndices, planet:GridPositionToChunkIndex(Vector3.new(x, y, z)))
		end
	end
end
print(#chunkIndices)
local s = os.clock()
for _, chunkIndex in chunkIndices do
	-- planet:GenerateChunk(chunkIndex)
	planet:PeekChunk(chunkIndex)
	-- if _ % 8 == 0 then
	-- 	task.wait()
	-- end
end
print(os.clock() - s)

-- local chunkIndex = planet:GridPositionToChunkIndex(Vector3.new(129, 257, 129))
-- local s = os.clock()
-- local data = planet:PeekChunk(chunkIndex)
-- print(os.clock() - s, data)

-- TODO: need to limit the master seed due to number precision:
-- local t = tonumber(tostring(os.time()):sub(1, 8))
-- print(t)
-- print(tonumber(`{t}{512}{512}{512}`))

-- local s = os.clock()
-- scheduler:GenerateChunks(chunkIndices)
-- print(`[Server] Generated {#chunkIndices} chunks in parallel in {string.format("%.6f", os.clock() - s)}s`)
-- local s = os.clock()

-- Run tests.
-- local Litmus = require(ReplicatedStorage.Shared.Litmus)
-- Litmus.RunSuite(require(ReplicatedStorage.Shared.Common.Classes.Infinigrid.TestFramework["Infinigrid.test"]))

-- Run benchmark.
-- require(ReplicatedStorage.Shared.Common.Classes.Infinigrid.TestFramework["Infinigrid.bench"])

-- Generate planet infinigrid for testing.
-- require(ReplicatedStorage.Shared.Common.Classes.Infinigrid).new(Vector3.zero, Vector3.new(4224, 4224, 4224), 64)

-- local Infinigrid = require(ReplicatedStorage.Shared.Common.Classes.Infinigrid)
-- local grid = Infinigrid.new(Vector3.zero, Vector3.new(4224, 4224, 4224), 64)
-- print(grid:GetChunkAtPosition(Vector3.zero))
