"""Writes the parkour animation specs (anim/specs/*.json) from shared poses.

  python anim/make_specs.py [--preview]

FK convention on the MrXen0 R15 rig (same as the roblox-animation skill's community rig):
limbs rest pointing down; X negative swings forward, Z positive swings to the character's right;
child angles compound with the parent. TORSO rotates the whole body around the root (leans it,
rolls it); UpTorso leans only the chest. Poses below use X positive = lean FORWARD for TORSO,
UpTorso and HEAD; game_axes() flips that on export to match what the game shows (see there).
Timing is Roblox timing (fast), 30 fps. Durations match rules/parkour.toml where a move has one.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "specs")
PREVIEW = "--preview" in sys.argv

FK_PROPS = {"ARM_IK_FK.L": 0.0, "ARM_IK_FK.R": 0.0, "LEG_IK_FK.L": 0.0, "LEG_IK_FK.R": 0.0}
BONES = [
    "TORSO", "UpTorso", "HEAD",
    "FK_UpperArm.L", "FK_LowerArm.L", "FK_UpperArm.R", "FK_LowerArm.R",
    "FK_UpperLeg.L", "FK_LowerLeg.L", "FK_Foot.L", "FK_UpperLeg.R", "FK_LowerLeg.R", "FK_Foot.R",
]


def pose(**rot):
    """Full pose: every listed bone gets a rotation (unlisted = rest), so keys never inherit by accident.
    Keyword names use _ for the dot: FK_UpperArm_L -> FK_UpperArm.L."""
    out = {}
    for bone in BONES:
        key = bone.replace(".", "_")
        out[bone] = {"rot": list(rot.get(key, (0, 0, 0)))}
    return out


def bone_name(key):
    """FK_LowerArm_L -> FK_LowerArm.L. Only the trailing side marker changes (a plain replace of
    "_L" also hit "_LowerArm" and produced FK.LowerArm.L, which the renderer caught)."""
    if key.startswith("FK_") and key[-2:] in ("_L", "_R"):
        return key[:-2] + "." + key[-1]
    return key


def merge(base, **changes):
    p = json.loads(json.dumps(base))
    for key, value in changes.items():
        p[bone_name(key)] = {"rot": list(value)}
    return p


# Shared poses -----------------------------------------------------------------------------------
STAND = pose()
AIR = pose(  # neutral airborne: arms a little out, knees soft
    FK_UpperArm_L=(-10, 0, -25), FK_LowerArm_L=(-25, 0, 0),
    FK_UpperArm_R=(-10, 0, 25), FK_LowerArm_R=(-25, 0, 0),
    FK_UpperLeg_L=(-20, 0, 0), FK_LowerLeg_L=(35, 0, 0),
    FK_UpperLeg_R=(-5, 0, 0), FK_LowerLeg_R=(15, 0, 0),
)
RUN_A = pose(  # right leg forward, left arm forward
    UpTorso=(14, 0, 0),
    FK_UpperArm_L=(-55, 0, -8), FK_LowerArm_L=(-70, 0, 0),
    FK_UpperArm_R=(40, 0, 8), FK_LowerArm_R=(-45, 0, 0),
    FK_UpperLeg_R=(-55, 0, 0), FK_LowerLeg_R=(25, 0, 0), FK_Foot_R=(-10, 0, 0),
    FK_UpperLeg_L=(35, 0, 0), FK_LowerLeg_L=(80, 0, 0), FK_Foot_L=(10, 0, 0),
)
RUN_B = pose(  # mirror of RUN_A
    UpTorso=(14, 0, 0),
    FK_UpperArm_R=(-55, 0, 8), FK_LowerArm_R=(-70, 0, 0),
    FK_UpperArm_L=(40, 0, -8), FK_LowerArm_L=(-45, 0, 0),
    FK_UpperLeg_L=(-55, 0, 0), FK_LowerLeg_L=(25, 0, 0), FK_Foot_L=(-10, 0, 0),
    FK_UpperLeg_R=(35, 0, 0), FK_LowerLeg_R=(80, 0, 0), FK_Foot_R=(10, 0, 0),
)
SLIDE = pose(  # body leaned back, lead leg straight out, back leg tucked under, hand trailing
    TORSO=(-38, 0, 0), UpTorso=(18, 0, 0), HEAD=(14, 0, 0),
    FK_UpperLeg_R=(-55, 0, 0), FK_LowerLeg_R=(0, 0, 0), FK_Foot_R=(-15, 0, 0),
    FK_UpperLeg_L=(-15, 0, -6), FK_LowerLeg_L=(105, 0, 0), FK_Foot_L=(20, 0, 0),
    FK_UpperArm_L=(35, 0, -35), FK_LowerArm_L=(-10, 0, 0),
    FK_UpperArm_R=(-60, 0, 20), FK_LowerArm_R=(-45, 0, 0),
)
TUCK = pose(  # knees to chest
    TORSO=(18, 0, 0), UpTorso=(12, 0, 0),
    FK_UpperLeg_L=(-105, 0, -4), FK_LowerLeg_L=(125, 0, 0), FK_Foot_L=(-20, 0, 0),
    FK_UpperLeg_R=(-105, 0, 4), FK_LowerLeg_R=(125, 0, 0), FK_Foot_R=(-20, 0, 0),
    FK_UpperArm_L=(-55, 0, -10), FK_LowerArm_L=(-70, 0, 0),
    FK_UpperArm_R=(-55, 0, 10), FK_LowerArm_R=(-70, 0, 0),
)
CROUCH = pose(  # hard landing impact: deep knees, one hand towards the ground
    TORSO=(22, 0, 0), UpTorso=(18, 0, 0), HEAD=(-12, 0, 0),
    FK_UpperLeg_L=(-70, 0, -10), FK_LowerLeg_L=(115, 0, 0), FK_Foot_L=(-45, 0, 0),
    FK_UpperLeg_R=(-70, 0, 10), FK_LowerLeg_R=(115, 0, 0), FK_Foot_R=(-45, 0, 0),
    FK_UpperArm_R=(-35, 0, 15), FK_LowerArm_R=(-10, 0, 0),
    FK_UpperArm_L=(-20, 0, -40), FK_LowerArm_L=(-30, 0, 0),
)


def wall_run(side):
    """Running along a wall on `side` (1 = wall on the right): run cycle tilted towards the wall,
    wall-side hand reaching out. The whole body tilts (TORSO Z) so it reads as running on the wall."""
    tilt = (0, 0, 22 * side)
    reach_arm = "FK_UpperArm_R" if side > 0 else "FK_UpperArm_L"
    a = merge(RUN_A, TORSO=tilt)
    b = merge(RUN_B, TORSO=tilt)
    a[bone_name(reach_arm)] = {"rot": [-20, 0, 75 * side]}
    b[bone_name(reach_arm)] = {"rot": [-30, 0, 70 * side]}
    return [(0.0, "smooth", a), (0.25, "smooth", b), (0.5, "smooth", a)]


SPECS = {
    "SlideIn": dict(duration=0.15, loop=False, keys=[(0.0, "in", RUN_A), (0.15, "out", SLIDE)]),
    "SlideHold": dict(duration=0.5, loop=True, keys=[(0.0, "smooth", SLIDE), (0.5, "smooth", SLIDE)]),
    "Vault": dict(duration=0.35, loop=False, keys=[
        (0.0, "in", RUN_A),
        (0.1, "in", merge(TUCK, TORSO=(28, 0, 0),
                          FK_UpperArm_L=(-75, 0, 0), FK_LowerArm_L=(0, 0, 0),  # hand planted on the box
                          FK_UpperArm_R=(-20, 0, 65))),
        (0.22, "out", merge(TUCK, TORSO=(18, 0, 0),
                            FK_UpperLeg_L=(-95, 0, 28), FK_UpperLeg_R=(-95, 0, 32),  # legs swing past the side
                            FK_UpperArm_L=(-40, 0, -10), FK_UpperArm_R=(-20, 0, 70))),
        (0.35, "smooth", RUN_B),
    ]),
    "WallRunL": dict(duration=0.5, loop=True, keys=wall_run(-1)),
    "WallRunR": dict(duration=0.5, loop=True, keys=wall_run(1)),
    "WallJump": dict(duration=0.3, loop=False, keys=[
        (0.0, "in", merge(TUCK, TORSO=(10, 0, 0))),
        (0.1, "out", pose(UpTorso=(-14, 0, 0), HEAD=(-10, 0, 0),
                          FK_UpperArm_L=(20, 0, -140), FK_UpperArm_R=(20, 0, 140),
                          FK_UpperLeg_L=(18, 0, -10), FK_LowerLeg_L=(20, 0, 0),
                          FK_UpperLeg_R=(25, 0, 10), FK_LowerLeg_R=(30, 0, 0))),
        (0.3, "smooth", AIR),
    ]),
    "DoubleJump": dict(duration=0.35, loop=False, keys=[
        (0.0, "in", AIR),
        (0.12, "out", TUCK),
        (0.35, "smooth", AIR),
    ]),
    # Forward roll: the whole body turns once around the root. Keys every 90 degrees so the
    # rotation can't take the short way back.
    "LandRoll": dict(duration=0.45, loop=False, keys=[
        (0.0, "in", merge(TUCK, TORSO=(20, 0, 0))),
        (0.11, "smooth", merge(TUCK, TORSO=(110, 0, 0))),
        (0.22, "smooth", merge(TUCK, TORSO=(200, 0, 0))),
        (0.33, "smooth", merge(TUCK, TORSO=(290, 0, 0))),
        (0.45, "out", RUN_A),
    ]),
    "HardLanding": dict(duration=0.35, loop=False, keys=[
        (0.0, "out", CROUCH),
        (0.2, "smooth", CROUCH),
        (0.35, "smooth", STAND),
    ]),
}


BODY_BONES = ("TORSO", "UpTorso", "HEAD")


def game_axes(bones):
    """Poses here are written with body-bone X POSITIVE = lean FORWARD (easy to read). On this rig
    the game shows the opposite: measured in Studio 2026-11-15, the slide (TORSO -38, meant to lean
    back) leaned forward and the vault leaned back. So body-bone X is flipped on export; limbs are
    unchanged (they looked right)."""
    out = json.loads(json.dumps(bones))
    for bone in BODY_BONES:
        if bone in out:
            out[bone]["rot"][0] = -out[bone]["rot"][0]
    return out


def write():
    os.makedirs(OUT, exist_ok=True)
    for name, s in SPECS.items():
        spec = {
            "name": name,
            "rbx_name": name,
            "priority": "Action",
            "loop": s["loop"],
            "fps": 30,
            "duration": s["duration"],
            "w": 640, "h": 560, "margin": 1.15,
            "plain": True,
            "preview": PREVIEW,
            "views": {"side": [1.0, 0.0, 0.0], "tq": [0.92, 0.38, 0.14]},
            "properties": FK_PROPS,
            "keyframes": [{"t": t, "ease": ease, "bones": game_axes(bones)} for (t, ease, bones) in s["keys"]],
        }
        with open(os.path.join(OUT, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(spec, f, indent=1)
    print(f"wrote {len(SPECS)} specs to {OUT} (preview={PREVIEW})")


if __name__ == "__main__":
    write()
