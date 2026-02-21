--!strict
--[[
	TableEditor - A comprehensive table viewing and editing module for Roblox.
	
	This is the main module file that orchestrates all components:
	- Types: Type definitions (imported from Types.luau)
	- Constants: Default options, colors, sizes (imported from Constants.luau)
	- Helpers: TableHelper, SearchHelper, ImageHelper, UiHelper
	- Packages: Signal, Trove
	
	Features:
	- View and edit Lua tables in a tree structure
	- Search and filter by key, value, or type
	- Syntax highlighting for different value types
	- Recursive table detection and duplicate reference tracking
	- Lazy loading for performance
	- Flash animations for changes
	- Linking multiple viewers together
	- Export to JSON or Lua format
	- Keybind support for toggling visibility
]]

--- Services ---
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

--- Imports ---
local Constants = require(script.Constants)
local Signal = require(script.Packages.Signal)
local Trove = require(script.Packages.Trove)
local Types = require(script.Types)

local ImageHelper = require(script.Helpers.ImageHelper)
local SearchHelper = require(script.Helpers.SearchHelper)
local SettingsMenuHelper = require(script.Helpers.SettingsMenuHelper)
local TableHelper = require(script.Helpers.TableHelper)
local UiHelper = require(script.Helpers.UiHelper)

--- Types ---
export type TableEditorImpl = Types.TableEditorImpl
export type Table = { [any]: any }
export type SyntaxColors = Types.SyntaxColors
export type SortMode = Types.SortMode
export type SearchTarget = Types.SearchTarget
export type SearchOptions = Types.SearchOptions
export type SearchResult = Types.SearchResult
export type FilterOptions = Types.FilterOptions
export type TypeOrdering = Types.TypeOrdering
export type ViewerOptions = Types.ViewerOptions
export type SignalConnection = Types.SignalConnection
export type DataEditedInfo = Types.DataEditedInfo
export type OnValueChangedOptions = Types.OnValueChangedOptions
export type TableEditor = Types.TableEditor
export type Signal<T...> = Types.Signal<T...>

type ViewerOptionsInternal = Types.ViewerOptionsInternal
type TableEditorGui = Types.TableEditorGui
type EntryGui = Types.EntryGui
type Association = Types.Association
type Associations = Types.Associations
type SearchState = Types.SearchState
type FilterOptionsState = Types.FilterOptionsState
type ValueWatchers = Types.ValueWatchers
type InternalTableEditor = Types.TableEditorInternal

--- Variables ---
local REMOVAL_KEY = Constants.REMOVAL_KEY
local DEFAULT_OPTIONS = Constants.DEFAULT_OPTIONS
local COLORS = Constants.COLORS
local SIZES = Constants.SIZES
local TRANSPARENCY = Constants.TRANSPARENCY
local POSITION_OFFSET = Constants.POSITION_OFFSET
local CELL_SIZE = Constants.CELL_SIZE
local CELL_MULTIPLIER = Constants.CELL_MULTIPLIER

local PathToString = TableHelper.PathToString
local DeepClone = TableHelper.DeepClone
local DeepEqual = TableHelper.DeepEqual
local HashValue = TableHelper.HashValue
local Patch = TableHelper.Patch
local GetDiff = TableHelper.GetDiff
local GetN = TableHelper.GetN
local GetInstancePath = TableHelper.GetInstancePath
local TableToJson = TableHelper.TableToJson
local TableToLua = TableHelper.TableToLua
local FormatFieldKey = TableHelper.FormatFieldKey
local FormatNumber = TableHelper.FormatNumber
local ComputeDiffWithMetadata = TableHelper.ComputeDiffWithMetadata

local FuzzyMatch = SearchHelper.FuzzyMatch
local MatchesTypeExclusion = SearchHelper.MatchesTypeExclusion
local ParseInputValue = SearchHelper.ParseInputValue
local ParseKeyInput = SearchHelper.ParseKeyInput
local FiltersEqual = SearchHelper.FiltersEqual
local DebouncedFilterUpdate = SearchHelper.DebouncedFilterUpdate
local GenerateAutoKey = SearchHelper.GenerateAutoKey

local CreateIcon = ImageHelper.CreateIcon
local CreateMaterialIcon = ImageHelper.CreateMaterialIcon
local SetMaterialIcon = ImageHelper.SetMaterialIcon

local CreateCorner = UiHelper.CreateCorner
local CreateStroke = UiHelper.CreateStroke
local CreatePadding = UiHelper.CreatePadding
local CreateSizeConstraint = UiHelper.CreateSizeConstraint
local CreateHeader = UiHelper.CreateHeader
local CreateFooter = UiHelper.CreateFooter
local CreateViewerArea = UiHelper.CreateViewerArea
local CreateTooltip = UiHelper.CreateTooltip
local CreateGhostRow = UiHelper.CreateGhostRow
local FindHeaderChild = UiHelper.FindHeaderChild
local FindFooterChild = UiHelper.FindFooterChild

local linkGroups: { [number]: { [string]: boolean } } = {}
local idToViewer: { [string]: any } = {}
local nextLinkGroupId = 1
local filterDebounceThreads: { [string]: thread } = {}
local quickViews: { [string]: any } = {} -- Quick view instances keyed by alias

-- Server/Client detection and RemoteEvent infrastructure
local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()
local REMOTE_EVENT_NAME = "TableEditor_ServerView"
local serverViewRemote: RemoteEvent? = nil
local pendingVerifications: { [string]: { OriginalData: any, Name: string, PlayerName: string } } = {}

--- Functions ---

--[[
	Finds a non-overlapping position for a new viewer window.
]]
local function FindNonOverlappingPosition(size: Vector2, screenSize: Vector2?): UDim2
	local camera = workspace.CurrentCamera
	local viewportSize = screenSize or (camera and camera.ViewportSize) or Vector2.new(1920, 1080)
	local viewerCount = 0
	local occupiedCells: { [number]: boolean } = {}

	for _, viewer in pairs(idToViewer) do
		local ui = viewer:GetUI()
		if ui and ui.Visible then
			viewerCount += 1
			-- Mark all cells this viewer occupies
			local pos = ui.AbsolutePosition
			local sz = ui.AbsoluteSize
			local startCellX = math.floor(pos.X / CELL_SIZE)
			local startCellY = math.floor(pos.Y / CELL_SIZE)
			local endCellX = math.floor((pos.X + sz.X) / CELL_SIZE)
			local endCellY = math.floor((pos.Y + sz.Y) / CELL_SIZE)

			for cx = startCellX, endCellX do
				for cy = startCellY, endCellY do
					occupiedCells[cx * CELL_MULTIPLIER + cy] = true
				end
			end
		end
	end

	if viewerCount == 0 then
		return UDim2.fromScale(0.25, 0.375)
	end

	local function IsPositionFree(testPos: Vector2): boolean
		if testPos.X < 0 or testPos.Y < 0 then
			return false
		end
		if testPos.X + size.X > viewportSize.X or testPos.Y + size.Y > viewportSize.Y then
			return false
		end

		local startCellX = math.floor(testPos.X / CELL_SIZE)
		local startCellY = math.floor(testPos.Y / CELL_SIZE)
		local endCellX = math.floor((testPos.X + size.X) / CELL_SIZE)
		local endCellY = math.floor((testPos.Y + size.Y) / CELL_SIZE)

		for cx = startCellX, endCellX do
			for cy = startCellY, endCellY do
				if occupiedCells[cx * CELL_MULTIPLIER + cy] then
					return false
				end
			end
		end
		return true
	end

	-- Try cascade positions
	for i = 1, math.min(viewerCount + 1, 20) do
		local cascadePos = Vector2.new(50 + POSITION_OFFSET * i, 50 + POSITION_OFFSET * i)
		if IsPositionFree(cascadePos) then
			return UDim2.fromOffset(cascadePos.X, cascadePos.Y)
		end
	end

	-- Try grid positions
	local gridSpacingX = size.X + 20
	local gridSpacingY = size.Y + 20
	local maxCols = math.min(math.floor(viewportSize.X / gridSpacingX), 10)
	local maxRows = math.min(math.floor(viewportSize.Y / gridSpacingY), 10)
	for row = 0, maxRows - 1 do
		for col = 0, maxCols - 1 do
			local gridPos = Vector2.new(col * gridSpacingX + 50, row * gridSpacingY + 50)
			if IsPositionFree(gridPos) then
				return UDim2.fromOffset(gridPos.X, gridPos.Y)
			end
		end
	end

	-- Fallback
	local fallbackX = (50 + POSITION_OFFSET * viewerCount) % math.max(1, viewportSize.X - size.X)
	local fallbackY = (50 + POSITION_OFFSET * viewerCount) % math.max(1, viewportSize.Y - size.Y)
	return UDim2.fromOffset(math.max(50, fallbackX), math.max(50, fallbackY))
end

--- Table Editor ---
local TableEditor = {} :: any
TableEditor.__index = TableEditor

--[[
	Creates a new TableEditor instance.
	
	@param data The table to view/edit
	@param options Optional configuration options
	@return A new TableEditor instance
]]
function TableEditor.new(data: Table, options: ViewerOptions?): TableEditor
	local mergedOptions = DeepClone(DEFAULT_OPTIONS)
	local positionExplicitlySet = options ~= nil and (options :: any).ViewerPosition ~= nil

	if options then
		for key, value in pairs(options :: any) do
			if typeof(value) == "table" and typeof((mergedOptions :: any)[key]) == "table" then
				for subKey, subValue in pairs(value) do
					(mergedOptions :: any)[key][subKey] = subValue
				end
			else
				(mergedOptions :: any)[key] = value
			end
		end
	end

	if not positionExplicitlySet then
		mergedOptions.ViewerPosition = FindNonOverlappingPosition(mergedOptions.StartingSize)
	end

	local self = (
		setmetatable({
			Data = data,
			Options = mergedOptions,

			_id = HttpService:GenerateGUID(false),
			_associations = {} :: Associations,
			_childrenIndex = {} :: { [Association]: { Association } },
			_keyFilters = {} :: { string },
			_valueFilters = {} :: { string },
			_typeFilters = {} :: { string },
			_typeExclusions = {} :: { string },
			_filterCombineMode = nil :: ("and" | "or")?,
			_filterMatchCount = 0,
			_filterOptions = {
				Key = nil :: FilterOptions?,
				Value = nil :: FilterOptions?,
			} :: FilterOptionsState,
			_searchState = {
				Query = nil :: string?,
				Options = nil :: SearchOptions?,
				Results = {} :: { SearchResult },
				CurrentIndex = 0,
				HighlightedAssociation = nil :: Association?,
			} :: SearchState,
			_ui = nil :: TableEditorGui?,
			_frozen = false,
			_pendingUpdates = nil :: { Table }?,
			_visible = true,
			_minimized = false,
			_collapsed = false,
			_tableRefs = {} :: { [Table]: string },
			_linkGroupId = nil :: number?,
			_inLinkMode = false,
			_rootViewer = nil :: TableEditor?,
			_rootPath = nil :: { any }?,
			_childViewers = {} :: { [string]: TableEditor },
			_lastSize = nil :: UDim2?,
			_pendingSearchFlashes = {} :: { [Association]: Color3 },
			_flashedAssociations = {} :: { [Association]: boolean },
			_flashThread = nil :: thread?,
			_guiToAssociation = {} :: { [Frame]: Association },
			_valueWatchers = {} :: ValueWatchers,
			_onDataEditedCallbacks = {} :: { (info: DataEditedInfo) -> () },
			_linkModeConnection = nil :: RBXScriptConnection?,
			_linkModeHighlights = {} :: { [string]: Frame },
			_isFiltering = nil :: boolean?,
			_snapshots = {} :: { TableEditor },
			_parentViewer = nil :: TableEditor?,
			_frozenValues = {} :: { [string]: any }, -- Path string -> frozen value
			_diffState = {
				Active = false,
				TargetViewer = nil,
				TargetViewerId = nil,
				DiffData = {},
				OriginalData = nil,
				SelectionMode = false,
				SelectionOverlays = {},
				EscapeConnection = nil,
				TargetDestroyConnection = nil,
				Stats = nil,
			},
			_trove = Trove.new(),
			OnDataEdited = Signal.new(),
		}, TableEditor) :: any
	) :: TableEditor

	self._ui = self:_CreateBaseUI()
	self:_UpdateAssociations()

	if mergedOptions.Parent then
		self._ui.Parent = mergedOptions.Parent
	else
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = `TableEditor_{mergedOptions.Title}`
		screenGui.ResetOnSpawn = false
		screenGui.DisplayOrder = 1000
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		self._ui.Parent = screenGui
		screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end

	if mergedOptions.DefaultCollapsed then
		self:Collapse()
	elseif mergedOptions.DefaultMinimized then
		self:Minimize()
	end

	self:_SetupKeybindings()
	idToViewer[self._id] = self

	return self :: TableEditor
end

--[[
	Updates the viewer with new data, handling animations and diff detection.
]]
function TableEditor.Update(self: InternalTableEditor, newData: Table)
	if not self._ui or not self.Options then
		return
	end

	if self._frozen then
		self._pendingUpdates = self._pendingUpdates or {}
		table.insert(self._pendingUpdates :: { Table }, DeepClone(newData))
		return
	end

	-- If same reference, force a full rebuild (data may have been mutated in place)
	local isSameReference = newData == self.Data
	local lastData = self.Data
	self.Data = newData

	if isSameReference then
		-- Full rebuild: remove stale associations that no longer exist in data
		self:_RebuildAssociations()
	else
		self:_UpdateAssociations(lastData)
	end

	self:_UpdateFiltersAndExclusions()
	self:_UpdateLink()

	if self.Options.AutoSizeToContent then
		self:AutoSize()
	end

	for _, childViewer in pairs(self._childViewers) do
		if childViewer._ui and childViewer._rootPath then
			local current: any = self.Data
			for _, key in pairs(childViewer._rootPath) do
				if typeof(current) ~= "table" then
					break
				end
				current = current[key]
			end
			if typeof(current) == "table" then
				childViewer:Update(current)
			end
		end
	end

	-- Update all snapshots (they handle frozen state internally)
	for _, snapshot in pairs(self._snapshots) do
		if snapshot._ui then
			snapshot:Update(TableHelper.DeepClone(newData))
		end
	end
end

--[[
	Applies a patch to the data, only updating changed values.
]]
function TableEditor.Patch(self: InternalTableEditor, patch: Table)
	if not self._ui or not self.Options then
		return
	end

	if self._frozen then
		if not self._pendingUpdates then
			self._pendingUpdates = {}
		end
		local pending = self._pendingUpdates :: { Table }
		local numPending = #pending
		local baseData = if numPending > 0 then pending[numPending] else self.Data
		local patched = DeepClone(baseData)
		Patch(patched, patch)
		table.insert(pending, patched)
		return
	end

	Patch(self.Data, patch)
	self:_UpdateAssociationsFromPatch(patch, "")
	self:_UpdateFiltersAndExclusions()
	self:_UpdateLink()

	if self.Options.AutoSizeToContent then
		self:AutoSize()
	end

	for _, childViewer in pairs(self._childViewers) do
		if childViewer._ui and childViewer._rootPath then
			local subPatch: any = patch
			for _, key in pairs(childViewer._rootPath) do
				if typeof(subPatch) ~= "table" then
					subPatch = nil
					break
				end
				subPatch = subPatch[key]
			end
			if typeof(subPatch) == "table" and next(subPatch) then
				childViewer:Patch(subPatch)
			end
		end
	end
end

--[[
	Returns the UI frame for this viewer.
]]
function TableEditor.GetUI(self: InternalTableEditor): TableEditorGui?
	return self._ui
end

--[[
	Returns the current data table.
]]
function TableEditor.GetData(self: InternalTableEditor): Table
	return self.Data
end

--[[
	Returns all associations (path -> Association mappings).
]]
function TableEditor.GetAssociations(self: InternalTableEditor): { [string]: Association }
	return self._associations
end

--[[
	Destroys the viewer and cleans up all resources.
]]
function TableEditor.Destroy(self: InternalTableEditor)
	-- Clean up all connections and tracked objects via Trove
	if self._trove then
		self._trove:Destroy()
	end

	-- Cancel flash thread (not in trove since it's a task)
	if self._flashThread then
		task.cancel(self._flashThread)
		self._flashThread = nil
	end

	-- Cancel debounce threads
	for _, suffix in pairs({ "", "_filter", "_exclusion" }) do
		local key = self._id .. suffix
		local debounceThread = filterDebounceThreads[key]
		if debounceThread then
			task.cancel(debounceThread)
			filterDebounceThreads[key] = nil
		end
	end

	-- Clean up diff mode
	if self._diffState then
		-- Exit diff mode if active
		if self._diffState.Active then
			self:StopDiff()
		end
		-- Cancel selection mode if active
		if self._diffState.SelectionMode then
			self:CancelDiffSelection()
		end
		-- Clean up any connections
		if self._diffState.EscapeConnection then
			self._diffState.EscapeConnection:Disconnect()
			self._diffState.EscapeConnection = nil
		end
		if self._diffState.TargetDestroyConnection then
			self._diffState.TargetDestroyConnection:Disconnect()
			self._diffState.TargetDestroyConnection = nil
		end
	end

	-- Clean up link mode highlights
	if self._linkModeHighlights then
		for _, highlight in pairs(self._linkModeHighlights) do
			pcall(function()
				highlight:Destroy()
			end)
		end
		table.clear(self._linkModeHighlights)
	end

	-- Clear pending search flashes
	self:_ClearPendingSearchFlashes()

	-- Remove from link group
	if self._linkGroupId and linkGroups[self._linkGroupId] then
		linkGroups[self._linkGroupId][self._id] = nil
		if not next(linkGroups[self._linkGroupId]) then
			linkGroups[self._linkGroupId] = nil
		else
			for viewerId in pairs(linkGroups[self._linkGroupId]) do
				local viewer = idToViewer[viewerId]
				if viewer then
					(viewer :: any):_UpdateLink()
				end
			end
		end
	end

	-- Destroy child viewers
	for _, childViewer in pairs(self._childViewers) do
		childViewer:Destroy()
	end
	table.clear(self._childViewers)

	-- Remove from root viewer's child list
	if self._rootViewer and self._rootViewer._childViewers then
		local rootViewer = self._rootViewer
		for pathStr, child in pairs(rootViewer._childViewers) do
			if child == self then
				rootViewer._childViewers[pathStr] = nil
				break
			end
		end
	end

	-- Destroy UI
	local ui = self._ui
	self._ui = nil
	if ui then
		local parent = ui.Parent
		pcall(game.Destroy, ui)
		if parent and parent:IsA("ScreenGui") and #parent:GetChildren() == 0 then
			pcall(game.Destroy, parent)
		end
	end

	-- Remove from global registry
	idToViewer[self._id] = nil

	-- Clean up signals and data
	self.OnDataEdited:Destroy()
	table.clear(self._valueWatchers)
	table.clear(self._onDataEditedCallbacks)
	table.clear(self._associations)
	table.clear(self._childrenIndex)
	table.clear(self._guiToAssociation)
	table.clear(self._keyFilters)
	table.clear(self._typeExclusions)
	table.clear(self._tableRefs)
	table.clear(self._pendingSearchFlashes)
	self.Data = nil :: any
	self.Options = nil :: any
end

--[[
	Links this viewer with another for synchronized updates.
]]
function TableEditor.Link(self: InternalTableEditor, viewer: InternalTableEditor)
	local groupId: number
	if self._linkGroupId and viewer._linkGroupId and self._linkGroupId ~= viewer._linkGroupId then
		groupId = self._linkGroupId
		local otherGroupId = viewer._linkGroupId
		local otherGroup = linkGroups[otherGroupId]
		if otherGroup then
			for viewerId in pairs(otherGroup) do
				linkGroups[groupId][viewerId] = true
				local v = idToViewer[viewerId]
				if v then
					v._linkGroupId = groupId
				end
			end
		end
		linkGroups[otherGroupId] = nil
	elseif self._linkGroupId then
		groupId = self._linkGroupId
	elseif viewer._linkGroupId then
		groupId = viewer._linkGroupId
	else
		groupId = nextLinkGroupId
		nextLinkGroupId += 1
		linkGroups[groupId] = {}
	end

	linkGroups[groupId][self._id] = true
	linkGroups[groupId][viewer._id] = true
	self._linkGroupId = groupId
	viewer._linkGroupId = groupId

	for viewerId in pairs(linkGroups[groupId]) do
		local v = idToViewer[viewerId]
		if v then
			(v :: any):_UpdateLink()
		end
	end
end

--[[
	Unlinks this viewer from another.
]]
function TableEditor.Unlink(self: InternalTableEditor, viewer: InternalTableEditor)
	if not self._linkGroupId or self._linkGroupId ~= viewer._linkGroupId then
		return
	end

	local groupId = self._linkGroupId
	linkGroups[groupId][viewer._id] = nil
	viewer._linkGroupId = nil

	local count = 0
	for _ in pairs(linkGroups[groupId]) do
		count += 1
	end
	if count <= 1 then
		linkGroups[groupId] = nil
		self._linkGroupId = nil
	end

	self:_UpdateLink()
	viewer:_UpdateLink()
end

-- Freeze/Snapshot Methods

--[[
	Freezes the viewer, preventing updates until unfrozen.
]]
function TableEditor.Freeze(self: InternalTableEditor)
	if not self.Options then
		return
	end
	self._frozen = true
	self._pendingUpdates = {}

	-- Update UI elements to show frozen state
	if not self._ui then
		return
	end

	local freezeBtn = FindHeaderChild(self._ui.Header, "FreezeButton") :: ImageButton?
	if freezeBtn then
		SetMaterialIcon(freezeBtn, "PlayArrow", Color3.fromRGB(100, 200, 100))
	end
end

--[[
	Unfreezes the viewer, applying any pending updates.
]]
function TableEditor.Unfreeze(self: InternalTableEditor)
	if not self.Options then
		return
	end
	self._frozen = false
	if self._ui then
		local freezeBtn = FindHeaderChild(self._ui.Header, "FreezeButton") :: ImageButton?
		if freezeBtn then
			SetMaterialIcon(freezeBtn, "Pause", Color3.fromRGB(100, 180, 255))
		end
	end

	if self._pendingUpdates and self._pendingUpdates[1] then
		local lastUpdate = self._pendingUpdates[#self._pendingUpdates]
		self._pendingUpdates = nil
		self:Update(lastUpdate)
	end
end

--[[
	Returns whether the viewer is frozen.
]]
function TableEditor.IsFrozen(self: InternalTableEditor): boolean
	return self._frozen
end

--[[
	Freezes a specific value at the given path.
	The value will not update when the data changes.
	
	@param path Array of keys representing the path to the value
]]
function TableEditor.FreezeValue(self: InternalTableEditor, path: { any })
	local pathStr = PathToString(path)
	local value = self.Data
	for _, key in ipairs(path) do
		if typeof(value) ~= "table" then
			return
		end
		value = value[key]
	end

	if typeof(value) == "table" then
		self._frozenValues[pathStr] = TableHelper.DeepClone(value)
	else
		self._frozenValues[pathStr] = value
	end

	-- Update the UI to show frozen state
	local association = self._associations[pathStr]
	if association and association.Gui then
		local freezeBtn = association.Gui:FindFirstChild("InfoBox")
			and association.Gui.InfoBox:FindFirstChild("FreezeValueButton")
		if freezeBtn then
			local icon = freezeBtn:FindFirstChild("Icon")
			if icon then
				icon.ImageColor3 = Color3.fromRGB(100, 180, 255)
			end
			freezeBtn.Visible = true
		end
	end
end

--[[
	Unfreezes a specific value at the given path.
	The value will resume updating when the data changes.
	
	@param path Array of keys representing the path to the value
]]
function TableEditor.UnfreezeValue(self: InternalTableEditor, path: { any })
	local pathStr = PathToString(path)
	self._frozenValues[pathStr] = nil

	-- Update the UI to show unfrozen state
	local association = self._associations[pathStr]
	if association and association.Gui then
		local freezeBtn = association.Gui:FindFirstChild("InfoBox")
			and association.Gui.InfoBox:FindFirstChild("FreezeValueButton")
		if freezeBtn then
			local icon = freezeBtn:FindFirstChild("Icon")
			if icon then
				icon.ImageColor3 = Color3.fromRGB(150, 150, 155)
			end
		end
	end
end

--[[
	Returns whether a specific value at the given path is frozen.
	
	@param path Array of keys representing the path to the value
	@return boolean True if the value is frozen
]]
function TableEditor.IsValueFrozen(self: InternalTableEditor, path: { any }): boolean
	local pathStr = PathToString(path)
	return self._frozenValues[pathStr] ~= nil
end

--[[
	Returns a list of all frozen value paths.
	
	@return Array of path strings that are currently frozen
]]
function TableEditor.GetFrozenValues(self: InternalTableEditor): { string }
	local paths = {}
	for pathStr in pairs(self._frozenValues) do
		table.insert(paths, pathStr)
	end
	return paths
end

--[[
	Unfreezes all frozen values.
]]
function TableEditor.UnfreezeAllValues(self: InternalTableEditor)
	for pathStr in pairs(self._frozenValues) do
		self._frozenValues[pathStr] = nil
		local association = self._associations[pathStr]
		if association and association.Gui then
			local freezeBtn = association.Gui:FindFirstChild("InfoBox")
				and association.Gui.InfoBox:FindFirstChild("FreezeValueButton")
			if freezeBtn then
				local icon = freezeBtn:FindFirstChild("Icon")
				if icon then
					icon.ImageColor3 = Color3.fromRGB(150, 150, 155)
				end
			end
		end
	end
end

--[[
	Updates the freeze button UI state for all entries based on _frozenValues.
	Also updates the association values and display to show frozen values.
	Called after frozen values are copied to a new viewer.
]]
function TableEditor._RefreshFreezeButtonStates(self: InternalTableEditor)
	for pathStr, association in pairs(self._associations) do
		if typeof(association) == "table" and association.Gui then
			local frozenValue = self._frozenValues[pathStr]
			local isFrozen = frozenValue ~= nil

			-- If frozen, update association value and display to show frozen value
			if isFrozen then
				association.Value = frozenValue
				self:_UpdateEntryUI(association)
			end

			local infoBox = association.Gui:FindFirstChild("InfoBox") :: Frame?
			if infoBox then
				local contentRow = infoBox:FindFirstChild("ContentRow") :: Frame?
				if contentRow then
					local freezeBtn = contentRow:FindFirstChild("FreezeValueButton") :: ImageButton?
					if freezeBtn then
						freezeBtn.Visible = isFrozen -- Will show on hover if not frozen
						SetMaterialIcon(
							freezeBtn,
							if isFrozen then "PlayArrow" else "Pause",
							if isFrozen then Color3.fromRGB(100, 200, 100) else Color3.fromRGB(100, 180, 255)
						)
					end
				end
			end
		end
	end
end

--[[
	================================================================================
	DIFF MODE - Compare two viewers side-by-side with VS Code style diff indicators
	================================================================================
]]

--[[
	Starts the viewer selection mode for diff comparison.
	Highlights all other visible viewers and waits for user to click one.
]]
function TableEditor.StartDiffSelection(self: InternalTableEditor)
	if self._diffState.Active then
		self:StopDiff()
	end

	-- Cancel any other viewer's selection mode first (only one selection at a time)
	for viewerId, viewer in idToViewer do
		if viewerId ~= self._id and viewer._diffState and viewer._diffState.SelectionMode then
			viewer:CancelDiffSelection()
		end
	end

	self._diffState.SelectionMode = true
	self:_CreateDiffSelectionOverlays()

	-- Add escape key handler to cancel selection
	if not self._diffState.EscapeConnection then
		self._diffState.EscapeConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape and self._diffState.SelectionMode then
				self:CancelDiffSelection()
			end
		end)
	end
end

--[[
	Cancels the viewer selection mode without starting a diff.
]]
function TableEditor.CancelDiffSelection(self: InternalTableEditor)
	self._diffState.SelectionMode = false
	self:_ClearDiffSelectionOverlays()

	-- Disconnect escape handler
	if self._diffState.EscapeConnection then
		self._diffState.EscapeConnection:Disconnect()
		self._diffState.EscapeConnection = nil
	end
end

--[[
	Starts a diff comparison with the target viewer.
	The source viewer (self) shows what's different compared to target.
	
	@param targetViewer The viewer to compare against
	@return boolean True if diff started successfully
]]
function TableEditor.StartDiff(self: InternalTableEditor, targetViewer: TableEditor): boolean
	if self._diffState.Active then
		self:StopDiff()
	end

	-- Cancel selection mode if active
	if self._diffState.SelectionMode then
		self:CancelDiffSelection()
	end

	-- Can't diff with self
	if targetViewer == self then
		warn("TableEditor: Cannot diff viewer with itself")
		return false
	end

	-- Store original data for restoration
	self._diffState.OriginalData = DeepClone(self.Data)
	self._diffState.TargetViewer = targetViewer
	self._diffState.TargetViewerId = (targetViewer :: any)._id

	-- Freeze the viewer during diff mode
	self:Freeze()

	-- Enter diff mode
	self:_EnterDiffMode(targetViewer :: InternalTableEditor)

	return true
end

--[[
	Stops the diff comparison and restores normal view.
]]
function TableEditor.StopDiff(self: InternalTableEditor)
	if not self._diffState.Active then
		return
	end

	self:_ExitDiffMode()

	-- Unfreeze if we froze for diff
	self:Unfreeze()
end

--[[
	Returns whether the viewer is currently in diff mode.
]]
function TableEditor.IsInDiffMode(self: InternalTableEditor): boolean
	return self._diffState.Active
end

--[[
	Returns the target viewer being compared against, or nil if not in diff mode.
]]
function TableEditor.GetDiffTarget(self: InternalTableEditor): TableEditor?
	return self._diffState.TargetViewer
end

--[[
	Returns diff statistics (added, removed, modified counts) or nil if not in diff mode.
]]
function TableEditor.GetDiffStats(self: InternalTableEditor): { Added: number, Removed: number, Modified: number }?
	if not self._diffState.Active then
		return nil
	end
	return self._diffState.Stats
end

--[[
	Returns whether the viewer is currently in diff selection mode.
]]
function TableEditor.IsInDiffSelectionMode(self: InternalTableEditor): boolean
	return self._diffState.SelectionMode
end

--[[
	Refreshes the diff comparison, recalculating differences.
	Useful when the target viewer's data has changed.
	Returns true if refresh succeeded, false if not in diff mode or target is gone.
]]
function TableEditor.RefreshDiff(self: InternalTableEditor): boolean
	if not self._diffState.Active then
		return false
	end

	local targetViewer = self._diffState.TargetViewer :: InternalTableEditor?
	if not targetViewer or not targetViewer._ui then
		-- Target viewer no longer exists
		self:StopDiff()
		return false
	end

	-- Re-enter diff mode with the same target (this recomputes the diff)
	self:_EnterDiffMode(targetViewer)
	return true
end

--[[
	Internal: Enters diff mode with the target viewer.
]]
function TableEditor._EnterDiffMode(self: InternalTableEditor, targetViewer: InternalTableEditor)
	self._diffState.Active = true

	-- Compute diff between source (self) and target
	local sourceData = self.Data
	local targetData = targetViewer.Data

	-- Warn if both viewers point to the exact same data table
	if sourceData == targetData then
		warn(
			"TableEditor: Both viewers reference the same data table. Changes in one affect both. Consider using DeepCopy if you need independent copies."
		)
	end

	self._diffState.DiffData = ComputeDiffWithMetadata(sourceData, targetData)

	-- Calculate diff statistics
	-- We count top-level entries and entries whose parent path is not also changed
	-- This avoids double-counting when a parent table is added/removed along with all children
	local addedCount, removedCount, modifiedCount = 0, 0, 0
	for pathStr, entry in self._diffState.DiffData do
		if entry.Status ~= "unchanged" then
			-- Check if parent path has the same status (would mean this is a child of a changed table)
			local parentPath = pathStr:match("(.+)%.[^%.]+$")
			local parentEntry = if parentPath then self._diffState.DiffData[parentPath] else nil
			local parentHasSameStatus = parentEntry and parentEntry.Status == entry.Status

			-- Only count if parent doesn't have the same status (avoids double counting children)
			if not parentHasSameStatus then
				if entry.Status == "added" then
					addedCount += 1
				elseif entry.Status == "removed" then
					removedCount += 1
				elseif entry.Status == "modified" then
					modifiedCount += 1
				end
			end
		end
	end
	self._diffState.Stats = {
		Added = addedCount,
		Removed = removedCount,
		Modified = modifiedCount,
	}

	-- Watch for target viewer destruction
	if targetViewer._ui then
		self._diffState.TargetDestroyConnection = targetViewer._ui.Destroying:Connect(function()
			self:StopDiff()
		end)
	end

	-- Store target viewer reference for ghost entry creation
	self._diffState.TargetViewer = targetViewer

	-- Create ghost entries for root-level removed items (items only in target)
	self:_CreateGhostEntriesForRemovedRootItems()

	-- Also create ghost entries for any currently expanded tables
	for pathStr, association in self._associations do
		if association.Expanded and association.ChildrenLoaded and not association.IsGhost then
			self:_CreateGhostEntriesForRemovedItems(association, pathStr)
		end
	end

	-- Update the UI to show diff indicators
	self:_UpdateDiffUI()

	-- Create diff bar above the main UI
	self:_CreateDiffBar(targetViewer, addedCount, removedCount, modifiedCount)
end

--[[
	Internal: Creates a diff information bar above the main UI.
]]
function TableEditor._CreateDiffBar(
	self: InternalTableEditor,
	targetViewer: InternalTableEditor,
	addedCount: number,
	removedCount: number,
	modifiedCount: number
)
	if not self._ui then
		return
	end

	-- Find the ScreenGui parent
	local screenGui = self._ui:FindFirstAncestorOfClass("ScreenGui")
	if not screenGui then
		return
	end

	-- Remove existing diff bar if any
	local existingBar = screenGui:FindFirstChild("DiffBar_" .. self._id)
	if existingBar then
		existingBar:Destroy()
	end

	local DIFF_BAR_HEIGHT = 24
	local GAP = 2

	-- Create the diff bar frame (parented to ScreenGui so it's not clipped)
	local diffBar = Instance.new("Frame")
	diffBar.Name = "DiffBar_" .. self._id
	diffBar.Size = UDim2.new(0, self._ui.AbsoluteSize.X, 0, DIFF_BAR_HEIGHT)
	diffBar.BackgroundColor3 = Color3.fromRGB(30, 35, 45)
	diffBar.BorderSizePixel = 0
	diffBar.ClipsDescendants = true
	diffBar.Parent = screenGui

	-- Position the bar above the main UI
	local function updateBarPosition()
		if not self._ui or not self._ui.Parent then
			return
		end
		local uiPos = self._ui.AbsolutePosition
		local uiSize = self._ui.AbsoluteSize
		diffBar.Position = UDim2.fromOffset(uiPos.X, uiPos.Y - DIFF_BAR_HEIGHT - GAP)
		diffBar.Size = UDim2.fromOffset(uiSize.X, DIFF_BAR_HEIGHT)
	end
	updateBarPosition()

	-- Update position when main UI moves/resizes
	local posConnection = self._ui:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateBarPosition)
	local sizeConnection = self._ui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateBarPosition)

	-- Store connections for cleanup
	diffBar:SetAttribute("PosConnectionId", tostring(posConnection))
	diffBar:SetAttribute("SizeConnectionId", tostring(sizeConnection))

	-- Clean up connections when bar is destroyed
	diffBar.Destroying:Connect(function()
		posConnection:Disconnect()
		sizeConnection:Disconnect()
	end)

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = diffBar

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = COLORS.DiffHeaderIndicator
	barStroke.Thickness = 1
	barStroke.Transparency = 0.5
	barStroke.Parent = diffBar

	-- Content layout
	local barPadding = Instance.new("UIPadding")
	barPadding.PaddingLeft = UDim.new(0, 8)
	barPadding.PaddingRight = UDim.new(0, 8)
	barPadding.Parent = diffBar

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	barLayout.Padding = UDim.new(0, 8)
	barLayout.Parent = diffBar

	-- DIFF icon/label
	local diffIcon = Instance.new("TextLabel")
	diffIcon.Name = "DiffIcon"
	diffIcon.Size = UDim2.fromOffset(32, 16)
	diffIcon.BackgroundColor3 = COLORS.DiffHeaderIndicator
	diffIcon.BackgroundTransparency = 0.3
	diffIcon.Text = "DIFF"
	diffIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
	diffIcon.TextSize = 10
	diffIcon.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
	diffIcon.LayoutOrder = 1
	diffIcon.Parent = diffBar

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 4)
	iconCorner.Parent = diffIcon

	-- Comparison info: "Source ↔ Target"
	local sourceTitle = self.Options.Title or "Source"
	local targetTitle = targetViewer.Options.Title or "Target"
	-- Truncate if needed
	if #sourceTitle > 12 then
		sourceTitle = sourceTitle:sub(1, 10) .. ".."
	end
	if #targetTitle > 12 then
		targetTitle = targetTitle:sub(1, 10) .. ".."
	end

	local comparisonLabel = Instance.new("TextLabel")
	comparisonLabel.Name = "ComparisonLabel"
	comparisonLabel.Size = UDim2.fromOffset(0, 16)
	comparisonLabel.AutomaticSize = Enum.AutomaticSize.X
	comparisonLabel.BackgroundTransparency = 1
	comparisonLabel.Text = `{sourceTitle} ↔ {targetTitle}`
	comparisonLabel.TextColor3 = Color3.fromRGB(180, 180, 185)
	comparisonLabel.TextSize = 11
	comparisonLabel.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular)
	comparisonLabel.LayoutOrder = 2
	comparisonLabel.Parent = diffBar

	-- Separator
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.Size = UDim2.fromOffset(1, 12)
	separator.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
	separator.BorderSizePixel = 0
	separator.LayoutOrder = 3
	separator.Parent = diffBar

	-- Stats section
	local totalChanges = addedCount + removedCount + modifiedCount

	if totalChanges == 0 then
		local noChangesLabel = Instance.new("TextLabel")
		noChangesLabel.Name = "NoChangesLabel"
		noChangesLabel.Size = UDim2.fromOffset(0, 16)
		noChangesLabel.AutomaticSize = Enum.AutomaticSize.X
		noChangesLabel.BackgroundTransparency = 1
		noChangesLabel.Text = "✓ No changes"
		noChangesLabel.TextColor3 = COLORS.DiffAdded
		noChangesLabel.TextSize = 11
		noChangesLabel.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold)
		noChangesLabel.LayoutOrder = 4
		noChangesLabel.Parent = diffBar
	else
		local statsContainer = Instance.new("Frame")
		statsContainer.Name = "StatsContainer"
		statsContainer.Size = UDim2.fromOffset(0, 16)
		statsContainer.AutomaticSize = Enum.AutomaticSize.X
		statsContainer.BackgroundTransparency = 1
		statsContainer.LayoutOrder = 4
		statsContainer.Parent = diffBar

		local statsLayout = Instance.new("UIListLayout")
		statsLayout.FillDirection = Enum.FillDirection.Horizontal
		statsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		statsLayout.Padding = UDim.new(0, 8)
		statsLayout.Parent = statsContainer

		if addedCount > 0 then
			local addedLabel = Instance.new("TextLabel")
			addedLabel.Name = "AddedLabel"
			addedLabel.Size = UDim2.fromOffset(0, 16)
			addedLabel.AutomaticSize = Enum.AutomaticSize.X
			addedLabel.BackgroundTransparency = 1
			addedLabel.Text = `+{addedCount}`
			addedLabel.TextColor3 = COLORS.DiffAdded
			addedLabel.TextSize = 11
			addedLabel.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold)
			addedLabel.LayoutOrder = 1
			addedLabel.Parent = statsContainer
		end

		if removedCount > 0 then
			local removedLabel = Instance.new("TextLabel")
			removedLabel.Name = "RemovedLabel"
			removedLabel.Size = UDim2.fromOffset(0, 16)
			removedLabel.AutomaticSize = Enum.AutomaticSize.X
			removedLabel.BackgroundTransparency = 1
			removedLabel.Text = `-{removedCount}`
			removedLabel.TextColor3 = COLORS.DiffRemoved
			removedLabel.TextSize = 11
			removedLabel.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold)
			removedLabel.LayoutOrder = 2
			removedLabel.Parent = statsContainer
		end

		if modifiedCount > 0 then
			local modifiedLabel = Instance.new("TextLabel")
			modifiedLabel.Name = "ModifiedLabel"
			modifiedLabel.Size = UDim2.fromOffset(0, 16)
			modifiedLabel.AutomaticSize = Enum.AutomaticSize.X
			modifiedLabel.BackgroundTransparency = 1
			modifiedLabel.Text = `~{modifiedCount}`
			modifiedLabel.TextColor3 = COLORS.DiffModified
			modifiedLabel.TextSize = 11
			modifiedLabel.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold)
			modifiedLabel.LayoutOrder = 3
			modifiedLabel.Parent = statsContainer
		end
	end

	-- Spacer to push close button to the right
	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.Size = UDim2.new(1, -200, 0, 1) -- Fill remaining space
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 5
	spacer.Parent = diffBar

	local spacerFlex = Instance.new("UIFlexItem")
	spacerFlex.FlexMode = Enum.UIFlexMode.Fill
	spacerFlex.Parent = spacer

	-- Close button (use simple X text that renders reliably)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(18, 18)
	closeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(180, 180, 185)
	closeBtn.TextSize = 11
	closeBtn.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
	closeBtn.LayoutOrder = 6
	closeBtn.Parent = diffBar

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 4)
	closeBtnCorner.Parent = closeBtn

	-- Hover effect for close button
	closeBtn.MouseEnter:Connect(function()
		closeBtn.BackgroundColor3 = COLORS.DiffRemoved
		closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		closeBtn.TextColor3 = Color3.fromRGB(180, 180, 185)
	end)

	closeBtn.MouseButton1Click:Connect(function()
		self:StopDiff()
	end)
