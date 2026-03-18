--!strict
--- Services ---
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local Jecs = require(ReplicatedStorage.Packages.Jecs)

--- Types ---
type UsableCharacter = CharacterHelper.UsableCharacter

--- Variables ---
local Climbing = Jecs.tag()
local OwnedBy = Jecs.tag()
local Private = Jecs.tag()
local Loaded = Jecs.tag()
local Alive = Jecs.tag()

local World = Jecs.world(true)

--- Functions ---

--- Jecs Common ---
return {
	World = World,
	Components = {
		-- Player Characters
		Character = World:component() :: Jecs.Id<UsableCharacter?>,

		-- Climbing System
		Climbable = World:component() :: Jecs.Id<{
			ClimbSpeedMultiplier: number,
			GripDecayMultiplier: number,
		}?>,

		-- Gravity System
		Gravity = World:component() :: Jecs.Id<VectorForce?>,

		-- Items
		Item = World:component() :: Jecs.Id<{
			Type: string,
			CFrameIndex: number?,
			Stack: number?,
		}>,
	},
	Tags = {
		-- General
		OwnedBy = OwnedBy,
		Private = Private,
		Loaded = Loaded,

		-- Entity
		Alive = Alive,

		-- Climbing System
		Climbing = Climbing,
	},
}
