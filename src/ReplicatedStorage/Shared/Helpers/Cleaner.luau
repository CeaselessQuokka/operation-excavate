--[[
	A cleanup manager similar to Trove, Maid, and Janitor that:
		- Supports stopping AnimationTracks and canceling Tweens before destroying them.
		- Ensures no errors are thrown in the main thread when cleaning.
		- Provides a way to remove (Unlink) a trackable without cleaning it.
--]]

--!strict
--- Types ---
-- AnimationTracks and Tweens will first be stopped/cancelled before getting Destroyed.
export type Trackable = thread | Callable | Disconnectable | Destroyable | Instance | RBXScriptConnection
export type Callable = (self: any) -> ()
export type Disconnectable = { Disconnect: (self: any) -> () }
export type Destroyable = { Destroy: (self: any) -> () }

--- Variables ---
local NIL_SYMBOL = newproxy(false)

local ROBLOX_WARN = warn

--- Functions ---
local function warn(message: string, ...: any)
	ROBLOX_WARN(debug.traceback(`[{script.Name}] {message}`), ...)
end

--- Cleaner Class ---
local Cleaner = {}
Cleaner.__index = Cleaner

export type Cleaner = typeof(setmetatable(
	{} :: {
		_tracked: { [Trackable]: any },
	},
	Cleaner
))
function Cleaner.new(): Cleaner
	return setmetatable({ _tracked = {} }, Cleaner)
end

function Cleaner.Add<T>(self: Cleaner, trackable: T & Trackable, funcArg: any): T
	if trackable == nil then
		warn(debug.traceback("Attempt to Add nil Trackable"))
		return trackable
	end

	local trackable = trackable :: any -- TODO: when new type system gets released, do this properly.
	local tracked = self._tracked
	if tracked[trackable] ~= nil then
		warn(debug.traceback(`Attempt to Add duplicate Trackable: "{trackable}" ({typeof(trackable)})`, trackable))
		return trackable
	end

	tracked[trackable] = if funcArg == nil then NIL_SYMBOL else funcArg
	return trackable
end

function Cleaner.Remove<T>(self: Cleaner, trackable: T & Trackable): boolean
	local trackable = trackable :: any -- TODO: when new type system gets released, do this properly.
	local funcArg = self._tracked[trackable]
	if self:Unlink(trackable) then
		self:_CleanTrackable(trackable, funcArg)
		return true
	end
	return false
end

function Cleaner.Unlink<T>(self: Cleaner, trackable: T & Trackable): boolean
	local trackable = trackable :: any -- TODO: when new type system gets released, do this properly.
	local tracked = self._tracked
	if tracked[trackable] == nil then
		return false
	end

	tracked[trackable] = nil
	return true
end

function Cleaner.Clean(self: Cleaner)
	for tracked, funcArg in self._tracked do
		self:_CleanTrackable(tracked, funcArg)
	end
	table.clear(self._tracked)
end
Cleaner.Destroy = Cleaner.Clean

function Cleaner._CleanTrackable<T>(self: Cleaner, trackable: T & Trackable, funcArg: any)
	local function CleanupTable(trackable: any, funcArg: any)
		local cleaner = trackable.Destroy or trackable.Disconnect
		if cleaner then
			cleaner(trackable)
		else
			if funcArg ~= NIL_SYMBOL then
				local cleanupFunction = trackable[funcArg]
				if typeof(cleanupFunction) == "function" then
					cleanupFunction(trackable)
					return
				else
					warn(
						`Unable to cleanup table Trackable with function key "{funcArg}" ({typeof(funcArg)}): "{cleanupFunction}"`,
						trackable
					)
				end
			else
				warn(
					`Unable to cleanup table Trackable: "{next(trackable)}" = "{select(2, next(trackable))}"`,
					trackable
				)
			end
		end
	end

	local function GetSecondaryInstanceCleanupFunction(trackable: Instance): Callable?
		if trackable:IsA("AnimationTrack") then
			return trackable.Stop
		elseif trackable:IsA("Tween") then
			return trackable.Cancel
		else
			return nil
		end
	end

	local trackable = trackable :: any -- TODO: when new type system gets released, do this properly.
	local typeOf = typeof(trackable)
	if typeOf == "thread" then
		pcall(task.cancel, trackable)
	elseif typeOf == "function" then
		if funcArg == NIL_SYMBOL then
			funcArg = nil
		end
		task.spawn(trackable, funcArg)
	elseif typeOf == "table" then
		task.spawn(CleanupTable, trackable, funcArg)
	elseif typeOf == "RBXScriptConnection" then
		trackable:Disconnect()
	elseif typeOf == "Instance" then
		local trackable: Instance = trackable
		local cleaner = GetSecondaryInstanceCleanupFunction(trackable)
		if cleaner then
			cleaner(trackable)
			task.delay(0, pcall, trackable.Destroy, trackable) -- Guarantee (according to https://devforum.roblox.com/t/deferred-engine-events/2276564) time for events to fire before destroying.
		else
			pcall(trackable.Destroy, trackable)
		end
	end
end

return Cleaner
