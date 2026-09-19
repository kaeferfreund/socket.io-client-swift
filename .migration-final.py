from pathlib import Path
import re

for name in ['Source/SocketIO/Ack/SocketTimedEmitter.swift', 'Source/SocketIO/Client/SocketIOClient.swift']:
    p = Path(name)
    s = p.read_text()
    s = re.sub(r'^(    )(public )?func (emit(?:WithAck)?\([^\n]*\) async throws -> sending \[Any\])',
               r'\1\2nonisolated(nonsending) func \3', s, flags=re.M)
    p.write_text(s)

p = Path('Tests/TestSocketIO/SocketAckManagerTest.swift')
s = p.read_text().replace('waitForExpectations(timeout: 3.0, handler: nil)', 'wait(for: [callbackExpection], timeout: 3.0)')
s = s.replace('waitForExpectations(timeout: 0.2, handler: nil)', 'wait(for: [callbackExpection], timeout: 0.2)')
p.write_text(s)
p = Path('Tests/TestSocketIO/SocketTimedEmitterTest.swift')
s = p.read_text()
s = s.replace('let task = Task { try await socket.emitWithAck("echo", 123) }',
              'let task = Task { try await socket.emitWithAck("echo", 123).first as? Int }')
s = s.replace('XCTAssertEqual(value?.first as? Int, 123)', 'XCTAssertEqual(value, 123)')
s = s.replace('let task = Task { try await socket.timeout(after: 5).emitWithAck("echo", 42) }',
              'let task = Task { try await socket.timeout(after: 5).emitWithAck("echo", 42).first as? Int }')
s = s.replace('XCTAssertEqual(value.first as? Int, 42)', 'XCTAssertEqual(value, 42)')
s = s.replace('let task = Task { try? await socket.timeout(after: 60).emit("ping") }',
              'let task = Task { _ = try? await socket.timeout(after: 60).emit("ping") }')
start = s.index('final class SocketTimedEmitterAsyncTest:')
end = s.index('// MARK: - Task 6:', start)
section = s[start:end]
section = re.sub(r'^(    )((?:private )?func [^\n]*\basync\b)', r'\1@MainActor\n\1\2', section, flags=re.M)
section = section.replace('await fulfillment(of: [exp], timeout: 1)',
                          'let result = await XCTWaiter.fulfillment(of: [exp], timeout: 1)\n        XCTAssertEqual(result, .completed)')
s = s[:start] + section + s[end:]
s += '''

final class SocketMainActorAsyncAPITest: XCTestCase {
    @MainActor
    func testMainActorCanAwaitTimedAndDefaultAcknowledgements() async {
        let manager = SocketManager(socketURL: URL(string: "http://localhost")!,
                                    config: [.log(false), .ackTimeout(0.01)])
        let socket = manager.defaultSocket
        socket.setTestStatus(.connected)
        do {
            _ = try await socket.timeout(after: 0.01).emitWithAck("timeout")
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? SocketAckError, .timeout)
        }
        do {
            _ = try await socket.emitWithAck("timeout")
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? SocketAckError, .timeout)
        }
    }
}
'''
p.write_text(s)
p = Path('Tests/TestSocketIO/SocketEnginePacketCodecTest.swift')
p.write_text(p.read_text().replace('    func engineDidSendPing() { pings += 1 }\n', ''))
p = Path('Documentation/SocketIO4Swift6Migration.md')
p.write_text(p.read_text().replace('Async acknowledgement methods return `sending [Any]`.',
'''Async acknowledgement methods are `nonisolated(nonsending)` so they inherit
the caller's isolation, including MainActor, and return `sending [Any]`.'''))
