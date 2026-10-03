// A prompt's other ways to allow (C05 reopened; NOTES.md -> S02 -> Prompt
// options): which of Claude Code's permission_suggestions are offered, and
// their labels. Each case of the live table (dev log
// 2026-10-03-c05-prompt-options-spike, claude 2.1.288) is one test below;
// what the hook carried there is what the suggestions are here.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import path from 'node:path'
import {
  ACCEPT_EDITS_LABEL, AUTO, AUTO_LABEL, SUGGESTED, offerable, promptOptions, suggestedLabel,
} from '../src/providers/claude/prompt-options.ts'

const HOME = path.join(path.sep, 'home', 'me')
const CWD = path.join(HOME, 'AppData', 'Local', 'Temp', 'garden-live')
const OUTSIDE = '//c/Users/me/outside-live/**'

const rules = (destination: string, ...r: { toolName: string; ruleContent?: string }[]) =>
  ({ type: 'addRules', rules: r, behavior: 'allow', destination })
const toEdits = { type: 'setMode', mode: 'acceptEdits', destination: 'session' }
/** The one option offered for a prompt, as [label, updates]. */
const offered = (tool: string, input: Record<string, unknown>, suggestions: unknown[], auto = false) =>
  promptOptions(tool, input, suggestions, auto, CWD, HOME).map((o) => [o.option, o.label, o.updates])

test('1 Bash: don\'t ask again, with the hook\'s exact rule (narrower than the terminal\'s npm *)', () => {
  const s = [rules('localSettings', { toolName: 'Bash', ruleContent: 'npm --version' })]
  assert.deepEqual(offered('Bash', { command: 'npm --version' }, s),
    [[SUGGESTED, 'Yes, and don\'t ask again for: npm --version', s]])
})

test('2 Bash, a compound command: only the part needing approval', () => {
  const s = [rules('localSettings', { toolName: 'Bash', ruleContent: 'npm test *' })]
  assert.deepEqual(offered('Bash', { command: 'git status && npm test' }, s),
    [[SUGGESTED, 'Yes, and don\'t ask again for: npm test *', s]])
})

test('3 Edit in the folder: the switch to accept edits, in the terminal\'s words', () => {
  for (const tool of ['Edit', 'Write', 'MultiEdit']) {
    assert.deepEqual(offered(tool, { file_path: path.join(CWD, 'a.txt') }, [toEdits]), [[SUGGESTED, ACCEPT_EDITS_LABEL, [toEdits]]])
  }
  assert.deepEqual(offered('NotebookEdit', { notebook_path: path.join(CWD, 'n.ipynb') }, [toEdits]), [[SUGGESTED, ACCEPT_EDITS_LABEL, [toEdits]]])
})

test('4 Read outside: reading the folder for this session', () => {
  const s = [rules('session', { toolName: 'Read', ruleContent: OUTSIDE })]
  assert.deepEqual(offered('Read', { file_path: 'C:\\Users\\me\\outside-live\\x.txt' }, s),
    [[SUGGESTED, 'Yes, allow reading from /c/Users/me/outside-live during this session', s]])
})

test('5 Bash in another folder: one entry, two rules, one option', () => {
  const s = [rules('localSettings', { toolName: 'Read', ruleContent: OUTSIDE }, { toolName: 'Bash', ruleContent: 'node -e "1"' })]
  assert.deepEqual(offered('Bash', { command: 'cd x && node -e "1"' }, s),
    [[SUGGESTED, 'Yes, and allow access to /c/Users/me/outside-live and "node -e \\"1\\"" commands', s]])
})

test('6 Write in a .claude folder: the mode switch would allow every edit, so nothing is offered', () => {
  for (const file of [path.join(CWD, '.claude', 'agents', 'x.md'), 'C:\\p\\.claude\\settings.json', '/p/.claude/x']) {
    assert.deepEqual(offered('Write', { file_path: file }, [toEdits]), [], file)
  }
  assert.deepEqual(offered('NotebookEdit', { notebook_path: '/p/.claude/n.ipynb' }, [toEdits]), [])
  // A folder merely named like it is fine.
  assert.equal(offered('Write', { file_path: '/p/.claudette/x' }, [toEdits]).length, 1)
})

test('7 WebFetch: don\'t ask again for the domain', () => {
  const s = [rules('localSettings', { toolName: 'WebFetch', ruleContent: 'domain:example.com' })]
  assert.deepEqual(offered('WebFetch', { url: 'https://example.com' }, s), [[SUGGESTED, 'Yes, and don\'t ask again for example.com', s]])
})

test('8 WebSearch: the whole tool, in this project', () => {
  const s = [rules('localSettings', { toolName: 'WebSearch' })]
  const shown = `~${CWD.slice(HOME.length)}`
  assert.deepEqual(offered('WebSearch', { query: 'q' }, s), [[SUGGESTED, `Yes, and don't ask again for Web Search commands in ${shown}`, s]])
  // Outside the home folder, the full path.
  assert.equal(suggestedLabel(s, '/srv/p', HOME), 'Yes, and don\'t ask again for Web Search commands in /srv/p')
})

