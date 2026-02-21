--!strict
--[[
	All type definitions for the TableEditor module.
	Types are organized by category for easier navigation.
	
	=== HOW TO USE TYPES IN YOUR CODE ===
	
	Option 1: Require Types module directly (recommended)
	```lua
	local TableEditorTypes = require(path.to.TableEditor.Types)
	type TableEditor = TableEditorTypes.TableEditor
	type ViewerOptions = TableEditorTypes.ViewerOptions
	type SearchResult = TableEditorTypes.SearchResult
	```
	
	Option 2: Use typeof on module
	```lua
	local TableEditor = require(path.to.TableEditor)
	type TableEditorInstance = typeof(TableEditor.new({}, nil))
	```
	
	=== AVAILABLE TYPES ===
	
	Public API Types (for consumers):
	- TableEditor: The main viewer/editor instance
	- ViewerOptions: Configuration options for new()
	- SearchResult: Result from Search() method
	- SearchOptions: Options for Search() method
	- FilterOptions: Options for filter methods
	- DataEditedInfo: Info passed to OnDataEdited event
	- SignalConnection: Connection returned by signal:Connect()
	- SortMode: "type-then-alpha" | "alpha-only" | "type-only" | "none"
	- SyntaxColors: Color configuration for syntax highlighting
	- Association: Internal data structure for table entries
	
	Internal Types (for module development):
	- TableEditorInternal: TableEditor with all private fields/methods
	- ViewerOptionsInternal: Fully resolved options (no optionals)
	- TableEditorGui: The main UI frame structure
	- EntryGui: Individual entry row structure
]]

--- Table Editor Types ---

-- Syntax & Display Types
export type SyntaxColors = {
	Default: Color3,
	boolean: Color3,
	number: Color3,
	string: Color3,
	table: Color3,
	["function"]: Color3,
	Instance: Color3,
	Other: Color3,
	RecursiveRef: Color3,
	DuplicateRef: Color3,
}

export type VerboseTypeSettings = {
	Instance: boolean?,
	["function"]: boolean?,
	thread: boolean?,
	table: boolean?,
}

-- Sorting & Filtering Types
export type SortMode = "type-then-alpha" | "alpha-only" | "type-only" | "none"

export type SearchTarget = "keys" | "values" | "both"

export type SearchOptions = {
	Target: SearchTarget?,
	CaseSensitive: boolean?,
	FuzzyMatch: boolean?,
	FuzzyThreshold: number?,
	WholeWord: boolean?,
	Regex: boolean?,
}

export type SearchResult = {
	Path: { any },
	PathString: string,
	MatchedOn: "key" | "value" | "both",
	Association: any, -- Association type, forward reference
}

export type FilterOptions = {
	Mode: ("include" | "exclude")?,
	Target: SearchTarget?,
	CaseSensitive: boolean?,
	FuzzyMatch: boolean?,
}

export type TypeOrdering = {
	boolean: number,
	number: number,
	string: number,
	table: number,
	["function"]: number,
	Instance: number,
	Other: number,
}

