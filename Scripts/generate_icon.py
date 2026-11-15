"""Render the project's vector V/play mark into Apple's icon catalog."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
art = root / 'Artwork'
art.mkdir(exist_ok=True)
svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><defs><linearGradient id="bg" x2="1" y2="1"><stop stop-color="#111c40"/><stop offset="1" stop-color="#5134c9"/></linearGradient><radialGradient id="glow" cx="85%" cy="15%" r="90%"><stop stop-color="#3ccec9" stop-opacity=".45"/><stop offset="1" stop-color="#3ccec9" stop-opacity="0"/></radialGradient></defs><path fill="url(#bg)" d="M0 0h1024v1024H0z"/><path fill="url(#glow)" d="M0 0h1024v1024H0z"/><path d="M240 310L455 740L795 292" fill="none" stroke="white" stroke-width="118" stroke-linejoin="round" stroke-linecap="round"/><path d="M455 330L455 520L610 425Z" fill="#68f6dd"/></svg>'''
(art / 'VietVideo.svg').write_text(svg)
n = 2048
y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
blend = ((x + y) / 2)[..., None]
start, end = np.array([17,28,64]), np.array([81,52,201])
rgb = start * (1-blend) + end * blend
glow = np.clip(1 - np.sqrt((x-.85)**2+(y-.15)**2)/.95,0,1)[...,None] * .45
rgb = rgb*(1-glow)+np.array([60,206,201])*glow
image = Image.fromarray(rgb.astype(np.uint8), 'RGB')
draw = ImageDraw.Draw(image)
points = [(480,620),(910,1480),(1590,584)]
draw.line(points, fill='white', width=236, joint='curve')
for px,py in points: draw.ellipse((px-118,py-118,px+118,py+118),fill='white')
draw.polygon([(910,660),(910,1040),(1220,850)],fill='#68f6dd')
image = image.resize((1024,1024),Image.Resampling.LANCZOS)
assert image.mode == 'RGB' and image.size == (1024,1024)
image.save(art/'VietVideo-1024.png')
catalog=root/'Sources/Brand.xcassets'
catalog.mkdir(exist_ok=True)
(catalog/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
icon=catalog/'AppIcon.appiconset';icon.mkdir(exist_ok=True)
entries=[]
for size in [20,29,40,60]:
 for scale in [2,3]:
  name=f'icon-{size}-{scale}.png';image.resize((size*scale,size*scale),Image.Resampling.LANCZOS).save(icon/name)
  entries.append(dict(idiom='iphone',size=f'{size}x{size}',scale=f'{scale}x',filename=name))
image.save(icon/'icon-1024.png');entries.append(dict(idiom='ios-marketing',size='1024x1024',scale='1x',filename='icon-1024.png'))
(icon/'Contents.json').write_text(json.dumps(dict(images=entries,info={'author':'xcode','version':1}),indent=2))
brand=catalog/'BrandMark.imageset';brand.mkdir(exist_ok=True);entries=[]
for scale in [1,2,3]:
 name=f'brand-{scale}.png';image.resize((256*scale,256*scale),Image.Resampling.LANCZOS).save(brand/name)
 entries.append(dict(idiom='universal',scale=f'{scale}x',filename=name))
(brand/'Contents.json').write_text(json.dumps(dict(images=entries,info={'author':'xcode','version':1}),indent=2))
print('Created opaque AppIcon catalog and BrandMark images.')

