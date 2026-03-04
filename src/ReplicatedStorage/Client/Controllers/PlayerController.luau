--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--- Imports ---
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local CharacterHelper = require(ReplicatedStorage.Shared.Helpers.CharacterHelper)

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

local DEFAULT_CHECK_INTERVAL = 0.125
local DEFAULT_Y_THRESHOLD = 6

local areaSignals: { [string]: { OnEntered: Signal<>, OnLeft: Signal<> } } = {}

--- Player Controller ---
local PlayerController = {
	Name = "PlayerController",

	Player = Players.LocalPlayer,
	PlayerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui,
	Character = nil :: UsableCharacter?,

	OnCharacterAdded = Signal.new() :: Signal<UsableCharacter>,
	OnDied = Signal.new() :: Signal<>,
}
Knit.CreateController(PlayerController)

function PlayerController:KnitStart()
	local self = PlayerController
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
			self.Character = nil
			self.OnDied:FireDeferred()
		end)

		self.Character = character :: UsableCharacter
		self.OnCharacterAdded:FireDeferred(character :: UsableCharacter)
	end

	localPlayer.CharacterAdded:Connect(OnCharacterAdded)
	if localPlayer.Character then
		task.defer(OnCharacterAdded, localPlayer.Character)
	end

	do -- Handle character rotation about planet. (TODO: Check for water)
		local gyro: AlignOrientation?
		local gyroAttachment: Attachment?
		local function CleanupGyro()
			if gyro then
				pcall(game.Destroy, gyro)
				gyro = nil
			end
			if gyroAttachment then
				pcall(game.Destroy, gyroAttachment)
				gyroAttachment = nil
			end
		end
		self:CharacterAdded(function(character)
			gyro = Instance.new("AlignOrientation")
			gyroAttachment = Instance.new("Attachment")
			gyro.Name = "PlanetAlignOrientation"
			gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
			gyro.MaxTorque = 1e9
			gyro.Responsiveness = 75
			gyro.Attachment0 = gyroAttachment
			gyroAttachment.Name = "PlanetAlignOrientationAttachment"
			gyroAttachment.Parent = character.PrimaryPart
			gyro.Enabled = false
			gyro.Parent = character.PrimaryPart
		end)
		self.OnDied:Connect(CleanupGyro)
		localPlayer.CharacterRemoving:Connect(CleanupGyro)

		-- Handle actual rotation logic.
		RunService.PreRender:Connect(function()
			local character = self.Character
			if not character or not gyro or not gyroAttachment then
				return
			end

			local origin = character:GetPivot()
			local normal = origin.Position.Unit -- Assumes origin is (0, 0, 0); otherwise you'd need to subtract position by the origin.
			local zDir = origin.ZVector
			local xDir = normal:Cross(zDir)
			local moveDirection = character.Humanoid.MoveDirection
			local projected = moveDirection - (normal * moveDirection:Dot(normal))
			if projected.Magnitude > 0.1 then
				projected = projected.Unit
				local rightDir = projected:Cross(normal)
				gyro.CFrame = CFrame.fromMatrix(Vector3.zero, rightDir, normal)
			else
				gyro.CFrame = CFrame.fromMatrix(Vector3.zero, xDir, normal)
			end
			-- gyro.CFrame = CFrame.fromMatrix(Vector3.zero, xDir, normal)
			-- local moveDirection = character.Humanoid.MoveDirection
			-- if moveDirection.Magnitude > 0.1 then
			-- 	character:PivotTo(CFrame.lookAlong(origin.Position, moveDirection, normal))
			-- end
		end)
	end
end

function PlayerController:CharacterAdded(callback: (character: UsableCharacter) -> ()): SignalConnection
	if localPlayer.Character then
		task.defer(callback, localPlayer.Character)
	end
	return self.OnCharacterAdded:Connect(callback)
end

function PlayerController:DisableControls()
	PlayerModule:GetControls():Disable()
end

function PlayerController:EnableControls()
	PlayerModule:GetControls():Enable()
end

function PlayerController:EnteredArea(
	name: string,
	area: Area,
	options: AreaOptions?,
	onEnteredCallback: (() -> ())?,
	onLeftCallback: (() -> ())?
): (Signal<>, Signal<>, () -> ())
	if areaSignals[name] then
		local cleanup = function()
			self:StopAreaCheck(name)
		end
		return areaSignals[name].OnEntered, areaSignals[name].OnLeft, cleanup
	end

	local function GetAreaCFrameAndSize(): (CFrame, Vector3)
		if typeof(area) == "Instance" and area:IsA("BasePart") then
			return area.CFrame, area.Size
		elseif typeof(area) == "table" then
			return area.CFrame, area.Size
		else
			error(`Invalid area given: "{area}" ({typeof(area)})`)
		end
	end

	local function IsInArea(): boolean
		local character = self.Character
		if not character then
			return false
		end

		local rootPart = CharacterHelper.GetRootPart(character)
		if not rootPart then
			return false
		end

		local position = rootPart.Position
		local areaCFrame, areaSize = GetAreaCFrameAndSize()
		local checkMode = if options and options.CheckMode then options.CheckMode else "Box"
		if checkMode == "Magnitude" then
			local radius = if options and options.Radius then options.Radius else (areaSize.Magnitude / 2)
			return CharacterHelper.DistanceFrom(character, areaCFrame.Position, false) <= radius
		elseif checkMode == "XZ" then
			local yThreshold = if options and options.YThreshold then options.YThreshold else DEFAULT_Y_THRESHOLD
			local radius = if options and options.Radius then options.Radius else math.max(areaSize.X, areaSize.Z) / 2
			return CharacterHelper.DistanceFrom(character, areaCFrame.Position, true, yThreshold) <= radius
		else
			local localPosition = areaCFrame:PointToObjectSpace(position)
			local halfSize = areaSize / 2
			return math.abs(localPosition.X) <= halfSize.X
				and math.abs(localPosition.Y) <= halfSize.Y
				and math.abs(localPosition.Z) <= halfSize.Z
		end
	end

	local onEntered = Signal.new()
	local onLeft = Signal.new()
	areaSignals[name] = {
		OnEntered = onEntered,
		OnLeft = onLeft,
	}
	if onEnteredCallback then
		onEntered:Connect(onEnteredCallback)
	end
	if onLeftCallback then
		onLeft:Connect(onLeftCallback)
	end

	task.spawn(function()
		local checkInterval = if options and options.CheckInterval
			then options.CheckInterval
			else DEFAULT_CHECK_INTERVAL
		local wasInArea = false
		while areaSignals[name] do
			local isInArea = IsInArea()
			if isInArea and not wasInArea then
				onEntered:FireDeferred()
			elseif not isInArea and wasInArea then
				onLeft:FireDeferred()
			end
			wasInArea = isInArea
			task.wait(checkInterval)
		end
	end)
	return onEntered, onLeft, function()
		self:StopAreaCheck(name)
	end
end

function PlayerController:StopAreaCheck(name: string)
	local areaData = areaSignals[name]
	if areaData then
		areaData.OnEntered:Destroy()
		areaData.OnLeft:Destroy()
		areaSignals[name] = nil
	end
end

return PlayerController
