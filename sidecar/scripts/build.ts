// Bundles the sidecar into one CommonJS file, dist/sidecar.cjs (Node's
// single-executable feature only runs one CommonJS script), plus the license
// notices of everything inside it. `npm run build`.
import fs from 'node:fs'
import path from 'node:path'
import { build } from 'esbuild'

const root = path.join(import.meta.dirname, '..')
const dist = path.join(root, 'dist')

export async function buildBundle(): Promise<string> {
  fs.mkdirSync(dist, { recursive: true })
  const out = path.join(dist, 'sidecar.cjs')
  const result = await build({
    entryPoints: [path.join(root, 'src', 'main.ts')],
    outfile: out,
    bundle: true,
    platform: 'node',
    format: 'cjs',
    target: 'node22',
    legalComments: 'eof',
    metafile: true,
    logLevel: 'warning',
  })
  // Only runtime dependencies may end up in the bundle.
  const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')) as {
    dependencies: Record<string, string>
  }
  const bundled = new Set<string>()
  for (const input of Object.keys(result.metafile.inputs)) {
    const m = /node_modules[\\/]((?:@[^\\/]+[\\/])?[^\\/]+)/.exec(input)
    if (m) bundled.add(m[1]!.replace('\\', '/'))
  }
  writeNotices([...bundled].sort(), pkg.dependencies)
  return out
}

/** THIRD_PARTY_LICENSES.txt: every bundled package's license, and Node's. */
function writeNotices(packages: string[], direct: Record<string, string>) {
  const parts = [
    'Third-party software in the sidecar executable.\n',
    'The executable is a Node.js runtime with our bundled script. Licenses follow.\n',
  ]
  for (const name of packages) {
    const dir = path.join(root, 'node_modules', name)
    const meta = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8')) as { version: string; license: string }
    const file = fs.readdirSync(dir).find((f) => /^licen[cs]e(\.(md|txt))?$/i.test(f))
    if (!file) throw new Error(`${name} has no license file; cannot redistribute it`)
    const via = name in direct ? '' : ' (dependency of a dependency)'
    parts.push(`\n==== ${name} ${meta.version}, ${meta.license}${via} ====\n\n`)
    parts.push(fs.readFileSync(path.join(dir, file), 'utf8').trim() + '\n')
  }
  parts.push(`\n==== Node.js ${process.version} ====\n\n`)
  parts.push(fs.readFileSync(path.join(root, 'licenses', 'node-LICENSE'), 'utf8'))
  fs.writeFileSync(path.join(dist, 'THIRD_PARTY_LICENSES.txt'), parts.join(''))
}

if (import.meta.filename === path.resolve(process.argv[1] ?? '')) {
  const out = await buildBundle()
  console.log(`built ${path.relative(root, out)}`)
}
