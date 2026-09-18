from pathlib import Path
import re
import subprocess
import tempfile

p = Path('.native-migration/xcode.rb')
s = p.read_text()
needle = 'settings = project.build_configurations + project.targets.flat_map(&:build_configurations)'
assert s.count(needle) == 1
s = s.replace(needle, """project.targets.each do |target|
  target.shell_script_build_phases.select { |phase| phase.shell_script.to_s.include?('Starscream.framework') }.each(&:remove_from_project)
end
""" + needle)
p.write_text(s)

# Reconcile the base branch's independently rebased changes using their actual
# before/after source snapshots, not commit-message heuristics. The resulting
# commit records both feature and updated-base parents.
old_ref = 'adb686a93537fd4ea5bae66fe0a35ff5fa5238c0'
new_ref = '4458325db9c1c54af6551ef7ddba0febb999cdca'
paths = subprocess.check_output(['git', 'diff', '--name-only', old_ref, new_ref], text=True).splitlines()
expected = {'Source/SocketIO/Client/SocketIOClientOption.swift', 'Source/SocketIO/Engine/SocketEngine.swift', 'Source/SocketIO/Engine/SocketEnginePollable.swift', 'Source/SocketIO/Util/SocketExtensions.swift'}
conflicts = set()
for path in paths:
    p = Path(path)
    before = subprocess.run(['git', 'show', f'{old_ref}:{path}'], capture_output=True).stdout
    after = subprocess.check_output(['git', 'show', f'{new_ref}:{path}'])
    if not p.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(after)
        continue
    with tempfile.TemporaryDirectory() as directory:
        inputs = []
        for name, data in [('native', p.read_bytes()), ('old', before), ('updated', after)]:
            f = Path(directory) / name
            f.write_bytes(data)
            inputs.append(str(f))
        result = subprocess.run(['git', 'merge-file', '-p', '-L', 'native', '-L', 'old-base', '-L', 'updated-base', *inputs], capture_output=True)
        if result.returncode >= 128:
            raise RuntimeError(result.stderr)
        p.write_bytes(result.stdout)
        if result.returncode:
            conflicts.add(path)
assert conflicts == expected, f'Unexpected merge conflicts: {conflicts}'

pattern = r'<<<<<<< native\n(.*?)=======\n(.*?)>>>>>>> updated-base\n'
for path in sorted(conflicts):
    p = Path(path)
    def resolve(match):
        native, updated = match.groups()
        if path.endswith('SocketIOClientOption.swift'):
            if 'case security' in native:
                return updated.split('    /// Allows you to set which certs')[0] + native
            return native + updated
        if path.endswith('SocketExtensions.swift'):
            return updated.replace('CertificatePinning', 'SocketTLSConfiguration')
        if path.endswith('SocketEngine.swift') and 'case .useCustomEngine:' in native:
            return updated.split('            case .enableSOCKSProxy:')[0] + native
        # Native close, session identity and native event handling already enforce
        # the corresponding updated-base protections, with generation guards.
        return native
    p.write_text(re.sub(pattern, resolve, p.read_text(), flags=re.S))
p = Path('Source/SocketIO/Engine/SocketEnginePollable.swift')
p.write_text(p.read_text().replace('        guard let issuedSession = session else { return }\n', ''))
p = Path('Tests/TestSocketIO/SocketStateRecoveryTest.swift')
s = p.read_text()
assert s.count('    let ws: WebSocket? = nil\n') == 1
p.write_text(s.replace('    let ws: WebSocket? = nil\n', ''))
for p in Path('Source').rglob('*.swift'):
    s = p.read_text()
    assert '<<<<<<<' not in s and 'Starscream.' not in s and 'import Starscream' not in s, str(p)
subprocess.run(['git', 'diff', '--exit-code', new_ref, '--', 'Source/SocketIO/Manager', 'Source/SocketIO/Client/SocketIOClient.swift'], check=True)

# Source objects and refs only; the bundle never includes credential configs.
subprocess.run(['git', 'bundle', 'create', '/tmp/native-history.bundle', '--all'], check=True)
subprocess.run(['git', 'add', '-A', '--', 'Source', 'Tests', 'Package.swift', 'Package.resolved', 'Cartfile', 'Cartfile.resolved', 'Socket.IO-Client-Swift.podspec', 'scripts', 'Documentation', 'README.md', 'CHANGELOG.md', 'PARITY.md'], check=True)
with open('/tmp/native-migration.patch', 'wb') as output:
    subprocess.run(['git', 'diff', '--cached', '--binary'], stdout=output, check=True)
