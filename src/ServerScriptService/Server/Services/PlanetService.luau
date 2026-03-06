--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--- Imports ---
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlayerService: typeof(require(ServerScriptService.Server.Services.PlayerService))

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)

--- PlanetService Service ---
local PlanetService = {
	Name = "PlanetService",
}
Knit.CreateService(PlanetService)

function PlanetService:KnitStart()
	PlayerService = Knit.GetService("PlayerService")

	local planet = PlanetGenerator.new(67, 64)
	local sortedOffsets: { Vector3 } = {}
	for x = -7, 7 do
		for y = -2, 2 do
			for z = -7, 7 do
				table.insert(sortedOffsets, Vector3.new(x, y, z))
			end
		end
	end
	table.sort(sortedOffsets, function(a, b)
		return a.X * a.X + a.Y * a.Y + a.Z * a.Z < b.X * b.X + b.Y * b.Y + b.Z * b.Z
	end)

	local function GenerateChunksAroundGridPosition(gridPosition: Vector3)
		local s = os.clock()
		local nGenerated = 0
		for _, offset in sortedOffsets do
			local chunkIndex = planet:GridPositionToChunkIndex(gridPosition + offset)
			local chunk = planet:PeekChunk(chunkIndex)
			if not chunk.Generated and chunk.ChunkType ~= "Air" then
				nGenerated += 1
				planet:GenerateChunk(chunkIndex)
				if nGenerated % 8 == 0 then
					task.wait()
				end
			end
		end
		print(os.clock() - s)
	end

	local planetGrid = planet.Grid
	local characters = PlayerService.Characters
	local lastPositions: { [Player]: Vector3 } = {}
	Players.PlayerRemoving:Connect(function(player)
		lastPositions[player] = nil
	end)
	while true do
		for player: Player, character: CharacterHelper.UsableR15Character in characters do
			local lastPosition = lastPositions[player]
			local currentPosition = character:GetPivot().Position
			if lastPosition and (currentPosition - lastPosition).Magnitude < 24 then
				continue
			end

			lastPositions[player] = currentPosition
			task.spawn(function()
				local currentChunkIndex = planetGrid:_GetNearestChunkIndexAtPosition(character:GetPivot().Position)
				local chunkGridPosition = planet:ChunkIndexToGridPosition(currentChunkIndex)
				GenerateChunksAroundGridPosition(chunkGridPosition)
			end)
		end
		task.wait(1 / 30)
	end
end

return PlanetService
