// A sidecar that fails to start, for the client's start retry (S01):
//   node tests/core/fake_sidecar.mjs <slow|exit|bad|old|refuse>
// slow: never sends the handshake; exit: exits at once; bad: a handshake
// with no port or token; old: another protocol version; refuse: a good
// handshake, then every connection closed at once. Like the real one, it
// exits when stdin closes.
import { createServer } from 'node:net'

const mode = process.argv[2]
if (mode === 'refuse') {
  const server = createServer((socket) => socket.destroy())
  server.listen(0, '127.0.0.1', () => {
    const port = server.address().port
    process.stdout.write(`{"type":"ready","protocol":1,"port":${port},"token":"${'a'.repeat(64)}"}\n`)
  })
}
process.stderr.write(`fake sidecar: ${mode}\n`)
if (mode === 'exit') process.exit(1)
if (mode === 'bad') process.stdout.write('{"type":"ready","protocol":1,"port":0,"token":""}\n')
if (mode === 'old') process.stdout.write(`{"type":"ready","protocol":99,"port":1234,"token":"${'a'.repeat(64)}"}\n`)
process.stdin.on('end', () => process.exit(0))
process.stdin.resume()
