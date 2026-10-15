"""Import audited 3m-ui v1.4.1 routes; run with an external upstream checkout.

Requires PyYAML only on the developer machine, never on the SSH host.
The upstream OpenAPI has misplaced trailing paths; normalize without changing it.
"""
import argparse
import json
import re
from pathlib import Path
import yaml

parser = argparse.ArgumentParser()
parser.add_argument('checkout', type=Path)
args = parser.parse_args()
root = args.checkout / 'backend'
raw = (root / 'docs/openapi.yaml').read_text()
head, tail = raw.split('\nsecurity:', 1)
spec = yaml.safe_load(head)
extra = re.search(r'\n  /', tail)
if extra:
    spec['paths'].update(yaml.safe_load('paths:' + tail[extra.start():])['paths'])

def resolve(v, depth=0):
    if depth > 20:
        return {}
    if isinstance(v, list):
        return [resolve(x, depth+1) for x in v]
    if not isinstance(v, dict):
        return v
    if '$ref' in v:
        value = spec
        for part in v['$ref'].split('/')[1:]:
            value = value[part.replace("~1", "/").replace("~0", "~")]
        return resolve(value, depth+1)
    return {k: resolve(x, depth+1) for k, x in v.items() if k not in ('example', 'examples')}

# Router registrations, rather than incomplete documentation, define reachability.
sources = {
    'internal/listener/api.go': '/listeners', 'internal/user/api.go': '/users',
    'internal/system/api.go': '/system', 'internal/auth/api.go': '/auth',
    'internal/acme/api.go': '/system', 'internal/subpage/api.go': '/system',
    'internal/telegram/api.go': '/telegram', 'internal/cluster/api.go': '/cluster',
    'internal/traffic/api.go': '/traffic', 'internal/protocol/api.go': '',
    'internal/router/dashboard.go': '', 'internal/router/panel_settings.go': '',
    'internal/router/panel_server.go': '', 'internal/router/access_token.go': '',
    'internal/router/mihomo_routes.go': '/mihomo', 'internal/router/config_routes.go': '/config',
    'internal/router/routing_routes.go': '/config',
}
routes = set()
handlers = {}
for file, prefix in sources.items():
    code = (root / file).read_text()
    for method, path in re.findall(r'\.(GET|POST|PUT|DELETE|PATCH)\("([^"]*)"', code):
        path = re.sub(r':(\w+)', r'{\1}', prefix+path)
        if path in ('/auth/login', '/auth/oauth/github/start', '/auth/oauth/github/callback'):
            continue
        routes.add((method, path))
for method, path in list(routes):
    if path.startswith('/listeners'):
        routes.add((method, path.replace('/listeners', '/nodes', 1)))
for method, path in [('GET','/nodes/{id}/uri'), ('POST','/nodes/{id}/client-access'), ('POST','/nodes/{id}/connection-check')]:
    routes.add((method,path))

def fields(**props):
    return {'type': 'object', 'properties': {k: {'type': v} for k,v in props.items()}}

# Exact request DTOs supplement incomplete OpenAPI schemas.
def dto(file, name):
    code = (root / file).read_text()
    body = re.search(r'type '+name+r' struct \{(.*?)\n\}', code, re.S)[1]
    props = {}
    for typ,key in re.findall(r'\w+\s+([^\s]+)\s+`[^`]*json:"([^",]+)',body):
        if key == '-': continue
        typ = typ.lstrip('*')
        props[key] = {'type': 'boolean' if typ == 'bool' else 'integer' if typ in ('int','int64','uint') else 'number' if typ == 'float64' else 'string'}
        if typ == 'time.Time': props[key].update(format='date-time')
    return {'type':'object','properties':props}

def go_schema(typ):
    typ=typ.lstrip('*')
    if typ.startswith('[]'): return {'type':'array','items':go_schema(typ[2:])}
    if typ.startswith('map[') or typ in ('interface{}','any'): return {'type':'object'}
    if typ in ('bool',): return {'type':'boolean'}
    if typ in ('int','int64','uint','uint64'): return {'type':'integer'}
    if typ in ('float64','float32'): return {'type':'number'}
    return {'type':'string', **({'format':'date-time'} if typ=='time.Time' else {})}

def struct_schema(body):
    props={key:go_schema(typ) for typ,key in re.findall(r'\w+\s+([^\s]+)\s+`[^`]*json:"([^",]+)',body) if key!='-'}
    return {'type':'object','properties':props}

