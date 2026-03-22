--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--- Imports ---
local PlanetResourceService = require(script.Parent.PlanetResourceService)
local PlayerService = require(script.Parent.PlayerService)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
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
	for x = -50, 50 do
		for y = -3, 3 do
			for z = -50, 50 do
				table.insert(sortedOffsets, Vector3.new(x, y, z))
			end
		end
	end
	local function GenerateChunksAroundGridPosition(gridPosition: Vector3)
		local sorted = table.clone(sortedOffsets)
		table.sort(sorted, function(a: Vector3, b: Vector3)
			return a.Magnitude < b.Magnitude
		end)

		local s = os.clock()
		local nGenerated = 0
		local lo, hi = 1, #sorted

		while lo <= hi do
			local lastGenerated = nGenerated

			-- Center outward
			local chunkIndex = planet:GridPositionToChunkIndex(gridPosition + sorted[lo])
			local chunk = planet:PeekChunk(chunkIndex)
			if not chunk.Generated and chunk.ChunkType ~= "Air" then
				nGenerated += 1
				PlanetResourceService.CreateChunk(chunkIndex)
				task.spawn(planet.GenerateChunk, planet, chunkIndex)
			end

			-- Edge inward
			if hi ~= lo then
				local chunkIndex2 = planet:GridPositionToChunkIndex(gridPosition + sorted[hi])
				local chunk2 = planet:PeekChunk(chunkIndex2)
				if not chunk2.Generated and chunk2.ChunkType ~= "Air" then
					nGenerated += 1
					PlanetResourceService.CreateChunk(chunkIndex2)
					task.spawn(planet.GenerateChunk, planet, chunkIndex2)
				end
			end

			lo += 1
			hi -= 1

			if lastGenerated ~= nGenerated and nGenerated % 12 <= 0 then
				task.wait()
			end
		end
		-- print(os.clock() - s)
	end

	local planetGrid = planet.Grid
	local characters = PlayerService.Characters
	local lastPositions: { [Player]: Vector3 } = {}
	Players.PlayerRemoving:Connect(function(player)
		lastPositions[player] = nil
	end)
	task.spawn(function()
		while true do
			-- TODO: why does this run multiple times even after updating currentPosition?
			task.wait(1 / 8)
			for player: Player, character: CharacterHelper.UsableR15Character in characters do
				local lastPosition = lastPositions[player]
				local currentPosition = character:GetPivot().Position
				if lastPosition and (currentPosition - lastPosition).Magnitude < 24 then
					continue
				end

				-- print("\t", (currentPosition - (lastPosition or Vector3.zero)).Magnitude)
				lastPositions[player] = currentPosition
				task.spawn(function()
					local currentChunkIndex = planetGrid:_GetNearestChunkIndexAtPosition(character:GetPivot().Position)
					local chunkGridPosition = planet:ChunkIndexToGridPosition(currentChunkIndex)
					-- print(chunkGridPosition)
					GenerateChunksAroundGridPosition(chunkGridPosition)
				end)
			end
			task.wait(1 / 8)
		end
	end)
end

return PlanetService
