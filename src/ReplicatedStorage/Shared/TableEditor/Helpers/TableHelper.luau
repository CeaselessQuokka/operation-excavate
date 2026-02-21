--!strict
--[[
	Helper functions for table manipulation, cloning, diffing, and utility operations.
]]

--- Services ---
local HttpService = game:GetService("HttpService")

--- Imports ---
local Constants = require(script.Parent.Parent.Constants)

--- Types ---
type Table = { [any]: any }

--- Variables ---
local REMOVAL_KEY = Constants.REMOVAL_KEY

--- Functions ---

--[[
	Converts a path array to a dot-separated string.
	Example: {"foo", "bar", 1} -> "foo.bar.1"
]]
local function PathToString(path: { any }): string
	if path[1] == nil then
		return ""
	end
	local parts = table.create(#path)
	for i, k in pairs(path) do
		parts[i] = tostring(k)
	end
	return table.concat(parts, ".")
end

--[[
	Creates a deep clone of a table, handling circular references.
]]
local function DeepClone<T>(tbl: T, visited_: { [any]: any }?): T
	if typeof(tbl) ~= "table" then
		return tbl
	end

	local visited = visited_ or {}
	if visited[tbl] then
		return visited[tbl]
	end

	local clone = {} :: any
	visited[tbl] = clone
	for key, value in pairs(tbl :: any) do
		if typeof(value) == "table" then
			clone[key] = DeepClone(value, visited)
		else
			clone[key] = value
		end
	end

	return clone :: T
end

--[[
	Performs deep equality comparison between two values.
	Handles circular references.
]]
local function DeepEqual(a: any, b: any, visited_: { [Table]: boolean }?): boolean
	if typeof(a) ~= typeof(b) then
		return false
	end

	if typeof(a) ~= "table" then
		return a == b
	end

	local visited = visited_ or {}
	if visited[a] then
		return true
	end
	visited[a] = true

	for key, valueA in pairs(a) do
		local valueB = b[key]
		if not DeepEqual(valueA, valueB, visited) then
			return false
		end
	end

	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end

	return true
end

--[[
	Creates a hash string for a value.
	Used for change detection without deep comparison.
]]
local function HashValue(value: any, visited_: { [Table]: boolean }?, depth_: number?): string
	local depth = depth_ or 0
	if typeof(value) ~= "table" then
		local t = typeof(value)
		if t == "number" then
			return `n:{value}`
		elseif t == "string" then
			if #value > 100 then
				return `s:{#value}:{value:sub(1, 50)}`
			end
			return `s:{value}`
		elseif t == "boolean" then
			return if value then "b:t" else "b:f"
		else
			return `{t}:{tostring(value)}`
		end
	end

	if depth > 5 then
		return "table:deep"
	end

	local visited = visited_ or {}
	if visited[value] then
		return "table:recursive"
	end
	visited[value] = true

	local count = 0
	for _ in pairs(value) do
		count += 1
		if count > 50 then
			break
		end
	end

	if count > 50 then
		return `table:large:{count}`
	end

	local parts = table.create(count)
	local keys = table.create(count)
	local i = 0
	for k in pairs(value) do
		i += 1
		keys[i] = k
	end
	table.sort(keys, function(ka, kb)
		return tostring(ka) < tostring(kb)
	end)
	for idx, k in pairs(keys) do
		parts[idx] = `{tostring(k)}={HashValue(value[k], visited, depth + 1)}`
	end
	return `t:{table.concat(parts, ",")}`
end

--[[
	Applies a patch to a source table.
	Values marked with REMOVAL_KEY are removed.
]]
local function Patch<T>(src: T, patch: Table, visited: { [Table]: boolean }?): T
	if typeof(src) ~= "table" then
		return src
	end

	local visitedTables = visited or {}
	if visitedTables[patch] then
		return src
	end
	visitedTables[patch] = true

	for key, patchValue in pairs(patch) do
		if patchValue == REMOVAL_KEY then
			(src :: any)[key] = nil
		elseif typeof(patchValue) == "table" and typeof((src :: any)[key]) == "table" then
			(src :: any)[key] = Patch((src :: any)[key], patchValue, visitedTables)
		else
			(src :: any)[key] = patchValue
		end
	end
	return src
end

--[[
	Computes the diff between two tables.
	Returns a patch that can be applied to `old` to get `new`.
]]
local function GetDiff(new: Table, old: Table): Table
	if typeof(new) ~= "table" or typeof(old) ~= "table" then
		return new
	end

	if next(old) == nil then
		return new
	end

	local diff: Table = {}

	local function BuildDiff(current: Table, previous: Table, diffRef: Table, visited: { [Table]: boolean })
		if visited[current] or visited[previous] then
			return
		end
		visited[current] = true
		visited[previous] = true

		-- Track deletions (keys in old but not in new)
		for key, previousValue in pairs(previous) do
			local currentValue = current[key]
			if currentValue == nil then
				diffRef[key] = REMOVAL_KEY
			end
		end

		-- Track mutations and additions (keys in new)
		for key, currentValue in pairs(current) do
			local previousValue = previous[key]
			if typeof(currentValue) == "table" and typeof(previousValue) == "table" then
				diffRef[key] = diffRef[key] or {}
				BuildDiff(currentValue, previousValue, diffRef[key], visited)
				if next(diffRef[key]) == nil then
					diffRef[key] = nil
				end
			elseif currentValue ~= previousValue then
				diffRef[key] = currentValue
			end
		end
	end

	BuildDiff(new, old, diff, {})
	return diff
end

--[[
	Counts the number of key-value pairs in a table.
]]
local function GetN(tbl: Table): number
	local n = 0
	for _ in pairs(tbl) do
		n += 1
	end
	return n
end

--[[
	Returns the full path string for a Roblox Instance.
]]
local function GetInstancePath(instance: Instance?, includeInstance: boolean?): string
	local function IsService(serviceName: string): boolean
		local success, result = pcall(function()
			return game:GetService(serviceName) ~= nil
		end)
		return success and result
	end

	local function SanitizeSegment(segment: string): string
		if IsService(segment) then
			return `game:GetService("{segment}")`
		end
		if segment:find("^%d+") or segment:find("[^%w_]") then
			return `["{segment}"]`
		end
		return `.{segment}`
	end

	if not instance then
		return "nil"
	end

	includeInstance = includeInstance ~= false
	if instance == game then
		return if includeInstance then "game" else "nil"
	end

	local path = ""
	local parent = if includeInstance then instance else instance.Parent
	while parent do
		local segment = parent.Name
		path = `{SanitizeSegment(segment)}{path}`
		if IsService(segment) then
			return path
		end
		parent = parent.Parent
	end

	return path
end

--[[
	Sanitizes a table for JSON encoding by converting non-JSON-safe values to strings.
]]
local function SanitizeForJson(tbl: Table, visited_: { [Table]: boolean }?): { [string]: any }
	local visited = visited_ or {}
	if visited[tbl] then
		return { ["__recursive__"] = true }
	end
	visited[tbl] = true

	local result: { [string]: any } = {}
	for k, v in pairs(tbl) do
		local key = tostring(k)
		local valueType = typeof(v)
		if valueType == "table" then
			result[key] = SanitizeForJson(v, visited)
		elseif valueType == "string" or valueType == "number" or valueType == "boolean" then
			result[key] = v
		elseif v ~= nil then
			result[key] = tostring(v)
		end
	end
	return result
end

--[[
	Converts a table to a JSON string.
]]
local function TableToJson(tbl: Table, indent_: number?): string
	local sanitized = SanitizeForJson(tbl)
	local success, result = pcall(function()
		return HttpService:JSONEncode(sanitized)
	end)

	if success and result then
		if indent_ and indent_ > 0 then
			local pretty = result
				:gsub("{%s*", "{\n")
				:gsub("%[%s*", "[\n")
				:gsub("%s*}", "\n}")
				:gsub("%s*%]", "\n]")
				:gsub(",%s*", ",\n")
			return pretty
		end
		return result
	end
	return "{}"
end

-- Lua reserved keywords that cannot be used as bare identifiers
local LUA_RESERVED_KEYWORDS = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
}

