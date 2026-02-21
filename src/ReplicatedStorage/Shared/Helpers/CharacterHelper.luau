--!strict
--- Services ---
local Players = game:GetService("Players")

--- Types ---
export type ResolvableCharacterInstance = Instance

export type Character = R15Character | R6Character
export type UsableCharacter = UsableR15Character | UsableR6Character
export type ValidCharacter = ValidR15Character | ValidR6Character

export type R15Character = Model & {
	Humanoid: Humanoid?,
	PrimaryPart: BasePart?,
	LeftFoot: BasePart?,
	LeftHand: BasePart?,
	LeftLowerArm: BasePart?,
	LeftLowerLeg: BasePart?,
	LeftUpperArm: BasePart?,
	LeftUpperLeg: BasePart?,
	LowerTorso: BasePart?,
	RightFoot: BasePart?,
	RightHand: BasePart?,
	RightLowerArm: BasePart?,
	RightLowerLeg: BasePart?,
	RightUpperArm: BasePart?,
	RightUpperLeg: BasePart?,
	UpperTorso: BasePart?,
	Head: BasePart?,
	HumanoidRootPart: BasePart?,
}

export type UsableR15Character = Model & {
	Humanoid: Humanoid,
	PrimaryPart: BasePart,
	LeftFoot: BasePart?,
	LeftHand: BasePart?,
	LeftLowerArm: BasePart?,
	LeftLowerLeg: BasePart?,
	LeftUpperArm: BasePart?,
	LeftUpperLeg: BasePart?,
	LowerTorso: BasePart?,
	RightFoot: BasePart?,
	RightHand: BasePart?,
	RightLowerArm: BasePart?,
	RightLowerLeg: BasePart?,
	RightUpperArm: BasePart?,
	RightUpperLeg: BasePart?,
	UpperTorso: BasePart,
	Head: BasePart,
	HumanoidRootPart: BasePart,
}

export type ValidR15Character = Model & {
	Humanoid: Humanoid,
	PrimaryPart: BasePart,
	LeftFoot: BasePart,
	LeftHand: BasePart,
	LeftLowerArm: BasePart,
	LeftLowerLeg: BasePart,
	LeftUpperArm: BasePart,
	LeftUpperLeg: BasePart,
	LowerTorso: BasePart,
	RightFoot: BasePart,
	RightHand: BasePart,
	RightLowerArm: BasePart,
	RightLowerLeg: BasePart,
	RightUpperArm: BasePart,
	RightUpperLeg: BasePart,
	UpperTorso: BasePart,
	Head: BasePart,
	HumanoidRootPart: BasePart,
}

export type R6Character = Model & {
	["Humanoid"]: Humanoid?,
	["Head"]: BasePart?,
	["HumanoidRootPart"]: BasePart?,
	["PrimaryPart"]: BasePart?,
	["Left Arm"]: BasePart?,
	["Left Leg"]: BasePart?,
	["Right Arm"]: BasePart?,
	["Right Leg"]: BasePart?,
	["Torso"]: BasePart?,
}

export type UsableR6Character = Model & {
	["Humanoid"]: Humanoid,
	["Head"]: BasePart,
	["HumanoidRootPart"]: BasePart,
	["PrimaryPart"]: BasePart,
	["Left Arm"]: BasePart?,
	["Left Leg"]: BasePart?,
	["Right Arm"]: BasePart?,
	["Right Leg"]: BasePart?,
	["Torso"]: BasePart,
}

export type ValidR6Character = Model & {
	["Humanoid"]: Humanoid,
	["Head"]: BasePart,
	["HumanoidRootPart"]: BasePart,
	["PrimaryPart"]: BasePart,
	["Left Arm"]: BasePart,
	["Left Leg"]: BasePart,
	["Right Arm"]: BasePart,
	["Right Leg"]: BasePart,
	["Torso"]: BasePart,
}

--- Variables ---
local R15_LIMB_INCLUDE_LIST = table.freeze({
	LeftFoot = true,
	LeftHand = true,
	LeftLowerArm = true,
	LeftLowerLeg = true,
	LeftUpperArm = true,
	LeftUpperLeg = true,
	LowerTorso = true,
	RightFoot = true,
	RightHand = true,
	RightLowerArm = true,
	RightLowerLeg = true,
	RightUpperArm = true,
	RightUpperLeg = true,
	UpperTorso = true,
	Head = true,
})

