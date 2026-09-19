"""Materialize the locally reviewed merge; upload objects without moving any ref."""
from pathlib import Path
import subprocess, json, csv, io, collections, re, os, urllib.request
root = Path.cwd()
base = 'c905f4f869bdd208ad04269a855e3ac2438abddd'
EXPECTED_TREE = '040c16983f64cc9b254a60a5cefa7b8b43ce9661'
TARGET = '3237747dbf6486bc59672288c5e6df25eaf369f7'

def git(*args):
    return subprocess.check_output(['git', *args], cwd=root, text=True)

def read(ref, path):
    return git('show', f'{ref}:{path}')

def merge3(a, b, c):
    if b == c: return b
    if a == b: return c
    if a == c: return b
    raise ValueError('Overlapping semantic edit outside the reviewed resolution')

p = 'Documentation/JavaScriptParityContracts.json'
a, b, c = [json.loads(read(ref, p)) for ref in (base, 'source', 'target')]
merged = {}
for key in set(a) | set(b) | set(c):
    if key == 'contracts':
        A, B, C = [{x['id']: x for x in d[key]} for d in (a, b, c)]
        order = list(B) + [k for k in C if k not in B]
        merged[key] = [merge3(A.get(k), B.get(k), C.get(k)) for k in order]
    else:
        merged[key] = merge3(a.get(key), b.get(key), c.get(key))
