--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Knit = require(ReplicatedStorage.Packages.Knit)

local LoadingHelper = require(ReplicatedStorage.Shared.Helpers.LoadingHelper)

--- Server Initialization ---
-- Load Knit services.
LoadingHelper.LoadModules(script.Services)
Knit.Start():expect()

-- Load server and shared components.
LoadingHelper.LoadModules(script.Components)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Components)

-- --!strict
-- --- Services ---
-- local Players = game:GetService("Players")
-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local RunService = game:GetService("RunService")
-- local ServerStorage = game:GetService("ServerStorage")

-- --- Imports ---
-- local Knit = require(ReplicatedStorage.Packages.Knit)

-- local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)
-- local Infinigrid = require(ReplicatedStorage.Shared.Common.Classes.Infinigrid)
-- local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)

-- --- Load Services ---
-- local servicesFolder = script:FindFirstChild("Services")
-- assert(servicesFolder, "[Server] Services folder not found")

-- for _, module in servicesFolder:GetChildren() do
-- 	if module:IsA("ModuleScript") and module:GetAttribute("Enabled") ~= false then
-- 		local success, err = pcall(require, module :: ModuleScript)
-- 		if not success then
-- 			warn(`[Server] Failed to load service "{module.Name}": {err}`)
-- 		end
-- 	end
-- end

-- --- Start Knit ---
-- Knit.Start():expect()

-- for t = if RunService:IsStudio() then 1 else 10, 1, -1 do
-- 	print(`[Server] Starting in {t}...`)
-- 	task.wait(1)
-- end

-- local planet = PlanetGenerator.new(67, 64)
-- local planetGrid = planet.Grid

-- local sortedOffsets: { Vector3 } = {}
-- for x = -7, 7 do
-- 	for y = -2, 2 do
-- 		for z = -7, 7 do
-- 			table.insert(sortedOffsets, Vector3.new(x, y, z))
-- 		end
-- 	end
-- end
-- table.sort(sortedOffsets, function(a, b)
-- 	return a.X * a.X + a.Y * a.Y + a.Z * a.Z < b.X * b.X + b.Y * b.Y + b.Z * b.Z
-- end)

-- local function GenerateChunksAroundGridPosition(gridPosition: Vector3)
-- 	local s = os.clock()
-- 	local nGenerated = 0
-- 	for _, offset in sortedOffsets do
-- 		local chunkIndex = planet:GridPositionToChunkIndex(gridPosition + offset)
-- 		local chunk = planet:PeekChunk(chunkIndex)
-- 		if not chunk.Generated and chunk.ChunkType ~= "Air" then
-- 			nGenerated += 1
-- 			planet:GenerateChunk(chunkIndex)
-- 			if nGenerated % 8 == 0 then
-- 				task.wait()
-- 			end
-- 		end
-- 	end
-- 	print(os.clock() - s)
-- end

-- local orientation = ServerStorage.AlignOrientation:Clone() :: AlignOrientation

-- local lastPosition = nil
-- local character: Model
-- while true do
-- 	character = Players:FindFirstChild("CeaselessQuokka") :: any
-- 	if character then
-- 		character = (character :: any).Character
-- 	end
-- 	if not character then
-- 		task.wait(1)
-- 		continue
-- 	end

-- 	local character = character :: Model
-- 	local pp = character.PrimaryPart :: BasePart
-- 	orientation.Attachment0 = pp.RootAttachment
-- 	orientation.Parent = pp
-- 	local currentPosition = character:GetPivot().Position

-- 	local normal = currentPosition.Unit
-- 	local zDir = character:GetPivot().ZVector
-- 	local xDir = normal:Cross(zDir)
-- 	orientation.CFrame = CFrame.fromMatrix(Vector3.zero, xDir, normal)
-- 	-- print(character.Humanoid.MoveDirection)

-- 	-- local ori = CFrame.fromMatrix(Vector3.zero, xDir, normal)
-- 	-- local y, x, z = ori:ToEulerAnglesYXZ()
-- 	-- local rori = pp.Orientation
-- 	-- local angles = CFrame.Angles(y, x, 0)
-- 	-- -- print(math.deg(y), math.deg(x), math.deg(z))
-- 	-- orientation.CFrame = angles

-- 	if lastPosition and (currentPosition - lastPosition).Magnitude < 24 then
-- 		task.wait(0.125)
-- 		continue
-- 	end

-- 	lastPosition = currentPosition
-- 	local currentChunkIndex = planetGrid:_GetNearestChunkIndexAtPosition(character:GetPivot().Position)
-- 	local chunkGridPosition = planet:ChunkIndexToGridPosition(currentChunkIndex)
-- 	task.spawn(GenerateChunksAroundGridPosition, chunkGridPosition)
-- end

-- -- local nGenerated = 0
-- -- for x = 0, 256 do
-- -- 	for y = 0, 256 do
-- -- 		for z = 0, 256 do
-- -- 			local gridPosition = Vector3.new(x, y, z)
-- -- 			local chunkIndex = planet:GridPositionToChunkIndex(gridPosition)
-- -- 			if planet:PeekChunk(chunkIndex).ChunkType == "Surface" then
-- -- 				nGenerated += 1
-- -- 				planet:GenerateChunk(chunkIndex)
-- -- 				if nGenerated % 24 == 0 then
-- -- 					task.wait()
-- -- 				end
-- -- 			end
-- -- 		end
-- -- 	end
-- -- end

