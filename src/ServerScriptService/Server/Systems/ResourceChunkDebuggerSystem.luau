--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Grid = require(ReplicatedStorage.Shared.Common.Classes.Grid)
local Jecs = require(ReplicatedStorage.Packages.Jecs)

local SystemScheduler = require(ReplicatedStorage.Shared.Systems)

local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)
local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)

--- Types ---
type ResourceChunkData = JecsCommon.ResourceChunkData

--- Variables ---
local World = JecsCommon.World
local ChildOf = Jecs.ChildOf
local Pair = Jecs.pair

local Grid = JecsCommon.Components.Grid
local ResourceChunk = JecsCommon.Components.ResourceChunk

local ChunkDebug = JecsCommon.Tags.ChunkDebug

local boxTemplate = Instance.new("Part")
boxTemplate.Size = Vector3.one * 64
boxTemplate.Anchored = true
boxTemplate.CanCollide = false
boxTemplate.CastShadow = false
boxTemplate.CanQuery = false
boxTemplate.Transparency = 1
local selectionBox = Instance.new("SelectionBox")
selectionBox.Adornee = boxTemplate
selectionBox.LineThickness = 0.0625
selectionBox.Color3 = Color3.new(1, 0, 0)
selectionBox.Parent = boxTemplate

--- Functions ---

--- Resource Chunk Debugger System ---
-- TODO: need a general way to track frontiers (one for terrain, one for resources, and one for chunk debugging)
World:added(ChunkDebug, function(chunkEntity: Jecs.Id)
	local chunk = World:get(chunkEntity, ResourceChunk) :: ResourceChunkData
	local gridEntity = World:target(chunkEntity, ChildOf) :: Jecs.Id
	local grid = World:get(gridEntity, Grid) :: Grid.Grid<any>
	local gridPosition = grid:ChunkIndexToGridPosition(chunk.ChunkIndex)
	local worldPosition = grid:GridPositionToWorldPosition(gridPosition)
	local box = boxTemplate:Clone()
	box.Position = worldPosition
	box.Parent = workspace.Terrain
end)
return true
