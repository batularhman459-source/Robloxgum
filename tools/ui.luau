-- UI pipeline. One spec in, three things out, all from the same source:
--   ui/build/<Name>.preview.png   preview of all 4 screen sizes
--   ui/build/<Name>.rbxm          the actual UI file (drag into Studio to inspect)
--   the build script              src/client/UiMount + src/shared/ui/UiBuilder build it in game
--
-- Usage:
--   lune run tools/ui check [Name]   validate + check (gate 5, no files written)
--   lune run tools/ui build [Name]   check, then write preview + .rbxm + report
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local UiBuilder = require("../src/shared/ui/UiBuilder")
local UiCheck = require("./UiCheck")
local UiLayout = require("../src/shared/ui/UiLayout")
local Preview = require("./Preview")

local cmd = process.args[1] or "check"
local only = process.args[2]

local function loadToml(path: string): any
	return serde.decode("toml", fs.readFile(path))
end

local function specNames(): { string }
	local names = {}
	for _, file in fs.readDir("ui/specs") do
		if string.sub(file, -5) == ".luau" then
			local name = string.sub(file, 1, -6)
			if not only or only == name then
				table.insert(names, name)
			end
		end
	end
	table.sort(names)
	return names
end

local LUNE_ENV = {
	Instance = roblox.Instance,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Vector2 = roblox.Vector2,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	Font = roblox.Font,
	Enum = roblox.Enum,
}

local function findEdge(): string?
	local candidates = {
		process.env.EDGE_PATH,
		"C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
		"C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
	}
	for _, p in candidates do
		if p and fs.isFile(p) then
			return p
		end
	end
	return nil
end

local icons = loadToml("ui/icons.toml")
local names = specNames()
if #names == 0 then
	print(if only then "No spec named " .. only else "No specs in ui/specs")
	process.exit(if only then 1 else 0)
end

local failedAny = false
for _, name in names do
	local spec = require("../ui/specs/" .. name)
	local theme = loadToml("ui/themes/" .. (spec.style or "house") .. ".toml")
	local problems = UiLayout.validate(spec, theme)
	if #problems > 0 then
		failedAny = true
		print("UI " .. name .. ": spec is invalid")
		for _, p in problems do
			print("  " .. p)
		end
		continue
	end

	local result = UiCheck.run(spec, theme, icons)
	local text = UiCheck.format(name, result)
	print(text)
	if #result.errors > 0 then
		failedAny = true
	end

	if cmd == "build" then
		if not fs.isDir("ui/build") then
			fs.writeDir("ui/build")
		end
		local cwd = string.gsub(process.cwd, "\\", "/")
		if string.sub(cwd, -1) ~= "/" then
			cwd ..= "/"
		end

		-- 1. The actual UI file.
		local gui = UiBuilder.build(spec, theme, icons, LUNE_ENV, UiLayout)
		fs.writeFile("ui/build/" .. name .. ".rbxm", roblox.serializeModel({ gui }))

		-- 2. The preview.
		local iconFiles = {}
		-- Every local PNG, uploaded or not, so new icons can be judged before uploading.
		if fs.isDir("ui/icons") then
			for _, file in fs.readDir("ui/icons") do
				if string.sub(file, -4) == ".png" then
					iconFiles[string.sub(file, 1, -5)] = "../icons/" .. file
				end
			end
		end
		local html, w, h = Preview.render(spec, theme, UiCheck.SCREENS, iconFiles, result.failed)
		local htmlPath = "ui/build/" .. name .. ".preview.html"
		local pngPath = cwd .. "ui/build/" .. name .. ".preview.png"
		fs.writeFile(htmlPath, html)
		fs.writeFile("ui/build/" .. name .. ".report.txt", text .. "\n")

		local edge = findEdge()
		if edge then
			local res = process.exec(edge, {
				"--headless=new",
				"--disable-gpu",
				"--hide-scrollbars",
				"--force-device-scale-factor=1",
				"--user-data-dir=" .. cwd .. "build/edge-profile",
				"--screenshot=" .. pngPath,
				"--window-size=" .. w .. "," .. h,
				"file:///" .. cwd .. htmlPath,
			})
			if fs.isFile(pngPath) then
				print("  wrote ui/build/" .. name .. ".preview.png, .rbxm, .report.txt")
			else
				print("  preview screenshot failed: " .. res.stderr)
				failedAny = true
			end
		else
			print("  Edge not found: open " .. htmlPath .. " in a browser (set EDGE_PATH to fix)")
		end
	end
end

process.exit(if failedAny then 1 else 0)
