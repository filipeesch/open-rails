"""`small_station` — one class of station for V1.

A 2.4 x 0.9 tile raised platform (exactly one HEIGHT_STEP so it aligns with
terrain steps and wagon floors), a gable station building with a company-
liveried name board, a canopy over the track edge, and a brick chimney.

Attachments publish the runtime hookups: platform top/ends, the entrance, the
chimney smoke origin, and coupling points down at rail height along the track
lane (-Y, one tile off the platform edge).
"""

PLATFORM_L = 2.40
PLATFORM_W = 0.90
PLATFORM_H = 0.25      # exactly one HEIGHT_STEP (asset-scale.md)
BUILD_Y = 0.12         # building centre, so the roof rear lands on +0.45


def build(ctx) -> None:
    platform = ctx.box("platform", size=(PLATFORM_L, PLATFORM_W, PLATFORM_H),
                       location=(0, 0, PLATFORM_H / 2), colour="earth")
    ctx.paint(platform, "earth", shade=0.88)
    ctx.beveled_box("platform_edge", size=(PLATFORM_L, 0.04, 0.26),
                    location=(0, -PLATFORM_W / 2 + 0.02, PLATFORM_H / 2),
                    colour="stone", bevel=0.006)

    _building(ctx)
    _canopy(ctx)
    _attachments(ctx)


def _building(ctx) -> None:
    wall_h = 0.42
    top = PLATFORM_H + wall_h                       # 0.67
    body = ctx.beveled_box("station_body", size=(1.40, 0.55, wall_h),
                           location=(0, BUILD_Y, PLATFORM_H + wall_h / 2),
                           colour="wood_light", bevel=0.012)
    ctx.shade_faces_below(body, fraction=0.18, factor=0.88)
    ctx.roof("station_roof", width=1.55, depth=0.66, height=0.26,
             location=(0, BUILD_Y, top), colour="roof_red", ridge_axis="x")
    ctx.beveled_box("station_ridge", size=(1.55, 0.05, 0.03),
                    location=(0, BUILD_Y, top + 0.26), colour="roof_dark", bevel=0.006)

    ctx.beveled_box("chimney", size=(0.11, 0.11, 0.46),
                    location=(-0.50, BUILD_Y, PLATFORM_H + 0.50),
                    colour="brick_red", bevel=0.007)
    ctx.box("chimney_cap", size=(0.14, 0.14, 0.04),
            location=(-0.50, BUILD_Y, 1.00), colour="stone")

    fy = BUILD_Y - 0.275 - 0.006                    # front (track) face, proud
    ctx.box("entrance_door", size=(0.13, 0.014, 0.24), location=(0, fy, 0.37),
            colour="wood_dark")
    for tag, wx in (("a", -0.45), ("b", -0.15), ("c", 0.15), ("d", 0.45)):
        if abs(wx) < 0.1:
            continue
        ctx.box("window_" + tag, size=(0.10, 0.012, 0.10),
                location=(wx, fy, 0.47), colour="glass_fake")

    board = ctx.box("name_board", size=(0.46, 0.014, 0.07), location=(0, fy, 0.60),
                    colour="wood_light")
    ctx.tag_company(board, "secondary")


def _canopy(ctx) -> None:
    ctx.box("canopy_roof", size=(1.70, 0.24, 0.05), location=(0, -0.31, 0.725),
            colour="roof_dark")
    for tag, x in (("l", -0.78), ("r", 0.78)):
        ctx.box("canopy_post_" + tag, size=(0.045, 0.045, 0.45),
                location=(x, -0.36, 0.475), colour="wood_dark")


def _attachments(ctx) -> None:
    ctx.attachment("platform", (0.0, 0.0, PLATFORM_H), kind="platform")
    ctx.attachment("platform_west", (-PLATFORM_L / 2, 0.0, PLATFORM_H), kind="platform")
    ctx.attachment("platform_east", (PLATFORM_L / 2, 0.0, PLATFORM_H), kind="platform")
    ctx.attachment("building_entrance", (0.0, BUILD_Y - 0.32, PLATFORM_H), kind="entrance")
    ctx.attachment("chimney_smoke", (-0.50, BUILD_Y, 1.04), kind="effect")
    track_y = -(PLATFORM_W / 2 + 0.55)              # rail centreline, next lane
    ctx.attachment("coupler_front", (PLATFORM_L / 2, track_y, 0.04), kind="coupling")
    ctx.attachment("coupler_rear", (-PLATFORM_L / 2, track_y, 0.04), kind="coupling")
