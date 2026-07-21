# Branding

`app_icon_master.png` (1024×1024) is the source launcher icon, generated with
`generate_icon.py` because Thirdsan hasn't supplied a real logo file yet —
see CLAUDE.md section 2 for the brand spec this approximates (gold/charcoal
palette, crossed utensils, matching the mark already used on the login
screen). It's a placeholder good enough to ship, not a final design.

## When the real logo arrives

Replace `app_icon_master.png` with the actual artwork (square, 1024×1024,
no transparency needed) and run:

```bash
cd mobile
python3 assets/branding/apply_icon.py
```

This regenerates every Android (`mipmap-*`) and iOS (`AppIcon.appiconset`)
launcher icon size from the new master. Requires Pillow (`pip install
pillow`).

## Regenerating the placeholder mark

```bash
cd mobile
python3 assets/branding/generate_icon.py   # rewrites app_icon_master.png
python3 assets/branding/apply_icon.py      # re-applies it to all platforms
```
