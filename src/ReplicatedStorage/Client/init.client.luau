--!strict
--- Services ---
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Imports ---
local Jabby = require(ReplicatedStorage.Packages.Jabby)
local Knit = require(ReplicatedStorage.Packages.Knit)

local LoadingHelper = require(ReplicatedStorage.Shared.Helpers.LoadingHelper)

local TableEditor = require(ReplicatedStorage.Shared.TableEditor) -- Keep so the client connections can be made

--- Client Initialization ---
-- Load Knit controllers.
LoadingHelper.LoadModules(script.Controllers)
LoadingHelper.LoadModules(script.Systems)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Systems, true)
Knit.Start({ ServicePromises = false }):expect()

-- Load client and shared components.
LoadingHelper.LoadModules(script.Components)
LoadingHelper.LoadModules(ReplicatedStorage.Shared.Components)

-- Setup Jabby.
local client = Jabby.obtain_client()
local function create_widget(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return
	end
	client.spawn_app(client.apps.home, nil)
end
ContextActionService:BindAction("Open Jabby Home", create_widget, false, Enum.KeyCode.F4)
