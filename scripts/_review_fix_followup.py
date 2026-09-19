#!/usr/bin/env python3
# Temporary validation correction; removed from the published tree.
from pathlib import Path
import json

REPLACEMENTS = json.loads(r'''
[
  [
    "Source/SocketIO/Engine/SocketEngine.swift",
    "fd153caefdaf6133a69609c7b579d37dbbab0eab4236583841c17a450900f784",
    [
      [
        "    internal var pollingRetirementDeadline: TimeInterval = 1\n",
        "    internal var pollingRetirementDeadline: TimeInterval = 1\n\n    /// Supplies an isolated session for lifecycle tests without opening a network request.\n    internal func setTestSession(_ value: URLSession?) { session = value }\n"
      ]
    ]
  ],
  [
    "Tests/TestSocketIO/SocketNativeEngineTest.swift",
    "2fd810c2f599661babdfa36793c6aea910c8799a48dcc5b61c4041e874f41f7f",
    [
      [
        "            engine.session = session\n",
        "            engine.setTestSession(session)\n"
      ]
    ]
  ],
  [
    "Source/SocketIO/Parse/SocketPacket.swift",
    "e296e32ce466c7e80f7c24e25426197f999b34e5a050e12c61d314aca48d814e",
    [
      [
        "    private mutating func binary(_ value: Data, path: String) throws -> Data {\n        guard allowBinary else { throw SocketPacketError.unsupportedValue(path: path, type: \"Data\") }\n        try consumeBytes(value.count)",
        "    private mutating func binary(_ value: Data, depth: Int, path: String) throws -> Data {\n        guard allowBinary else { throw SocketPacketError.unsupportedValue(path: path, type: \"Data\") }\n        // Reserve the eventual placeholder's two keys and two scalar values now,\n        // before ack registration. Its dictionary replaces the already-counted\n        // Data node; its children need one further nesting level at serialization.\n        guard depth < SocketPacket.maximumEmitNestingDepth else {\n            throw SocketPacketError.nestingTooDeep(path: path, limit: SocketPacket.maximumEmitNestingDepth)\n        }\n        for _ in 0..<4 { try consumeNode() }\n        try consumeBytes(value.count)"
      ],
      [
        "binary(data as Data, path: path)",
        "binary(data as Data, depth: depth, path: path)"
      ],
      [
        "binary(data, path: path)",
        "binary(data, depth: depth, path: path)"
      ]
    ]
  ],
  [
    "Tests/TestSocketIO/SocketPacketEncoderTest.swift",
    "c0b085b6775972acd3d5b472f857bec917c8616d479abea01cd448f1efcbebe6",
    [
      [
        "    func testFoundationBudgetsCountDictionaryKeysAndMutableLeaves() {",
        "    func testBinaryPlaceholderBudgetsAreCheckedBeforeShredding() throws {\n        var tooSmall = SocketEmitNormalizer(allowBinary: true, maximumNodes: 5)\n        XCTAssertThrowsError(try tooSmall.normalize([Data()])) { error in\n            guard case SocketPacketError.tooManyNodes(limit: 5) = error else {\n                return XCTFail(\"Expected a placeholder node-budget error\")\n            }\n        }\n        var exact = SocketEmitNormalizer(allowBinary: true, maximumNodes: 6)\n        let values = try XCTUnwrap(try exact.normalize([Data()]) as? [Any])\n        let packet = SocketPacket.packetFromEmit(values, id: -1, nsp: \"/\", ack: false)\n        var wire = SocketEmitNormalizer(allowBinary: false, maximumNodes: 6)\n        XCTAssertNotNil(try wire.normalize(packet.data))\n\n        var shallow = SocketEmitNormalizer(allowBinary: true)\n        XCTAssertNotNil(try shallow.normalize(Data(), depth: SocketPacket.maximumEmitNestingDepth - 1))\n        var deep = SocketEmitNormalizer(allowBinary: true)\n        XCTAssertThrowsError(try deep.normalize(Data(), depth: SocketPacket.maximumEmitNestingDepth)) { error in\n            guard case SocketPacketError.nestingTooDeep = error else {\n                return XCTFail(\"Expected a placeholder depth error\")\n            }\n        }\n    }\n\n    func testFoundationBudgetsCountDictionaryKeysAndMutableLeaves() {"
      ]
    ]
  ]
]
''')
p = Path("scripts/_review_fix.py")
s = p.read_text()
start = s.index("CHANGES = json.loads(r" + chr(39) * 3) + len("CHANGES = json.loads(r" + chr(39) * 3)
end = s.index(chr(39) * 3 + ")", start)
changes = json.loads(s[start:end])
for name, expected, replacements in REPLACEMENTS:
    row = next(row for row in changes if row[0] == name)
    for before, after in replacements:
        matches = [op for op in row[3] if before in op[2]]
        assert len(matches) == 1 and matches[0][2].count(before) == 1, name
        matches[0][2] = matches[0][2].replace(before, after)
    row[2] = expected
s = s[:start] + json.dumps(changes, ensure_ascii=False) + s[end:]
s = s.replace('for name in ("scripts/_review_fix.py", ".github/workflows/review-fix-validation.yml"):',
              'for name in ("scripts/_review_fix.py", "scripts/_review_fix_followup.py", ".github/workflows/review-fix-validation.yml"):')
p.write_text(s)
