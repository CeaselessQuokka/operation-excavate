--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

--- Imports ---
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlayerService: typeof(require(ServerScriptService.Server.Services.PlayerService))

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)
local TableEditor = require(ReplicatedStorage.Shared.TableEditor)

--- PlanetService Service ---
local PlanetService = {
	Name = "PlanetService",
}
Knit.CreateService(PlanetService)

function PlanetService:KnitStart()
	PlayerService = Knit.GetService("PlayerService")

	local fpsTable: { number } = table.create(60, task.wait())
	local idx = 1
	local nFrames = 1
	print(fpsTable, #fpsTable)
	RunService.Heartbeat:Connect(function(dt)
		nFrames += dt
		fpsTable[idx] = dt
		idx = idx % 60 + 1
		local tFps = 0
		for _, v in fpsTable do
			if v then
				tFps += v
			end
		end
		if nFrames >= 0.125 then
			TableEditor.ServerView(Players:GetPlayers(), "Info", {
				FPS = math.floor(1 / (tFps / 60)),
			})
			nFrames = 0
		end
	end)

	local planet = PlanetGenerator.new(67, 64)
	local sortedOffsets: { Vector3 } = {}
	for x = -10, 10 do
		for y = -1, 3 do
			for z = -10, 10 do
				table.insert(sortedOffsets, Vector3.new(x, y, z))
			end
		end
	end
	local function GenerateChunksAroundGridPosition(gridPosition: Vector3)
		local sorted = table.clone(sortedOffsets)
		table.sort(sorted, function(a, b)
			local aySame = a.Y == 0
			local bySame = b.Y == 0
			if aySame ~= bySame then
				return aySame
			end
			return a.X * a.X + a.Z * a.Z < b.X * b.X + b.Z * b.Z
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
				planet:GenerateChunk(chunkIndex)
			end

			-- Edge inward
			if hi ~= lo then
				local chunkIndex2 = planet:GridPositionToChunkIndex(gridPosition + sorted[hi])
				local chunk2 = planet:PeekChunk(chunkIndex2)
				if not chunk2.Generated and chunk2.ChunkType ~= "Air" then
					nGenerated += 1
					planet:GenerateChunk(chunkIndex2)
				end
			end

			lo += 1
			hi -= 1

			if lastGenerated ~= nGenerated and nGenerated % 4 <= 1 then
				task.wait()
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
		-- TODO: why does this run multiple times even after updating currentPosition?
		task.wait(1 / 30)
		for player: Player, character: CharacterHelper.UsableR15Character in characters do
			local lastPosition = lastPositions[player]
			local currentPosition = character:GetPivot().Position
			if lastPosition and (currentPosition - lastPosition).Magnitude < 24 then
				continue
			end

			print("\t", (currentPosition - (lastPosition or Vector3.zero)).Magnitude)
			lastPositions[player] = currentPosition
			task.spawn(function()
				local currentChunkIndex = planetGrid:_GetNearestChunkIndexAtPosition(character:GetPivot().Position)
				local chunkGridPosition = planet:ChunkIndexToGridPosition(currentChunkIndex)
				GenerateChunksAroundGridPosition(chunkGridPosition)
			end)
		end
	end
end

return PlanetService
