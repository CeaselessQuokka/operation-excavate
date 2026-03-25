--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local PlayerService = require(script.Parent.PlayerService)

local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Signal = require(ReplicatedStorage.Packages.Signal)

local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local Planet = require(ReplicatedStorage.Shared.Common.Planet)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)
local ResourceOffsets = require(ReplicatedStorage.Shared.Common.ResourceOffsets)

--- Types ---
type ChunkIndex = Planet.ChunkIndex
type ResourceId = Planet.ResourceId
type ResourceChunkData = Planet.ResourceChunkData
type Signal<Params...> = Signal.Signal<Params...>
type SignalConnection = { Disconnect: (any) -> () }
type ServerApi<Params..., Return...> = Remote.ServerApi<Params..., Return...>

--- Variables ---
local N_RESOURCE_TYPES = JecsCommon.NResourceTypes
local N_OFFSETS = #ResourceOffsets
local RESOURCE_OFFSET_BITS = Planet.ResourceOffsetBits
local MAX_RESOURCE_TYPES = Planet.MaxResourceTypes
local MAX_RESOURCE_OFFSETS = Planet.MaxResourceOffsets

local World = JecsCommon.World
local ChildOf = Jecs.ChildOf
local Pair = Jecs.pair

local Grid = JecsCommon.Components.Grid
local Player = JecsCommon.Components.Player
local ResourceChunk = JecsCommon.Components.ResourceChunk

local ReplicateTo = JecsCommon.Tags.ReplicateTo

local gridEntity = World:entity()
World:set(gridEntity, Grid, Planet.Terrain.Grid)

local OnResourceGridSync = Remote.Event("OnResourceGridSync") :: ServerApi<(Vector3, Vector3)>
local onReplicateResourceChunk = Remote.Event("OnReplicateResourceChunk") :: Remote.ServerApi<(ResourceChunkData)>
local onRemoveReplicatedResourceChunk =
	Remote.Event("OnRemoveReplicatedResourceChunk") :: Remote.ServerApi<(ChunkIndex)>

--- Functions ---
local function IsResourceExposed(): boolean end

-- Initially identity all exposed resources, and discard ones that are droppable.
local function ProcessChunk(chunkData: ResourceChunkData) end

--- Planet Resource Service ---
local PlanetResourceService = {
	GridEntity = gridEntity,
	ResourceGrid = Planet.Terrain.Grid,
}

function PlanetResourceService.PermissionTerraform(player: Player, point: Vector3): boolean
	return true
end

-- TODO: need to support shapes like box, ball, cone (drills), etc
function PlanetResourceService.Terraform(point: Vector3, radius: number) end

-- TODO: need a general way to track frontiers (one for terrain, one for resources, and one for chunk debugging)
function PlanetResourceService.CreateChunk(chunkIndex: number)
	local chunkEntity = World:entity()
	World:add(chunkEntity, Pair(ChildOf, PlanetResourceService.GridEntity))
	local resources: { [ResourceId]: true } = table.create(512) :: any
	for i = 1, 512 do
		local typeId = math.random(1, N_RESOURCE_TYPES)
		local offsetId = math.random(1, N_OFFSETS)
		local resourceId = bit32.bor(bit32.lshift(typeId, RESOURCE_OFFSET_BITS), offsetId)
		resources[resourceId] = true
	end
	World:set(chunkEntity, ResourceChunk, { ChunkIndex = chunkIndex, Resources = resources } :: ResourceChunkData)
	-- local playerEntity = PlayerService.GetPlayerEntity(game.Players:FindFirstChild("CeaselessQuokka")) :: Jecs.Id
	-- World:add(chunkEntity, Pair(ReplicateTo, playerEntity)) -- TODO: remove
	-- World:add(chunkEntity, JecsCommon.Tags.ChunkDebug) -- TODO: remove
end

do -- Service initialization.
	PlayerService.PlayerAdded(function(player)
		local grid = PlanetResourceService.ResourceGrid
		OnResourceGridSync:Fire(player, grid.Center, grid.GridWorldSize)
	end)

	-- Handle resource chunk replication to clients.
	-- World:added(ReplicateTo, function(chunkEntity: Jecs.Entity<any>, relationship: any)
	-- 	local chunkData = World:get(chunkEntity, ResourceChunk)
	-- 	if chunkData then
	-- 		local playerEntity = Jecs.pair_second(World, relationship)
	-- 		local player = World:get(playerEntity, Player)
	-- 		if player then
	-- 			onReplicateResourceChunk:Fire(player, chunkData)
	-- 		end
	-- 	end
	-- end)
	-- World:removed(ReplicateTo, function(chunkEntity: Jecs.Entity<any>, relationship: any)
	-- 	local chunkData = World:get(chunkEntity, ResourceChunk)
	-- 	if chunkData then
	-- 		local playerEntity = Jecs.pair_second(World, relationship)
	-- 		local player = World:get(playerEntity, Player)
	-- 		if player then
	-- 			onRemoveReplicatedResourceChunk:Fire(player, chunkData.ChunkIndex)
	-- 		end
	-- 	end
	-- end)
end

return PlanetResourceService
