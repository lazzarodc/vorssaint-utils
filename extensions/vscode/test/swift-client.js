// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
'use strict';
const fs = require('node:fs/promises');
const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const { startBridge } = require('../bridge');
(async () => {
    const root = `/tmp/vsc-${process.pid}`;
    await fs.mkdir(root, { mode: 0o700 });
    const calls = [];
    const terminal = { processId: Promise.resolve(202), show: flag => calls.push(['show', flag]),
        sendText: (text, enter) => calls.push(['send', text, enter]) };
    const disposable = () => ({ dispose() {} });
    const vscode = { env: {}, window: { terminals: [terminal], onDidOpenTerminal: disposable, onDidCloseTerminal: disposable },
        commands: { executeCommand: async command => calls.push(['command', command]) } };
    const bridge = await startBridge({ vscode, root });
    try {
        const child = spawn(process.argv[2], [bridge.socketPath], { stdio: 'inherit' });
        const exit = await new Promise((resolve, reject) => { child.on('exit', resolve); child.on('error', reject); });
        assert.equal(exit, 0);
        assert.deepEqual(calls, [['command', 'workbench.action.focusWindow'], ['show', false], ['send', 'Olá\nworld', true]]);
        console.log('Swift ↔ Node bridge: focus, UTF-8 send and rejected wrong terminal passed');
    } finally { await bridge.dispose(); await fs.rm(root, { recursive: true }); }
})().catch(error => { console.error(error); process.exitCode = 1; });
