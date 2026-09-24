#!/usr/bin/env python3
"""Genera l'icona di CalenTask (tutte le misure dell'AppIcon).

Pagina di calendario bianca con testata corallo, anelli e una spunta
viola, su fondo indaco→viola. Quadrato pieno (full-bleed): su iOS e
macOS 26 la forma arrotondata la applica il sistema.

Uso: python3 .github/scripts/make-icon.py  (serve Pillow + numpy)
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 4                      # supersampling per bordi puliti
S = 1024 * SS
OUT = os.path.join(os.path.dirname(__file__), "../../CalenTask/Assets.xcassets/AppIcon.appiconset")


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def gradient(size, c1, c2, angle_deg=135):
    """Gradiente lineare diagonale RGBA (numpy)."""
    w, h = size
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    a = np.deg2rad(angle_deg)
    t = (x * np.cos(a) + y * np.sin(a))
    t = (t - t.min()) / (t.max() - t.min())
    c1 = np.array(c1, np.float32)
    c2 = np.array(c2, np.float32)
    rgb = c1[None, None, :] * (1 - t[..., None]) + c2[None, None, :] * t[..., None]
    alpha = np.full((h, w, 1), 255, np.float32)
    return Image.fromarray(np.concatenate([rgb, alpha], axis=2).astype(np.uint8), "RGBA")


def radial_glow(size, center, radius, color, strength):
    w, h = size
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((x - center[0]) ** 2 + (y - center[1]) ** 2) / radius
    a = np.clip(1 - d, 0, 1) ** 2 * strength * 255
    rgb = np.broadcast_to(np.array(color, np.float32), (h, w, 3))
    return Image.fromarray(np.concatenate([rgb, a[..., None]], axis=2).astype(np.uint8), "RGBA")


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def render(dark=False):
    size = (S, S)
    top, bottom = ("#2B2F77", "#4A2A8A") if dark else ("#4F46E5", "#8B5CF6")
    img = gradient(size, hex_rgb(top), hex_rgb(bottom), 120)
    # Luce calda in alto a sinistra, per profondità.
    img.alpha_composite(radial_glow(size, (S * 0.18, S * 0.10), S * 0.9, (255, 255, 255), 0.22 if not dark else 0.10))
    img.alpha_composite(radial_glow(size, (S * 0.95, S * 1.0), S * 0.8, hex_rgb("#F76B15"), 0.28 if not dark else 0.18))

    # La pagina del calendario.
    card = (int(S * 0.205), int(S * 0.235), int(S * 0.795), int(S * 0.805))
    radius = int(S * 0.11)

    # Ombra morbida.
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = int(S * 0.028)
    sd.rounded_rectangle((card[0], card[1] + off, card[2], card[3] + off), radius=radius,
                         fill=(20, 10, 60, 120 if not dark else 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.03))
    img.alpha_composite(shadow)

    page_color = (246, 247, 251, 255) if dark else (255, 255, 255, 255)
    page = Image.new("RGBA", size, page_color)
    img.paste(page, (0, 0), rounded_mask(size, card, radius))

    # Testata corallo (solo la parte alta della pagina, angoli arrotondati sopra).
    header_h = int((card[3] - card[1]) * 0.27)
    header = gradient(size, hex_rgb("#FF8A4C"), hex_rgb("#E5484D"), 0)
    header_mask = Image.new("L", size, 0)
    hm = ImageDraw.Draw(header_mask)
    hm.rounded_rectangle(card, radius=radius, fill=255)
    hm.rectangle((0, card[1] + header_h, S, S), fill=0)
    img.paste(header, (0, 0), header_mask)

    d = ImageDraw.Draw(img)
    # Anelli.
    ring_w, ring_h = int(S * 0.045), int(S * 0.11)
    for cx in (card[0] + (card[2] - card[0]) * 0.30, card[0] + (card[2] - card[0]) * 0.70):
        x0 = int(cx - ring_w / 2)
        y0 = int(card[1] - ring_h * 0.42)
        d.rounded_rectangle((x0, y0, x0 + ring_w, y0 + ring_h), radius=ring_w // 2,
                            fill=(255, 255, 255, 255))
        d.rounded_rectangle((x0 + ring_w * 0.22, y0 + ring_h * 0.55, x0 + ring_w * 0.78, y0 + ring_h * 0.92),
                            radius=ring_w // 3, fill=(200, 60, 60, 255))

    body_top = card[1] + header_h

    # La spunta, grande, viola: il "task" nel calendario.
    check = [
        (card[0] + (card[2] - card[0]) * 0.27, body_top + (card[3] - body_top) * 0.50),
        (card[0] + (card[2] - card[0]) * 0.45, body_top + (card[3] - body_top) * 0.70),
        (card[0] + (card[2] - card[0]) * 0.76, body_top + (card[3] - body_top) * 0.26),
    ]
    width = int(S * 0.085)
    stroke_color = (91, 70, 229, 255) if not dark else (110, 86, 207, 255)

    def distance_to_check(x, y):
        best = float("inf")
        for (ax, ay), (bx, by) in zip(check, check[1:]):
            vx, vy = bx - ax, by - ay
            t = max(0, min(1, ((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy)))
            best = min(best, ((ax + t * vx - x) ** 2 + (ay + t * vy - y) ** 2) ** 0.5)
        return best

    # Puntini dei giorni, tenui; spariscono (interi) dove passa la spunta.
    cols, rows = 5, 3
    gx0, gx1 = card[0] + (card[2] - card[0]) * 0.17, card[0] + (card[2] - card[0]) * 0.83
    gy0, gy1 = body_top + (card[3] - body_top) * 0.20, body_top + (card[3] - body_top) * 0.80
    dot = S * 0.028
    for r in range(rows):
        for c in range(cols):
            x = gx0 + (gx1 - gx0) * c / (cols - 1)
            y = gy0 + (gy1 - gy0) * r / (rows - 1)
            if distance_to_check(x, y) < width * 1.1:
                continue
            d.ellipse((x - dot / 2, y - dot / 2, x + dot / 2, y + dot / 2), fill=(214, 211, 238, 255))

    d.line(check, fill=stroke_color, width=width, joint="curve")
    for p in check:
        rr = width / 2
        d.ellipse((p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr), fill=stroke_color)

    return img.resize((1024, 1024), Image.LANCZOS)


def tinted(base):
    """Variante 'tinted' di iOS: scala di grigi."""
    return base.convert("L").convert("RGBA")


def main():
    light = render(dark=False)
    dark = render(dark=True)
    light.convert("RGB").save(os.path.join(OUT, "icon-1024.png"))
    dark.convert("RGB").save(os.path.join(OUT, "icon-1024-dark.png"))
    tinted(light).convert("RGB").save(os.path.join(OUT, "icon-1024-tinted.png"))
    for px in (16, 32, 64, 128, 256, 512, 1024):
        light.resize((px, px), Image.LANCZOS).convert("RGB").save(os.path.join(OUT, f"icon-mac-{px}.png"))
    print("ok")


if __name__ == "__main__":
    main()
