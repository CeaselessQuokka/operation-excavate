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

local ResourceChunk = JecsCommon.Components.ResourceChunk

--- Functions ---

--- Server Resource System ---
-- Get resource chunk cache.
local pausedThread = coroutine.running()
local resourceChunkArchetype: Jecs.Archetype
local resourceChunks: { ResourceChunkData }
local setCache: (() -> ())?
setCache = World:added(ResourceChunk, function(_, _, resourceChunk: ResourceChunkData)
	if setCache then
		-- Wait for archetype to be made, and then set cache.
		setCache()
		setCache = nil
		resourceChunkArchetype = World:query(ResourceChunk):cached():archetypes()[1]
		resourceChunks = resourceChunkArchetype.columns_map[ResourceChunk]
	end
end)

return true
