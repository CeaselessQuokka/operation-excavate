--!strict
do
	return
end
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

local CHUNK_SIZE = 128
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
print("ChunkIndex:", 0)
print("GridPosition:", planetGrid:ChunkIndexToGridPosition(0))
print("WorldPosition:", planetGrid:GridPositionToWorldPosition(planetGrid:ChunkIndexToGridPosition(0)))
print("ChunkIndex:", 1)
print("GridPosition:", planetGrid:ChunkIndexToGridPosition(1))
print("WorldPosition:", planetGrid:GridPositionToWorldPosition(planetGrid:ChunkIndexToGridPosition(1)))

local character = Players.LocalPlayer.Character :: Model
local diag = DiagnosticHelper.new("Infinigrid")
while true do
	task.wait()
	local chunkIndex = planetGrid:_GetNearestChunkIndexAtPosition(character:GetPivot().Position)
	local worldSpaceCenter = planetGrid:GridPositionToWorldPosition(planetGrid:ChunkIndexToGridPosition(chunkIndex))
	print(chunkIndex, planetGrid:ChunkIndexToGridPosition(chunkIndex), worldSpaceCenter)
	DebugHelper.Box(
		CFrame.new(worldSpaceCenter),
		Vector3.one * CHUNK_SIZE,
		{ Reuse = debugBox, Color = debugBoxColorScheme[1] }
	)
end
