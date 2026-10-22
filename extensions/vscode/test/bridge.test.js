// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const net = require('node:net');
const { startBridge } = require('../bridge');
function host(pid) {
    const calls = [];
    const listeners = [];
    const terminal = { processId: Promise.resolve(pid), show: flag => calls.push(['show', flag]),
        sendText: (text, enter) => calls.push(['send', text, enter]) };
    return { calls, terminal, listeners, api: { env: {}, window: { terminals: [terminal],
        onDidOpenTerminal: fn => { listeners.push(fn); return { dispose() {} }; },
        onDidCloseTerminal: fn => { listeners.push(fn); return { dispose() {} }; } },
        commands: { executeCommand: async name => calls.push(['command', name]) } } };
}
function request(socketPath, payload, fragmented = false) {
    return new Promise((resolve, reject) => {
        const socket = net.createConnection(socketPath);
        let buffer = '';
        socket.on('error', reject);
        socket.on('connect', () => {
            const text = JSON.stringify({ version: 1, id: 'test', ...payload }) + '\n';
            if (fragmented) { socket.write(text.slice(0, 8)); setTimeout(() => socket.write(text.slice(8)), 5); }
            else socket.write(text);
        });
        socket.on('data', chunk => { buffer += chunk; if (buffer.includes('\n')) resolve(JSON.parse(buffer)); });
    });
}
test('two windows target exact terminals, even with identical names or changed cwd', async t => {
    // Short socket paths are required on macOS.
    const short = `/tmp/vsb-${process.pid}`;
    await fs.mkdir(short, { mode: 0o700 });
    const one = host(101), two = host(202);
    const a = await startBridge({ vscode: one.api, root: short });
    const b = await startBridge({ vscode: two.api, root: short });
    t.after(async () => {
        await a.dispose(); await b.dispose();
        await assert.rejects(fs.stat(a.registryPath), { code: 'ENOENT' });
        await assert.rejects(fs.stat(b.socketPath), { code: 'ENOENT' });
        await fs.rm(short, { recursive: true });
    });
    assert.equal((await request(b.socketPath, { action: 'focus', shellPid: 202 }, true)).ok, true);
    assert.deepEqual(one.calls, []);
    assert.deepEqual(two.calls, [['command', 'workbench.action.focusWindow'], ['show', false]]);
    assert.equal((await request(a.socketPath, { action: 'sendText', shellPid: 101, text: 'hello\nworld' })).ok, true);
    assert.equal((await request(a.socketPath, { action: 'sendKey', shellPid: 101, text: '\u001b' })).ok, true);
    assert.deepEqual(one.calls, [['send', 'hello\nworld', true], ['send', '\u001b', false]]);
    assert.equal((await request(a.socketPath, { action: 'focus', shellPid: 202 })).ok, false);
    one.api.window.terminals = [];
    assert.equal((await request(a.socketPath, { action: 'sendText', shellPid: 101, text: 'wrong' })).ok, false);
    assert.equal(one.calls.length, 2);
    const entry = JSON.parse(await fs.readFile(b.registryPath, 'utf8'));
    assert.deepEqual(entry.shellPids, [202]);
    assert.equal((await fs.stat(b.registryPath)).mode & 0o777, 0o600);
    assert.equal((await fs.stat(b.socketPath)).mode & 0o777, 0o600);
});
test('remote windows publish no local process identifiers', async () => {
    const remote = host(300);
    remote.api.env.remoteName = 'ssh-remote';
    const bridge = await startBridge({ vscode: remote.api, root: '/does/not/exist' });
    await bridge.dispose();
    assert.equal(bridge.socketPath, undefined);
});
test('unsupported requests and unresolved shell PIDs do not block live terminals', async t => {
    const root = `/tmp/vsu-${process.pid}`;
    await fs.mkdir(root, { mode: 0o700 });
    const local = host(303);
    local.api.window.terminals.push({ processId: new Promise(() => {}) });
    const bridge = await startBridge({ vscode: local.api, root });
    t.after(async () => { await bridge.dispose(); await fs.rm(root, { recursive: true }); });
    assert.deepEqual(JSON.parse(await fs.readFile(bridge.registryPath)).shellPids, [303]);
    assert.equal((await request(bridge.socketPath, { action: 'arbitraryCommand', shellPid: 303 })).ok, false);
    assert.deepEqual(local.calls, []);
    assert.equal((await request(bridge.socketPath, { action: 'focus', shellPid: 303 })).ok, true);
});
test('a bridge rejects a shared or symlinked directory', async t => {
    const root = `/tmp/vsp-${process.pid}`;
    await fs.mkdir(root, { mode: 0o755 });
    t.after(() => fs.rm(root, { recursive: true }));
    await assert.rejects(startBridge({ vscode: host(1).api, root }), /Invalid bridge directory/);
});
