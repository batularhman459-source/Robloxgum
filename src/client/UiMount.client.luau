--!strict
-- Builds every UI spec (ui/specs) into PlayerGui. Specs with mount = false are skipped;
-- code opens those itself with UiRuntime.mount("<Name>").
local UiRuntime = require(script.Parent:WaitForChild("UiRuntime"))

UiRuntime.mountAll()
