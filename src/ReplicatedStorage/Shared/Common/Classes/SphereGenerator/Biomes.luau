--[[
	Biome definitions and selection for sphere terrain generation.
	Maps temperature, moisture, and mountainness values to biome types,
	each with characteristic terrain materials and height behavior.

	Temperature is derived from latitude (poles = cold, equator = hot) with noise perturbation.
	Moisture is purely noise-driven. High mountainness overrides other biomes with Mountain.
]]

--!strict

--- Types ---
export type Biome = {
	Name: string,
	SurfaceMaterial: Enum.Material,
	SubsurfaceMaterial: Enum.Material,
	DeepMaterial: Enum.Material,
	ShoreMaterial: Enum.Material,
	HeightScale: number,
}

--- Variables ---
local BIOME_LIST: { Biome } = {
	{
		Name = "Desert",
		SurfaceMaterial = Enum.Material.Sand,
		SubsurfaceMaterial = Enum.Material.Sandstone,
		DeepMaterial = Enum.Material.Rock,
		ShoreMaterial = Enum.Material.Sand,
		HeightScale = 0.15,
	},
	{
		Name = "Savanna",
		SurfaceMaterial = Enum.Material.Ground,
		SubsurfaceMaterial = Enum.Material.Sandstone,
		DeepMaterial = Enum.Material.Rock,
		ShoreMaterial = Enum.Material.Sand,
		HeightScale = 0.2,
	},
	{
		Name = "TropicalForest",
		SurfaceMaterial = Enum.Material.LeafyGrass,
		SubsurfaceMaterial = Enum.Material.Mud,
		DeepMaterial = Enum.Material.Rock,
		ShoreMaterial = Enum.Material.Sand,
		HeightScale = 0.3,
	},
	{
		Name = "Grassland",
		SurfaceMaterial = Enum.Material.Grass,
		SubsurfaceMaterial = Enum.Material.Ground,
		DeepMaterial = Enum.Material.Rock,
		ShoreMaterial = Enum.Material.Sand,
		HeightScale = 0.15,
	},
	{
		Name = "Plains",
		SurfaceMaterial = Enum.Material.Grass,
		SubsurfaceMaterial = Enum.Material.Ground,
		DeepMaterial = Enum.Material.Rock,
		ShoreMaterial = Enum.Material.Sand,
		HeightScale = 0.08,
	},
	{
		Name = "Forest",
		SurfaceMaterial = Enum.Material.LeafyGrass,
		SubsurfaceMaterial = Enum.Material.Ground,
		DeepMaterial = Enum.Material.Rock,
		ShoreMaterial = Enum.Material.Sand,
		HeightScale = 0.25,
	},
	{
		Name = "Swamp",
		SurfaceMaterial = Enum.Material.Mud,
		SubsurfaceMaterial = Enum.Material.Mud,
		DeepMaterial = Enum.Material.Slate,
		ShoreMaterial = Enum.Material.Mud,
		HeightScale = 0.05,
	},
	{
		Name = "Tundra",
		SurfaceMaterial = Enum.Material.Ground,
		SubsurfaceMaterial = Enum.Material.Rock,
		DeepMaterial = Enum.Material.Slate,
		ShoreMaterial = Enum.Material.Ground,
		HeightScale = 0.12,
	},
	{
		Name = "Taiga",
		SurfaceMaterial = Enum.Material.Snow,
		SubsurfaceMaterial = Enum.Material.Ground,
		DeepMaterial = Enum.Material.Rock,
		ShoreMaterial = Enum.Material.Snow,
		HeightScale = 0.2,
	},
	{
		Name = "IceCap",
		SurfaceMaterial = Enum.Material.Snow,
		SubsurfaceMaterial = Enum.Material.Ice,
		DeepMaterial = Enum.Material.Glacier,
		ShoreMaterial = Enum.Material.Ice,
		HeightScale = 0.1,
	},
	{
		Name = "Mountain",
		SurfaceMaterial = Enum.Material.Rock,
		SubsurfaceMaterial = Enum.Material.Slate,
		DeepMaterial = Enum.Material.Basalt,
		ShoreMaterial = Enum.Material.Rock,
		HeightScale = 0.6,
	},
}

local BIOME_MAP: { [string]: Biome } = {}
for _, biome in BIOME_LIST do
	BIOME_MAP[biome.Name] = biome
end

-- Selection grid: rows = temperature (cold → hot), columns = moisture (dry → wet)
-- 5 temperature bands weighted so most of the habitable zone gets green biomes
local BIOME_GRID: { { string } } = {
	{ "IceCap", "IceCap", "Taiga" },
	{ "Tundra", "Taiga", "Forest" },
	{ "Grassland", "Forest", "TropicalForest" },
	{ "Plains", "Forest", "Swamp" },
	{ "Desert", "Savanna", "TropicalForest" },
}

--- Biomes ---
local Biomes = {}

function Biomes.GetBiome(temperature: number, moisture: number, mountainness: number): Biome
	if mountainness > 0.35 then
		return BIOME_MAP["Mountain"]
	end

	temperature = math.clamp(temperature, 0, 0.999)
	moisture = math.clamp(moisture, 0, 0.999)

	local tempIdx = math.floor(temperature * 5) + 1
	local moistIdx = math.floor(moisture * 3) + 1

	return BIOME_MAP[BIOME_GRID[tempIdx][moistIdx]]
end

function Biomes.GetBiomeByName(name: string): Biome?
	return BIOME_MAP[name]
end

return table.freeze(Biomes)
