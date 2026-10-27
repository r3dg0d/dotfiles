#!/usr/bin/env python3
"""Render editable annotations into a separate PNG and perform the chosen action."""
import json
import math
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlparse

try:
    from PIL import Image, ImageDraw
except ImportError:
    # Bootstrap with the existing Nix Python package; persistent dependency in rice.nix.
    for package in Path('/nix/store').glob('*-python3.13-pillow-*/lib/python3.13/site-packages'):
        sys.path.insert(0, str(package))
    from PIL import Image, ImageDraw


def render(source, marks):
    image = Image.open(source).convert('RGBA')
    draw = ImageDraw.Draw(image)
    for mark in marks:
        points = [(point['x'], point['y']) for point in mark['points']]
        if not points:
            continue
        color, width = mark['color'], max(1, round(mark['width']))
        a, b = points[0], points[-1]
        if mark['tool'] == 'pen':
            if len(points) == 1:
                x,y=a; draw.ellipse((x-width/2,y-width/2,x+width/2,y+width/2),fill=color)
            else:
                draw.line(points, fill=color, width=width, joint='curve')
        elif mark['tool'] in ('rectangle', 'redact'):
            box = (min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]))
            if mark['tool'] == 'redact':
                draw.rectangle(box, fill='#07060d')
            else:
                draw.rectangle(box, outline=color, width=width)
        elif mark['tool'] == 'arrow':
            draw.line([a,b],fill=color,width=width)
            angle=math.atan2(b[1]-a[1],b[0]-a[0]); length=max(14,width*4)
            tips=[(b[0]-length*math.cos(angle+d), b[1]-length*math.sin(angle+d)) for d in (-0.5,0.5)]
            draw.polygon([b,*tips],fill=color)
    target = Path(source).with_name(Path(source).stem + '-edited.png')
    image.save(target)
    return target


def perform(source, marks, action, endpoint=''):
    target = render(source, marks)
    if action == 'copy':
        subprocess.run(['wl-copy','--type','image/png'],input=target.read_bytes(),check=True,timeout=10)
    if action == 'upload':
        if endpoint == 'guns.lol':
            from uploader import upload
            response = upload(target)
            subprocess.run(['wl-copy'], input=response.encode(), check=True, timeout=10)
            return {'message': 'Uploaded to guns.lol · link copied', 'path': str(target), 'url': response}
        if urlparse(endpoint).scheme != 'https' or not urlparse(endpoint).hostname:
            raise ValueError('Enter an HTTPS upload endpoint first')
        response = subprocess.run(['curl','--fail','--silent','--show-error','--max-time','60',
                                   '-F',f'file=@{target}',endpoint],capture_output=True,text=True,check=True,timeout=65).stdout.strip()
        try:
            data=json.loads(response)
            response=data.get('url') or (data.get('data') or {}).get('url') or ''
        except json.JSONDecodeError:
            pass
        if urlparse(response).scheme not in ('https','http'):
            raise ValueError('Uploaded, but the server returned no share URL')
        subprocess.run(['wl-copy'],input=response.encode(),check=True,timeout=10)
        return {'message':'Uploaded · link copied', 'path':str(target), 'url':response}
    return {'message':'Image copied' if action=='copy' else 'Saved edited PNG', 'path':str(target)}


if __name__ == '__main__':
    try:
        print(json.dumps(perform(sys.argv[1],json.loads(sys.argv[2]),sys.argv[3],sys.argv[4] if len(sys.argv)>4 else '')))
    except Exception as error:
        print(json.dumps({'message':'Could not complete action: '+str(error)}))
