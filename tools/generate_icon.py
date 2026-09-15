from pathlib import Path
from PIL import Image, ImageDraw

SIZE = 1024
PNG_OUT = Path('assets/branding/app_icon.png')
WINDOWS_ICO = Path('windows/runner/resources/app_icon.ico')

img = Image.new('RGB', (SIZE, SIZE), '#2F6BFF')
d = ImageDraw.Draw(img)

# Desktop
d.rounded_rectangle((190, 220, 620, 520), radius=48, fill='white')
d.rounded_rectangle((235, 265, 575, 472), radius=24, fill='#EAF0FF')
d.rounded_rectangle((325, 555, 500, 594), radius=20, fill='white')
d.rounded_rectangle((388, 500, 437, 575), radius=20, fill='white')

# Phone
d.rounded_rectangle((610, 390, 825, 770), radius=56, fill='white')
d.rounded_rectangle((642, 445, 793, 690), radius=24, fill='#EAF0FF')
d.ellipse((704, 714, 732, 742), fill='#2F6BFF')

# Transfer arrows
def arrow(x1, y1, x2, y2, color, width=54, head=55):
    d.line((x1, y1, x2, y2), fill=color, width=width)
    if x2 > x1:
        d.line((x2-head, y2-head, x2, y2), fill=color, width=width)
        d.line((x2-head, y2+head, x2, y2), fill=color, width=width)
    else:
        d.line((x2+head, y2-head, x2, y2), fill=color, width=width)
        d.line((x2+head, y2+head, x2, y2), fill=color, width=width)

arrow(340, 675, 548, 675, '#BFD0FF')
arrow(675, 335, 465, 335, 'white')

# HAI sparkle
cx, cy = 795, 205
sparkle = [
    (cx, cy-58), (cx+18, cy-18), (cx+58, cy), (cx+18, cy+18),
    (cx, cy+58), (cx-18, cy+18), (cx-58, cy), (cx-18, cy-18),
]
d.polygon(sparkle, fill='#DCE6FF')

PNG_OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(PNG_OUT, 'PNG', optimize=True)
print(f'Generated {PNG_OUT}')

# When a Windows scaffold exists, replace Flutter's default icon directly.
# This avoids running flutter_launcher_icons for Android inside a Windows-only CI job.
if WINDOWS_ICO.parent.exists():
    img.save(
        WINDOWS_ICO,
        format='ICO',
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(f'Generated {WINDOWS_ICO}')
