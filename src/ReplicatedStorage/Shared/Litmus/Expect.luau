--[[
	Assertion and matcher library for Litmus test framework.
	Provides fluent `expect(value).To.Equal(...)` style assertions with negation via `.Never.To`.
--]]

--!strict

--- Types ---
export type Matchers = {
	Equal: (expected: any) -> (),
	DeepEqual: (expected: any) -> (),
	BeNil: () -> (),
	Exist: () -> (),
	BeA: (typeName: string) -> (),
	BeTruthy: () -> (),
	BeFalsy: () -> (),
	BeNear: (expected: number, tolerance: number?) -> (),
	Throw: (pattern: string?) -> (),
	Contain: (element: any) -> (),
	ContainKey: (key: any) -> (),
	HaveLength: (expected: number) -> (),
	BeGreaterThan: (expected: number) -> (),
	BeGreaterThanOrEqual: (expected: number) -> (),
	BeLessThan: (expected: number) -> (),
	BeLessThanOrEqual: (expected: number) -> (),
	BeInRange: (min: number, max: number) -> (),
	Match: (pattern: string) -> (),
	Satisfy: (predicate: (any) -> boolean, description: string?) -> (),
	BeInteger: () -> (),
}

export type Expectation = {
	To: Matchers,
	Never: { To: Matchers },
}

--- Variables ---
local DEFAULT_TOLERANCE = 1e-9
local MAX_FORMAT_DEPTH = 3
local MAX_FORMAT_ELEMENTS = 8

--- Functions ---
local function DeepEquals(a: any, b: any, depth: number?): boolean
	local d = depth or 0
	if d > 20 then
		return false
	end
	if a == b then
		return true
	end
	if typeof(a) ~= typeof(b) then
		return false
	end
	if typeof(a) == "table" then
		for key, value in a :: { [any]: any } do
			if not DeepEquals(value, (b :: { [any]: any })[key], d + 1) then
				return false
			end
		end
		for key, _ in b :: { [any]: any } do
			if (a :: { [any]: any })[key] == nil then
				return false
			end
		end
		return true
	end
	return false
end

local function FormatValue(value: any, depth: number?): string
	local d = depth or 0
	if d > MAX_FORMAT_DEPTH then
		return "..."
	end
	local t = typeof(value)
	if t == "string" then
		return `"{value}"`
	elseif t == "table" then
		local parts: { string } = {}
		local count = 0
		for k, v in value :: { [any]: any } do
			count += 1
			if count > MAX_FORMAT_ELEMENTS then
				table.insert(parts, "...")
				break
			end
			table.insert(parts, `{FormatValue(k, d + 1)} = {FormatValue(v, d + 1)}`)
		end
		return string.format("{ %s }", table.concat(parts, ", "))
	elseif t == "Vector3" then
		local vec = value :: Vector3
		return `Vector3({vec.X}, {vec.Y}, {vec.Z})`
	else
		return tostring(value)
	end
end

--- Expect ---
local Expect = {}

function Expect.new(actual: any): Expectation
	local function CreateMatchers(negated: boolean): Matchers
		local function Check(condition: boolean, message: string)
			if if negated then condition else not condition then
				error((if negated then "Did not expect: " else "Expected: ") .. message, 3)
			end
		end

		return table.freeze({
			Equal = function(expected: any)
				Check(actual == expected, `{FormatValue(actual)} to equal {FormatValue(expected)}`)
			end,

			DeepEqual = function(expected: any)
				Check(DeepEquals(actual, expected), `{FormatValue(actual)} to deep-equal {FormatValue(expected)}`)
			end,

			BeNil = function()
				Check(actual == nil, `{FormatValue(actual)} to be nil`)
			end,

			Exist = function()
				Check(actual ~= nil, "value to exist (got nil)")
			end,

			BeA = function(typeName: string)
				Check(typeof(actual) == typeName, `{FormatValue(actual)} to be a "{typeName}" (got "{typeof(actual)}")`)
			end,

			BeTruthy = function()
				Check(not not actual, `{FormatValue(actual)} to be truthy`)
			end,

			BeFalsy = function()
				Check(not actual, `{FormatValue(actual)} to be falsy`)
			end,

			BeNear = function(expected: number, tolerance: number?)
				local tol = tolerance or DEFAULT_TOLERANCE
				local diff = math.abs((actual :: number) - expected)
				Check(diff <= tol, `{actual} to be near {expected} (diff: {diff}, tolerance: {tol})`)
			end,

			Throw = function(pattern: string?)
				local ok, err = pcall(actual :: (...any) -> ...any)
				local threw = not ok
				if pattern then
					local matched = threw and string.find(tostring(err), pattern, 1, true) ~= nil
					local message = `function to throw matching "{pattern}"`
					if threw then
						message ..= ` (got: "{tostring(err)}")`
					end
					Check(matched, message)
				else
					local message = "function to throw"
					if threw then
						message ..= ` (got: "{tostring(err)}")`
					end
					Check(threw, message)
				end
			end,

			Contain = function(element: any)
				local found = false
				for _, v in actual :: { any } do
					if DeepEquals(v, element) then
						found = true
						break
					end
				end
				Check(found, `table to contain {FormatValue(element)}`)
			end,

			ContainKey = function(key: any)
				Check((actual :: { [any]: any })[key] ~= nil, `table to contain key {FormatValue(key)}`)
			end,

			HaveLength = function(expected: number)
				local len = #(actual :: { any })
				Check(len == expected, `length {len} to be {expected}`)
			end,

			BeGreaterThan = function(expected: number)
				Check((actual :: number) > expected, `{actual} to be greater than {expected}`)
			end,

			BeGreaterThanOrEqual = function(expected: number)
				Check((actual :: number) >= expected, `{actual} to be greater than or equal to {expected}`)
			end,

			BeLessThan = function(expected: number)
				Check((actual :: number) < expected, `{actual} to be less than {expected}`)
			end,

			BeLessThanOrEqual = function(expected: number)
				Check((actual :: number) <= expected, `{actual} to be less than or equal to {expected}`)
			end,

			BeInRange = function(min: number, max: number)
				local val = actual :: number
				Check(val >= min and val <= max, `{val} to be in range [{min}, {max}]`)
			end,

			Match = function(pattern: string)
				Check(string.find(actual :: string, pattern) ~= nil, `"{actual}" to match pattern "{pattern}"`)
			end,

			Satisfy = function(predicate: (any) -> boolean, description: string?)
				local desc = description or "custom predicate"
				Check(predicate(actual), `{FormatValue(actual)} to satisfy {desc}`)
			end,

			BeInteger = function()
				local val = actual :: number
				Check(typeof(val) == "number" and val % 1 == 0, `{FormatValue(actual)} to be an integer`)
			end,
		})
	end

	return table.freeze({
		To = CreateMatchers(false),
		Never = table.freeze({ To = CreateMatchers(true) }),
	})
end

return table.freeze(Expect)