local R6_LIMB_INCLUDE_LIST = table.freeze({
	["Head"] = true,
	["Left Arm"] = true,
	["Left Leg"] = true,
	["Right Arm"] = true,
	["Right Leg"] = true,
	["Torso"] = true,
})

--- Character Helper ---
local CharacterHelper = {}

local function GetCharacterModel(instance: ResolvableCharacterInstance): Character?
	if Players:GetPlayerFromCharacter(instance) then
		-- Instance passed is the character model.
		return instance :: Character
	else
		-- Instance passed is potentially an instance within the character.
		local character = instance:FindFirstAncestorOfClass("Model")
		while character do
			if Players:GetPlayerFromCharacter(character) then
				break
			end

			character = character:FindFirstAncestorOfClass("Model")
		end
		return character :: Character?
	end
end

function CharacterHelper.GetCharacter(instance: ResolvableCharacterInstance?): Character?
	assert(typeof(instance) == "Instance" or instance == nil, "CharacterHelper.GetCharacter expects Instance or nil.")
	if not instance then
		return nil
	end

	return (
		if instance.ClassName == "Player" and instance.Parent
			then (instance :: Player).Character :: Character?
			else GetCharacterModel(instance)
	) :: Character?
end

function CharacterHelper.GetCharacterFromLimb(limb: ResolvableCharacterInstance?): Character?
	assert(typeof(limb) == "Instance" or limb == nil, "CharacterHelper.GetCharacterFromLimb expects Instance or nil.")
	if not limb or not limb.Parent or not limb:IsA("BasePart") then
		return nil
	end

	local character = limb.Parent
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid then
		return nil
	end

	local rigType = humanoid.RigType.Name
	if rigType == "R15" and not R15_LIMB_INCLUDE_LIST[limb.Name] then
		return nil
	elseif rigType == "R6" and not R6_LIMB_INCLUDE_LIST[limb.Name] then
		return nil
	end

	return if Players:GetPlayerFromCharacter(character) then character :: Character else nil
end

function CharacterHelper.GetHumanoid(instance: ResolvableCharacterInstance?): Humanoid?
	local character = CharacterHelper.GetCharacter(instance)
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

function CharacterHelper.GetAnimator(instance: ResolvableCharacterInstance?, createAnimator: boolean?): Animator?
	local humanoid = CharacterHelper.GetHumanoid(instance)
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator and createAnimator then
		-- Types were being weird whenever I tried to reassign "animator". Thus the new variable.
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		return newAnimator
	end
	return animator
end

function CharacterHelper.GetHumanoidFromLimb(limb: ResolvableCharacterInstance?): Humanoid?
	local character = CharacterHelper.GetCharacterFromLimb(limb)
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

function CharacterHelper.GetPlayer(instance: ResolvableCharacterInstance?): Player?
	return Players:GetPlayerFromCharacter(CharacterHelper.GetCharacter(instance))
end

function CharacterHelper.GetPlayerFromLimb(limb: ResolvableCharacterInstance?): Player?
	return Players:GetPlayerFromCharacter(CharacterHelper.GetCharacterFromLimb(limb))
end

function CharacterHelper.GetPrimaryPart(instance: ResolvableCharacterInstance?): BasePart?
	local character = CharacterHelper.GetCharacter(instance)
	return if character then character.PrimaryPart else nil
end

function CharacterHelper.GetRootPart(instance: ResolvableCharacterInstance?): BasePart?
	local character = CharacterHelper.GetCharacter(instance)
	local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if rootPart and rootPart:IsA("BasePart") then rootPart else nil
end

function CharacterHelper.IsPlayer(instance: ResolvableCharacterInstance?): boolean
	return CharacterHelper.GetPlayer(instance) ~= nil
end

function CharacterHelper.IsAlive(instance: ResolvableCharacterInstance?): boolean
	local humanoid = CharacterHelper.GetHumanoid(instance)
	return if humanoid then humanoid.Health > 0 else false
end

function CharacterHelper.IsUsable(instance: ResolvableCharacterInstance?): boolean
	local character = CharacterHelper.GetCharacter(instance)
	return CharacterHelper.IsAlive(character) and CharacterHelper.GetRootPart(character) ~= nil