-- Viewer Options Types
export type ViewerOptions = {
	-- Basic Options
	Title: string?,
	Parent: Instance?,

	-- Display Options
	AppendWrenchEmoji: boolean?,
	ShowTableValue: boolean?,
	ShowExtraAnimationTrackData: boolean?,
	MinKeyPixels: number?,

	-- Size Options
	StartingSize: Vector2?,
	MinSize: Vector2?,
	MaxSize: Vector2?,
	AutoSizeToContent: boolean?,
	AutoSizeMaxHeight: number?,
	AutoSizeMode: ("content" | "maxAvailable" | "fixed")?,

	-- Position Options
	ViewerPosition: UDim2?,
	RememberPositionStates: boolean?,
	OpenPosition: UDim2?,
	ClosedPosition: UDim2?,

	-- Behavior Options
	Expanded: boolean?,
	DefaultCollapsed: boolean?,
	DefaultMinimized: boolean?,
	NumberPrecision: number?,
	FilterOnType: boolean?,
	CaseSensitive: boolean?,
	FuzzyMatching: boolean?,
	FuzzyThreshold: number?,
	OrderTablesBasedOffNumberOfElements: boolean?,
	LazyLoadChildren: boolean?,
	Editable: boolean?,

	-- Font Options
	KeyFontFace: Font?,
	ValueFontFace: Font?,
	TextTruncateType: Enum.TextTruncate?,

	-- Recursive Options
	DetectRecursiveTables: boolean?,
	RecursiveDisplayFormat: string?,
	DetectDuplicateReferences: boolean?,
	DuplicateDisplayFormat: string?,
	MaxRecursionDepth: number?,

	-- Keybinding Options
	ToggleKeybind: { Enum.KeyCode }?,
	FocusKeybind: { Enum.KeyCode }?,

	-- Export Options
	EnableExport: boolean?,
	ExportFormat: ("json" | "lua" | "both")?,

	-- Visual Options
	ShowTooltips: boolean?,
	TooltipDelay: number?,
	FlashOnChange: boolean?,
	FlashColor: Color3?,
	FlashDuration: number?,
	FlashOnRemoval: boolean?,
	FlashRemovalColor: Color3?,
	FlashOnDecrement: boolean?,
	FlashOnBooleanFalse: boolean?,
	FloatRelevantResults: boolean?,
	FlashNestedResults: boolean?,
	MaxFloatResults: number?,
	MaxConcurrentFlashes: number?,
	FlashNavigationColor: Color3?,
	FlashSearchNestedColor: Color3?,
	FlashSearchRootColor: Color3?,

	-- Performance Options
	UnloadDelay: number?,
	FilterDebounceDelay: number?,
	EnablePooling: boolean?,
	MaxPoolSize: number?,

	-- Add Row Options
	ShowAddRowsWhileFiltering: boolean?,
	ShowAddRowsWhileExcluding: boolean?,

	-- Ordering
	SortMode: SortMode?,
	TypeOrdering: TypeOrdering?,
	SyntaxHighlighting: SyntaxColors?,

	-- Verbose Mode Options
	VerboseKeys: boolean?,
	VerboseValues: boolean?,
	VerboseKeyTypes: VerboseTypeSettings?,
	VerboseValueTypes: VerboseTypeSettings?,
}

export type ViewerOptionsInternal = {
	Title: string,
	Parent: Instance?,
	AppendWrenchEmoji: boolean,
	ShowTableValue: boolean,
	ShowExtraAnimationTrackData: boolean,
	MinKeyPixels: number,
	StartingSize: Vector2,
	MinSize: Vector2,
	MaxSize: Vector2,
	AutoSizeToContent: boolean,
	AutoSizeMaxHeight: number,
	AutoSizeMode: "content" | "maxAvailable" | "fixed",
	ViewerPosition: UDim2,
	RememberPositionStates: boolean,
	OpenPosition: UDim2,
	ClosedPosition: UDim2,
	Expanded: boolean,
	DefaultCollapsed: boolean,
	DefaultMinimized: boolean,
	NumberPrecision: number,
	FilterOnType: boolean,
	CaseSensitive: boolean,
	FuzzyMatching: boolean,
	FuzzyThreshold: number,
	OrderTablesBasedOffNumberOfElements: boolean,
	LazyLoadChildren: boolean,
	Editable: boolean,
	KeyFontFace: Font,
	ValueFontFace: Font,
	TextTruncateType: Enum.TextTruncate,
	DetectRecursiveTables: boolean,
	RecursiveDisplayFormat: string,
	DetectDuplicateReferences: boolean,
	DuplicateDisplayFormat: string,
	MaxRecursionDepth: number,
	ToggleKeybind: { Enum.KeyCode }?,
	FocusKeybind: { Enum.KeyCode }?,
	EnableExport: boolean,
	ExportFormat: "json" | "lua" | "both",
	ShowTooltips: boolean,
	TooltipDelay: number,
	FlashOnChange: boolean,
	FlashColor: Color3,
	FlashDuration: number,
	FloatRelevantResults: boolean,
	FlashNestedResults: boolean,
	FlashOnRemoval: boolean,
	FlashRemovalColor: Color3,
	FlashOnDecrement: boolean,
	FlashOnBooleanFalse: boolean,
	MaxFloatResults: number,
	MaxConcurrentFlashes: number,
	FlashNavigationColor: Color3,
	FlashSearchNestedColor: Color3,
	FlashSearchRootColor: Color3,
	UnloadDelay: number,
	FilterDebounceDelay: number,
	EnablePooling: boolean,
	MaxPoolSize: number,
	ShowAddRowsWhileFiltering: boolean,
	ShowAddRowsWhileExcluding: boolean,
	SortMode: SortMode,
	TypeOrdering: TypeOrdering,
	SyntaxHighlighting: SyntaxColors,
	VerboseKeys: boolean,
	VerboseValues: boolean,
	VerboseKeyTypes: VerboseTypeSettings,
	VerboseValueTypes: VerboseTypeSettings,
}

