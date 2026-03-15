--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)

--- Types ---

--- Variables ---
local Climbing = Jecs.tag()

local World = Jecs.world(true)
--- Functions ---

--- Jecs Common ---
return {
	World = World,
	Components = {
		-- Climbing System
		Climbing = Climbing,
		Climbable = World:component() :: Jecs.Id<{
			ClimbSpeedMultiplier: number,
			GripDecayMultiplier: number,
		}?>,

		-- Gravity System
		Gravity = World:component() :: Jecs.Id<VectorForce>,
	},
}
