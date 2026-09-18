// Protocol-level proof for the polling batch limit in SocketEnginePollable.
//
// engine.io v4 servers advertise a `maxPayload` in the handshake. It is not
// advice: a POST above it is answered with HTTP 413 and every packet it carried
// is discarded. The session stays open, so nothing surfaces to the application.
//
//   Scenario A - all queued packets go out in one POST, the way a client that
//                ignores `maxPayload` batches them. HTTP 413, no acks, events
//                gone.
//   Scenario B - the batch is cut at `maxPayload` and the rest follows in the
//                next POST, which is what `getWritablePackets()` in
//                engine.io-client does, and what this fork now does.
//
// Run:      npm install && node max-payload-proof.mjs   (in this directory)
// Requires: Node >= 18. No Swift toolchain.
//
// Exits non-zero unless A loses the events and B delivers them.
//
// This pins the server contract. The client-side invariant is pinned by the
// SocketEngineTest.testPostBatch* cases.
import { spawn } from "node:child_process"
import { fileURLToPath } from "node:url"

const MAX_PAYLOAD = 200
const SEP = String.fromCharCode(30) // the engine.io v4 record separator

const server = spawn("node", ["server.js"], {
  cwd: fileURLToPath(new URL(".", import.meta.url)),
  env: { ...process.env, MAX_HTTP_BUFFER_SIZE: String(MAX_PAYLOAD) },
})
const port = await new Promise((resolve, reject) => {
  let buf = ""
  const t = setTimeout(() => reject(new Error("server did not start")), 15000)
  server.stdout.on("data", d => {
    buf += d
    const m = buf.match(/READY port=(\d+)/)
    if (m) { clearTimeout(t); resolve(Number(m[1])) }
  })
  server.stderr.on("data", d => process.stderr.write(`[server] ${d}`))
})
const base = `http://127.0.0.1:${port}`

// Two acked events that fit individually but not together.
const packets = [
  `420["ping","${"a".repeat(120)}"]`,
  `421["ping","${"b".repeat(120)}"]`,
]

async function session(label, batchEverything) {
  const open = JSON.parse((await (await fetch(`${base}/socket.io/?EIO=4&transport=polling`)).text()).slice(1))
  const sid = open.sid
  if (open.maxPayload !== MAX_PAYLOAD) {
    throw new Error(`server advertised maxPayload=${open.maxPayload}, expected ${MAX_PAYLOAD}`)
  }
  const poll = () => fetch(`${base}/socket.io/?EIO=4&transport=polling&sid=${sid}`).then(r => r.text())
  const post = body => fetch(`${base}/socket.io/?EIO=4&transport=polling&sid=${sid}`,
    { method: "POST", body, headers: { "content-type": "text/plain;charset=UTF-8" } })

  const connectAck = poll()
  await post("40")
  if (!(await connectAck).includes('40{"sid"')) throw new Error("no namespace CONNECT")

  const statuses = []
  if (batchEverything) {
    statuses.push((await post(packets.join(SEP))).status)
  } else {
    // Cut at maxPayload: each packet on its own stays under the limit.
    for (const packet of packets) statuses.push((await post(packet)).status)
  }

  // Collect whatever the server sends back before giving up on the acks.
  const frames = []
  const deadline = Date.now() + 1500
  while (Date.now() < deadline && !(frames.some(f => f.includes("430")) && frames.some(f => f.includes("431")))) {
    frames.push(await Promise.race([poll(), new Promise(r => setTimeout(() => r(""), 600))]))
  }
  const joined = frames.join("")
  const acked = ["430", "431"].filter(id => joined.includes(id)).length

  console.log(`${label}\n  POST status: ${statuses.join(", ")}\n  events acked: ${acked} of ${packets.length}`)
  return { statuses, acked }
}

const a = await session(`Scenario A - one POST of ${packets.join(SEP).length} bytes, limit is ${MAX_PAYLOAD} (client ignoring maxPayload)`, true)
const b = await session("Scenario B - batch cut at maxPayload, rest in the next POST (JS client, and this fork)", false)
server.kill()

const asExpected =
  a.statuses.every(s => s === 413) && a.acked === 0 &&
  b.statuses.every(s => s === 200) && b.acked === packets.length
console.log(`\nRESULT: ${asExpected
  ? "mechanism confirmed - A loses both events to a 413, B delivers them."
  : `unexpected - A=${JSON.stringify(a)} B=${JSON.stringify(b)}`}`)
process.exitCode = asExpected ? 0 : 1
