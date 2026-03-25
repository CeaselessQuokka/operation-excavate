--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

--- Imports ---
local PlayerService = require(script.Parent.PlayerService)

local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Signal = require(ReplicatedStorage.Packages.Signal)

local DebugHelper = require(ReplicatedStorage.Shared.Helpers.DebugHelper)
local DiagnosticHelper = require(ReplicatedStorage.Shared.Helpers.DiagnosticHelper)
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
local N_OFFSETS = #ResourceOffsets
local RESOURCE_OFFSET_BITS = Planet.ResourceOffsetBits
local MAX_RESOURCE_TYPES = Planet.MaxResourceTypes
local MAX_RESOURCE_OFFSETS = Planet.MaxResourceOffsets
local RESOURCE_TYPE_TO_SIZE = Planet.ResourceIdToSize
local N_RESOURCE_TYPES = Planet.NResourceTypes

local TERRAIN_PARAMS = RaycastParams.new()
TERRAIN_PARAMS.IgnoreWater = true
TERRAIN_PARAMS.FilterType = Enum.RaycastFilterType.Include
TERRAIN_PARAMS:AddToFilter(Planet.RobloxTerrain) -- TODO: will need to add Buildings to this in the future (put it all under a folder and just set the folder)

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
local diag = DiagnosticHelper.new("Chunk")
local function IsResourceExposed(resourceId: ResourceId, chunkCenter: Vector3): boolean
	diag:StartTimer("IsResourceExposed")
	local typeId = bit32.rshift(resourceId, RESOURCE_OFFSET_BITS)
	local offsetId = bit32.band(resourceId, MAX_RESOURCE_OFFSETS)
	local worldCFrame = ResourceOffsets[offsetId] + chunkCenter
	local worldSize = RESOURCE_TYPE_TO_SIZE[typeId] / 2
	local topLeftFrontCorner = (worldCFrame * CFrame.new(-worldSize.X, worldSize.Y, -worldSize.Z)).Position
	local bottomRightBackCorner = (worldCFrame * CFrame.new(worldSize.X, -worldSize.Y, worldSize.Z)).Position
	if Workspace:Raycast(topLeftFrontCorner, bottomRightBackCorner - topLeftFrontCorner, TERRAIN_PARAMS) then
		diag:StopTimer("IsResourceExposed")
		return true
	else
		local topRightFrontCorner = (worldCFrame * CFrame.new(worldSize.X, worldSize.Y, -worldSize.Z)).Position
		local bottomLeftBackCorner = (worldCFrame * CFrame.new(-worldSize.X, -worldSize.Y, worldSize.Z)).Position
		local isExposed = Workspace:Raycast(
			topRightFrontCorner,
			bottomLeftBackCorner - topRightFrontCorner,
			TERRAIN_PARAMS
		) ~= nil
		diag:StopTimer("IsResourceExposed")
		return isExposed
	end
end

-- TODO: properly validate IsResourceExposed and CanDropResource
-- TODO: add each chunk to a multithreading queue, and in that actor it task.waits every 32 resources or so

local chunks: { [ChunkIndex]: Jecs.Entity<any> } = {} -- TODO: rethink how to do this
local realModels: { [ResourceId]: Model } = {} -- TODO: rethink how to do this

local function CanDropResource(resourceId: ResourceId, chunkCenter: Vector3): boolean
	diag:StartTimer("CanDropResource")
	local offsetId = bit32.band(resourceId, MAX_RESOURCE_OFFSETS)
	local from = ResourceOffsets[offsetId].Position + chunkCenter
	local direction = from.Unit
	local to = direction * -40000
	local floorResult = Workspace:Raycast(from, to, TERRAIN_PARAMS)
	if floorResult then
		local newFrom = floorResult.Position
		local canDrop = Workspace:Raycast(newFrom, direction * (newFrom - from).Magnitude, TERRAIN_PARAMS) == nil
		diag:StopTimer("CanDropResource")
		return canDrop
	end
	diag:StopTimer("CanDropResource")
	return false
end

