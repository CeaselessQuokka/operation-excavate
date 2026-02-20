# Install Tooling
rokit install

# Install Wally Packages
wally install

# Generate Sourcemap (this is used by Luau-LSP and Wally Package Types)
rojo sourcemap "default.project.json" --output "sourcemap.json"

# Link Types in Packages/ (this allows types to be used when required)
wally-package-types --sourcemap "sourcemap.json" "Packages/"

# Link Types in ServerPackages/ (this allows types to be used when required)
wally-package-types --sourcemap "sourcemap.json" "ServerPackages/"
