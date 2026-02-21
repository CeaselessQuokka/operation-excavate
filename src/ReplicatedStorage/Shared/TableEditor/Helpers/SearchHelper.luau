--!strict
--[[
	Helper functions for search, filtering, and fuzzy matching operations.
]]

--- Imports ---
local Constants = require(script.Parent.Parent.Constants)

--- Types ---
type Table = { [any]: any }

--- Variables ---
local TYPE_ALIASES = Constants.TYPE_ALIASES

--- Functions ---

--[[
	Performs fuzzy string matching between a query and target.
	Uses multiple strategies: exact substring, prefix, subsequence, initials, and Levenshtein distance.
	
	NOTE: Always performs case-insensitive matching regardless of caller settings.
	Inputs are lowercased internally for consistent fuzzy matching behavior.
	
	@param query The search query string
	@param target The target string to match against
	@param threshold The similarity threshold (0-1, where 1 is exact match)
	@return true if the target matches the query within the threshold
]]
local function FuzzyMatch(query: string, target: string, threshold: number): boolean
	if query == "" then
		return true
	end

	query = string.lower(query)
	target = string.lower(target)
	query = query:gsub("^%s+", ""):gsub("%s+$", "")
	local m, n = #query, #target

	-- Exact substring match (fastest check)
	if string.find(target, query, 1, true) then
		return true
	end

	-- Prefix match
	if m <= n and string.sub(target, 1, m) == query then
		return true
	end

	-- Subsequence match
	local qi = 1
	local queryByte = string.byte(query, qi)
	for i = 1, n do
		if string.byte(target, i) == queryByte then
			qi += 1
			if qi > m then
				return true
			end
			queryByte = string.byte(query, qi)
		end
	end

	-- Initials match (for short queries)
	if m <= 5 then
		local initials = ""
		for word in target:gmatch("%S+") do
			initials ..= string.sub(word, 1, 1)
		end
		if string.find(initials, query, 1, true) then
			return true
		end
	end

	-- Skip expensive Levenshtein for long strings
	if m > 10 or n > 50 then
		return false
	end

	if n == 0 then
		return false
	end

	-- Levenshtein distance with early termination
	local maxDistance = math.max(math.floor(m * (1 - threshold)), 1)
	if m <= 3 then
		maxDistance = math.max(maxDistance, 1)
	end

	local prevRow = table.create(n + 1)
	local currRow = table.create(n + 1)
	for j = 0, n do
		prevRow[j + 1] = j
	end

	for i = 1, m do
		currRow[1] = i
		local minInRow = i
		local queryCharByte = string.byte(query, i)

		for j = 1, n do
			local cost = if queryCharByte == string.byte(target, j) then 0 else 1
			currRow[j + 1] = math.min(
				prevRow[j + 1] + 1, -- deletion
				currRow[j] + 1, -- insertion
				prevRow[j] + cost -- substitution
			)
			minInRow = math.min(minInRow, currRow[j + 1])
		end

		-- Early termination if minimum in row exceeds threshold
		if minInRow > maxDistance then
			return false
		end

		prevRow, currRow = currRow, prevRow
	end

	return prevRow[n + 1] <= maxDistance
end

