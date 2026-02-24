--!strict
-- do
-- 	return
-- end
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

local CHUNK_SIZE = 64
local planetGrid = Infinigrid.new(Vector3.zero, Vector3.one * 8296 * 2, CHUNK_SIZE)
print(planetGrid)

local debugBoxColorScheme = DebugHelper.GetColorScheme()
local debugBox = DebugHelper.Box(CFrame.identity, Vector3.one * CHUNK_SIZE, { Color = debugBoxColorScheme[1] })
debugBox.Name = "CurrentChunk"
local currentGridPosition = DebugHelper.LabeledPoint(Vector3.zero, "")
currentGridPosition.Name = "CurrentGridPosition"

local character = Players.LocalPlayer.Character :: Model
local diag = DiagnosticHelper.new("Infinigrid")
while true do
	task.wait()
	local chunkIndex = planetGrid:_GetNearestChunkIndexAtPosition(character:GetPivot().Position)
	local worldSpaceCenter = planetGrid:GridPositionToWorldPosition(planetGrid:ChunkIndexToGridPosition(chunkIndex))
	-- print(chunkIndex, planetGrid:ChunkIndexToGridPosition(chunkIndex), worldSpaceCenter)
	DebugHelper.LabeledPoint(
		worldSpaceCenter,
		`{chunkIndex} ({planetGrid:ChunkIndexToGridPosition(chunkIndex)})\n\t\t{worldSpaceCenter}`,
		{ Reuse = currentGridPosition }
	)
	DebugHelper.Box(
		CFrame.new(worldSpaceCenter),
		Vector3.one * CHUNK_SIZE,
		{ Reuse = debugBox, Color = debugBoxColorScheme[1] }
	)
	planetGrid:GetNeighborIndices(chunkIndex)
end