test('9 PowerShell: the folder for this session, without the mode switch the terminal didn\'t make', () => {
  const dirs = { type: 'addDirectories', directories: [CWD], destination: 'session' }
  assert.deepEqual(offered('PowerShell', { command: 'Get-ChildItem | Out-File list.txt' }, [dirs, toEdits]),
    [[SUGGESTED, `Yes, and allow access to ${CWD} during this session`, [dirs]]])
})

test('the switch to auto mode comes last, when C06 offers it', () => {
  const s = [rules('localSettings', { toolName: 'Bash', ruleContent: 'npm test' })]
  const auto = [{ type: 'setMode', mode: 'auto', destination: 'session' }]
  assert.deepEqual(offered('Bash', { command: 'npm test' }, s, true), [
    [SUGGESTED, 'Yes, and don\'t ask again for: npm test', s],
    [AUTO, AUTO_LABEL, auto],
  ])
  assert.deepEqual(offered('Bash', { command: 'npm test' }, [], true), [[AUTO, AUTO_LABEL, auto]])
  assert.deepEqual(offered('Bash', { command: 'npm test' }, []), [], 'nothing to offer')
})

test('never more than the terminal: other modes, restrictive or removing entries and unknown shapes are dropped', () => {
  const bad: unknown[] = [
    { type: 'setMode', mode: 'bypassPermissions', destination: 'session' },
    { type: 'setMode', mode: 'auto', destination: 'session' },
    { type: 'setMode', mode: 'dontAsk', destination: 'session' },
    { type: 'setMode', mode: 'acceptEdits', destination: 'localSettings' },
    { ...rules('localSettings', { toolName: 'Bash', ruleContent: 'rm *' }), behavior: 'deny' },
    { ...rules('localSettings', { toolName: 'Bash', ruleContent: 'rm *' }), behavior: 'ask' },
    { ...rules('localSettings', { toolName: 'Bash' }), type: 'replaceRules' },
    { ...rules('localSettings', { toolName: 'Bash' }), type: 'removeRules' },
    { type: 'removeDirectories', directories: ['/x'], destination: 'session' },
    rules('policySettings', { toolName: 'Bash' }),
    rules('localSettings'),
    { type: 'addRules', rules: [{ ruleContent: 'x' }], behavior: 'allow', destination: 'localSettings' },
    { type: 'addRules', rules: [{ toolName: 'Bash', ruleContent: 3 }], behavior: 'allow', destination: 'localSettings' },
    { type: 'addRules', rules: 'Bash', behavior: 'allow', destination: 'localSettings' },
    { type: 'addDirectories', directories: [], destination: 'session' },
    { type: 'addDirectories', directories: [''], destination: 'session' },
    { type: 'addDirectories', directories: [3], destination: 'session' },
    { type: 'somethingNew', destination: 'session' },
    null, 'addRules', [toEdits],
  ]
  assert.deepEqual(offerable('Bash', { command: 'x' }, bad), [])
  assert.deepEqual(offerable('Edit', { file_path: '/p/a' }, bad), [], 'acceptEdits only for the session')
  assert.deepEqual(offerable('Bash', {}, { not: 'a list' }), [])
  assert.deepEqual(offerable('Bash', {}, undefined), [])
  // The good ones among bad ones stay, unchanged.
  const good = rules('localSettings', { toolName: 'Bash', ruleContent: 'make' })
  assert.deepEqual(offerable('Bash', { command: 'make' }, [...bad, good]), [good])
})

test('kinds not seen live get a plain label of what they do and where it\'s saved (stopgap)', () => {
  const label = (s: unknown[]) => suggestedLabel(s as Record<string, unknown>[], CWD, HOME)
  assert.equal(label([rules('localSettings', { toolName: 'mcp__srv__tool' })]),
    'Yes, and always allow mcp__srv__tool (saved in this project\'s .claude/settings.local.json)')
  assert.equal(label([rules('projectSettings', { toolName: 'Bash', ruleContent: 'make' })]),
    'Yes, and always allow Bash(make) (saved in this project\'s .claude/settings.json)')
  assert.equal(label([rules('userSettings', { toolName: 'WebFetch', ruleContent: 'domain:a.com' })]),
    'Yes, and always allow WebFetch(domain:a.com) (saved in your ~/.claude/settings.json)')
  assert.equal(label([rules('session', { toolName: 'Glob' })]), 'Yes, and allow Glob for this session')
  assert.equal(label([{ type: 'addDirectories', directories: ['/a'], destination: 'localSettings' }]),
    'Yes, and allow access to /a (saved in this project\'s .claude/settings.local.json)')
  // Several entries in one option.
  assert.equal(label([rules('session', { toolName: 'Glob' }), { type: 'addDirectories', directories: ['/a', '/b'], destination: 'session' }]),
    'Yes, and allow Glob for this session, and allow access to /a, /b for this session')
  assert.equal(label([toEdits, rules('session', { toolName: 'Glob' })]),
    'Yes, and switch to accept edits for this session, and allow Glob for this session')
})
