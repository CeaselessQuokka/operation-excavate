--!strict
--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--- Imports ---
local Signal = require(ReplicatedStorage.Packages.Signal)

local TableHelper = require(ReplicatedStorage.Shared.Helpers.TableHelper)
local t = require(ReplicatedStorage.Packages.t)

local Types = require(ReplicatedStorage.Shared.Types)

--- Types ---
export type CacheKey = string
export type RequestCallback<Return, Params...> = (Params...) -> Return

export type OnStartResult<Result> = {
	Options: RequestOptionsInternal<Result>,
	Args: { any },
}
export type OnStepResult<Result> = {
	Options: RequestOptionsInternal<Result>,
	Args: { any },
	Retries: number,
}
export type BeforeRequestResult<Result> = {
	Options: RequestOptionsInternal<Result>,
	Args: { any },
	Retries: number,
}
export type AfterRequestResult<Result> = {
	Options: RequestOptionsInternal<Result>,
	Args: { any },
	Retries: number,
	Successful: boolean,
	Result: Result | string,
}
export type OnSuccessResult<Result> = {
	Options: RequestOptionsInternal<Result>,
	Args: { any },
	Retries: number,
	Result: Result,
	WasCached: boolean,
}
export type OnFailureResult<Result> = {
	Options: RequestOptionsInternal<Result>,
	Args: { any },
	Retries: number,
	Reason: string,
}
export type OnFinishResult<Result> = {
	Options: RequestOptionsInternal<Result>,
	Args: { any },
	Retries: number,
	Successful: boolean,
	Result: Result | string,
	WasCached: boolean?,
}
export type RequestOptions<Result> = {
	Cache: boolean?, -- Whether to cache the result of the request.
	CacheKey: CacheKey?, -- Key to use for caching the result of the request, otherwise a key will be generated based on the parameters.
	CacheDuration: number?, -- Duration to cache the result of the request (note that is at the mercy of caching done by the request you are making). -1 means an indefinite cache.
	CacheOnClients: boolean?, -- [SHARED] Whether to cache the result on clients as well (requires remote calls).
	MaxRetries: number?, -- Max number of retries before returning.
	RetryDelayFunction: ((retryCount: number, maxJitter: number) -> number)?, -- Function to calculate the delay based on the retry count.
	TransformResult: ((result: any) -> Result)?, -- Function to transform the result before returning it.
	RequestFromServer: boolean?, -- [CLIENT ONLY] Whether to request the data from the server instead (should only be done if the data is cached and shared amongst clients).
	AllowMultipleRequests: boolean?, -- Whether to allow multiple concurrent requests with the same cache key.
	IgnoreCache: boolean?, -- Whether to ignore the cache and force a request
	Hooks: {
		OnStart: ((OnStartResult<Result>) -> boolean)?, -- Fires (deferred) at the start of the very start of the request only once.
		OnStep: ((OnStepResult<Result>) -> boolean)?, -- Fires (blocking) on each step of the request process (Before request, after request, and on request failure) with the current retry count. Return false to cancel the request.
		BeforeRequest: ((BeforeRequestResult<Result>) -> boolean)?, -- Fires (blocking) right before each request attempt. Return false to cancel the request.
		AfterRequest: ((AfterRequestResult<Result>) -> boolean)?, -- Fires (blocking) right after each request attempt. Return false to cancel further retries.
		OnSuccess: ((OnSuccessResult<Result>) -> ())?, -- Fires (deferred) when a request is successful.
		OnFailure: ((OnFailureResult<Result>) -> boolean)?, -- Fires (blocking) when a request fails. Return false to cancel further retries.
		OnFinish: ((OnFinishResult<Result>) -> ())?, -- Fires (deferred) when a request finishes, regardless of success or failure.
	}?,
}

type Signal<Params...> = Types.Signal<Params...>
type SignalConnection = Types.SignalConnection
type CacheState = {
	CurrentValue: any,
	OnUpdate: Signal<any>,
	CachedOnClients: boolean,
	CacheExpiration: number?, -- Timestamp when the cache expires (if applicable).
	RemoveFromCacheThread: thread?,
}

