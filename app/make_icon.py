"""Zeichnet das App-Logo (app/logo.png, 1024 px) und app/logo.icns. Aufruf: python3 app/make_icon.py"""
import os, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter

S = 4096                      # 4x zeichnen, dann verkleinern = glatte Kanten
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

def u(v):                     # Koordinaten in 1024er-Einheiten
    return int(v * S / 1024)

# Kachel: Verlauf blau -> türkis, macOS-Rundung, leichter Schatten
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    t = y / S
    gd.line([(0, y), (S, y)], fill=(int(30 + 10 * t), int(90 + 90 * t), int(220 - 30 * t), 255))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([u(100), u(100), u(924), u(924)], radius=u(185), fill=255)
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([u(100), u(118), u(924), u(942)], radius=u(185), fill=(0, 0, 0, 90))
img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(u(14))))
img.paste(grad, (0, 0), mask)
d = ImageDraw.Draw(img)

W = (255, 255, 255, 255)
BLUE = (40, 110, 215, 255)
# Papier oben
d.rounded_rectangle([u(355), u(230), u(669), u(440)], radius=u(18), fill=W)
# Druckerkörper
d.rounded_rectangle([u(250), u(390), u(774), u(650)], radius=u(60), fill=W)
d.rounded_rectangle([u(330), u(560), u(694), u(600)], radius=u(20), fill=BLUE)   # Ausgabeschlitz
d.ellipse([u(660), u(445), u(705), u(490)], fill=(60, 200, 120, 255))             # Statuslämpchen
# ausgegebenes Blatt mit Textzeilen
d.rounded_rectangle([u(355), u(580), u(669), u(790)], radius=u(18), fill=W)
for i, w in enumerate((250, 210, 230)):
    y = u(625 + i * 45)
    d.rounded_rectangle([u(395), y, u(395 + w), y + u(18)], radius=u(9), fill=(190, 205, 225, 255))

# Umzugs-Abzeichen: oranger Kreis mit weißem Pfeil
cx, cy, r = u(745), u(745), u(150)
d.ellipse([cx - r - u(14), cy - r - u(14), cx + r + u(14), cy + r + u(14)], fill=W)
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 149, 0, 255))
d.rounded_rectangle([cx - u(85), cy - u(22), cx + u(30), cy + u(22)], radius=u(10), fill=W)
d.polygon([(cx + u(10), cy - u(70)), (cx + u(95), cy), (cx + u(10), cy + u(70))], fill=W)

here = os.path.dirname(os.path.abspath(__file__))
logo = img.resize((1024, 1024), Image.LANCZOS)
logo.save(os.path.join(here, "logo.png"))

with tempfile.TemporaryDirectory() as t:
    iconset = os.path.join(t, "logo.iconset")
    os.mkdir(iconset)
    for px in (16, 32, 128, 256, 512):
        logo.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, f"icon_{px}x{px}.png"))
        logo.resize((px * 2, px * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{px}x{px}@2x.png"))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(here, "logo.icns")], check=True)
print("app/logo.png + app/logo.icns geschrieben")
