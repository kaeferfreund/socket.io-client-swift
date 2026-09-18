from pathlib import Path

def edit(name, old, new):
    p=Path(name); s=p.read_text(); assert old in s, name+' missing fragment'; p.write_text(s.replace(old,new,1))

edit('Source/SocketIO/Manager/SocketManager.swift',
'    public var handleQueue = DispatchQueue.main',
'''    private let handleQueueKey = DispatchSpecificKey<UInt8>()
    public var handleQueue = DispatchQueue.main {
        didSet {
            oldValue.setSpecific(key: handleQueueKey, value: nil)
            handleQueue.setSpecific(key: handleQueueKey, value: 1)
        }
    }

    /// Registration is synchronous when the caller obeys the handleQueue contract.
    /// This preserves emit(); disconnect() ordering without synchronous cross-queue hops.
    internal var isOnHandleQueue: Bool {
        DispatchQueue.getSpecific(key: handleQueueKey) != nil
            || (Thread.isMainThread && handleQueue === DispatchQueue.main)
    }''')
edit('Source/SocketIO/Manager/SocketManager.swift', '        setConfigs(_config)\n\n        if autoConnect {',
'        setConfigs(_config)\n        handleQueue.setSpecific(key: handleQueueKey, value: 1)\n\n        if autoConnect {')
edit('Source/SocketIO/Manager/SocketManager.swift', '    deinit {\n', '    deinit {\n        handleQueue.setSpecific(key: handleQueueKey, value: nil)\n')
edit('Source/SocketIO/Client/SocketIOClient.swift',
'                timeout(after: defaultTimeout).emit(event, with: items, ack: ack)',
'                emitTimed(event: event, items: [], timeout: defaultTimeout, mappedItems: mapped, ack: ack)')
edit('Source/SocketIO/Client/SocketIOClient.swift',
'            queue.async { [weak self] in\n                guard let self = self else { return }\n                guard !self.failIfReserved(mapped) else {',
'            performAckRegistration { [weak self] in\n                guard let self = self else { return }\n                guard !self.failIfReserved(mapped) else {')
p=Path('Source/SocketIO/Client/SocketIOClient.swift');s=p.read_text();start=s.index('    func emitTimed(event: String,');end=s.index('    /// Internal — allocate the next ack id',start)
s=s[:start]+'''    private func performAckRegistration(_ work: @escaping () -> Void) {
        guard let manager = manager else { return }
        if (manager as? SocketManager)?.isOnHandleQueue == true { work() }
        else { manager.handleQueue.async(execute: work) }
    }

    func emitTimed(event: String,
                   items: [SocketData],
                   timeout: Double,
                   ackId: Int? = nil,
                   cancellation: SocketAsyncAckState? = nil,
                   mappedItems: [Any]? = nil,
                   ack: @escaping (Error?, [Any]) -> Void) {
        guard let manager = self.manager else { ack(SocketAckError.disconnected, []); return }
        let queue = manager.handleQueue
        performAckRegistration { [weak self] in
            guard let self = self else { return }
            if cancellation?.isCancelled == true { ack(CancellationError(), []); return }
            do {
                // A custom SocketData representation is evaluated exactly once.
                let mapped = try mappedItems ?? ([event] + items.map { try $0.socketRepresentation() })
                guard !self.failIfReserved(mapped) else {
                    ack(NSError(domain: "SocketIO.Emit", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Reserved event name: " + event]), [])
                    return
                }
                if ackId == nil, cancellation == nil,
                   self.enqueueRetriableIfActive(mapped, userAck: ack, attemptTimeout: timeout) { return }
                // Retry queue entries allocate their IDs per attempt, never here.
                let id = ackId ?? self.allocateAckId()
                cancellation?.register(id)
                let ackDroppingBuffered: (Error?, [Any]) -> Void = { [weak self] err, data in
                    if err != nil { self?.dropBufferedEmit(ack: id) }
                    ack(err, data)
                }
                self.ackHandlers.addTimedAck(id, on: queue, callback: ackDroppingBuffered, timeout: timeout)
                self.emit(mapped, ack: id, binary: true, isAck: false)
            } catch { ack(error, []) }
        }
    }

'''+s[end:]
s=s.replace('''    /// Internal — allocate the next ack id (matches existing `currentAck += 1`
    /// pattern from `createOnAck`). Called from the async emit overload before
    /// entering the cancellation handler so the cancel path can reference the
    /// same id.''','''    /// Allocate IDs on handleQueue together with acknowledgement registration.''')
s=s.replace('''            // fires: JS registers a plain ack then, which also never times out
            // — but a disconnect still interrupts it (JS `_clearAcks`), which
            // the timed-ack clearing provides.''','''            // fires. A disconnect removes that plain registration silently;
            // reconnect force-drains the retained queue head with a new ID.''')
p.write_text(s)
p=Path('Tests/TestSocketIO/SocketRetrySafetyTest.swift');s=p.read_text();pos=s.index('    func testPlainRetryInheritsAckTimeout')
s=s[:pos]+'''    func testEmitImmediatelyFollowedByDisconnectFailsTheAlreadyRegisteredAck() {
        make([.ackTimeout(10)])
        let failed = expectation(description: "same-turn emit is registered before disconnect")
        socket.emit("never_ack", ack: { error, _ in
            XCTAssertEqual(error as? SocketAckError, .disconnected)
            failed.fulfill()
        })
        XCTAssertEqual(engine.sentPackets.count, 1)
        socket.didDisconnect(reason: "transport close")
        wait(for: [failed], timeout: 2)
    }

    func testTimedRetryDoesNotConsumeAnUnusedAckID() throws {
        make([.retries(1)])
        socket.timeout(after: 10).emit("x", ack: { _, _ in })
        drain()
        XCTAssertEqual(try ackID(0), 0)
    }

'''+s[pos:];p.write_text(s)