-- -- --!strict
-- -- --- Services ---
-- -- local Players = game:GetService("Players")
-- -- local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- -- --- Imports ---
-- -- local Infinigrid = require(ReplicatedStorage.Shared.Common.Classes.Infinigrid)
-- -- local Knit = require(ReplicatedStorage.Packages.Knit)
-- -- local ParallelChunkScheduler = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.ParallelChunkScheduler)
-- -- local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)

-- -- --- Load Services ---
-- -- local servicesFolder = script:FindFirstChild("Services")
-- -- assert(servicesFolder, "[Server] Services folder not found")

-- -- for _, module in servicesFolder:GetChildren() do
-- -- 	if module:IsA("ModuleScript") and module:GetAttribute("Enabled") ~= false then
-- -- 		local success, err = pcall(require, module :: ModuleScript)
-- -- 		if not success then
-- -- 			warn(`[Server] Failed to load service "{module.Name}": {err}`)
-- -- 		end
-- -- 	end
-- -- end

-- -- --- Start Knit ---
-- -- Knit.Start():expect()

-- -- -- do
-- -- -- 	return
-- -- -- end

-- -- for t = 3, 1, -1 do
-- -- 	print(`[Server] Starting in {t}...`)
-- -- 	task.wait(1)
-- -- end

-- -- local s = os.clock()
-- -- local planet = PlanetGenerator.new(67, 64)
-- -- local planetRadius = math.ceil(planet.MaxSurfaceRadius / 8) * 8
-- -- print(os.clock() - s, planet.MaxSurfaceRadius, planetRadius)
-- -- local s = os.clock()
-- -- local planetGrid = Infinigrid.new(planet.Center, planet.GridWorldSize, planet.ChunkSize)
-- -- print(os.clock() - s, planet.Center, planet.GridWorldSize, planet.ChunkSize)

-- -- -- local scheduler = ParallelChunkScheduler.new()
-- -- -- scheduler:SetPlanet(planet)

-- -- task.wait(2)

-- -- -- local chunkIndices = {
-- -- -- 	-- planet:GridPositionToChunkIndex(Vector3.new(129, 258, 129)),
-- -- -- }
-- -- -- for x = 129, 0, -1 do
-- -- -- 	for y = 257, 257, -1 do
-- -- -- 		for z = 129, 0, -1 do
-- -- -- 			table.insert(chunkIndices, planet:GridPositionToChunkIndex(Vector3.new(x, y, z)))
-- -- -- 		end
-- -- -- 	end
-- -- -- end
-- -- -- print(#chunkIndices)
-- -- -- local s = os.clock()
-- -- -- for _, chunkIndex in chunkIndices do
-- -- -- 	-- planet:GenerateChunk(chunkIndex)
-- -- -- 	planet:PeekChunk(chunkIndex)
-- -- -- 	-- if _ % 8 == 0 then
-- -- -- 	-- 	task.wait()
-- -- -- 	-- end
-- -- -- end
-- -- -- print(os.clock() - s)

-- -- local chunkIndex1 = planet:GridPositionToChunkIndex(Vector3.new(129, 257, 129))
-- -- local chunkIndex2 = planet:GridPositionToChunkIndex(Vector3.new(129, 256, 129))
-- -- local chunkIndex3 = planet:GridPositionToChunkIndex(Vector3.new(129, 255, 129))
-- -- local chunkIndex4 = planet:GridPositionToChunkIndex(Vector3.new(129, 254, 129))
-- -- print(
-- -- 	planet:PeekChunk(chunkIndex1),
-- -- 	planet:PeekChunk(chunkIndex2),
-- -- 	planet:PeekChunk(chunkIndex3),
-- -- 	planet:PeekChunk(chunkIndex4)
-- -- )

-- -- -- local chunkIndex = planet:GridPositionToChunkIndex(Vector3.new(129, 257, 129))
-- -- -- local s = os.clock()
-- -- -- local data = planet:PeekChunk(chunkIndex)
-- -- -- print(os.clock() - s, data)

-- -- -- TODO: need to limit the master seed due to number precision:
-- -- -- local t = tonumber(tostring(os.time()):sub(1, 8))
-- -- -- print(t)
-- -- -- print(tonumber(`{t}{512}{512}{512}`))

-- -- -- local s = os.clock()
-- -- -- scheduler:GenerateChunks(chunkIndices)
-- -- -- print(`[Server] Generated {#chunkIndices} chunks in parallel in {string.format("%.6f", os.clock() - s)}s`)
-- -- -- local s = os.clock()

-- -- -- Run tests.
-- -- -- local Litmus = require(ReplicatedStorage.Shared.Litmus)
-- -- -- Litmus.RunSuite(require(ReplicatedStorage.Shared.Common.Classes.Infinigrid.TestFramework["Infinigrid.test"]))

-- -- -- Run benchmark.
-- -- -- require(ReplicatedStorage.Shared.Common.Classes.Infinigrid.TestFramework["Infinigrid.bench"])

-- -- -- Generate planet infinigrid for testing.
-- -- -- require(ReplicatedStorage.Shared.Common.Classes.Infinigrid).new(Vector3.zero, Vector3.new(4224, 4224, 4224), 64)

-- -- -- local Infinigrid = require(ReplicatedStorage.Shared.Common.Classes.Infinigrid)
-- -- -- local grid = Infinigrid.new(Vector3.zero, Vector3.new(4224, 4224, 4224), 64)
-- -- -- print(grid:GetChunkAtPosition(Vector3.zero))
