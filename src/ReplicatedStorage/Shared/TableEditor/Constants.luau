--!strict
--[[
	Constants and default settings for the TableEditor module.
	Modify these values to change default behavior without touching the main code.
]]

--- Imports ---
local Types = require(script.Parent.Types)

--- Types ---
type ViewerOptionsInternal = Types.ViewerOptionsInternal
type SortMode = Types.SortMode

--- Variables ---

-- Special key used to mark entries for removal in patch operations
local REMOVAL_KEY = "M\20k\17\30\16\11\14" -- Obfuscated "Mrkd4Del"

-- Icon sprite sheet asset ID
local ICON_SHEET = "rbxassetid://100203647121460"

-- Position offset in pixels for cascading new viewers
local POSITION_OFFSET = 30

-- Cell size for grid-based position calculations
local CELL_SIZE = 100
local CELL_MULTIPLIER = 10000

-- Default font families
local DEFAULT_KEY_FONT =
	Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)

local DEFAULT_VALUE_FONT =
	Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)

local DEFAULT_HEADER_FONT =
	Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)

local DEFAULT_BOLD_FONT =
	Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

-- Type aliases for fuzzy type matching in filters
local TYPE_ALIASES: { [string]: { string } } = {
	boolean = { "bool", "b", "boolean", "bo", "boo", "boole", "boolea" },
	number = { "num", "n", "number", "int", "float", "integer", "nu", "numb", "numbe" },
	string = { "str", "s", "string", "text", "st", "stri", "strin" },
	table = { "tbl", "t", "table", "tab", "array", "dict", "dictionary", "ta", "tabl" },
	["function"] = { "func", "f", "function", "fn", "method", "fu", "fun", "funct", "functi", "functio" },
	Instance = { "inst", "i", "instance", "obj", "object", "in", "ins", "insta", "instan", "instanc" },
}

-- Default viewer options
local DEFAULT_OPTIONS: ViewerOptionsInternal = {
	-- Basic Options
	Title = "Table Editor",
	Parent = nil,

	-- Display Options
	AppendWrenchEmoji = false,
	ShowTableValue = true,
	ShowExtraAnimationTrackData = true,
	MinKeyPixels = 50,

	-- Size Options
	StartingSize = Vector2.new(320, 420),
	MinSize = Vector2.new(200, 44),
	MaxSize = Vector2.new(8192, 8192),
	AutoSizeToContent = false,
	AutoSizeMaxHeight = 600,
	AutoSizeMode = "fixed",

	-- Position Options
	ViewerPosition = UDim2.fromScale(0.25, 0.375),
	RememberPositionStates = false,
	OpenPosition = UDim2.fromScale(0.25, 0.375),
	ClosedPosition = UDim2.fromScale(0.01, 0.01),

	-- Behavior Options
	Expanded = false,
	DefaultCollapsed = false,
	DefaultMinimized = false,
	Editable = false,
	NumberPrecision = -1,
	FilterOnType = false,
	CaseSensitive = false,
	FuzzyMatching = false,
	FuzzyThreshold = 0.4,
	OrderTablesBasedOffNumberOfElements = false,
	LazyLoadChildren = true,

	-- Font Options
	KeyFontFace = DEFAULT_KEY_FONT,
	ValueFontFace = DEFAULT_VALUE_FONT,
	TextTruncateType = Enum.TextTruncate.SplitWord,

	-- Recursive Options
	DetectRecursiveTables = true,
	RecursiveDisplayFormat = "↻ Recursive: %s",
	DetectDuplicateReferences = true,
	DuplicateDisplayFormat = "⟳ Ref: %s",
	MaxRecursionDepth = 50,

	-- Keybinding Options
	ToggleKeybind = nil,
	FocusKeybind = nil,

	-- Export Options
	EnableExport = true,
	ExportFormat = "both",

	-- Visual Options
	ShowTooltips = true,
	TooltipDelay = 0.5,
	FlashOnChange = true,
	FlashColor = Color3.fromRGB(100, 200, 100),
	FlashDuration = 0.3,
	FlashOnRemoval = true,
	FlashRemovalColor = Color3.fromRGB(255, 100, 100),
	FlashOnDecrement = true,
	FlashOnBooleanFalse = true,
	FloatRelevantResults = true,
	FlashNestedResults = true,
	MaxFloatResults = 100,
	MaxConcurrentFlashes = 50,
	-- Additional Flash Colors
	FlashNavigationColor = Color3.fromRGB(100, 150, 255), -- Blue for navigation
	FlashSearchNestedColor = Color3.fromRGB(100, 150, 255), -- Blue for nested search results
	FlashSearchRootColor = Color3.fromRGB(255, 165, 0), -- Orange for root search results

	-- Performance Options
	UnloadDelay = 15, -- Delay in seconds before unloading collapsed children
	FilterDebounceDelay = 0.15,
	EnablePooling = true,
	MaxPoolSize = 20,

	-- Add Row Options
	ShowAddRowsWhileFiltering = false,
	ShowAddRowsWhileExcluding = false,

	-- Ordering
	SortMode = "type-then-alpha" :: SortMode,
	TypeOrdering = {
		boolean = 1,
		number = 2,
		string = 3,
		Instance = 4,
		Other = 5,
		["function"] = 6,
		table = 7,
	},
	SyntaxHighlighting = {
		Default = Color3.fromRGB(200, 200, 200),
		boolean = Color3.fromRGB(86, 156, 214),
		number = Color3.fromRGB(181, 206, 168),
		string = Color3.fromRGB(206, 145, 120),
		table = Color3.fromRGB(224, 167, 86),
		["function"] = Color3.fromRGB(197, 134, 192),
		Instance = Color3.fromRGB(78, 201, 176),
		Other = Color3.fromRGB(86, 156, 214),
		RecursiveRef = Color3.fromRGB(255, 100, 100),
		DuplicateRef = Color3.fromRGB(255, 180, 100),
	},

	-- Verbose Mode Options
	-- Global verbose toggles for keys and values
	VerboseKeys = false,
	VerboseValues = false,
	-- Per-type verbose settings for keys (only used if VerboseKeys is true)
	VerboseKeyTypes = {
		Instance = true, -- Show GetFullName() for Instance keys
		["function"] = true, -- Show memory address for function keys
		thread = true, -- Show memory address for thread keys
		table = true, -- Show item count for table keys
	},
	-- Per-type verbose settings for values (only used if VerboseValues is true)
	VerboseValueTypes = {
		Instance = true, -- Show GetFullName() for Instance values
		["function"] = true, -- Show memory address for function values
		thread = true, -- Show memory address for thread values
		table = false, -- Show item count for table values (already shown by default)
	},
}

