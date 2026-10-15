#!/usr/bin/env python3
"""Only for 5a-ui-owned new 3m-ui installations; existing panels use panel.py."""
import json
import os
from pathlib import Path
import secrets
import shlex
import socket
import sys
import time
import urllib.error
import urllib.request
import manage as common

ROOT = common.ROOT
CONFIG = Path('/etc/3m-ui/config.yaml')
TOKEN = ''


def prepare():
    connection=common.read('3m-connection.json')
    if not connection:
        if CONFIG.exists() or Path('/var/lib/3m-ui/3m-ui.db').exists():
            raise RuntimeError('Existing 3m-ui is not owned by this installation')
        request=common.read('request.json')
        with socket.socket() as sock:
            sock.bind(('127.0.0.1',0))
            port=sock.getsockname()[1]
        if port==request['nodePort']: return prepare()
        connection={'username':'5a_ui_'+secrets.token_hex(6),'password':secrets.token_urlsafe(32),
            'bootstrapPassword':secrets.token_urlsafe(32),'panelPort':port,'webPath':'',
            'nodePort':request['nodePort'],'host':request['host']}
        common.write('3m-connection.json',connection)
    # Let the official bootstrap create config + DB together. A precreated
    # config with no DB is treated as an existing installation by its read-only
    # storage audit. Environment overrides bind the very first start privately.
    env=ROOT/'3m-panel.env'
    with env.open('w') as output:
        os.chmod(env,0o600)
        for key,value in {'THREE_M_UI_ADMIN_USERNAME':connection['username'],
            'THREE_M_UI_ADMIN_PASSWORD':connection['bootstrapPassword'],
            'THREE_M_UI_PORT':str(connection['panelPort']),
            'THREE_M_UI_CONFIG':str(CONFIG),'THREE_M_UI_LISTEN':'127.0.0.1',
            'THREE_M_UI_SUB_PORT':'0','THREE_M_UI_SUB_LISTEN':'127.0.0.1'}.items():
            output.write(key+'='+shlex.quote(value)+'\n')


def api(path,method='GET',data=None):
    connection=common.read('3m-connection.json')
    base='http://127.0.0.1:'+str(connection['panelPort'])+connection['webPath']+'/api/v1'
    headers={'Content-Type':'application/json','Authorization':'Bearer '+TOKEN}
    payload=json.dumps(data if data is not None else {}).encode() if method!='GET' else None
    request=urllib.request.Request(base+path,data=payload,headers=headers,method=method)
    with common.OPENER.open(request,timeout=20) as response:
        value=json.load(response)
    if isinstance(value,dict) and (value.get('error') or value.get('valid') is False):
        raise RuntimeError('3m-ui rejected operation')
    return value


def login():
    global TOKEN
    connection=common.read('3m-connection.json')
    for password in (connection['password'],connection.get('bootstrapPassword')):
        if not password: continue
        try:
            result=api('/auth/login','POST',{'username':connection['username'],'password':password})
        except urllib.error.HTTPError as error:
            if error.code==401: continue
            raise
        TOKEN=result['token']
        if result.get('must_change_password'):
            result=api('/auth/password','POST',{'current_password':password,'new_password':connection['password']})
            TOKEN=result['token']
        return
    raise RuntimeError('Managed credentials changed; refusing to reset account')


def configure():
    for attempt in range(20):
        try:
            login()
            break
        except (urllib.error.URLError, OSError):
            if attempt == 19: raise
            time.sleep(1)
    connection=common.read('3m-connection.json')
    listeners=api('/listeners') or []
    listener=next((i for i in listeners if i['name']=='5a-ui-vless'),None)
    if listener is None:
        if any(str(i['port'])==str(connection['nodePort']) for i in listeners):
            raise RuntimeError('Node port belongs to another listener')
        target=common.choose_target(common.read('request.json'))
        config={'security_layer':'reality','transport_layer':'raw','flow':'xtls-rprx-vision',
            'reality-config':{'dest':target+':443','server-names':[target]}}
        listener=api('/listeners','POST',{'name':'5a-ui-vless','protocol':'vless','type':'vless',
            'port':str(connection['nodePort']),'bind_address':'0.0.0.0','enabled':True,
            'public_host':connection['host'],'client_fingerprint':'chrome','config':json.dumps(config)})
    elif listener['protocol']!='vless' or str(listener['port'])!=str(connection['nodePort']):
        raise RuntimeError('Managed listener changed; refusing to overwrite')
    connection['listenerId']=listener['id']
    common.write('3m-connection.json',connection)
    users=api('/users') or []
    user=next((u for u in users if u['username']=='5a-ui'),None)
    if user is None:
        user=api('/users/quick','POST',{'username':'5a-ui','remark':'5a-ui managed node'})['user']
    connection['userId']=user['id']
    common.write('3m-connection.json',connection)
    bindings=api('/users/'+str(user['id'])+'/listeners') or []
    if not bindings:
        api('/users/'+str(user['id'])+'/listeners','POST',{'listener_ids':[listener['id']]})
    elif {b['id'] for b in bindings}!={listener['id']}:
        raise RuntimeError('Managed bindings changed; refusing to overwrite')
    api('/config/apply','POST',{})
    if not api('/mihomo/status').get('running'):
        api('/mihomo/start','POST',{})


def check():
    login()
    connection=common.read('3m-connection.json')
    for _ in range(20):
        try:
            with socket.create_connection(('127.0.0.1',connection['nodePort']),timeout=2): pass
            if not api('/mihomo/status').get('running'): raise RuntimeError('Mihomo stopped')
            share=api('/nodes/'+str(connection['listenerId'])+'/uri')
            if not share.get('uri','').startswith('vless://'): raise RuntimeError('Share unavailable')
            return
        except (OSError,RuntimeError): time.sleep(1)
    raise RuntimeError('Mihomo node did not become available')


def status():
    state=common.read('state.json',{'phase':'not-installed','message':'尚未完成安装。'})
    if state['phase']!='ready': return state
    login()
    config=common.read('3m-connection.json')
    share=api('/nodes/'+str(config['listenerId'])+'/uri')
    state.update({'installed':True,'running':True,'node':{'host':config['host'],'port':config['nodePort'],
        'serverName':'','link':share['uri']},'message':'3m-ui 节点已创建，请读取实例管理以检查运行情况。'})
    return state


if __name__=='__main__':
    os.umask(0o077)
    command=sys.argv[1]
    if command=='status': print('5A_UI_RESULT='+json.dumps(status()))
    elif command in ('prepare','configure','check'): globals()[command]()
    else: raise SystemExit('Unknown command')
