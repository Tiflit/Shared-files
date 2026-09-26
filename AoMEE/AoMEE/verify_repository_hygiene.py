from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
FORBIDDEN = [
    re.compile(r'(?i)[A-Z]:[\\\\/]+'),
    re.compile(r'(?i)(?:[\\\\/])Users(?:[\\\\/])'),
    re.compile(r'(?i)(?:[\\\\/])home(?:[\\\\/])'),
    re.compile(r'(?i)OneDrive'),
    re.compile(r'(?i)AppData'),
]
SUFFIXES = {'.md','.txt','.csv','.json','.py','.ps1','.chn','.html','.xml','.ini'}

bad=[]
for p in ROOT.rglob('*'):
    if not p.is_file() or '.git' in p.parts or p.suffix.lower() not in SUFFIXES:
        continue
    try: text=p.read_text(encoding='utf-8-sig')
    except (UnicodeDecodeError,OSError): continue
    for n,line in enumerate(text.splitlines(),1):
        if any(rx.search(line) for rx in FORBIDDEN):
            bad.append(f'{p.relative_to(ROOT)}:{n}: {line.strip()}')

print('AoMEE repository hygiene')
if bad:
    print('FAIL: local-path indicators found')
    print('\n'.join(bad))
    sys.exit(1)
print('PASS: no drive-letter, home, OneDrive or AppData paths found')
