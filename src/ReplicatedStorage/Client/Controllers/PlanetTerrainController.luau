--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--- Imports ---
local PlayerController = require(ReplicatedStorage.Client.Controllers.PlayerController)
local PlayerService = require(script.Parent.PlayerController)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)
local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local Planet = require(ReplicatedStorage.Shared.Common.Planet)
local TableEditor = require(ReplicatedStorage.Shared.TableEditor)

--- Variables ---
local World = JecsCommon.World

--- Planet Terrain Controller ---
local PlanetTerrainController = {}

-- TODO: need to support shapes like box, ball, cone (drills), etc
do -- Controller initialization.
	local planet = Planet.Terrain
	local sortedOffsets: { Vector3 } = {}
	for x = -8, 8 do
		for y = -1, 1 do
			for z = -8, 8 do
				table.insert(sortedOffsets, Vector3.new(x, y, z))
			end
		end
	end
	local sorted = table.clone(sortedOffsets)
	table.sort(sorted, function(a: Vector3, b: Vector3)
		return a.Magnitude < b.Magnitude
	end)
	local sizeZ = planet.Grid.GridSize.Z
	-- TODO: have an initial generation around the player, but then check if the player goes left or right on the grid (or forward or backward or diagonal) and then add chunks to generate based off that at the end of the initial frontier (will need to support multiple players)
	local function GenerateChunksAroundGridPosition(gridPosition: Vector3)
		local nGenerated = 0
		for _, offset in sorted do
			local chunkIndex = planet:GridPositionToChunkIndex(gridPosition + offset)
			local isAir, generated = planet:FastPeekChunk(chunkIndex)
			if generated then
				continue
			end

			if isAir then
				-- for yOffset = 1, 3 do
				-- 	chunkIndex -= sizeZ
				-- 	isAir, generated = planet:FastPeekChunk(chunkIndex)
				-- 	if not generated and not isAir then
				-- 		break
				-- 	end
				-- end
				-- local neighbors = planet.Grid:GetNeighborIndices(chunkIndex)
				-- for _, neighborChunkIndex in neighbors do
				-- 	local neighborIsAir, neighborIsGenerated = planet:FastPeekChunk(neighborChunkIndex)
				-- 	if not neighborIsGenerated and not neighborIsAir then
				-- 		nGenerated += 1
				-- 		planet:GenerateChunk(neighborChunkIndex)
				-- 		print("GENERATING", neighborChunkIndex)
				-- 	end
				-- 	if nGenerated % 8 == 0 then
				-- 		task.wait()
				-- 	end
				-- end
			elseif not generated then
				nGenerated += 1
				planet:GenerateChunk(chunkIndex)
			end
			if nGenerated % 8 == 0 then
				task.wait()
			end
		end
	end

	local planetGrid = planet.Grid
	local lastChunkIndex = nil
	task.spawn(function()
		while task.wait(1 / 8) do
			local character = PlayerController.Character
			if not character then
				continue
			end
			print(character:GetPivot().Position.Unit)
			local currentChunkIndex = planetGrid:GetNearestChunkIndexAtPosition(character:GetPivot().Position)
			if lastChunkIndex and currentChunkIndex == lastChunkIndex then
				continue
			end

			lastChunkIndex = currentChunkIndex
			task.spawn(function()
				local chunkGridPosition = planet:ChunkIndexToGridPosition(currentChunkIndex)
				GenerateChunksAroundGridPosition(chunkGridPosition)
			end)
		end
		task.wait(1 / 8)
	end)
end

return PlanetTerrainController