end

--[[
	Internal: Exits diff mode and restores normal view.
]]
function TableEditor._ExitDiffMode(self: InternalTableEditor)
	self._diffState.Active = false
	self._diffState.TargetViewer = nil
	self._diffState.TargetViewerId = nil
	self._diffState.Stats = nil
	table.clear(self._diffState.DiffData)

	-- Disconnect target viewer destruction watcher
	if self._diffState.TargetDestroyConnection then
		self._diffState.TargetDestroyConnection:Disconnect()
		self._diffState.TargetDestroyConnection = nil
	end

	-- Disconnect escape handler if still connected
	if self._diffState.EscapeConnection then
		self._diffState.EscapeConnection:Disconnect()
		self._diffState.EscapeConnection = nil
	end

	-- Clean up ghost entries (items that only existed in target)
	local ghostPathsToRemove: { string } = {}
	for pathStr, association in self._associations do
		if association.IsGhost then
			table.insert(ghostPathsToRemove, pathStr)
		end
	end
	for _, pathStr in ghostPathsToRemove do
		local association = self._associations[pathStr]
		if association then
			-- Remove from parent's children index
			if association.Parent and self._childrenIndex[association.Parent] then
				local children = self._childrenIndex[association.Parent]
				for i = #children, 1, -1 do
					if children[i] == association then
						table.remove(children, i)
						break
					end
				end
			end
			-- Destroy the GUI
			if association.Gui then
				association.Gui:Destroy()
			end
			-- Remove from associations
			self._associations[pathStr] = nil
		end
	end

	-- Restore original data if we have it
	if self._diffState.OriginalData then
		self.Data = self._diffState.OriginalData
		self._diffState.OriginalData = nil
	end

	-- Refresh the UI to remove diff indicators
	self:_RefreshAllEntryUIs()
	self:_UpdateDiffUI()

	-- Remove diff bar (parented to ScreenGui)
	if self._ui then
		local screenGui = self._ui:FindFirstAncestorOfClass("ScreenGui")
		if screenGui then
			local diffBar = screenGui:FindFirstChild("DiffBar_" .. self._id)
			if diffBar then
				diffBar:Destroy()
			end
		end
	end
end

--[[
	Internal: Gets data from a table at a given path.
	@param data The root table
	@param pathStr The dot-separated path string
	@return The value at that path, or nil if not found
]]
function TableEditor._GetDataAtPath(self: InternalTableEditor, data: Table, pathStr: string): any
	if pathStr == "" then
		return data
	end

	local current: any = data
	for segment in pathStr:gmatch("[^%.]+") do
		if typeof(current) ~= "table" then
			return nil
		end
		-- Try as string key first, then as number
		local key: any = segment
		if current[key] == nil then
			local numKey = tonumber(segment)
			if numKey then
				key = numKey
			end
		end
		current = current[key]
		if current == nil then
			return nil
		end
	end
	return current
end

