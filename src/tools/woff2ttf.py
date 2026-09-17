"""Convert eDEX-UI's bundled woff2 webfonts into TTFs Windows/Rainmeter can use."""
import glob, os
from fontTools.ttLib import TTFont

os.makedirs('build/ttf', exist_ok=True)
for src in sorted(glob.glob('assets/fonts/*.woff2')):
    font = TTFont(src)
    font.flavor = None            # drop woff2 compression -> plain TTF/OTF
    name = os.path.splitext(os.path.basename(src))[0]
    # recover the real family name so Windows shows it correctly
    fam = ''
    for rec in font['name'].names:
        if rec.nameID == 4:
            fam = rec.toUnicode(); break
    dest = f'build/ttf/{name}.ttf'
    font.save(dest)
    print(f'{os.path.basename(src):28} -> {dest:32} family="{fam}"')
