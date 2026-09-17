"""Minimal asar reader — lists or extracts files from an Electron app.asar."""
import json, os, struct, sys

def read_header(f):
    f.seek(0)
    # pickle: uint32 payload-size fields, then the JSON header
    _, hdr_size, _, json_len = struct.unpack('<4I', f.read(16))
    header = json.loads(f.read(json_len).decode('utf-8'))
    return header, 8 + hdr_size  # base offset for file data

def walk(node, prefix=''):
    for name, meta in node.get('files', {}).items():
        path = f'{prefix}/{name}' if prefix else name
        if 'files' in meta:
            yield from walk(meta, path)
        else:
            yield path, meta

if __name__ == '__main__':
    asar, mode = sys.argv[1], sys.argv[2]
    with open(asar, 'rb') as f:
        header, base = read_header(f)
        entries = list(walk(header))
        if mode == 'list':
            pat = sys.argv[3] if len(sys.argv) > 3 else ''
            for p, m in entries:
                if pat.lower() in p.lower():
                    print(f"{m.get('size', 0):>10}  {p}")
        else:  # extract <pattern> <outdir>
            pat, out = sys.argv[3], sys.argv[4]
            n = 0
            for p, m in entries:
                if pat.lower() not in p.lower() or 'offset' not in m:
                    continue
                dest = os.path.join(out, os.path.basename(p))
                f.seek(base + int(m['offset']))
                with open(dest, 'wb') as o:
                    o.write(f.read(m['size']))
                n += 1
                print('extracted', p)
            print(f'-- {n} file(s) -> {out}')
