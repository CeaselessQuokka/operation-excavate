--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--- Imports ---
local PlanetResourceService = require(script.Parent.PlanetResourceService)
local PlayerService = require(script.Parent.PlayerService)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)
local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local Planet = require(ReplicatedStorage.Shared.Common.Planet)
local TableEditor = require(ReplicatedStorage.Shared.TableEditor)

--- Variables ---
local World = JecsCommon.World

--- Planet Terrain Service ---
local PlanetTerrainService = {}

function PlanetResourceService.PermissionTerraform(player: Player, point: Vector3): boolean
	PlanetResourceService.PermissionTerraform(player, point)
	return true
end

-- TODO: need to support shapes like box, ball, cone (drills), etc
function PlanetTerrainService.Terraform(point: Vector3, radius: number)
	radius = math.ceil(radius / 4) * 4
	Workspace.Terrain:FillBall(point, radius, Enum.Material.Air)
	task.delay(0, PlanetResourceService.Terraform, point, radius)
end

do -- Service initialization.
	-- do -- Track FPS.
	-- 	local fpsTable: { number } = table.create(60, task.wait())
	-- 	local idx = 1
	-- 	local t = 0
	-- 	RunService.Heartbeat:Connect(function(dt)
	-- 		t += dt
	-- 		fpsTable[idx] = dt
	-- 		idx = idx % 60 + 1
	-- 		local tFps = 0
	-- 		for _, v in fpsTable do
	-- 			if v then
	-- 				tFps += v
	-- 			end
	-- 		end
	-- 		if t >= 0.375 then
	-- 			-- if RunService:IsStudio() then
	-- 			TableEditor.ServerView(Players:GetPlayers(), "Info", {
	-- 				FPS = math.floor(1 / (tFps / 60)),
	-- 			})
	-- 			-- end
	-- 			t = 0
	-- 		end
	-- 	end)
	-- end

	local planet = Planet.Terrain
	local sortedOffsets: { Vector3 } = {}
	for x = -8, 8 do
		for y = -1, 2 do
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
				for yOffset = 1, 3 do
					chunkIndex -= sizeZ
					isAir, generated = planet:FastPeekChunk(chunkIndex)
					if not generated and not isAir then
						break
					end
				end
			end
			if not generated and not isAir then
				nGenerated += 1
				PlanetResourceService.CreateChunk(chunkIndex)
				planet:GenerateChunk(chunkIndex)
			end
			if nGenerated % 16 == 0 then
				task.wait()
			end
		end
	end

	local planetGrid = planet.Grid
	local characters = PlayerService.Characters
	local lastChunkPositions: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(player)
		lastChunkPositions[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1 / 8)
			local threads = 0
			for player: Player, character: CharacterHelper.UsableR15Character in characters do
				local lastChunkIndex = lastChunkPositions[player]
				local currentChunkIndex = planetGrid:GetNearestChunkIndexAtPosition(character:GetPivot().Position)
				if lastChunkIndex and currentChunkIndex == lastChunkIndex then
					continue
				end

				-- print("\t", (currentPosition - (lastPosition or Vector3.zero)).Magnitude)
				lastChunkPositions[player] = currentChunkIndex
				task.spawn(function()
					threads += 1
					local chunkGridPosition = planet:ChunkIndexToGridPosition(currentChunkIndex)
					GenerateChunksAroundGridPosition(chunkGridPosition)
					threads -= 1
				end)
			end
			task.wait(1 / 8)
			-- while threads > 0 do
			-- 	task.wait(1 / 8)
			-- end
			-- print("DONE")
		end
	end)

	local remote = Remote.Event("OnRequestTerraform") :: Remote.ServerApi<(Vector3, number)>
	remote:Connect(function(player, point, radius)
		PlanetTerrainService.Terraform(point, radius)
	end)
end

return PlanetTerrainService
