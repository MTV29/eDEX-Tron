"""Convert the bundled woff2 webfonts into TTFs Windows/Rainmeter can use.

Also writes build/ttf/families.json: the family name each file actually
declares. Nothing else should hard-code those names. They are not guessable --
the file called fira_mono.woff2 calls itself "FuraMono NF", and United Sans
Medium calls itself "United Sans Rg Md", not "United Sans Reg Medium" -- and a
name that does not match is not an error anywhere. GDI quietly substitutes
Microsoft Sans Serif and the HUD renders in the wrong typeface while looking
like it worked.
"""
import glob, json, os
from fontTools.ttLib import TTFont

os.makedirs('build/ttf', exist_ok=True)
families = {}
for src in sorted(glob.glob('assets/fonts/*.woff2')):
    font = TTFont(src)
    font.flavor = None            # drop woff2 compression -> plain TTF/OTF
    name = os.path.splitext(os.path.basename(src))[0]
    names = {rec.nameID: rec.toUnicode() for rec in font['name'].names}
    family = names.get(1, '')     # what FontFace has to say to select it
    full = names.get(4, '')       # the human name, which is often different
    dest = f'build/ttf/{name}.ttf'
    font.save(dest)
    families[name + '.ttf'] = family
    print(f'{os.path.basename(src):28} -> {dest:32} family="{family}" full="{full}"')

with open('build/ttf/families.json', 'w', encoding='utf-8') as f:
    json.dump(families, f, indent=2, sort_keys=True)
    f.write('\n')
print(f'{"families.json":28} -> build/ttf/families.json       {len(families)} font(s)')
