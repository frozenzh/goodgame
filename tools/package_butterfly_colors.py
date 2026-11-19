"""按同一图集逐像素换翼色，保持 alpha、身体和全部帧布局一致。"""
from pathlib import Path
import colorsys
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/hd/world/ambient_fauna'
DOC = ROOT / 'docs/ambient_fauna'
base = Image.open(OUT/'butterfly_atlas.png').convert('RGBA')
template = (OUT/'butterfly_frames.tres').read_text(encoding='utf-8')
colors = {'gold': None, 'blue': .56, 'pink': .94, 'purple': .76, 'mint': .40}
atlases = []
manifest = []
for name, hue in colors.items():
    atlas = base.copy()
    # 只换明亮翼片；棕色身体、触须、描边及低明度阴影原样保留。
    pixels = []
    for r,g,b,a in base.getdata():
        if hue is not None and a and r > 110 and g > 75:
            h,s,v = colorsys.rgb_to_hsv(r/255,g/255,b/255)
            if .065 < h < .19 and v > .43:
                r,g,b = (round(c*255) for c in colorsys.hsv_to_rgb(hue, s*.78, v))
        pixels.append((r,g,b,a))
    atlas.putdata(pixels)
    atlas.save(OUT/f'butterfly_{name}_atlas.png')
    (OUT/f'butterfly_{name}_frames.tres').write_text(template.replace('butterfly_atlas.png',f'butterfly_{name}_atlas.png'),encoding='utf-8')
    atlases.append(atlas)
    manifest.append({'color':name,'sprite_frames':f'res://assets/hd/world/ambient_fauna/butterfly_{name}_frames.tres','alpha_identical':atlas.getchannel('A').tobytes()==base.getchannel('A').tobytes()})
preview=Image.new('RGB',(500,160),'#c8cfb3')
d=ImageDraw.Draw(preview)
for i,(name,atlas) in enumerate(zip(colors,atlases)):
    frame=atlas.crop((0,0,20,20)).resize((100,100),Image.Resampling.NEAREST)
    preview.paste(frame,(i*100,12),frame)
    d.text((i*100+30,126),name,fill='#35281e')
preview.save(DOC/'butterfly_five_colors.png')
animation=[]
for j in range(4):
    img=Image.new('RGB',(500,140),'#c8cfb3')
    for i,atlas in enumerate(atlases):
        frame=atlas.crop((j*20,0,j*20+20,20)).resize((100,100),Image.Resampling.NEAREST)
        img.paste(frame,(i*100,20),frame)
    animation.append(img)
animation[0].save(DOC/'butterfly_five_colors.gif',save_all=True,append_images=animation[1:],duration=100,loop=0)
(OUT/'butterfly_colors.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(manifest))
