"""Build an image-per-slide deck from PPT导出 PNGs (4:3, 20x15in)."""
import re
import sys
from pathlib import Path

from pptx import Presentation
from pptx.util import Inches

src_dir = Path(sys.argv[1])
out = Path(sys.argv[2])

imgs = [p for p in src_dir.iterdir() if p.suffix.lower() in {".png", ".jpg", ".jpeg"}]
imgs.sort(key=lambda p: int(re.sub(r"\D", "", p.stem) or 0))
print(f"images: {len(imgs)}  first={imgs[0].name} last={imgs[-1].name}")

prs = Presentation()
prs.slide_width = Inches(20)
prs.slide_height = Inches(15)
blank = prs.slide_layouts[6]

for i, img in enumerate(imgs, 1):
    slide = prs.slides.add_slide(blank)
    slide.shapes.add_picture(str(img), 0, 0, width=prs.slide_width, height=prs.slide_height)

prs.save(out)
print(f"saved: {out}  slides={len(prs.slides)}")
