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
local MAX_RESOURCE_OFFSETS = Planet.MaxResourceOffsets
local RESOURCE_TYPE_TO_SIZE = Planet.ResourceIdToSize
local N_RESOURCE_TYPES = Planet.NResourceTypes

local TERRAIN_PARAMS = RaycastParams.new()
TERRAIN_PARAMS.IgnoreWater = true
TERRAIN_PARAMS.FilterType = Enum.RaycastFilterType.Include
TERRAIN_PARAMS:AddToFilter(Planet.RobloxTerrain) -- TODO: will need to add Buildings to this in the future (put it all under a folder and just set the folder)

local resourceGrid = Planet.Terrain.Grid
local resourceChunks: { [ChunkIndex]: ResourceChunkData } = {}

--- Functions ---
local diag = DiagnosticHelper.new("Chunk")
-- local function IsResourceExposed(typeId: number, offsetId: number, chunkCenter: Vector3): boolean
-- 	diag:StartTimer("IsResourceExposed")
-- 	local worldCFrame = ResourceOffsets[offsetId] + chunkCenter
-- 	local worldSize = RESOURCE_TYPE_TO_SIZE[typeId] / 2
-- 	local topLeftFrontCorner = (worldCFrame * CFrame.new(-worldSize.X, worldSize.Y, -worldSize.Z)).Position
-- 	local bottomRightBackCorner = (worldCFrame * CFrame.new(worldSize.X, -worldSize.Y, worldSize.Z)).Position
-- 	if DebugHelper.Raycast(topLeftFrontCorner, bottomRightBackCorner - topLeftFrontCorner, TERRAIN_PARAMS) then
-- 		local box = DebugHelper.Box(worldCFrame, worldSize * 2, { Color = Color3.new(0, 1, 0) })
-- 		diag:StopTimer("IsResourceExposed")
-- 		return true
-- 	else
-- 		local topRightFrontCorner = (worldCFrame * CFrame.new(worldSize.X, worldSize.Y, -worldSize.Z)).Position
-- 		local bottomLeftBackCorner = (worldCFrame * CFrame.new(-worldSize.X, -worldSize.Y, worldSize.Z)).Position
-- 		local isExposed = DebugHelper.Raycast(
-- 			topRightFrontCorner,
-- 			bottomLeftBackCorner - topRightFrontCorner,
-- 			TERRAIN_PARAMS
-- 		) ~= nil
-- 		diag:StopTimer("IsResourceExposed")
-- 		local box = DebugHelper.Box(
-- 			worldCFrame,
-- 			worldSize * 2,
-- 			{ Color = if isExposed then Color3.new(0, 1, 0) else Color3.new(1, 0, 0) }
-- 		)
-- 		return isExposed
-- 	end
-- end
local CAST_VECTORS = {
	(Vector3.one - Vector3.xAxis), --- TODO: do for each plane and then check all planes; need to heavily optimize this
	-- I may even need to do each cast in its own frame and have a solid locking mechanism, probably shouldn't even say the chunk data exists until it is fully processed
}
local function IsResourceExposed(typeId: number, offsetId: number, chunkCenter: Vector3): boolean
	local worldCFrame = ResourceOffsets[offsetId] + chunkCenter
	local worldSize = RESOURCE_TYPE_TO_SIZE[typeId]
	local halfWorldSize = worldSize / 2
	local left = worldCFrame * CFrame.new(-halfWorldSize.X, 0, 0)
	DebugHelper.Box(worldCFrame, worldSize)
	if
		DebugHelper.Blockcast(left, worldSize * (Vector3.one - Vector3.xAxis), worldCFrame.RightVector * worldSize.X)
	then
		return true
	end
	return false
end

-- TODO: properly validate IsResourceExposed and CanDropResource
-- TODO: add each chunk to a multithreading queue, and in that actor it task.waits every 32 resources or so

local function CanDropResource(offsetId: number, chunkCenter: Vector3): boolean
	diag:StartTimer("CanDropResource")
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
	local resources = chunkData.Resources
	local exposedResources = chunkData.ExposedResources
	local chunkCenter = resourceGrid:ChunkIndexToWorldPosition(chunkData.ChunkIndex)
	for resourceId in resources do
		local typeId = bit32.rshift(resourceId, RESOURCE_OFFSET_BITS)
		local offsetId = bit32.band(resourceId, MAX_RESOURCE_OFFSETS)
		if CanDropResource(offsetId, chunkCenter) then
			resources[resourceId] = nil
		elseif IsResourceExposed(typeId, offsetId, chunkCenter) then
			exposedResources[resourceId] = true
			local prefab = Planet.ResourceTypeToPrefab[Planet.ResourceIdToType[typeId]]:Clone()
			prefab:PivotTo(ResourceOffsets[offsetId] + chunkCenter)
			prefab.Parent = workspace
		end
		task.wait()
	end
	diag:StopTimer("ProcessChunk")
	-- diag:PrintBreakdown(true)
end

--- Planet Resource Service ---
local PlanetResourceService = {
	ResourceGrid = resourceGrid,
	Chunks = resourceChunks,
}

-- TODO: need to support shapes like box, ball, cone (drills), etc
function PlanetResourceService.Terraform(point: Vector3, radius: number)
	-- TODO: narrow search using items within radius? need to benchmark this
	radius = math.ceil(radius / 4) * 4
	local chunkIndex = resourceGrid:GetNearestChunkIndexAtPosition(point)
	local chunkData = resourceChunks[chunkIndex]
	if chunkData then
		local chunkCenter = resourceGrid:ChunkIndexToWorldPosition(chunkData.ChunkIndex)
		for resourceId in chunkData.Resources do
			local offsetId = bit32.band(resourceId, MAX_RESOURCE_OFFSETS)
			if CanDropResource(offsetId, chunkCenter) then
				chunkData.Resources[resourceId] = nil
				chunkData.ExposedResources[resourceId] = nil
			else
				local typeId = bit32.rshift(resourceId, RESOURCE_OFFSET_BITS)
				if not chunkData.ExposedResources[resourceId] and IsResourceExposed(typeId, offsetId, chunkCenter) then
					chunkData.ExposedResources[resourceId] = true
				end
			end
		end
	end
end

-- TODO: need a general way to track frontiers (one for terrain, one for resources, and one for chunk debugging)
function PlanetResourceService.CreateChunk(chunkIndex: number)
	local resources: { [ResourceId]: true } = table.create(64) :: any
	for i = 1, 16 do
		local typeId = math.random(1, N_RESOURCE_TYPES)
		local offsetId = math.random(1, N_OFFSETS)
		local resourceId = bit32.bor(bit32.lshift(typeId, RESOURCE_OFFSET_BITS), offsetId)
		resources[resourceId] = true
	end
	local chunkData = { ChunkIndex = chunkIndex, Resources = resources, ExposedResources = {} }
	task.delay(math.random() + 1, ProcessChunk, chunkData)
end

return PlanetResourceService
