--!strict
-- The package's Config, now read from rules/wallrun.toml (CLAUDE.md: every tunable number lives in rules/). Same shape
-- as the package's original Config, so the package code reads it unchanged.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local r = require(ReplicatedStorage:WaitForChild("Rules"):WaitForChild("wallrun")) :: any

export type SoundDefinition = {
	Id: number,
	Volume: number,
	PitchVariance: number?,
	MaxDistance: number?,
}

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local Config = {
	WallDetectionDistance = r.detect.distance :: number,
	RayForwardOffset = r.detect.rayForwardOffset :: number,
	MaxWallNormalY = r.detect.maxWallNormalY :: number,

	WallRunSpeed = r.run.fallbackSpeed :: number,
	WallRunVerticalSpeed = r.run.verticalSpeed :: number,
	MaxRunDuration = r.run.maxDuration :: number,
	WallSnapDistance = r.run.snapDistance :: number,
	MaxSnapCorrection = r.run.maxSnapCorrection :: number,
	SnapKp = r.run.snapKp :: number,
	SnapKi = r.run.snapKi :: number,
	SnapKd = r.run.snapKd :: number,
	TangentSmoothTime = r.run.tangentSmoothTime :: number,
	TangentSmoothMaxSpeed = r.run.tangentSmoothMaxSpeed :: number,
	CorrectionSmoothTime = r.run.correctionSmoothTime :: number,
	CorrectionSmoothMaxSpeed = r.run.correctionSmoothMaxSpeed :: number,
	OrientationResponsiveness = r.run.orientationResponsiveness :: number,
	RequireAirborneToStart = r.run.requireAirborne == 1,
	MinStartHeight = r.run.minStartHeight :: number,
	GroundCheckDistance = r.run.groundCheckDistance :: number,
	GroundGraceTime = r.run.groundGraceTime :: number,
	ReattachCooldown = r.run.reattachCooldown :: number,

	WallJumpAwayForce = r.jump.awayForce :: number,
	WallJumpUpForce = r.jump.upForce :: number,
	WallJumpForwardKeep = r.jump.forwardKeep :: number,

	CameraTiltAngle = r.camera.tiltAngle :: number,
	CameraTiltSmoothTime = r.camera.tiltSmoothTime :: number,
	CameraTiltMaxSpeed = r.camera.tiltMaxSpeed :: number,
	CameraJumpTiltImpulse = r.camera.jumpTiltImpulse :: number,

	FovZoomAmount = r.camera.fovZoom :: number,
	FovSmoothTime = r.camera.fovSmoothTime :: number,
	FovMaxSpeed = r.camera.fovMaxSpeed :: number,
	FovJumpImpulse = r.camera.fovJumpImpulse :: number,

	ShakeAmplitude = r.camera.shakeAmplitude :: number,
	ShakeFrequency = r.camera.shakeFrequency :: number,
	ShakeFadeOutTime = r.camera.shakeFadeOutTime :: number,
	ShakePositionInfluence = vec(r.camera.shakePosition),
	ShakeRotationInfluence = vec(r.camera.shakeRotation),

	AnimationFadeTime = r.animation.fadeTime :: number,

	TrailDuration = r.trail.duration :: number,
	TrailGroundGrace = r.trail.groundGrace :: number,
	TrailLimbs = { "Right Arm", "Left Arm", "Right Leg", "Left Leg" },
	StepEvery = r.sound.stepEvery :: number,

	Sounds = {
		Step = { Id = r.sound.stepId, Volume = r.sound.stepVolume, PitchVariance = r.sound.stepPitchVariance },
	} :: { [string]: SoundDefinition },
}

export type ConfigType = typeof(Config)

return Config
