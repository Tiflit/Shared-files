from pathlib import Path
import re,sys
ROOT=Path(__file__).resolve().parent
DRIVE = re.compile(r'(?i)' + r'[A-Z]' + r':[\\\\/]+')
RX=[DRIVE,re.compile(r'(?i)(?:[\\\\/])Users(?:[\\\\/])'),re.compile(r'(?i)(?:[\\\\/])home(?:[\\\\/])'),re.compile(r'(?i)OneDrive'),re.compile(r'(?i)AppData')]
EXT={'.md','.txt','.csv','.json','.py','.ps1','.chn','.html','.xml','.ini'}
bad=[]
for p in ROOT.rglob('*'):
 if not p.is_file() or '.git' in p.parts or p.suffix.lower() not in EXT: continue
 try:t=p.read_text(encoding='utf-8-sig')
 except (UnicodeDecodeError,OSError):continue
 for n,line in enumerate(t.splitlines(),1):
  if any(r.search(line) for r in RX):bad.append(f'{p.relative_to(ROOT)}:{n}: {line.strip()}')
print('AoMEE repository hygiene')
if bad: print('FAIL\n'+'\n'.join(bad));sys.exit(1)
print('PASS: no drive-letter, home, OneDrive or AppData paths found')
