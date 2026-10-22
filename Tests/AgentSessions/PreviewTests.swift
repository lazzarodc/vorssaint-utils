// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main
struct PreviewTests {
    static func main() {
        var agent = AgentSession(id: 1, kind: .codex, cpu: 0, elapsed: "", status: .waiting, bypassPermissions: false)
        agent.lastMessage = "**Neste caso, reaproveitar o código é permitido.** O Agents Island usa a licença `MIT`."
        precondition(agent.listPreview == "Neste caso, reaproveitar o código é permitido. O Agents Island usa a licença MIT.",
                     "the list preview must show the readable message without Markdown markers")
        precondition(agent.lastMessage?.hasPrefix("**Neste caso") == true,
                     "the original Markdown remains available to session details")
        agent.lastMessage = "## Resultado\n\n- **Pronto**\n- Veja [documentação](https://example.com)\n\n```sh\nprintf '%s' foo_bar\n```"
        precondition(agent.listPreview == "Resultado Pronto Veja documentação printf '%s' foo_bar",
                     "block boundaries stay separated, links show their labels, and code keeps literal syntax")
        agent.status = .idle
        precondition(agent.listPreview.hasPrefix("Resultado Pronto"), "idle previews also remove Markdown")
        agent.lastMessage = nil
        agent.lastPrompt = "Leia **README.md** e `foo_bar`."
        precondition(agent.listPreview == "Leia README.md e foo_bar.", "the user-prompt fallback also reads cleanly")
        agent.status = .working
        agent.activity = "Running rg '**' foo_bar"
        precondition(agent.listPreview == "Running rg '**' foo_bar", "tool activities preserve literal command syntax")
        agent.activity = nil
        precondition(agent.listPreview == "Leia README.md e foo_bar.", "working sessions without activity retain their prompt fallback")
        agent.lastPrompt = nil
        precondition(agent.listPreview.isEmpty, "a session without text has an empty preview")
        print("✅ PreviewTests: readable session previews passed")
    }
}