end

function CharacterHelper.IsValid(instance: ResolvableCharacterInstance?): boolean
	local character = CharacterHelper.GetCharacter(instance)
	if not character or not CharacterHelper.IsUsable(character) then
		return false
	end

	local usableCharacter: UsableCharacter = character
	local rigType = usableCharacter.Humanoid.RigType.Name
	if rigType == "R15" and usableCharacter.PrimaryPart ~= usableCharacter.HumanoidRootPart then
		return false
	elseif rigType == "R6" and usableCharacter.PrimaryPart ~= usableCharacter.Head then
		return false
	end

	for name in (if rigType == "R15" then R15_LIMB_INCLUDE_LIST else R6_LIMB_INCLUDE_LIST) :: any do
		local limb = usableCharacter:FindFirstChild(name :: string)
		if not limb or not limb:IsA("BasePart") then
			return false
		end
	end

	return true
end

function CharacterHelper.LoadAnimation(
	instance: ResolvableCharacterInstance?,
	animation: Animation
): (AnimationTrack?, Animator?)
	assert(
		typeof(animation) == "Instance" and animation.ClassName == "Animation",
		"CharacterHelper.LoadAnimation expects Animation instance as 2nd argument."
	)

	local looped: any = animation:GetAttribute("Looped")
	local priority = animation:GetAttribute("AnimationPriority") or "Action"
	assert(typeof(looped) == "boolean" or looped == nil, "Looped attribute must be a boolean or nil.")
	assert(typeof(priority) == "string", "AnimationPriority attribute must be a string or nil.")

	if not CharacterHelper.IsUsable(instance) then
		return nil, nil
	end

	local animator = CharacterHelper.GetAnimator(instance, true)
	local track = if animator then animator:LoadAnimation(animation) else nil
	if not track then
		return nil, nil
	end

	track.Looped = if looped ~= nil then looped else track.Looped
	track.Priority = Enum.AnimationPriority:FromName(priority) or Enum.AnimationPriority.Action
	return track, animator
end

function CharacterHelper.DistanceFrom(
	instance: ResolvableCharacterInstance?,
	point: Vector3,
	useXZ: boolean?,
	yThreshold: number?
): number
	local character = CharacterHelper.GetCharacter(instance)
	if not character or not CharacterHelper.IsUsable(character) then
		return math.huge
	end

	local usableCharacter = character :: UsableCharacter
	local origin = usableCharacter.HumanoidRootPart.Position
	if not useXZ then
		return (origin - point).Magnitude
	else
		if math.abs(origin.Y - point.Y) > math.abs((yThreshold or 10)) then
			return math.huge
		end

		local displacement = origin - point
		return math.sqrt(displacement.X ^ 2 + displacement.Z ^ 2)
	end
end

function CharacterHelper.RemoveFromSeat(instance: ResolvableCharacterInstance?)
	local humanoid = CharacterHelper.GetHumanoid(instance)
	if humanoid and humanoid.SeatPart then
		local seatWeld: Weld? = humanoid.SeatPart:QueryDescendants(">Weld#SeatWeld")[1] :: any
		if seatWeld then
			pcall(game.Destroy, seatWeld)
		else
			humanoid.Sit = false
		end
	end
end

-- Moves the player originating from their feet.
function CharacterHelper.MoveTo(instance: ResolvableCharacterInstance?, to: CFrame, relative: boolean?)
	local character = CharacterHelper.GetCharacter(instance) :: UsableCharacter?
	if not character or not CharacterHelper.IsUsable(character) then
		return
	end

	local humanoid = character.Humanoid
	local rootPart = character.HumanoidRootPart
	local halfRootHeight = rootPart.Size.Y / 2
	local hipHeight = humanoid.HipHeight
	local heightOffset = halfRootHeight + hipHeight
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg: BasePart? = character:QueryDescendants(">BasePart#LeftLeg")[1]
			or character:QueryDescendants(">BasePart#RightLeg")[1]
		if leg then
			heightOffset += leg.Size.Y
		end
	end
	character:PivotTo(if relative then to * CFrame.new(0, heightOffset, 0) else to + Vector3.new(0, heightOffset, 0))
end

return table.freeze(CharacterHelper)
