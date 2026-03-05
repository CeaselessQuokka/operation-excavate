--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)
local ThreadingHelper = require(ReplicatedStorage.Shared.Helpers.ThreadingHelper)

--- Types ---
type Character = CharacterHelper.Character
type UsableCharacter = CharacterHelper.UsableCharacter
type Signal<Params...> = Signal.Signal<Params...>
type SignalConnection = { Disconnect: (any) -> () }

--- Player Service ---
local PlayerService = {
	Name = "PlayerService",

	Characters = {} :: { [Player]: UsableCharacter }, -- Note: Characters is a bit of a misnomer; these are UsableCharacters.

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
			self.OnDied:FireDeferred(player)
			if self._diedEvents[player] then
				self._diedEvents[player]:FireDeferred()
			end
		end)

		self:_InitializeCharacter(character, player)
		self.OnCharacterAdded:FireDeferred(character, player)
		self.Characters[player] = character
		local addedSignal = self._characterAddedEvents[player]
		if addedSignal then
			addedSignal:FireDeferred(character, player)
		end
	end

	self:PlayerAdded(function(player)
		player.CharacterAdded:Connect(function(character)
			OnCharacterAdded(character :: UsableCharacter, player)
		end)
		player.CharacterRemoving:Connect(function()
			self.Characters[player] = nil
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
	end)
end

-- Loads the player's character if not already loaded, then returns it.
function PlayerService:LoadCharacter(player: Player, force: boolean?, timeout: number?): UsableCharacter?
	local character = self.Characters[player]
	if not force and character then
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
	do -- Handle custom character controller.
		-- Create the controller objects.
		-- TODO: better organize code
		local manager = Instance.new("ControllerManager")
		local groundController = Instance.new("GroundController")
		local airController = Instance.new("AirController")
		local groundSensor = Instance.new("ControllerPartSensor")
		airController.MoveMaxForce = 1000
		airController.BalanceRigidityEnabled = true
		airController.MaintainAngularMomentum = false
		groundController.BalanceRigidityEnabled = true
		groundSensor.SearchDistance = 4.5 -- (character.HumanoidRootPart.Size.Y / 2) + character.Humanoid.HipHeight + 1
		groundController.GroundOffset = character.Humanoid.HipHeight
		groundSensor.Name = "GroundSensor"
		groundSensor.UpdateType = Enum.SensorUpdateType.Manual
		manager.GroundSensor = groundSensor
		manager.RootPart = character.HumanoidRootPart
		manager.ActiveController = groundController
		groundController.Parent = manager
		airController.Parent = manager
		groundSensor.Parent = character.HumanoidRootPart
		manager.Parent = character
	end
end

return PlayerService
