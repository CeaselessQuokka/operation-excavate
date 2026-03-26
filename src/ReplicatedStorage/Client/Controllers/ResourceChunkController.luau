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
}

do -- Controller initialization.
end

return ResourceChunkController