--[[
	Internal: Creates ghost entries for items that exist in target but not in source (removed items).
	These entries are displayed with removed styling to show what was deleted.
	@param parentAssociation The parent association to add ghost children to
	@param parentPathString The path string of the parent
]]
function TableEditor._CreateGhostEntriesForRemovedItems(
	self: InternalTableEditor,
	parentAssociation: Association,
	parentPathString: string
)
	if not self._diffState.Active or not self._diffState.TargetViewer then
		return
	end

	local targetViewer = self._diffState.TargetViewer :: InternalTableEditor
	local targetData = targetViewer.Data

	-- Get the corresponding table from the target viewer's data
	local targetTable = self:_GetDataAtPath(targetData, parentPathString)
	if typeof(targetTable) ~= "table" then
		return
	end

	-- Get the source table (our data at this path)
	local sourceTable = if parentPathString == "" then self.Data else self:_GetDataAtPath(self.Data, parentPathString)

	-- Find keys that exist in target but not in source (these are "removed" items)
	local ghostAssociations: { Association } = {}

	for key, value in pairs(targetTable) do
		local keyExists = sourceTable and typeof(sourceTable) == "table" and sourceTable[key] ~= nil
		if not keyExists then
			local pathString = if parentPathString == "" then tostring(key) else `{parentPathString}.{tostring(key)}`

			-- Check if we already have an association for this path (shouldn't happen, but safety check)
			if self._associations[pathString] then
				continue
			end

			-- Create a ghost association
			local ghostAssociation: Association = {
				Key = key,
				Parent = parentAssociation,
				Depth = parentAssociation.Depth + 1,
				Value = value, -- Value from target (what was removed)
				ChildrenLoaded = false,
				IsGhost = true, -- Mark as ghost entry
				_meta = {},
			}

			self._associations[pathString] = ghostAssociation

			if not self._childrenIndex[parentAssociation] then
				self._childrenIndex[parentAssociation] = {}
			end
			table.insert(self._childrenIndex[parentAssociation], ghostAssociation)
			table.insert(ghostAssociations, ghostAssociation)
		end
	end

	-- Create GUIs for ghost associations
	for _, ghostAssociation in ghostAssociations do
		if not ghostAssociation.Gui then
			ghostAssociation.Gui = self:_CreateEntry(ghostAssociation)
		end
	end
end

--[[
	Internal: Creates ghost entries for root-level items that exist in target but not in source.
	These are displayed with removed styling to show what was deleted.
]]
function TableEditor._CreateGhostEntriesForRemovedRootItems(self: InternalTableEditor)
	if not self._diffState.Active or not self._diffState.TargetViewer then
		return
	end

	local targetViewer = self._diffState.TargetViewer :: InternalTableEditor
	local targetData = targetViewer.Data
	local sourceData = self.Data

	if typeof(targetData) ~= "table" then
		return
	end

	-- Find keys that exist in target but not in source (these are "removed" items)
	local ghostAssociations: { Association } = {}

	for key, value in pairs(targetData) do
		local keyExists = sourceData and typeof(sourceData) == "table" and sourceData[key] ~= nil
		if not keyExists then
			local pathString = tostring(key)

			-- Check if we already have an association for this path
			if self._associations[pathString] then
				continue
			end

			-- Create a ghost association (root level has Parent = nil and Depth = 1)
			local ghostAssociation: Association = {
				Key = key,
				Parent = nil,
				Depth = 1,
				Value = value, -- Value from target (what was removed)
				ChildrenLoaded = false,
				IsGhost = true, -- Mark as ghost entry
				_meta = {},
			}

			self._associations[pathString] = ghostAssociation
			table.insert(ghostAssociations, ghostAssociation)
		end
	end

	-- Create GUIs for ghost associations
	for _, ghostAssociation in ghostAssociations do
		if not ghostAssociation.Gui then
			ghostAssociation.Gui = self:_CreateEntry(ghostAssociation)
		end
	end
end

--[[
	Internal: Gets the diff status for a given path string.
	Also checks parent paths for inherited status (e.g., child of added table is also added).
]]
function TableEditor._GetDiffStatusForPath(self: InternalTableEditor, pathStr: string): string?
	if not self._diffState.Active then
		return nil
	end

	-- Check if this is a ghost entry (items that exist only in target = removed)
	local association = self._associations[pathStr]
	if association and association.IsGhost then
		return "removed"
	end

	-- Direct lookup first
	local diffEntry = self._diffState.DiffData[pathStr]
	if diffEntry then
		return diffEntry.Status
	end

	-- Check if any parent path has added/removed status (children inherit)
	local currentPath = pathStr
	while true do
		local parentPath = currentPath:match("(.+)%.[^%.]+$")
		if not parentPath then
			break
		end

		local parentEntry = self._diffState.DiffData[parentPath]
		if parentEntry then
			-- If parent is added or removed, children inherit that status
			if parentEntry.Status == "added" or parentEntry.Status == "removed" then
				return parentEntry.Status
			end
		end

		currentPath = parentPath
	end

	return nil
end

--[[
	Internal: Updates all entry UIs to show diff indicators.
]]
function TableEditor._UpdateDiffUI(self: InternalTableEditor)
	for pathStr, association in self._associations do
		if association.Gui then
			local infoBox = association.Gui:FindFirstChild("InfoBox") :: Frame?
			if infoBox then
				-- Find or create diff gutter indicator
				local diffGutter = infoBox:FindFirstChild("DiffGutter") :: Frame?

				if self._diffState.Active then
					local diffStatus = self:_GetDiffStatusForPath(pathStr)

					if diffStatus and diffStatus ~= "unchanged" then
						-- Create gutter if doesn't exist
						if not diffGutter then
							local newGutter = Instance.new("Frame")
							newGutter.Name = "DiffGutter"
							newGutter.Size = UDim2.new(0, 4, 1, 0)
							newGutter.Position = UDim2.fromOffset(0, 0)
							newGutter.BorderSizePixel = 0
							newGutter.ZIndex = 5
							newGutter.Parent = infoBox
							diffGutter = newGutter
						end

						-- Set color based on status
						local gutterColor = COLORS.DiffModified
						local bgColor = COLORS.DiffModifiedBackground
						if diffStatus == "added" then
							gutterColor = COLORS.DiffAdded
							bgColor = COLORS.DiffAddedBackground
						elseif diffStatus == "removed" then
							gutterColor = COLORS.DiffRemoved
							bgColor = COLORS.DiffRemovedBackground
						end

						if diffGutter then
							diffGutter.BackgroundColor3 = gutterColor
							diffGutter.BackgroundTransparency = TRANSPARENCY.DiffGutter
							diffGutter.Visible = true
						end

						-- Apply subtle background tint to the entire row
						local changeFlash = infoBox:FindFirstChild("ChangeFlash") :: Frame?
						if changeFlash then
							changeFlash.BackgroundColor3 = bgColor
							changeFlash.BackgroundTransparency = TRANSPARENCY.DiffBackground
						end
					else
						-- Hide gutter for unchanged
						if diffGutter then
							diffGutter.Visible = false
						end
						-- Reset background
						local changeFlash = infoBox:FindFirstChild("ChangeFlash") :: Frame?
						if changeFlash then
							changeFlash.BackgroundTransparency = 1
						end
					end
				else
					-- Not in diff mode - hide gutter and reset background
					if diffGutter then
						diffGutter.Visible = false
					end
					local changeFlash = infoBox:FindFirstChild("ChangeFlash") :: Frame?
					if changeFlash then
						changeFlash.BackgroundTransparency = 1
					end
				end
			end
		end
	end
end

--[[
	Internal: Creates selection overlays on all other visible viewers.
]]
function TableEditor._CreateDiffSelectionOverlays(self: InternalTableEditor)
	-- Clear any existing overlays
	self:_ClearDiffSelectionOverlays()

	-- Create overlays for all other viewers
	for viewerId, viewer in idToViewer do
		if viewerId ~= self._id and viewer._ui and viewer._ui.Visible then
			local viewerFrame = viewer._ui :: Frame
			local isViewerInDiffMode = viewer._diffState and viewer._diffState.Active
			local viewerTitle = viewer.Options and viewer.Options.Title or "Viewer"

			-- Create overlay frame
			local overlay = Instance.new("TextButton")
			overlay.Name = "DiffSelectionOverlay"
			overlay.Size = UDim2.new(1, 0, 1, 0)
			overlay.BackgroundColor3 = if isViewerInDiffMode then COLORS.DiffModified else COLORS.DiffSelectionHighlight
			overlay.BackgroundTransparency = TRANSPARENCY.DiffSelectionOverlay
			overlay.BorderSizePixel = 0
			overlay.ZIndex = 100
			overlay.Text = ""
			overlay.AutoButtonColor = false

			-- Add a border highlight
			local stroke = Instance.new("UIStroke")
			stroke.Color = if isViewerInDiffMode then COLORS.DiffModified else COLORS.DiffSelectionHighlight
			stroke.Thickness = 3
			stroke.Transparency = 0.3
			stroke.Parent = overlay

			-- Add label showing viewer name
			local label = Instance.new("TextLabel")
			label.Name = "SelectLabel"
			label.Size = UDim2.new(1, -16, 0, 36)
			label.Position = UDim2.new(0, 8, 0.5, -18)
			label.BackgroundColor3 = if isViewerInDiffMode then COLORS.DiffModified else COLORS.DiffSelectionHighlight
			label.BackgroundTransparency = 0.1
			label.BorderSizePixel = 0
			label.Text = if isViewerInDiffMode
				then `⚠ {viewerTitle}\n(Already comparing)`
				else `Click to compare with:\n"{viewerTitle}"`
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextSize = 12
			label.TextWrapped = true
			label.FontFace = Font.new(
				"rbxasset://fonts/families/SourceSansPro.json",
				Enum.FontWeight.SemiBold,
				Enum.FontStyle.Normal
			)
			label.Parent = overlay

			local labelCorner = Instance.new("UICorner")
			labelCorner.CornerRadius = UDim.new(0, 4)
			labelCorner.Parent = label

			-- Hover effects
			overlay.MouseEnter:Connect(function()
				overlay.BackgroundTransparency = TRANSPARENCY.DiffSelectionOverlay - 0.2
				stroke.Transparency = 0
				stroke.Thickness = 4
			end)

			overlay.MouseLeave:Connect(function()
				overlay.BackgroundTransparency = TRANSPARENCY.DiffSelectionOverlay
				stroke.Transparency = 0.3
				stroke.Thickness = 3
			end)

			-- Click to select
			overlay.Activated:Connect(function()
				self:CancelDiffSelection()
				self:StartDiff(viewer)
			end)

			overlay.Parent = viewerFrame
			self._diffState.SelectionOverlays[viewerId] = overlay
		end
	end

	-- Also update the source viewer to show it's in selection mode
	if self._ui then
		local header = self._ui:FindFirstChild("Header") :: Frame?
		if header then
			local headerLabel = header:FindFirstChild("HeaderLabel") :: TextLabel?
			if headerLabel then
				headerLabel.Text = `{self.Options.Title} (Select viewer...)`
				headerLabel.TextColor3 = COLORS.DiffSelectionHighlight
			end

			-- Add cancel button
			local cancelBtn = Instance.new("TextButton")
			cancelBtn.Name = "DiffCancelButton"
			cancelBtn.Size = UDim2.new(0, 70, 0, 18)
			cancelBtn.Position = UDim2.new(1, -8, 0.5, 0)
			cancelBtn.AnchorPoint = Vector2.new(1, 0.5)
			cancelBtn.BackgroundColor3 = COLORS.DiffRemoved
			cancelBtn.BackgroundTransparency = 0.3
			cancelBtn.BorderSizePixel = 0
			cancelBtn.Text = "Cancel (Esc)"
			cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			cancelBtn.TextSize = 10
			cancelBtn.FontFace = Font.new(
				"rbxasset://fonts/families/SourceSansPro.json",
				Enum.FontWeight.SemiBold,
				Enum.FontStyle.Normal
			)
			cancelBtn.ZIndex = 5
			cancelBtn.Parent = header

			local cancelCorner = Instance.new("UICorner")
			cancelCorner.CornerRadius = UDim.new(0, 4)
			cancelCorner.Parent = cancelBtn

			-- Hover effects
			cancelBtn.MouseEnter:Connect(function()
				cancelBtn.BackgroundTransparency = 0.1
			end)
			cancelBtn.MouseLeave:Connect(function()
				cancelBtn.BackgroundTransparency = 0.3
			end)

			cancelBtn.Activated:Connect(function()
				self:CancelDiffSelection()
			end)

			-- Store reference for cleanup
			self._diffState.SelectionOverlays["_cancelButton"] = cancelBtn :: any
		end

		-- Add a border to source viewer to show it's the one comparing
		local existingStroke = self._ui:FindFirstChild("DiffSelectionStroke")
		if not existingStroke then
			local sourceStroke = Instance.new("UIStroke")
			sourceStroke.Name = "DiffSelectionStroke"
			sourceStroke.Color = COLORS.DiffSelectionHighlight
			sourceStroke.Thickness = 3
			sourceStroke.Transparency = 0.2
			sourceStroke.Parent = self._ui
			self._diffState.SelectionOverlays["_sourceStroke"] = sourceStroke :: any
		end
	end
end

--[[
	Internal: Clears all diff selection overlays.
]]
function TableEditor._ClearDiffSelectionOverlays(self: InternalTableEditor)
	-- Destroy all overlays (including cancel button and source stroke stored with special keys)
	for key, overlay in self._diffState.SelectionOverlays do
		if overlay and (overlay :: any).Parent then
			(overlay :: any):Destroy()
		end
	end
	table.clear(self._diffState.SelectionOverlays)

	-- Also remove source stroke from UI if present
	if self._ui then
		local sourceStroke = self._ui:FindFirstChild("DiffSelectionStroke")
		if sourceStroke then
			sourceStroke:Destroy()
		end
	end

	-- Restore header text (only if not entering diff mode)
	if self._ui and not self._diffState.Active then
		local header = self._ui:FindFirstChild("Header") :: Frame?
		if header then
			local headerLabel = header:FindFirstChild("HeaderLabel") :: TextLabel?
			if headerLabel then
				headerLabel.Text = self.Options.Title
				headerLabel.TextColor3 = COLORS.HeaderText
			end

			-- Also remove cancel button if somehow still there
			local cancelBtn = header:FindFirstChild("DiffCancelButton")
			if cancelBtn then
				cancelBtn:Destroy()
			end
		end
	end
end

--[[
	Creates a frozen snapshot of the current data.
	The snapshot uses a deep copy of the data, so it remains frozen
	and independent of the original data.
]]
function TableEditor.Snapshot(self: InternalTableEditor, title: string?): TableEditor
	local snapshotTitle = title or `{self.Options.Title} (Snapshot)`
	-- Deep clone the data so the snapshot starts with current state
	local snapshotData = TableHelper.DeepClone(self.Data)
	local snapshot = TableEditor.new(snapshotData, {
		Title = snapshotTitle,
		ViewerPosition = UDim2.new(
			self.Options.ViewerPosition.X.Scale + 0.02,
			self.Options.ViewerPosition.X.Offset + 20,
			self.Options.ViewerPosition.Y.Scale + 0.02,
			self.Options.ViewerPosition.Y.Offset + 20
		),
	});
	-- Track parent-snapshot relationship for auto-sync
	(snapshot :: any)._parentViewer = self
	table.insert(self._snapshots, snapshot)

	-- Copy frozen values to snapshot (deep clone table values)
	for pathStr, frozenValue in pairs(self._frozenValues) do
		if typeof(frozenValue) == "table" then
			(snapshot :: any)._frozenValues[pathStr] = TableHelper.DeepClone(frozenValue)
		else
			(snapshot :: any)._frozenValues[pathStr] = frozenValue
		end
	end

	-- Note: _RefreshFreezeButtonStates is not needed here because the frozen values
	-- are already applied during _CreateEntry when the UI is built

	-- Freeze immediately - snapshots start frozen by default
	snapshot:Freeze()
	return snapshot
end

--[[
	Creates a focused viewer for a subtable at the given path.
]]
function TableEditor.FocusTable(self: InternalTableEditor, path: { any }): TableEditor?
	local actualPath: { any } = if path then path else {}

	local current: any = self.Data
	for _, key in pairs(actualPath) do
		if typeof(current) ~= "table" then
			return nil
		end
		current = current[key]
	end

	if typeof(current) ~= "table" then
		return nil
	end

	local pathStr = PathToString(actualPath)

	if self._childViewers[pathStr] then
		return self._childViewers[pathStr]
	end

	-- Deep clone the sub-table so child viewer has frozen snapshot of current state
	local clonedData = TableHelper.DeepClone(current)

	local focused = TableEditor.new(clonedData, {
		Title = `{self.Options.Title}.{pathStr}`,
		ViewerPosition = UDim2.new(
			self.Options.ViewerPosition.X.Scale + 0.02,
			self.Options.ViewerPosition.X.Offset + 20,
			self.Options.ViewerPosition.Y.Scale + 0.02,
			self.Options.ViewerPosition.Y.Offset + 20
		),
		-- Inherit verbose settings from parent
		VerboseKeys = self.Options.VerboseKeys,
		VerboseValues = self.Options.VerboseValues,
		VerboseKeyTypes = TableHelper.DeepClone(self.Options.VerboseKeyTypes),
		VerboseValueTypes = TableHelper.DeepClone(self.Options.VerboseValueTypes),
	})
	focused._rootViewer = self
	focused._rootPath = actualPath
	self._childViewers[pathStr] = focused

	-- Copy frozen values that are within this subtable (translate paths to be relative)
	local pathPrefix = pathStr .. "."
	for frozenPathStr, frozenValue in pairs(self._frozenValues) do
		-- Check if this frozen path is within the focused subtable
		if frozenPathStr == pathStr or string.sub(frozenPathStr, 1, #pathPrefix) == pathPrefix then
			-- Translate path: remove the prefix to make it relative to the focused table
			local relativePath = if frozenPathStr == pathStr then "" else string.sub(frozenPathStr, #pathPrefix + 1)
			if relativePath ~= "" then
				if typeof(frozenValue) == "table" then
					(focused :: any)._frozenValues[relativePath] = TableHelper.DeepClone(frozenValue)
				else
					(focused :: any)._frozenValues[relativePath] = frozenValue
				end
			end
		end
	end

	-- Note: _RefreshFreezeButtonStates is not needed here because the frozen values
	-- are already applied during _CreateEntry when the UI is built

	-- Freeze child viewers by default
	focused:Freeze()
	return focused
end

-- Export Methods

--[[
	Exports the data to JSON format.
]]
function TableEditor.ExportToJson(self: InternalTableEditor): string
	return TableToJson(self.Data)
end

--[[
	Exports the data to Lua format.
]]
function TableEditor.ExportToLua(self: InternalTableEditor): string
	return "return " .. TableToLua(self.Data)
end

-- Data Manipulation Methods

--[[
	Adds a new row to the data at the specified path.
]]
function TableEditor.AddRow(self: InternalTableEditor, path: { any }, key: any, value: any): boolean
	if not self.Options then
		return false
	end
	if not self.Options.Editable then
		warn("TableEditor: Editing is disabled. Set Options.Editable = true to enable.")
		return false
	end

	if key == nil then
		warn("TableEditor: Cannot add row with nil key")
		return false
	end

	local actualPath: { any } = if path then path else {}
	local target = self.Data
	for _, pathKey in pairs(actualPath) do
		if typeof(target) ~= "table" then
			return false
		end
		target = target[pathKey]
	end

	if typeof(target) ~= "table" then
		return false
	end

	if target[key] ~= nil then
		warn("TableEditor: Key already exists:", key)
		return false
	end

	target[key] = value
	local fullPath = table.clone(actualPath)
	table.insert(fullPath, key)
	local pathString = PathToString(fullPath)

	local editInfo: DataEditedInfo = {
		Path = fullPath,
		PathString = pathString,
		OldValue = nil,
		NewValue = value,
		EditType = "add",
		Source = "edit",
	}
	self.OnDataEdited:Fire(editInfo)
	self:_FireValueWatchers(editInfo)

	local parentAssoc: Association? = nil
	if actualPath[1] then
		local parentPathString = PathToString(actualPath)
		parentAssoc = self._associations[parentPathString]
		if parentAssoc and not parentAssoc.ChildrenLoaded then
			parentAssoc.ChildrenLoaded = true
			self:_LoadChildAssociations(parentAssoc, true)
		end
	end

	-- Create the new association
	local newAssoc: Association = {
		Key = key,
		Parent = parentAssoc,
		Depth = if parentAssoc then parentAssoc.Depth + 1 else 0,
		Value = value,
		ChildrenLoaded = false,
		_meta = {},
	}

	if typeof(value) == "table" then
		local refPath = self:_GetTableRefPath(value, self._tableRefs)
		if refPath then
			if refPath == pathString then
				newAssoc.IsRecursive = true
			else
				newAssoc.IsDuplicateRef = true
				newAssoc.DuplicateOfKey = refPath
			end
		else
			self._tableRefs[value] = pathString
		end
	end

	newAssoc.Gui = self:_CreateEntry(newAssoc)
	newAssoc._meta.LastValueHash = HashValue(value)
	self._associations[pathString] = newAssoc

	if newAssoc.Gui then
		self._guiToAssociation[newAssoc.Gui] = newAssoc
	end

	if parentAssoc then
		if not self._childrenIndex[parentAssoc] then
			self._childrenIndex[parentAssoc] = {}
		end
		table.insert(self._childrenIndex[parentAssoc], newAssoc)
	end

	self:_UpdateOrdering()
	self:_UpdateFiltersAndExclusions()
	self:_UpdateLink()

	-- Notify other viewers sharing the same data table
	self:_NotifySameDataViewersStructuralChange()

	return true
end

--[[
	Removes a row from the data at the specified path.
]]
function TableEditor.RemoveRow(self: InternalTableEditor, path: { any }, key: any): boolean
	if not self.Options then
		return false
	end
	if not self.Options.Editable then
		warn("TableEditor: Editing is disabled. Set Options.Editable = true to enable.")
		return false
	end

	local target = self.Data
	for _, pathKey in pairs(path) do
		if typeof(target) ~= "table" then
			return false
		end
		target = target[pathKey]
	end

	if typeof(target) ~= "table" then
		return false
	end

	local oldValue = target[key]
	if oldValue == nil then
		warn("TableEditor: Key does not exist:", key)
		return false
	end

	local fullPath = table.clone(path)
	table.insert(fullPath, key)
	local pathString = PathToString(fullPath)

	local isArrayRemoval = typeof(key) == "number"
	local assoc = self._associations[pathString]

	if isArrayRemoval then
		local parentPathString = PathToString(path)
		local parentPathPrefix = if parentPathString == "" then "" else parentPathString .. "."
		local toRemove: { string } = {}

		for assocPath, childAssoc in pairs(self._associations) do
			local isDirectChild = false
			if parentPathString == "" then
				isDirectChild = not assocPath:find("%.")
				if not isDirectChild then
					local firstKey = assocPath:match("^([^%.]+)")
					if firstKey and tonumber(firstKey) then
						isDirectChild = true
					end
				end
			else
				if assocPath:sub(1, #parentPathPrefix) == parentPathPrefix then
					isDirectChild = true
				end
			end

			if isDirectChild then
				table.insert(toRemove, assocPath)
				if typeof(childAssoc.Value) == "table" then
					self._tableRefs[childAssoc.Value] = nil
				end
				self._childrenIndex[childAssoc] = nil
			end
		end

		-- Only flash if the entry is not frozen
		local isFrozen = self._frozenValues[pathString] ~= nil
		if assoc and assoc.Gui and self.Options.FlashOnRemoval and not isFrozen then
			self:_FlashEntry(assoc, self.Options.FlashRemovalColor)
			local parent = assoc.Parent
			while parent do
				if parent.Gui then
					self:_FlashEntry(parent, self.Options.FlashRemovalColor)
				end
				parent = parent.Parent
			end
		end

		for _, removePath in pairs(toRemove) do
			local removeAssoc = self._associations[removePath]
			if removeAssoc and removeAssoc.Gui then
				self:_ReturnEntryToPool(removeAssoc.Gui)
			end
			self._associations[removePath] = nil
		end

		local parentAssoc = assoc and assoc.Parent
		if parentAssoc then
			self._childrenIndex[parentAssoc] = nil
		end
	else
		if assoc then
			local pathPrefix = pathString .. "."
			local toRemove: { string } = { pathString }

			for assocPath, childAssoc in pairs(self._associations) do
				if assocPath:sub(1, #pathPrefix) == pathPrefix then
					table.insert(toRemove, assocPath)
					if typeof(childAssoc.Value) == "table" then
						self._tableRefs[childAssoc.Value] = nil
					end
					if childAssoc.Gui then
						self:_ReturnEntryToPool(childAssoc.Gui)
					end
					self._childrenIndex[childAssoc] = nil
				end
			end

			if assoc.Gui then
				-- Only flash if the entry is not frozen
				local isFrozen = self._frozenValues[pathString] ~= nil
				if self.Options.FlashOnRemoval and not isFrozen then
					self:_FlashEntry(assoc, self.Options.FlashRemovalColor)
					local parent = assoc.Parent
					while parent do
						if parent.Gui then
							self:_FlashEntry(parent, self.Options.FlashRemovalColor)
						end
						parent = parent.Parent
					end
					task.delay(self.Options.FlashDuration, function()
						if assoc.Gui then
							self:_ReturnEntryToPool(assoc.Gui)
						end
					end)
				else
					self:_ReturnEntryToPool(assoc.Gui)
				end
			end

			if typeof(assoc.Value) == "table" then
				self._tableRefs[assoc.Value] = nil
			end

			if assoc.Parent then
				local parentChildren = self._childrenIndex[assoc.Parent]
				if parentChildren then
					for i, child in pairs(parentChildren) do
						if child == assoc then
							table.remove(parentChildren, i)
							break
						end
					end
				end
			end
			self._childrenIndex[assoc] = nil

			for _, removePath in pairs(toRemove) do
				self._associations[removePath] = nil
			end
		end
	end

	if isArrayRemoval then
		table.remove(target, key)
	else
		target[key] = nil
	end

	local editInfo: DataEditedInfo = {
		Path = fullPath,
		PathString = pathString,
		OldValue = oldValue,
		NewValue = nil,
		EditType = "remove",
		Source = "edit",
	}
	self.OnDataEdited:Fire(editInfo)
	self:_FireValueWatchers(editInfo)

	if isArrayRemoval then
		self:_UpdateAssociations()
		self:_UpdateFiltersAndExclusions()
	else
		self:_UpdateOrdering()
	end
	self:_UpdateLink()

	-- Notify other viewers sharing the same data table
	self:_NotifySameDataViewersStructuralChange()

	return true
end

--[[
	Sets a value at the specified path.
]]
function TableEditor.SetValue(self: InternalTableEditor, path: { any }, value: any): boolean
	if not self.Options then
		return false
	end
	if not self.Options.Editable then
		warn("TableEditor: Editing is disabled. Set Options.Editable = true to enable.")
		return false
	end

	if not path or not path[1] then
		return false
	end

	local target = self.Data
	for i = 1, #path - 1 do
		if typeof(target) ~= "table" then
			return false
		end
		target = target[path[i]]
	end

	if typeof(target) ~= "table" then
		return false
	end

	local key = path[#path]
	local oldValue = target[key]
	target[key] = value

	local pathString = PathToString(path)
	local editInfo: DataEditedInfo = {
		Path = path,
		PathString = pathString,
		OldValue = oldValue,
		NewValue = value,
		EditType = "set",
		Source = "edit",
	}
	self.OnDataEdited:Fire(editInfo)
	self:_FireValueWatchers(editInfo)
	self:_UpdateSingleAssociation(pathString, oldValue, value)
	self:_UpdateLink()

	-- Notify other viewers sharing the same data table to update their UI
	self:_NotifySameDataViewers(pathString, oldValue, value)

	return true
end

--[[
	Internal: Notifies other viewers that share the same data table reference
	to update their UI for the changed path.
]]
function TableEditor._NotifySameDataViewers(self: InternalTableEditor, pathString: string, oldValue: any, newValue: any)
	for viewerId, viewer in idToViewer do
		if viewerId ~= self._id and viewer.Data == self.Data then
			-- Same data table reference - update their UI for this path
			local assoc = viewer._associations[pathString]
			if assoc then
				(viewer :: any):_UpdateSingleAssociation(pathString, oldValue, newValue)
			end
		end
	end
end

--[[
	Internal: Notifies other viewers that share the same data table reference
	to fully refresh their associations (used for structural changes like add/remove).
]]
function TableEditor._NotifySameDataViewersStructuralChange(self: InternalTableEditor)
	for viewerId, viewer in idToViewer do
		if viewerId ~= self._id and viewer.Data == self.Data then
			-- Same data table reference - fully refresh their associations
			(viewer :: any):_UpdateAssociations()
		end
	end
end

--[[
	Gets the value at the specified path.
]]
function TableEditor.GetValue(self: InternalTableEditor, path: { any }): any
	if path == nil then
		return self.Data
	end
	local target = self.Data
	for _, pathKey in pairs(path) do
		if typeof(target) ~= "table" then
			return nil
		end
		target = target[pathKey]
	end
	return target
end

--[[
	Subscribes to value changes at a path.
]]
function TableEditor.OnValueChanged(
	self: InternalTableEditor,
	path: { any }?,
	callback: (newValue: any, oldValue: any, info: DataEditedInfo) -> (),
	options: OnValueChangedOptions?
): SignalConnection
	local actualPath: { any } = if path then path else {}
	local pathString = PathToString(actualPath)

	local sourceFilter: "edit" | "api" | "any" = if options and options.Source then options.Source else "any"
	if not callback then
		return {
			Connected = false,
			Disconnect = function() end,
		}
	end

	if not self._valueWatchers[pathString] then
		self._valueWatchers[pathString] = {}
	end

	local watcherEntry = { callback = callback, source = sourceFilter }
	table.insert(self._valueWatchers[pathString], watcherEntry)

	local connection: SignalConnection = {
		Connected = true,
		Disconnect = function(conn: SignalConnection)
			if conn.Connected then
				conn.Connected = false
				local watchers = self._valueWatchers[pathString]
				if watchers then
					for i, entry in pairs(watchers) do
						if entry.callback == callback then
							table.remove(watchers, i)
							break
						end
					end
					if not watchers[1] then
						self._valueWatchers[pathString] = nil
					end
				end
			end
		end,
	}
	return connection
end

--[[
	Fires value watchers for an edit.
]]
function TableEditor._FireValueWatchers(self: InternalTableEditor, editInfo: DataEditedInfo)
	local pathParts = editInfo.Path
	local source = editInfo.Source
	local pathsToCheck: { string } = { "" } -- Always check root
	local currentPath = ""

	for _, key in pairs(pathParts) do
		if currentPath == "" then
			currentPath = tostring(key)
		else
			currentPath = currentPath .. "." .. tostring(key)
		end
		table.insert(pathsToCheck, currentPath)
	end

	for _, watchPath in pairs(pathsToCheck) do
		local watchers = self._valueWatchers[watchPath]
		if watchers then
			for _, entry in pairs(watchers) do
				if entry.callback and (entry.source == "any" or entry.source == source) then
					local newValue: any
					local oldValue: any
					if watchPath == editInfo.PathString then
						newValue = editInfo.NewValue
						oldValue = editInfo.OldValue
					else
						newValue = editInfo.NewValue
						oldValue = editInfo.OldValue
					end
					task.spawn(entry.callback, newValue, oldValue, editInfo)
				end
			end
		end
	end
end

--[[
	Scrolls to and highlights a path in the viewer.
]]
function TableEditor.ScrollToPath(self: InternalTableEditor, path: { any })
	if not self._ui then
		return
	end

	local currentPath = ""
	for _, key in pairs(path) do
		currentPath = if currentPath == "" then tostring(key) else currentPath .. "." .. tostring(key)
		local assoc = self._associations[currentPath]
		if assoc and typeof(assoc.Value) == "table" then
			if assoc.Gui then
				local children = assoc.Gui:FindFirstChild("Children") :: Frame?
				if children then
					children.Visible = true
					local infoBox = assoc.Gui:FindFirstChild("InfoBox")
					if infoBox then
						local expansionButton = infoBox:FindFirstChild("ExpansionButton")
						if expansionButton then
							local icon = expansionButton:FindFirstChild("Icon") :: ImageLabel?
							if icon then
								icon.Rotation = 90
							end
						end
					end
				end
			end

			if not assoc.ChildrenLoaded then
				assoc.ChildrenLoaded = true
				self:_LoadChildAssociations(assoc)
			end
		end
	end

	local targetPath = PathToString(path)
	local targetAssoc = self._associations[targetPath]
	if targetAssoc and targetAssoc.Gui then
		local scrollFrame = self._ui.Viewer.Table
		local targetPos = targetAssoc.Gui.AbsolutePosition.Y - scrollFrame.AbsolutePosition.Y
		scrollFrame.CanvasPosition = Vector2.new(0, math.max(0, targetPos - 50))
		self:_FlashEntry(targetAssoc, self.Options.FlashNavigationColor)
	end
end

-- Visibility Methods

--[[
	Shows the viewer.
]]
function TableEditor.Show(self: InternalTableEditor)
	if not self.Options then
		return
	end
	self._visible = true
	if self._ui then
		self._ui.Visible = true
		if self.Options.RememberPositionStates then
			self._ui.Position = self.Options.OpenPosition
		end
	end
end

--[[
	Hides the viewer.
]]
function TableEditor.Hide(self: InternalTableEditor)
	if not self.Options then
		return
	end
	self._visible = false
	if self._ui then
		if self.Options.RememberPositionStates then
			self.Options.OpenPosition = self._ui.Position
		end
		self._ui.Visible = false
		if self.Options.RememberPositionStates then
			self._ui.Position = self.Options.ClosedPosition
		end
	end
end

--[[
	Toggles the viewer visibility.
]]
function TableEditor.Toggle(self: InternalTableEditor)
	if self._visible then
		self:Hide()
	else
		self:Show()
	end
end

--[[
	Returns whether the viewer is visible.
]]
function TableEditor.IsVisible(self: InternalTableEditor): boolean
	return self._visible
end

--[[
	Collapses the viewer to just the title bar.
]]
function TableEditor.Collapse(self: InternalTableEditor)
	if not self._ui or not self.Options then
		return
	end

	if self._collapsed then
		self._collapsed = false
		if self._lastSize then
			self._ui.Size = self._lastSize
		end
		self._ui.Footer.Visible = true
		self._ui.Viewer.Visible = true

		-- Restore size constraint
		local sizeConstraint = self._ui:FindFirstChildOfClass("UISizeConstraint")
		if sizeConstraint then
			sizeConstraint.MinSize = self.Options.MinSize
		end

		-- Show header corner fix
		local cornerFix = self._ui.Header:FindFirstChild("CornerFix") :: Frame?
		if cornerFix then
			cornerFix.Visible = true
		end

		local collapseBtn = FindHeaderChild(self._ui.Header, "CollapseButton") :: ImageButton?
		if collapseBtn then
			SetMaterialIcon(collapseBtn, "ExpandLess")
		end
	else
		self._collapsed = true
		self._lastSize = self._ui.Size
		self._ui.Footer.Visible = false
		self._ui.Viewer.Visible = false

		-- Hide options menu if visible
		local optionsMenu = self._ui:FindFirstChild("OptionsMenu") :: Frame?
		if optionsMenu then
			optionsMenu.Visible = false
		end

		-- Hide header corner fix (causes extra space at bottom when collapsed)
		local cornerFix = self._ui.Header:FindFirstChild("CornerFix") :: Frame?
		if cornerFix then
			cornerFix.Visible = false
		end

		-- Calculate minimal width needed for header content
		-- Sum up the individual section widths (left + title text + right + padding)
		local content = self._ui.Header:FindFirstChild("Content") :: Frame?
		local minWidth = 100 -- Fallback minimum
		if content then
			local leftSection = content:FindFirstChild("LeftSection") :: Frame?
			local titleSection = content:FindFirstChild("TitleSection") :: Frame?
			local rightSection = content:FindFirstChild("RightSection") :: Frame?

			local leftWidth = if leftSection then leftSection.AbsoluteSize.X else 0
			local rightWidth = if rightSection then rightSection.AbsoluteSize.X else 0

			-- Get actual title text width
			local titleWidth = 0
			if titleSection then
				local headerLabel = titleSection:FindFirstChild("HeaderLabel") :: TextLabel?
				if headerLabel then
					titleWidth = headerLabel.TextBounds.X + 4 -- text width + small padding
				end
			end

			-- Total: left + title + right + gaps between sections (4px each) + outer padding
			minWidth = leftWidth + titleWidth + rightWidth + 8 + 12
		end

		-- Temporarily remove size constraint minimum to allow shrinking
		local sizeConstraint = self._ui:FindFirstChildOfClass("UISizeConstraint")
		if sizeConstraint then
			sizeConstraint.MinSize = Vector2.new(0, 0)
		end

		-- Use content-based width, header height (28px)
		self._ui.Size = UDim2.fromOffset(minWidth, 28)

		local collapseBtn = FindHeaderChild(self._ui.Header, "CollapseButton") :: ImageButton?
		if collapseBtn then
			SetMaterialIcon(collapseBtn, "ExpandMore")
		end
	end
end

--[[
	Minimizes the viewer to a small icon.
]]
function TableEditor.Minimize(self: InternalTableEditor)
	if not self._ui or not self.Options then
		return
	end

	local header = self._ui.Header
	local minimizeBtn = FindHeaderChild(header, "MinimizeButton") :: ImageButton?

	if self._minimized then
		-- RESTORE from minimized state
		self._minimized = false
		if self._lastSize then
			self._ui.Size = self._lastSize
		end
		self._ui.Footer.Visible = true
		self._ui.Viewer.Visible = true

		-- Restore size constraint
		local sizeConstraint = self._ui:FindFirstChildOfClass("UISizeConstraint")
		if sizeConstraint then
			sizeConstraint.MinSize = self.Options.MinSize
		end

		-- Restore header size
		header.Size = UDim2.new(1, 0, 0, 28)

		-- Show header corner fix
		local cornerFix = header:FindFirstChild("CornerFix") :: Frame?
		if cornerFix then
			cornerFix.Visible = true
		end

		-- Show header content
		local content = header:FindFirstChild("Content") :: Frame?
		if content then
			content.Visible = true

			-- Restore minimize button to RightSection
			if minimizeBtn then
				local rightSection = content:FindFirstChild("RightSection") :: Frame?
				if rightSection then
					minimizeBtn.Parent = rightSection
					minimizeBtn.Position = UDim2.new()
					minimizeBtn.AnchorPoint = Vector2.zero
				end
			end
		end

		local headerLabel = FindHeaderChild(header, "HeaderLabel") :: TextLabel?
		if headerLabel then
			headerLabel.Visible = true
		end
		local badgeLabel = FindHeaderChild(header, "BadgeLabel") :: TextLabel?
		if badgeLabel then
			badgeLabel.Visible = self._linkGroupId ~= nil
		end
	else
		-- MINIMIZE to square
		self._minimized = true
		self._lastSize = self._ui.Size

		-- Hide options menu if visible
		local optionsMenu = self._ui:FindFirstChild("OptionsMenu") :: Frame?
		if optionsMenu then
			optionsMenu.Visible = false
		end

		-- Hide everything except minimizeBtn
		self._ui.Footer.Visible = false
		self._ui.Viewer.Visible = false

		-- Hide header corner fix
		local cornerFix = header:FindFirstChild("CornerFix") :: Frame?
		if cornerFix then
			cornerFix.Visible = false
		end

		-- Hide header content (contains all the nested sections)
		local content = header:FindFirstChild("Content") :: Frame?
		if content then
			content.Visible = false
		end

		-- Calculate minimized size: button (24x24) + minimal padding
		local buttonSize = 24
		local padding = 2 -- Minimal padding around button
		local minimizedSize = buttonSize + padding * 2 -- 28x28 total

		-- Temporarily remove size constraint minimum to allow shrinking
		local sizeConstraint = self._ui:FindFirstChildOfClass("UISizeConstraint")
		if sizeConstraint then
			sizeConstraint.MinSize = Vector2.new(0, 0)
		end

		-- Shrink header to match minimized size
		header.Size = UDim2.new(1, 0, 0, minimizedSize)

		self._ui.Size = UDim2.fromOffset(minimizedSize, minimizedSize)

		-- Center minimize button in the minimized frame
		if minimizeBtn then
			minimizeBtn.Position = UDim2.fromScale(0.5, 0.5)
			minimizeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
			minimizeBtn.Visible = true
			-- Temporarily reparent to header directly so it's visible
			minimizeBtn.Parent = header
		end
	end
end

--[[
	Restores the viewer from minimized or collapsed state.
]]
function TableEditor.Restore(self: InternalTableEditor)
	if self._minimized then
		self:Minimize()
	end
	if self._collapsed then
		self:Collapse()
	end
end

--[[
	Returns whether the viewer is minimized.
]]
function TableEditor.IsMinimized(self: InternalTableEditor): boolean
	return self._minimized
end

--[[
	Returns whether the viewer is collapsed.
]]
function TableEditor.IsCollapsed(self: InternalTableEditor): boolean
	return self._collapsed
end

-- Size Methods

--[[
	Auto-sizes the viewer based on content or available space.
]]
function TableEditor.AutoSize(self: InternalTableEditor)
	if not self._ui or not self.Options then
		return
	end

	local mode = self.Options.AutoSizeMode

	-- Fixed mode: don't auto-size at all, keep current manual size
	if mode == "fixed" then
		return
	end

	local table_ = self._ui.Viewer.Table
	local contentHeight = table_.ListLayout.AbsoluteContentSize.Y
	local headerHeight = 28
	local footerHeight = 28
	local padding = 16
	local newWidth = self._ui.Size.X.Offset
	local newHeight = self._ui.Size.Y.Offset

	if mode == "maxAvailable" then
		local screenGui = self._ui:FindFirstAncestorOfClass("ScreenGui")
		if screenGui then
			local screenSize = screenGui.AbsoluteSize
			local position = self._ui.AbsolutePosition
			local maxWidth = math.min(screenSize.X - position.X - 20, self.Options.MaxSize.X)
			local maxHeight = math.min(screenSize.Y - position.Y - 20, self.Options.MaxSize.Y)
			newWidth = math.max(maxWidth, self.Options.MinSize.X)
			newHeight = math.max(maxHeight, self.Options.MinSize.Y)
		end
	elseif mode == "content" or self.Options.AutoSizeToContent then
		local totalHeight =
			math.min(contentHeight + headerHeight + footerHeight + padding, self.Options.AutoSizeMaxHeight)
		newHeight = math.max(totalHeight, self.Options.MinSize.Y)
	end

	self._ui.Size = UDim2.fromOffset(newWidth, newHeight)
end

--[[
	Expands the viewer to fill available screen space.
]]
function TableEditor.ExpandToMax(self: InternalTableEditor)
	if not self._ui or not self.Options then
		return
	end

	-- Calculate content width by finding the widest entry
	local maxContentWidth = 0
	local viewer = self._ui.Viewer
	if viewer then
		local scrollFrame = viewer:FindFirstChild("ScrollingFrame")
		if scrollFrame then
			for _, child in scrollFrame:GetChildren() do
				if child:IsA("Frame") then
					-- Check the content width (key + value labels)
					local contentWidth = 0
					local keyLabel = child:FindFirstChild("KeyLabel")
					local valueLabel = child:FindFirstChild("ValueLabel")
					if keyLabel and keyLabel:IsA("TextLabel") then
						contentWidth += keyLabel.AbsoluteSize.X
					end
					if valueLabel and valueLabel:IsA("TextLabel") then
						contentWidth += valueLabel.AbsoluteSize.X + 20 -- padding between
					end
					maxContentWidth = math.max(maxContentWidth, contentWidth + 60) -- margin
				end
			end
		end
	end

	local screenGui = self._ui:FindFirstAncestorOfClass("ScreenGui")
	if screenGui then
		local screenSize = screenGui.AbsoluteSize
		local position = self._ui.AbsolutePosition

		-- For width: use content width if available, otherwise use available screen space
		local targetWidth = if maxContentWidth > 0
			then math.min(maxContentWidth, self.Options.MaxSize.X)
			else self.Options.MaxSize.X
		local maxWidth = math.min(screenSize.X - position.X - 20, targetWidth)

		-- For height: expand to max available
		local maxHeight = math.min(screenSize.Y - position.Y - 20, self.Options.MaxSize.Y)

		maxWidth = math.max(maxWidth, self.Options.MinSize.X)
		maxHeight = math.max(maxHeight, self.Options.MinSize.Y)
		self._ui.Size = UDim2.fromOffset(maxWidth, maxHeight)
	end
end

-- Options Methods

--[[
	Sets an option value.
]]
function TableEditor.SetOption(self: InternalTableEditor, key: string, value: any)
	(self.Options :: any)[key] = value
end

--[[
	Gets an option value.
]]
function TableEditor.GetOption(self: InternalTableEditor, key: string): any
	return (self.Options :: any)[key]
end

-- Sort Methods

--[[
	Sets the sort mode and re-sorts entries.
]]
function TableEditor.SetSortMode(self: InternalTableEditor, mode: SortMode)
	self.Options.SortMode = mode
	-- Invalidate cached sort keys
	for _, assoc in pairs(self._associations) do
		if typeof(assoc) == "table" then
			assoc._meta.CachedSortKey = nil
		end
	end
	self:_UpdateOrdering()
end

--[[
	Gets the current sort mode.
]]
function TableEditor.GetSortMode(self: InternalTableEditor): SortMode
	return self.Options.SortMode
end

-- Search & Filter API

function TableEditor.Search(self: InternalTableEditor, query: string, options: SearchOptions?): { SearchResult }
	local opts: SearchOptions = options or {}
	local target = opts.Target or "both"
	local caseSensitive = opts.CaseSensitive or false
	local fuzzyMatch = opts.FuzzyMatch or false
	local fuzzyThreshold = opts.FuzzyThreshold or 0.4
	local wholeWord = opts.WholeWord or false
	local useRegex = opts.Regex or false

	self:ClearSearch()
	if query == "" then
		return {}
	end

	local searchQuery = if caseSensitive then query else query:lower()
	local results: { SearchResult } = {}

	local function MatchesQuery(text: string): boolean
		local testText = if caseSensitive then text else text:lower()
		if useRegex then
			local success, result = pcall(function()
				return testText:match(searchQuery) ~= nil
			end)
			return success and result
		elseif fuzzyMatch then
			return FuzzyMatch(searchQuery, testText, fuzzyThreshold)
		elseif wholeWord then
			return testText:match("%f[%w]" .. searchQuery .. "%f[%W]") ~= nil
		else
			return testText:find(searchQuery, 1, true) ~= nil
		end
	end

	for pathString, association in pairs(self._associations) do
		if typeof(association) ~= "table" then
			continue
		end
		local keyStr = self:_FormatFieldKey(association.Key)
		local valueStr = self:_FormatFieldValue(association.Value, association)
		local keyMatches = (target == "keys" or target == "both") and MatchesQuery(keyStr)
		local valueMatches = (target == "values" or target == "both") and MatchesQuery(valueStr)

		if keyMatches or valueMatches then
			local matchedOn: "key" | "value" | "both" = if keyMatches and valueMatches
				then "both"
				elseif keyMatches then "key"
				else "value"
			table.insert(results, {
				Path = self:_GetAssociationPath(association),
				PathString = pathString,
				MatchedOn = matchedOn,
				Association = association,
			})
		end
	end

	table.sort(results, function(a, b)
		return a.PathString < b.PathString
	end)

	self._searchState = {
		Query = query,
		Options = opts,
		Results = results,
		CurrentIndex = 0,
		HighlightedAssociation = nil,
	}
	return results
end

function TableEditor.FindNext(self: InternalTableEditor): SearchResult?
	local state = self._searchState
	if #state.Results == 0 then
		return nil
	end
	if state.HighlightedAssociation then
		self:_ClearSearchHighlight()
	end
	state.CurrentIndex = state.CurrentIndex + 1
	if state.CurrentIndex > #state.Results then
		state.CurrentIndex = 1
	end
	local result = state.Results[state.CurrentIndex]
	if result then
		self:_HighlightSearchResult(result)
	end
	return result
end

function TableEditor.FindPrevious(self: InternalTableEditor): SearchResult?
	local state = self._searchState
	if #state.Results == 0 then
		return nil
	end
	if state.HighlightedAssociation then
		self:_ClearSearchHighlight()
	end
	state.CurrentIndex = state.CurrentIndex - 1
	if state.CurrentIndex < 1 then
		state.CurrentIndex = #state.Results
	end
	local result = state.Results[state.CurrentIndex]
	if result then
		self:_HighlightSearchResult(result)
	end
	return result
end

function TableEditor.ClearSearch(self: InternalTableEditor)
	if self._searchState.HighlightedAssociation then
		self:_ClearSearchHighlight()
	end
	self._searchState = {
		Query = nil,
		Options = nil,
		Results = {},
		CurrentIndex = 0,
		HighlightedAssociation = nil,
	}
end

function TableEditor.GetSearchResults(self: InternalTableEditor): { SearchResult }
	return self._searchState.Results
end

function TableEditor.GetCurrentSearchIndex(self: InternalTableEditor): number?
	if self._searchState.CurrentIndex == 0 then
		return nil
	end
	return self._searchState.CurrentIndex
end

function TableEditor.GetSearchResultCount(self: InternalTableEditor): number
	return #self._searchState.Results
end

function TableEditor.GoToSearchResult(self: InternalTableEditor, index: number): boolean
	local state = self._searchState
	if index < 1 or index > #state.Results then
		return false
	end
	if state.HighlightedAssociation then
		self:_ClearSearchHighlight()
	end
	state.CurrentIndex = index
	local result = state.Results[index]
	if result then
		self:_HighlightSearchResult(result)
	end
	return true
end

function TableEditor.SetKeyFilter(self: InternalTableEditor, filters: { string }?, options: FilterOptions?)
	local newFilters: { string } = {}
	if filters then
		local opts: FilterOptions = options or {}
		local caseSensitive = if opts.CaseSensitive ~= nil then opts.CaseSensitive else self.Options.CaseSensitive
		for _, filter in pairs(filters) do
			local trimmed = filter:gsub("^%s+", ""):gsub("%s+$", "")
			if trimmed ~= "" then
				table.insert(newFilters, if caseSensitive then trimmed else trimmed:lower())
			end
		end
	end
	if FiltersEqual(self._keyFilters, newFilters) then
		return
	end
	table.clear(self._keyFilters)
	for _, f in pairs(newFilters) do
		table.insert(self._keyFilters, f)
	end
	self._filterOptions.Key = if filters then (options or {}) else nil
	self:_UpdateFiltersAndExclusions()
end

function TableEditor.SetValueFilter(self: InternalTableEditor, filters: { string }?, options: FilterOptions?)
	local newFilters: { string } = {}
	if filters then
		local opts: FilterOptions = options or {}
		local caseSensitive = if opts.CaseSensitive ~= nil then opts.CaseSensitive else self.Options.CaseSensitive
		for _, filter in pairs(filters) do
			local trimmed = filter:gsub("^%s+", ""):gsub("%s+$", "")
			if trimmed ~= "" then
				table.insert(newFilters, if caseSensitive then trimmed else trimmed:lower())
			end
		end
	end
	if FiltersEqual(self._valueFilters, newFilters) then
		return
	end
	table.clear(self._valueFilters)
	for _, f in pairs(newFilters) do
		table.insert(self._valueFilters, f)
	end
	self._filterOptions.Value = if filters then (options or {}) else nil
	self:_UpdateFiltersAndExclusions()
end

function TableEditor.SetTypeFilter(self: InternalTableEditor, types: { string }?)
	local newFilters: { string } = {}
	if types then
		for _, typeStr in pairs(types) do
			local trimmed = typeStr:gsub("^%s+", ""):gsub("%s+$", ""):lower()
			if trimmed ~= "" then
				table.insert(newFilters, trimmed)
			end
		end
	end
	if FiltersEqual(self._typeFilters, newFilters) then
		return
	end
	table.clear(self._typeFilters)
	for _, f in pairs(newFilters) do
		table.insert(self._typeFilters, f)
	end
	self:_UpdateFiltersAndExclusions()
end

function TableEditor.SetTypeExclusion(self: InternalTableEditor, types: { string }?)
	local newFilters: { string } = {}
	if types then
		for _, typeStr in pairs(types) do
			local trimmed = typeStr:gsub("^%s+", ""):gsub("%s+$", ""):lower()
			if trimmed ~= "" then
				table.insert(newFilters, trimmed)
			end
		end
	end
	if FiltersEqual(self._typeExclusions, newFilters) then
		return
	end
	table.clear(self._typeExclusions)
	for _, f in pairs(newFilters) do
		table.insert(self._typeExclusions, f)
	end
	self:_UpdateFiltersAndExclusions()
end

function TableEditor.ClearAllFilters(self: InternalTableEditor)
	table.clear(self._keyFilters)
	table.clear(self._valueFilters)
	table.clear(self._typeFilters)
	table.clear(self._typeExclusions)
	self._filterOptions.Key = nil
	self._filterOptions.Value = nil
	self:_UpdateFiltersAndExclusions()
end

function TableEditor.GetActiveFilters(self: InternalTableEditor): {
	KeyFilters: { string },
	ValueFilters: { string },
	TypeFilters: { string },
	TypeExclusions: { string },
}
	return {
		KeyFilters = table.clone(self._keyFilters),
		ValueFilters = table.clone(self._valueFilters),
		TypeFilters = table.clone(self._typeFilters),
		TypeExclusions = table.clone(self._typeExclusions),
	}
end

function TableEditor.GetFilterMatchCount(self: InternalTableEditor): number
	return self._filterMatchCount
end

-- Entry Expansion API

function TableEditor.ExpandPath(self: InternalTableEditor, path: { any }): boolean
	local pathString = PathToString(path)
	local association = self._associations[pathString]
	if not association or typeof(association.Value) ~= "table" or association.IsRecursive then
		return false
	end
	return self:_SetAssociationExpanded(association, true, false)
end

function TableEditor.CollapsePath(self: InternalTableEditor, path: { any }): boolean
	local pathString = PathToString(path)
	local association = self._associations[pathString]
	if not association or typeof(association.Value) ~= "table" or association.IsRecursive then
		return false
	end
	return self:_SetAssociationExpanded(association, false, false)
end

function TableEditor.TogglePath(self: InternalTableEditor, path: { any }): boolean
	local pathString = PathToString(path)
	local association = self._associations[pathString]
	if not association or typeof(association.Value) ~= "table" or association.IsRecursive then
		return false
	end
	local currentState = self:_GetAssociationExpansionState(association)
	return self:_SetAssociationExpanded(association, not currentState, false)
end

function TableEditor.IsPathExpanded(self: InternalTableEditor, path: { any }): boolean?
	local pathString = PathToString(path)
	local association = self._associations[pathString]
	if not association or typeof(association.Value) ~= "table" then
		return nil
	end
	return self:_GetAssociationExpansionState(association)
end

function TableEditor.ExpandAllEntries(self: InternalTableEditor)
	for _, association in pairs(self._associations) do
		if not association.Parent and typeof(association.Value) == "table" then
			self:_SetAssociationExpanded(association, true, true)
		end
	end
end

function TableEditor.CollapseAllEntries(self: InternalTableEditor)
	for _, association in pairs(self._associations) do
		if not association.Parent and typeof(association.Value) == "table" then
			self:_SetAssociationExpanded(association, false, true)
		end
	end
end

function TableEditor.ExpandToDepth(self: InternalTableEditor, maxDepth: number)
	local function ExpandToDepthRecursive(association: Association, currentDepth: number)
		if typeof(association.Value) ~= "table" or association.IsRecursive then
			return
		end
		if currentDepth < maxDepth then
			self:_SetAssociationExpanded(association, true, false)
			if self.Options.LazyLoadChildren and not association.ChildrenLoaded then
				association.ChildrenLoaded = true
				self:_LoadChildAssociations(association, true)
			end
			if association.ChildrenLoaded then
				for _, childAssoc in pairs(self:_GetChildAssociations(association)) do
					ExpandToDepthRecursive(childAssoc, currentDepth + 1)
				end
			end
		else
			self:_SetAssociationExpanded(association, false, false)
		end
	end
	for _, association in pairs(self._associations) do
		if not association.Parent and typeof(association.Value) == "table" then
			ExpandToDepthRecursive(association, 0)
		end
	end
end

function TableEditor._SetupKeybindings(self: InternalTableEditor)
	local keybinds = self.Options.ToggleKeybind
	if not keybinds or not keybinds[1] then
		return
	end
	self._trove:Connect(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local allPressed = true
		for i, keyCode in pairs(keybinds) do
			if i == #keybinds then
				if input.KeyCode ~= keyCode then
					allPressed = false
				end
			else
				if not UserInputService:IsKeyDown(keyCode) then
					allPressed = false
				end
			end
		end
		if allPressed then
			self:Toggle()
		end
	end)
end

function TableEditor._UpdateLink(self: InternalTableEditor, skipBroadcast: boolean?)
	if not self._ui then
		return
	end
	local groupId = self._linkGroupId
	local isOutOfSync = false
	if groupId and linkGroups[groupId] then
		for viewerId in pairs(linkGroups[groupId]) do
			if viewerId == self._id then
				continue
			end
			local otherViewer = idToViewer[viewerId]
			if otherViewer and not DeepEqual(self.Data, otherViewer.Data) then
				isOutOfSync = true
				break
			end
		end
		if not skipBroadcast then
			for viewerId in pairs(linkGroups[groupId]) do
				if viewerId ~= self._id then
					local otherViewer = idToViewer[viewerId]
					if otherViewer then
						(otherViewer :: any):_UpdateLink(true)
					end
				end
			end
		end
	end
	local desyncIcon = FindHeaderChild(self._ui.Header, "DesyncIcon") :: ImageLabel?
	if desyncIcon then
		desyncIcon.Visible = isOutOfSync
	end
	local badgeLabel = FindHeaderChild(self._ui.Header, "BadgeLabel") :: TextLabel?
	if badgeLabel then
		badgeLabel.Visible = groupId ~= nil
		if groupId then
			badgeLabel.Text = tostring(groupId)
			badgeLabel.TextColor3 = if isOutOfSync then Color3.fromRGB(255, 100, 100) else Color3.fromRGB(100, 255, 100)
		end
	end
end

--[[
	Exports all options that differ from DEFAULT_OPTIONS as Luau code.
	This is useful for quickly getting the current position, size, and other settings.
	@returns string Luau code representing the non-default options
]]
function TableEditor._ExportNonDefaultSettings(self: InternalTableEditor): string
	local lines: { string } = {}
	table.insert(lines, "-- TableEditor Settings Export")
	table.insert(lines, "local options = {")

	-- Helper function to format a value as Luau code
	local function FormatValue(value: any, indent: string?): string
		local indentStr = indent or "\t"
		local valueType = typeof(value)
		if valueType == "string" then
			return string.format("%q", value)
		elseif valueType == "number" or valueType == "boolean" then
			return tostring(value)
		elseif valueType == "Vector2" then
			return string.format("Vector2.new(%g, %g)", value.X, value.Y)
		elseif valueType == "UDim2" then
			return string.format(
				"UDim2.new(%g, %d, %g, %d)",
				value.X.Scale,
				value.X.Offset,
				value.Y.Scale,
				value.Y.Offset
			)
		elseif valueType == "Color3" then
			local r = math.floor(value.R * 255 + 0.5)
			local g = math.floor(value.G * 255 + 0.5)
			local b = math.floor(value.B * 255 + 0.5)
			return string.format("Color3.fromRGB(%d, %d, %d)", r, g, b)
		elseif valueType == "EnumItem" then
			return tostring(value)
		elseif valueType == "Font" then
			return string.format(
				"Font.new(\"%s\", Enum.FontWeight.%s, Enum.FontStyle.%s)",
				value.Family,
				value.Weight.Name,
				value.Style.Name
			)
		elseif valueType == "table" then
			-- Handle simple key-value tables (like TypeOrdering, SyntaxHighlighting)
			local subLines: { string } = {}
			table.insert(subLines, "{")
			local keys = {}
			for k in pairs(value) do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for _, k in ipairs(keys) do
				local v = value[k]
				local keyStr = if typeof(k) == "string" and k:match("^[%a_][%w_]*$")
					then k
					else string.format("[%q]", tostring(k))
				table.insert(
					subLines,
					string.format("%s\t%s = %s,", indentStr, keyStr, FormatValue(v, indentStr .. "\t"))
				)
			end
			table.insert(subLines, indentStr .. "}")
			return table.concat(subLines, "\n")
		else
			-- For types we can't serialize (Instance, function, etc.)
			return string.format("nil --[[ %s: cannot serialize ]]", valueType)
		end
	end

	-- Helper function to compare values (handles tables and special types)
	local function ValuesEqual(a: any, b: any): boolean
		local typeA, typeB = typeof(a), typeof(b)
		if typeA ~= typeB then
			return false
		end
		if typeA == "table" then
			-- Deep compare
			for k, v in pairs(a) do
				if not ValuesEqual(v, b[k]) then
					return false
				end
			end
			for k in pairs(b) do
				if a[k] == nil then
					return false
				end
			end
			return true
		elseif typeA == "Vector2" then
			return a.X == b.X and a.Y == b.Y
		elseif typeA == "UDim2" then
			return a.X.Scale == b.X.Scale
				and a.X.Offset == b.X.Offset
				and a.Y.Scale == b.Y.Scale
				and a.Y.Offset == b.Y.Offset
		elseif typeA == "Color3" then
			return a.R == b.R and a.G == b.G and a.B == b.B
		elseif typeA == "Font" then
			return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style
		else
			return a == b
		end
	end

	-- Collect non-default options
	local hasChanges = false
	local sortedKeys: { string } = {}
	for key in pairs(DEFAULT_OPTIONS) do
		table.insert(sortedKeys, key)
	end
	table.sort(sortedKeys)

	-- Always include current UI position and size (these are what the user typically wants)
	if self._ui then
		local currentPosition = self._ui.Position
		local currentSize = Vector2.new(self._ui.Size.X.Offset, self._ui.Size.Y.Offset)
		hasChanges = true
		table.insert(lines, string.format("\tViewerPosition = %s,", FormatValue(currentPosition)))
		table.insert(lines, string.format("\tStartingSize = %s,", FormatValue(currentSize)))
	end

	for _, key in ipairs(sortedKeys) do
		-- Skip ViewerPosition and StartingSize since we handle them specially above
		if key == "ViewerPosition" or key == "StartingSize" then
			continue
		end

		local currentValue = self.Options[key]
		local defaultValue = DEFAULT_OPTIONS[key]

		-- Skip nil values and compare
		if currentValue ~= nil and not ValuesEqual(currentValue, defaultValue) then
			hasChanges = true
			local formattedValue = FormatValue(currentValue)
			table.insert(lines, string.format("\t%s = %s,", key, formattedValue))
		end
	end

	table.insert(lines, "}")

	if not hasChanges then
		return "-- All settings are at default values"
	end

	return table.concat(lines, "\n")
end

--[[
	Toggles debug mode which shows bounding boxes for invisible UI elements.
	@param enabled Whether debug mode should be enabled
]]
function TableEditor._SetDebugMode(self: InternalTableEditor, enabled: boolean)
	self._debugMode = enabled
	local debugColor = Color3.fromRGB(255, 0, 255) -- Magenta for visibility
	local debugTransparency = 0.8

	local function SetDebugBackground(instance: Instance)
		if not instance:IsA("GuiObject") then
			return
		end

		local gui = instance :: GuiObject

		if enabled then
			-- Only modify elements that are normally invisible (transparency == 1)
			if gui.BackgroundTransparency == 1 then
				gui:SetAttribute("_debugOriginalTransparency", 1)
				gui:SetAttribute("_debugOriginalColor", gui.BackgroundColor3:ToHex())
				gui.BackgroundTransparency = debugTransparency
				gui.BackgroundColor3 = debugColor
			end
		else
			-- Restore any element that has debug attributes (was modified by debug mode)
			local originalTransparency = gui:GetAttribute("_debugOriginalTransparency") :: number?
			if originalTransparency ~= nil then
				gui.BackgroundTransparency = originalTransparency
				gui:SetAttribute("_debugOriginalTransparency", nil)
			end
			local originalColorHex = gui:GetAttribute("_debugOriginalColor") :: string?
			if originalColorHex then
				gui.BackgroundColor3 = Color3.fromHex(originalColorHex)
				gui:SetAttribute("_debugOriginalColor", nil)
			end
		end
	end

	-- Apply to all descendants of the UI
	if self._ui then
		for _, descendant in self._ui:GetDescendants() do
			SetDebugBackground(descendant)
		end
	end
end

function TableEditor._FormatFieldKey(self: InternalTableEditor, key: any): string
	local baseFormat = FormatFieldKey(key)
	if not self.Options.VerboseKeys then
		return baseFormat
	end

	local keyType = typeof(key)
	local verboseTypes = self.Options.VerboseKeyTypes or {}
	if keyType == "Instance" and verboseTypes.Instance then
		local instance = key :: Instance
		local success, instancePath = pcall(function()
			return GetInstancePath(instance)
		end)
		if success then
			return `{baseFormat} ({instancePath})`
		end
	elseif keyType == "function" and verboseTypes["function"] then
		return `{baseFormat} ({tostring(key)})`
	elseif keyType == "thread" and verboseTypes.thread then
		return `{baseFormat} ({tostring(key)})`
	elseif keyType == "table" and verboseTypes.table then
		local count = GetN(key)
		return `{baseFormat} ({tostring(key)}) ({count} items)`
	end

	return baseFormat
end

function TableEditor._FormatFieldValue(self: InternalTableEditor, value: any, association: Association?): string
	if association and association.IsRecursive then
		return self.Options.RecursiveDisplayFormat:format(association.DuplicateOfKey or "root")
	end
	if association and association.IsDuplicateRef then
		return self.Options.DuplicateDisplayFormat:format(association.DuplicateOfKey or "unknown")
	end
	local valueType = typeof(value)
	local verboseEnabled = self.Options.VerboseValues
	local verboseTypes = self.Options.VerboseValueTypes or {}
	if valueType == "table" then
		if self.Options.ShowTableValue then
			-- ShowTableValue controls whether table values show anything at all
			-- Verbose table setting controls whether to show item count
			if verboseEnabled and verboseTypes.table then
				local count = if association and association._meta.CachedChildCount
					then association._meta.CachedChildCount
					else GetN(value)
				if association then
					association._meta.CachedChildCount = count
				end
				return `<Table> ({count} items)`
			end
			return "<Table>"
		else
			return ""
		end
	elseif valueType == "function" then
		if verboseEnabled and verboseTypes["function"] then
			return `<Function> ({tostring(value)})`
		end
		return "<Function>"
	elseif valueType == "thread" then
		if verboseEnabled and verboseTypes.thread then
			return `<Thread> ({tostring(value)})`
		end
		return "<Thread>"
	elseif valueType == "string" then
		return ("%q"):format(value)
	elseif valueType == "Instance" then
		local instance = value :: Instance
		if verboseEnabled and verboseTypes.Instance then
			local success, instancePath = pcall(function()
				return GetInstancePath(instance)
			end)
			if success then
				return `<Instance: {instance.ClassName}> ({instancePath})`
			end
		end
		-- Non-verbose: just show class name, no path
		return `<Instance: {instance.ClassName}>`
	elseif valueType == "number" then
		return FormatNumber(value, self.Options.NumberPrecision)
	else
		return tostring(value)
	end
end

function TableEditor._GetValueColor(self: InternalTableEditor, association: Association): Color3
	local highlighting = self.Options.SyntaxHighlighting
	if association.IsRecursive then
		return highlighting.RecursiveRef
	end
	if association.IsDuplicateRef then
		return highlighting.DuplicateRef
	end
	local valueType = typeof(association.Value)
	return highlighting[valueType] or highlighting.Other
end

function TableEditor._GetAssociationPath(self: InternalTableEditor, association: Association): { any }
	local path: { any } = {}
	local current: Association? = association
	while current and current.Key ~= nil do
		table.insert(path, 1, current.Key)
		current = current.Parent
	end
	return path
end

function TableEditor._GetAssociationPathString(self: InternalTableEditor, association: Association): string
	return PathToString(self:_GetAssociationPath(association))
end

function TableEditor._GetTableRefPath(self: InternalTableEditor, tbl: Table, visited: { [Table]: string }): string?
	return visited[tbl]
end

function TableEditor._GetChildAssociations(self: InternalTableEditor, parent: Association?): { Association }
	if parent then
		return self._childrenIndex[parent] or {}
	else
		local roots: { Association } = {}
		for _, assoc in pairs(self._associations) do
			if typeof(assoc) == "table" and not assoc.Parent then
				table.insert(roots, assoc)
			end
		end
		return roots
	end
end

function TableEditor._GetAssociationExpansionState(self: InternalTableEditor, association: Association): boolean
	local hasActiveFilters = self._keyFilters[1] ~= nil or self._typeExclusions[1] ~= nil
	if hasActiveFilters then
		if association._meta.FilterModeExpansionState ~= nil then
			return association._meta.FilterModeExpansionState
		end
		if association.Gui then
			local children = association.Gui:FindFirstChild("Children") :: Frame?
			if children then
				return children.Visible
			end
		end
		return self.Options.Expanded or false
	else
		if association._meta.ExpansionState ~= nil then
			return association._meta.ExpansionState
		end
		return self.Options.Expanded or false
	end
end

-- Stub methods that need full implementation
function TableEditor._CreateBaseUI(self: InternalTableEditor): TableEditorGui
	local options = self.Options

	-- Main Frame
	local frame = Instance.new("Frame")
	frame.Name = "TableEditor"
	frame.Size = UDim2.fromOffset(options.StartingSize.X, options.StartingSize.Y)
	frame.Position = if options.RememberPositionStates and self._visible
		then options.OpenPosition
		elseif options.RememberPositionStates then options.ClosedPosition
		else options.ViewerPosition
	frame.BackgroundColor3 = COLORS.MainBackground
	frame.BackgroundTransparency = TRANSPARENCY.MainBackground
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true -- Prevent bleed-through on collapse/minimize

	CreateCorner(SIZES.CornerRadius).Parent = frame
	CreateStroke(COLORS.MainBorder, SIZES.MainStrokeThickness).Parent = frame

	-- Size constraint
	local sizeConstraint = CreateSizeConstraint(options.MinSize, options.MaxSize)
	sizeConstraint.Parent = frame

	-- Create header using UiHelper
	local header = CreateHeader(options)
	header.Parent = frame

	-- Setup link mode functionality
	local linkButton = FindHeaderChild(header, "LinkButton") :: ImageButton

	-- Store as instance variables for cleanup
	self._linkModeConnection = nil :: RBXScriptConnection?
	self._linkModeHighlights = {} :: { [string]: Frame }

	local function ExitLinkMode()
		self._inLinkMode = false
		SetMaterialIcon(linkButton, "Link", Color3.fromRGB(180, 180, 180))

		-- Remove all highlights
		for _, highlight in pairs(self._linkModeHighlights) do
			highlight:Destroy()
		end
		table.clear(self._linkModeHighlights)

		-- Disconnect the click listener
		if self._linkModeConnection then
			self._linkModeConnection:Disconnect()
			self._linkModeConnection = nil
		end
	end

	local function EnterLinkMode()
		self._inLinkMode = true
		SetMaterialIcon(linkButton, "Link", Color3.fromRGB(100, 200, 255))

		-- Add highlight frames to all other viewers
		for viewerId, viewer in pairs(idToViewer) do
			if viewerId == self._id then
				continue -- Skip self
			end

			local viewerUI = viewer:GetUI()
			if not viewerUI then
				continue
			end

			local isLinked = self._linkGroupId ~= nil
				and viewer._linkGroupId ~= nil
				and self._linkGroupId == viewer._linkGroupId

			-- Create highlight overlay
			local highlight = Instance.new("Frame")
			highlight.Name = "LinkModeHighlight"
			highlight.Size = UDim2.fromScale(1, 1)
			highlight.Position = UDim2.fromScale(0, 0)
			highlight.BackgroundColor3 = if isLinked
				then Color3.fromRGB(100, 255, 100)
				else Color3.fromRGB(100, 200, 255)
			highlight.BackgroundTransparency = 0.9
			highlight.BorderSizePixel = 0
			highlight.ZIndex = 1000
			highlight.Parent = viewerUI

			local highlightCorner = CreateCorner(8)
			highlightCorner.Parent = highlight

			local highlightStroke = Instance.new("UIStroke")
			highlightStroke.Color = if isLinked then Color3.fromRGB(100, 255, 100) else Color3.fromRGB(100, 200, 255)
			highlightStroke.Thickness = 3
			highlightStroke.Transparency = 0.3
			highlightStroke.Parent = highlight

			-- Label showing viewer title and link status
			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Size = UDim2.new(1, -16, 0, 24)
			label.Position = UDim2.new(0.5, 0, 0.5, 0)
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
			label.BackgroundTransparency = 0.2
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextSize = 14
			label.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold)
			label.Text = if isLinked
				then "🔗 Click to UNLINK: " .. (viewer.Options.Title or "Viewer")
				else "🔗 Click to LINK: " .. (viewer.Options.Title or "Viewer")
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.ZIndex = 1001
			label.Parent = highlight

			local labelCorner = CreateCorner(4)
			labelCorner.Parent = label

			-- Hover effect
			highlight.MouseEnter:Connect(function()
				highlight.BackgroundTransparency = 0.7
				highlightStroke.Transparency = 0
				highlightStroke.Thickness = 4
			end)

			highlight.MouseLeave:Connect(function()
				highlight.BackgroundTransparency = 0.9
				highlightStroke.Transparency = 0.3
				highlightStroke.Thickness = 3
			end)

			-- Click to link/unlink
			local clickButton = Instance.new("TextButton")
			clickButton.Name = "ClickArea"
			clickButton.Size = UDim2.fromScale(1, 1)
			clickButton.BackgroundTransparency = 1
			clickButton.Text = ""
			clickButton.ZIndex = 1002
			clickButton.Parent = highlight

			clickButton.Activated:Connect(function()
				-- Check current link state (not captured isLinked which may be stale)
				local currentlyLinked = self._linkGroupId ~= nil
					and viewer._linkGroupId ~= nil
					and self._linkGroupId == viewer._linkGroupId
				if currentlyLinked then
					self:Unlink(viewer)
				else
					self:Link(viewer)
				end
				ExitLinkMode()
			end)

			self._linkModeHighlights[viewerId] = highlight
		end

		-- Listen for escape key to exit link mode
		self._linkModeConnection = UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.Escape then
				ExitLinkMode()
			end
		end)
	end

	-- Toggle link mode on click
	linkButton.Activated:Connect(function()
		if self._inLinkMode then
			ExitLinkMode()
		else
			EnterLinkMode()
		end
	end)

	-- Create viewer area
	local viewer = CreateViewerArea(options)
	viewer.Parent = frame

	local scrollingFrame = viewer:FindFirstChild("Table") :: ScrollingFrame

	-- Root Ghost Row (for adding new entries to root - always created, visibility controlled by Editable)
	local ghostRowResult = CreateGhostRow({
		Parent = scrollingFrame,
		Indent = 0,
		KeyFontFace = options.KeyFontFace,
		ValueFontFace = options.ValueFontFace,
		PlaceholderText = "value (use {} for table)",
	})
	local rootGhostRow = ghostRowResult.Row
	local keyInput = ghostRowResult.KeyInput
	local valueInput = ghostRowResult.ValueInput
	local addBtn = ghostRowResult.AddButton

	-- Control visibility based on Editable option
	rootGhostRow.Visible = options.Editable
	rootGhostRow:SetAttribute("CanShow", options.Editable)
	rootGhostRow.Name = "RootGhostRow" -- Name it for easy finding in _UpdateEditableState

	-- Add row handler
	local function DoAddRow()
		local keyText = keyInput.Text
		local valueText = valueInput.Text

		local parsedKey = ParseKeyInput(keyText)

		-- If no key, auto-generate
		if parsedKey == nil then
			parsedKey = GenerateAutoKey(self.Data)
		end

		local parsedValue = ParseInputValue(valueText)

		-- Add to root
		local success = self:AddRow({}, parsedKey, parsedValue)
		if success then
			keyInput.Text = ""
			valueInput.Text = ""

			-- Flash the newly added entry
			local pathString = tostring(parsedKey)
			local newAssoc = self._associations[pathString]
			if newAssoc then
				self:_FlashEntry(newAssoc, self.Options.FlashColor)
			end
		end
	end

	addBtn.Activated:Connect(DoAddRow)

	keyInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			DoAddRow()
		end
	end)

	valueInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			DoAddRow()
		end
	end)

	-- Setup scroll connection for pending flashes
	self._trove:Connect(scrollingFrame:GetPropertyChangedSignal("CanvasPosition"), function()
		if not self._flashThread then
			self._flashThread = task.delay(0.25, function()
				self:_ProcessPendingSearchFlashes()
				self._flashThread = nil
			end)
		end
	end)

	-- Create footer
	local footer = CreateFooter(options)
	footer.Parent = frame

	-- Create tooltip
	local tooltip = CreateTooltip(options)
	tooltip.Parent = frame

	-- Create drag detector
	local dragDetector = Instance.new("UIDragDetector")
	dragDetector.Name = "UIDragDetector"
	dragDetector.DragRelativity = Enum.UIDragDetectorDragRelativity.Relative
	dragDetector.Parent = frame

	-- Options Menu (hidden by default)
	local optionsMenu = Instance.new("Frame")
	optionsMenu.Name = "OptionsMenu"
	optionsMenu.Size = UDim2.fromOffset(180, 200)
	optionsMenu.Position = UDim2.new(1, -185, 1, -240)
	optionsMenu.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	optionsMenu.BorderSizePixel = 0
	optionsMenu.Visible = false
	optionsMenu.ZIndex = 10
	optionsMenu.Parent = frame

	local optionsCorner = CreateCorner(6)
	optionsCorner.Parent = optionsMenu

	local optionsStroke = CreateStroke(Color3.fromRGB(70, 70, 75), 1)
	optionsStroke.Parent = optionsMenu

	self:_CreateOptionsMenu(optionsMenu)

	-- Event Handlers
	self:_SetupBaseUIEvents(frame :: any, header, footer, viewer, optionsMenu)

	return frame :: any
end

function TableEditor._CreateEntry(self: InternalTableEditor, association: Association): EntryGui
	local options = self.Options

	local entry = Instance.new("Frame")
	entry.Name = self:_FormatFieldKey(association.Key)
	entry.Size = UDim2.new(1, 0, 0, 0)
	entry.AutomaticSize = Enum.AutomaticSize.Y
	entry.BackgroundTransparency = 1
	entry.BorderSizePixel = 0
	association.Gui = entry :: EntryGui
	self._guiToAssociation[entry] = association
	-- Defer parenting until entry is fully built to prevent layout race conditions
	local entryParent: Instance? = nil
	if association.Parent and association.Parent.Gui then
		entryParent = association.Parent.Gui.Children
	elseif self._ui then
		entryParent = self._ui.Viewer.Table
	end

	local infoBox = Instance.new("Frame")
	infoBox.Name = "InfoBox"
	infoBox.Size = UDim2.new(1, -16 * association.Depth, 0, 22)
	infoBox.Position = UDim2.new(1, 0, 0, 0)
	infoBox.AnchorPoint = Vector2.new(1, 0)
	infoBox.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	infoBox.BackgroundTransparency = 0.6
	infoBox.BorderSizePixel = 0
	infoBox.Parent = entry

	local infoCorner = CreateCorner(4)
	infoCorner.Parent = infoBox

	local changeFlash = Instance.new("Frame")
	changeFlash.Name = "ChangeFlash"
	changeFlash.Size = UDim2.new(1, 0, 1, 0)
	changeFlash.BackgroundColor3 = options.FlashColor
	changeFlash.BackgroundTransparency = 1
	changeFlash.BorderSizePixel = 0
	changeFlash.ZIndex = 0
	changeFlash.Parent = infoBox

	local flashCorner = CreateCorner(4)
	flashCorner.Parent = changeFlash

	-- Cache commonly used checks
	local isExpandableTable = typeof(association.Value) == "table" and not association.IsRecursive

	-- Left Actions Container (fixed size, for expand/focus buttons)
	local leftActions = Instance.new("Frame")
	leftActions.Name = "LeftActions"
	leftActions.Size = UDim2.fromOffset(38, 22)
	leftActions.Position = UDim2.fromOffset(0, 0) -- Explicitly position at left edge
	leftActions.BackgroundTransparency = 1
	leftActions.ZIndex = 2
	leftActions.Parent = infoBox

	-- Expansion Button
	local expansionButton = Instance.new("ImageButton")
	expansionButton.Name = "ExpansionButton"
	expansionButton.Size = UDim2.fromOffset(16, 16)
	expansionButton.Position = UDim2.fromOffset(4, 3)
	expansionButton.BackgroundTransparency = 1
	expansionButton.AutoButtonColor = false
	expansionButton.Visible = isExpandableTable
	expansionButton.ZIndex = 2
	expansionButton.Parent = leftActions

	local expandIcon = CreateIcon(Vector2.new(16, 0), UDim2.fromOffset(12, 12))
	expandIcon.Parent = expansionButton

	-- Focus Button (for tables)
	local focusButton = Instance.new("ImageButton")
	focusButton.Name = "FocusButton"
	focusButton.Size = UDim2.fromOffset(14, 14)
	focusButton.Position = UDim2.fromOffset(20, 4)
	focusButton.BackgroundTransparency = 1
	focusButton.AutoButtonColor = false
	focusButton.Visible = isExpandableTable
	focusButton.ZIndex = 2
	focusButton.Parent = leftActions

	local focusIcon = CreateIcon(Vector2.new(112, 0), UDim2.fromOffset(10, 10), Color3.fromRGB(150, 150, 155))
	focusIcon.Parent = focusButton

	-- Check if this value is frozen and apply frozen value early
	local pathStr = self:_GetAssociationPathString(association)
	local isValueFrozen = self._frozenValues[pathStr] ~= nil
	if isValueFrozen then
		association.Value = self._frozenValues[pathStr]
	end

	-- Content Row (flex layout: key, value, freeze button, delete button)
	local contentRow = Instance.new("Frame")
	contentRow.Name = "ContentRow"
	contentRow.Size = UDim2.new(1, -38, 1, 0) -- Full width minus left actions
	contentRow.Position = UDim2.fromOffset(38, 0)
	contentRow.BackgroundTransparency = 1
	contentRow.ZIndex = 2

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Horizontal
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	contentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 0)
	contentLayout.Parent = contentRow

	contentRow.Parent = infoBox

	-- Field Key (grows with FlexItem - key gets more space than value)
	local isGhost = association.IsGhost == true
	local fieldKey = Instance.new("TextBox")
	fieldKey.Name = "FieldKey"
	fieldKey.Size = UDim2.new(0.5, 0, 1, 0) -- Base 50%, flex will adjust
	fieldKey.BackgroundTransparency = 1
	fieldKey.TextColor3 = if typeof(association.Key) == "number"
		then options.SyntaxHighlighting.Other
		else options.SyntaxHighlighting.Default
	fieldKey.TextSize = 13
	fieldKey.FontFace = options.KeyFontFace
	fieldKey.Text = self:_FormatFieldKey(association.Key)
	fieldKey.TextEditable = options.Editable and not isGhost
	fieldKey.ClearTextOnFocus = false
	fieldKey.TextXAlignment = Enum.TextXAlignment.Left
	fieldKey.TextTruncate = options.TextTruncateType
	fieldKey.LayoutOrder = 1
	-- Apply ghost styling (strikethrough effect via transparency)
	if isGhost then
		fieldKey.TextTransparency = 0.4
	end
	fieldKey.Parent = contentRow

	local keyFlexItem = Instance.new("UIFlexItem")
	keyFlexItem.FlexMode = Enum.UIFlexMode.Fill
	keyFlexItem.ItemLineAlignment = Enum.ItemLineAlignment.Stretch
	keyFlexItem.GrowRatio = 2 -- Key grows more than value
	keyFlexItem.Parent = fieldKey

	-- Field Value (grows with FlexItem - value gets less space than key)
	local fieldValue = Instance.new("TextBox")
	fieldValue.Name = "FieldValue"
	fieldValue.Size = UDim2.new(0.5, 0, 1, 0) -- Base 50%, flex will adjust
	fieldValue.BackgroundTransparency = 1
	fieldValue.TextColor3 = self:_GetValueColor(association)
	fieldValue.TextSize = 13
	fieldValue.FontFace = options.ValueFontFace
	fieldValue.Text = self:_FormatFieldValue(association.Value, association)

	local canEditValue = options.Editable
		and typeof(association.Value) ~= "table"
		and typeof(association.Value) ~= "function"
		and not association.IsRecursive
		and not association.IsDuplicateRef
		and not isGhost
	fieldValue.TextEditable = canEditValue
	fieldValue.ClearTextOnFocus = false
	fieldValue.TextXAlignment = Enum.TextXAlignment.Right
	fieldValue.TextTruncate = options.TextTruncateType
	fieldValue.LayoutOrder = 2
	-- Apply ghost styling (strikethrough effect via transparency)
	if isGhost then
		fieldValue.TextTransparency = 0.4
	end
	fieldValue.Parent = contentRow

	local valueFlexItem = Instance.new("UIFlexItem")
	valueFlexItem.FlexMode = Enum.UIFlexMode.Fill
	valueFlexItem.ItemLineAlignment = Enum.ItemLineAlignment.Stretch
	valueFlexItem.GrowRatio = 1 -- Value grows less than key
	valueFlexItem.Parent = fieldValue

	-- Freeze Value Button (fixed size, shown on hover) - LayoutOrder 3
	-- pathStr and isValueFrozen already computed earlier
	local freezeValueBtn = Instance.new("ImageButton")
	freezeValueBtn.Name = "FreezeValueButton"
	freezeValueBtn.Size = UDim2.fromOffset(18, 22) -- Fixed width, full height for clickability
	freezeValueBtn.BackgroundTransparency = 1
	freezeValueBtn.AutoButtonColor = false
	freezeValueBtn.Visible = isValueFrozen and not isGhost -- Always visible if frozen, otherwise show on hover (not for ghosts)
	freezeValueBtn.LayoutOrder = 3 -- Left of delete button
	freezeValueBtn.Parent = contentRow

	-- Use Material Design Pause/PlayArrow icons (show action to take: Pause=freeze, PlayArrow=unfreeze)
	local freezeValueIcon = CreateMaterialIcon(
		if isValueFrozen then "PlayArrow" else "Pause",
		UDim2.fromOffset(12, 12),
		if isValueFrozen then Color3.fromRGB(100, 200, 100) else Color3.fromRGB(100, 180, 255)
	)
	if freezeValueIcon then
		freezeValueIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		freezeValueIcon.Position = UDim2.fromScale(0.5, 0.5)
		freezeValueIcon.Parent = freezeValueBtn
	end

	-- Delete Row Button (fixed size, always visible when Editable, rightmost) - LayoutOrder 4
	local deleteBtn = Instance.new("ImageButton")
	deleteBtn.Name = "DeleteRowButton"
	deleteBtn.Size = UDim2.fromOffset(18, 22) -- Fixed width, full height for clickability
	deleteBtn.BackgroundTransparency = 1
	deleteBtn.AutoButtonColor = false
	deleteBtn.Visible = options.Editable and not isGhost -- Always visible when Editable (not for ghosts)
	deleteBtn.LayoutOrder = 4 -- Rightmost button
	deleteBtn:SetAttribute("CanShow", options.Editable and not isGhost)
	deleteBtn.Parent = contentRow

	local deleteIcon = CreateIcon(Vector2.new(32, 0), UDim2.fromOffset(10, 10), Color3.fromRGB(255, 100, 100))
	deleteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	deleteIcon.Position = UDim2.fromScale(0.5, 0.5)
	deleteIcon.Parent = deleteBtn

	-- Show/hide freeze button on hover (delete button always visible when Editable)
	infoBox.MouseEnter:Connect(function()
		if not isGhost then
			freezeValueBtn.Visible = true
		end
	end)

	infoBox.MouseLeave:Connect(function()
		-- Keep freeze button visible if value is frozen (and not ghost)
		if not self._frozenValues[pathStr] or isGhost then
			freezeValueBtn.Visible = false
		end
	end)

	-- Freeze value button handler
	freezeValueBtn.Activated:Connect(function()
		if self._frozenValues[pathStr] then
			-- Unfreeze the value - get current value from data and update display
			self._frozenValues[pathStr] = nil
			SetMaterialIcon(freezeValueBtn, "Pause", Color3.fromRGB(100, 180, 255))

			-- Get the current value from the actual data and update the association
			local path = self:_GetAssociationPath(association)
			if path and path[1] then
				local currentValue = self.Data
				for _, key in ipairs(path) do
					if typeof(currentValue) == "table" then
						currentValue = currentValue[key]
					else
						break
					end
				end
				-- Update association with current value and refresh display
				association.Value = currentValue
				self:_UpdateEntryUI(association)
			end
		else
			-- Freeze the value at its current state
			if typeof(association.Value) == "table" then
				self._frozenValues[pathStr] = TableHelper.DeepClone(association.Value)
			else
				self._frozenValues[pathStr] = association.Value
			end
			SetMaterialIcon(freezeValueBtn, "PlayArrow", Color3.fromRGB(100, 200, 100))
		end
	end)

	-- Delete button handler
	deleteBtn.Activated:Connect(function()
		local path = self:_GetAssociationPath(association)
		if path[1] then
			local parentPath = {}
			for i = 1, #path - 1 do
				table.insert(parentPath, path[i])
			end
			local key = path[#path]
			self:RemoveRow(parentPath, key)
		end
	end)

	-- Handle key renaming (always connect handlers, check editability at runtime)
	do
		local originalKeyText = fieldKey.Text
		local originalKey = association.Key
		fieldKey.Focused:Connect(function()
			-- Check current editable state
			if not self.Options.Editable then
				return
			end
			originalKeyText = fieldKey.Text
			originalKey = association.Key
		end)

		fieldKey.FocusLost:Connect(function(enterPressed)
			-- Check current editable state
			if not self.Options.Editable then
				fieldKey.Text = self:_FormatFieldKey(association.Key)
				return
			end

			local newText = fieldKey.Text:gsub("^%s+", ""):gsub("%s+$", "")
			if newText == originalKeyText or newText == "" then
				fieldKey.Text = originalKeyText
				return
			end

			local newKey: any = if tonumber(newText) then tonumber(newText) else newText
			if newKey ~= originalKey then
				local path = self:_GetAssociationPath(association)
				if not path[1] then
					fieldKey.Text = originalKeyText
					return
				end

				local parentPath: { any } = {}
				for i = 1, #path - 1 do
					table.insert(parentPath, path[i])
				end

				local parentTable = self.Data
				for _, k in pairs(parentPath) do
					if typeof(parentTable) ~= "table" then
						fieldKey.Text = originalKeyText
						return
					end
					parentTable = parentTable[k]
				end

				if typeof(parentTable) ~= "table" then
					fieldKey.Text = originalKeyText
					return
				end

				if parentTable[newKey] ~= nil and newKey ~= originalKey then
					warn("TableEditor: Key already exists:", newKey)
					fieldKey.Text = originalKeyText
					return
				end

				local value = parentTable[originalKey]

				-- Store old data for proper diff detection
				local oldData = TableHelper.DeepClone(self.Data)

				-- Perform the rename in data
				parentTable[newKey] = value
				parentTable[originalKey] = nil

				local oldFullPath = table.clone(parentPath)
				table.insert(oldFullPath, originalKey)
				local oldPathString = PathToString(oldFullPath)

				local newFullPath = table.clone(parentPath)
				table.insert(newFullPath, newKey)
				local newPathString = PathToString(newFullPath)

				local removeInfo: DataEditedInfo = {
					Path = oldFullPath,
					PathString = oldPathString,
					OldValue = value,
					NewValue = nil,
					EditType = "remove",
					Source = "edit",
				}
				self.OnDataEdited:Fire(removeInfo)
				self:_FireValueWatchers(removeInfo)

				local addInfo: DataEditedInfo = {
					Path = newFullPath,
					PathString = newPathString,
					OldValue = nil,
					NewValue = value,
					EditType = "add",
					Source = "edit",
				}
				self.OnDataEdited:Fire(addInfo)
				self:_FireValueWatchers(addInfo)

				-- Pass oldData so diff detection properly removes old association
				self:_UpdateAssociations(oldData)
				self:_UpdateFiltersAndExclusions()
				self:_UpdateLink()
				return
			end
		end)
	end

	local keySizeConstraint = Instance.new("UISizeConstraint")
	keySizeConstraint.Name = "SizeConstraint"
	keySizeConstraint.MinSize = Vector2.new(options.MinKeyPixels, 0)
	keySizeConstraint.Parent = fieldKey

	-- Handle value editing (always connect handlers, check editability at runtime)
	-- Only connect if value type allows editing (tables/functions/recursive/duplicate can never be edited)
	local canEverEdit = typeof(association.Value) ~= "table"
		and typeof(association.Value) ~= "function"
		and not association.IsRecursive
		and not association.IsDuplicateRef

	if canEverEdit then
		local originalValue = association.Value
		fieldValue.Focused:Connect(function()
			-- Check current editable state
			if not self.Options.Editable then
				return
			end
			originalValue = association.Value
			if typeof(originalValue) == "string" then
				fieldValue.Text = originalValue
			end
		end)

		fieldValue.FocusLost:Connect(function(enterPressed: boolean)
			-- Check current editable state
			if not self.Options.Editable then
				fieldValue.Text = self:_FormatFieldValue(association.Value, association)
				return
			end

			local newText = fieldValue.Text
			if not enterPressed then
				fieldValue.Text = self:_FormatFieldValue(originalValue, association)
				return
			end

			local newValue: any
			local isNilValue = false
			if newText == "true" then
				newValue = true
			elseif newText == "false" then
				newValue = false
			elseif newText == "nil" then
				newValue = nil
				isNilValue = true
			elseif tonumber(newText) ~= nil then
				newValue = tonumber(newText)
			else
				if
					(newText:sub(1, 1) == "\"" and newText:sub(-1) == "\"")
					or (newText:sub(1, 1) == "'" and newText:sub(-1) == "'")
				then
					newValue = newText:sub(2, -2)
				else
					newValue = newText
				end
			end

			if isNilValue then
				local path = self:_GetAssociationPath(association)
				if path[1] then
					local parentPath: { any } = {}
					for i = 1, #path - 1 do
						table.insert(parentPath, path[i])
					end
					local key = path[#path]
					self:RemoveRow(parentPath, key)
				end
				return
			end

			if newValue == originalValue then
				fieldValue.Text = self:_FormatFieldValue(originalValue, association)
				return
			end

			local path = self:_GetAssociationPath(association)
			if not path[1] then
				fieldValue.Text = self:_FormatFieldValue(originalValue, association)
				return
			end

			local target = self.Data
			for i = 1, #path - 1 do
				if typeof(target) ~= "table" then
					fieldValue.Text = self:_FormatFieldValue(originalValue, association)
					warn("TableEditor: Failed to navigate to path for value edit")
					return
				end
				target = target[path[i]]
			end

			if typeof(target) ~= "table" then
				fieldValue.Text = self:_FormatFieldValue(originalValue, association)
				warn("TableEditor: Target is not a table")
				return
			end

			local key = path[#path]
			local oldValue = originalValue
			target[key] = newValue
			association.Value = newValue

			fieldValue.Text = self:_FormatFieldValue(newValue, association)
			fieldValue.TextColor3 = self:_GetValueColor(association)
			association._meta.LastValueHash = HashValue(newValue)

			local pathString = PathToString(path)

			local editInfo: DataEditedInfo = {
				Path = path,
				PathString = pathString,
				OldValue = oldValue,
				NewValue = newValue,
				EditType = "set",
				Source = "edit",
			}
			self.OnDataEdited:Fire(editInfo)
			self:_FireValueWatchers(editInfo)
			self:_UpdateLink()
			if self.Options.FlashOnChange then
				self:_FlashEntry(association, self.Options.FlashColor)
			end
		end)
	end

	-- Children Container
	local children = Instance.new("Frame")
	children.Name = "Children"
	children.Size = UDim2.new(1, 0, 0, 0)
	children.Position = UDim2.fromOffset(0, 22)
	children.AutomaticSize = Enum.AutomaticSize.Y
	children.BackgroundTransparency = 1
	children.BorderSizePixel = 0
	children.Visible = false
	children.Parent = entry

	local childrenLayout = Instance.new("UIListLayout")
	childrenLayout.Name = "ListLayout"
	childrenLayout.SortOrder = Enum.SortOrder.LayoutOrder
	childrenLayout.Padding = UDim.new(0, 1)
	childrenLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	childrenLayout.Parent = children

	-- Ghost Row (always created for tables, hidden when not Editable)
	if typeof(association.Value) == "table" and not association.IsRecursive and not association.IsDuplicateRef then
		local ghostIndent = 16 * (association.Depth + 1)

		local ghostRowResult = CreateGhostRow({
			Parent = children,
			Indent = ghostIndent,
			KeyFontFace = options.KeyFontFace,
			ValueFontFace = options.ValueFontFace,
			PlaceholderText = "value",
		})
		-- Hide ghost row if not editable
		ghostRowResult.Row.Visible = options.Editable

		local keyInput = ghostRowResult.KeyInput
		local valueInput = ghostRowResult.ValueInput
		local addBtn = ghostRowResult.AddButton

		local function DoAddRow()
			local path = self:_GetAssociationPath(association)
			local keyText = keyInput.Text
			local valueText = valueInput.Text
			local parsedKey = ParseKeyInput(keyText)
			if parsedKey == nil then
				parsedKey = GenerateAutoKey(association.Value)
			end

			local parsedValue = ParseInputValue(valueText)
			local success = self:AddRow(path, parsedKey, parsedValue)
			if success then
				keyInput.Text = ""
				valueInput.Text = ""
				local fullPath = table.clone(path)
				table.insert(fullPath, parsedKey)
				local pathString = PathToString(fullPath)
				local newAssoc = self._associations[pathString]
				if newAssoc then
					self:_FlashEntry(newAssoc, self.Options.FlashColor)
				end
			end
		end

		addBtn.Activated:Connect(DoAddRow)
		keyInput.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				DoAddRow()
			end
		end)
		valueInput.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				DoAddRow()
			end
		end)
	end

	if isExpandableTable then
		local expanded = if association._meta.ExpansionState ~= nil
			then association._meta.ExpansionState
			else options.Expanded

		local function SetExpanded(state: boolean)
			local hasActiveFilters = self._keyFilters[1] ~= nil or self._typeExclusions[1] ~= nil
			if hasActiveFilters then
				association._meta.FilterModeExpansionState = state
			else
				association._meta.ExpansionState = state
				expanded = state
			end
			children.Visible = state
			expandIcon.Rotation = if state then 90 else 0

			if state then
				if association._meta.UnloadThread then
					task.cancel(association._meta.UnloadThread)
					association._meta.UnloadThread = nil
				end

				if options.LazyLoadChildren and not association.ChildrenLoaded then
					association.ChildrenLoaded = true
					self:_LoadChildAssociations(association, false)

					-- If in diff mode, update diff indicators for newly loaded children
					if self._diffState and self._diffState.Active then
						self:_UpdateDiffUI()
					end
				elseif self._diffState and self._diffState.Active then
					-- Children already loaded but we're in diff mode - still need to update UI
					self:_UpdateDiffUI()
				end

				if hasActiveFilters and association.ChildrenLoaded then
					for _, childAssoc in pairs(self:_GetChildAssociations(association)) do
						if childAssoc.Gui then
							childAssoc.Gui.Visible = true
						end
					end
				end
			else
				if options.LazyLoadChildren and association.ChildrenLoaded and not hasActiveFilters then
					association._meta.UnloadThread = task.delay(options.UnloadDelay, function()
						local currentExpanded = association._meta.ExpansionState
						if not currentExpanded and association.ChildrenLoaded and association.Gui then
							local function UnloadChildrenRecursive(parentAssoc: Association)
								local childrenList = self._childrenIndex[parentAssoc]
								if not childrenList then
									return
								end

								for _, childAssoc in pairs(childrenList) do
									if childAssoc.ChildrenLoaded then
										UnloadChildrenRecursive(childAssoc)
									end
									if typeof(childAssoc.Value) == "table" then
										self._tableRefs[childAssoc.Value] = nil
									end
									if childAssoc.Gui then
										self:_ReturnEntryToPool(childAssoc.Gui)
										childAssoc.Gui = nil
									end
									childAssoc.ChildrenLoaded = false
									childAssoc._meta.CachedSortKey = nil
								end
								self._childrenIndex[parentAssoc] = nil
							end
							UnloadChildrenRecursive(association)
							association.ChildrenLoaded = false
						end
						association._meta.UnloadThread = nil
					end)
				end
			end
		end

		local function SetExpandedRecursive(state: boolean)
			local hasActiveFilters = self._keyFilters[1] ~= nil or self._typeExclusions[1] ~= nil
			local function ExpandAllNested(assoc: Association)
				if typeof(assoc.Value) ~= "table" or assoc.IsRecursive then
					return
				end
				if not assoc.Gui then
					return
				end

				local childrenFrame = assoc.Gui:FindFirstChild("Children") :: Frame?
				if not childrenFrame then
					return
				end

				if hasActiveFilters then
					assoc._meta.FilterModeExpansionState = true
				else
					assoc._meta.ExpansionState = true
				end
				childrenFrame.Visible = true
				local infoBox = assoc.Gui:FindFirstChild("InfoBox")
				if infoBox then
					local expBtn = infoBox:FindFirstChild("ExpansionButton")
					if expBtn then
						local icon = expBtn:FindFirstChild("Icon") :: ImageLabel?
						if icon then
							icon.Rotation = 90
						end
					end
				end

				if options.LazyLoadChildren and not assoc.ChildrenLoaded then
					assoc.ChildrenLoaded = true
					self:_LoadChildAssociations(assoc, true)

					-- If in diff mode, update diff indicators for newly loaded children
					if self._diffState and self._diffState.Active then
						self:_UpdateDiffUI()
					end
				end
				if assoc.ChildrenLoaded then
					for _, childAssoc in pairs(self:_GetChildAssociations(assoc)) do
						ExpandAllNested(childAssoc)
					end
				end
			end

			local function CollapseAllNested(assoc: Association)
				if typeof(assoc.Value) ~= "table" or assoc.IsRecursive then
					return
				end

				if assoc.ChildrenLoaded then
					for _, childAssoc in pairs(self:_GetChildAssociations(assoc)) do
						CollapseAllNested(childAssoc)
					end
				end
				if assoc.Gui then
					local childrenFrame = assoc.Gui:FindFirstChild("Children") :: Frame?
					if childrenFrame then
						-- Set expansion state to appropriate storage
						if hasActiveFilters then
							assoc._meta.FilterModeExpansionState = false
						else
							assoc._meta.ExpansionState = false
						end
						childrenFrame.Visible = false
						local infoBox = assoc.Gui:FindFirstChild("InfoBox")
						if infoBox then
							local expBtn = infoBox:FindFirstChild("ExpansionButton")
							if expBtn then
								local icon = expBtn:FindFirstChild("Icon") :: ImageLabel?
								if icon then
									icon.Rotation = 0
								end
							end
						end
					end
				end
			end

			if state then
				SetExpanded(true)
				if association.ChildrenLoaded then
					for _, childAssoc in pairs(self:_GetChildAssociations(association)) do
						ExpandAllNested(childAssoc)
					end
				end
			else
				if association.ChildrenLoaded then
					for _, childAssoc in pairs(self:_GetChildAssociations(association)) do
						CollapseAllNested(childAssoc)
					end
				end
				SetExpanded(false)
			end
		end

		expansionButton.Activated:Connect(function()
			local hasActiveFilters = self._keyFilters[1] ~= nil or self._typeExclusions[1] ~= nil
			local currentState: boolean

			if hasActiveFilters then
				if association._meta.FilterModeExpansionState ~= nil then
					currentState = association._meta.FilterModeExpansionState
				else
					currentState = children.Visible
				end
			else
				if association._meta.ExpansionState ~= nil then
					currentState = association._meta.ExpansionState
				else
					currentState = options.Expanded or false
				end
			end
			if
				UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			then
				SetExpandedRecursive(not currentState)
			else
				SetExpanded(not currentState)
			end
		end)

		focusButton.Activated:Connect(function()
			local path = self:_GetAssociationPath(association)
			self:FocusTable(path)
		end)
		SetExpanded(expanded)
	end

	if options.ShowTooltips and self._ui then
		local tooltip = self._ui.Tooltip
		association._meta.TooltipThreads = {}

		local function SetupTooltip(textBox: TextBox)
			local delayThread: thread? = nil

			textBox.MouseEnter:Connect(function()
				if textBox.TextFits then
					return
				end

				delayThread = task.delay(options.TooltipDelay, function()
					if not self._ui or not association.Gui then
						return
					end

					tooltip.Label.Text = textBox.Text
					tooltip.Visible = true
					local absPos = textBox.AbsolutePosition
					local absSize = textBox.AbsoluteSize
					local framePos = self._ui.AbsolutePosition
					local tooltipX = absPos.X - framePos.X
					local tooltipY = absPos.Y - framePos.Y + absSize.Y + 4
					local frameSize = self._ui.AbsoluteSize
					local tooltipSize = tooltip.AbsoluteSize
					if tooltipX + tooltipSize.X > frameSize.X then
						tooltipX = frameSize.X - tooltipSize.X - 4
					end
					if tooltipY + tooltipSize.Y > frameSize.Y then
						tooltipY = absPos.Y - framePos.Y - tooltipSize.Y - 4
					end
					tooltip.Position = UDim2.fromOffset(math.max(4, tooltipX), math.max(4, tooltipY))

					if association._meta.TooltipThreads then
						for i, t in pairs(association._meta.TooltipThreads) do
							if t == delayThread then
								table.remove(association._meta.TooltipThreads, i)
								break
							end
						end
					end
					delayThread = nil
				end)

				if association._meta.TooltipThreads and delayThread then
					table.insert(association._meta.TooltipThreads, delayThread)
				end
			end)

			textBox.MouseLeave:Connect(function()
				if delayThread then
					task.cancel(delayThread)
					if association._meta.TooltipThreads then
						for i, t in pairs(association._meta.TooltipThreads) do
							if t == delayThread then
								table.remove(association._meta.TooltipThreads, i)
								break
							end
						end
					end
					delayThread = nil
				end
				tooltip.Visible = false
			end)
		end
		SetupTooltip(fieldKey)
		SetupTooltip(fieldValue)
	end

	-- Parent entry now that it's fully built (prevents layout race conditions)
	entry.Parent = entryParent

	return entry :: EntryGui
end

function TableEditor._SetAssociationExpanded(
	self: InternalTableEditor,
	association: Association,
	state: boolean,
	recursive: boolean?
): boolean
	if typeof(association.Value) ~= "table" or association.IsRecursive then
		return false
	end

	local hasActiveFilters = self._keyFilters[1] ~= nil or self._typeExclusions[1] ~= nil
	local options = self.Options

	-- Helper to set expansion for a single association
	local function SetSingleExpanded(assoc: Association, newState: boolean)
		if typeof(assoc.Value) ~= "table" or assoc.IsRecursive then
			return
		end

		-- Update the expansion state
		if hasActiveFilters then
			assoc._meta.FilterModeExpansionState = newState
		else
			assoc._meta.ExpansionState = newState
		end

		-- Update GUI if present
		if assoc.Gui then
			local children = assoc.Gui:FindFirstChild("Children") :: Frame?
			if children then
				children.Visible = newState
			end

			local infoBox = assoc.Gui:FindFirstChild("InfoBox")
			if infoBox then
				local expBtn = infoBox:FindFirstChild("ExpansionButton")
				if expBtn then
					local icon = expBtn:FindFirstChild("Icon") :: ImageLabel?
					if icon then
						icon.Rotation = if newState then 90 else 0
					end
				end
			end
		end

		if newState then
			-- Expanding
			if assoc._meta.UnloadThread then
				task.cancel(assoc._meta.UnloadThread)
				assoc._meta.UnloadThread = nil
			end

			if options.LazyLoadChildren and not assoc.ChildrenLoaded then
				assoc.ChildrenLoaded = true
				self:_LoadChildAssociations(assoc, false) -- Don't skip filter update, ensure ordering is updated

				-- If in diff mode, update diff indicators for newly loaded children
				if self._diffState and self._diffState.Active then
					self:_UpdateDiffUI()
				end
			elseif self._diffState and self._diffState.Active then
				-- Children already loaded but we're in diff mode - still need to update UI
				self:_UpdateDiffUI()
			end

			if hasActiveFilters and assoc.ChildrenLoaded then
				for _, childAssoc in pairs(self:_GetChildAssociations(assoc)) do
					if childAssoc.Gui then
						childAssoc.Gui.Visible = true
					end
				end
			end
		else
			-- Collapsing - handle unload delay
			if options.LazyLoadChildren and assoc.ChildrenLoaded and not hasActiveFilters then
				assoc._meta.UnloadThread = task.delay(options.UnloadDelay, function()
					local currentExpanded = assoc._meta.ExpansionState
					if not currentExpanded and assoc.ChildrenLoaded and assoc.Gui then
						self:_UnloadChildrenGuis(assoc)
						assoc.ChildrenLoaded = false
					end
					assoc._meta.UnloadThread = nil
				end)
			end
		end
	end

	if recursive then
		-- Recursive expand/collapse
		local function ProcessRecursive(assoc: Association)
			if typeof(assoc.Value) ~= "table" or assoc.IsRecursive then
				return
			end

			if state then
				-- When expanding recursively, expand this first, then children
				SetSingleExpanded(assoc, true)
				if assoc.ChildrenLoaded then
					for _, childAssoc in pairs(self:_GetChildAssociations(assoc)) do
						ProcessRecursive(childAssoc)
					end
				end
			else
				-- When collapsing recursively, collapse children first, then this
				if assoc.ChildrenLoaded then
					for _, childAssoc in pairs(self:_GetChildAssociations(assoc)) do
						ProcessRecursive(childAssoc)
					end
				end
				SetSingleExpanded(assoc, false)
			end
		end
		ProcessRecursive(association)
	else
		SetSingleExpanded(association, state)
	end

	return true
end

function TableEditor._LoadChildAssociations(
	self: InternalTableEditor,
	parentAssociation: Association,
	skipFilterUpdate: boolean?
)
	if typeof(parentAssociation.Value) ~= "table" then
		return
	end

	local visited = self._tableRefs
	local parentPathString = self:_GetAssociationPathString(parentAssociation)

	-- First pass: Create all associations WITHOUT GUIs
	-- This allows us to build the flat list and determine what's in viewport
	local newAssociations: { Association } = {}

	for key, value in pairs(parentAssociation.Value) do
		local pathString = if parentPathString == "" then tostring(key) else `{parentPathString}.{tostring(key)}`
		local existingAssoc = self._associations[pathString]

		if existingAssoc then
			if existingAssoc.Gui then
				continue
			end
			existingAssoc.Value = value
			existingAssoc._meta.LastValueHash = HashValue(value)
			if not self._childrenIndex[parentAssociation] then
				self._childrenIndex[parentAssociation] = {}
			end
			table.insert(self._childrenIndex[parentAssociation], existingAssoc)
			table.insert(newAssociations, existingAssoc)
			continue
		end

		local childAssociation: Association = {
			Key = key,
			Parent = parentAssociation,
			Depth = parentAssociation.Depth + 1,
			Value = value,
			ChildrenLoaded = false,
			IsGhost = parentAssociation.IsGhost, -- Inherit ghost status from parent
			_meta = {},
		}

		if typeof(value) == "table" then
			local refPath = self:_GetTableRefPath(value, visited)
			if refPath then
				local currentPath = self:_GetAssociationPathString(childAssociation)
				if refPath == currentPath then
					childAssociation.IsRecursive = true
				else
					childAssociation.IsDuplicateRef = true
					childAssociation.DuplicateOfKey = refPath
				end
			else
				visited[value] = self:_GetAssociationPathString(childAssociation)
			end
		end

		childAssociation._meta.LastValueHash = HashValue(value)
		self._associations[pathString] = childAssociation

		if not self._childrenIndex[parentAssociation] then
			self._childrenIndex[parentAssociation] = {}
		end
		table.insert(self._childrenIndex[parentAssociation], childAssociation)
		table.insert(newAssociations, childAssociation)
	end

	-- Create GUIs for all new associations
	for _, childAssociation in newAssociations do
		if not childAssociation.Gui then
			childAssociation.Gui = self:_CreateEntry(childAssociation)
		end
	end

	-- If in diff mode and this is NOT a ghost parent, create ghost entries for removed items
	-- Ghost parents already have their children as ghosts, so we don't need to add more
	if self._diffState and self._diffState.Active and not parentAssociation.IsGhost then
		self:_CreateGhostEntriesForRemovedItems(parentAssociation, parentPathString)
	end

	if not skipFilterUpdate then
		self:_UpdateOrdering()
		if not self._isFiltering then
			self:_UpdateFiltersAndExclusions()
		end
	end
end

--[[
	Internal: Completely rebuilds associations from scratch.
	Used when the same data reference is passed to Update() (in-place mutations).
	This properly handles removals, additions, and changes.
]]
function TableEditor._RebuildAssociations(self: InternalTableEditor)
	table.clear(self._childrenIndex)

	-- Collect all valid paths from current data (use temporary visited table)
	local validPaths: { [string]: boolean } = {}
	local newAssociationsNeedingGui: { Association } = {}

	local function CollectValidPaths(data: Table, parentPath: string, depth: number, tempVisited: { [Table]: boolean })
		if depth > self.Options.MaxRecursionDepth then
			return
		end
		for key, value in pairs(data) do
			local pathString = if parentPath == "" then tostring(key) else `{parentPath}.{tostring(key)}`
			validPaths[pathString] = true
			if typeof(value) == "table" then
				-- Track table refs to avoid infinite loops
				if not tempVisited[value] then
					tempVisited[value] = true
					-- Only recurse into loaded children
					local existingAssoc = self._associations[pathString]
					if not self.Options.LazyLoadChildren or (existingAssoc and existingAssoc.ChildrenLoaded) then
						CollectValidPaths(value, pathString, depth + 1, tempVisited)
					end
				end
			end
		end
	end
	CollectValidPaths(self.Data, "", 0, {})

	-- Remove associations that no longer exist in data
	local toRemove: { string } = {}
	for pathString, assoc in pairs(self._associations) do
		if not validPaths[pathString] and not assoc.IsGhost then
			table.insert(toRemove, pathString)
		end
	end
	for _, pathString in ipairs(toRemove) do
		local assoc = self._associations[pathString]
		if assoc then
			if assoc.Gui then
				self:_ReturnEntryToPool(assoc.Gui)
			end
			self._associations[pathString] = nil
		end
	end

	-- Fresh visited table for recursion detection during build
	local visited: { [Table]: string } = {}
	self._tableRefs = visited

	-- Now rebuild/update remaining associations
	local function BuildAssociations(data: Table, parentAssociation: Association?, depth: number, parentPath: string)
		if depth > self.Options.MaxRecursionDepth then
			return
		end

		for key, value in pairs(data) do
			local pathString = if parentPath == "" then tostring(key) else `{parentPath}.{tostring(key)}`
			local existingAssoc = self._associations[pathString]

			-- Determine recursion/duplicate status
			local isRecursive = false
			local isDuplicateRef = false
			local duplicateOfKey: string? = nil

			if typeof(value) == "table" and self.Options.DetectRecursiveTables then
				local existingPath = visited[value]
				if existingPath then
					if existingPath == pathString then
						isRecursive = true
					elseif self.Options.DetectDuplicateReferences then
						isDuplicateRef = true
						duplicateOfKey = existingPath
					end
				else
					visited[value] = pathString
				end
			end

			local association: Association
			if existingAssoc then
				-- Update existing association
				local oldHash = existingAssoc._meta.LastValueHash
				local newHash = HashValue(value)
				local oldValue = existingAssoc.Value

				-- Check if this value is frozen - if so, keep the frozen value
				local frozenValue = self._frozenValues[pathString]
				if frozenValue ~= nil then
					existingAssoc.Value = frozenValue
				else
					existingAssoc.Value = value
				end

				existingAssoc.Parent = parentAssociation
				existingAssoc.Depth = depth -- Update depth in case hierarchy changed
				existingAssoc._meta.LastValueHash = newHash
				existingAssoc.IsRecursive = isRecursive
				existingAssoc.IsDuplicateRef = isDuplicateRef
				existingAssoc.DuplicateOfKey = duplicateOfKey

				-- Flash if value changed and not frozen
				-- For tables: also check that the change isn't ONLY from frozen descendants
				local shouldFlash = frozenValue == nil and self.Options.FlashOnChange and oldHash ~= newHash
				if shouldFlash and typeof(value) == "table" then
					-- Check if ALL frozen descendants cover all the changes
					-- If this table has frozen descendants, we need to check if there are also non-frozen changes
					local hasFrozenDescendant = false
					local pathPrefix = pathString .. "."
					for frozenPath in pairs(self._frozenValues) do
						if frozenPath:sub(1, #pathPrefix) == pathPrefix then
							hasFrozenDescendant = true
							break
						end
					end
					-- Only skip flash if there are frozen descendants AND no non-frozen children changed
					-- We track this by marking this entry, then later checking if any non-frozen child marked it for flash
					if hasFrozenDescendant then
						existingAssoc._meta.PendingFlashCheck = true
						shouldFlash = false
					end
				end
				if shouldFlash then
					local flashColor: Color3? = nil
					if self.Options.FlashOnDecrement and typeof(value) == "number" and typeof(oldValue) == "number" then
						if value < oldValue then
							flashColor = self.Options.FlashRemovalColor
						end
					end
					self:_FlashEntry(existingAssoc, flashColor)
					-- Mark ancestors for flash since a non-frozen child changed
					local parent = parentAssociation
					while parent do
						if parent._meta.PendingFlashCheck then
							parent._meta.PendingFlashCheck = nil
							self:_FlashEntry(parent)
						end
						parent = parent.Parent
					end
				end

				-- Update InfoBox size to reflect new depth
				if existingAssoc.Gui then
					local infoBox = existingAssoc.Gui:FindFirstChild("InfoBox") :: Frame?
					if infoBox then
						infoBox.Size = UDim2.new(1, -16 * depth, 0, 22)
					end
				end

				self:_UpdateEntryUI(existingAssoc)
				association = existingAssoc
			else
				-- Create new association
				association = {
					Key = key,
					Parent = parentAssociation,
					Depth = depth,
					Value = value,
					ChildrenLoaded = not self.Options.LazyLoadChildren,
					IsRecursive = isRecursive,
					IsDuplicateRef = isDuplicateRef,
					DuplicateOfKey = duplicateOfKey,
					_meta = {},
				}

				association._meta.LastValueHash = HashValue(value)
				self._associations[pathString] = association
				table.insert(newAssociationsNeedingGui, association)
			end

			if parentAssociation then
				if not self._childrenIndex[parentAssociation] then
					self._childrenIndex[parentAssociation] = {}
				end
				table.insert(self._childrenIndex[parentAssociation], association)
			end

			if typeof(value) == "table" and not association.IsRecursive and not association.IsDuplicateRef then
				if not self.Options.LazyLoadChildren or association.ChildrenLoaded then
					association.ChildrenLoaded = true
					BuildAssociations(value, association, depth + 1, pathString)
				end
			end
		end
	end

	BuildAssociations(self.Data, nil, 0, "")

	-- Create GUIs for new associations
	for _, association in newAssociationsNeedingGui do
		if not association.Gui then
			association.Gui = self:_CreateEntry(association)
		end
	end

	self:_UpdateOrdering()
end

function TableEditor._UpdateAssociations(self: InternalTableEditor, lastData: Table?)
	local visited: { [Table]: string } = {}
	self._tableRefs = visited
	table.clear(self._childrenIndex)

	-- Track new associations that need GUIs (created without GUIs first)
	local newAssociationsNeedingGui: { Association } = {}

	local function BuildAssociations(data: Table, parentAssociation: Association?, depth: number, parentPath: string)
		if depth > self.Options.MaxRecursionDepth then
			return
		end

		for key, value in pairs(data) do
			local pathString = if parentPath == "" then tostring(key) else `{parentPath}.{tostring(key)}`
			local association: Association = {
				Key = key,
				Parent = parentAssociation,
				Depth = depth,
				Value = value,
				ChildrenLoaded = not self.Options.LazyLoadChildren,
				_meta = {},
			}

			if typeof(value) == "table" and self.Options.DetectRecursiveTables then
				local existingPath = visited[value]
				if existingPath then
					if existingPath == pathString then
						association.IsRecursive = true
					elseif self.Options.DetectDuplicateReferences then
						association.IsDuplicateRef = true
						association.DuplicateOfKey = existingPath
					end
				else
					visited[value] = pathString
				end
			end

			local existingAssoc = self._associations[pathString]
			if existingAssoc and existingAssoc.Gui then
				local oldHash = existingAssoc._meta.LastValueHash
				local newHash = HashValue(value)

				-- Check if this value is frozen - if so, keep the frozen value
				local frozenValue = self._frozenValues[pathString]
				if frozenValue ~= nil then
					existingAssoc.Value = frozenValue
				else
					existingAssoc.Value = value
				end

				existingAssoc.IsRecursive = association.IsRecursive
				existingAssoc.IsDuplicateRef = association.IsDuplicateRef
				existingAssoc.DuplicateOfKey = association.DuplicateOfKey

				-- Only flash if not frozen and value actually changed
				-- For tables: also check that the change isn't ONLY from frozen descendants
				local shouldFlash = frozenValue == nil
					and self.Options.FlashOnChange
					and lastData
					and oldHash ~= newHash
				if shouldFlash and typeof(value) == "table" then
					local hasFrozenDescendant = false
					local pathPrefix = pathString .. "."
					for frozenPath in pairs(self._frozenValues) do
						if frozenPath:sub(1, #pathPrefix) == pathPrefix then
							hasFrozenDescendant = true
							break
						end
					end
					if hasFrozenDescendant then
						existingAssoc._meta.PendingFlashCheck = true
						shouldFlash = false
					end
				end
				if shouldFlash then
					self:_FlashEntry(existingAssoc)
					-- Mark ancestors for flash since a non-frozen child changed
					local parent = parentAssociation
					while parent do
						if parent._meta.PendingFlashCheck then
							parent._meta.PendingFlashCheck = nil
							self:_FlashEntry(parent)
						end
						parent = parent.Parent
					end
				end
				existingAssoc._meta.LastValueHash = newHash
				self:_UpdateEntryUI(existingAssoc)
				association = existingAssoc

				if parentAssociation then
					if not self._childrenIndex[parentAssociation] then
						self._childrenIndex[parentAssociation] = {}
					end
					table.insert(self._childrenIndex[parentAssociation], association)
				end
			else
				-- Don't create GUI yet - defer until we know what's in viewport
				self._associations[pathString] = association
				association._meta.LastValueHash = HashValue(value)
				table.insert(newAssociationsNeedingGui, association)

				if parentAssociation then
					if not self._childrenIndex[parentAssociation] then
						self._childrenIndex[parentAssociation] = {}
					end
					table.insert(self._childrenIndex[parentAssociation], association)
				end
			end

			if typeof(value) == "table" and not association.IsRecursive and not association.IsDuplicateRef then
				if not self.Options.LazyLoadChildren or association.ChildrenLoaded then
					association.ChildrenLoaded = true
					BuildAssociations(value, association, depth + 1, pathString)
				end
			end
		end
	end

	if lastData then
		local diff = GetDiff(self.Data, lastData)
		self:_ProcessRemovals(diff, "")
	end

	BuildAssociations(self.Data, nil, 0, "")

	-- Create GUIs for associations that need them
	for _, association in newAssociationsNeedingGui do
		if not association.Gui then
			association.Gui = self:_CreateEntry(association)
		end
	end
	self:_UpdateOrdering()
end

function TableEditor._ProcessRemovals(
	self: InternalTableEditor,
	diff: Table,
	parentPath: string,
	visited: { [Table]: boolean }?
)
	local visitedTables = visited or {}
	if visitedTables[diff] then
		return
	end
	visitedTables[diff] = true

	for key, value in pairs(diff) do
		local pathString = if parentPath == "" then tostring(key) else `{parentPath}.{tostring(key)}`
		if value == REMOVAL_KEY then
			local assoc = self._associations[pathString]
			if assoc then
				if assoc.Parent then
					local parentChildren = self._childrenIndex[assoc.Parent]
					if parentChildren then
						for i, child in pairs(parentChildren) do
							if child == assoc then
								table.remove(parentChildren, i)
								break
							end
						end
					end
				end
				self._childrenIndex[assoc] = nil
				if assoc.Gui then
					if self.Options.FlashOnRemoval then
						self:_FlashEntry(assoc, self.Options.FlashRemovalColor)
						task.delay(self.Options.FlashDuration, function()
							if assoc.Gui then
								self:_ReturnEntryToPool(assoc.Gui)
							end
						end)
					else
						self:_ReturnEntryToPool(assoc.Gui)
					end
				end
			end
			self._associations[pathString] = nil
		elseif typeof(value) == "table" then
			self:_ProcessRemovals(value, pathString, visitedTables)
		end
	end
end

function TableEditor._UpdateAssociationsFromPatch(self: InternalTableEditor, patch: Table, parentPath: string)
	for key, value in pairs(patch) do
		local pathString = if parentPath == "" then tostring(key) else `{parentPath}.{tostring(key)}`

		if value == REMOVAL_KEY then
			local assoc = self._associations[pathString]
			if assoc then
				if assoc.Parent then
					local parentChildren = self._childrenIndex[assoc.Parent]
					if parentChildren then
						for i, child in pairs(parentChildren) do
							if child == assoc then
								table.remove(parentChildren, i)
								break
							end
						end
					end
				end
				self._childrenIndex[assoc] = nil
				if assoc.Gui then
					self:_ReturnEntryToPool(assoc.Gui)
				end
				self._associations[pathString] = nil
			end
		elseif typeof(value) == "table" then
			local assoc = self._associations[pathString]
			if assoc then
				self:_UpdateAssociationsFromPatch(value, pathString)
			end
		else
			local assoc = self._associations[pathString]
			if assoc then
				local oldValue = assoc.Value
				self:_UpdateSingleAssociation(pathString, oldValue, value)
			end
		end
	end
	self:_UpdateOrdering()
end

function TableEditor._UpdateSingleAssociation(
	self: InternalTableEditor,
	pathString: string,
	oldValue: any,
	newValue: any
)
	local assoc = self._associations[pathString]
	if not assoc then
		return
	end

	local oldHash = assoc._meta.LastValueHash
	local newHash = HashValue(newValue)

	assoc.Value = newValue
	assoc._meta.LastValueHash = newHash
	assoc._meta.CachedSortKey = nil
	assoc._meta.CachedChildCount = nil

	if self.Options.FlashOnChange and oldHash ~= newHash then
		local flashColor: Color3? = nil
		if self.Options.FlashOnDecrement and typeof(newValue) == "number" and typeof(oldValue) == "number" then
			if newValue < oldValue then
				flashColor = self.Options.FlashRemovalColor
			end
		end
		self:_FlashEntry(assoc, flashColor)
	end

	self:_UpdateEntryUI(assoc)
end

function TableEditor._UpdateFiltersAndExclusions(self: InternalTableEditor, rootOverride: { Association }?)
	local function MatchesKeyFilter(key: string): boolean
		local filters = self._keyFilters
		if not filters[1] then
			return true
		end

		local keyOpts = self._filterOptions.Key
		local caseSensitive = if keyOpts then keyOpts.CaseSensitive else self.Options.CaseSensitive
		local fuzzyMatch = if keyOpts then keyOpts.FuzzyMatch else self.Options.FuzzyMatching
		local testKey = if caseSensitive then key else key:lower()

		for _, filter in pairs(filters) do
			if fuzzyMatch then
				if FuzzyMatch(filter, testKey, self.Options.FuzzyThreshold) then
					return true
				end
			else
				if testKey:find(filter, 1, true) then
					return true
				end
			end
		end

		return false
	end

	local function MatchesValueFilter(valueStr: string): boolean
		local filters = self._valueFilters
		if not filters[1] then
			return true
		end

		local valOpts = self._filterOptions.Value
		local caseSensitive = if valOpts then valOpts.CaseSensitive else self.Options.CaseSensitive
		local fuzzyMatch = if valOpts then valOpts.FuzzyMatch else self.Options.FuzzyMatching
		local testValue = if caseSensitive then valueStr else valueStr:lower()

		for _, filter in pairs(filters) do
			if fuzzyMatch then
				if FuzzyMatch(filter, testValue, self.Options.FuzzyThreshold) then
					return true
				end
			else
				if testValue:find(filter, 1, true) then
					return true
				end
			end
		end

		return false
	end

	-- Recursively check if a table contains any value matching the filter (for deep value search)
	local function TableContainsMatchingValue(tbl: Table, visitedTables: { [Table]: boolean }?): boolean
		local filters = self._valueFilters
		if not filters[1] then
			return true
		end

		local visited = visitedTables or {}
		if visited[tbl] then
			return false
		end
		visited[tbl] = true

		local valOpts = self._filterOptions.Value
		local caseSensitive = if valOpts then valOpts.CaseSensitive else self.Options.CaseSensitive
		local fuzzyMatch = if valOpts then valOpts.FuzzyMatch else self.Options.FuzzyMatching

		for _, value in pairs(tbl) do
			if typeof(value) == "table" then
				if TableContainsMatchingValue(value, visited) then
					return true
				end
			else
				local valueStr = tostring(value)
				local testValue = if caseSensitive then valueStr else valueStr:lower()

				for _, filter in pairs(filters) do
					if fuzzyMatch then
						if FuzzyMatch(filter, testValue, self.Options.FuzzyThreshold) then
							return true
						end
					else
						if testValue:find(filter, 1, true) then
							return true
						end
					end
				end
			end
		end

		return false
	end

	-- Recursively check if a table contains any key matching the filter (for deep key search)
	local function TableContainsMatchingKey(tbl: Table, visitedTables: { [Table]: boolean }?): boolean
		local filters = self._keyFilters
		if not filters[1] then
			return true
		end

		local visited = visitedTables or {}
		if visited[tbl] then
			return false
		end
		visited[tbl] = true

		local keyOpts = self._filterOptions.Key
		local caseSensitive = if keyOpts then keyOpts.CaseSensitive else self.Options.CaseSensitive
		local fuzzyMatch = if keyOpts then keyOpts.FuzzyMatch else self.Options.FuzzyMatching

		for key, value in pairs(tbl) do
			local keyStr = tostring(key)
			local testKey = if caseSensitive then keyStr else keyStr:lower()

			for _, filter in pairs(filters) do
				if fuzzyMatch then
					if FuzzyMatch(filter, testKey, self.Options.FuzzyThreshold) then
						return true
					end
				else
					if testKey:find(filter, 1, true) then
						return true
					end
				end
			end

			if typeof(value) == "table" then
				if TableContainsMatchingKey(value, visited) then
					return true
				end
			end
		end

		return false
	end

	local function IsTypeIncluded(valueType: string): boolean
		local typeFilters = self._typeFilters
		if not typeFilters[1] then
			return true
		end

		for _, typeFilter in pairs(typeFilters) do
			if MatchesTypeExclusion(valueType, typeFilter) then
				return true
			end
		end

		return false
	end

	local function IsTypeExcluded(valueType: string): boolean
		local exclusions = self._typeExclusions
		if not exclusions[1] then
			return false
		end

		for _, exclusion in pairs(exclusions) do
			if MatchesTypeExclusion(valueType, exclusion) then
				return true
			end
		end

		return false
	end

	local function ProcessAssociation(
		association: Association,
		visited: { [Association]: boolean }?,
		ancestorIsDirectMatch: boolean?
	)
		local seen = visited or {}
		if seen[association] then
			return
		end
		seen[association] = true

		if not association.Gui then
			return
		end

		association._meta.FilterModeExpansionState = nil

		local keyStr = self:_FormatFieldKey(association.Key)
		local valueStr = self:_FormatFieldValue(association.Value, association)
		local valueType = typeof(association.Value)

		local keyMatches = MatchesKeyFilter(keyStr)
		local valueMatches = MatchesValueFilter(valueStr)
		local typeIncluded = IsTypeIncluded(valueType)
		local typeExcluded = IsTypeExcluded(valueType)

		local hasKeyFilters = self._keyFilters[1] ~= nil
		local hasValueFilters = self._valueFilters[1] ~= nil
		local hasTypeFilters = self._typeFilters[1] ~= nil
		local hasAnyFilter = hasKeyFilters or hasValueFilters or hasTypeFilters

		local isTable = typeof(association.Value) == "table"
		local canDeepSearch = isTable and not association.IsRecursive and not association.IsDuplicateRef

		-- Determine if this item directly matches the filter
		-- When both key and value filters are set:
		--   "and" mode (B): must match BOTH key AND value
		--   "or" mode (E): must match EITHER key OR value
		-- When only one filter type is set, it just needs to match that filter
		local directKeyMatch = not hasKeyFilters or keyMatches
		local directValueMatch = not hasValueFilters or valueMatches
		local directTypeMatch = not hasTypeFilters or typeIncluded

		-- Check the filter combine mode when both filters are set
		local hasBothFilters = hasKeyFilters and hasValueFilters
		local isEitherMode = hasBothFilters and self._filterCombineMode == "or"
		local directMatch: boolean
		if isEitherMode then
			-- In "either" mode (E): match if key OR value matches (and type matches)
			directMatch = (keyMatches or valueMatches) and directTypeMatch
		else
			-- "both" mode (B) or single filter: standard AND logic
			directMatch = directKeyMatch and directValueMatch and directTypeMatch
		end

		-- For tables, also check if any descendant matches
		local hasMatchingDescendants = false
		if canDeepSearch and not directMatch and not ancestorIsDirectMatch then
			local descendantKeyMatch = not hasKeyFilters or TableContainsMatchingKey(association.Value)
			local descendantValueMatch = not hasValueFilters or TableContainsMatchingValue(association.Value)
			if isEitherMode then
				-- In "either" mode: match if descendants have key OR value match
				hasMatchingDescendants = (descendantKeyMatch or descendantValueMatch) and directTypeMatch
			else
				hasMatchingDescendants = descendantKeyMatch and descendantValueMatch and directTypeMatch
			end
		end

		-- Should this item be visible?
		-- If an ancestor is a direct match, this item should be visible (to show contents of matching table)
		local shouldBeVisible = directMatch or hasMatchingDescendants or (ancestorIsDirectMatch == true)

		-- Only mark as KeyFiltered if it's a DIRECT match (for highlighting)
		-- This is set for items that themselves match, not just their parents/descendants
		association._meta.KeyFiltered = directMatch or nil

		if typeExcluded then
			association.Gui.Visible = false
			association._meta.KeyFiltered = nil
		elseif hasAnyFilter then
			if isTable then
				-- Tables: show if direct match OR has matching descendants OR ancestor was direct match
				local isVisible = shouldBeVisible == true
				association.Gui.Visible = isVisible
				if shouldBeVisible then
					if
						not association.ChildrenLoaded
						and not association.IsRecursive
						and not association.IsDuplicateRef
					then
						association.ChildrenLoaded = true
						self:_LoadChildAssociations(association, true)
					end
				end
			else
				-- Non-tables: show if direct match OR ancestor was direct match (to show contents)
				local isVisible = directMatch or (ancestorIsDirectMatch == true)
				association.Gui.Visible = isVisible
			end
		elseif self._typeExclusions[1] and isTable then
			if not association.ChildrenLoaded and not association.IsRecursive and not association.IsDuplicateRef then
				association.ChildrenLoaded = true
				self:_LoadChildAssociations(association, true)
			end
			association.Gui.Visible = true
		else
			association.Gui.Visible = true
		end

		-- Process children recursively
		-- Pass down whether this item or an ancestor is a direct match
		if association.ChildrenLoaded and isTable and not association.IsRecursive then
			local passDownDirectMatch = directMatch or ancestorIsDirectMatch
			for _, child in pairs(self:_GetChildAssociations(association)) do
				ProcessAssociation(child, seen, passDownDirectMatch)
			end
		end
	end

	local function AtLeastOneVisible(association: Association, visited: { [Association]: boolean }?): boolean
		local seen = visited or {}
		if seen[association] then
			return false
		end
		seen[association] = true

		if not association.Gui then
			return false
		end

		if typeof(association.Value) ~= "table" then
			return association.Gui.Visible
		end

		if association.ChildrenLoaded then
			for _, child in pairs(self:_GetChildAssociations(association)) do
				if child.Gui and child.Gui.Visible then
					-- If this child is a direct match (KeyFiltered), count it as visible
					-- regardless of whether it has visible children
					if child._meta.KeyFiltered then
						return true
					end
					if typeof(child.Value) == "table" then
						-- Recursively check nested tables with visited tracking
						if AtLeastOneVisible(child, seen) then
							return true
						end
					else
						return true
					end
				end
			end
			return false
		end

		if self._typeExclusions[1] then
			local hasNonExcludedChild = false
			for _, value in pairs(association.Value) do
				if not IsTypeExcluded(typeof(value)) then
					hasNonExcludedChild = true
					break
				end
			end
			return hasNonExcludedChild
		end

		-- Fallback: if no children loaded yet, check if this table directly matched
		-- or if there are no active filters
		local hasAnyFilter = self._keyFilters[1] ~= nil or self._valueFilters[1] ~= nil or self._typeFilters[1] ~= nil
		return association._meta.KeyFiltered == true or not hasAnyFilter
	end

	local function HideEmptyTables(association: Association, visited: { [Association]: boolean }?)
		local seen = visited or {}
		if seen[association] then
			return
		end
		seen[association] = true

		if not association.Gui or association._meta.KeyFiltered then
			return
		end

		if association.IsRecursive then
			return
		end

		if typeof(association.Value) == "table" then
			if not AtLeastOneVisible(association) then
				association.Gui.Visible = false
			end

			if association.ChildrenLoaded then
				for _, child in pairs(self:_GetChildAssociations(association)) do
					HideEmptyTables(child, seen)
				end
			end
		end
	end

	local function HasFilteredDescendant(association: Association, visited: { [Association]: boolean }?): boolean
		local seen = visited or {}
		if seen[association] then
			return false
		end
		seen[association] = true

		if not association.ChildrenLoaded then
			return false
		end

		for _, child in pairs(self:_GetChildAssociations(association)) do
			if child._meta.KeyFiltered then
				return true
			end
			if typeof(child.Value) == "table" and HasFilteredDescendant(child, seen) then
				return true
			end
		end

		return false
	end

	local function ExpandVisibleTables(association: Association, visited: { [Association]: boolean }?)
		local seen = visited or {}
		if seen[association] then
			return
		end
		seen[association] = true

		if not association.Gui or not association.Gui.Visible then
			return
		end

		if association.IsRecursive then
			return
		end

		if typeof(association.Value) == "table" and association.Gui:FindFirstChild("Children") then
			local childrenFrame = association.Gui.Children
			if HasFilteredDescendant(association) then
				childrenFrame.Visible = true
				association._meta.FilterModeExpansionState = true
				local infoBox = association.Gui:FindFirstChild("InfoBox")
				if infoBox then
					local expBtn = infoBox:FindFirstChild("ExpansionButton")
					if expBtn then
						local icon = expBtn:FindFirstChild("Icon") :: ImageLabel?
						if icon then
							icon.Rotation = 90
						end
					end
				end

				if association.ChildrenLoaded then
					for _, child in pairs(self:_GetChildAssociations(association)) do
						ExpandVisibleTables(child, seen)
					end
				end
			else
				childrenFrame.Visible = false
				association._meta.FilterModeExpansionState = false
				local infoBox = association.Gui:FindFirstChild("InfoBox")
				if infoBox then
					local expBtn = infoBox:FindFirstChild("ExpansionButton")
					if expBtn then
						local icon = expBtn:FindFirstChild("Icon") :: ImageLabel?
						if icon then
							icon.Rotation = 0
						end
					end
				end
			end
		end
	end

	local function ApplyExpansionState(association: Association, state: boolean)
		if not association.Gui then
			return
		end

		local childrenFrame = association.Gui:FindFirstChild("Children") :: Frame?
		if childrenFrame then
			childrenFrame.Visible = state
		end

		local infoBox = association.Gui:FindFirstChild("InfoBox")
		if infoBox then
			local expBtn = infoBox:FindFirstChild("ExpansionButton")
			if expBtn then
				local icon = expBtn:FindFirstChild("Icon") :: ImageLabel?
				if icon then
					icon.Rotation = if state then 90 else 0
				end
			end
		end
	end

	local function RestoreNormalExpansionState(association: Association, visited: { [Association]: boolean }?)
		local seen = visited or {}
		if seen[association] then
			return
		end
		seen[association] = true

		if not association.Gui then
			return
		end

		association._meta.KeyFiltered = nil
		association._meta.FilterModeExpansionState = nil
		association.Gui.Visible = true
		if association.IsRecursive then
			return
		end

		if typeof(association.Value) == "table" and association.Gui:FindFirstChild("Children") then
			local normalState: boolean = if association._meta.ExpansionState ~= nil
				then association._meta.ExpansionState
				else (self.Options.Expanded or false)
			ApplyExpansionState(association, normalState)
			if association.ChildrenLoaded then
				for _, child in pairs(self:_GetChildAssociations(association)) do
					RestoreNormalExpansionState(child, seen)
				end
			end
		end
	end

	local function ApplyFilterModeExpansionState(association: Association, visited: { [Association]: boolean }?)
		local seen = visited or {}
		if seen[association] then
			return
		end
		seen[association] = true

		if not association.Gui or not association.Gui.Visible then
			return
		end

		if association.IsRecursive then
			return
		end

		if typeof(association.Value) == "table" and association.Gui:FindFirstChild("Children") then
			local filterState = association._meta.FilterModeExpansionState
			if filterState ~= nil then
				ApplyExpansionState(association, filterState)
			end

			if association.ChildrenLoaded then
				for _, child in pairs(self:_GetChildAssociations(association)) do
					ApplyFilterModeExpansionState(child, seen)
				end
			end
		end
	end

	local toProcess: { Association }
	if rootOverride then
		toProcess = rootOverride
	else
		toProcess = {}
		for _, assoc in pairs(self._associations) do
			if typeof(assoc) == "table" and not assoc.Parent then
				table.insert(toProcess, assoc)
			end
		end
	end

	local hasKeyFilters = self._keyFilters[1] ~= nil
	local hasValueFilters = self._valueFilters[1] ~= nil
	local hasTypeFilters = self._typeFilters[1] ~= nil
	local hasTypeExclusions = self._typeExclusions[1] ~= nil
	local hasAnyFilter = hasKeyFilters or hasValueFilters or hasTypeFilters or hasTypeExclusions

	if hasAnyFilter then
		-- Clear flashed tracking for new filter application
		if self._flashedAssociations then
			table.clear(self._flashedAssociations)
		end

		-- Process all root associations (this recursively loads and processes children)
		-- Note: TableContainsMatchingKey/Value search raw table data, not associations,
		-- so all matches are found regardless of lazy loading state. The recursive
		-- ProcessAssociation calls will load GUIs for any tables with matching descendants.
		for _, assoc in pairs(toProcess) do
			ProcessAssociation(assoc)
		end

		-- Count all matches (KeyFiltered items)
		local matchCount = 0
		for _pathStr, assoc in pairs(self._associations) do
			if typeof(assoc) == "table" and assoc._meta.KeyFiltered then
				matchCount += 1
			end
		end
		self._filterMatchCount = matchCount

		for _, assoc in pairs(toProcess) do
			HideEmptyTables(assoc)
		end
		if hasKeyFilters or hasValueFilters or hasTypeFilters then
			for _, assoc in pairs(toProcess) do
				ExpandVisibleTables(assoc)
			end

			-- Reset ordering before applying float logic to prevent cumulative offset
			self:_UpdateOrdering()

			if self.Options.FloatRelevantResults then
				local floatCount = 0
				local maxFloat = self.Options.MaxFloatResults
				for _pathStr, assoc in pairs(self._associations) do
					if typeof(assoc) == "table" and assoc.Gui and assoc._meta.KeyFiltered then
						if floatCount < maxFloat then
							assoc.Gui.LayoutOrder = assoc.Gui.LayoutOrder - 10000000
							floatCount += 1
						end
					end
				end
			end
			if self.Options.FlashNestedResults then
				local nestedFlashColor = self.Options.FlashSearchNestedColor
				local rootFlashColor = self.Options.FlashSearchRootColor
				for _pathStr, assoc in pairs(self._associations) do
					if typeof(assoc) == "table" and assoc.Gui and assoc._meta.KeyFiltered then
						if assoc.Depth > 0 then
							self._pendingSearchFlashes[assoc] = nestedFlashColor
						else
							self._pendingSearchFlashes[assoc] = rootFlashColor
						end
					end
				end
				-- Defer initial flash processing to next frame so layout has updated
				task.defer(function()
					self:_ProcessPendingSearchFlashes()
				end)
			end

			for _, assoc in pairs(toProcess) do
				ApplyFilterModeExpansionState(assoc)
			end
		end
	else
		self._filterMatchCount = 0
		for _, assoc in pairs(toProcess) do
			RestoreNormalExpansionState(assoc)
		end
		self:_ClearPendingSearchFlashes()
		self:_UpdateOrdering()
	end

	local ui = self._ui
	if ui and self.Options.Editable then
		local viewer = ui:FindFirstChild("Viewer")
		local scrollingFrame = if viewer then viewer:FindFirstChild("Table") else nil

		if scrollingFrame then
			local isFiltering = self._keyFilters[1] ~= nil
				or self._valueFilters[1] ~= nil
				or self._typeFilters[1] ~= nil
			local isExcluding = self._typeExclusions[1] ~= nil
			local showAddRows = true
			if isFiltering and not self.Options.ShowAddRowsWhileFiltering then
				showAddRows = false
			end
			if isExcluding and not self.Options.ShowAddRowsWhileExcluding then
				showAddRows = false
			end

			local rootGhostRow = scrollingFrame:FindFirstChild("RootGhostRow") :: Frame?
			if rootGhostRow then
				rootGhostRow.Visible = showAddRows
			end

			local function UpdateNestedGhostRows(parent: Instance)
				for _, child in pairs(parent:GetChildren()) do
					if child.Name == "GhostRow" then
						(child :: Frame).Visible = showAddRows
					elseif child:IsA("Frame") then
						UpdateNestedGhostRows(child)
					end
				end
			end
			UpdateNestedGhostRows(scrollingFrame)
		end
	end

	-- Update match count label in footer
	if ui then
		local footer = ui:FindFirstChild("Footer") :: Frame?
		if footer then
			local matchCountLabel = FindFooterChild(footer, "MatchCountLabel") :: TextLabel?
			if matchCountLabel then
				if hasAnyFilter and self._filterMatchCount > 0 then
					matchCountLabel.Text =
						`{self._filterMatchCount} match{if self._filterMatchCount == 1 then "" else "es"}`
					matchCountLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
				elseif hasAnyFilter then
					matchCountLabel.Text = "0 matches"
					matchCountLabel.TextColor3 = Color3.fromRGB(200, 100, 100)
				else
					matchCountLabel.Text = ""
				end
			end
		end
	end
end

function TableEditor._UpdateOrdering(self: InternalTableEditor)
	local sortMode = self.Options.SortMode

	local function GetSortKey(association: Association): number
		local currentValueType = typeof(association.Value)

		if
			association._meta.CachedSortKey ~= nil
			and association._meta.LastValueType == currentValueType
			and association._meta.LastSortMode == sortMode
			and not self.Options.OrderTablesBasedOffNumberOfElements
		then
			return association._meta.CachedSortKey
		end

		if sortMode == "none" then
			association._meta.CachedSortKey = 0
			association._meta.LastValueType = currentValueType
			association._meta.LastSortMode = sortMode
			return 0
		end

		local typeOrder = self.Options.TypeOrdering[currentValueType] or self.Options.TypeOrdering.Other

		local keyOrder = 0
		if typeof(association.Key) == "number" then
			keyOrder = association.Key
		else
			local keyStr = tostring(association.Key):lower()
			for i = 1, math.min(#keyStr, 3) do
				keyOrder = keyOrder * 96 + (keyStr:byte(i) - 32)
			end
		end

		local baseOrder: number

		if typeof(association.Key) == "number" then
			baseOrder = keyOrder
		elseif sortMode == "type-then-alpha" then
			baseOrder = typeOrder * 1000000 + keyOrder
		elseif sortMode == "alpha-only" then
			baseOrder = keyOrder
		elseif sortMode == "type-only" then
			baseOrder = typeOrder * 1000000
		else
			baseOrder = typeOrder * 1000000 + keyOrder
		end

		if self.Options.OrderTablesBasedOffNumberOfElements and currentValueType == "table" then
			local childCount = association._meta.CachedChildCount
			if childCount == nil then
				childCount = GetN(association.Value)
				association._meta.CachedChildCount = childCount
			end
			baseOrder = baseOrder + (childCount :: number) * 100
		end

		association._meta.CachedSortKey = baseOrder
		association._meta.LastValueType = currentValueType
		association._meta.LastSortMode = sortMode
		return baseOrder
	end

	for _, assoc in pairs(self._associations) do
		if typeof(assoc) == "table" and assoc.Gui then
			assoc.Gui.LayoutOrder = GetSortKey(assoc)
		end
	end
end

--[[
	Refreshes all entry UIs to reflect current options (e.g., color changes).
]]
function TableEditor._RefreshAllEntryUIs(self: InternalTableEditor)
	for _, assoc in pairs(self._associations) do
		if assoc and assoc.Gui then
			self:_UpdateEntryUI(assoc)
		end
	end

	-- Also refresh child viewers with updated settings
	for _, childViewer in pairs(self._childViewers) do
		if childViewer._ui then
			childViewer.Options.VerboseKeys = self.Options.VerboseKeys
			childViewer.Options.VerboseValues = self.Options.VerboseValues
			childViewer.Options.VerboseKeyTypes = self.Options.VerboseKeyTypes
			childViewer.Options.VerboseValueTypes = self.Options.VerboseValueTypes
			childViewer:_RefreshAllEntryUIs()
		end
	end

	-- Also refresh snapshots with updated settings
	for _, snapshot in pairs(self._snapshots) do
		if snapshot._ui then
			snapshot.Options.VerboseKeys = self.Options.VerboseKeys
			snapshot.Options.VerboseValues = self.Options.VerboseValues
			snapshot.Options.VerboseKeyTypes = self.Options.VerboseKeyTypes
			snapshot.Options.VerboseValueTypes = self.Options.VerboseValueTypes
			snapshot:_RefreshAllEntryUIs()
		end
	end
end

--[[
	Updates the editable state of all TextBoxes based on Options.Editable.
	Also manages delete buttons and ghost rows dynamically.
]]
function TableEditor._UpdateEditableState(self: InternalTableEditor)
	local editable = self.Options.Editable

	for _, assoc in pairs(self._associations) do
		if typeof(assoc) == "table" and assoc.Gui then
			local infoBox = assoc.Gui:FindFirstChild("InfoBox") :: Frame?
			if infoBox then
				local contentRow = infoBox:FindFirstChild("ContentRow") :: Frame?
				if contentRow then
					local fieldKey = contentRow:FindFirstChild("FieldKey") :: TextBox?
					local fieldValue = contentRow:FindFirstChild("FieldValue") :: TextBox?

					if fieldKey then
						fieldKey.TextEditable = editable
					end

					if fieldValue then
						-- Value editability depends on Editable AND the value type
						local canEditValue = editable
							and typeof(assoc.Value) ~= "table"
							and typeof(assoc.Value) ~= "function"
							and not assoc.IsRecursive
							and not assoc.IsDuplicateRef
						fieldValue.TextEditable = canEditValue
					end

					-- Handle delete button visibility (it's inside contentRow)
					local deleteBtn = contentRow:FindFirstChild("DeleteRowButton") :: ImageButton?
					if deleteBtn then
						-- Delete button is always visible when Editable, hidden when not
						deleteBtn:SetAttribute("CanShow", editable)
						deleteBtn.Visible = editable
					end
				end
			end

			-- Handle ghost rows in children containers
			local children = assoc.Gui:FindFirstChild("Children") :: Frame?
			if children then
				local ghostRow = children:FindFirstChild("GhostRow") :: Frame?
				if ghostRow then
					ghostRow.Visible = editable
				end
			end
		end
	end

	-- Handle root ghost row visibility
	if self._ui then
		local viewer = self._ui:FindFirstChild("Viewer") :: Frame?
		if viewer then
			local tableScroll = viewer:FindFirstChild("Table") :: ScrollingFrame?
			if tableScroll then
				local rootGhostRow = tableScroll:FindFirstChild("RootGhostRow") :: Frame?
				if rootGhostRow then
					rootGhostRow.Visible = editable
				end
			end
		end
	end
end

function TableEditor._UpdateEntryUI(self: InternalTableEditor, association: Association)
	if not association.Gui then
		return
	end

	local gui = association.Gui
	local infoBox = gui:FindFirstChild("InfoBox") :: Frame?
	if not infoBox then
		return
	end

	local contentRow = infoBox:FindFirstChild("ContentRow") :: Frame?
	if not contentRow then
		return
	end

	local fieldValue = contentRow:FindFirstChild("FieldValue") :: TextBox?
	local fieldKey = contentRow:FindFirstChild("FieldKey") :: TextBox?

	-- Clear cached child count so it's recalculated from current data
	association._meta.CachedChildCount = nil

	if fieldValue then
		fieldValue.Text = self:_FormatFieldValue(association.Value, association)
		fieldValue.TextColor3 = self:_GetValueColor(association)
	end

	if fieldKey then
		fieldKey.Text = self:_FormatFieldKey(association.Key)
		fieldKey.TextColor3 = if typeof(association.Key) == "number"
			then self.Options.SyntaxHighlighting.Other
			else self.Options.SyntaxHighlighting.Default
	end
end

function TableEditor._FlashEntry(self: InternalTableEditor, association: Association, color: Color3?)
	if not association.Gui then
		return
	end

	local infoBox = association.Gui:FindFirstChild("InfoBox") :: Frame?
	if not infoBox then
		return
	end

	local flash = infoBox:FindFirstChild("ChangeFlash") :: Frame?
	if not flash then
		return
	end

	local now = tick()
	local lastChange = association._meta.LastChangeTime or 0
	local timeSinceLastChange = now - lastChange
	association._meta.LastChangeTime = now

	local intensity = math.clamp(1 - (timeSinceLastChange / 2), 0.3, 0.8)
	flash.BackgroundColor3 = color or self.Options.FlashColor
	flash.BackgroundTransparency = 1 - intensity

	local tween = TweenService:Create(
		flash,
		TweenInfo.new(self.Options.FlashDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
end

function TableEditor._HighlightSearchResult(self: InternalTableEditor, result: SearchResult)
	local association = result.Association :: Association
	if not association then
		return
	end

	-- Expand parents
	local current = association.Parent
	while current do
		if typeof(current.Value) == "table" and not current.IsRecursive then
			self:_SetAssociationExpanded(current, true, false)
		end
		current = current.Parent
	end

	if association.Gui then
		self:ScrollToPath(result.Path)
		local infoBox = association.Gui:FindFirstChild("InfoBox") :: Frame?
		if infoBox then
			local highlight = infoBox:FindFirstChild("SearchHighlight") :: Frame?
			if not highlight then
				local newHighlight = Instance.new("Frame")
				newHighlight.Name = "SearchHighlight"
				newHighlight.Size = UDim2.fromScale(1, 1)
				newHighlight.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
				newHighlight.BackgroundTransparency = TRANSPARENCY.SearchHighlight
				newHighlight.BorderSizePixel = 0
				newHighlight.ZIndex = 0
				newHighlight.Parent = infoBox
				newHighlight.Visible = true
			else
				highlight.Visible = true
			end
		end
		self._searchState.HighlightedAssociation = association
	end
end

function TableEditor._ClearSearchHighlight(self: InternalTableEditor)
	local association = self._searchState.HighlightedAssociation
	if association and association.Gui then
		local infoBox = association.Gui:FindFirstChild("InfoBox") :: Frame?
		if infoBox then
			local highlight = infoBox:FindFirstChild("SearchHighlight") :: Frame?
			if highlight then
				highlight.Visible = false
			end
		end
	end
	self._searchState.HighlightedAssociation = nil
end

function TableEditor._ProcessPendingSearchFlashes(self: InternalTableEditor)
	if not self._pendingSearchFlashes then
		return
	end

	local toRemove: { Association } = {}
	for association, color in pairs(self._pendingSearchFlashes) do
		if not association.Gui or not association._meta.KeyFiltered then
			table.insert(toRemove, association)
		elseif not self._keyFilters[1] and not self._valueFilters[1] then
			table.insert(toRemove, association)
		elseif self._flashedAssociations[association] then
			-- Already flashed, just remove from pending
			table.insert(toRemove, association)
		elseif self:_IsEntryInView(association) then
			self:_FlashEntryMultiple(association, color, 3)
			self._flashedAssociations[association] = true
			table.insert(toRemove, association)
		end
	end

	for _, association in pairs(toRemove) do
		self._pendingSearchFlashes[association] = nil
	end
end

function TableEditor._IsEntryInView(self: InternalTableEditor, association: Association): boolean
	if not self._ui or not association.Gui then
		return false
	end
	local scrollFrame = self._ui.Viewer.Table
	local infoBox = association.Gui:FindFirstChild("InfoBox") :: Frame?
	if not infoBox then
		return false
	end
	local scrollTop = scrollFrame.AbsolutePosition.Y
	local scrollBottom = scrollTop + scrollFrame.AbsoluteSize.Y
	local infoTop = infoBox.AbsolutePosition.Y
	local infoBottom = infoTop + infoBox.AbsoluteSize.Y
	return infoBottom > scrollTop and infoTop < scrollBottom
end

function TableEditor._ReturnEntryToPool(self: InternalTableEditor, entry: Frame)
	self:_CancelEntryTooltipThreads(entry)
	local children = entry:FindFirstChild("Children") :: Frame?
	if children then
		for _, child in pairs(children:GetChildren()) do
			if child:IsA("Frame") and child.Name ~= "ListLayout" then
				self:_ReturnEntryToPool(child)
			end
		end
	end
	entry:Destroy()
end

function TableEditor._CancelEntryTooltipThreads(self: InternalTableEditor, entry: Frame)
	local assoc = self._guiToAssociation[entry]
	if assoc then
		if assoc._meta.TooltipThreads then
			for _, thread in pairs(assoc._meta.TooltipThreads) do
				task.cancel(thread)
			end
			table.clear(assoc._meta.TooltipThreads)
		end
		if assoc._meta.UnloadThread then
			task.cancel(assoc._meta.UnloadThread)
			assoc._meta.UnloadThread = nil
		end
		self._guiToAssociation[entry] = nil
	end
end

function TableEditor._ClearPendingSearchFlashes(self: InternalTableEditor)
	if self._pendingSearchFlashes then
		table.clear(self._pendingSearchFlashes)
	end
	if self._flashedAssociations then
		table.clear(self._flashedAssociations)
	end
end

function TableEditor._FlashEntryMultiple(
	self: InternalTableEditor,
	association: Association,
	color: Color3?,
	times: number?
)
	if association._meta.Flashing then
		return
	end

	local flashCount = times or 3
	local flashDuration = self.Options.FlashDuration
	association._meta.Flashing = true
	self:_FlashEntry(association, color)
	if flashCount == 1 then
		association._meta.Flashing = nil
		return
	end

	for i = 2, flashCount do
		task.delay(flashDuration * (i - 1), function()
			if association.Gui and association._meta.KeyFiltered and self._keyFilters[1] then
				self:_FlashEntry(association, color)
			end
			if i == flashCount then
				association._meta.Flashing = nil
			end
		end)
	end
end

function TableEditor._QueueSearchFlash(self: InternalTableEditor, association: Association, color: Color3)
	if not association.Gui then
		return
	end

	-- Skip if already flashed in this filter session
	if self._flashedAssociations[association] then
		return
	end

	if self:_IsEntryInView(association) then
		self:_FlashEntryMultiple(association, color, 3)
		self._flashedAssociations[association] = true
	else
		self._pendingSearchFlashes[association] = color
	end
end

function TableEditor._UnloadChildrenGuis(self: InternalTableEditor, association: Association)
	local children = self._childrenIndex[association]
	if not children then
		return
	end

	for _, childAssoc in pairs(children) do
		if childAssoc.ChildrenLoaded then
			self:_UnloadChildrenGuis(childAssoc)
		end
		if typeof(childAssoc.Value) == "table" then
			self._tableRefs[childAssoc.Value] = nil
		end
		if childAssoc.Gui then
			self:_ReturnEntryToPool(childAssoc.Gui)
			childAssoc.Gui = nil
		end
		childAssoc.ChildrenLoaded = false
		childAssoc._meta.CachedSortKey = nil
	end
	self._childrenIndex[association] = nil
	association.ChildrenLoaded = false
end

function TableEditor._DestroyEntryRecursive(self: InternalTableEditor, entry: Frame)
	local children = entry:FindFirstChild("Children") :: Frame?
	if children then
		for _, child in pairs(children:GetChildren()) do
			if child:IsA("Frame") and child.Name ~= "ListLayout" then
				self:_DestroyEntryRecursive(child)
			end
		end
	end

	self:_ReturnEntryToPool(entry)
end

function TableEditor._CreateOptionsMenu(self: InternalTableEditor, menu: Frame)
	local options = self.Options
	local fontFace = options.KeyFontFace

	-- Create scrolling container for the menu content
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ScrollContent"
	scrollFrame.Size = UDim2.new(1, 0, 1, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	scrollFrame.CanvasSize = UDim2.new(1, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = menu

	local scrollPadding = CreatePadding(4, 4, 4, 4)
	scrollPadding.Parent = scrollFrame

	local mainLayout = Instance.new("UIListLayout")
	mainLayout.FillDirection = Enum.FillDirection.Vertical
	mainLayout.Padding = UDim.new(0, 4)
	mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mainLayout.Parent = scrollFrame

	-- === General Settings Section ===
	local generalContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "General", "General", true, fontFace, 1)

	SettingsMenuHelper.CreateToggle(
		generalContent,
		"AutoSize",
		"Auto-size",
		options.AutoSizeToContent,
		fontFace,
		function(state)
			self.Options.AutoSizeToContent = state
			if state then
				self:AutoSize()
			end
		end
	)

	SettingsMenuHelper.CreateToggle(
		generalContent,
		"LazyLoad",
		"Lazy Load",
		options.LazyLoadChildren,
		fontFace,
		function(state)
			self.Options.LazyLoadChildren = state
		end
	)

	SettingsMenuHelper.CreateToggle(
		generalContent,
		"FuzzyMatch",
		"Fuzzy Search",
		options.FuzzyMatching,
		fontFace,
		function(state)
			self.Options.FuzzyMatching = state
			self:_UpdateFiltersAndExclusions()
		end
	)

	SettingsMenuHelper.CreateToggle(
		generalContent,
		"FloatResults",
		"Float Relevant",
		options.FloatRelevantResults,
		fontFace,
		function(state)
			self.Options.FloatRelevantResults = state
			self:_UpdateFiltersAndExclusions()
		end
	)

	-- Find current sort mode index
	local sortModes = { "type-then-alpha", "alpha-only", "type-only", "none" }
	local currentSortIndex = 1
	for i, mode in ipairs(sortModes) do
		if mode == options.SortMode then
			currentSortIndex = i
			break
		end
	end

	SettingsMenuHelper.CreateCycleButton(
		generalContent,
		"SortMode",
		"Sort Mode",
		sortModes,
		currentSortIndex,
		fontFace,
		function(_index: number, value: string)
			self.Options.SortMode = value :: Types.SortMode
			self:_UpdateOrdering()
		end
	)

	-- === Flash Settings Section ===
	local flashContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "Flash", "Flash Animations", false, fontFace, 2)

	SettingsMenuHelper.CreateToggle(
		flashContent,
		"FlashChanges",
		"Flash Changes",
		options.FlashOnChange,
		fontFace,
		function(state)
			self.Options.FlashOnChange = state
		end
	)

	SettingsMenuHelper.CreateToggle(
		flashContent,
		"FlashNested",
		"Flash Nested",
		options.FlashNestedResults,
		fontFace,
		function(state)
			self.Options.FlashNestedResults = state
		end
	)

	SettingsMenuHelper.CreateSectionLabel(flashContent, "FlashRedLabel", "Flash Red On:", fontFace)

	SettingsMenuHelper.CreateToggle(
		flashContent,
		"FlashRemoval",
		"Removals",
		options.FlashOnRemoval,
		fontFace,
		function(state)
			self.Options.FlashOnRemoval = state
		end
	)

	SettingsMenuHelper.CreateToggle(
		flashContent,
		"FlashDecrement",
		"Decrements",
		options.FlashOnDecrement,
		fontFace,
		function(state)
			self.Options.FlashOnDecrement = state
		end
	)

	SettingsMenuHelper.CreateToggle(
		flashContent,
		"FlashFalse",
		"Bool → False",
		options.FlashOnBooleanFalse,
		fontFace,
		function(state)
			self.Options.FlashOnBooleanFalse = state
		end
	)

	-- === Search Settings Section ===
	local searchContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "Search", "Search Options", false, fontFace, 3)

	SettingsMenuHelper.CreateToggle(
		searchContent,
		"CaseSensitive",
		"Case Sensitive",
		options.CaseSensitive,
		fontFace,
		function(state)
			self.Options.CaseSensitive = state
			self:_UpdateFiltersAndExclusions()
		end
	)

	SettingsMenuHelper.CreateToggle(
		searchContent,
		"FilterOnType",
		"Filter on Type",
		options.FilterOnType,
		fontFace,
		function(state)
			self.Options.FilterOnType = state
			self:_UpdateFiltersAndExclusions()
		end
	)

	SettingsMenuHelper.CreateNumberInput(
		searchContent,
		"FuzzyThreshold",
		"Fuzzy Threshold",
		options.FuzzyThreshold,
		fontFace,
		function(value)
			local num = math.clamp(value, 0, 1)
			self.Options.FuzzyThreshold = num
			self:_UpdateFiltersAndExclusions()
		end,
		0.01 -- step
	)

	SettingsMenuHelper.CreateNumberInput(
		searchContent,
		"FilterDebounce",
		"Filter Debounce (s)",
		options.FilterDebounceDelay,
		fontFace,
		function(value)
			local num = math.clamp(value, 0, 2)
			self.Options.FilterDebounceDelay = num
		end,
		0.05 -- step
	)

	-- === Display Settings Section ===
	local displayContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "Display", "Display Options", false, fontFace, 4)

	SettingsMenuHelper.CreateToggle(
		displayContent,
		"ShowTableValue",
		"Show Table Value",
		options.ShowTableValue,
		fontFace,
		function(state)
			self.Options.ShowTableValue = state
			-- Would need refresh to apply
		end
	)

	SettingsMenuHelper.CreateNumberInput(
		displayContent,
		"NumberPrecision",
		"Number Precision",
		options.NumberPrecision,
		fontFace,
		function(value)
			local num = math.clamp(math.floor(value), 0, 15)
			self.Options.NumberPrecision = num
			-- Would need refresh to apply
		end,
		1 -- step
	)

	SettingsMenuHelper.CreateToggle(
		displayContent,
		"ShowTooltips",
		"Show Tooltips",
		options.ShowTooltips,
		fontFace,
		function(state)
			self.Options.ShowTooltips = state
		end
	)

	SettingsMenuHelper.CreateNumberInput(
		displayContent,
		"TooltipDelay",
		"Tooltip Delay (s)",
		options.TooltipDelay,
		fontFace,
		function(value)
			local num = math.clamp(value, 0, 5)
			self.Options.TooltipDelay = num
		end,
		0.1 -- step
	)

	SettingsMenuHelper.CreateToggle(
		displayContent,
		"Editable",
		"Editable Values",
		options.Editable,
		fontFace,
		function(state)
			self.Options.Editable = state
			self:_UpdateEditableState()
		end
	)

	-- === Verbose Mode Section ===
	local verboseContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "Verbose", "Verbose Mode", false, fontFace, 5)

	SettingsMenuHelper.CreateSectionLabel(verboseContent, "VerboseKeyTypesLabel", "Key Types:", fontFace, 1)

	SettingsMenuHelper.CreateToggle(
		verboseContent,
		"VerboseKeys",
		"Verbose Keys",
		options.VerboseKeys,
		fontFace,
		function(state)
			self.Options.VerboseKeys = state
			self:_RefreshAllEntryUIs()
		end,
		2
	)

	SettingsMenuHelper.CreateToggle(
		verboseContent,
		"VerboseKeyFunction",
		"  Function (Address)",
		options.VerboseKeyTypes["function"] or false,
		fontFace,
		function(state)
			self.Options.VerboseKeyTypes["function"] = state
			if self.Options.VerboseKeys then
				self:_RefreshAllEntryUIs()
			end
		end,
		3
	)

	SettingsMenuHelper.CreateToggle(
		verboseContent,
		"VerboseKeyInstance",
		"  Instance (GetFullName)",
		options.VerboseKeyTypes.Instance or false,
		fontFace,
		function(state)
			self.Options.VerboseKeyTypes.Instance = state
			if self.Options.VerboseKeys then
				self:_RefreshAllEntryUIs()
			end
		end,
		4
	)

	SettingsMenuHelper.CreateToggle(
		verboseContent,
		"VerboseKeyTable",
		"  Table (Item Count)",
		options.VerboseKeyTypes.table or false,
		fontFace,
		function(state)
			self.Options.VerboseKeyTypes.table = state
			if self.Options.VerboseKeys then
				self:_RefreshAllEntryUIs()
			end
		end,
		5
	)

	SettingsMenuHelper.CreateToggle(
		verboseContent,
		"VerboseKeyThread",
		"  Thread (Address)",
		options.VerboseKeyTypes.thread or false,
		fontFace,
		function(state)
			self.Options.VerboseKeyTypes.thread = state
			if self.Options.VerboseKeys then
				self:_RefreshAllEntryUIs()
			end
		end,
		6
	)

	SettingsMenuHelper.CreateSectionLabel(verboseContent, "VerboseValueTypesLabel", "Value Types:", fontFace, 7)

	SettingsMenuHelper.CreateToggle(
		verboseContent,
		"VerboseValues",
		"Verbose Values",
		options.VerboseValues,
		fontFace,
		function(state)
			self.Options.VerboseValues = state
			self:_RefreshAllEntryUIs()
		end,
		8
	)

	SettingsMenuHelper.CreateToggle(
		verboseContent,
		"VerboseValueFunction",
		"  Function (Address)",
		options.VerboseValueTypes["function"] or false,
		fontFace,
		function(state)
			self.Options.VerboseValueTypes["function"] = state
			if self.Options.VerboseValues then
				self:_RefreshAllEntryUIs()
			end
		end,
		9
	)

	SettingsMenuHelper.CreateToggle(
		verboseContent,
		"VerboseValueInstance",
		"  Instance (GetFullName)",
		options.VerboseValueTypes.Instance or false,
		fontFace,
		function(state)
			self.Options.VerboseValueTypes.Instance = state
			if self.Options.VerboseValues then
				self:_RefreshAllEntryUIs()
			end
		end,
		10
	)

	SettingsMenuHelper.CreateToggle(
		verboseContent,
		"VerboseValueTable",
		"  Table (Item Count)",
		options.VerboseValueTypes.table or false,
		fontFace,
		function(state)
			self.Options.VerboseValueTypes.table = state
			if self.Options.VerboseValues then
				self:_RefreshAllEntryUIs()
			end
		end,
		11
	)

	SettingsMenuHelper.CreateToggle(
		verboseContent,
		"VerboseValueThread",
		"  Thread (Address)",
		options.VerboseValueTypes.thread or false,
		fontFace,
		function(state)
			self.Options.VerboseValueTypes.thread = state
			if self.Options.VerboseValues then
				self:_RefreshAllEntryUIs()
			end
		end,
		12
	)

	-- === Colors Settings Section ===
	local colorsContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "Colors", "Colors", false, fontFace, 6)

	-- Get the parent ScreenGui for the color picker
	local pickerParent: GuiObject? = nil
	local current: Instance? = menu
	while current do
		if current:IsA("ScreenGui") or current:IsA("SurfaceGui") or current:IsA("BillboardGui") then
			pickerParent = current :: GuiObject
			break
		end
		current = current.Parent
	end

	-- Track layout order for color settings
	local colorLayoutOrder = 0

	local flashColorsLabel =
		SettingsMenuHelper.CreateSectionLabel(colorsContent, "FlashColorsLabel", "Flash Colors:", fontFace)
	colorLayoutOrder += 1
	flashColorsLabel.LayoutOrder = colorLayoutOrder

	local flashColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"FlashColor",
		"Change Flash",
		options.FlashColor,
		fontFace,
		function(color)
			self.Options.FlashColor = color
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	flashColorPicker.LayoutOrder = colorLayoutOrder

	local removalColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"FlashRemovalColor",
		"Removal Flash",
		options.FlashRemovalColor,
		fontFace,
		function(color)
			self.Options.FlashRemovalColor = color
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	removalColorPicker.LayoutOrder = colorLayoutOrder

	local navColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"FlashNavigationColor",
		"Navigation Flash",
		options.FlashNavigationColor,
		fontFace,
		function(color)
			self.Options.FlashNavigationColor = color
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	navColorPicker.LayoutOrder = colorLayoutOrder

	local searchNestedColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"FlashSearchNestedColor",
		"Search Nested",
		options.FlashSearchNestedColor,
		fontFace,
		function(color)
			self.Options.FlashSearchNestedColor = color
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	searchNestedColorPicker.LayoutOrder = colorLayoutOrder

	local searchRootColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"FlashSearchRootColor",
		"Search Root",
		options.FlashSearchRootColor,
		fontFace,
		function(color)
			self.Options.FlashSearchRootColor = color
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	searchRootColorPicker.LayoutOrder = colorLayoutOrder

	local syntaxLabel =
		SettingsMenuHelper.CreateSectionLabel(colorsContent, "SyntaxColorsLabel", "Syntax Highlighting:", fontFace)
	colorLayoutOrder += 1
	syntaxLabel.LayoutOrder = colorLayoutOrder

	local booleanColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"SyntaxBoolean",
		"Boolean",
		options.SyntaxHighlighting.boolean,
		fontFace,
		function(color)
			self.Options.SyntaxHighlighting.boolean = color
			self:_RefreshAllEntryUIs()
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	booleanColorPicker.LayoutOrder = colorLayoutOrder

	local numberColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"SyntaxNumber",
		"Number",
		options.SyntaxHighlighting.number,
		fontFace,
		function(color)
			self.Options.SyntaxHighlighting.number = color
			self:_RefreshAllEntryUIs()
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	numberColorPicker.LayoutOrder = colorLayoutOrder

	local stringColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"SyntaxString",
		"String",
		options.SyntaxHighlighting.string,
		fontFace,
		function(color)
			self.Options.SyntaxHighlighting.string = color
			self:_RefreshAllEntryUIs()
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	stringColorPicker.LayoutOrder = colorLayoutOrder

	local tableColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"SyntaxTable",
		"Table",
		options.SyntaxHighlighting.table,
		fontFace,
		function(color)
			self.Options.SyntaxHighlighting.table = color
			self:_RefreshAllEntryUIs()
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	tableColorPicker.LayoutOrder = colorLayoutOrder

	local functionColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"SyntaxFunction",
		"Function",
		options.SyntaxHighlighting["function"],
		fontFace,
		function(color)
			self.Options.SyntaxHighlighting["function"] = color
			self:_RefreshAllEntryUIs()
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	functionColorPicker.LayoutOrder = colorLayoutOrder

	local instanceColorPicker = SettingsMenuHelper.CreateColorPicker(
		colorsContent,
		"SyntaxInstance",
		"Instance",
		options.SyntaxHighlighting.Instance,
		fontFace,
		function(color)
			self.Options.SyntaxHighlighting.Instance = color
			self:_RefreshAllEntryUIs()
		end,
		pickerParent
	)
	colorLayoutOrder += 1
	instanceColorPicker.LayoutOrder = colorLayoutOrder

	-- === Recursion Settings Section ===
	local recursionContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "Recursion", "Recursion Detection", false, fontFace, 7)

	SettingsMenuHelper.CreateToggle(
		recursionContent,
		"DetectRecursive",
		"Detect Recursive",
		options.DetectRecursiveTables,
		fontFace,
		function(state)
			self.Options.DetectRecursiveTables = state
		end
	)

	SettingsMenuHelper.CreateToggle(
		recursionContent,
		"DetectDuplicates",
		"Detect Duplicates",
		options.DetectDuplicateReferences,
		fontFace,
		function(state)
			self.Options.DetectDuplicateReferences = state
		end
	)

	SettingsMenuHelper.CreateNumberInput(
		recursionContent,
		"MaxRecursionDepth",
		"Max Depth",
		options.MaxRecursionDepth,
		fontFace,
		function(value)
			local num = math.clamp(math.floor(value), 1, 100)
			self.Options.MaxRecursionDepth = num
		end,
		1 -- step
	)

	-- === Size Settings Section ===
	local sizeContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "Size", "Size Limits", false, fontFace, 8)

	SettingsMenuHelper.CreateNumberInput(
		sizeContent,
		"MinWidth",
		"Min Width",
		options.MinSize.X,
		fontFace,
		function(value)
			local num = math.clamp(math.floor(value), 50, 500)
			self.Options.MinSize = Vector2.new(num, self.Options.MinSize.Y)
		end,
		10 -- step
	)

	SettingsMenuHelper.CreateNumberInput(
		sizeContent,
		"MinHeight",
		"Min Height",
		options.MinSize.Y,
		fontFace,
		function(value)
			local num = math.clamp(math.floor(value), 50, 500)
			self.Options.MinSize = Vector2.new(self.Options.MinSize.X, num)
		end,
		10 -- step
	)

	SettingsMenuHelper.CreateNumberInput(
		sizeContent,
		"MaxWidth",
		"Max Width",
		options.MaxSize.X,
		fontFace,
		function(value)
			local num = math.clamp(math.floor(value), 100, 2000)
			self.Options.MaxSize = Vector2.new(num, self.Options.MaxSize.Y)
		end,
		50 -- step
	)

	SettingsMenuHelper.CreateNumberInput(
		sizeContent,
		"MaxHeight",
		"Max Height",
		options.MaxSize.Y,
		fontFace,
		function(value)
			local num = math.clamp(math.floor(value), 100, 2000)
			self.Options.MaxSize = Vector2.new(self.Options.MaxSize.X, num)
		end,
		50 -- step
	)

	SettingsMenuHelper.CreateNumberInput(
		sizeContent,
		"AutoSizeMaxHeight",
		"Auto-Size Max Height",
		options.AutoSizeMaxHeight,
		fontFace,
		function(value)
			local num = math.clamp(math.floor(value), 100, 2000)
			self.Options.AutoSizeMaxHeight = num
			if self.Options.AutoSizeToContent then
				self:AutoSize()
			end
		end,
		50 -- step
	)

	-- AutoSizeMode cycle button
	local autoSizeModes = { "content", "maxAvailable", "fixed" }
	local currentAutoSizeIndex = 1
	for i, mode in autoSizeModes do
		if mode == options.AutoSizeMode then
			currentAutoSizeIndex = i
			break
		end
	end

	SettingsMenuHelper.CreateCycleButton(
		sizeContent,
		"AutoSizeMode",
		"Auto-Size Mode",
		autoSizeModes,
		currentAutoSizeIndex,
		fontFace,
		function(_index: number, value: string)
			self.Options.AutoSizeMode = value :: "content" | "maxAvailable" | "fixed"
			if self.Options.AutoSizeToContent then
				self:AutoSize()
			end
		end
	)

	-- === Performance Settings Section ===
	local perfContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "Performance", "Performance", false, fontFace, 9)

	SettingsMenuHelper.CreateToggle(
		perfContent,
		"EnablePooling",
		"Enable Pooling",
		options.EnablePooling,
		fontFace,
		function(state)
			self.Options.EnablePooling = state
		end
	)

	SettingsMenuHelper.CreateNumberInput(
		perfContent,
		"MaxPoolSize",
		"Max Pool Size",
		options.MaxPoolSize,
		fontFace,
		function(value)
			local num = math.clamp(math.floor(value), 0, 500)
			self.Options.MaxPoolSize = num
		end,
		10 -- step
	)

	SettingsMenuHelper.CreateNumberInput(
		perfContent,
		"FlashDuration",
		"Flash Duration (s)",
		options.FlashDuration,
		fontFace,
		function(value)
			local num = math.clamp(value, 0.1, 5)
			self.Options.FlashDuration = num
		end,
		0.1 -- step
	)

	SettingsMenuHelper.CreateNumberInput(
		perfContent,
		"MaxFloatResults",
		"Max Float Results",
		options.MaxFloatResults,
		fontFace,
		function(value)
			local num = math.clamp(math.floor(value), 1, 100)
			self.Options.MaxFloatResults = num
		end,
		1 -- step
	)

	SettingsMenuHelper.CreateNumberInput(
		perfContent,
		"MaxConcurrentFlashes",
		"Max Concurrent Flashes",
		options.MaxConcurrentFlashes,
		fontFace,
		function(value)
			local num = math.clamp(math.floor(value), 1, 50)
			self.Options.MaxConcurrentFlashes = num
		end,
		1 -- step
	)

	-- === Add Row Settings Section ===
	local addRowContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "AddRow", "Add Row Options", false, fontFace, 10)

	SettingsMenuHelper.CreateToggle(
		addRowContent,
		"AddRowsFiltering",
		"While Filtering",
		options.ShowAddRowsWhileFiltering,
		fontFace,
		function(state)
			self.Options.ShowAddRowsWhileFiltering = state
			self:_UpdateFiltersAndExclusions()
		end
	)

	SettingsMenuHelper.CreateToggle(
		addRowContent,
		"AddRowsExcluding",
		"While Excluding",
		options.ShowAddRowsWhileExcluding,
		fontFace,
		function(state)
			self.Options.ShowAddRowsWhileExcluding = state
			self:_UpdateFiltersAndExclusions()
		end
	)

	-- === Actions Section ===
	local actionsContent =
		SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "Actions", "Actions", true, fontFace, 11)

	SettingsMenuHelper.CreateButton(actionsContent, "ExpandMax", "⤢ Expand to Max", fontFace, function()
		self:ExpandToMax()
		menu.Visible = false
	end)

	SettingsMenuHelper.CreateButton(actionsContent, "Snapshot", "📸 Snapshot", fontFace, function()
		self:Snapshot()
		menu.Visible = false
	end)

	SettingsMenuHelper.CreateButton(actionsContent, "ExportJson", "📄 Export JSON", fontFace, function()
		local json = self:ExportToJson()
		print(json)
		menu.Visible = false
	end)

	SettingsMenuHelper.CreateButton(actionsContent, "ExportLua", "📜 Export Lua", fontFace, function()
		local lua = self:ExportToLua()
		print(lua)
		menu.Visible = false
	end)

	-- Diff comparison buttons
	local diffButton = SettingsMenuHelper.CreateButton(
		actionsContent,
		"StartDiff",
		"🔍 Compare with Viewer...",
		fontFace,
		function()
			menu.Visible = false
			-- Check if there are other viewers to compare with
			local hasOtherViewers = false
			for viewerId in idToViewer do
				if viewerId ~= self._id then
					hasOtherViewers = true
					break
				end
			end

			if not hasOtherViewers then
				-- Flash the header to indicate no viewers available
				if self._ui then
					local header = self._ui:FindFirstChild("Header") :: Frame?
					if header then
						local headerLabel = header:FindFirstChild("HeaderLabel") :: TextLabel?
						if headerLabel then
							local originalText = headerLabel.Text
							local originalColor = headerLabel.TextColor3
							headerLabel.Text = "No other viewers to compare"
							headerLabel.TextColor3 = COLORS.DiffRemoved
							task.delay(2, function()
								if headerLabel and headerLabel.Parent then
									headerLabel.Text = originalText
									headerLabel.TextColor3 = originalColor
								end
							end)
						end
					end
				end
				return
			end

			-- Start selection mode
			self:StartDiffSelection()
		end
	)

	-- Stop diff button (initially hidden, shown when in diff mode)
	local stopDiffButton = SettingsMenuHelper.CreateButton(
		actionsContent,
		"StopDiff",
		"✖ Stop Comparison",
		fontFace,
		function()
			menu.Visible = false
			self:StopDiff()
		end
	)
	stopDiffButton.Visible = self._diffState.Active
	stopDiffButton.BackgroundColor3 = COLORS.DiffRemoved:Lerp(COLORS.ButtonBackground, 0.7)

	-- Refresh diff button (shown when in diff mode)
	local refreshDiffButton = SettingsMenuHelper.CreateButton(
		actionsContent,
		"RefreshDiff",
		"🔄 Refresh Comparison",
		fontFace,
		function()
			menu.Visible = false
			self:RefreshDiff()
		end
	)
	refreshDiffButton.Visible = self._diffState.Active

	-- Update button visibility based on diff state
	local function updateDiffButtonVisibility()
		diffButton.Visible = not self._diffState.Active and not self._diffState.SelectionMode
		stopDiffButton.Visible = self._diffState.Active
		refreshDiffButton.Visible = self._diffState.Active
	end

	-- Connect to check diff state when menu becomes visible
	menu:GetPropertyChangedSignal("Visible"):Connect(function()
		if menu.Visible then
			updateDiffButtonVisibility()
		end
	end)

	-- === Debug Section ===
	local debugContent = SettingsMenuHelper.CreateCollapsibleSection(scrollFrame, "Debug", "Debug", false, fontFace, 12)

	SettingsMenuHelper.CreateToggle(
		debugContent,
		"ShowBoundingBoxes",
		"Show Bounding Boxes",
		false,
		fontFace,
		function(state)
			self:_SetDebugMode(state)
		end
	)

	SettingsMenuHelper.CreateButton(debugContent, "RunAllTests", "🧪 Run All Tests", fontFace, function()
		menu.Visible = false
		task.spawn(function()
			-- Use deferred require to avoid cyclic dependency at module load time
			local testsModule = script:FindFirstChild("Tests")
			if testsModule then
				local comprehensiveModule = testsModule:FindFirstChild("Comprehensive")
				if comprehensiveModule and comprehensiveModule:IsA("ModuleScript") then
					local success, ComprehensiveTests = pcall(require, comprehensiveModule)
					if success and ComprehensiveTests and ComprehensiveTests.runTests then
						ComprehensiveTests.runTests()
					else
						warn("Failed to load ComprehensiveTests module")
					end
				else
					warn("Comprehensive tests module not found")
				end
			else
				warn("Tests module not found")
			end
		end)
	end)

	SettingsMenuHelper.CreateButton(debugContent, "ExportSettings", "⚙️ Export Settings", fontFace, function()
		menu.Visible = false
		local output = self:_ExportNonDefaultSettings()
		print(output)
	end)

	-- Menu height is now automatic via AutomaticCanvasSize
	-- Just set a reasonable max height
	local maxMenuHeight = 350
	menu.Size = UDim2.fromOffset(200, maxMenuHeight)
	menu.Position = UDim2.new(1, -205, 1, -28 - maxMenuHeight - 5)

	-- Adjust menu height based on content (up to max)
	mainLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local contentHeight = mainLayout.AbsoluteContentSize.Y + 16 -- padding
		local height = math.min(contentHeight, maxMenuHeight)
		menu.Size = UDim2.fromOffset(200, height)
		menu.Position = UDim2.new(1, -205, 1, -28 - height - 5)
	end)
