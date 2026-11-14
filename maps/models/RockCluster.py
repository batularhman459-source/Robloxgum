"""Three chiselled rocks leaning together, big / mid / small, different seeds and tones."""
import lib

BUDGET = "prop"


def build():
    lib.reset()
    lib.rock("RockBig", 3.0, (0, 0, 0), "stone", seed=3, cuts=16)
    lib.rock("RockMid", 1.9, (3.0, 1.6, 0), "stoneDark", seed=8, cuts=13)
    lib.rock("RockSmall", 1.1, (-2.6, 2.0, 0), "stone", seed=21, cuts=10)
