import math, wave, array, random
from pathlib import Path
rate=22050; duration=64; n=rate*duration
left=array.array('f',[0])*n; right=array.array('f',[0])*n
rng=random.Random(29)
# 封装 note 的处理，供相关流程复用。
def note(start,length,midi,amp,pan,pad=False):
 f=440*2**((midi-69)/12); count=int(length*rate); begin=int(start*rate)
 for j in range(count):
  t=j/rate
  env=(min(1,t/1.5)*min(1,(length-t)/2)) if pad else (1-math.exp(-t*45))*math.exp(-t/1.3)*min(1,(length-t)/.3)
  v=amp*env*(math.sin(2*math.pi*f*t)+.22*math.sin(2*math.pi*f*2*t)+.07*math.sin(2*math.pi*f*3*t))
  k=(begin+j)%n
  left[k]+=v*math.sqrt((1-pan)/2); right[k]+=v*math.sqrt((1+pan)/2)
# Eight 8-second bars, 60 BPM; Cmaj7, Am7, Fmaj7, Gsus, with a resolving repeat.
chords=[[48,55,59,64],[45,52,55,60],[41,48,52,57],[43,50,55,60]]*2
melody=[76,79,74,72,76,72,71,67]
for b,ch in enumerate(chords):
 for m in ch: note(b*8,10,m,.026,rng.uniform(-.5,.5),True)
 for s in range(8): note(b*8+s,3.4,ch[[0,2,1,3,1,2,3,2][s]]+12,.065,(-.35 if s%2 else .35))
 note(b*8+2,4.5,melody[b],.07,-.15)
 note(b*8+6,3.8,melody[b]-2 if b%2 else melody[b]+3,.04,.2)
peak=max(max(map(abs,left)),max(map(abs,right))); out=array.array('h')
for a,b in zip(left,right): out.extend((int(a/peak*.65*32767),int(b/peak*.65*32767)))
p=Path('assets/audio'); p.mkdir(exist_ok=True)
with wave.open(str(p/'pond_days.wav'),'wb') as w: w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate); w.writeframes(out.tobytes())
