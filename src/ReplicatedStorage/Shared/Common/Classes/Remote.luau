--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--- Types ---
export type RemoteInstance = RemoteEvent | RemoteFunction
export type Config = {
	-- The cooldown period for firing the remote from the current run context.
	CooldownPerFire: number?,

	-- The period in which you can send MaxRequestsPerPeriod amount of requests. Applies to the current run context.
	RequestPeriod: number?,

	-- The max amount of requests you can send in the RequestPeriod. Applies to the current run context.
	MaxRequestsPerPeriod: number?,
}

export type ServerApi<Params..., Return...> = {
	Fire: (self: Remote<Params..., Return...>, player: Player, Params...) -> Return...,
	FireAll: (self: Remote<Params..., Return...>, Params...) -> (),
	Connect: (
		self: Remote<Params..., Return...>,
		handler: (player: Player, Params...) -> Return...
	) -> RBXScriptConnection?,
}
export type ClientApi<Params..., Return...> = {
	Fire: (self: Remote<Params..., Return...>, Params...) -> Return...,
	Connect: (self: Remote<Params..., Return...>, handler: (Params...) -> Return...) -> RBXScriptConnection?,
}

--- Variables ---
local IS_SERVER = RunService:IsServer()

local REMOTES_FOLDER_NAME = "Remotes"
local REMOTES_FOLDER_PARENT = ReplicatedStorage
local REMOTES_FOLDER: Folder
if IS_SERVER then
	REMOTES_FOLDER = Instance.new("Folder")
	REMOTES_FOLDER.Name = REMOTES_FOLDER_NAME
	REMOTES_FOLDER.Parent = REMOTES_FOLDER_PARENT
else
	REMOTES_FOLDER = REMOTES_FOLDER_PARENT:WaitForChild(REMOTES_FOLDER_NAME) :: Folder
	assert(
		REMOTES_FOLDER and REMOTES_FOLDER.ClassName == "Folder",
		`Invalid remote folder found; got "{REMOTES_FOLDER.ClassName}", expected "Folder"`
	)
end

local DEFAULT_CONFIG: Config = {}

local remotes: { [string]: Remote<...any, ...any> } = {}

--- Functions ---
local function AwaitRemoteInstance(name: string): RemoteInstance
	local instance: RemoteInstance = REMOTES_FOLDER:WaitForChild(name) :: any
	assert(
		instance and (instance.ClassName == "RemoteEvent" or instance.ClassName == "RemoteFunction"),
		`Invalid remote instance found; got "{instance.ClassName}", expected "RemoteEvent" or "RemoteFunction"`
	)
	return instance
end

--- Remote Class ---
local Remote = {}
Remote.__index = Remote

export type Remote<Params..., Return...> = setmetatable<
	{
		Instance: RemoteInstance, -- The underlying RemoteEvent or RemoteFunction instance. The type is just a hack to get proper typing.
		Config: Config?, -- Only respected by server.
		_cooldowns: {
			[Player]: {
				-- Timestamp in UTC seconds of the last time this remote was fired from the current run context.
				LastFireTime: number,

				-- The amount of requests sent in the current RequestPeriod.
				-- Resets after RequestPeriod seconds have passed since the first
				-- request in the period. Nil if no requests have been made in the
				-- current run context or if RequestPeriod is not configured.
				RequestsThisPeriod: number,

				-- Timestamp in UTC seconds of when the current RequestPeriod will reset.
				-- Nil if no requests have been made in the current run context or if RequestPeriod is not configured.
				PeriodResetTime: number,
			},
		},
		_meta: {
			-- The total amount of times this remote has been fired from the current run context.
			TotalFires: number,
		},
	},
	typeof(Remote)
>
function Remote.Event<Params..., Return...>(name: string, config: Config?): Remote<Params..., Return...>
	assert(config == nil or IS_SERVER, "Config can only be set for the server")
	if remotes[name] then
		return remotes[name]
	end

	local remoteInstance: RemoteInstance
	if IS_SERVER then
		if not REMOTES_FOLDER:FindFirstChild(name) then
			remoteInstance = Instance.new("RemoteEvent")
			remoteInstance.Name = name
			remoteInstance.Parent = REMOTES_FOLDER
		end
	else
		remoteInstance = AwaitRemoteInstance(name)
	end

	local self: Remote<Params..., Return...> = setmetatable({
		Instance = remoteInstance,
		Config = config,
		_cooldowns = {},
		_meta = {
			TotalFires = 0,
		},
	}, Remote) :: any
	remotes[name] = self
	return self
end