inferred={}
for file,prefix in sources.items():
    code=(root/file).read_text()
    for match in re.finditer(r'\.(GET|POST|PUT|DELETE|PATCH)\("([^"]*)",\s*(?:h\.(\w+)|func)',code):
        method,path,name=match.groups()
        path=re.sub(r':(\w+)',r'{\1}',prefix+path)
        if name:
            fn=re.search(r'func \(h \*\w+\) '+name+r'\(.*?(?=\nfunc |\Z)',code,re.S)
            body=fn[0] if fn else ''
        else:
            body=re.split(r'\n\t(?:api|group|rg)\.(?:GET|POST|PUT|DELETE|PATCH)\(',code[match.end():],maxsplit=1)[0]
        request=re.search(r'var \w+ struct \{(.*?)\n\s*\}',body,re.S)
        schema=struct_schema(request[1]) if request else {}
        named=re.search(r'var \w+ ([\w.]+)\s*\n',body)
        if not schema and named:
            typ=named[1].split('.')[-1]
            candidates=list((root/file).parent.glob('*.go'))
            if '.' in named[1]:candidates += list((root/'internal/database/models').glob('*.go'))
            for candidate in candidates:
                definition=re.search(r'type '+typ+r' struct \{(.*?)\n\}',candidate.read_text(),re.S)
                if definition:
                    schema=struct_schema(definition[1]);break
        queries=[{'name':key,'in':'query','schema':{'type':'string'}} for key in sorted(set(re.findall(r'c\.(?:Query|DefaultQuery)\("([^"]+)"',body)))]
        inferred[method,path]=(schema,queries)
for (method,path),facts in list(inferred.items()):
    if path.startswith('/listeners'): inferred[method,path.replace('/listeners','/nodes',1)]=facts

listener = dto('internal/database/models/listener.go','Listener')
user_create = dto('internal/user/service.go','CreateInput')
user_update = dto('internal/user/service.go','UpdateInput')
overrides = {
    ('POST','/users'): user_create, ('PUT','/users/{id}'): user_update,
    ('POST','/auth/password'): fields(current_password='string',new_password='string'),
    ('POST','/auth/totp/enable'): fields(code='string'),
    ('POST','/auth/totp/disable'): fields(password='string',code='string'),
    ('POST','/mihomo/update'): fields(version='string'),
    ('POST','/config/apply'): fields(config='string'),
    ('POST','/config/preview'): fields(config='string'),
    ('POST','/config/validate'): fields(config='string'),
}
for prefix in ('/listeners','/nodes'):
    overrides.update({('POST',prefix):listener, ('PUT',prefix+'/{id}'):listener,
        ('POST',prefix+'/quick'):fields(name='string',protocol='string'),
        ('POST',prefix+'/generate'):fields(kind='string',cipher='string'),
        ('POST',prefix+'/batch'):{'type':'array','items':listener},
        ('POST',prefix+'/batch/enabled'):{'type':'object','properties':{'ids':{'type':'array','items':{'type':'integer'}},'enabled':{'type':'boolean'}}},
        ('POST',prefix+'/{id}/clone'):fields(name='string',port='string')})
for suffix in ('listeners','nodes'):
    overrides['POST','/users/{id}/'+suffix]={'type':'object','properties':{'listener_ids':{'type':'array','items':{'type':'integer'}}}}
ops=[]
for method,path in sorted(routes):
    source = resolve(spec['paths'].get(path, {}))
    info = source.get(method.lower(), {})
    content = info.get('requestBody',{}).get('content',{})
    encoding = next(iter(content),'application/json')
    if path == '/system/backup/restore-db': encoding='multipart/form-data'
    inferred_body,queries=inferred.get((method,path),({},[]))
    parameters = info.get('parameters', source.get('parameters',[]))
    parameters = [p for p in parameters if isinstance(p,dict)]
    for query in queries:
        if not any(p.get('name')==query['name'] for p in parameters): parameters.append(query)
    for key in re.findall(r'\{(\w+)\}',path):
        if not any(p.get('name')==key for p in parameters):
            parameters.append({'in':'path','name':key,'required':True,'schema':{'type':'integer' if key.lower().endswith('id') or key in ('version','index') else 'string'}})
    ops.append({'id':'3m.'+method.lower()+'.'+path.strip('/').replace('/','.'),
        'panelType':'3m-ui','method':method,'path':path,'group':'3m-'+(path.split('/')[1] if path and path!='/{id}' else 'access-tokens'),
        'label':info.get('summary',method+' '+path),
        'write':method!='GET','since':'1.4.1','encoding':encoding,'parameters':parameters,
        'body':overrides.get((method,path),inferred_body or content.get(encoding,{}).get('schema',{}))})
Path('contracts/3m-operations.json').write_text(json.dumps(ops,ensure_ascii=False,indent=2)+'\n')
print(f'Imported {len(ops)} registered 3m-ui operations')
