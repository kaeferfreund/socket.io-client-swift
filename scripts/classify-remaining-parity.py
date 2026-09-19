"""One-time, checked migration of the 44 reviewed upstream inventory rows."""
import collections, csv, json
from pathlib import Path
R=Path('.')
path=R/'Documentation/JavaScriptTestInventory.csv'
with path.open(newline='') as f:
    reader=csv.DictReader(f); fields=reader.fieldnames; rows=list(reader)
by={r['id']:r for r in rows}
original=[r['id'] for r in rows if r['status']=='unmapped']
expected=[133,137,138,139,140,141,142,143,144,145,146,147,148,158,163,164,165,168,169,170,171,172,178,179,180,181,182,183,186,194,195,196,197,201,202,220,223,240,241,242,246,247,248,257]
assert original==['JS-%03d'%i for i in expected],original
mp=R/'Documentation/JavaScriptParityContracts.json'; manifest=json.loads(mp.read_text())
assert manifest['remaining_unmapped_ids']==original
review=[]
classes={
 'E':('EngineRemainingParityE2ETest','Tests/TestSocketIO/E2E/EngineRemainingParityE2ETest.swift'),
 'U':('SocketRemainingParityTest','Tests/TestSocketIO/SocketRemainingParityTest.swift'),
 'P':('SocketRemainingBinaryParserTest','Tests/TestSocketIO/SocketRemainingBinaryParserTest.swift'),
}
def focused(ids, kind, description, tests):
    ids=['JS-%03d'%i for i in ids]
    evidence=[]
    for key,method in tests:
        cls,path=classes[key];evidence.append({'path':path,'symbol':cls+'.'+method})
    contract={'id':'remaining-'+ids[0].lower(),'kind':kind,'upstream_ids':ids,'assertions':[description],'tests':evidence}
    manifest['contracts'].append(contract)
    for id in ids:
        r=by[id];assert r['status']=='unmapped';r['status']='focused-regression'
        r['swift_tests']='; '.join(t['symbol'] for t in evidence)
        r['review_note']='Remaining-client review: '+description+' Native contract/adaptation only; see RemainingClientParity.md.'
        review.append({'id':id,'status':r['status'],'reason':description,'contract':contract['id']})
def boundary(ids, status, reason):
    for number in ids:
        id='JS-%03d'%number;r=by[id];assert r['status']=='unmapped'
        r['status']=status;r['swift_tests']='';r['review_note']=reason+' Not counted as an equivalent test port.'
        review.append({'id':id,'status':status,'reason':reason})
