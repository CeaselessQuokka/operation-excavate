--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)

local SystemScheduler = require(ReplicatedStorage.Shared.Systems)

local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)

--- Types ---
type ResourceChunkData = JecsCommon.ResourceChunkData

--- Variables ---
local World = JecsCommon.World
local ChildOf = Jecs.ChildOf
local Pair = Jecs.pair

local Grid = JecsCommon.Components.Grid
local ResourceChunk = JecsCommon.Components.ResourceChunk

local ReplicateTo = JecsCommon.Tags.ReplicateTo

--- Functions ---

--- Resource Chunk Replication System ---
World:added(ReplicateTo, function(chunkEntity: Jecs.Id)
	-- TODO: need to verify for multiple ppl?
	local chunk = World:get(chunkEntity, ResourceChunk) :: ResourceChunkData
	local playerEntity = World:target(chunkEntity, ReplicateTo, 1) :: Jecs.Id
	print(chunkEntity, playerEntity)
end)
return true