type RequestOptionsInternal<Result> = {
	Cache: boolean,
	CacheKey: CacheKey?,
	CacheDuration: number,
	CacheOnClients: boolean,
	MaxRetries: number,
	RetryDelayFunction: (retryCount: number, maxJitter: number) -> number,
	TransformResult: ((result: any) -> Result)?,
	RequestFromServer: boolean,
	AllowMultipleRequests: boolean,
	IgnoreCache: boolean,
	Hooks: {
		OnStart: ((OnStartResult<Result>) -> boolean)?,
		OnStep: ((OnStepResult<Result>) -> boolean)?,
		BeforeRequest: ((BeforeRequestResult<Result>) -> boolean)?,
		AfterRequest: ((AfterRequestResult<Result>) -> boolean)?,
		OnSuccess: ((OnSuccessResult<Result>) -> ())?,
		OnFailure: ((OnFailureResult<Result>) -> boolean)?,
		OnFinish: ((OnFinishResult<Result>) -> ())?,
	},
}

--- Variables ---
local IS_SERVER = RunService:IsServer()
local REQUEST_JITTER = 3 -- Jitter time (in seconds) to add to retry delays so retries don't all happen at once.

local DEFAULT_REQUEST_OPTIONS: RequestOptionsInternal<any> = table.freeze({
	Cache = false,
	CacheKey = nil,
	CacheDuration = if RunService:IsStudio() then 5 else 60,
	CacheOnClients = false,
	MaxRetries = 5,
	RetryDelayFunction = function(retryCount: number, maxJitter: number): number
		return (0.5 * retryCount) ^ 1.5 + (math.random() * maxJitter)
	end,
	RequestFromServer = false,
	AllowMultipleRequests = false,
	IgnoreCache = false,
	Hooks = {},
})

local VALID_SERVER_REQUESTS = table.freeze({
	BadgeService = {
		GetBadgeInfoAsync = true,
		UserHasBadgeAsync = true,
	},
	GamePassService = {
		PlayerHasPass = true,
	},
	MarketplaceService = {
		PlayerOwnsAsset = true,
	},
})

local CLIENT_OPTION_VALIDATION = t.strictInterface({
	Cache = t.optional(t.boolean),
	CacheKey = t.optional(t.string),
	CacheDuration = t.optional(t.number),
	CacheOnClients = t.optional(t.boolean),
	MaxRetries = t.optional(t.intersection(t.numberConstrained(0, 10), t.integer)),
	RequestFromServer = t.optional(t.boolean),
	AllowMultipleRequests = t.optional(t.boolean),
})

local onCacheOnClientsRemote: RemoteEvent = ReplicatedStorage.Remotes.RequestHelper.OnCacheOnClients
local onRequestFromServerRemote: RemoteFunction = ReplicatedStorage.Remotes.RequestHelper.OnRequestFromServer
local onSyncCacheRemote: RemoteEvent = ReplicatedStorage.Remotes.RequestHelper.OnSyncCache

local activeRequests: { [CacheKey]: boolean } = {}
local cache: { [CacheKey]: CacheState } = {}

--- Functions ---
local function GetCacheKey<Result>(options: RequestOptionsInternal<Result>, ...: any): CacheKey?
	if options.CacheKey ~= nil and options.CacheKey ~= "" then
		return options.CacheKey
	end

	local cacheKey = ""
	for _, arg in { ... } do
		if not typeof(arg):find("^%s*%a+:%s+0x[abcdef%d]+%s*$") then
			-- If it's something like "table: 0xabcdef12...", skip it.
			cacheKey = `{cacheKey}{arg}`
		end
	end
	if cacheKey == "" then
		warn(
			`[{script.Name}] Unable to generate cache key from parameters; using a random cache key. This can lead to memory leaks, so make sure to fix it in the code. A default random one is only given to avoid major failures live in the case of unforeseen edge cases.`,
			...
		)
		return tostring(Workspace:GetServerTimeNow())
	end
	return cacheKey
end

local function GetOptions<Return>(partial: RequestOptions<Return>?): RequestOptionsInternal<Return>
	local options = TableHelper.ReconcileOptions(partial, DEFAULT_REQUEST_OPTIONS)
	return options
end