-- Initially identity all exposed resources, and discard ones that are droppable.
local function ProcessChunk(chunkData: ResourceChunkData)
	diag:StartTimer("ProcessChunk")
	local exposedResources: { [ResourceId]: true } = {}
	local chunkCenter = Planet.Terrain.Grid:ChunkIndexToWorldPosition(chunkData.ChunkIndex)
	for resourceId in chunkData.Resources do
		local typeId = bit32.rshift(resourceId, RESOURCE_OFFSET_BITS)
		local offsetId = bit32.band(resourceId, MAX_RESOURCE_OFFSETS)
		if CanDropResource(resourceId, chunkCenter) then
			chunkData.Resources[resourceId] = nil
		elseif IsResourceExposed(resourceId, chunkCenter) then
			exposedResources[resourceId] = true
			local prefab = Planet.ResourceTypeToPrefab[Planet.ResourceIdToType[typeId]]:Clone()
			prefab:PivotTo(ResourceOffsets[offsetId] + chunkCenter)
			prefab.Parent = workspace
			realModels[resourceId] = prefab
		end
	end
	chunkData.ExposedResources = exposedResources
	diag:StopTimer("ProcessChunk")
	-- diag:PrintBreakdown(true)
end

--- Planet Resource Service ---
local PlanetResourceService = {
	GridEntity = gridEntity,
	ResourceGrid = Planet.Terrain.Grid,
}

function PlanetResourceService.PermissionTerraform(player: Player, point: Vector3): boolean
	return true
end

-- TODO: need to support shapes like box, ball, cone (drills), etc
function PlanetResourceService.Terraform(point: Vector3, radius: number)
	radius = math.ceil(radius / 4) * 4
	local chunkIndex = Planet.Terrain.Grid:GetNearestChunkIndexAtPosition(point)
	local chunkEntity = chunks[chunkIndex]
	if chunkEntity then
		local chunkData = World:get(chunkEntity, ResourceChunk)
		if chunkData then
			local chunkCenter = Planet.Terrain.Grid:ChunkIndexToWorldPosition(chunkData.ChunkIndex)
			for resourceId in chunkData.Resources do
				if CanDropResource(resourceId, chunkCenter) then
					chunkData.Resources[resourceId] = nil
					if chunkData.ExposedResources then
						chunkData.ExposedResources[resourceId] = nil
					end
					if realModels[resourceId] then
						local gravitySet = false
						for _, part in realModels[resourceId]:QueryDescendants("BasePart") do
							if not gravitySet then
								gravitySet = true
								local gravityEntity = World:entity()
								local movementAttachment: Attachment = (ServerStorage :: any).Assets.Character.MovementAttachment:Clone()
								local gravityForce: VectorForce = (ServerStorage :: any).Assets.Character.Gravity:Clone()
								movementAttachment.Parent = part
								gravityForce.Attachment0 = movementAttachment
								gravityForce.Parent = part
								World:set(gravityEntity, JecsCommon.Components.Gravity, gravityForce)
							end
							part.Anchored = false
						end
					end
				else
					if
						(not chunkData.ExposedResources or not chunkData.ExposedResources[resourceId])
						and IsResourceExposed(resourceId, chunkCenter)
					then
						if chunkData.ExposedResources then
							chunkData.ExposedResources[resourceId] = true
						end
						local typeId = bit32.rshift(resourceId, RESOURCE_OFFSET_BITS)
						local offsetId = bit32.band(resourceId, MAX_RESOURCE_OFFSETS)
						local prefab = Planet.ResourceTypeToPrefab[Planet.ResourceIdToType[typeId]]:Clone()
						prefab:PivotTo(ResourceOffsets[offsetId] + chunkCenter)
						prefab.Parent = workspace
						realModels[resourceId] = prefab
					end
				end
			end
		end
	end
end

-- TODO: need a general way to track frontiers (one for terrain, one for resources, and one for chunk debugging)
function PlanetResourceService.CreateChunk(chunkIndex: number)
	local chunkEntity = World:entity()
	World:add(chunkEntity, Pair(ChildOf, PlanetResourceService.GridEntity))
	local resources: { [ResourceId]: true } = table.create(512) :: any
	for i = 1, 64 do
		local typeId = math.random(1, N_RESOURCE_TYPES)
		local offsetId = math.random(1, N_OFFSETS)
		local resourceId = bit32.bor(bit32.lshift(typeId, RESOURCE_OFFSET_BITS), offsetId)
		resources[resourceId] = true
	end
	local chunkData = { ChunkIndex = chunkIndex, Resources = resources } :: ResourceChunkData
	World:set(chunkEntity, ResourceChunk, chunkData)
	chunks[chunkIndex] = chunkEntity
	task.delay(math.random() + 1, ProcessChunk, chunkData)
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