focused([133],'transferable-wire-regression','Forced base64 polling returns bytes 0...4; observer sees bAAECAwQ= in the actual POST body.', [('E','testForcedBase64Polling')])
focused([137,144],'transferable-wire-regression','Direct WebSocket and completed polling-to-WebSocket upgrade return bytes 0...4 and empty Data. Actual client frames are base64 text, not binary frames; handshake requests b64=1. Native Data replaces ArrayBuffer/Blob.', [('E','testForcedBase64WebSocket'),('E','testForcedBase64AfterActualTransportUpgrade')])
focused([139,140],'transferable-wire-regression','Native Data replaces Blob input/output. Bytes 0...4 and zero-length bytes survive the raw polling round trip in order; the engine API uses a separate text header.', [('E','testBinaryDataPolling')])
focused([141],'transferable-wire-regression','Five payloads at the original 72/20/20/20/72-byte boundaries are echoed in order. Every actual polling POST is at most the 100-byte advertised maxPayload. Includes base64 expansion and record separators.', [('E','testBinaryMaxPayloadBatching')])
focused([142,143],'transferable-wire-regression','Native Data replaces Blob input/output. WebSocket echoes bytes 0...4 and empty bytes; observer confirms binary frames, independently of the Socket.IO parser.', [('E','testBinaryDataWebSocket')])
focused([145],'native-assertion-equivalent','Raw localhost polling opens, then receives the unsolicited server greeting hi. Open precedes message delivery and the engine has a nonempty SID.', [('E','testConnectLocalhostPolling')])
focused([146],'native-assertion-equivalent','Raw localhost WebSocket opens, then receives the unsolicited server greeting hi. Open precedes message delivery and the engine has a nonempty SID.', [('E','testConnectLocalhostWebSocket')])
focused([147],'native-assertion-equivalent','The exact upstream string cash money followed by three euro symbols is echoed unchanged through raw polling.', [('E','testMultibyteUTF8Polling')])
focused([148],'native-assertion-equivalent','The exact upstream Unicode scalar sequence U+10000 through U+10FFFF and private-use endpoints U+E000/U+F8FF is echoed unchanged, not merely a common emoji.', [('E','testUnicodeScalarBoundaries')])
focused([165],'native-URI-equivalent','addTrailingSlash(false) emits /engine.io? on the wire, with no slash before the query. Custom paths are normalized independently of option order; the default retains the slash.', [('E','testNoTrailingSlashOnWire'),('U','testTrailingSlashIndependentOfConfigurationOrder')])
focused([178],'native-cookie-contract','Server-set cookies are sent on subsequent polling POSTs and on the WebSocket upgrade only when enabled. The isolated jar survives reconnect and is not shared with another engine or the application jar.', [('E','testServerCookiesSentWhenEnabled'),('E','testCookiesSurvivePollingToWebSocketUpgrade'),('U','testEnabledCredentialsUsePrivateStoreAndSurviveReconnect')])
focused([179],'native-cookie-contract','Disabled credentials do not resend server cookies in polling or the WebSocket upgrade, and do not read a pre-populated engine jar. Explicit application Cookie headers remain explicit.', [('E','testServerCookiesNotSentWhenDisabled'),('E','testDisabledCookiesStayDisabledDuringUpgrade'),('U','testDisabledCredentialsNeverReadStoredCookiesForWebSocket'),('U','testExplicitCookieHeaderRemainsExplicitWhenCredentialsDisabled')])
focused([180],'native-cookie-contract','Foundation parses the upstream simple foo=bar cookie into the same name and value. The native cookie object and browser CORS semantics are not claimed to be identical to the Node CookieJar.', [('U','testSimpleNativeCookieParsing')])
focused([182],'native-cookie-contract','Foundation preserves the entire upstream cookie value bar=bar&foo=foo&John=Doe&Doe=John, including equals signs and ampersands.', [('U','testCookieValueContainingEqualsAndAmpersands')])
focused([194],'native-error-contract','A 101-byte payload against maxHttpBufferSize=100 produces polling write error HTTP 413 and a transport error close carrying structured detail.', [('E','testOversizePollingReports413AndCloseDetail')])
focused([195],'native-error-contract','A 101-byte WebSocket payload against maxHttpBufferSize=100 closes with peer code 1009. A simultaneous receive error must not erase the peer close code or turn it into a generic error close.', [('E','testOversizeWebSocketReports1009AndCloseDetail'),('U','testCloseDetailIncludesPeerCodeEvenWithReceiveError')])
focused([196],'native-error-contract','An actual stale-SID polling GET reports HTTP 400 and the exact Session ID unknown JSON body, followed by one detailed transport error close.', [('E','testUnknownSIDPollingReports400BodyAndCloseDetail')])
focused([197],'native-error-contract','An actual stale-SID WebSocket handshake fails and closes with native transport detail. URLSession need not expose the HTTP rejection status; no fabricated XHR or CloseEvent object is claimed.', [('E','testUnknownSIDWebSocketReportsErrorAndCloseDetail')])
focused([220,223],'transferable-wire-regression','A custom extraHeaders value reaches both actual polling GET and POST requests. URLSession replaces browser/Node XMLHttpRequest; browser CORS/preflight is not implemented by this native test.', [('E','testExtraHeadersReachPollingGETAndPOST')])
focused([240],'native-data-regression','Original two-zero-byte ArrayBuffer payload is represented by Data at namespace /, id 0. Exact header and attachment bytes also have an independent assertion; native encode/decode preserves the payload.', [('P','testArrayBufferEquivalentHasExactWireAndAttachment')])
focused([242],'native-data-regression','Original typed-array bytes 0...4 survive Data encoding at namespace / and id 0. A sliced buffer excludes sentinel prefix/suffix bytes without modifying its source.', [('P','testTypedArrayEquivalentEncodesOnlySelectedBytes')])
focused([246],'native-data-regression','Original two-zero-byte Blob payload is adapted to native Data at namespace / and id 0; empty and high-bit byte payloads also round-trip.', [('P','testBlobEquivalentPreservesEmptyAndNonemptyData')])
focused([247],'native-data-regression','The original nested hi/why/binary/bye event at /deep with id 999 encodes and reconstructs unchanged using Data instead of Blob. Additional null/nested inputs remain intact.', [('P','testBlobEquivalentDeepInJSON')])
focused([248],'native-data-regression','The original hi ack/why/binary/bye ack payload at /deep with id 999 encodes as a binary ACK and reconstructs unchanged using Data instead of Blob.', [('P','testBinaryAckBlobEquivalent')])
focused([257],'native-assertion-equivalent','All seven public native SocketPacket.PacketType values correspond to protocol type numbers 0 through 6.', [('P','testPublicPacketTypesMatchWireNumbers')])
boundary([138],'platform-specific','Deleting JavaScript ArrayBuffer and receiving its browser fallback wrapper has no native runtime analogue. Swift always receives Data; the transferable base64 wire path is tested under JS-133.')
boundary([158],'api-difference','The standalone JS package exports a numeric protocol constant. Swift exposes a fused Engine.IO transport with SocketIOVersion and generated EIO query values, not the same module export. Native EIO 3/4 values have a separate unit regression.')
boundary([163,164,168,169,170,171],'api-difference','These use JS new Socket({host,port,secure}) option-object overloads, including unbracketed IPv6 hosts. Swift requires an explicit Foundation URL; absolute URL cases are covered separately. No implicit-host constructor or identical default-location inference is promised.')
boundary([172],'api-difference','The JS internal randomString helper promises eight characters and different consecutive values. Swift does not expose that helper or its exact length; wire cache-busting uses a separate native contract, not a fabricated compatible helper.')
boundary([181],'api-difference','The Node cookie parser returns only name/value/expires and overwrites expiry in header iteration order. Foundation preserves domain/path/security and owns native expiration policy. The conflicting Max-Age/Expires sample is not declared object-for-object equivalent; native parsing and security scope have separate tests.')
boundary([183],'api-difference','The standalone JS parseuri helper exposes a parsed-component object and handles a corpus of shorthand inputs. Swift uses Foundation URL/URLComponents instead; no identical public parseuri result or input grammar is promised. Absolute transport URL validation remains separately tested.')
boundary([186],'api-difference','JS can be configured with transports: [] and reports No transports available. Swift has fixed native transports and rejects contradictory forcePolling/forceWebsockets options; the empty transport-list API is not representable. A fail-before-network native configuration test remains.')
boundary([201,202],'api-difference','JavaScript exports public Transport/Polling/WebSocket constructors. Swift provides SocketEngine and internal native transport protocols instead; adding artificial JS constructor exports is outside the native API contract.')
boundary([241],'platform-specific','Object.create(null) and prototype lookup are JavaScript-specific. Swift dictionaries have no JavaScript prototype. A native special-key/binary dictionary regression exists, but is not labelled a literal null-prototype test port.')
assert len(review)==44 and len(set(x['id'] for x in review))==44
manifest['remaining_unmapped_ids']=[]
manifest['remaining_review']={'baseline_sha':'c905f4f869bdd208ad04269a855e3ac2438abddd','original_unmapped_ids':original,'dispositions':sorted(review,key=lambda x:x['id']),'meaning':'All prior unmapped rows now have an explicit native regression or API/platform boundary. This is classification completeness, NOT full assertion parity.'}
mp.write_text(json.dumps(manifest,indent=2)+'\n')
with path.open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(rows)
sp=R/'Documentation/ReviewEvidence/InventorySummary.json';summary=json.loads(sp.read_text());summary['review_statuses']=dict(collections.Counter(r['status'] for r in rows));summary['review_statuses']['unmapped']=0
sp.write_text(json.dumps(summary,indent=2)+'\n')
print(collections.Counter(r['status'] for r in review))