-- UI Color Palette
local COLORS = {
	-- Backgrounds
	MainBackground = Color3.fromRGB(25, 25, 28),
	HeaderBackground = Color3.fromRGB(35, 35, 40),
	FooterBackground = Color3.fromRGB(35, 35, 40),
	EntryBackground = Color3.fromRGB(40, 40, 45),
	InputBackground = Color3.fromRGB(45, 45, 50),
	ButtonBackground = Color3.fromRGB(55, 55, 60),
	ButtonHover = Color3.fromRGB(70, 70, 75),
	OptionsMenuBackground = Color3.fromRGB(40, 40, 45),
	TooltipBackground = Color3.fromRGB(50, 50, 55),
	BadgeBackground = Color3.fromRGB(50, 50, 55),

	-- Borders & Strokes
	MainBorder = Color3.fromRGB(60, 60, 65),
	OptionsBorder = Color3.fromRGB(70, 70, 75),
	TooltipBorder = Color3.fromRGB(80, 80, 85),
	Separator = Color3.fromRGB(60, 60, 65),

	-- Text
	HeaderText = Color3.fromRGB(220, 220, 225),
	LabelText = Color3.fromRGB(180, 180, 185),
	SubLabelText = Color3.fromRGB(140, 140, 145),
	PlaceholderText = Color3.fromRGB(100, 100, 105),
	ButtonText = Color3.fromRGB(200, 200, 205),
	IconDefault = Color3.fromRGB(200, 200, 200),
	IconSubtle = Color3.fromRGB(150, 150, 155),
	IconResize = Color3.fromRGB(100, 100, 105),

	-- Semantic Colors
	FilterText = Color3.fromRGB(100, 200, 100),
	ExclusionText = Color3.fromRGB(255, 100, 100),
	LinkActive = Color3.fromRGB(100, 200, 255),
	LinkInactive = Color3.fromRGB(180, 180, 180),
	FreezeActive = Color3.fromRGB(100, 180, 255),
	FreezeLive = Color3.fromRGB(100, 200, 100),
	CloseButton = Color3.fromRGB(255, 80, 80),
	AddButton = Color3.fromRGB(60, 120, 60),
	AddButtonText = Color3.fromRGB(150, 255, 150),
	DeleteIcon = Color3.fromRGB(255, 100, 100),
	DesyncIcon = Color3.fromRGB(255, 100, 100),
	BadgeSynced = Color3.fromRGB(100, 255, 100),
	BadgeDesynced = Color3.fromRGB(255, 100, 100),
	ToggleOn = Color3.fromRGB(80, 160, 80),
	ToggleOff = Color3.fromRGB(60, 60, 65),
	ToggleIndicator = Color3.fromRGB(220, 220, 220),
	SearchHighlight = Color3.fromRGB(255, 200, 0),
	LinkHighlightLinked = Color3.fromRGB(15, 24, 15),
	LinkHighlightUnlinked = Color3.fromRGB(100, 200, 255),

	-- Scrollbar
	ScrollBar = Color3.fromRGB(80, 80, 85),

	-- Diff Mode (VS Code style)
	DiffAdded = Color3.fromRGB(35, 134, 54), -- Green for additions
	DiffAddedBackground = Color3.fromRGB(35, 134, 54), -- Green background tint
	DiffRemoved = Color3.fromRGB(248, 81, 73), -- Red for removals
	DiffRemovedBackground = Color3.fromRGB(248, 81, 73), -- Red background tint
	DiffModified = Color3.fromRGB(227, 179, 65), -- Yellow for modifications
	DiffModifiedBackground = Color3.fromRGB(227, 179, 65), -- Yellow background tint
	DiffSelectionHighlight = Color3.fromRGB(100, 180, 255), -- Blue highlight for viewer selection
	DiffHeaderIndicator = Color3.fromRGB(100, 200, 255), -- Blue header indicator for diff mode
}