-- Data Types
export type Table = { [any]: any }

-- GUI Structure Types
export type TableEditorGui = Frame & {
	Header: Frame & {
		HeaderLabel: TextLabel,
		CollapseButton: TextButton,
		MinimizeButton: ImageButton,
		CloseButton: ImageButton,
		FreezeButton: TextButton,
		LinkButton: TextButton,
		DesyncIcon: ImageLabel,
		BadgeLabel: TextLabel,
		FreezeIndicator: ImageLabel,
	},
	Footer: Frame & {
		FieldFilter: TextBox,
		Exclusions: TextBox,
		ResizeButton: ImageButton,
		HamburgerButton: ImageButton,
	},
	Viewer: Frame & {
		Table: ScrollingFrame & {
			ListLayout: UIListLayout,
			UIPadding: UIPadding,
		},
	},
	OptionsMenu: Frame,
	Tooltip: Frame & {
		Label: TextLabel,
	},
	UIDragDetector: UIDragDetector,
}

export type EntryGui = Frame & {
	Children: Frame & {
		ListLayout: UIListLayout,
	},
	InfoBox: Frame & {
		ExpansionButton: ImageButton,
		FocusButton: ImageButton,
		DeleteRowButton: ImageButton?,
		ChangeFlash: Frame,
		Info: Frame & {
			FieldKey: TextBox & {
				SizeConstraint: UISizeConstraint,
			},
			FieldValue: TextBox,
			FlexLayout: UIListLayout,
		},
	},
}

-- Association Types
export type AssociationMeta = {
	ExpansionState: boolean?,
	FilterModeExpansionState: boolean?,
	KeyFiltered: boolean?,
	LastValueHash: string?,
	LastChangeTime: number?,
	Flashing: boolean?,
	CachedSortKey: number?,
	CachedChildCount: number?,
	LastValueType: string?,
	LastSortMode: string?,
	UnloadThread: thread?,
	TooltipThreads: { thread }?,
}

export type Association = {
	Key: any,
	Gui: EntryGui?,
	Parent: Association?,
	Depth: number,
	Value: any,
	OriginalTable: Table?,
	IsRecursive: boolean?,
	IsDuplicateRef: boolean?,
	DuplicateOfKey: string?,
	ChildrenLoaded: boolean?,
	IsGhost: boolean?, -- True if this is a ghost entry (exists only in target during diff)
	Expanded: boolean?, -- Whether this entry is expanded
	_meta: AssociationMeta,
}

export type Associations = { [string]: Association }

-- Signal Types
export type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> SignalConnection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> SignalConnection,
	Fire: (self: Signal<T...>, T...) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

-- Event Types
export type DataEditedInfo = {
	Path: { any },
	PathString: string,
	OldValue: any,
	NewValue: any,
	EditType: "set" | "add" | "remove",
	Source: "edit" | "api",
}

