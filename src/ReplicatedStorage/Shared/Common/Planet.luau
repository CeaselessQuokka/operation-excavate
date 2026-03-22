--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local PlanetGenerator = require(ReplicatedStorage.Shared.Common.Classes.SphereGenerator.PlanetGenerator)

--- Types ---

--- Variables ---

--- Functions ---

--- Planet Common ---
local Planet = {
	Terrain = PlanetGenerator.new(67, 64),
}

return table.freeze(Planet)
