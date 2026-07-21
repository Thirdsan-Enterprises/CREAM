"""
Cream POS app icon — generated to match the brand palette/mark already
established in the app (CLAUDE.md section 2, and the crossed-utensils
gold-circle mark used on the login screen).

Kept deliberately simple (bold ring + crossed utensils, no fine hat
detail, no text) because a launcher icon has to read clearly at 48x48 —
a full chef's-hat illustration turns to mud at that size. The circle +
crossed fork/spoon mark is the piece of the brand that actually holds up
that small; CSC/tagline stays in the in-app UI where there's room for it.
"""

from PIL import Image, ImageDraw

SIZE = 1024
CHARCOAL = (26, 26, 26, 255)      # #1A1A1A
GOLD = (201, 161, 92, 255)        # #C9A15C
GOLD_LIGHT = (212, 175, 106, 255)  # #D4AF6A


def make_base():
    img = Image.new("RGBA", (SIZE, SIZE), CHARCOAL)
    return img


def draw_ring(img):
    draw = ImageDraw.Draw(img)
    margin = 60
    width = 26
    draw.ellipse(
        [margin, margin, SIZE - margin, SIZE - margin],
        outline=GOLD,
        width=width,
    )
    return img


def make_fork(length, tine_count=4):
    """Vertical fork on a transparent canvas: stem + tines at the top."""
    w, h = 220, length
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    stem_w = 34
    cx = w // 2
    stem_top = 190
    # stem
    draw.rounded_rectangle(
        [cx - stem_w // 2, stem_top, cx + stem_w // 2, h],
        radius=stem_w // 2,
        fill=GOLD_LIGHT,
    )
    # tines
    tine_w = 26
    tine_h = 190
    gap = 44
    start_x = cx - (gap * (tine_count - 1)) // 2
    for i in range(tine_count):
        x = start_x + i * gap
        draw.rounded_rectangle(
            [x - tine_w // 2, 0, x + tine_w // 2, tine_h],
            radius=tine_w // 2,
            fill=GOLD_LIGHT,
        )
    # neck joining tines to stem
    draw.rounded_rectangle(
        [start_x - tine_w // 2, tine_h - 30, start_x + gap * (tine_count - 1) + tine_w // 2, stem_top + 30],
        radius=20,
        fill=GOLD_LIGHT,
    )
    return canvas


def make_spoon(length):
    """Vertical spoon: stem + oval bowl at the top."""
    w, h = 220, length
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    stem_w = 34
    cx = w // 2
    bowl_h = 230
    stem_top = bowl_h - 40
    draw.rounded_rectangle(
        [cx - stem_w // 2, stem_top, cx + stem_w // 2, h],
        radius=stem_w // 2,
        fill=GOLD_LIGHT,
    )
    bowl_w = 150
    draw.ellipse(
        [cx - bowl_w // 2, 0, cx + bowl_w // 2, bowl_h],
        fill=GOLD_LIGHT,
    )
    return canvas


def paste_rotated(base, utensil, angle, offset_x=0):
    rotated = utensil.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = (SIZE - rotated.width) // 2 + offset_x
    y = (SIZE - rotated.height) // 2
    base.alpha_composite(rotated, (x, y))


def main():
    img = make_base()

    utensil_len = 620
    fork = make_fork(utensil_len)
    spoon = make_spoon(utensil_len)

    # Cross them like an X, centered.
    paste_rotated(img, fork, 24, offset_x=-8)
    paste_rotated(img, spoon, -24, offset_x=8)

    draw_ring(img)

    import os
    out = os.path.join(os.path.dirname(__file__), "app_icon_master.png")
    img.convert("RGB").save(out)
    print("saved", out)


if __name__ == "__main__":
    main()