export type OnValueChangedOptions = {
	Source: ("edit" | "api" | "any")?,
}

-- Value Watcher Types
export type ValueWatcherEntry = {
	callback: (newValue: any, oldValue: any, info: DataEditedInfo) -> (),
	source: "edit" | "api" | "any",
}

export type ValueWatchers = {
	[string]: { ValueWatcherEntry },
}

-- Filter Options State
export type FilterOptionsState = {
	Key: FilterOptions?,
	Value: FilterOptions?,
}

-- Search State
export type SearchState = {
	Query: string?,
	Options: SearchOptions?,
	Results: { SearchResult },
	CurrentIndex: number,
	HighlightedAssociation: Association?,
}

-- Diff Types
export type DiffStatus = "added" | "removed" | "modified" | "unchanged"

export type DiffEntry = {
	Status: DiffStatus,
	OldValue: any?, -- Value in target viewer (nil if added)
	NewValue: any?, -- Value in source viewer (nil if removed)
	ChildDiffs: { [any]: DiffEntry }?, -- For tables, nested diff info
}

export type DiffState = {
	Active: boolean,
	TargetViewer: any?, -- Reference to the target TableEditor
	TargetViewerId: string?, -- ID of target viewer for display
	DiffData: { [string]: DiffEntry }, -- Path string -> DiffEntry
	OriginalData: any?, -- Original data before diff mode (to restore)
	SelectionMode: boolean, -- Whether we're currently selecting a viewer
	SelectionOverlays: { [string]: any }, -- Viewer highlights during selection (TextButton/GuiButton)
	EscapeConnection: RBXScriptConnection?, -- Connection for escape key during selection
	TargetDestroyConnection: RBXScriptConnection?, -- Connection to detect target viewer destruction
	Stats: { Added: number, Removed: number, Modified: number }?, -- Diff statistics
}

