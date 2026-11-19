"""将内置 imagegen 原稿切为固定画布，输出环境动物美术资源；不启动 Godot。"""
from pathlib import Path
import json
import shutil
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = Path('C:/Users/Zhuheng/.codex/generated_images/01a1c569-e34e-7a83-b0b1-24227d35f91e')
OUT = ROOT / 'assets/hd/world/ambient_fauna'
DOC = ROOT / 'docs/ambient_fauna'
OUT.mkdir(parents=True, exist_ok=True)
DOC.mkdir(parents=True, exist_ok=True)
specs = {
    'butterfly': ('exec-d65717c0-3d4b-426e-a7fa-814ef9112974.png', 20, {'fly': ([0,1,2,3], 10, True), 'perch': ([4,5], 2, True)}, (10,10)),
    'bird': ('exec-4007a594-b8a5-467a-b6c9-0466713d45c9.png', 32, {'fly': ([0,1,2,3], 10, True), 'stand': ([4], 1, True), 'peck': ([5,6,7], 5, False)}, (16,28)),
}
manifest = {}
for name, (source, size, animations, pivot) in specs.items():
    shutil.copy2(SRC/source, OUT/f'{name}_imagegen_source.png')
    im = Image.open(SRC/source).convert('RGBA')
    w,h = im.size
    frames=[]
    for i in range(8):
        cell=im.crop((i%4*w//4,i//4*h//2,(i%4+1)*w//4,(i//4+1)*h//2))
        cell=cell.resize((size,size), Image.Resampling.NEAREST)
        # 二值透明消除缩小后边缘半透明杂点；所有动作使用同一画布，不自动裁边。
        px=list(cell.getdata())
        cell.putdata([(r,g,b,255) if a>=160 else (0,0,0,0) for r,g,b,a in px])
        if name == 'bird' and i in (5,6):
            aligned=Image.new('RGBA',(size,size))
            aligned.paste(cell,(1,0))
            cell=aligned
        frames.append(cell)
    atlas=Image.new('RGBA',(size*4,size*2))
    for i,f in enumerate(frames): atlas.paste(f,(i%4*size,i//4*size))
    atlas.save(OUT/f'{name}_atlas.png')
    lines=[f'[gd_resource type="SpriteFrames" load_steps={len(set(i for ids,_,_ in animations.values() for i in ids))+2} format=3]', '',f'[ext_resource type="Texture2D" path="res://assets/hd/world/ambient_fauna/{name}_atlas.png" id="1"]','']
    for i in sorted(set(i for ids,_,_ in animations.values() for i in ids)):
        lines += [f'[sub_resource type="AtlasTexture" id="Frame_{i}"]','atlas = ExtResource("1")', f'region = Rect2({i%4*size}, {i//4*size}, {size}, {size})', '']
    entries=[]
    for anim,(ids,fps,loop) in animations.items():
        fs=', '.join('{"duration": 1.0, "texture": SubResource("Frame_%d")}'%i for i in ids)
        entries.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}'%(fs,str(loop).lower(),anim,fps))
        previews=[]
        for i in ids:
            bg=Image.new('RGB',(192,192),'#d7d5bd')
            d=ImageDraw.Draw(bg)
            for y in range(0,192,12):
                for x in range(0,192,12):
                    if (x//12+y//12)%2: d.rectangle((x,y,x+11,y+11), fill='#b9bca7')
            f=frames[i].resize((size*5,size*5),Image.Resampling.NEAREST)
            bg.paste(f,((192-size*5)//2,(192-size*5)//2),f)
            previews.append(bg)
        previews[0].save(DOC/f'{name}_{anim}.gif', save_all=True, append_images=previews[1:], duration=round(1000/fps), loop=0)
    lines += ['[resource]', 'animations = ['+',\n'.join(entries)+']','']
    (OUT/f'{name}_frames.tres').write_text('\n'.join(lines),encoding='utf-8')
    manifest[name]={'cell':[size,size], 'atlas':list(atlas.size),'pivot':pivot,'animations':animations,'frames':[{'index':i,'region':[i%4*size,i//4*size,size,size],'bounds':f.getbbox()} for i,f in enumerate(frames)], 'alpha_values':sorted(set(atlas.getchannel('A').getdata())),'border_clear':all(f.getpixel((x,y))[3]==0 for f in frames for x,y in [(x,0) for x in range(size)]+[(x,size-1) for x in range(size)]+[(0,y) for y in range(size)]+[(size-1,y) for y in range(size)])}
    atlas.resize((size*4*5,size*2*5),Image.Resampling.NEAREST).save(DOC/f'{name}_contact.png')
(DOC/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(manifest,ensure_ascii=False))