merged = {k: merged[k] for k in list(b) + [k for k in c if k not in b]}
(root / p).write_text(json.dumps(merged, indent=2) + '\n')
p = 'Documentation/JavaScriptTestInventory.csv'
allrows = [list(csv.DictReader(io.StringIO(read(ref, p)))) for ref in (base, 'source', 'target')]
a, b, c = [{v['id']: v for v in d} for d in allrows]
rows = [merge3(a.get(k), b.get(k), c.get(k)) for k in b]
with (root / p).open('w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=list(allrows[0][0]), lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
p = 'Documentation/ReviewEvidence/InventorySummary.json'
summary = json.loads(read('source', p))
summary['review_statuses'] = dict(collections.Counter(row['status'] for row in rows))
(root / p).write_text(json.dumps(summary, indent=2) + '\n')

def replace_conflicts(path, replacements):
    p = root / path
    s = p.read_text()
    matches = list(re.finditer(r'^<<<<<<<[^\n]*\n(.*?)^=======\n(.*?)^>>>>>>>[^\n]*\n', s, re.M | re.S))
    assert len(matches) == len(replacements), (path, len(matches))
    for match, replacement in reversed(list(zip(matches, replacements))):
        s = s[:match.start()] + replacement + s[match.end():]
    p.write_text(s)

replace_conflicts('Source/SocketIO/Engine/SocketEngine.swift', ['''        messages += data.map {
            forceBase64 ? .text("b" + $0.base64EncodedString()) : .binary($0)
        }
'''])
replace_conflicts('Source/SocketIO/Engine/SocketEngineSpec.swift', ['''        if polling || forceBase64 { return .right("b" + data.base64EncodedString()) }
        return .left(data)
'''])
replace_conflicts('Source/SocketIO/Util/SocketExtensions.swift', ['''        case ("version", _):
            return .invalidConfiguration("The version option was removed. Only Socket.IO 4.x (Engine.IO 4) is supported; remove version from configuration.")
        case ("withCredentials", _), ("forceBase64", _), ("addTrailingSlash", _):
            return .invalidConfiguration("invalid value for " + key + "; expected Bool")
'''])
p = root / 'Tests/TestSocketIO/SocketClearAcksOnCloseTest.swift'
s = p.read_text()
start = s.index('    @MainActor\n    func testAsyncEmitWithAckThrowsDisconnectedOnATransportDropThatReconnects() async {')
end = s.index('\n}\n\n/// Fake transport', start)
s = s[:start] + '''    @MainActor
    func testAsyncEmitWithAckThrowsDisconnectedOnATransportDropThatReconnects() async {
        let initial = expectation(description: "initial connect")
        let registered = expectation(description: "emit reached the fake transport")
        let rejoined = expectation(description: "namespace re-joined")
        let thrown = expectation(description: "await throws the disconnect error")
        manager = SocketManager(socketURL: URL(string: "http://localhost/")!,
            config: [.log(false), .reconnects(true), .reconnectWait(0), .ackTimeout(10)])
        engine = ClearAcksTestEngine(client: manager, url: manager.socketURL, options: nil)
        manager.engine = engine
        socket = manager.defaultSocket
        socket.once(clientEvent: .connect) { _, _ in initial.fulfill() }
        engine.onEventWrite = { registered.fulfill() }
        socket.connect()
        await fulfillment(of: [initial], timeout: 5)

        let boxed = SocketUncheckedSendableBox(socket!)
        let task = Task {
            do {
                _ = try await boxed.value.emitWithAck("echo", "a")
                XCTFail("the acknowledgement must not resolve")
            } catch {
                XCTAssertEqual(error as? SocketAckError, .disconnected)
            }
            thrown.fulfill()
        }
        defer { task.cancel() }
        await fulfillment(of: [registered], timeout: 5)
        socket.once(clientEvent: .connect) { _, _ in rejoined.fulfill() }
        engine.dropTransport(reason: "transport close")
        await fulfillment(of: [thrown, rejoined], timeout: 5)
        XCTAssertTrue(socket.ackHandlers.pendingTimedAckIDs.isEmpty)
        XCTAssertEqual(socket.status, .connected)
        _ = await task.value
    }
''' + s[end:]
p.write_text(s)
for name in ['Source/SocketIO/Engine/SocketEngine.swift', 'Source/SocketIO/Manager/SocketManager.swift',
             'Tests/TestSocketIO/E2E/EngineRemainingParityE2ETest.swift', 'Tests/TestSocketIO/SocketRemainingParityTest.swift']:
    p = root / name
    s = re.sub(r'\.async(?=[ {(])', '.socketAsync', p.read_text())
    s = re.sub(r'\.asyncAfter(?=\()', '.socketAsyncAfter', s)
    p.write_text(s)
p = root / 'Tests/TestSocketIO/E2E/EngineRemainingParityE2ETest.swift'
p.write_text(p.read_text().replace('    func engineDidSendPing() {}\n', ''))
p = root / '.github/workflows/swift.yml'
s = p.read_text().replace('branches: [ "master", "development" ]', 'branches: [ "master", "development", "feat/socketio4-swift6.4" ]').replace('branches: [ "master", "development", "feat/connect-timeout" ]', 'branches: [ "master", "development", "feat/connect-timeout", "feat/socketio4-swift6.4" ]')
p.write_text(s)
p = root / 'Tests/TestSocketIO/SocketRemainingParityTest.swift'
s = p.read_text().replace('    func engineDidSendPing() {}\n', '')
s = s.replace('''    func testProtocolVersionsHaveNativeWireConstants() {
        XCTAssertEqual(engine().engineIOParam, "&EIO=4")
        XCTAssertEqual(engine([.version(.two)]).engineIOParam, "&EIO=3")
    }''', '''    func testProtocolVersionsHaveNativeWireConstants() {
        // Version selection is removed in the integration branch. Every
        // transport configuration must retain the Engine.IO 4 wire constant.
        for options: [SocketIOClientOption] in [[], [.forcePolling(true)],
                [.forceWebsockets(true)], [.forceBase64(true)]] {
            XCTAssertEqual(engine(options).engineIOParam, "&EIO=4")
        }
    }''')
a = s.index('    func testForcedBase64ControlsWebSocketBatch() {')
b = s.index('\n    private func cookie', a)
s = s[:a] + '''    func testForcedBase64ControlsWebSocketBatch() {
        for base64 in [false, true] {
            let instance = engine([.forceWebsockets(true), .forceBase64(base64)])
            let transport = RemainingUnitTransport()
            instance.webSocketTransportFactory = { _ in transport }
            instance.connect(); settle(instance)
            transport.onEvent?(.opened(protocol: nil)); settle(instance)
            instance.sendWebSocketMessage("header", withType: .message, withData: [Data([0, 1, 2]), Data()], completion: nil)
            settle(instance)
            instance.engineQueue.sync {
                let expected: [EngineWebSocketMessage] = base64
                    ? [.text("4header"), .text("bAAEC"), .text("b")]
                    : [.text("4header"), .binary(Data([0, 1, 2])), .binary(Data())]
                XCTAssertEqual(transport.messages, expected)
                XCTAssertEqual(instance.urlWebSocket.query?.contains("b64=1"), base64)
                XCTAssertEqual(instance.engineIOParam, "&EIO=4")
            }
            instance.disconnect(reason: "test"); settle(instance)
        }
    }
''' + s[b:]
p.write_text(s)
p = root / 'Source/SocketIO/Manager/SocketManager.swift'
p.write_text(p.read_text().replace('handleQueue.socketAsyncAfter(deadline: .now() + timeout, execute: timer)', 'handleQueue.asyncAfter(deadline: .now() + timeout, execute: timer)'))
p = root / 'Documentation/RemainingClientParity.md'
s = p.read_text().replace('The inventory still contains 70 candidate mappings', 'After integration with the Swift 6.4 branch, the inventory still contains 68 candidate mappings')
s += '''
## Integration into the Socket.IO 4 / Swift 6.4 branch

This follow-up is merged with `feat/socketio4-swift6.4` at
`3237747dbf6486bc59672288c5e6df25eaf369f7`, not into `master`.
The combined implementation retains `swift-tools-version:6.4`, Swift 6 language
mode, the Xcode 27 runner, and the removal of Socket.IO version selection and
Engine.IO 3 framing. Forced base64 is always the Engine.IO 4 `b` prefix; neither
`b4` nor the legacy binary packet prefix is restored.

The new raw Engine.IO test callbacks use the existing serial-queue transfer
helper. The async transport-drop acknowledgement regression waits for an actual
write-registration signal, without blocking MainActor. Test contracts from both
branches are retained; inventory totals are regenerated from the merged rows.
The full CI also runs for pull requests targeting and pushes to this integration
branch, including its strict-concurrency and Thread Sanitizer checks.
'''
p.write_text(s)
subprocess.run(['python3', 'scripts/test-review-regressions.py'], check=True)
subprocess.run(['python3', 'scripts/check-parity-contracts.py'], check=True)
git('add', '-A')
git('diff', '--cached', '--check')
assert git('write-tree').strip() == EXPECTED_TREE, 'Merge differs from locally reviewed tree'
assert not list((root / '.github').rglob('*parity-merge*')), 'Temporary files must not enter the final tree'

def api(path, data):
    request = urllib.request.Request('https://api.github.com/repos/kaeferfreund/socket.io-client-swift/' + path,
        data=json.dumps(data).encode(), method='POST', headers={
            'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
            'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28',
            'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)

known = set()
for ref in ['source', 'target']:
    for line in git('ls-tree', '-r', ref).splitlines():
        known.add(line.split()[2])
elements = []
for line in git('diff', '--cached', '--raw', '--no-abbrev', '--no-renames', 'target').splitlines():
    metadata, path = line.split('\t', 1)
    oldmode, mode, oldsha, sha, status = metadata.split()
    if status == 'D':
        elements.append({'path': path, 'mode': oldmode[1:], 'type': 'blob', 'sha': None})
        continue
    if sha not in known:
        result = api('git/blobs', {'content': git('cat-file', 'blob', sha), 'encoding': 'utf-8'})
        assert result['sha'] == sha, 'Blob content changed in transit: ' + path
    elements.append({'path': path, 'mode': mode, 'type': 'blob', 'sha': sha})
result = api('git/trees', {'base_tree': git('rev-parse', 'target^{tree}').strip(), 'tree': elements})
assert result['sha'] == EXPECTED_TREE, 'Uploaded tree differs from reviewed tree'
parents = [os.environ['GITHUB_SHA'], TARGET]
result = api('git/commits', {
    'message': 'Merge Socket.IO 4 / Swift 6.4 into remaining client parity; resolve integration conflicts',
    'tree': EXPECTED_TREE, 'parents': parents})
evidence = {'sha': result['sha'], 'tree': EXPECTED_TREE, 'parents': parents,
            'original_source': git('rev-parse', 'source').strip(), 'target': TARGET,
            'refs_updated': False, 'files_changed_from_target': len(elements)}
Path(os.environ['RUNNER_TEMP'], 'prepared-merge.json').write_text(json.dumps(evidence, indent=2) + '\n')
print(json.dumps(evidence, indent=2))
