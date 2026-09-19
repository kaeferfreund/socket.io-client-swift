//
//  SocketStringReader.swift
//  Socket.IO-Client-Swift
//
//  Created by Lukas Schmidt on 07.09.15.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

/// A bounded UTF-16 reader for Engine.IO 3 length-prefixed polling payloads.
struct SocketStringReader {
    let message: String
    var currentIndex: String.UTF16View.Index
    private(set) var failed = false
    var hasNext: Bool { !failed && currentIndex < message.utf16.endIndex }

    init(message: String) {
        self.message = message
        currentIndex = message.utf16.startIndex
    }

    /// Fails without trapping or accepting an unpaired UTF-16 surrogate.
    mutating func readSafely(count: Int) -> String? {
        guard !failed, count >= 0,
              let end = message.utf16.index(currentIndex, offsetBy: count, limitedBy: message.utf16.endIndex),
              let value = String(message.utf16[currentIndex..<end]) else {
            failed = true
            return nil
        }
        currentIndex = end
        return value
    }

    mutating func read(count: Int) -> String { readSafely(count: count) ?? "" }

    mutating func readUntilOccurence(of delimiter: String) -> String {
        guard !failed, let character = delimiter.utf16.first else { failed = true; return "" }
        let substring = message.utf16[currentIndex...]
        guard let end = substring.firstIndex(of: character) else { return readUntilEnd() }
        guard let value = String(substring[..<end]) else { failed = true; return "" }
        currentIndex = message.utf16.index(after: end)
        return value
    }

    mutating func readUntilEnd() -> String {
        read(count: message.utf16.distance(from: currentIndex, to: message.utf16.endIndex))
    }
}
