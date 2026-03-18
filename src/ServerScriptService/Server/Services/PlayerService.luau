--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--- Imports ---
local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local ThreadingHelper = require(ReplicatedStorage.Shared.Helpers.ThreadingHelper)

local JecsCommon = require(ReplicatedStorage.Shared.Common.JecsCommon)
local Types = require(ReplicatedStorage.Shared.Common.Types)

--- Types ---
type Character = CharacterHelper.Character
type UsableCharacter = CharacterHelper.UsableCharacter
type Signal<Params...> = Signal.Signal<Params...>
type SignalConnection = { Disconnect: (any) -> () }

--- Player Service ---
local PlayerService = {
	Name = "PlayerService",
	Client = {
		-- Client to Server
		OnResetRequested = Knit.CreateSignal() :: Types.ServerRemoteSignal<()>,
	},

	Characters = {} :: { [Player]: UsableCharacter }, -- Note: Characters is a bit of a misnomer; these are UsableCharacters.
	_jecs = {} :: { [Player]: { Character: Jecs.Id, Gravity: Jecs.Id } },

	_characterAddedEvents = {} :: { [Player]: Signal<UsableCharacter, Player> },
	_diedEvents = {} :: { [Player]: Signal<> },

	OnCharacterAdded = Signal.new() :: Signal<UsableCharacter, Player>,
	OnDied = Signal.new() :: Signal<Player>,
}
Knit.CreateService(PlayerService)

function PlayerService:KnitInit()
	local self = PlayerService
	local function OnCharacterAdded(character: UsableCharacter, player: Player)
		local usable = false
		while player.Parent and character == player.Character :: any do
			task.wait()
			if CharacterHelper.IsUsable(character) then
				usable = true
				break
			end
		end
		if not usable then
			return
		end

		character.Humanoid.Died:Once(function()
			self.Characters[player] = nil
			JecsCommon.World:remove(self._jecs[player].Character, JecsCommon.Tags.Alive)
			self.OnDied:FireDeferred(player)
			if self._diedEvents[player] then
				self._diedEvents[player]:FireDeferred()
			end
		end)

		local jecsData = self._jecs[player]
		JecsCommon.World:set(jecsData.Character, JecsCommon.Components.Character, character)
		JecsCommon.World:add(jecsData.Character, JecsCommon.Tags.Alive)
		self:_InitializeCharacter(character, player)
		self.OnCharacterAdded:FireDeferred(character, player)
		self.Characters[player] = character
		local addedSignal = self._characterAddedEvents[player]
		if addedSignal then
			addedSignal:FireDeferred(character, player)
		end
	end

	self:PlayerAdded(function(player)
		do -- Register with Jecs.
			self._jecs[player] = {
				Character = JecsCommon.World:entity(),
				Gravity = JecsCommon.World:entity(),
			}
		end

		player.CharacterAdded:Connect(function(character)
			OnCharacterAdded(character :: UsableCharacter, player)
		end)
		player.CharacterRemoving:Connect(function()
			self.Characters[player] = nil
			local jecsData = self._jecs[player]
			if jecsData then
				JecsCommon.World:remove(jecsData.Character, JecsCommon.Components.Character)
				JecsCommon.World:remove(jecsData.Character, JecsCommon.Tags.Alive)
				JecsCommon.World:remove(jecsData.Gravity, JecsCommon.Components.Gravity)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.Characters[player] = nil
		local diedEvent = self._diedEvents[player]
		self._diedEvents[player] = nil
		if diedEvent then
			diedEvent:Destroy()
		end

		local characterAddedEvent = self._characterAddedEvents[player]
		self._characterAddedEvents[player] = nil
		if characterAddedEvent then
			characterAddedEvent:Destroy()
		end

		local jecsData = self._jecs[player]
		self._jecs[player] = nil
		JecsCommon.World:delete(jecsData.Character)
		JecsCommon.World:delete(jecsData.Gravity)
	end)
end

function PlayerService:KnitStart()
	local self = PlayerService
	self.Client.OnResetRequested:Connect(function(player)
		local humanoid = CharacterHelper.GetHumanoid(player)
		if humanoid and humanoid.EvaluateStateMachine then
			humanoid.Health = 0
		else
			self:LoadCharacter(player)
		end
	end)
end

-- Loads the player's character if not already loaded, then returns it.
function PlayerService:LoadCharacter(player: Player, timeout: number?, onlyLoadIfNeeded: boolean?): UsableCharacter?
	local character = self.Characters[player]
	if onlyLoadIfNeeded == true and character then
		return character
	end

	self.Characters[player] = nil
	player:LoadCharacterAsync()
	return self:GetCharacter(player, true, timeout)
end

function PlayerService:GetCharacter(player: Player, await: boolean?, timeout: number?): UsableCharacter?
	local self = PlayerService
	local character = self.Characters[player]
	if character then
		return character
	elseif not await then
		return nil
	end

	timeout = timeout or 5
	local startTime = os.clock()
	while player.Parent and os.clock() - startTime < timeout and not self.Characters[player] do
		ThreadingHelper.WaitForAny(timeout, self.OnCharacterAdded, player.AncestryChanged)
	end
	return self.Characters[player]
end

function PlayerService:PlayerAdded(callback: (Player) -> ())
	Players.PlayerAdded:Connect(callback)
	for _, player in Players:GetPlayers() do
		task.defer(callback, player)
	end
end

function PlayerService:CharacterAdded(player: Player, callback: (UsableCharacter, Player) -> ()): SignalConnection
	local self = PlayerService
	local character = self.Characters[player]
	if character then
		task.defer(callback, character, player)
	end
	local addedSignal = self._characterAddedEvents[player]
	if not addedSignal then
		addedSignal = Signal.new()
		self._characterAddedEvents[player] = addedSignal
	end
	return addedSignal:Connect(callback)
end

function PlayerService:PlayerDied(player: Player): Signal<>
	local self = PlayerService
	if not self._diedEvents[player] then
		self._diedEvents[player] = Signal.new()
	end
	return self._diedEvents[player]
end

function PlayerService:_InitializeCharacter(character: UsableCharacter, player: Player)
	local self = PlayerService
	local rootPart = character.HumanoidRootPart
	do -- Create custom movement attached, and custom gravity force.
		local movementAttachment: Attachment = (ServerStorage :: any).Assets.Character.MovementAttachment:Clone()
		local gravityForce: VectorForce = (ServerStorage :: any).Assets.Character.Gravity:Clone()
		movementAttachment.Parent = rootPart
		gravityForce.Attachment0 = movementAttachment
		gravityForce.Parent = rootPart
		JecsCommon.World:set(self._jecs[player].Gravity, JecsCommon.Components.Gravity, gravityForce)
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

return PlayerService
