"""Body facts missing from upstream OpenAPI; audited against 3x-ui controllers.

Keep these small and explicit. Complete inbound, client and setting editors use
read-back data, preserving protocol-specific and future fields.
"""

STRING = {'type': 'string'}
INTEGER = {'type': 'integer'}
BOOLEAN = {'type': 'boolean'}
STRINGS = {'type': 'array', 'items': STRING}
INTEGERS = {'type': 'array', 'items': INTEGER}


def obj(**properties):
    return {'type': 'object', 'properties': properties}


OVERRIDES = {
    '/inbounds/bulkDel': obj(ids=INTEGERS),
    '/inbounds/setEnable/{id}': obj(enable=BOOLEAN),
    '/inbounds/{id}/subSortIndex': obj(subSortIndex=INTEGER),
    '/clients/import': obj(data=STRING),
    '/clients/bulkAdjust': obj(emails=STRINGS, addDays=INTEGER, addBytes=INTEGER, flow=STRING, adTag=STRING),
    '/clients/bulkEnable': obj(emails=STRINGS),
    '/clients/bulkDisable': obj(emails=STRINGS),
    '/clients/bulkDel': obj(emails=STRINGS, keepTraffic=BOOLEAN),
    '/clients/bulkResetTraffic': obj(emails=STRINGS),
    '/clients/groups/create': obj(name=STRING),
    '/clients/groups/rename': obj(oldName=STRING, newName=STRING),
    '/clients/groups/delete': obj(name=STRING),
    '/clients/groups/resetTraffic': obj(name=STRING),
    '/clients/groups/bulkAdd': obj(emails=STRINGS, group=STRING),
    '/clients/groups/bulkRemove': obj(emails=STRINGS),
    '/clients/updateTraffic/{email}': obj(upload=INTEGER, download=INTEGER),
    '/nodes/setEnable/{id}': obj(enable=BOOLEAN),
    '/nodes/mtls/trustCA': obj(caCert=STRING),
    '/nodes/updatePanel': obj(ids=INTEGERS, dev=BOOLEAN),
    '/hosts/setEnable/{groupId}': obj(enable=BOOLEAN),
    '/hosts/reorder': obj(ids=STRINGS),
    '/hosts/bulk/setEnable': obj(ids=STRINGS, enable=BOOLEAN),
    '/hosts/bulk/del': obj(ids=STRINGS),
}

# ClientController.bulkCreate binds a list, although OpenAPI calls it an object.
OVERRIDES['/clients/bulkCreate'] = {'type': 'array', 'items': obj(client=obj(email=STRING, enable=BOOLEAN, totalGB=INTEGER, expiryTime=INTEGER), inboundIds=INTEGERS)}
for path in ('/hosts/add', '/hosts/update/{groupId}', '/hosts/bulk/add'):
    OVERRIDES[path] = obj(inboundIds=INTEGERS, hosts=STRINGS, remark=STRING, isDisabled=BOOLEAN,
                          port=INTEGER, security={'type': 'string', 'default': 'same'}, sni=STRING,
                          path=STRING, tags=STRINGS, alpn=STRINGS, fingerprint=STRING)
for path in ('/nodes/add', '/nodes/update/{id}', '/nodes/test', '/nodes/certFingerprint', '/nodes/inbounds'):
    OVERRIDES[path] = obj(name=STRING, scheme={'type': 'string', 'default': 'https'},
                         address=STRING, port={'type': 'integer', 'default': 443}, basePath=STRING,
                         apiToken=STRING, enable=BOOLEAN, allowPrivateAddress=BOOLEAN,
                         tlsVerifyMode={'type': 'string', 'default': 'verify'},
                         inboundSyncMode={'type': 'string', 'default': 'all'}, inboundTags=STRINGS)