--[[
	TableEditor - Public API Type
	
	This is the public interface for TableEditor instances.
	Use this type when you need to reference a TableEditor in your code.
]]
export type TableEditor = {
	-- Public Properties
	Data: Table,
	Options: ViewerOptionsInternal,
	OnDataEdited: Signal<DataEditedInfo>,

	-- Core Methods
	Update: (self: TableEditor, newData: Table) -> (),
	Patch: (self: TableEditor, patch: Table) -> (),
	GetUI: (self: TableEditor) -> TableEditorGui?,
	GetData: (self: TableEditor) -> Table,
	GetAssociations: (self: TableEditor) -> { [string]: Association },
	Destroy: (self: TableEditor) -> (),

	-- Linking
	Link: (self: TableEditor, viewer: TableEditor) -> (),
	Unlink: (self: TableEditor, viewer: TableEditor) -> (),

	-- Freeze/Snapshot
	Freeze: (self: TableEditor) -> (),
	Unfreeze: (self: TableEditor) -> (),
	IsFrozen: (self: TableEditor) -> boolean,
	Snapshot: (self: TableEditor, title: string?) -> TableEditor,

	-- Focus
	FocusTable: (self: TableEditor, path: { any }) -> TableEditor?,

	-- Export
	ExportToJson: (self: TableEditor) -> string,
	ExportToLua: (self: TableEditor) -> string,

	-- Data Manipulation
	AddRow: (self: TableEditor, path: { any }, key: any, value: any) -> boolean,
	RemoveRow: (self: TableEditor, path: { any }, key: any) -> boolean,
	SetValue: (self: TableEditor, path: { any }, value: any) -> boolean,
	GetValue: (self: TableEditor, path: { any }) -> any,
	ScrollToPath: (self: TableEditor, path: { any }) -> (),

	-- Value Change Events
	OnValueChanged: (
		self: TableEditor,
		path: { any }?,
		callback: (newValue: any, oldValue: any, info: DataEditedInfo) -> (),
		options: OnValueChangedOptions?
	) -> SignalConnection,

	-- Visibility
	Show: (self: TableEditor) -> (),
	Hide: (self: TableEditor) -> (),
	Toggle: (self: TableEditor) -> (),
	IsVisible: (self: TableEditor) -> boolean,
	Collapse: (self: TableEditor) -> (),
	Minimize: (self: TableEditor) -> (),
	Restore: (self: TableEditor) -> (),
	IsMinimized: (self: TableEditor) -> boolean,
	IsCollapsed: (self: TableEditor) -> boolean,

	-- Entry Expansion
	ExpandPath: (self: TableEditor, path: { any }) -> boolean,
	CollapsePath: (self: TableEditor, path: { any }) -> boolean,
	TogglePath: (self: TableEditor, path: { any }) -> boolean,
	ExpandAllEntries: (self: TableEditor) -> (),
	CollapseAllEntries: (self: TableEditor) -> (),
	ExpandToDepth: (self: TableEditor, depth: number) -> (),
	IsPathExpanded: (self: TableEditor, path: { any }) -> boolean?,

	-- Size
	AutoSize: (self: TableEditor) -> (),
	ExpandToMax: (self: TableEditor) -> (),

	-- Options
	SetOption: (self: TableEditor, key: string, value: any) -> (),
	GetOption: (self: TableEditor, key: string) -> any,

	-- Sorting
	SetSortMode: (self: TableEditor, mode: SortMode) -> (),
	GetSortMode: (self: TableEditor) -> SortMode,

	-- Search
	Search: (self: TableEditor, query: string, options: SearchOptions?) -> { SearchResult },
	FindNext: (self: TableEditor) -> SearchResult?,
	FindPrevious: (self: TableEditor) -> SearchResult?,
	ClearSearch: (self: TableEditor) -> (),
	GetSearchResults: (self: TableEditor) -> { SearchResult },
	GetCurrentSearchIndex: (self: TableEditor) -> number?,
	GetSearchResultCount: (self: TableEditor) -> number,
	GoToSearchResult: (self: TableEditor, index: number) -> boolean,

	-- Filtering
	SetKeyFilter: (self: TableEditor, filters: { string }?, options: FilterOptions?) -> (),
	SetValueFilter: (self: TableEditor, filters: { string }?, options: FilterOptions?) -> (),
	SetTypeFilter: (self: TableEditor, types: { string }?) -> (),
	SetTypeExclusion: (self: TableEditor, types: { string }?) -> (),
	ClearAllFilters: (self: TableEditor) -> (),
	GetActiveFilters: (
		self: TableEditor
	) -> {
		KeyFilters: { string },
		ValueFilters: { string },
		TypeFilters: { string },
		TypeExclusions: { string },
	},
	GetFilterMatchCount: (self: TableEditor) -> number,

	-- Diff Mode
	StartDiffSelection: (self: TableEditor) -> (), -- Enter viewer selection mode
	CancelDiffSelection: (self: TableEditor) -> (), -- Cancel viewer selection
	StartDiff: (self: TableEditor, targetViewer: TableEditor) -> boolean, -- Start diff with target
	StopDiff: (self: TableEditor) -> (), -- Exit diff mode
	RefreshDiff: (self: TableEditor) -> boolean, -- Refresh diff comparison
	IsInDiffMode: (self: TableEditor) -> boolean, -- Check if in diff mode
	IsInDiffSelectionMode: (self: TableEditor) -> boolean, -- Check if in selection mode
	GetDiffTarget: (self: TableEditor) -> TableEditor?, -- Get the target viewer
	GetDiffStats: (self: TableEditor) -> { Added: number, Removed: number, Modified: number }?, -- Get diff statistics
}