--[[
	Converts a table to a Lua code string representation.
]]
local function TableToLua(tbl: Table, indent_: number?, visited_: { [Table]: boolean? }?): string
	local indent = indent_ or 0
	local visited = visited_ or {}
	if visited[tbl] then
		return "{ --[[ RECURSIVE REFERENCE ]] }"
	end

	visited[tbl] = true
	local result: { string } = {}
	local spaces = string.rep("\t", indent)
	local nextSpaces = string.rep("\t", indent + 1)
	table.insert(result, "{\n")
	local keys: { any } = {}
	for k in pairs(tbl) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		if typeof(a) == typeof(b) then
			if typeof(a) == "number" then
				return a < b
			end
			return tostring(a) < tostring(b)
		end
		return typeof(a) == "number"
	end)

	for _, k in pairs(keys) do
		local v = tbl[k]
		local keyStr: string
		if typeof(k) == "number" then
			keyStr = `[{k}]`
		elseif typeof(k) == "string" and k:match("^[%a_][%w_]*$") and not LUA_RESERVED_KEYWORDS[k] then
			-- Valid identifier and not a reserved keyword
			keyStr = k
		else
			-- Use bracket notation for non-identifiers and reserved keywords
			keyStr = `[{("%q"):format(tostring(k))}]`
		end

		local valueStr: string
		if typeof(v) == "table" then
			valueStr = TableToLua(v, indent + 1, visited)
		elseif typeof(v) == "string" then
			valueStr = ("%q"):format(v)
		elseif typeof(v) == "number" or typeof(v) == "boolean" then
			valueStr = tostring(v)
		elseif typeof(v) == "nil" then
			valueStr = "nil"
		elseif typeof(v) == "function" then
			valueStr = "function() end --[[ function ]]"
		elseif typeof(v) == "Instance" then
			valueStr = `nil --[[ Instance: {v:GetFullName()} ]]`
		else
			valueStr = `nil --[[ {typeof(v)}: {tostring(v)} ]]`
		end
		table.insert(result, `{nextSpaces}{keyStr} = {valueStr},\n`)
	end

	table.insert(result, `{spaces}}}`)
	visited[tbl] = nil
	return table.concat(result)
