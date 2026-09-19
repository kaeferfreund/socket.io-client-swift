from pathlib import Path
R=Path('.')
def edit(path,old,new):
 p=R/path;s=p.read_text();assert old in s,(path,old[:90]);p.write_text(s.replace(old,new,1))
p='scripts/check-parity-contracts.py'
edit(p,'    for row in rows:\n        if row[\'status\'] in', '''    review = manifest.get('remaining_review')
    if review is None:
        errors.append('Missing explicit remaining-client review')
    else:
        original = review.get('original_unmapped_ids', [])
        dispositions = review.get('dispositions', [])
        seen = [entry.get('id') for entry in dispositions]
        if len(original) != 44 or len(set(original)) != 44 or sorted(seen) != sorted(original):
            errors.append('Remaining-client review must account for all 44 original IDs exactly once')
        contracts = {entry['id']: entry for entry in manifest['contracts']}
        for entry in dispositions:
            id = entry.get('id')
            row = by_id.get(id)
            if row is None or entry.get('status') != row['status']:
                errors.append(str(id) + ': disposition disagrees with inventory status')
            if not entry.get('reason', '').strip():
                errors.append(str(id) + ': disposition requires a reviewed reason')
            status = entry.get('status')
            if status == 'focused-regression':
                contract = contracts.get(entry.get('contract'))
                if contract is None or id not in contract['upstream_ids']:
                    errors.append(str(id) + ': native disposition requires an executable contract')
            elif status not in ('api-difference', 'platform-specific'):
                errors.append(str(id) + ': unreviewed disposition category')
    for row in rows:
        if row['status'] in''')
p='scripts/test-review-regressions.py'
edit(p,'manifest["remaining_unmapped_ids"] = []','manifest["remaining_unmapped_ids"] = ["JS-999"]')
edit(p,'    def test_mktemp_failure_stops_before_prepare_or_compilation(self):','''    def test_disposition_requires_reason_and_complete_original_id_set(self):
        validate = runpy.run_path(str(ROOT / "scripts/check-parity-contracts.py"))["validate"]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(ROOT / "Documentation", root / "Documentation")
            shutil.copytree(ROOT / "Tests", root / "Tests", ignore=shutil.ignore_patterns("Fixtures"))
            path = root / "Documentation/JavaScriptParityContracts.json"
            manifest = json.loads(path.read_text())
            manifest["remaining_review"]["dispositions"][0]["reason"] = ""
            path.write_text(json.dumps(manifest))
            self.assertTrue(any("requires a reviewed reason" in e for e in validate(root=root)))
            manifest["remaining_review"]["dispositions"].pop()
            path.write_text(json.dumps(manifest))
            self.assertTrue(any("all 44 original IDs" in e for e in validate(root=root)))

    def test_native_disposition_requires_matching_executable_contract(self):
        validate = runpy.run_path(str(ROOT / "scripts/check-parity-contracts.py"))["validate"]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(ROOT / "Documentation", root / "Documentation")
            shutil.copytree(ROOT / "Tests", root / "Tests", ignore=shutil.ignore_patterns("Fixtures"))
            path = root / "Documentation/JavaScriptParityContracts.json"
            manifest = json.loads(path.read_text())
            entry = next(e for e in manifest["remaining_review"]["dispositions"] if e["status"] == "focused-regression")
            entry["contract"] = "missing-contract"
            path.write_text(json.dumps(manifest))
            self.assertTrue(any("requires an executable contract" in e for e in validate(root=root)))

    def test_mktemp_failure_stops_before_prepare_or_compilation(self):''')
p='.github/workflows/swift.yml'
edit(p,'node --test polling-proof-observer.test.mjs server-socket-id.test.mjs','node --test polling-proof-observer.test.mjs server-socket-id.test.mjs engine-parity-observer.test.mjs')
p='README.md'
s=(R/p).read_text();i=s.index('\n');s=s[:i]+'''\n
### Native transport parity follow-up

`withCredentials(true)` enables an isolated engine-owned jar for server cookies.
**Migration:** automatic server cookies are now opt-in (default `false`); the
application's shared cookie store is not used. Explicit `.cookies(...)` and
`Cookie` headers remain explicit. The private jar survives reconnects and
polling-to-WebSocket upgrades; create a new manager for a new cookie identity.

`.forceBase64(true)` enables Engine.IO base64 text over WebSocket, including
upgrades. `.addTrailingSlash(false)` requests the configured path without an
appended slash. Defaults are `false` and `true`, respectively.

Transport errors and disconnects keep their reason at `data[0]` and may append a
`SocketTransportError` at `data[1]` (HTTP status/body or WebSocket code/reason).
Custom reason-only Engine.IO delegates retain a fallback. Subclasses handling
manager engine callbacks should also account for the new typed overloads.
See [remaining-client review](Documentation/RemainingClientParity.md) for exact
test mappings, native adaptations, migration details and known boundaries.
''' +s[i:];(R/p).write_text(s)
p='CHANGELOG.md'
s=(R/p).read_text();s='''## Native transport parity follow-up (2026-09-19)

- Add explicit, private-cookie `withCredentials`, WebSocket `forceBase64` and `addTrailingSlash` options.
- Migration: server-cookie replay defaults to off and no longer uses the application-wide cookie jar. Explicit cookie/header configuration is preserved.
- Carry bounded native HTTP and WebSocket error details through error/close notifications. Snapshot close codes before URLSession cancellation can erase them.
- Add raw Engine.IO wire, cookie isolation/upgrade, Unicode, binary parser and error regressions. Make polling fixture observation passive and replace blocking waits in the async acknowledgement test.
- Classify all 44 previously unmapped declarations: 29 have reviewed native regression contracts and 15 have explicit API/platform boundaries. Zero unmapped entries is not full upstream assertion parity.

'''+s;(R/p).write_text(s)
p='Source/SocketIO/Manager/SocketManager.swift'
edit(p,'    public func engineDidClose(reason: String, error: SocketTransportError) {','    open func engineDidClose(reason: String, error: SocketTransportError) {')
edit(p,'    public func engineDidError(reason: String, error: SocketTransportError) {','    open func engineDidError(reason: String, error: SocketTransportError) {')
