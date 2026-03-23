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

local ResourceChunk = JecsCommon.Components.ResourceChunk

--- Functions ---

--- Server Resource System ---
-- Get resource chunk cache.
local resourceChunkArchetype: Jecs.Archetype
local resourceChunks: { ResourceChunkData }
local setCache: (() -> ())?
setCache = World:added(ResourceChunk, function()
	if setCache then
		-- Set cache after archetype has been made.
		setCache()
		setCache = nil
		resourceChunkArchetype = World:query(ResourceChunk):cached():archetypes()[1]
		resourceChunks = resourceChunkArchetype.columns_map[ResourceChunk]
		-- System logic.
	end
end)

return true
