-- Tiny test runner for Lune. Runs every tests/*.spec.luau file.
-- Each spec returns { ["test name"] = function(t) ... end }.
-- Usage: lune run tests/run
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local function loadRules(name: string)
	return serde.decode("toml", fs.readFile("rules/" .. name .. ".toml"))
end

local t = {}
function t.eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(expected), tostring(actual)), 2)
	end
end
function t.ok(cond, msg)
	if not cond then
		error(msg or "expected true", 2)
	end
end
t.rules = loadRules

local passed, failed = 0, 0
local files = fs.readDir("tests")
table.sort(files)
for _, file in files do
	if string.sub(file, -10) == ".spec.luau" then
		local spec = require("./" .. string.sub(file, 1, -6))
		local names = {}
		for name in spec do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local ok, err = pcall(spec[name], t)
			if ok then
				passed += 1
			else
				failed += 1
				print(string.format("FAIL  %s > %s\n      %s", file, name, tostring(err)))
			end
		end
	end
end

print(string.format("Tests: %d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
