--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)

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
local Player = JecsCommon.Components.Player

local ReplicateTo = JecsCommon.Tags.ReplicateTo

local onReplicateResourceChunk = Remote.Event("OnReplicateResourceChunk") :: Remote.ServerApi<(ResourceChunkData)>

--- Functions ---

--- Resource Chunk Replication System ---
World:added(ReplicateTo, function(chunkEntity: Jecs.Id, relationship: any)
	local chunk = World:get(chunkEntity, ResourceChunk) :: ResourceChunkData
	local playerEntity = Jecs.pair_second(World, relationship)
	local player = World:get(playerEntity, Player) :: Player
	onReplicateResourceChunk:Fire(player, chunk)
end)
return true
