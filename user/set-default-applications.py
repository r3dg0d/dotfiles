import configparser,json,os,sys
from pathlib import Path
associations=json.loads(Path(sys.argv[1]).read_text())
path=Path('/home/neo/.config/mimeapps.list')
config=configparser.ConfigParser(interpolation=None,strict=False)
config.optionxform=str
if path.exists(): config.read(path)
for section in ['Default Applications','Added Associations']:
 if not config.has_section(section): config.add_section(section)
 for mime,desktop in associations.items():
  old=[x for x in config[section].get(mime,'').split(';') if x and x!=desktop]
  config[section][mime]=';'.join([desktop]+(old if section=='Added Associations' else []))+';'
if config.has_section('Removed Associations'):
 for mime,desktop in associations.items():
  if mime in config['Removed Associations']:
   config['Removed Associations'][mime]=';'.join(x for x in config['Removed Associations'][mime].split(';') if x and x!=desktop)+';'
path.parent.mkdir(parents=True,exist_ok=True)
tmp=path.with_name('mimeapps.list.tmp')
with tmp.open('w') as f: config.write(f,space_around_delimiters=False)
os.replace(tmp,path)
