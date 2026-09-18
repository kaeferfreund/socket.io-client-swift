from pathlib import Path
import subprocess

# The existing test target also had a Carthage-only copy phase. Removing the
# framework reference is insufficient while that phase still names Starscream.
p = Path('.native-migration/xcode.rb')
s = p.read_text()
needle = "settings = project.build_configurations + project.targets.flat_map(&:build_configurations)"
assert s.count(needle) == 1
s = s.replace(needle, """project.targets.each do |target|
  target.shell_script_build_phases.select { |phase| phase.shell_script.to_s.include?('Starscream.framework') }.each(&:remove_from_project)
end
""" + needle)
p.write_text(s)

# A bundle contains source objects and refs, never the checkout's credential
# config. Keep it even when compilation fails so the resulting code is reviewable.
subprocess.run(['git', 'bundle', 'create', '/tmp/native-history.bundle', '--all'], check=True)
subprocess.run(['git', 'add', '-A', '--', 'Source', 'Tests', 'Package.swift', 'Package.resolved', 'Cartfile', 'Cartfile.resolved', 'Socket.IO-Client-Swift.podspec', 'scripts', 'Documentation', 'README.md', 'CHANGELOG.md', 'PARITY.md'], check=True)
with open('/tmp/native-migration.patch', 'wb') as output:
    subprocess.run(['git', 'diff', '--cached', '--binary'], stdout=output, check=True)