end

--[[
	Formats a table key for display.
	Strings are returned as-is, other types are converted to string with type prefix.
	
	@param key The key to format
	@return The formatted key string
]]
local function FormatFieldKey(key: any): string
	local keyType = typeof(key)
	if keyType == "string" then
		return key
	elseif keyType == "number" then
		return tostring(key)
	elseif keyType == "function" then
		return "<function>"
	elseif keyType == "thread" then
		return "<thread>"
	elseif keyType == "table" then
		return "<table>"
	else
		return `<{keyType}> ({tostring(key)})`
	end
end

--[[
	Formats a number with the specified precision, removing trailing zeros.
	
	@param value The number to format
	@param precision Number of decimal places (-1 for no formatting)
	@return The formatted number string
]]
local function FormatNumber(value: number, precision: number): string
	if precision >= 0 then
		return (`%.{precision}f`):format(value):gsub("(%.%d-)0+$", "%1"):gsub("%.$", "")
	end
	return tostring(value)
end

--[[
	DiffEntry type for tracking diff status of values
]]
type DiffStatus = "added" | "removed" | "modified" | "unchanged"
type DiffEntry = {
	Status: DiffStatus,
	OldValue: any?,
	NewValue: any?,
	ChildDiffs: { [any]: DiffEntry }?,
}

--[[
	Helper: Recursively marks all children of a table with a status.
	Used when an entire table is added or removed.
]]
local function MarkAllChildrenWithStatus(
	tbl: Table,
	status: DiffStatus,
	parentPath: string,
	result: { [string]: DiffEntry },
	visited: { [Table]: boolean }
)
	if visited[tbl] then
		return
	end
	visited[tbl] = true

	for key, value in tbl do
		local pathStr = `{parentPath}.{tostring(key)}`
		result[pathStr] = {
			Status = status,
			OldValue = if status == "removed" then value else nil,
			NewValue = if status == "added" then value else nil,
			ChildDiffs = nil,
		}

		if typeof(value) == "table" then
			MarkAllChildrenWithStatus(value, status, pathStr, result, visited)
		end
	end
end