--[[
	TableEditorInternal - Internal type with all private fields and methods
	
	This type is used internally by the module implementation.
	It extends TableEditor with all private state and methods.
	Use this type when implementing internal methods that need
	access to private fields.
]]
export type TableEditorInternal = TableEditor & {
	-- Private Methods
	_SetupKeybindings: (self: TableEditorInternal) -> (),
	_UpdateLink: (self: TableEditorInternal, skipBroadcast: boolean?) -> (),
	_NotifySameDataViewers: (self: TableEditorInternal, pathString: string, oldValue: any, newValue: any) -> (),
	_NotifySameDataViewersStructuralChange: (self: TableEditorInternal) -> (),
	_CreateDiffBar: (
		self: TableEditorInternal,
		targetViewer: TableEditorInternal,
		addedCount: number,
		removedCount: number,
		modifiedCount: number
	) -> (),
	_FormatFieldKey: (self: TableEditorInternal, key: any) -> string,
	_FormatFieldValue: (self: TableEditorInternal, value: any, association: Association?) -> string,
	_CreateBaseUI: (self: TableEditorInternal) -> TableEditorGui,
	_CreateOptionsMenu: (self: TableEditorInternal, menu: Frame) -> (),
	_SetupBaseUIEvents: (
		self: TableEditorInternal,
		frame: TableEditorGui,
		header: Frame,
		footer: Frame,
		viewer: Frame,
		optionsMenu: Frame
	) -> (),
	_CreateEntry: (self: TableEditorInternal, association: Association) -> EntryGui,
	_GetValueColor: (self: TableEditorInternal, association: Association) -> Color3,
	_GetAssociationPath: (self: TableEditorInternal, association: Association) -> { any },
	_LoadChildAssociations: (self: TableEditorInternal, parentAssociation: Association, skipFirst: boolean?) -> (),
	_GetTableRefPath: (self: TableEditorInternal, tbl: Table, visited: { [Table]: string }) -> string?,
	_GetAssociationPathString: (self: TableEditorInternal, association: Association) -> string,
	_UpdateFiltersAndExclusions: (self: TableEditorInternal, rootOverride: { Association }?) -> (),
	_HighlightSearchResult: (self: TableEditorInternal, result: SearchResult) -> (),
	_ClearSearchHighlight: (self: TableEditorInternal) -> (),
	_UpdateAssociations: (self: TableEditorInternal, lastData: Table?) -> (),
	_ProcessRemovals: (
		self: TableEditorInternal,
		diff: Table,
		parentPath: string,
		visited: { [Table]: boolean }?
	) -> (),
	_UpdateAssociationsFromPatch: (self: TableEditorInternal, patch: Table, parentPath: string) -> (),
	_UpdateEntryUI: (self: TableEditorInternal, association: Association) -> (),
	_RefreshAllEntryUIs: (self: TableEditorInternal) -> (),
	_UpdateEditableState: (self: TableEditorInternal) -> (),
	_FlashEntry: (self: TableEditorInternal, association: Association, color: Color3?) -> (),
	_FlashEntryMultiple: (self: TableEditorInternal, association: Association, color: Color3?, times: number?) -> (),
	_UpdateOrdering: (self: TableEditorInternal) -> (),
	_FireValueWatchers: (self: TableEditorInternal, editInfo: DataEditedInfo) -> (),
	_GetChildAssociations: (self: TableEditorInternal, parent: Association?) -> { Association },
	_UnloadChildrenGuis: (self: TableEditorInternal, association: Association) -> (),
	_IsEntryInView: (self: TableEditorInternal, association: Association) -> boolean,
	_ProcessPendingSearchFlashes: (self: TableEditorInternal) -> (),
	_QueueSearchFlash: (self: TableEditorInternal, association: Association, color: Color3) -> (),
	_ClearPendingSearchFlashes: (self: TableEditorInternal) -> (),
	_ReturnEntryToPool: (self: TableEditorInternal, entry: Frame) -> (),
	_CancelEntryTooltipThreads: (self: TableEditorInternal, entry: Frame) -> (),
	_DestroyEntryRecursive: (self: TableEditorInternal, entry: Frame) -> (),
	_UpdateSingleAssociation: (self: TableEditorInternal, pathString: string, oldValue: any, newValue: any) -> (),
	_SetAssociationExpanded: (
		self: TableEditorInternal,
		association: Association,
		state: boolean,
		recursive: boolean?
	) -> boolean,
	_GetAssociationExpansionState: (self: TableEditorInternal, association: Association) -> boolean,
	_SetDebugMode: (self: TableEditorInternal, enabled: boolean) -> (),

	-- Diff Mode Private Methods
	_EnterDiffMode: (self: TableEditorInternal, targetViewer: TableEditorInternal) -> (),
	_ExitDiffMode: (self: TableEditorInternal) -> (),
	_ComputeDiff: (self: TableEditorInternal, sourceData: Table, targetData: Table) -> { [string]: DiffEntry },
	_GetDiffStatusForPath: (self: TableEditorInternal, pathStr: string) -> DiffStatus?,
	_UpdateDiffUI: (self: TableEditorInternal) -> (),
	_CreateDiffSelectionOverlays: (self: TableEditorInternal) -> (),
	_ClearDiffSelectionOverlays: (self: TableEditorInternal) -> (),
	_RefreshFreezeButtonStates: (self: TableEditorInternal) -> (),

	-- Internal State
	_id: string,
	_associations: Associations,
	_childrenIndex: { [Association]: { Association } },
	_keyFilters: { string },
	_valueFilters: { string },
	_typeFilters: { string },
	_typeExclusions: { string },
	_filterCombineMode: ("and" | "or")?,
	_filterMatchCount: number,
	_filterOptions: FilterOptionsState,
	_searchState: SearchState,
	_ui: TableEditorGui?,
	_frozen: boolean,
	_pendingUpdates: { Table }?,
	_visible: boolean,
	_minimized: boolean,
	_collapsed: boolean,
	_tableRefs: { [Table]: string },
	_linkGroupId: number?,
	_inLinkMode: boolean?,
	_rootViewer: TableEditorInternal?,
	_rootPath: { any }?,
	_childViewers: { [string]: TableEditorInternal },
	_lastSize: UDim2?,
	_pendingSearchFlashes: { [Association]: Color3 },
	_flashedAssociations: { [Association]: boolean },
	_linkModeConnection: RBXScriptConnection?, -- Dynamic connection, managed separately
	_linkModeHighlights: { [string]: Frame },
	_isFiltering: boolean?,
	_flashThread: thread?,
	_guiToAssociation: { [Frame]: Association },
	_valueWatchers: ValueWatchers,
	_onDataEditedCallbacks: { (info: DataEditedInfo) -> () },
	_debugMode: boolean?,
	_trove: any, -- Trove for connection cleanup

	-- Diff Mode State
	_diffState: DiffState,
	_snapshots: { TableEditorInternal },
	_parentViewer: TableEditorInternal?,
	_frozenValues: { [string]: any },
}

--[[
	TableEditorImpl - Module implementation type
	
	This is the type of the TableEditor module itself (what you get from require).
	Use this type for the return value of require(TableEditor).
]]
export type ServerViewTarget = Player | { Player } | "all"

export type TableEditorImpl = {
	-- Core constructor
	new: (data: Table, options: ViewerOptions?) -> TableEditor,

	-- Quick View API (client-side)
	View: (name: string, data: Table?, options: ViewerOptions?) -> TableEditor,
	GetQuickView: (name: string) -> TableEditor?,
	GetAllQuickViews: () -> { [string]: TableEditor },
	DestroyQuickView: (name: string) -> boolean,
	DestroyAllQuickViews: () -> number,

	-- Server View API (server-side only)
	-- Sends a view request to specified clients
	-- Returns a dictionary of player names to whether the request was successfully sent
	ServerView: (
		players: ServerViewTarget,
		name: string,
		data: Table?,
		options: ViewerOptions?
	) -> { [string]: boolean },
}

-- Module return (empty table, types are exported)
return {}
