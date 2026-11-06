"""Builds the Android app icons from two source images (run after `flutter create`).

app_icon_full.png        - the full icon (rounded square, transparent corners)
app_icon_foreground.png  - the white microscope on a transparent background

Writes: legacy icons, adaptive icon layers (Android 8+) and the background colour.
"""
import os

from PIL import Image

BACKGROUND = '#5FE3AC'
RES = os.path.join('android', 'app', 'src', 'main', 'res')

# density: (legacy icon size in px, adaptive layer size in px)
DENSITIES = {
    'mdpi': (48, 108),
    'hdpi': (72, 162),
    'xhdpi': (96, 216),
    'xxhdpi': (144, 324),
    'xxxhdpi': (192, 432),
}

full = Image.open('app_icon_full.png').convert('RGBA')
fore = Image.open('app_icon_foreground.png').convert('RGBA')

for name, (legacy, layer) in DENSITIES.items():
    folder = os.path.join(RES, 'mipmap-' + name)
    os.makedirs(folder, exist_ok=True)
    full.resize((legacy, legacy), Image.LANCZOS).save(os.path.join(folder, 'ic_launcher.png'))
    full.resize((legacy, legacy), Image.LANCZOS).save(os.path.join(folder, 'ic_launcher_round.png'))
    fore.resize((layer, layer), Image.LANCZOS).save(os.path.join(folder, 'ic_launcher_foreground.png'))

anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
os.makedirs(anydpi, exist_ok=True)
adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""
for fname in ('ic_launcher.xml', 'ic_launcher_round.xml'):
    with open(os.path.join(anydpi, fname), 'w') as f:
        f.write(adaptive)

values = os.path.join(RES, 'values')
os.makedirs(values, exist_ok=True)
with open(os.path.join(values, 'ic_launcher_background.xml'), 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">%s</color>\n</resources>\n' % BACKGROUND)

print('App icons written to', RES)