--- Request Helper ---
local RequestHelper = {
	ActiveRequests = activeRequests,
	Cache = cache,

	OnInitialRequest = Signal.new() :: Signal<OnStartResult<any>>, -- Fires on the initial request only, but not for reattempts (use OnBefore/AfterRequest for this behavior).
	OnBeforeRequest = Signal.new() :: Signal<BeforeRequestResult<any>>, -- Fires before each request attempt.
	OnAfterRequest = Signal.new() :: Signal<AfterRequestResult<any>>, -- Fires after each request attempt.
	OnRequestSuccess = Signal.new() :: Signal<OnSuccessResult<any>>, -- Fires on each successful request.
	OnRequestFailure = Signal.new() :: Signal<OnFailureResult<any>>, -- Fires on each failed request.
	OnRequestFinish = Signal.new() :: Signal<OnFinishResult<any>>, -- Fires when a request finishes, regardless of success or failure.
	OnRequestCached = Signal.new() :: Signal<CacheKey, any>, -- Fires when a request result is cached.
}

-- Returns if the request was successful, the result (if successful), and an error message (if not successful).
function RequestHelper.Send<Return, Params...>(
	callback: RequestCallback<Return, Params...>,
	options: RequestOptions<Return>?,
	...: any
): (boolean, Return?, string?)
	local options = GetOptions(options)
	local activeRequestKey: CacheKey? = nil
	local cacheKey = GetCacheKey(options, ...)
	if not options.AllowMultipleRequests then
		activeRequestKey = cacheKey
		if activeRequestKey then
			if activeRequests[activeRequestKey] then
				return false, nil
			end

			activeRequests[activeRequestKey] = true
		end
	end

	if options.Hooks.OnStart then
		task.defer(options.Hooks.OnStart, { Options = options, Args = { ... } })
	end
	local success, result = RequestHelper._Request(callback, options, ...)
	if activeRequestKey then
		activeRequests[activeRequestKey] = nil
	end
	return success, result
end

-- Returns if the asynchronous request was initiated successfully.
function RequestHelper.SendAsync<Return, Params...>(
	callback: RequestCallback<Return, Params...>,
	options: RequestOptions<Return>?,
	...: any
): boolean
	local options = GetOptions(options)
	if not next(options.Hooks) then
		warn(`[{script.Name}] Request was not sent; no hooks defined for asynchronous request.`)
		return false
	end

	if options.Hooks.OnStart then
		task.defer(options.Hooks.OnStart, { Options = options, Args = { ... } })
	end
	local cacheKey = GetCacheKey(options, ...)
	local activeRequestKey: CacheKey? = nil
	if not options.AllowMultipleRequests then
		activeRequestKey = cacheKey
		if activeRequestKey then
			if activeRequests[activeRequestKey] then
				return false
			end

			activeRequests[activeRequestKey] = true
		end
	end

	local cachedResult: Return? = RequestHelper.GetFromCache(cacheKey)
	if cachedResult ~= nil then
		local successData: OnSuccessResult<any> = {
			Options = options,
			Args = { ... },
			Retries = 0,
			Result = cachedResult,
			WasCached = true,
		}
		if options.Hooks.OnSuccess then
			task.defer(options.Hooks.OnSuccess :: (any) -> (), successData)
		end
		if options.Hooks.OnFinish then
			task.defer(options.Hooks.OnFinish :: (any) -> (), successData)
		end
		RequestHelper.OnRequestSuccess:FireDeferred(successData)
		RequestHelper.OnRequestFinish:FireDeferred({
			Options = options,
			Args = { ... },
			Retries = 0,
			Successful = true,
			Result = cachedResult,
			WasCached = true,
		})
		if activeRequestKey then
			activeRequests[activeRequestKey] = nil
		end
	else
		local args = { ... }
		task.defer(function()
			RequestHelper._Request(callback, options, table.unpack(args))
			if activeRequestKey then
				activeRequests[activeRequestKey] = nil
			end
		end)
	end
	return true
end

function RequestHelper.GetFromCache(cacheKey: CacheKey?): any
	if cacheKey == nil or cacheKey == "" then
		return nil
	end

	return if cache[cacheKey] then cache[cacheKey].CurrentValue else nil
end

