--!strict
-- Collision groups, registered once on the server (they replicate to clients).
-- SlideBody: the upper body (Head, UpperTorso) while sliding. It does not collide with the world, so a
-- sliding player fits under low gaps; the lowered root part and lower torso still collide normally.
-- (Setting CanCollide doesn't work: the Humanoid forces it back on Head and torso every frame.)
local PhysicsService = game:GetService("PhysicsService")

local SLIDE_BODY = "SlideBody"

if not PhysicsService:IsCollisionGroupRegistered(SLIDE_BODY) then
	PhysicsService:RegisterCollisionGroup(SLIDE_BODY)
end
PhysicsService:CollisionGroupSetCollidable(SLIDE_BODY, "Default", false)
PhysicsService:CollisionGroupSetCollidable(SLIDE_BODY, SLIDE_BODY, false)
