--!strict
-- Test code
for t = 3, 1, -1 do
	print(t)
	task.wait(1)
end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugHelper = require(ReplicatedStorage.Shared.Helpers.DebugHelper)
local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)
local Infinigrid = require(ReplicatedStorage.Shared.Common.Classes.Infinigrid)

local CHUNK_SIZE = 256
local planetGrid = Infinigrid.new(Vector3.zero, Vector3.one * 4224, CHUNK_SIZE)
print(planetGrid)

local debugBoxColorScheme = DebugHelper.GetColorScheme()
local debugBox = DebugHelper.Box(CFrame.identity, Vector3.one * CHUNK_SIZE, { Color = debugBoxColorScheme[1] })

local gridPosition = planetGrid:ChunkIndexToGridPosition(2592)
DebugHelper.Box(
	CFrame.new(planetGrid:GridPositionToWorldPosition(gridPosition)),
	Vector3.one * CHUNK_SIZE,
	{ Color = debugBoxColorScheme[2] :: any }
)

print(planetGrid.GenerationOrigin, planetGrid:ChunkIndexToGridPosition(1), planetGrid:ChunkIndexToGridPosition(2))

local character = Players.LocalPlayer.Character :: Model
local diag = DiagnosticHelper.new("Infinigrid")
while true do
	task.wait()
	local chunkIndex = planetGrid:_GetNearestChunkIndexAtPosition(character:GetPivot().Position)
	local worldSpaceCenter = planetGrid:GridPositionToWorldPosition(planetGrid:ChunkIndexToGridPosition(chunkIndex))
	print(chunkIndex, worldSpaceCenter)
	DebugHelper.Box(
		CFrame.new(worldSpaceCenter),
		Vector3.one * CHUNK_SIZE,
		{ Reuse = debugBox, Color = debugBoxColorScheme[1] }
	)
end
