--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Remote = require(ReplicatedStorage.Shared.Common.Classes.Remote)
local Signal = require(ReplicatedStorage.Packages.Signal)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local ThreadingHelper = require(ReplicatedStorage.Shared.Helpers.ThreadingHelper)

local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)

--- Types ---
type UsableCharacter = CharacterHelper.UsableCharacter
type Signal<Params...> = Signal.Signal<Params...>
type SignalConnection = { Disconnect: (any) -> () }
type ServerApi<Params..., Return...> = Remote.ServerApi<Params..., Return...>

--- Variables ---
local World = JecsCommon.World
local CharacterComponent = JecsCommon.Components.Character
local GravityComponent = JecsCommon.Components.Gravity
local AliveTag = JecsCommon.Tags.Alive

local jecs = {} :: { [Player]: { Character: Jecs.Id, Gravity: Jecs.Id } }
local characterAddedEvents = {} :: { [Player]: Signal<UsableCharacter, Player> }
local diedEvents = {} :: { [Player]: Signal<> }

--- Functions ---
function InitializeCharacter(character: UsableCharacter, player: Player)
	local rootPart = character.HumanoidRootPart
	do -- Create custom movement attached, and custom gravity force.
		local movementAttachment: Attachment = (ServerStorage :: any).Assets.Character.MovementAttachment:Clone()
		local gravityForce: VectorForce = (ServerStorage :: any).Assets.Character.Gravity:Clone()
		movementAttachment.Parent = rootPart
		gravityForce.Attachment0 = movementAttachment
		gravityForce.Parent = rootPart
		World:set(jecs[player].Gravity, GravityComponent, gravityForce)
	end

	do -- Create custom movement controller.
		local controller: ControllerManager & {
			AirController: AirController,
			GroundController: GroundController,
			GroundSensor: ControllerPartSensor,
		} = (
			ServerStorage :: any
		).Assets.Character.ControllerManager:Clone()
		local airController = controller.AirController
		local groundController = controller.GroundController
		local groundSensor = controller.GroundSensor
		groundSensor.SearchDistance = (rootPart.Size.Y / 2) + character.Humanoid.HipHeight + 1
		groundController.GroundOffset = character.Humanoid.HipHeight
		controller.RootPart = rootPart
		airController.Parent = controller
		groundSensor.Parent = rootPart
		controller.Parent = character
	end
end

--- Player Service ---
local PlayerService = {
	Characters = {} :: { [Player]: UsableCharacter },

	OnCharacterAdded = Signal.new() :: Signal<UsableCharacter, Player>,
	OnDied = Signal.new() :: Signal<Player>,

	OnResetRequested = Remote.Event("OnResetRequested", {
		CooldownPerFire = 10, -- TODO: change to 5 after testing.
	}) :: ServerApi<()>,
}

-- Loads the player's character if not already loaded, then returns it.
function PlayerService.LoadCharacter(player: Player, timeout: number?, onlyLoadIfNeeded: boolean?): UsableCharacter?
	local character = PlayerService.Characters[player]
	if onlyLoadIfNeeded == true and CharacterHelper.IsUsable(character) then
		return character
	end

	PlayerService.Characters[player] = nil
	player:LoadCharacterAsync()
	return PlayerService.GetCharacter(player, true, timeout)
end

function PlayerService.GetCharacter(player: Player, await: boolean?, timeout: number?): UsableCharacter?
	local character = PlayerService.Characters[player]
	if character then
		return character
	elseif not await then
		return nil
	end

	timeout = timeout or 6
	local startTime = os.clock()
	while player.Parent and os.clock() - startTime < timeout and not PlayerService.Characters[player] do
		ThreadingHelper.WaitForAny(timeout, PlayerService.OnCharacterAdded, player.AncestryChanged)
	end
	return PlayerService.Characters[player]
end

function PlayerService.PlayerAdded(callback: (Player) -> ())
	Players.PlayerAdded:Connect(callback)
	for _, player in Players:GetPlayers() do
		task.defer(callback, player)
	end
end

function PlayerService.CharacterAdded(player: Player, callback: (UsableCharacter, Player) -> ()): SignalConnection
	local character = PlayerService.Characters[player]
	if character then
		task.defer(callback, character, player)
	end
	local addedSignal = characterAddedEvents[player]
	if not addedSignal then
		addedSignal = Signal.new()
		characterAddedEvents[player] = addedSignal
	end
	return addedSignal:Connect(callback)
end

function PlayerService.PlayerDied(player: Player): Signal<>
	if not diedEvents[player] then
		diedEvents[player] = Signal.new()
	end
	return diedEvents[player]
end

do
	local function OnCharacterAdded(character: UsableCharacter, player: Player)
		local usable = false
		while player.Parent and character == player.Character :: any do
			if CharacterHelper.IsUsable(character) then
				usable = true
				break
			end
			task.wait(1 / 15)
		end
		if not usable then
			return
		end

		character.Humanoid.Died:Once(function()
			PlayerService.Characters[player] = nil
			World:remove(jecs[player].Character, AliveTag)
			PlayerService.OnDied:FireDeferred(player)
			if diedEvents[player] then
				diedEvents[player]:FireDeferred()
			end
		end)

		local jecsData = jecs[player]
		World:set(jecsData.Character, CharacterComponent, character)
		World:add(jecsData.Character, AliveTag)
		InitializeCharacter(character, player)
		PlayerService.OnCharacterAdded:FireDeferred(character, player)
		PlayerService.Characters[player] = character
		local addedSignal = characterAddedEvents[player]
		if addedSignal then
			addedSignal:FireDeferred(character, player)
		end
	end

	PlayerService.PlayerAdded(function(player)
		do -- Register with Jecs.
			jecs[player] = {
				Character = World:entity(),
				Gravity = World:entity(),
			}
		end

		player.CharacterAdded:Connect(function(character)
			OnCharacterAdded(character :: UsableCharacter, player)
		end)
		player.CharacterRemoving:Connect(function()
			PlayerService.Characters[player] = nil
			local jecsData = jecs[player]
			if jecsData then
				World:remove(jecsData.Character, CharacterComponent)
				World:remove(jecsData.Character, AliveTag)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerService.Characters[player] = nil
		local diedEvent = diedEvents[player]
		diedEvents[player] = nil
		if diedEvent then
			diedEvent:Destroy()
		end

		local characterAddedEvent = characterAddedEvents[player]
		characterAddedEvents[player] = nil
		if characterAddedEvent then
			characterAddedEvent:Destroy()
		end

		local jecsData = jecs[player]
		jecs[player] = nil
		World:delete(jecsData.Character)
		World:delete(jecsData.Gravity)
	end)

	PlayerService.OnResetRequested:Connect(function(player)
		local humanoid = CharacterHelper.GetHumanoid(player)
		if humanoid and humanoid.EvaluateStateMachine then
			humanoid.Health = 0
		else
			PlayerService.LoadCharacter(player)
		end
	end)
end

return PlayerService
