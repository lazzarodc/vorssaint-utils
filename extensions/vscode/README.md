# Vorssaint Terminal Bridge

Optional companion for **Vorssaint AI Agents**, in the same repository as the macOS app.
Requires macOS and VS Code 1.143 or newer. No runtime npm dependencies, telemetry,
network listener or access to terminal output.

In Vorssaint's AI Agents settings, choose **Install VS Code extension**. Alternatively,
run `python3 Tools/package-vscode-extension.py` from the repository root, then use
VS Code's **Extensions: Install from VSIX…** with `build/vorssaint-terminal-focus.vsix`.
Reload existing VS Code windows after installation. Non-default VS Code profiles may
need the extension installed/enabled in that profile too. Remove it through VS Code's
Extensions view like any other extension.

Each local, trusted window publishes its shell PIDs through a private Unix socket in
`/tmp/vorssaint-vscode-<uid>/`. The app walks the agent's current process ancestors to
find the shell, so changing directories does not affect the association. The owning
extension focuses its own window and reveals the exact terminal. Replies and raw
approval keys use `Terminal.sendText`, never simulated keystrokes in the editor.

Registry files contain only protocol version, extension-host PID, shell PIDs and
heartbeat time. The directory is owner-only (0700); registrations and sockets are
0600. Requests and acknowledgements are bounded, timed out and revalidate live
terminals. Closing/unloading removes that window's files; crashed registrations
expire. Both the regular and Developer app use this transient bridge directory.
Remote SSH/WSL/container windows and virtual/custom terminals without local shell PIDs
are not supported. No terminal, folder or shell is created by this extension.

Development checks: `npm test --prefix extensions/vscode` and
`Tools/test-agent-sessions.sh`. `Tools/test-vscode-bridge.sh` exercises the production
Swift client against the production Node server with fake terminal objects; it does
not send to any real session. Real multi-window focus still needs a desktop check.

This companion was written for Vorssaint against public VS Code APIs. It contains no
code copied from the installed Vibe Island extension. Licensed GPL-3.0-or-later.