function RequestHelper.RemoveFromCache(cacheKey: CacheKey?): any
	if cacheKey == nil or cacheKey == "" then
		return nil
	end

	local cacheState = cache[cacheKey]
	if cacheState then
		local currentValue = cacheState.CurrentValue
		cacheState.CurrentValue = nil
		if not cacheState.OnUpdate:GetConnections()[1] then
			cache[cacheKey] = nil
			cacheState.OnUpdate:Destroy()
		end
		return currentValue
	end
	return nil
end

-- Can be called from the client only.
function RequestHelper.RequestFromServer(
	service: string,
	method: string,
	options: RequestOptions<any>?,
	forceRequest: boolean?, -- Whether to force the request even if cached.
	...: any
): (boolean, any?)
	assert(not IS_SERVER, `[{script.Name}] RequestFromServer can only be called from the client.`)

	local fullOptions = GetOptions(options)
	local cacheKey = GetCacheKey(fullOptions, ...)
	if not forceRequest then
		local cachedValue = RequestHelper.GetFromCache(cacheKey)
		if cachedValue ~= nil then
			return true, cachedValue
		end
	end

	local success, result = onRequestFromServerRemote:InvokeServer(service, method, options, ...)
	if fullOptions.Cache and cacheKey then
		RequestHelper._UpdateCache(fullOptions, result)
	end
	return success, result
end

function RequestHelper.CacheUpdated(cacheKey: CacheKey, callback: (any) -> (), fireNow: boolean?): SignalConnection
	local cacheState = cache[cacheKey]
	if not cacheState then
		cacheState = {
			CurrentValue = nil,
			OnUpdate = Signal.new(),
			CachedOnClients = false,
		}
		cache[cacheKey] = cacheState
	end
	if fireNow then
		task.defer(callback, cacheState.CurrentValue)
	end
	return cacheState.OnUpdate:Connect(callback)
end

