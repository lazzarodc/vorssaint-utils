#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swiftc Sources/Vorssaint/Services/AgentSessions/VSCodeTerminalBridge.swift \
    Tests/AgentSessions/VSCodeBridgeTests.swift -o "$work/client"
node extensions/vscode/test/swift-client.js "$work/client"
