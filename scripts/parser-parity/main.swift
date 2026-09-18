import Foundation
func normal(_ value: Any) -> Any {
    if let d = value as? Data { return ["__bytes": [UInt8](d)] }
    if let a = value as? [Any] { return a.map(normal) }
    if let d = value as? JSON { return d.mapValues(normal) }
    return value
}
let parser = Parser()
while let line = readLine() {
    var result: JSON
    do {
        guard let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? JSON,
              let header = input["header"] as? String else { throw NSError(domain: "input", code: 1) }
        var packet = try parser.parseString(header)
        var completed = !packet.type.isBinary
        for bytes in input["binaries"] as? [[UInt8]] ?? [] {
            if !packet.type.isBinary || completed { throw NSError(domain: "probe", code: 1) }
            completed = packet.addData(Data(bytes))
            if packet.reconstructionFailed { throw NSError(domain: "probe", code: 2) }
        }
        if !completed { result = ["status": "pending"] }
        else {
            var type = packet.type.rawValue
            if type == 5 { type = 2 }; if type == 6 { type = 3 }
            let payload: Any = type == 0 || type == 4 ? (packet.data.first ?? NSNull()) : (type == 1 ? NSNull() as Any : packet.data as Any)
            result = ["status": "ok", "type": type, "id": packet.id, "nsp": packet.nsp, "data": normal(payload)]
        }
    } catch { result = ["status": "error"] }
    let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .fragmentsAllowed])
    print(String(data: data, encoding: .utf8)!)
}
