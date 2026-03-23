--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)
local Signal = require(ReplicatedStorage.Packages.Signal)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local ThreadingHelper = require(ReplicatedStorage.Shared.Helpers.ThreadingHelper)

local PlayerModule = (require)(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))

--- Types ---
type Character = CharacterHelper.Character
type UsableCharacter = CharacterHelper.UsableCharacter
type Signal<T...> = Signal.Signal<T...>
type SignalConnection = Signal.Connection

export type Area = BasePart | { CFrame: CFrame, Size: Vector3 }
export type AreaCheckMode = "Box" | "XZ" | "Magnitude"
export type AreaOptions = {
	CheckMode: AreaCheckMode?,
	YThreshold: number?,
	Radius: number?,
	CheckInterval: number?,
}

--- Variables ---
local localPlayer = Players.LocalPlayer

--- Player Controller ---
local PlayerController = {
	Name = "PlayerController",

	Player = localPlayer,
	PlayerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui,
	Character = nil :: UsableCharacter?,

	OnCharacterAdded = Signal.new() :: Signal<UsableCharacter>,
	OnDied = Signal.new() :: Signal<>,
}

function PlayerController.CharacterAdded(callback: (character: UsableCharacter) -> ()): SignalConnection
	if localPlayer.Character then
		task.defer(callback, localPlayer.Character)
	end
	return PlayerController.OnCharacterAdded:Connect(callback)
end

function PlayerController.WaitForQuery(query: string, character: UsableCharacter?): any
	-- Resolve character.
	character = character or PlayerController.Character or localPlayer.CharacterAdded:Wait()
	if not character then
		return nil
	end

	-- Resolve instance.
	while character == localPlayer.Character do
		local instance = character:QueryDescendants(query)[1]
		if instance then
			return instance
		end
		ThreadingHelper.WaitForAny(
			nil,
			character.DescendantAdded,
			localPlayer.CharacterRemoving,
			localPlayer.CharacterAdded,
			localPlayer.AncestryChanged
		)
	end
	warn(`[{script.Name}] Failed to find instance with query "{query}" in character.`)
	return nil
end

function PlayerController.DisableControls()
	PlayerModule:GetControls():Disable()
end

function PlayerController.EnableControls()
	PlayerModule:GetControls():Enable()
end

do -- Initialize controller.
	local function OnCharacterAdded(character: Character)
		local usable = false
		while character == localPlayer.Character do
			task.wait()
			if CharacterHelper.IsUsable(character) then
				usable = true
				break
			end
		end
		if not usable then
			return
		end

		local humanoid = CharacterHelper.GetHumanoid(character) :: Humanoid
		humanoid.Died:Once(function()
			PlayerController.Character = nil
			PlayerController.OnDied:FireDeferred()
		end)

		PlayerController.Character = character :: UsableCharacter
		PlayerController.OnCharacterAdded:FireDeferred(character :: UsableCharacter)
	end

	localPlayer.CharacterAdded:Connect(OnCharacterAdded)
	if localPlayer.Character then
		task.defer(OnCharacterAdded, localPlayer.Character)
	end

	local remote = Remote.Event("OnRequestTerraform") :: Remote.ClientApi<(Vector3, number)>
	local mouse = PlayerController.Player:GetMouse()
	mouse.Button1Down:Connect(function()
		remote:Fire(mouse.Hit.Position, 4)
	end)
end

return PlayerController