-- UI Sizes
local SIZES = {
	-- Main Frame
	HeaderHeight = 28,
	FooterHeight = 28,
	MinimizedSize = 28,
	CornerRadius = 8,

	-- Buttons
	HeaderButtonSize = 24,
	FooterButtonSize = 20,
	IconSize = 14,
	SmallIconSize = 12,
	TinyIconSize = 10,

	-- Inputs
	InputHeight = 18,
	FilterModeButtonWidth = 22,

	-- Entry
	EntryHeight = 22,
	EntryCornerRadius = 4,
	IndentPerLevel = 16,
	ExpansionButtonSize = 16,
	FocusButtonSize = 14,
	DeleteButtonSize = 14,

	-- Spacing
	Padding = 4,
	SmallPadding = 2,
	LargePadding = 8,

	-- Tooltip
	TooltipMaxWidth = 400,
	TooltipMaxHeight = 200,
	TooltipCornerRadius = 4,

	-- Options Menu
	OptionsMenuWidth = 180,
	OptionsToggleHeight = 24,
	OptionsButtonHeight = 24,
	OptionsCornerRadius = 6,

	-- Ghost Row
	GhostRowKeyWidth = 80,
	GhostRowAddButtonSize = 18,

	-- Stroke
	MainStrokeThickness = 1,
	OptionsStrokeThickness = 1,
	TooltipStrokeThickness = 1,
}

-- Transparency values
local TRANSPARENCY = {
	MainBackground = 0.05,
	HeaderBackground = 0.1,
	FooterBackground = 0.1,
	EntryBackground = 0.6,
	GhostRowBackground = 0.8,
	GhostRowHover = 0.6,
	InputBackground = 0.3,
	AddButtonDefault = 0.3,
	AddButtonHover = 0.1,
	SearchHighlight = 0.7,
	LinkHighlight = 0.9,
	LinkHighlightHover = 0.7,
	LinkHighlightStroke = 0.3,
	LinkHighlightStrokeHover = 0,

	-- Diff Mode
	DiffGutter = 0, -- Fully opaque gutter indicator
	DiffBackground = 0.85, -- Subtle background tint
	DiffSelectionOverlay = 0.7, -- Viewer selection overlay
}

--- Constants ---
local Constants = {
	-- Keys
	REMOVAL_KEY = REMOVAL_KEY,

	-- Assets
	ICON_SHEET = ICON_SHEET,

	-- Positioning
	POSITION_OFFSET = POSITION_OFFSET,
	CELL_SIZE = CELL_SIZE,
	CELL_MULTIPLIER = CELL_MULTIPLIER,

	-- Fonts
	DEFAULT_KEY_FONT = DEFAULT_KEY_FONT,
	DEFAULT_VALUE_FONT = DEFAULT_VALUE_FONT,
	DEFAULT_HEADER_FONT = DEFAULT_HEADER_FONT,
	DEFAULT_BOLD_FONT = DEFAULT_BOLD_FONT,

	-- Type Matching
	TYPE_ALIASES = TYPE_ALIASES,

	-- Options
	DEFAULT_OPTIONS = DEFAULT_OPTIONS,

	-- UI
	COLORS = COLORS,
	SIZES = SIZES,
	TRANSPARENCY = TRANSPARENCY,
}

return table.freeze(Constants)
