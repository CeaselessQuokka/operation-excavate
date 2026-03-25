--!strict
--- Services ---
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)

--- Types ---
export type ChunkIndex = number
export type ResourceId = number -- A number composed of the resource type (14 bits) and Vector3 offset relative to the chunk (16 bits).
export type ResourceChunkData = {
	ChunkIndex: number,
	Resources: { [ResourceId]: true }, -- Array of resource IDs.
	ExposedResources: { [ResourceId]: true }?, -- Resources that are exposed in the chunk.
}

--- Variables ---
local CHUNK_SIZE = 64
local RESOURCE_OFFSET_BITS = 16

local RESOURCE_TYPE_TO_ID: { [string]: number } = {}
local RESOURCE_ID_TO_TYPE: { [number]: string } = {}
for _, resource in CollectionService:GetTagged("Resource") do
	-- TODO: add ID validation to ensure sequential and no dupes
	local name = resource.Name
	local id = resource:GetAttribute("ResourceTypeId") :: number
	RESOURCE_TYPE_TO_ID[name] = id
	RESOURCE_ID_TO_TYPE[id] = name
end

--- Planet Common ---
local Planet = {
	ChunkSize = CHUNK_SIZE,
	Terrain = PlanetGenerator.new(67, CHUNK_SIZE),
	ResourceOffsetBits = RESOURCE_OFFSET_BITS,
	MaxResourceTypes = (2 ^ 14) - 1,
	MaxResourceOffsets = (2 ^ RESOURCE_OFFSET_BITS) - 1,
	ResourceTypeToId = RESOURCE_TYPE_TO_ID,
	ResourceIdToType = RESOURCE_ID_TO_TYPE,
}

return table.freeze(Planet)
