// Packages the sidecar as one executable per platform with Node's
// single-executable feature (NOTES.md -> Architecture -> Platforms).
//
//   npm run package                          this machine's platform
//   npm run package -- --target linux-x64    another platform
//
// Targets: win-x64, linux-x64, linux-arm64, darwin-x64, darwin-arm64.
// Output: dist/<target>/sidecar[.exe] and THIRD_PARTY_LICENSES.txt.
//
// The executable is an official Node binary of exactly the pinned version
// with our bundle injected. For this machine's platform that's the running
// node; other platforms' binaries are downloaded from nodejs.org once, checked
// against the release's SHA-256 list, and cached in .cache/.
//
// macOS: the injected binary must be signed again before it runs (Apple
// Silicon refuses unsigned code). That needs `codesign` on a Mac:
//   codesign --sign - dist/darwin-arm64/sidecar      (ad hoc, for testing)
// Release signing and notarization: docs/release.md -> Code signing.
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { inject } from 'postject'
import { buildBundle } from './build.ts'

const root = path.join(import.meta.dirname, '..')
const dist = path.join(root, 'dist')
const cache = path.join(root, '.cache')
// From Node's SEA docs; fixed for every Node version.
const FUSE = 'NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2'
const TARGETS = ['win-x64', 'linux-x64', 'linux-arm64', 'darwin-x64', 'darwin-arm64'] as const
type Target = (typeof TARGETS)[number]

function currentTarget(): Target {
  const os = { win32: 'win', linux: 'linux', darwin: 'darwin' }[process.platform as string]
  const t = `${os}-${process.arch}` as Target
  if (!TARGETS.includes(t)) throw new Error(`unsupported build machine ${process.platform}-${process.arch}`)
  return t
}

function pinnedVersion(): string {
  const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')) as { engines: { node: string } }
  return `v${pkg.engines.node}`
}

async function download(url: string): Promise<Buffer> {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`download failed (${res.status}): ${url}`)
  return Buffer.from(await res.arrayBuffer())
}

/** The official Node binary for `target`, verified and cached. */
async function nodeBinary(target: Target, version: string): Promise<string> {
  if (target === currentTarget()) return process.execPath
  const exe = target.startsWith('win') ? 'node.exe' : 'node'
  const dir = path.join(cache, `node-${version}-${target}`)
  const bin = path.join(dir, exe)
  if (fs.existsSync(bin)) return bin

  const base = `https://nodejs.org/dist/${version}/`
  const archive = target.startsWith('win') ? `node-${version}-${target}.zip` : `node-${version}-${target}.tar.gz`
  const sums = (await download(base + 'SHASUMS256.txt')).toString('utf8')
  const expected = sums.split('\n').map((l) => l.trim().split(/\s+/)).find((p) => p[1] === archive)?.[0]
  if (!expected) throw new Error(`${archive} not listed in SHASUMS256.txt`)
  console.log(`downloading ${base}${archive}`)
  const data = await download(base + archive)
  const actual = crypto.createHash('sha256').update(data).digest('hex')
  if (actual !== expected) throw new Error(`checksum mismatch for ${archive}`)

  fs.mkdirSync(dir, { recursive: true })
  const archivePath = path.join(dir, archive)
  fs.writeFileSync(archivePath, data)
  // bsdtar (Windows 10+, macOS) and GNU tar read .tar.gz; bsdtar also reads .zip.
  const member = target.startsWith('win')
    ? `node-${version}-${target}/node.exe`
    : `node-${version}-${target}/bin/node`
  execFileSync('tar', ['-xf', archivePath, '-C', dir, member], { stdio: 'inherit' })
  fs.renameSync(path.join(dir, member), bin)
  fs.rmSync(archivePath)
  fs.rmSync(path.join(dir, `node-${version}-${target}`), { recursive: true, force: true })
  return bin
}

async function packageFor(target: Target) {
  const version = pinnedVersion()
  // The blob must be made by the same Node version as the binary it goes into.
  if (process.version !== version) {
    throw new Error(`packaging needs Node ${version} (pinned in package.json); this is ${process.version}`)
  }
  const bundle = await buildBundle()

  const outDir = path.join(dist, target)
  fs.mkdirSync(outDir, { recursive: true })
  const blob = path.join(dist, 'sea-prep.blob')
  const config = path.join(dist, 'sea-config.json')
  fs.writeFileSync(config, JSON.stringify({
    main: bundle,
    output: blob,
    disableExperimentalSEAWarning: true,
    // Code cache and snapshots only load on the platform that made them.
    useCodeCache: false,
    useSnapshot: false,
  }))
  execFileSync(process.execPath, ['--experimental-sea-config', config], { stdio: 'inherit' })

  const out = path.join(outDir, target.startsWith('win') ? 'sidecar.exe' : 'sidecar')
  fs.copyFileSync(await nodeBinary(target, version), out)
  fs.chmodSync(out, 0o755)
  await inject(out, 'NODE_SEA_BLOB', fs.readFileSync(blob), {
    sentinelFuse: FUSE,
    ...(target.startsWith('darwin') ? { machoSegmentName: 'NODE_SEA' } : {}),
  })
  fs.copyFileSync(path.join(dist, 'THIRD_PARTY_LICENSES.txt'), path.join(outDir, 'THIRD_PARTY_LICENSES.txt'))
  fs.rmSync(blob)
  fs.rmSync(config)

  console.log(`packaged ${path.relative(root, out)} (${(fs.statSync(out).size / 1e6).toFixed(0)} MB)`)
  if (target.startsWith('darwin')) {
    console.log('  macOS: sign it on a Mac before it will run (see the top of scripts/package.ts)')
  }
}

const i = process.argv.indexOf('--target')
const target = i >= 0 ? process.argv[i + 1] : currentTarget()
if (!TARGETS.includes(target as Target)) throw new Error(`unknown target ${target}; one of ${TARGETS.join(', ')}`)
await packageFor(target as Target)
