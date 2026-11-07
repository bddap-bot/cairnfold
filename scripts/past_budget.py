"""Which phases a Quest bench lets past the frame budget: a "sweep/..." phase always, and a label the scene marks
"past_budget" while its garden is past the build budget (World.fill over 1), which no player can build. A
"pair/PHASE/..." stretch of scripts/pair_layer.py is judged as PHASE."""


def past_budget(label: dict, fill: float) -> bool:
    name = label["name"].removeprefix("pair/")
    return name.startswith("sweep/") or (bool(label.get("past_budget")) and fill > 1)
