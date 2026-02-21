--!strict
--[[
	Helper functions for getting and validating Instance attributes.
]]

--- Types ---
export type Validator = (value: any, name: string) -> (boolean, string?)
export type Transformer<T> = (element: string) -> T

--- Variables ---
local ERROR = [[
	
		[%s] Invalid Attribute
			Attribute: %q (%s)
			Reason: %s
			Instance: %s

]]

--- Attribute Helper ---
local AttributeHelper = {}

function AttributeHelper.Get(instance: Instance, name: string, validator: Validator?, default: any?): any?
	assert(typeof(instance) == "Instance", `Expected "instance" parameter to be an Instance`)
	assert(typeof(name) == "string", `Expected "name" parameter to be a string`)
	assert(
		validator == nil or typeof(validator) == "function",
		`Expected "validator" parameter to be a function or nil`
	)

	local value = instance:GetAttribute(name)
	if validator and (value ~= nil or default ~= nil) then -- If value is nil and default is nil, then we skip validation for an implicit optional attribute.
		local isValid, reason = validator(value, name)
		assert(isValid, ERROR:format("Get", name, tostring(value), reason or "N/A", instance:GetFullName()))
	end
	return if value == nil then default else value
end

-- The "with" parameter accepts any valid Lua pattern.
function AttributeHelper.GetWith(instance: Instance, with: string, truncateWith: boolean?): { [string]: any }
	assert(typeof(instance) == "Instance", `Expected "instance" parameter to be an Instance`)
	assert(typeof(with) == "string", `Expected "with" parameter to be a string`)

	local filteredAttributes: { [string]: any } = {}
	for name, value in pairs(instance:GetAttributes()) do
		if not name:find(with) then
			continue
		end

		filteredAttributes[if truncateWith then name:gsub(with, "") else name] = value
	end
	return filteredAttributes
end

function AttributeHelper.GetAsArray<T>(
	instance: Instance,
	name: string,
	strip: boolean?, -- Defaults to false.
	validator: Validator?,
	transformer: Transformer<T>?,
	default: any?
): { T }
	assert(typeof(instance) == "Instance", `Expected "instance" parameter to be an Instance`)
	assert(typeof(name) == "string", `Expected "name" parameter to be a string`)
	assert(
		validator == nil or typeof(validator) == "function",
		`Expected "validator" parameter to be a function or nil`
	)
	assert(
		transformer == nil or typeof(transformer) == "function",
		`Expected "transformer" parameter to be a function or nil`
	)

	local value = (instance:GetAttribute(name) or default) :: string?
	assert(
		value == nil or typeof(value) == "string",
		ERROR:format("GetAsArray", name, tostring(value), "Expected a string or nil", instance:GetFullName())
	)
	if value == nil or value == "" then
		return {}
	end

	local elements: { T } = {}
	for _, element in pairs(value:split(",")) do
		if strip then
			element = element:match("^%s*(.-)%s*$") or ""
		end
		if element == "" then
			continue
		end
		if validator then
			local isValid, reason = validator(element, name)
			assert(isValid, ERROR:format("GetAsArray -> for", name, element, reason or "N/A", instance:GetFullName()))
		end
		if transformer then
			table.insert(elements, transformer(element))
		else
			table.insert(elements, (element :: any) :: T)
		end
	end
	return elements
end

function AttributeHelper.GetAsSet<T>(
	instance: Instance,
	name: string,
	strip: boolean?, -- Defaults to false.
	validator: Validator?,
	transformer: Transformer<T>?,
	default: any?
): { [T]: boolean }
	local set: { [T]: boolean } = {}
	for _, element in pairs(AttributeHelper.GetAsArray(instance, name, strip, validator, transformer, default)) do
		set[element] = true
	end
	return set
end

function AttributeHelper.OnAttributeChanged(
	instance: Instance,
	name: string,
	callback: (any) -> (),
	validator: Validator?,
	default: any?
): RBXScriptConnection
	assert(typeof(instance) == "Instance", `Expected "instance" parameter to be an Instance`)
	assert(typeof(name) == "string", `Expected "name" parameter to be a string`)
	assert(typeof(callback) == "function", `Expected "callback" parameter to be a function`)
	assert(
		validator == nil or typeof(validator) == "function",
		`Expected "validator" parameter to be a function or nil`
	)

	local function OnAttributeChanged()
		callback(AttributeHelper.Get(instance, name, validator, default))
	end
	task.defer(OnAttributeChanged)
	return instance:GetAttributeChangedSignal(name):Connect(OnAttributeChanged)
end

return table.freeze(AttributeHelper)
