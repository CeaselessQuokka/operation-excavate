--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)
local Signal = require(ReplicatedStorage.Packages.Signal)

local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)

--- Types ---
type Signal<Params...> = Signal.Signal<Params...>
type SignalConnection = { Disconnect: (any) -> () }
type ClientApi<Params..., Return...> = Remote.ClientApi<Params..., Return...>
type ResourceChunkData = JecsCommon.ResourceChunkData

--- Variables ---
local World = JecsCommon.World

local ResourceChunk = JecsCommon.Components.ResourceChunk

--- Functions ---

--- Resource Chunk Controller ---
local ResourceChunkController = {
	OnSignal = Signal.new() :: Signal<>,

	-- OnResourceGridSync = Remote.Event("OnResourceGridSync") :: ClientApi<()>,
	OnReplicateResourceChunk = Remote.Event("OnReplicateResourceChunk") :: ClientApi<(ResourceChunkData)>,
}

function ResourceChunkController.Method(...: any): ...any end

do -- Controller initialization.
	ResourceChunkController.OnReplicateResourceChunk:Connect(function(chunkData)
		local chunk = World:entity()
		World:set(chunk, ResourceChunk, chunkData)
		-- print("GOT DATA", chunkData)
	end)
end

return ResourceChunkController
