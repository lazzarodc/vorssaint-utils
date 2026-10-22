// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
'use strict';
const { startBridge } = require('./bridge');
let bridge;
async function activate(context) {
    const vscode = require('vscode');
    const output = vscode.window.createOutputChannel('Vorssaint');
    context.subscriptions.push(output);
    try {
        bridge = await startBridge({ vscode });
    } catch {
        output.appendLine('Could not start the local terminal bridge. Reload the window to retry.');
    }
}
async function deactivate() { await bridge?.dispose(); bridge = undefined; }
module.exports = { activate, deactivate };