-- Assumes GetOptions has already been called.
function RequestHelper._Request<Return, Params...>(
	callback: RequestCallback<Return, Params...>,
	options: RequestOptionsInternal<Return>,
	...: any
): (boolean, Return?)
	RequestHelper.OnInitialRequest:FireDeferred({ Options = options, Args = { ... } })
	local cacheKey = GetCacheKey(options, ...)
	if not options.IgnoreCache then
		local cachedValue: Return? = RequestHelper.GetFromCache(cacheKey)
		if cachedValue ~= nil then
			if options.Hooks.OnSuccess then
				task.defer(options.Hooks.OnSuccess, {
					Options = options,
					Args = { ... },
					Retries = 0,
					Result = cachedValue,
					WasCached = true,
				})
			end
			if options.Hooks.OnFinish then
				task.defer(options.Hooks.OnFinish, {
					Options = options,
					Args = { ... },
					Retries = 0,
					Successful = true,
					Result = cachedValue,
					WasCached = true,
				})
			end
			RequestHelper.OnRequestSuccess:FireDeferred({
				Options = options,
				Args = { ... },
				Retries = 0,
				Result = cachedValue,
				WasCached = true,
			})
			RequestHelper.OnRequestFinish:FireDeferred({
				Options = options,
				Args = { ... },
				Retries = 0,
				Successful = true,
				Result = cachedValue,
				WasCached = true,
			})
			return true, cachedValue
		end
	end

	local retries = 0
	while retries <= options.MaxRetries do
		-- Fire step hook.
		local hooks = options.Hooks
		if hooks.OnStep then
			if not hooks.OnStep({ Options = options, Args = { ... }, Retries = retries }) then
				return false, nil
			end
		end

		-- Wait before retrying.
		if retries > 0 then
			task.wait(options.RetryDelayFunction(retries, REQUEST_JITTER))
		end

		-- Fire hooks before request.
		if hooks.OnStep then
			if not hooks.OnStep({ Options = options, Args = { ... }, Retries = retries }) then
				return false, nil
			end
		end
		if hooks.BeforeRequest then
			if not hooks.BeforeRequest({ Options = options, Args = { ... }, Retries = retries }) then
				return false, nil
			end
		end
		RequestHelper.OnBeforeRequest:FireDeferred({ Options = options, Args = { ... }, Retries = retries })

		-- Send the request.
		local success, result = pcall(callback, ...)

		-- Fire hooks after request.
		if hooks.OnStep then
			if not hooks.OnStep({ Options = options, Args = { ... }, Retries = retries }) then
				return false, nil
			end
		end
		if hooks.AfterRequest then
			local continueRequest = hooks.AfterRequest({
				Options = options,
				Args = { ... },
				Retries = retries,
				Successful = success,
				Result = result,
			})
			if not continueRequest then
				return false, nil
			end
		end
		RequestHelper.OnAfterRequest:FireDeferred({
			Options = options,
			Args = { ... },
			Retries = retries,
			Successful = success,
			Result = result,
		})

		-- Handle request response.
		if success then
			local transformedResult: Return = if options.TransformResult
				then options.TransformResult(result)
				else result

			-- Fire success hook.
			if hooks.OnSuccess then
				task.defer(hooks.OnSuccess, {
					Options = options,
					Args = { ... },
					Retries = retries,
					Result = transformedResult,
					WasCached = options.Cache and cacheKey ~= nil,
				})
			end
			if hooks.OnFinish then
				task.defer(hooks.OnFinish, {
					Options = options,
					Args = { ... },
					Retries = retries,
					Successful = true,
					Result = transformedResult,
					WasCached = options.Cache and cacheKey ~= nil,
				})
			end
			RequestHelper.OnRequestSuccess:FireDeferred({
				Options = options,
				Args = { ... },
				Retries = retries,
				Result = transformedResult,
				WasCached = options.Cache and cacheKey ~= nil,
			})
			RequestHelper.OnRequestFinish:FireDeferred({
				Options = options,
				Args = { ... },
				Retries = retries,
				Successful = true,
				Result = transformedResult,
				WasCached = options.Cache and cacheKey ~= nil,
			})

			-- Cache the result if requested.
			if options.Cache and cacheKey then
				if IS_SERVER and options.CacheOnClients then
					local replicationOptions = {
						Cache = true,
						CacheKey = cacheKey,
						CacheDuration = options.CacheDuration,
						CacheOnClients = true,
					}
					onCacheOnClientsRemote:FireAllClients(replicationOptions, transformedResult)
				end
				RequestHelper._UpdateCache(options, transformedResult)
			elseif options.Cache then
				warn(
					`[{script.Name}] Caching requested but no cache key could be determined; result will not be cached. Please provide a CacheKey in the RequestOptions to avoid this warning.`
				)
			end
			return true, transformedResult
		else
			warn(debug.traceback(`[_FAILURE_MESSAGE_PATTERN_FINDING_] "{result}"`), ...) -- Used to find patterns between failure messages in the future. For example: if it's possible to see if the message failed due to 429 or other reasons for better handling.

			-- Fire hooks on failure.
			if hooks.OnStep then
				if not hooks.OnStep({ Options = options, Args = { ... }, Retries = retries }) then
					return false, nil
				end
			end
			if hooks.OnFailure then
				local continueRequest = hooks.OnFailure({
					Options = options,
					Args = { ... },
					Retries = retries,
					Reason = result :: any,
				})
				if not continueRequest then
					return false, nil
				end
			end
			RequestHelper.OnRequestFailure:FireDeferred({
				Options = options,
				Args = { ... },
				Retries = retries,
				Reason = result :: any,
			})
		end
		retries += 1
	end
	if options.Hooks.OnFinish then
		task.defer(options.Hooks.OnFinish, {
			Options = options,
			Args = { ... },
			Retries = retries,
			Successful = false,
			Result = "Max retries reached",
		})
		RequestHelper.OnRequestFinish:FireDeferred({
			Options = options,
			Args = { ... },
			Retries = retries,
			Successful = false,
			Result = "Max retries reached",
		})
		warn(`[{script.Name}] Request failed; maximum retries reached`, ...)
	end
	return false, nil
end

