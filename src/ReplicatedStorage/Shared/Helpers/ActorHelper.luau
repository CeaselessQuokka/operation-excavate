--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Signal = require(ReplicatedStorage.Modules.Packages.Signal)
local TableHelper = require(ReplicatedStorage.Modules.Helpers.TableHelper)
local ThreadingHelper = require(ReplicatedStorage.Modules.Helpers.ThreadingHelper)

--- Types ---
export type Guild<Return, Params...> = {
	Active: boolean,
	Actors: { Actor },

	OnDisbanded: Signal.Signal<>,

	Delegate: (self: Guild<Return, Params...>, options: DelegationOptionsInternal<Return>?, Params...) -> Return,
	Dispatch: (self: Guild<Return, Params...>, options: DispatchOptions<Return>?, ...any) -> (),
	Disband: (self: Guild<Return, Params...>) -> (),
	Destroy: (self: Guild<Return, Params...>) -> (), -- Alias for Disband.
}

export type DelegationOptions<Return> = {
	AwaitCompletion: boolean?, -- Whether to wait for all dispatched tasks to complete before returning from Delegate (default: true).
	OnFinished: ((completed: boolean, result: Return) -> ())?, -- Callback for when all dispatched tasks have completed.
}
export type Delegator<Return, Params...> = (
	Guild<Return, Params...>,
	DelegationOptionsInternal<Return>,
	Params...
) -> (boolean, Return)

export type DispatchOptions<Return> = {
	Id: number, -- ID to identify this dispatched task.
	Timeout: number?, -- In seconds; -1 for no timeout (default is 5): time to wait for this dispatched task to complete.
	AwaitCompletion: boolean?, -- Whether to wait for this dispatched task to complete before returning from Dispatch (default: true).
	OnFinished: ((completed: boolean, result: Return) -> ())?, -- Callback for when this dispatched task has completed.
}

export type DelegationOptionsInternal<Return> = {
	AwaitCompletion: boolean,
	OnFinished: (completed: boolean, result: Return) -> (),
}

--- Variables ---
local DEFAULT_DELEGATION_OPTIONS: DelegationOptionsInternal<any> = table.freeze({
	AwaitCompletion = true,
	OnFinished = nil :: any, -- Defined in the guild's Delegate method.
})

local DEFAULT_DISPATCH_OPTIONS: DispatchOptions<any> = table.freeze({
	Id = nil :: any, -- Set later in :Dispatch.
	Timeout = 45,
	AwaitCompletion = true,
	OnFinished = nil,
})

local IS_SERVER = RunService:IsServer()

local actorId = SharedTable.new({ Id = 1 })
local dispatchId = SharedTable.new({ Id = 1 })

--- Functions ---
local function GetActorId(): number
	return SharedTable.increment(actorId, "Id", 1)
end

local function GetDispatchId(): number
	return SharedTable.increment(dispatchId, "Id", 1)
end

--- Actor Helper ---
local ActorHelper = {}

