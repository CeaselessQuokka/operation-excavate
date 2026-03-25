--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Signal = require(ReplicatedStorage.Packages.Signal)

local Grid = require(ReplicatedStorage.Shared.Common.Classes.Grid)
local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local Planet = require(ReplicatedStorage.Shared.Common.Planet)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)

--- Types ---
type ChunkIndex = Planet.ChunkIndex
type ResourceChunkData = Planet.ResourceChunkData
type Signal<Params...> = Signal.Signal<Params...>
type SignalConnection = { Disconnect: (any) -> () }
type ClientApi<Params..., Return...> = Remote.ClientApi<Params..., Return...>

--- Variables ---
local World = JecsCommon.World
local Pair = Jecs.pair

local ResourceChunk = JecsCommon.Components.ResourceChunk
local GridComponent = JecsCommon.Components.Grid

local ChildOf = Jecs.ChildOf

--- Functions ---

--- Resource Chunk Controller ---
local ResourceChunkController = {
	GridEntity = nil :: Jecs.Entity<any>?,
	Grid = nil :: Grid.Grid?,
	Chunks = {} :: { [ChunkIndex]: Jecs.Entity<any> },

	OnResourceGridSynced = Signal.new() :: Signal<Grid.Grid, Jecs.Entity<any>>,

	OnResourceGridSync = Remote.Event("OnResourceGridSync") :: ClientApi<(Vector3, Vector3)>,
	OnReplicateResourceChunk = Remote.Event("OnReplicateResourceChunk") :: ClientApi<(ResourceChunkData)>,
	OnRemoveReplicatedResourceChunk = Remote.Event("OnRemoveReplicatedResourceChunk") :: ClientApi<(ChunkIndex)>,
}

function ResourceChunkController.ResourceGridSynced(callback: (Grid.Grid, Jecs.Entity<any>) -> ())
	if ResourceChunkController.GridEntity and ResourceChunkController.Grid then
		task.defer(callback, ResourceChunkController.Grid, ResourceChunkController.GridEntity)
	else
		ResourceChunkController.OnResourceGridSynced:Once(callback)
	end
end

do -- Controller initialization.
	ResourceChunkController.OnResourceGridSync:Connect(function(center, gridWorldSize)
		local gridEntity = World:entity()
		local grid = Grid.new(center, gridWorldSize, Planet.ChunkSize)
		World:set(gridEntity, GridComponent, grid)
		ResourceChunkController.OnResourceGridSynced:FireDeferred(grid, gridEntity)
	end)
	ResourceChunkController.ResourceGridSynced(function(grid, gridEntity)
		ResourceChunkController.OnReplicateResourceChunk:Connect(function(chunkData)
			local chunkEntity = World:entity()
			World:add(chunkEntity, Pair(ChildOf, gridEntity))
			World:set(chunkEntity, ResourceChunk, chunkData)
			ResourceChunkController.Chunks[chunkData.ChunkIndex] = chunkEntity
			print("REPLICATED")
		end)
		ResourceChunkController.OnRemoveReplicatedResourceChunk:Connect(function(chunkIndex)
			local chunkEntity = ResourceChunkController.Chunks[chunkIndex]
			ResourceChunkController.Chunks[chunkIndex] = nil
			if chunkEntity then
				World:delete(chunkEntity)
			end
		end)
	end)
end

return ResourceChunkController
