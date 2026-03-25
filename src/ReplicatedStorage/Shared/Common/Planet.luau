--!strict
--- Services ---
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--- Imports ---
local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)

--- Types ---
export type ChunkIndex = number
export type ResourceId = number -- A number composed of the resource type (14 bits) and Vector3 offset relative to the chunk (16 bits).
export type ResourceType = string
export type ResourceChunkData = {
	ChunkIndex: number,
	Resources: { [ResourceId]: true }, -- Array of resource IDs.
	ExposedResources: { [ResourceId]: true }?, -- Resources that are exposed in the chunk.
}

--- Variables ---
local CHUNK_SIZE = 64
local RESOURCE_OFFSET_BITS = 16

local N_RESOURCE_TYPES = 0
local RESOURCE_TYPE_TO_PREFAB: { [ResourceType]: Model } = {}
local RESOURCE_TYPE_TO_ID: { [ResourceType]: ResourceId } = {}
local RESOURCE_ID_TO_TYPE: { [ResourceId]: ResourceType } = {}
local RESOURCE_ID_TO_SIZE: { [ResourceId]: Vector3 } = {}
for _, resource in CollectionService:GetTagged("Resource") :: { Model } do
	assert(not RESOURCE_TYPE_TO_PREFAB[resource.Name], `Duplicate resource type: "{resource}"`)
	local id = resource:GetAttribute("ResourceTypeId") :: ResourceId
	assert(not RESOURCE_ID_TO_TYPE[id], `Duplicate resource ID: "{id}" on resource "{resource}"`)
	local name = resource.Name
	RESOURCE_TYPE_TO_PREFAB[name] = resource
	RESOURCE_TYPE_TO_ID[name] = id
	RESOURCE_ID_TO_TYPE[id] = name
	RESOURCE_ID_TO_SIZE[id] = resource:GetExtentsSize()
	N_RESOURCE_TYPES += 1
end

--- Planet Common ---
local Planet = {
	RobloxTerrain = Workspace.Terrain or Workspace:GetPropertyChangedSignal("Terrain"):Wait(),
	ChunkSize = CHUNK_SIZE,
	Terrain = PlanetGenerator.new(67, CHUNK_SIZE, true),
	ResourceOffsetBits = RESOURCE_OFFSET_BITS,
	MaxResourceTypes = (2 ^ 14) - 1,
	MaxResourceOffsets = (2 ^ RESOURCE_OFFSET_BITS) - 1,
	ResourceTypeToPrefab = RESOURCE_TYPE_TO_PREFAB,
	ResourceTypeToId = RESOURCE_TYPE_TO_ID,
	ResourceIdToType = RESOURCE_ID_TO_TYPE,
	ResourceIdToSize = RESOURCE_ID_TO_SIZE,
	NResourceTypes = N_RESOURCE_TYPES,
}

return table.freeze(Planet)