--[[
	Checks if a value type matches a type exclusion string.
	Supports partial matching and type aliases (e.g., "bool" matches "boolean").
	
	@param valueType The actual type of the value (e.g., "boolean", "number")
	@param exclusion The exclusion filter string (e.g., "bool", "num")
	@return true if the value type should be excluded
]]
local function MatchesTypeExclusion(valueType: string, exclusion: string): boolean
	local lowerValueType = string.lower(valueType)
	if exclusion == "" then
		return false
	end

	-- Exact match
	if lowerValueType == exclusion then
		return true
	end

	-- Check type aliases
	local aliases = TYPE_ALIASES[lowerValueType]
	if aliases then
		for _, alias in pairs(aliases) do
			if alias == exclusion or string.sub(alias, 1, #exclusion) == exclusion then
				return true
			end
		end
	end

	-- Prefix match on full type name
	if string.sub(lowerValueType, 1, #exclusion) == exclusion then
		return true
	end

	return false
end

--[[
	Parses a text input into a typed value.
	Handles: booleans, nil, numbers, empty tables, quoted strings, and plain strings.
	
	@param text The input text to parse
	@return The parsed value
]]
local function ParseInputValue(text: string): any
	local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")

	if trimmed == "" then
		return ""
	elseif trimmed == "true" then
		return true
	elseif trimmed == "false" then
		return false
	elseif trimmed == "nil" then
		return nil
	elseif trimmed == "{}" then
		return {} -- Create empty table
	elseif tonumber(trimmed) then
		return tonumber(trimmed)
	elseif trimmed:match("^\".*\"$") or trimmed:match("^'.*'$") then
		return trimmed:sub(2, -2)
	else
		return trimmed
	end
end

--[[
	Parses a key input, converting to number if applicable.
	
	@param text The input text to parse as a key
	@return The parsed key value, or nil if invalid
]]
local function ParseKeyInput(text: string): any
	local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")

	if trimmed == "" then
		return nil -- Invalid key
	elseif tonumber(trimmed) then
		return tonumber(trimmed)
	else
		return trimmed
	end
end

--[[
	Compares two filter arrays for equality.
	
	@param a First filter array
	@param b Second filter array (can be nil)
	@return true if both arrays contain the same filters
]]
local function FiltersEqual(a: { string }, b: { string }?): boolean
	if not b then
		return #a == 0
	end
	if #a ~= #b then
		return false
	end
	for i, v in pairs(a) do
		if v ~= b[i] then
			return false
		end
	end
	return true
end

--[[
	Debounces filter update callbacks.
	Cancels any pending callback for the same viewer and schedules a new one.
	
	@param viewerId The unique viewer ID
	@param callback The callback to execute after debounce
	@param delay The debounce delay in seconds (default 0.15)
	@param threads A table storing active debounce threads by viewerId
]]
local function DebouncedFilterUpdate(
	viewerId: string,
	callback: () -> (),
	delay: number?,
	threads: { [string]: thread }
)
	local actualDelay = delay or 0.15
	local existingThread = threads[viewerId]
	if existingThread then
		task.cancel(existingThread)
	end
	threads[viewerId] = task.delay(actualDelay, function()
		threads[viewerId] = nil
		callback()
	end)
end

--[[
	Generates an auto-key for adding a new entry to a table.
	If the table is array-like, returns the next integer index.
	Otherwise, generates a unique string key like "newKey", "newKey1", etc.
	
	@param targetTable The table to generate a key for
	@return The generated key (number or string)
]]
local function GenerateAutoKey(targetTable: Table): string | number
	-- Check if it's an array-like table
	local isArray = true
	local maxIndex = 0

	for k, _ in pairs(targetTable) do
		if typeof(k) ~= "number" or k < 1 or k ~= math.floor(k) then
			isArray = false
			break
		end
		maxIndex = math.max(maxIndex, k)
	end

	if isArray then
		return maxIndex + 1
	else
		local baseKey = "newKey"
		local suffix = 1
		local parsedKey: string = baseKey
		while targetTable[parsedKey] ~= nil do
			parsedKey = baseKey .. suffix
			suffix += 1
		end
		return parsedKey
	end
end

--- Search Helper ---
local SearchHelper = {
	FuzzyMatch = FuzzyMatch,
	MatchesTypeExclusion = MatchesTypeExclusion,
	ParseInputValue = ParseInputValue,
	ParseKeyInput = ParseKeyInput,
	FiltersEqual = FiltersEqual,
	DebouncedFilterUpdate = DebouncedFilterUpdate,
	GenerateAutoKey = GenerateAutoKey,
}

return table.freeze(SearchHelper)
