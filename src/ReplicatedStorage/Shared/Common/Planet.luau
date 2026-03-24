--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)

--- Types ---

--- Variables ---
local CHUNK_SIZE = 64

--- Functions ---

--- Planet Common ---
local Planet = {
	ChunkSize = CHUNK_SIZE,
	Terrain = PlanetGenerator.new(67, CHUNK_SIZE),
	MaxResourceTypes = (2 ^ 14) - 1,
}

return table.freeze(Planet)
