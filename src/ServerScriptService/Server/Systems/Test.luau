local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")
local Jecs = require(ReplicatedStorage.Packages.Jecs)

local world = Jecs.world()

local Pair = Jecs.pair

local Owns = world:component() :: Jecs.Id<{ Owner: Player }>
local player = world:entity()
local pet = world:entity()

local ownsPetPair = Pair(Owns, pet)
print("Owns-Pet Pair:", ownsPetPair, typeof(ownsPetPair), getmetatable(ownsPetPair), ownsPetPair == Pair(Owns, pet))

world:add(player, ownsPetPair)
print(world:has(player, ownsPetPair), world:has(player, Pair(Owns, pet)))

local Position = world:component() :: Jecs.Id<vector>

-- world:set(player, Position, vector.zero)

print("Position Component:", Position, typeof(Position), getmetatable(Position))
print("Entity:", player, typeof(player), getmetatable(player))
print("Entity Position:", world:get(player, Position))

local first = Jecs.pair_first(world, ownsPetPair)
local second = Jecs.pair_second(world, ownsPetPair)
print("First:", first, typeof(first), getmetatable(first))
print("Second:", second, typeof(second), getmetatable(second))

for entity, position in world:query(Jecs.Wildcard) do
	print("Queried Entity:", entity, typeof(entity), getmetatable(entity))
	print("Queried Position:", position, typeof(position), getmetatable(position))
end

task.wait()
StudioTestService:EndTest(true)

return true