end

function TableEditor._SetupBaseUIEvents(
	self: InternalTableEditor,
	frame: TableEditorGui,
	header: Frame,
	footer: Frame,
	viewer: Frame,
	optionsMenu: Frame
)
	local options = self.Options

	-- Close button
	local closeButton = FindHeaderChild(header, "CloseButton") :: ImageButton
	closeButton.Activated:Once(function()
		self:Destroy()
	end)

	-- Minimize button (shrink to 28x28)
	local minimizeButton = FindHeaderChild(header, "MinimizeButton") :: ImageButton
	minimizeButton.Activated:Connect(function()
		self:Minimize()
	end)

	-- Collapse button (shrink to title bar)
	local collapseButton = FindHeaderChild(header, "CollapseButton") :: ImageButton
	collapseButton.Activated:Connect(function()
		self:Collapse()
	end)

	-- Freeze button
	local freezeButton = FindHeaderChild(header, "FreezeButton") :: ImageButton
	freezeButton.Activated:Connect(function()
		if self._frozen then
			self:Unfreeze()
		else
			self:Freeze()
		end
	end)

	-- Hamburger menu
	local hamburgerButton = FindFooterChild(footer, "HamburgerButton") :: ImageButton
	hamburgerButton.Activated:Connect(function()
		optionsMenu.Visible = not optionsMenu.Visible
	end)

	-- Close menu when clicking elsewhere
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mousePos = Vector2.new(input.Position.X, input.Position.Y)
			local menuPos = optionsMenu.AbsolutePosition
			local menuSize = optionsMenu.AbsoluteSize
			if
				not (
					mousePos.X >= menuPos.X
					and mousePos.X <= menuPos.X + menuSize.X
					and mousePos.Y >= menuPos.Y
					and mousePos.Y <= menuPos.Y + menuSize.Y
				)
			then
				local hambPos = hamburgerButton.AbsolutePosition
				local hambSize = hamburgerButton.AbsoluteSize
				if
					not (
						mousePos.X >= hambPos.X
						and mousePos.X <= hambPos.X + hambSize.X
						and mousePos.Y >= hambPos.Y
						and mousePos.Y <= hambPos.Y + hambSize.Y
					)
				then
					optionsMenu.Visible = false
				end
			end
		end
	end)

	-- Resize handling
	local resizeButton = FindFooterChild(footer, "ResizeButton") :: ImageButton
	local resizing = false
	local resizeOffset = Vector2.zero

	resizeButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mousePos = Vector2.new(input.Position.X, input.Position.Y)
			resizeOffset = (frame.AbsolutePosition + frame.AbsoluteSize) - mousePos
			resizing = true
		end
	end)

	self._trove:Connect(UserInputService.InputChanged, function(input)
		if not resizing or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local mousePos = Vector2.new(input.Position.X, input.Position.Y)
		local size = mousePos - frame.AbsolutePosition + resizeOffset
		local x = math.clamp(size.X, options.MinSize.X, options.MaxSize.X)
		local y = math.clamp(size.Y, options.MinSize.Y, options.MaxSize.Y)
		frame.Size = UDim2.fromOffset(x, y)
	end)
	self._trove:Connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = false
		end
	end)

	local fieldFilter = FindFooterChild(footer, "FieldFilter") :: TextBox
	local exclusionsBox = FindFooterChild(footer, "Exclusions") :: TextBox
	local filterModeButton = FindFooterChild(footer, "FilterModeButton") :: TextButton

	-- Filter mode: "keys", "values", "both" (AND logic), or "either" (OR logic)
	local filterMode: "keys" | "values" | "both" | "either" = "keys"
	local filterModeLabels = {
		keys = "K",
		values = "V",
		both = "B",
		either = "E",
	}
	local filterModePlaceholders = {
		keys = "🔍 Filter keys...",
		values = "🔍 Filter values...",
		both = "🔍 Filter keys & values (AND)...",
		either = "🔍 Filter keys | values (OR)...",
	}

	local function UpdateFilterMode()
		filterModeButton.Text = filterModeLabels[filterMode]
		fieldFilter.PlaceholderText = filterModePlaceholders[filterMode]
	end

	local function CycleFilterMode()
		if filterMode == "keys" then
			filterMode = "values"
		elseif filterMode == "values" then
			filterMode = "both"
		elseif filterMode == "both" then
			filterMode = "either"
		else
			filterMode = "keys"
		end
		UpdateFilterMode()
		-- Re-apply filters with new mode
		local rawTokens = fieldFilter.Text:split(",")
		local filters: { string } = {}
		for _, token in pairs(rawTokens) do
			local trimmed = token:gsub("^%s+", ""):gsub("%s+$", "")
			if trimmed ~= "" then
				table.insert(filters, trimmed)
			end
		end
		-- Set filters based on mode (nil for modes that don't use that filter type)
		if filters[1] then
			if filterMode == "keys" then
				self:SetKeyFilter(filters)
				self:SetValueFilter(nil)
				self._filterCombineMode = nil
			elseif filterMode == "values" then
				self:SetKeyFilter(nil)
				self:SetValueFilter(filters)
				self._filterCombineMode = nil
			elseif filterMode == "both" then
				self:SetKeyFilter(filters)
				self:SetValueFilter(filters)
				self._filterCombineMode = "and"
			else -- either
				self:SetKeyFilter(filters)
				self:SetValueFilter(filters)
				self._filterCombineMode = "or"
			end
		else
			self:SetKeyFilter(nil)
			self:SetValueFilter(nil)
			self._filterCombineMode = nil
		end
	end

	filterModeButton.Activated:Connect(CycleFilterMode)

	local function UpdateFilters()
		local rawTokens = fieldFilter.Text:split(",")
		local filters: { string } = {}
		for _, token in pairs(rawTokens) do
			local trimmed = token:gsub("^%s+", ""):gsub("%s+$", "")
			if trimmed ~= "" then
				table.insert(filters, trimmed)
			end
		end
		-- Set filters based on mode (nil for modes that don't use that filter type)
		if filters[1] then
			if filterMode == "keys" then
				self:SetKeyFilter(filters)
				self:SetValueFilter(nil)
				self._filterCombineMode = nil
			elseif filterMode == "values" then
				self:SetKeyFilter(nil)
				self:SetValueFilter(filters)
				self._filterCombineMode = nil
			elseif filterMode == "both" then
				self:SetKeyFilter(filters)
				self:SetValueFilter(filters)
				self._filterCombineMode = "and"
			else -- either
				self:SetKeyFilter(filters)
				self:SetValueFilter(filters)
				self._filterCombineMode = "or"
			end
		else
			self:SetKeyFilter(nil)
			self:SetValueFilter(nil)
			self._filterCombineMode = nil
		end
	end

	local function UpdateExclusions()
		local rawTokens = exclusionsBox.Text:split(",")
		local types: { string } = {}
		for _, token in pairs(rawTokens) do
			local trimmed = token:gsub("^%s+", ""):gsub("%s+$", "")
			if trimmed ~= "" then
				table.insert(types, trimmed)
			end
		end
		if types[1] then
			self:SetTypeExclusion(types)
		else
			self:SetTypeExclusion(nil)
		end
	end

	if options.FilterOnType then
		fieldFilter:GetPropertyChangedSignal("Text"):Connect(function()
			DebouncedFilterUpdate(
				self._id .. "_filter",
				UpdateFilters,
				options.FilterDebounceDelay,
				filterDebounceThreads
			)
		end)
		exclusionsBox:GetPropertyChangedSignal("Text"):Connect(function()
			DebouncedFilterUpdate(
				self._id .. "_exclusion",
				UpdateExclusions,
				options.FilterDebounceDelay,
				filterDebounceThreads
			)
		end)
	else
		fieldFilter.FocusLost:Connect(UpdateFilters)
		exclusionsBox.FocusLost:Connect(UpdateExclusions)
	end

	if options.RememberPositionStates then
		frame:GetPropertyChangedSignal("Position"):Connect(function()
			if not self.Options then
				return
			end
			if self._visible then
				self.Options.OpenPosition = frame.Position
			else
				self.Options.ClosedPosition = frame.Position
			end
		end)
	end
end

--[[
	Quick view functionality - provides a simple way to view tables without manual setup.
	Manages ScreenGui lifecycle and reuses existing viewers when possible.
]]

--[[
	Creates or updates a quick view for the given data.
	
	If a quick view with the same name already exists, it will be updated with the new data.
	Otherwise, a new quick view will be created with its own ScreenGui.
	
	@param name The name/identifier for the quick view (used as title)
	@param data The table data to display (defaults to empty table if nil)
	@param options Optional configuration options (Title will be overridden by name)
	@return The TableEditor instance for the quick view
]]
function TableEditor.View(name: string, data: Table?, options: ViewerOptions?): TableEditor
	assert(type(name) == "string" and name ~= "", "View name must be a non-empty string")

	local safeData: Table = data or {}
	local alias = `{name}QuickView`

	-- If quick view already exists, update it and return
	local existingView = quickViews[alias]
	if existingView then
		-- Validate the existing view is still valid
		if existingView._ui and existingView._ui.Parent then
			existingView:Update(safeData)
			return existingView
		end
		-- View was destroyed externally, clean up reference
		quickViews[alias] = nil
	end

	-- Merge options with defaults for quick views
	local mergedOptions: ViewerOptions = options and DeepClone(options) or {}
	mergedOptions.Title = mergedOptions.Title or name

	-- Create a dedicated ScreenGui for this quick view
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = alias
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 1000
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mergedOptions.Parent = screenGui

	-- Create the TableEditor instance
	local viewer = TableEditor.new(safeData, mergedOptions)
	local internalViewer = viewer :: any

	-- Store reference
	quickViews[alias] = viewer

	-- Wrap the Destroy method to clean up quick view reference
	local originalDestroy = internalViewer.Destroy
	function internalViewer:Destroy()
		quickViews[alias] = nil
		originalDestroy(self)
	end

	-- Resolve parent.
	-- Try for local player's PlayerGui first; otherwise it's probably studio, so use StarterGui.
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		local playerGui = localPlayer and localPlayer:FindFirstChild("PlayerGui")
		if playerGui then
			screenGui.Parent = playerGui
		else
			task.spawn(function()
				local gui = localPlayer:WaitForChild("PlayerGui", 10)
				if gui and screenGui.Parent == nil then
					screenGui.Parent = gui
				end
			end)
		end
	else
		screenGui.Parent = game:GetService("StarterGui")
	end
	return viewer
end

--[[
	Retrieves an existing quick view by name.
	
	@param name The name of the quick view to retrieve
	@return The TableEditor instance if found, nil otherwise
]]
function TableEditor.GetQuickView(name: string): TableEditor?
	assert(type(name) == "string" and name ~= "", "View name must be a non-empty string")

	local alias = `{name}QuickView`
	local viewer = quickViews[alias]

	-- Validate the view is still valid
	if viewer then
		local internalViewer = viewer :: any
		if internalViewer._ui and internalViewer._ui.Parent then
			return viewer
		end
		-- Clean up invalid reference
		quickViews[alias] = nil
	end

	return nil
end

--[[
	Returns a dictionary of all active quick views.
	
	@return Dictionary mapping names to TableEditor instances
]]
function TableEditor.GetAllQuickViews(): { [string]: TableEditor }
	local result: { [string]: TableEditor } = {}

	for alias, viewer in pairs(quickViews) do
		local internalViewer = viewer :: any
		-- Only include valid views
		if internalViewer._ui and internalViewer._ui.Parent then
			-- Extract original name from alias (remove "QuickView" suffix)
			local name = alias:gsub("QuickView$", "")
			result[name] = viewer
		else
			-- Clean up invalid reference
			quickViews[alias] = nil
		end
	end

	return result
end

--[[
	Destroys a specific quick view by name.
	
	@param name The name of the quick view to destroy
	@return true if the view was found and destroyed, false otherwise
]]
function TableEditor.DestroyQuickView(name: string): boolean
	assert(type(name) == "string" and name ~= "", "View name must be a non-empty string")

	local alias = `{name}QuickView`
	local viewer = quickViews[alias]

	if viewer then
		viewer:Destroy() -- This will also clean up the quickViews reference
		return true
	end

	return false
end

--[[
	Destroys all active quick views.
	
	@return The number of quick views that were destroyed
]]
function TableEditor.DestroyAllQuickViews(): number
	local count = 0

	-- Collect aliases first to avoid modifying table during iteration
	local aliases: { string } = {}
	for alias in pairs(quickViews) do
		table.insert(aliases, alias)
	end

	for _, alias in ipairs(aliases) do
		local viewer = quickViews[alias]
		if viewer then
			viewer:Destroy()
			count += 1
		end
	end

	return count
end

--[[
	===============================
	SERVER VIEW FUNCTIONALITY
	===============================
	
	Allows the server to request clients to display table viewers.
	Includes data integrity verification to detect network serialization issues.
	
	Known serialization limitations when sending data over RemoteEvents
	(verified from official Roblox documentation):
	
	CONFIRMED BEHAVIORS:
	- Functions → nil (cannot be serialized)
	- Metatables are completely lost in transfer
	- Non-string/number table keys (Instance, userdata, function) → converted to strings
	- Table references become separate copies (same table used in multiple places becomes distinct copies)
	- Non-replicable Instances → nil (e.g., ServerStorage descendants sent to client)
	- Mixed tables (numeric + string keys) should be avoided, may cause undefined behavior
	- Nil values in table indices should be avoided
	
	LIKELY BEHAVIORS (not explicitly documented but expected):
	- Threads → nil (similar to functions, not serializable)
	- Userdata → nil or error (not serializable)
	
	UNCERTAIN (behavior may vary):
	- NaN values - may become nil or cause issues
	- Infinity values (math.huge) - behavior not documented
	- Sparse arrays (holes) - may be collapsed or cause issues
	
	Reference: https://create.roblox.com/docs/scripting/events/remote#argument-limitations
]]

-- Types for ServerView
type ServerViewTarget = Player | { Player } | "all"
type VerificationResult = {
	Success: boolean,
	Discrepancies: { string }?,
}

--[[
	Analyzes data before sending to detect potential serialization issues.
	Returns a list of warnings about data that may not serialize properly.
	
	Based on official Roblox documentation for RemoteEvent argument limitations.
]]
local function AnalyzeDataForSerializationIssues(data: any, path: string?, visited: { [any]: boolean }?): { string }
	local warnings: { string } = {}
	local currentPath = path or "root"
	local visitedTables = visited or {}

	if typeof(data) ~= "table" then
		local dataType = typeof(data)

		-- Check for non-serializable types (confirmed in Roblox docs)
		if dataType == "function" then
			-- CONFIRMED: "Functions included as arguments... will not be replicated...
			-- the resulting argument on the receiving side will be nil"
			table.insert(warnings, `{currentPath}: Functions cannot be serialized (will become nil) [CONFIRMED]`)
		elseif dataType == "thread" then
			-- LIKELY: Threads are similar to functions - not serializable data
			table.insert(warnings, `{currentPath}: Threads likely cannot be serialized (expected to become nil)`)
		elseif dataType == "userdata" then
			-- Userdata as VALUES (not keys) - behavior not explicitly documented
			-- but userdata is not a serializable type
			table.insert(warnings, `{currentPath}: Userdata may not serialize correctly`)
		elseif dataType == "number" then
			-- NaN and Infinity - not explicitly documented, warn about potential issues
			if data ~= data then -- NaN check (NaN ~= NaN is true)
				table.insert(warnings, `{currentPath}: NaN value detected - behavior over network is undefined`)
			elseif data == math.huge then
				table.insert(warnings, `{currentPath}: Positive infinity detected - behavior over network is undefined`)
			elseif data == -math.huge then
				table.insert(warnings, `{currentPath}: Negative infinity detected - behavior over network is undefined`)
			end
		end

		return warnings
	end

	-- Check for circular references (will cause infinite loop or error)
	if visitedTables[data] then
		table.insert(warnings, `{currentPath}: Circular reference detected (will cause issues)`)
		return warnings
	end
	visitedTables[data] = true

	-- Check for metatable - CONFIRMED: "all of the metatable information is lost in the transfer"
	local mt = getmetatable(data)
	if mt then
		table.insert(warnings, `{currentPath}: Table has a metatable which will be lost in transfer [CONFIRMED]`)
	end

	-- Analyze table structure
	local hasNumericKeys = false
	local hasStringKeys = false
	local numericKeys: { number } = {}
	local _maxNumericKey = 0

	for key, value in pairs(data) do
		local keyType = typeof(key)

		if keyType == "number" then
			hasNumericKeys = true
			table.insert(numericKeys, key)
			if key > _maxNumericKey then
				_maxNumericKey = key
			end
		elseif keyType == "string" then
			hasStringKeys = true
		else
			-- CONFIRMED: "If any indices of a passed table are non-string types such as
			-- an Instance, userdata, or function, Roblox automatically converts those indices to strings"
			table.insert(
				warnings,
				`{currentPath}[{tostring(key)}]: Non-string/number key (type: {keyType}) will be converted to string "{tostring(
					key
				)}" [CONFIRMED]`
			)
		end

		-- Check for nil values in table (explicitly warned against in docs)
		if value == nil then
			local keyStr = if keyType == "string" then `"{key}"` else tostring(key)
			table.insert(warnings, `{currentPath}[{keyStr}]: Nil value in table - should be avoided [CONFIRMED]`)
		end

		-- Recurse into values
		local childPath = if keyType == "string" then `{currentPath}.{key}` else `{currentPath}[{tostring(key)}]`
		local childWarnings = AnalyzeDataForSerializationIssues(value, childPath, visitedTables)
		for _, warning in ipairs(childWarnings) do
			table.insert(warnings, warning)
		end
	end

	-- Check for mixed tables
	-- CONFIRMED: "do not pass a mixed table of numeric and string keys"
	if hasNumericKeys and hasStringKeys then
		table.insert(
			warnings,
			`{currentPath}: Mixed table (numeric + string keys) - explicitly warned against in docs [CONFIRMED]`
		)
	end

	-- Check for sparse arrays (holes) - docs say "avoid nil values for any index"
	if hasNumericKeys and #numericKeys > 0 then
		table.sort(numericKeys)
		local expectedKey = 1
		for _, key in ipairs(numericKeys) do
			if key ~= expectedKey then
				if key > expectedKey then
					table.insert(
						warnings,
						`{currentPath}: Sparse array detected (hole at index {expectedKey}) - behavior may be undefined`
					)
					break
				end
			end
			expectedKey = key + 1
		end
	end

	-- Note: Metatables are silently lost - we can't easily detect this without getmetatable
	-- which might not be available, so we skip this check
	return warnings
end

--[[
	Compares two Roblox data types for equality, handling the fact that
	they become different userdata objects after network transfer.
	
	Uses FuzzyEq where available, or component-wise comparison for types that support it.
]]
local function RobloxDataTypesEqual(a: any, b: any): boolean
	local typeA = typeof(a)

	-- Must be same type
	if typeA ~= typeof(b) then
		return false
	end

	-- Vector3 - has FuzzyEq
	if typeA == "Vector3" then
		return a:FuzzyEq(b)
	end

	-- Vector2 - has FuzzyEq
	if typeA == "Vector2" then
		return a:FuzzyEq(b)
	end

	-- CFrame - has FuzzyEq (compares position and rotation with tolerance)
	if typeA == "CFrame" then
		return a:FuzzyEq(b, 1e-3)
	end

	-- Vector3int16 - compare integer components (no FuzzyEq available)
	if typeA == "Vector3int16" then
		return a.X == b.X and a.Y == b.Y and a.Z == b.Z
	end

	-- Vector2int16 - compare integer components (no FuzzyEq available)
	if typeA == "Vector2int16" then
		return a.X == b.X and a.Y == b.Y
	end

	-- Color3 - compare RGB components with tolerance (no FuzzyEq available)
	if typeA == "Color3" then
		local EPSILON = 1e-6
		return math.abs(a.R - b.R) < EPSILON and math.abs(a.G - b.G) < EPSILON and math.abs(a.B - b.B) < EPSILON
	end

	-- UDim2 - compare components
	if typeA == "UDim2" then
		local EPSILON = 1e-6
		return math.abs(a.X.Scale - b.X.Scale) < EPSILON
			and math.abs(a.X.Offset - b.X.Offset) < EPSILON
			and math.abs(a.Y.Scale - b.Y.Scale) < EPSILON
			and math.abs(a.Y.Offset - b.Y.Offset) < EPSILON
	end

	-- UDim - compare components
	if typeA == "UDim" then
		local EPSILON = 1e-6
		return math.abs(a.Scale - b.Scale) < EPSILON and math.abs(a.Offset - b.Offset) < EPSILON
	end

	-- Rect - compare components
	if typeA == "Rect" then
		local EPSILON = 1e-6
		return math.abs(a.Min.X - b.Min.X) < EPSILON
			and math.abs(a.Min.Y - b.Min.Y) < EPSILON
			and math.abs(a.Max.X - b.Max.X) < EPSILON
			and math.abs(a.Max.Y - b.Max.Y) < EPSILON
	end

	-- Region3 - compare CFrame and Size
	if typeA == "Region3" then
		local EPSILON = 1e-6
		local cfEqual = RobloxDataTypesEqual(a.CFrame, b.CFrame)
		local sizeEqual = (a.Size - b.Size).Magnitude < EPSILON
		return cfEqual and sizeEqual
	end

	-- Ray - compare Origin and Direction
	if typeA == "Ray" then
		local EPSILON = 1e-6
		return (a.Origin - b.Origin).Magnitude < EPSILON and (a.Direction - b.Direction).Magnitude < EPSILON
	end

	-- NumberRange - compare Min and Max
	if typeA == "NumberRange" then
		local EPSILON = 1e-6
		return math.abs(a.Min - b.Min) < EPSILON and math.abs(a.Max - b.Max) < EPSILON
	end

	-- NumberSequence - compare keypoints
	if typeA == "NumberSequence" then
		local keypointsA = a.Keypoints
		local keypointsB = b.Keypoints
		if #keypointsA ~= #keypointsB then
			return false
		end
		local EPSILON = 1e-6
		for i, kpA in ipairs(keypointsA) do
			local kpB = keypointsB[i]
			if
				math.abs(kpA.Time - kpB.Time) > EPSILON
				or math.abs(kpA.Value - kpB.Value) > EPSILON
				or math.abs(kpA.Envelope - kpB.Envelope) > EPSILON
			then
				return false
			end
		end
		return true
	end

	-- ColorSequence - compare keypoints
	if typeA == "ColorSequence" then
		local keypointsA = a.Keypoints
		local keypointsB = b.Keypoints
		if #keypointsA ~= #keypointsB then
			return false
		end
		local EPSILON = 1e-6
		for i, kpA in ipairs(keypointsA) do
			local kpB = keypointsB[i]
			if math.abs(kpA.Time - kpB.Time) > EPSILON or not RobloxDataTypesEqual(kpA.Value, kpB.Value) then
				return false
			end
		end
		return true
	end

	-- BrickColor - compare by Number (unique identifier)
	if typeA == "BrickColor" then
		return a.Number == b.Number
	end

	-- Enum/EnumItem - direct comparison should work
	if typeA == "EnumItem" then
		return a == b
	end

	-- Instance - compare by reference (same Instance should be same)
	if typeA == "Instance" then
		return a == b
	end

	-- TweenInfo - compare all components
	if typeA == "TweenInfo" then
		return a.Time == b.Time
			and a.EasingStyle == b.EasingStyle
			and a.EasingDirection == b.EasingDirection
			and a.RepeatCount == b.RepeatCount
			and a.Reverses == b.Reverses
			and a.DelayTime == b.DelayTime
	end

	-- Font - compare components
	if typeA == "Font" then
		return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style
	end

	-- PathWaypoint - compare Position and Action
	if typeA == "PathWaypoint" then
		return RobloxDataTypesEqual(a.Position, b.Position) and a.Action == b.Action
	end

	-- DateTime - compare UnixTimestampMillis
	if typeA == "DateTime" then
		return a.UnixTimestampMillis == b.UnixTimestampMillis
	end

	-- For any other type, fall back to direct comparison
	return a == b
end

--[[
	Checks if a type is a Roblox data type that needs special comparison.
]]
local function IsRobloxDataType(typeName: string): boolean
	local robloxTypes = {
		"Vector3",
		"Vector2",
		"CFrame",
		"Color3",
		"UDim2",
		"UDim",
		"Rect",
		"Region3",
		"Ray",
		"NumberRange",
		"NumberSequence",
		"ColorSequence",
		"BrickColor",
		"EnumItem",
		"TweenInfo",
		"Font",
		"PathWaypoint",
		"DateTime",
		"Vector3int16",
		"Vector2int16",
		"Faces",
		"Axes",
		"PhysicalProperties",
		"OverlapParams",
		"RaycastParams",
	}
	return table.find(robloxTypes, typeName) ~= nil
end

--[[
	Deep comparison that returns a list of discrepancies between two values.
	More detailed than DeepEqual - reports exactly what differs.
	
	This is used for verification after client receives data to detect
	actual serialization issues that occurred.
	
	Handles Roblox data types (Vector3, CFrame, Color3, etc.) with fuzzy equality
	since they become different userdata objects after network transfer.
]]
local function FindDiscrepancies(original: any, received: any, path: string?, visited: { [any]: boolean }?): { string }
	local discrepancies: { string } = {}
	local currentPath = path or "root"
	local visitedTables = visited or {}

	local typeOriginal = typeof(original)
	local typeReceived = typeof(received)

	-- Type mismatch
	if typeOriginal ~= typeReceived then
		table.insert(discrepancies, `{currentPath}: Type changed from {typeOriginal} to {typeReceived}`)
		return discrepancies
	end

	-- Handle Roblox data types with special comparison
	if IsRobloxDataType(typeOriginal) then
		if not RobloxDataTypesEqual(original, received) then
			table.insert(
				discrepancies,
				`{currentPath}: {typeOriginal} value changed from {tostring(original)} to {tostring(received)}`
			)
		end
		return discrepancies
	end

	-- Non-table comparison
	if typeOriginal ~= "table" then
		if original ~= received then
			-- Special handling for NaN
			if typeOriginal == "number" and original ~= original then
				table.insert(discrepancies, `{currentPath}: NaN became {tostring(received)}`)
			else
				table.insert(
					discrepancies,
					`{currentPath}: Value changed from {tostring(original)} to {tostring(received)}`
				)
			end
		end
		return discrepancies
	end

	-- Avoid infinite loops with circular references
	if visitedTables[original] then
		return discrepancies
	end
	visitedTables[original] = true

	-- Check for keys in original that are missing or different in received
	for key, originalValue in pairs(original) do
		local keyStr = if typeof(key) == "string" then `"{key}"` else tostring(key)
		local childPath = `{currentPath}[{keyStr}]`

		local receivedValue = received[key]
		if receivedValue == nil then
			table.insert(discrepancies, `{childPath}: Key missing after serialization`)
		else
			local childDiscrepancies = FindDiscrepancies(originalValue, receivedValue, childPath, visitedTables)
			for _, disc in ipairs(childDiscrepancies) do
				table.insert(discrepancies, disc)
			end
		end
	end

	-- Check for extra keys in received (shouldn't happen but good to check)
	for key in pairs(received) do
		if original[key] == nil then
			local keyStr = if typeof(key) == "string" then `"{key}"` else tostring(key)
			table.insert(discrepancies, `{currentPath}[{keyStr}]: Unexpected key appeared after serialization`)
		end
	end

	return discrepancies
end

--[[
	Gets or creates the RemoteEvent for ServerView communication.
	On server: Creates the RemoteEvent in ReplicatedStorage
	On client: Finds the RemoteEvent in ReplicatedStorage
]]
local function GetOrCreateServerViewRemote(): RemoteEvent?
	if serverViewRemote then
		return serverViewRemote
	end

	if IS_SERVER then
		-- Server creates the RemoteEvent
		local existing = ReplicatedStorage:FindFirstChild(REMOTE_EVENT_NAME)
		if existing and existing:IsA("RemoteEvent") then
			serverViewRemote = existing
		else
			local remote = Instance.new("RemoteEvent")
			remote.Name = REMOTE_EVENT_NAME
			remote.Parent = ReplicatedStorage
			serverViewRemote = remote
		end
	else
		-- Client waits for the RemoteEvent (with timeout)
		local existing = ReplicatedStorage:FindFirstChild(REMOTE_EVENT_NAME)
		if existing and existing:IsA("RemoteEvent") then
			serverViewRemote = existing
		end
		-- Don't wait on client - it may never be created if server doesn't use ServerView
	end

	return serverViewRemote
end

--[[
	Sends a server view request to the specified players.
	
	@param players The target players: single Player, array of Players, or "all"
	@param name The name/identifier for the quick view
	@param data The table data to display
	@param options Optional configuration options
	@return Dictionary mapping player names to whether the request was sent
]]
function TableEditor.ServerView(
	players: ServerViewTarget,
	name: string,
	data: Table?,
	options: ViewerOptions?
): { [string]: boolean }
	if not IS_SERVER then
		warn("[TableEditor.ServerView] This function can only be called from the server")
		return {}
	end

	assert(type(name) == "string" and name ~= "", "View name must be a non-empty string")

	local remote = GetOrCreateServerViewRemote()
	if not remote then
		warn("[TableEditor.ServerView] Failed to create RemoteEvent")
		return {}
	end

	local safeData: Table = data or {}
	local results: { [string]: boolean } = {}

	-- Pre-analyze data for serialization issues
	local serializationWarnings = AnalyzeDataForSerializationIssues(safeData)
	if #serializationWarnings > 0 then
		warn(`[TableEditor.ServerView] Potential serialization issues detected for "{name}":`)
		for i, warning in ipairs(serializationWarnings) do
			if i <= 10 then -- Limit output
				warn(`  - {warning}`)
			elseif i == 11 then
				warn(`  ... and {#serializationWarnings - 10} more warnings`)
				break
			end
		end
	end

	-- Create a verification ID for this request
	local verificationId = HttpService:GenerateGUID(false)

	-- Resolve target players
	local targetPlayers: { Player } = {}
	if typeof(players) == "Instance" and players:IsA("Player") then
		table.insert(targetPlayers, players)
	elseif typeof(players) == "table" then
		for _, player in ipairs(players) do
			if typeof(player) == "Instance" and player:IsA("Player") then
				table.insert(targetPlayers, player)
			end
		end
	elseif players == "all" then
		targetPlayers = Players:GetPlayers()
	else
		warn("[TableEditor.ServerView] Invalid players argument. Expected Player, {Player}, or \"all\"")
		return {}
	end

	if #targetPlayers == 0 then
		warn("[TableEditor.ServerView] No valid players to send to")
		return {}
	end

	-- Clone data for each verification (in case original is modified)
	local clonedData = DeepClone(safeData)

	-- Send to each player
	for _, player in ipairs(targetPlayers) do
		local playerVerificationId = `{verificationId}_{player.UserId}`

		-- Store for verification callback
		pendingVerifications[playerVerificationId] = {
			OriginalData = clonedData,
			Name = name,
			PlayerName = player.Name,
		}

		-- Clean up verification after timeout (30 seconds)
		task.delay(30, function()
			if pendingVerifications[playerVerificationId] then
				warn(`[TableEditor.ServerView] Verification timeout for "{name}" from {player.Name}`)
				pendingVerifications[playerVerificationId] = nil
			end
		end)

		-- Fire to client
		local success = pcall(function()
			remote:FireClient(player, "view", {
				Name = name,
				Data = safeData,
				Options = options,
				VerificationId = playerVerificationId,
			})
		end)

		results[player.Name] = success
		if not success then
			warn(`[TableEditor.ServerView] Failed to send to {player.Name}`)
			pendingVerifications[playerVerificationId] = nil
		end
	end

	return results
end

--[[
	Handles verification response from client.
	Compares the data received by client with the original to detect serialization issues.
]]
local function HandleVerificationResponse(player: Player, verificationId: string, receivedData: any)
	local pending = pendingVerifications[verificationId]
	if not pending then
		return -- Already timed out or doesn't exist
	end

	pendingVerifications[verificationId] = nil

	-- Find discrepancies between original and what client received
	local discrepancies = FindDiscrepancies(pending.OriginalData, receivedData)

	if #discrepancies > 0 then
		warn(
			`[TableEditor.ServerView] Data integrity issues detected for "{pending.Name}" sent to {pending.PlayerName}:`
		)
		for i, discrepancy in ipairs(discrepancies) do
			if i <= 15 then -- Limit output
				warn(`  - {discrepancy}`)
			elseif i == 16 then
				warn(`  ... and {#discrepancies - 15} more discrepancies`)
				break
			end
		end
		warn(`[TableEditor.ServerView] Total discrepancies: {#discrepancies}`)
	end
end

--[[
	Sets up the client-side listener for ServerView requests.
	Called automatically when module loads on client.
]]
local function SetupClientServerViewListener()
	if not IS_CLIENT then
		return
	end

	-- Wait a bit for the remote to potentially be created
	task.spawn(function()
		-- Try to find the remote periodically
		local remote: RemoteEvent? = nil
		for _ = 1, 10 do
			remote = ReplicatedStorage:FindFirstChild(REMOTE_EVENT_NAME) :: RemoteEvent?
			if remote then
				break
			end
			task.wait(1)
		end

		if not remote then
			-- Remote doesn't exist, server isn't using ServerView
			return
		end

		serverViewRemote = remote

		remote.OnClientEvent:Connect(function(action: string, payload: any)
			if action == "view" and typeof(payload) == "table" then
				local name = payload.Name
				local data = payload.Data
				local options = payload.Options
				local verificationId = payload.VerificationId

				if typeof(name) ~= "string" or name == "" then
					warn("[TableEditor] Received invalid ServerView request: missing name")
					return
				end

				-- Call the local View function
				local success, err = pcall(function()
					TableEditor.View(name, data, options)
				end)

				if not success then
					warn(`[TableEditor] Failed to create ServerView "{name}": {err}`)
				end

				-- Send verification data back to server
				if verificationId and remote then
					pcall(function()
						remote:FireServer("verify", verificationId, data)
					end)
				end
			end
		end)
	end)
end

--[[
	Sets up the server-side listener for verification responses.
	Called automatically when module loads on server.
]]
local function SetupServerVerificationListener()
	if not IS_SERVER then
		return
	end

	-- Delay to ensure remote is created if ServerView is used
	task.spawn(function()
		task.wait(1)

		local remote = GetOrCreateServerViewRemote()
		if not remote then
			return
		end

		remote.OnServerEvent:Connect(function(player: Player, action: string, ...)
			if action == "verify" then
				local verificationId, receivedData = ...
				if typeof(verificationId) == "string" then
					HandleVerificationResponse(player, verificationId, receivedData)
				end
			end
		end)
	end)
end

-- Initialize listeners based on context
if IS_CLIENT then
	SetupClientServerViewListener()
elseif IS_SERVER then
	SetupServerVerificationListener()
end

return TableEditor :: TableEditorImpl
