--!strict
--- Loading Helper ---
local LoadingHelper = {}

-- Loads modules deeply, but does not look into other modules.
-- Modules are ignored if their "Enabled" attribute is false.
-- Modules are ignored if they end in ".disabled".
-- If "forceIn" is true, then it will force search inside the root's children,
--- even if is a ModuleScript (and will NOT load root).
function LoadingHelper.LoadModules(root: Instance, forceIn: boolean?)
	if not forceIn and root.ClassName == "ModuleScript" then
		if root:GetAttribute("Enabled") == false or root.Name:lower():find("%.disabled") then
			return
		end

		xpcall(require, function(err: string)
			warn(`[{script.Name}] An error occurred while requiring module "{root.Name}": {debug.traceback(err)}`)
		end, root)
	else
		for _, module in root:GetChildren() do
			LoadingHelper.LoadModules(module)
		end
	end
end

return table.freeze(LoadingHelper)
