--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--- Imports ---
local PlanetResourceService = require(script.Parent.PlanetResourceService)
local PlayerService = require(script.Parent.PlayerService)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)
local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local Planet = require(ReplicatedStorage.Shared.Common.Planet)
local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)
local TableEditor = require(ReplicatedStorage.Shared.TableEditor)

--- Variables ---
local World = JecsCommon.World

--- PlanetService Service ---
local PlanetService = {}

do -- Service initialization.
	do -- Track FPS.
		local fpsTable: { number } = table.create(60, task.wait())
		local idx = 1
		local t = 0
		RunService.Heartbeat:Connect(function(dt)
			t += dt
			fpsTable[idx] = dt
			idx = idx % 60 + 1
			local tFps = 0
			for _, v in fpsTable do
				if v then
					tFps += v
				end
			end
			if t >= 0.375 then
				-- if RunService:IsStudio() then
				TableEditor.ServerView(Players:GetPlayers(), "Info", {
					FPS = math.floor(1 / (tFps / 60)),
				})
				-- end
				t = 0
			end
		end)
	end

	task.wait(3)
	local planet = Planet.Terrain
	local sortedOffsets: { Vector3 } = {}
	for x = -100, 100 do
		for y = -2, 1 do
			for z = -100, 100 do
				table.insert(sortedOffsets, Vector3.new(x, y, z))
			end
		end
	end
	local sorted = table.clone(sortedOffsets)
	table.sort(sorted, function(a: Vector3, b: Vector3)
		return a.Magnitude < b.Magnitude
	end)
	-- local sizeZ = planet.Grid.GridSize.Z
	local function GenerateChunksAroundGridPosition(gridPosition: Vector3)
		local nGenerated = 0
		for _, offset in sorted do
			local chunkIndex = planet:GridPositionToChunkIndex(gridPosition + offset)
			local isAir, generated = planet:FastPeekChunk(chunkIndex)
			if not generated and not isAir then
				nGenerated += 1
				PlanetResourceService.CreateChunk(chunkIndex)
				planet:GenerateChunk(chunkIndex)
			end
			if nGenerated % 16 == 0 then
				task.wait()
			end
		end

		-- local nGenerated = 0
		-- local lo, hi = 1, #sorted
		-- while lo <= hi do
		-- 	local lastGenerated = nGenerated

		-- 	-- Center outward
		-- 	local chunkIndex = planet:GridPositionToChunkIndex(gridPosition + sorted[lo])
		-- 	local isAir, generated = planet:FastPeekChunk(chunkIndex)
		-- 	-- if not generated then
		-- 	-- if isAir then
		-- 	-- 	for yOffset = 1, 5 do
		-- 	-- 		isAir, generated = planet:FastPeekChunk(chunkIndex - sizeZ)
		-- 	-- 		if not generated and not isAir then
		-- 	-- 			break
		-- 	-- 		end
		-- 	-- 	end
		-- 	-- end
		-- 	if not generated and not isAir then
		-- 		nGenerated += 1
		-- 		PlanetResourceService.CreateChunk(chunkIndex)
		-- 		task.spawn(planet.GenerateChunk, planet, chunkIndex)
		-- 	end
		-- 	-- end

		-- 	-- Edge inward
		-- 	if hi ~= lo then
		-- 		local chunkIndex2 = planet:GridPositionToChunkIndex(gridPosition + sorted[hi])
		-- 		local isAir2, generated2 = planet:FastPeekChunk(chunkIndex2)
		-- 		-- if not generated2 then
		-- 		-- if isAir2 then
		-- 		-- 	for yOffset = 1, 5 do
		-- 		-- 		isAir2, generated2 = planet:FastPeekChunk(chunkIndex2 - sizeZ)
		-- 		-- 		if not generated2 and not isAir2 then
		-- 		-- 			break
		-- 		-- 		end
		-- 		-- 	end
		-- 		-- end
		-- 		if not generated2 and not isAir2 then
		-- 			nGenerated += 1
		-- 			PlanetResourceService.CreateChunk(chunkIndex2)
		-- 			task.spawn(planet.GenerateChunk, planet, chunkIndex2)
		-- 		end
		-- 		-- end
		-- 	end

		-- 	lo += 1
		-- 	hi -= 1
		-- 	if lastGenerated ~= nGenerated and nGenerated % 16 <= 0 then
		-- 		task.wait()
		-- 	end
		-- end
	end

	local planetGrid = planet.Grid
	local characters = PlayerService.Characters
	local lastPositions: { [Player]: Vector3 } = {}
	Players.PlayerRemoving:Connect(function(player)
		lastPositions[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1 / 4)
			local threads = 0
			for player: Player, character: CharacterHelper.UsableR15Character in characters do
				local lastPosition = lastPositions[player]
				local currentPosition = character:GetPivot().Position
				if lastPosition and (currentPosition - lastPosition).Magnitude < 24 then
					continue
				end

				-- print("\t", (currentPosition - (lastPosition or Vector3.zero)).Magnitude)
				lastPositions[player] = currentPosition
				task.spawn(function()
					threads += 1
					local currentChunkIndex = planetGrid:_GetNearestChunkIndexAtPosition(character:GetPivot().Position)
					local chunkGridPosition = planet:ChunkIndexToGridPosition(currentChunkIndex)
					-- print(chunkGridPosition)
					GenerateChunksAroundGridPosition(chunkGridPosition)
					threads -= 1
				end)
			end
			while threads > 0 do
				task.wait(1 / 8)
			end
			print("DONE")
		end
	end)
end

return PlanetService
