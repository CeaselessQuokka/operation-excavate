--[[
	Handles the creation, management, and throttling of remotes.
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
--- Services ---

--- Imports ---

--- Types ---
export type Config = {
	CooldownPerFire: number?, -- The cooldown period for firing the remote from the current run context.
	RequestPeriod: number?, -- The period in which you can send MaxRequests amount of requests. Applies to the current run context.
	MaxRequests: number?, -- The max amount of requests you can send in the RequestPeriod. Applies to the current run context.
}

--- Variables ---
local REMOTES_FOLDER_NAME = "Remotes"
local REMOTES_FOLDER_PARENT = ReplicatedStorage
local REMOTES_FOLDER
if RunService:IsServer() then
	REMOTES_FOLDER = Instance.new("Folder")
	REMOTES_FOLDER.Name = REMOTES_FOLDER_NAME
	REMOTES_FOLDER.Parent = REMOTES_FOLDER_PARENT
else
	REMOTES_FOLDER = REMOTES_FOLDER_PARENT:WaitForChild(REMOTES_FOLDER_NAME)
end

local remotes: { [string]: Remote } = {}

--- Functions ---

--- Remote Class ---
local Remote = {}
Remote.__index = Remote

export type Remote = setmetatable<{}, typeof(Remote)>
function Remote.Event(name: string, config: Config?): Remote
	if remotes[name] then
		return remotes[name]
	elseif RunService:IsClient() then
		local waitingTime = 0
		while not remotes[name] do
			waitingTime += task.wait(1)
			if waitingTime >= 10 then
				warn(`Still waiting for remote "{name}" after 10 seconds. Are you sure you have the right name?`)
			end
		end
		return remotes[name]
	end
	local self: Remote = setmetatable({}, Remote)
	return self
end

function Remote.Method(self: Remote, ...: any) end

if RunService:IsClient() then -- Handle replicating remotes to client.
	local function RegisterRemote(remote: RemoteEvent | RemoteFunction)
		remotes[remote.Name] = remote
	end
end

return table.freeze(Remote)
