--!strict
--- Loading Helper ---
local LoadingHelper = {}

-- Loads modules deeply, but does not look into other modules.
-- Modules are ignored if their "Enabled" attribute is false.
-- Modules are ignored if they end in ".disabled".
function LoadingHelper.LoadModules(root: Instance)
	if root.ClassName == "ModuleScript" then
		if root:GetAttribute("Enabled") == false or root.Name:lower():find("%.disabled$") then
			return
		end

		local success: boolean, err: string = pcall(require, root)
		if not success then
			warn(`[{script.Name}] Failed to load module "{root.Name}": {debug.traceback(err)}`)
		end
	else
		for _, module in root:GetChildren() do
			LoadingHelper.LoadModules(module)
		end
	end
end

return table.freeze(LoadingHelper)