function RequestHelper._UpdateCache(options: RequestOptionsInternal<any>, resultToCache: any, cacheExpiration: number?)
	local cacheKey = GetCacheKey(options)
	if not cacheKey then
		return
	end
	if cacheExpiration and Workspace:GetServerTimeNow() >= cacheExpiration then
		-- Don't cache if already expired.
		return
	end

	local cacheState = cache[cacheKey]
	if not cacheState then
		cacheState = {
			CurrentValue = nil,
			OnUpdate = Signal.new(),
			CachedOnClients = options.CacheOnClients,
		}
		cache[cacheKey] = cacheState
	end
	if cacheState.RemoveFromCacheThread then
		task.cancel(cacheState.RemoveFromCacheThread)
		cacheState.RemoveFromCacheThread = nil
	end
	if options.Cache then
		cacheState.CacheExpiration = cacheExpiration
			or (if options.CacheDuration ~= -1 then Workspace:GetServerTimeNow() + options.CacheDuration else nil)
	end
	local lastValue = cacheState.CurrentValue
	cacheState.CurrentValue = resultToCache
	if lastValue ~= resultToCache then
		cacheState.OnUpdate:FireDeferred(resultToCache)
		RequestHelper.OnRequestCached:FireDeferred(cacheKey, resultToCache)
	end
	if cacheExpiration and cacheExpiration ~= 1 then
		cacheState.RemoveFromCacheThread =
			task.delay(Workspace:GetServerTimeNow() - cacheExpiration, RequestHelper.RemoveFromCache, cacheKey)
	elseif not cacheExpiration and options.CacheDuration ~= -1 then
		cacheState.RemoveFromCacheThread = task.delay(options.CacheDuration, RequestHelper.RemoveFromCache, cacheKey)
	end
end

do -- Handle remotes.
	if not IS_SERVER then
		onSyncCacheRemote.OnClientEvent:Connect(
			function(cache: { [CacheKey]: { CurrentValue: any, CacheExpiration: number? } })
				for cacheKey, cacheData in cache do
					RequestHelper._UpdateCache(
						GetOptions({
							Cache = true,
							CacheKey = cacheKey,
							CacheDuration = -1,
							CacheOnClients = true,
							RequestFromServer = false,
						}),
						cacheData.CurrentValue,
						cacheData.CacheExpiration
					)
				end
			end
		)

		onCacheOnClientsRemote.OnClientEvent:Connect(RequestHelper._UpdateCache)
	else
		local function OnPlayerAdded(player: Player)
			local serverCache: { [CacheKey]: { CurrentValue: any, CacheExpiration: number? } } = {}
			for cacheKey, cacheState in cache do
				if cacheState.CachedOnClients then
					serverCache[cacheKey] = {
						CurrentValue = cacheState.CurrentValue,
						CacheExpiration = cacheState.CacheExpiration,
					}
				end
			end
			onSyncCacheRemote:FireClient(player, serverCache)
		end
		Players.PlayerAdded:Connect(OnPlayerAdded)
		for _, player in Players:GetPlayers() do
			task.defer(OnPlayerAdded, player)
		end

		function onRequestFromServerRemote.OnServerInvoke(
			player: Player,
			service: string,
			method: string,
			options: RequestOptions<any>?,
			...: any
		): (boolean, any?)
			assert(
				t.string(service) and VALID_SERVER_REQUESTS[service],
				`[{script.Name}] Service "{service}" is not valid for RequestFromServer. Player: "{player.UserId}"`
			)
			assert(
				t.string(method) and VALID_SERVER_REQUESTS[service][method],
				`[{script.Name}] Method "{method}" is not valid for RequestFromServer on service "{service}".`
			)
			assert(CLIENT_OPTION_VALIDATION(options))

			local options = GetOptions(options)
			local cachedValue = RequestHelper.GetFromCache(options.CacheKey)
			if cachedValue ~= nil then
				return true, cachedValue
			end

			local serviceInstance = game:GetService(service)
			local methodFunction = serviceInstance[method] :: (...any) -> ...any
			local success, result = pcall(methodFunction, serviceInstance, ...)
			if success then
				local cacheKey = options.CacheKey
				if options.CacheOnClients and cacheKey then
					onCacheOnClientsRemote:FireAllClients(options, result)
				end
				if options.Cache and cacheKey then
					RequestHelper._UpdateCache(options, result)
				end
				return true, result
			else
				warn(debug.traceback(`[{script.Name}] RequestFromServer failed for player "{player.UserId}": {result}`))
				return false, nil
			end
		end
	end
end

return table.freeze(RequestHelper)