--[[
	Computes a detailed diff between source and target tables.
	Returns a table mapping path strings to DiffEntry objects.
	
	Source = the "new" state (what you have)
	Target = the "old" state (what you're comparing against)
	
	- "added": exists in source but not in target
	- "removed": exists in target but not in source  
	- "modified": exists in both but values differ
	- "unchanged": exists in both with same value
	
	@param source The source table (current viewer's data)
	@param target The target table (comparison viewer's data)
	@return Table mapping path strings to DiffEntry
]]
local function ComputeDiffWithMetadata(
	source: Table,
	target: Table,
	parentPath_: string?,
	result_: { [string]: DiffEntry }?,
	visited_: { [Table]: boolean }?
): { [string]: DiffEntry }
	local result = result_ or {}
	local parentPath = parentPath_ or ""
	local visited = visited_ or {}

	-- Prevent infinite recursion on circular refs
	if typeof(source) == "table" and visited[source] then
		return result
	end
	if typeof(source) == "table" then
		visited[source] = true
	end
	if typeof(target) == "table" and visited[target] then
		return result
	end
	if typeof(target) == "table" then
		visited[target] = true
	end

	-- Track all keys from both tables
	local allKeys: { [any]: boolean } = {}
	if typeof(source) == "table" then
		for k in source do
			allKeys[k] = true
		end
	end
	if typeof(target) == "table" then
		for k in target do
			allKeys[k] = true
		end
	end

	for key in allKeys do
		local pathStr = if parentPath == "" then tostring(key) else `{parentPath}.{tostring(key)}`
		local sourceValue = if typeof(source) == "table" then source[key] else nil
		local targetValue = if typeof(target) == "table" then target[key] else nil

		local status: DiffStatus

		if sourceValue == nil and targetValue ~= nil then
			-- Removed: in target but not source
			status = "removed"
			result[pathStr] = {
				Status = status,
				OldValue = targetValue,
				NewValue = nil,
				ChildDiffs = nil,
			}
			-- If it's a table, mark all its children as removed too
			if typeof(targetValue) == "table" then
				MarkAllChildrenWithStatus(targetValue, "removed", pathStr, result, {})
			end
		elseif sourceValue ~= nil and targetValue == nil then
			-- Added: in source but not target
			status = "added"
			result[pathStr] = {
				Status = status,
				OldValue = nil,
				NewValue = sourceValue,
				ChildDiffs = nil,
			}
			-- If it's a table, mark all its children as added too
			if typeof(sourceValue) == "table" then
				MarkAllChildrenWithStatus(sourceValue, "added", pathStr, result, {})
			end
		elseif typeof(sourceValue) == "table" and typeof(targetValue) == "table" then
			-- Both are tables - recurse and check for any changes
			ComputeDiffWithMetadata(sourceValue, targetValue, pathStr, result, visited)

			-- Check if any children have changes
			local hasChanges = false
			local pathPrefix = pathStr .. "."
			for childPath, childEntry in result do
				if childPath:sub(1, #pathPrefix) == pathPrefix then
					if childEntry.Status ~= "unchanged" then
						hasChanges = true
						break
					end
				end
			end

			status = if hasChanges then "modified" else "unchanged"
			result[pathStr] = {
				Status = status,
				OldValue = targetValue,
				NewValue = sourceValue,
				ChildDiffs = nil,
			}
		elseif not DeepEqual(sourceValue, targetValue) then
			-- Values differ
			status = "modified"
			result[pathStr] = {
				Status = status,
				OldValue = targetValue,
				NewValue = sourceValue,
				ChildDiffs = nil,
			}
		else
			-- Same value
			status = "unchanged"
			result[pathStr] = {
				Status = status,
				OldValue = targetValue,
				NewValue = sourceValue,
				ChildDiffs = nil,
			}
		end
	end

	return result
end

--- Table Helper ---
local TableHelper = {
	PathToString = PathToString,
	DeepClone = DeepClone,
	DeepEqual = DeepEqual,
	HashValue = HashValue,
	Patch = Patch,
	GetDiff = GetDiff,
	GetN = GetN,
	GetInstancePath = GetInstancePath,
	SanitizeForJson = SanitizeForJson,
	TableToJson = TableToJson,
	TableToLua = TableToLua,
	FormatFieldKey = FormatFieldKey,
	FormatNumber = FormatNumber,
	ComputeDiffWithMetadata = ComputeDiffWithMetadata,
}

return table.freeze(TableHelper)