function ActorHelper.FormGuild<Return, Params...>(
	nActors: number,
	template: Actor,
	delegator: Delegator<Return, Params...>
): Guild<Return, Params...>
	local guild = {
		Active = true,
		Actors = table.create(nActors),

		OnDisbanded = Signal.new(),
	}
	for actorNumber = 1, nActors do
		local actorId = GetActorId()
		local actor = template:Clone()
		actor.Name = `GuildActor{actorId}_{template.Name}{actorNumber}`
		actor:SetAttribute("ActorId", actorId)
		actor.Parent = if IS_SERVER then ServerScriptService else Players.LocalPlayer:WaitForChild("PlayerScripts")
		guild.Actors[actorNumber] = actor
	end

	-- Delegates a larger task; the passed delegator function will send
	-- parameters generated from the delegator function to the Dispatch
	-- method.
	-- Returns whether or not the delegation completed before timing out.
	local numDelegations = 0
	local function GuildCleanup()
		local self = guild :: Guild<Return, Params...>
		if not self.Active and numDelegations <= 0 then
			guild.OnDisbanded:FireDeferred()
			for _, actor in guild.Actors do
				pcall(game.Destroy, actor)
			end
		end
	end

	function guild:Delegate(options: DelegationOptions<Return>?, ...): (boolean, Return?)
		local self = self :: Guild<Return, Params...>
		if not self.Active then
			task.defer(GuildCleanup)
			return false, nil
		end

		numDelegations += 1
		local options = TableHelper.ReconcileOptions(options, DEFAULT_DELEGATION_OPTIONS)
		if options.AwaitCompletion then
			local completed, result = delegator(self, options, ...)
			if options.OnFinished then
				task.defer(options.OnFinished, completed, result)
			end
			numDelegations -= 1
			task.defer(GuildCleanup)
			return completed, result
		else
			local args = { ... }
			task.defer(function()
				local completed, result = delegator(self, options, table.unpack(args))
				if options.OnFinished then
					task.defer(options.OnFinished, completed, result)
				end
				numDelegations -= 1
				GuildCleanup()
			end)
			return true, nil
		end
	end

	-- Hands off a delegated task to an actor in round-robin fashion
	-- with parameters given by the delegator function.
	local currentActorIndex = 1
	function guild:Dispatch(options: DispatchOptions<Return>?, ...: any)
		local self = self :: Guild<Return, Params...>
		if not self.Active then
			return
		end

		currentActorIndex = (currentActorIndex % nActors) + 1
		local actor = self.Actors[currentActorIndex]
		local options = TableHelper.ReconcileOptions(options, DEFAULT_DISPATCH_OPTIONS)
		local timeoutThread: thread?
		if options.Timeout then
			timeoutThread = task.delay(options.Timeout, function()
				actor:SetAttribute(`{options.Id}TimedOut`, true)
			end)
		end
		options.Id = GetDispatchId()
		actor:SendMessage(actor.Name, options, ...)
		if options.AwaitCompletion then
			if
				not ThreadingHelper.WaitForAny(
					options.Timeout,
					actor:GetAttributeChangedSignal(`{options.Id}Completed`),
					actor:GetAttributeChangedSignal(`{options.Id}TimedOut`)
				)
			then
				warn(`Dispatch {options.Id} timed out before completion.`)
			end
			if not actor:GetAttribute(`{options.Id}TimedOut`) and timeoutThread then
				task.cancel(timeoutThread)
			end
			if options.OnFinished then
				local completed = actor:GetAttribute(`{options.Id}Completed`) :: boolean?
				task.defer(options.OnFinished, completed == true)
			end
			actor:SetAttribute(`{options.Id}Completed`, nil)
			actor:SetAttribute(`{options.Id}TimedOut`, nil)
		elseif options.OnFinished then
			ThreadingHelper.WaitForAnyAsync(
				function(raceFinished)
					if not raceFinished then
						warn(`Dispatch (async) {options.Id} timed out before completion.`)
					end
					if not actor:GetAttribute(`{options.Id}TimedOut`) and timeoutThread then
						task.cancel(timeoutThread)
					end
					if options.OnFinished then
						local completed = actor:GetAttribute(`{options.Id}Completed`) :: boolean?
						task.defer(options.OnFinished, completed == true)
					end
					actor:SetAttribute(`{options.Id}Completed`, nil)
					actor:SetAttribute(`{options.Id}TimedOut`, nil)
				end,
				options.Timeout,
				actor:GetAttributeChangedSignal(`{options.Id}Completed`),
				actor:GetAttributeChangedSignal(`{options.Id}TimedOut`)
			)
		end
	end

	-- Marks the guild for removal/cleanup; this way no other tasks
	-- get dispatched. The guild will wait for all remaining tasks to
	-- finish (within a specifiable timeout) and then terminate.
	function guild:Disband()
		local self = self :: Guild<Return, Params...>
		self.Active = false
		task.defer(GuildCleanup)
	end
	function guild:Destroy()
		-- Alias for Disband.
		local self = self :: Guild<Return, Params...>
		self:Disband()
	end

	return guild :: Guild<Return, Params...>
end

return ActorHelper