function Remote.Function<Params..., Return...>(name: string, config: Config?): Remote<Params..., Return...>
	assert(config == nil or IS_SERVER, "Config can only be set for the server")
	if remotes[name] then
		return remotes[name]
	end

	local remoteInstance: RemoteInstance
	if IS_SERVER then
		if not REMOTES_FOLDER:FindFirstChild(name) then
			remoteInstance = Instance.new("RemoteFunction")
			remoteInstance.Name = name
			remoteInstance.Parent = REMOTES_FOLDER
		end
	else
		remoteInstance = AwaitRemoteInstance(name)
	end

	local self: Remote<Params..., Return...> = setmetatable({
		Instance = remoteInstance,
		Config = config,
		_cooldowns = {},
		_meta = {
			TotalFires = 0,
		},
	}, Remote) :: any
	remotes[name] = self
	return self
end

function Remote.Fire<Params..., Return...>(self: Remote<Params..., Return...>, ...: Params...): Return...
	local isEvent = self.Instance.ClassName == "RemoteEvent"
	if IS_SERVER then
		local player: Player = ... :: any
		if isEvent then
			(self.Instance :: RemoteEvent):FireClient(player, select(2, ...))
		else
			return (self.Instance :: RemoteFunction):InvokeClient(player, select(2, ...))
		end
	else
		if isEvent then
			(self.Instance :: RemoteEvent):FireServer(...)
		else
			return (self.Instance :: RemoteFunction):InvokeServer(...)
		end
	end
end

function Remote.FireAll<Params..., Return...>(self: Remote<Params..., Return...>, ...: Params...)
	assert(IS_SERVER, "FireAll can only be called from the server")
	assert(self.Instance.ClassName == "RemoteEvent", "FireAll can only be called on RemoteEvents")

	local remoteInstance = self.Instance :: RemoteEvent
	remoteInstance:FireAllClients(...)
end

function Remote.Connect<Params..., Return...>(self: Remote<Params..., Return...>, handler: (Params...) -> Return...): RBXScriptConnection?
	if IS_SERVER then
		if self.Instance.ClassName == "RemoteEvent" then
			return (self.Instance :: RemoteEvent).OnServerEvent:Connect(function(player: Player, ...: Params...)
				if not self:_IsOnCooldown(player) then
					local config = self.Config or DEFAULT_CONFIG
					local cooldownData = self._cooldowns[player]
					if
						config.RequestPeriod
						and config.MaxRequestsPerPeriod
						and cooldownData.RequestsThisPeriod == 0
					then
						cooldownData.PeriodResetTime = os.time() + config.RequestPeriod
					end
					self._meta.TotalFires += 1
					cooldownData.RequestsThisPeriod += 1
					cooldownData.LastFireTime = os.time()
					handler(...)
				end
			end)
		else
			local remoteInstance = self.Instance :: RemoteFunction
			function remoteInstance.OnServerInvoke(player: Player, ...: Params...): Return...
				if not self:_IsOnCooldown(player) then
					local config = self.Config or DEFAULT_CONFIG
					local cooldownData = self._cooldowns[player]
					if
						config.RequestPeriod
						and config.MaxRequestsPerPeriod
						and cooldownData.RequestsThisPeriod == 0
					then
						cooldownData.PeriodResetTime = os.time() + config.RequestPeriod
					end
					self._meta.TotalFires += 1
					cooldownData.RequestsThisPeriod += 1
					cooldownData.LastFireTime = os.time()
					return handler(...)
				end
			end
		end
	else
		if self.Instance.ClassName == "RemoteEvent" then
			return (self.Instance :: RemoteEvent).OnClientEvent:Connect(handler :: any)
		else
			(self.Instance :: RemoteFunction).OnClientInvoke = handler
		end
	end
	return nil
end

function Remote._IsOnCooldown<Params..., Return...>(self: Remote<Params..., Return...>, player: Player): boolean
	local config: Config = self.Config or DEFAULT_CONFIG
	local cooldownData = self._cooldowns[player]
	if config.CooldownPerFire then
		if os.time() < cooldownData.LastFireTime + config.CooldownPerFire then
			warn(`Remote "{self.Instance}" is on cooldown; cannot fire for player "{player}" ({player.UserId})`)
			return true
		end
	elseif config.MaxRequestsPerPeriod and config.RequestPeriod then
		if cooldownData.RequestsThisPeriod >= config.MaxRequestsPerPeriod then
			if os.time() < cooldownData.PeriodResetTime then
				warn(
					`Remote "{self.Instance}" has exceeded the max requests per period; cannot fire for player "{player}" ({player.UserId})`
				)
				return true
			else
				cooldownData.RequestsThisPeriod = 0
				cooldownData.PeriodResetTime = 0
			end
		end
	end
	return false
end

do -- Handle cooldown (un)populating.
	Players.PlayerAdded:Connect(function(player)
		for _, remote in remotes do
			remote._cooldowns[player] = {
				LastFireTime = 0,
				RequestsThisPeriod = 0,
				PeriodResetTime = 0,
			}
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, remote in remotes do
			remote._cooldowns[player] = nil
		end
	end)
end

return table.freeze(Remote)
