// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
'use strict';
const fs = require('node:fs/promises');
const net = require('node:net');
const path = require('node:path');
const crypto = require('node:crypto');
const MAX_BYTES = 65536;

async function startBridge({ vscode, root, heartbeatMs = 10000 }) {
    if (process.platform !== 'darwin' || vscode.env.remoteName) return { dispose() {} };
    root ??= `/tmp/vorssaint-vscode-${process.getuid()}`;
    await fs.mkdir(root, { mode: 0o700, recursive: true });
    const directory = await fs.lstat(root);
    if (!directory.isDirectory() || directory.isSymbolicLink() || directory.uid !== process.getuid()
        || (directory.mode & 0o777) !== 0o700) throw new Error('Invalid bridge directory');
    const id = crypto.randomUUID();
    const socketPath = path.join(root, `${id}.sock`);
    const registryPath = path.join(root, `${id}.json`);
    let disposed = false;
    let writing = Promise.resolve();
    const sockets = new Set();
    async function terminals() {
        const live = vscode.window.terminals.slice();
        const entries = await Promise.all(live.map(async terminal => {
            let timer;
            try {
                const pid = await Promise.race([terminal.processId, new Promise(resolve => {
                    timer = setTimeout(() => resolve(undefined), 300);
                })]);
                return { terminal, pid };
            } catch { return null; }
            finally { clearTimeout(timer); }
        }));
        return entries.filter(entry => entry && Number.isSafeInteger(entry.pid) && entry.pid > 1
            && vscode.window.terminals.includes(entry.terminal) && entry.terminal.exitStatus === undefined);
    }
    function publish() {
        writing = writing.catch(() => {}).then(async () => {
            if (disposed) return;
            const entries = await terminals();
            if (disposed) return;
            const temporary = `${registryPath}.tmp`;
            await fs.writeFile(temporary, JSON.stringify({ version: 1, extensionPid: process.pid,
                shellPids: entries.map(entry => entry.pid), updatedAt: Date.now() / 1000 }), { mode: 0o600 });
            await fs.rename(temporary, registryPath);
        });
        return writing;
    }
    async function dispatch(request) {
        if (request.version !== 1 || typeof request.id !== 'string' || !Number.isSafeInteger(request.shellPid)
            || !['focus', 'sendText', 'sendKey'].includes(request.action)) throw new Error('Invalid request');
        if (request.action !== 'focus' && (typeof request.text !== 'string' || !request.text.length)) throw new Error('Invalid text');
        const entry = (await terminals()).find(entry => entry.pid === request.shellPid);
        if (!entry) throw new Error('Terminal no longer available');
        if (request.action === 'focus') {
            await vscode.commands.executeCommand('workbench.action.focusWindow');
            entry.terminal.show(false);
        } else {
            entry.terminal.sendText(request.text, request.action === 'sendText');
        }
    }
    const server = net.createServer(socket => {
        sockets.add(socket);
        socket.on('close', () => sockets.delete(socket));
        socket.on('error', () => {});
        socket.setTimeout(2000, () => socket.destroy());
        let buffer = Buffer.alloc(0);
        let handled = false;
        socket.on('data', chunk => {
            if (handled) return;
            buffer = Buffer.concat([buffer, chunk]);
            if (buffer.length > MAX_BYTES) { handled = true; socket.destroy(); return; }
            const end = buffer.indexOf(10);
            if (end < 0) return;
            handled = true;
            let request;
            try { request = JSON.parse(buffer.subarray(0, end).toString('utf8')); }
            catch { socket.end(JSON.stringify({ version: 1, ok: false }) + '\n'); return; }
            dispatch(request).then(() => {
                socket.end(JSON.stringify({ version: 1, id: request.id, ok: true }) + '\n');
            }, () => {
                socket.end(JSON.stringify({ version: 1, id: request?.id, ok: false }) + '\n');
            });
        });
    });
    try {
        await new Promise((resolve, reject) => { server.once('error', reject); server.listen(socketPath, resolve); });
        server.on('error', () => {});
        await fs.chmod(socketPath, 0o600);
        await publish();
    } catch (error) { server.close(); await fs.rm(socketPath, { force: true }); throw error; }
    const opened = vscode.window.onDidOpenTerminal(() => { publish().catch(() => {}); });
    const closed = vscode.window.onDidCloseTerminal(() => { publish().catch(() => {}); });
    const timer = setInterval(() => { publish().catch(() => {}); }, heartbeatMs);
    timer.unref();
    return {
        registryPath, socketPath,
        async dispose() {
            disposed = true;
            clearInterval(timer); opened.dispose(); closed.dispose();
            for (const socket of sockets) socket.destroy();
            await new Promise(resolve => server.close(resolve));
            await writing.catch(() => {});
            await Promise.all([registryPath, `${registryPath}.tmp`, socketPath].map(file => fs.rm(file, { force: true })));
        }
    };
}
module.exports = { startBridge };
