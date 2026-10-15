"""Import interface facts from audited upstream OpenAPI files (no server data)."""
import argparse
import json
from pathlib import Path
from panel_schema_overrides import OVERRIDES

parser = argparse.ArgumentParser()
parser.add_argument('--spec', required=True)
parser.add_argument('--baseline', required=True)
args = parser.parse_args()
spec = json.loads(Path(args.spec).read_text())
baseline = json.loads(Path(args.baseline).read_text())

# POST is not synonymous with mutation in the panel API. Everything not
# explicitly classified as a read requires confirmation, including diagnostics
# that initiate outbound network traffic or notify third-party services.
reads = {
    '/setting/all', '/setting/defaultSettings', '/setting/factoryDefaults',
    '/xray/', '/xray/balancerStatus', '/clients/ips/{email}',
    '/clients/hwids/{email}', '/clients/onlines', '/clients/onlinesByGuid',
    '/clients/clientIpsByGuid', '/clients/activeInbounds', '/clients/lastOnline',
    '/server/logs/{count}', '/server/xraylogs/{count}', '/server/amneziawglogs/{count}',
}

def schema_facts(value, document=None):
    document = document or spec
    if isinstance(value, list):
        return [schema_facts(v, document) for v in value]
    if not isinstance(value, dict):
        return value
    if '$ref' in value:
        ref = value['$ref'].split('/')[-1]
        return schema_facts(document['components']['schemas'][ref], document)
    return {k: schema_facts(v, document) for k, v in value.items()
            if k not in ('description', 'example', 'examples', 'title')}

operations = []
for path, methods in spec['paths'].items():
    if not path.startswith('/panel/api/') or path.endswith('/openapi.json'):
        continue
    for method, entry in methods.items():
        if method not in ('get', 'post', 'put', 'patch', 'delete'):
            continue
        short = path.removeprefix('/panel/api')
        body = entry.get('requestBody', {}).get('content', {})
        encoding = next(iter(body), 'application/json')
        operation = {
            'id': entry['operationId'], 'method': method.upper(), 'path': short,
            'group': short.split('/')[1],
            'write': method != 'get' and short not in reads,
            'since': '3.6.0' if method in baseline['paths'].get(path, {}) else '3.10.0',
            'encoding': encoding,
            'parameters': schema_facts(entry.get('parameters', [])),
            'body': OVERRIDES.get(short, schema_facts(body.get(encoding, {}).get('schema', {}))),
        }
        old = baseline['paths'].get(path, {}).get(method)
        # The 3.6 spec describes many real form/multipart routes as empty JSON
        # stubs. Those encodings come from the audited controllers (and live
        # regression), not the old spec. Token schemas are a verified behavioral
        # difference: old panels ignore scope/expiry/expectedScope entirely.
        if old is not None and short.startswith('/setting/apiTokens/'):
            content = old.get('requestBody', {}).get('content', {})
            old_encoding = next(iter(content), 'application/json')
            legacy = {'body': schema_facts(content.get(old_encoding, {}).get('schema', {}), baseline)}
            if any(operation[key] != value for key, value in legacy.items()):
                operation['legacy'] = legacy
        operations.append(operation)
Path('contracts/panel-operations.json').write_text(json.dumps(operations, ensure_ascii=False, indent=2) + '\n')
print(f'Imported {len(operations)} operations from audited upstream specs.')
