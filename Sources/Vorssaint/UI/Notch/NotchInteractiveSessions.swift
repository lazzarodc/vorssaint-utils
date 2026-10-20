// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Portions Copyright (c) 2026 Mustafa Halabi and Mohammad Hammoud (MIT).
// Adapted from Agents Island, commit 275f5e8bb7984dc25fc0b9ed10b48d1eecb3603c.
// See Resources/AgentsIsland-LICENSE.txt for the original license.

import AppKit
import SwiftUI

private func sessionString(_ key: NotchSessionText) -> String {
    NotchAgentStrings.session(key, language: L10n.shared.language)
}

private func sessionStatusLabel(_ status: AgentStatus) -> String {
    switch status {
    case .working: return sessionString(.working)
    case .waiting: return sessionString(.waiting)
    case .idle: return sessionString(.idle)
    }
}

private func localizedSessionActivity(_ activity: String) -> String {
    activity == "Thinking…" ? sessionString(.working) : activity
}

private func jumpToSession(_ agent: AgentSession) {
    DispatchQueue.global(qos: .userInitiated).async { TerminalBridge.jump(to: agent) }
}

struct NotchInteractiveSessionCard: View {
    let agent: AgentSession
    var selected = false
    let onShowDetail: () -> Void

    private let showLastPrompt = true
    private let showActivity = true
    private let showTerminalChip = true
    private let showTasks = true
    private let showModel = true
    private let showGitBranch = true
    private let showSubagents = true
    private let fontSize = 11
    @ObservedObject private var approvals = ApprovalCenter.shared
    @State private var hovered = false
    @State private var replyText = ""
    @State private var sending = false
    @State private var justSent = false

    private var fs: CGFloat { CGFloat(fontSize) }
    private var approval: ApprovalCenter.Approval? { approvals.pending[agent.id] }
    private var approvalColor: Color { AgentStatus.waiting.color }
    /// The agent is waiting on you and we can type back into its terminal.
    private var canReply: Bool {
        effectiveStatus == .waiting && agent.terminalApp != nil && approval == nil
    }

    /// Live question from the PreToolUse hook — the only real-time source
    /// (the transcript records AskUserQuestion only after it's answered).
    private var liveQuestion: PendingQuestion? { approvals.questions[agent.id]?.question ?? agent.pendingQuestion }

    /// A pending question/approval means "waiting on you" regardless of the
    /// flickery CPU/registry status — pin the card's color to that.
    private var effectiveStatus: AgentStatus {
        (approval != nil || liveQuestion != nil) ? .waiting : agent.status
    }

    /// A subtle wash of the status color behind the card (idle stays neutral).
    private var statusWash: Color {
        switch effectiveStatus {
        case .working, .waiting: return effectiveStatus.color.opacity(hovered || selected ? 0.14 : 0.10)
        case .idle:              return .clear
        }
    }

    /// Border color: selected wins, otherwise a status tint.
    private var borderColor: Color {
        if selected { return Color(red: 0.45, green: 0.62, blue: 1.0).opacity(0.8) }
        switch effectiveStatus {
        case .working, .waiting: return effectiveStatus.color.opacity(0.4)
        case .idle:              return .white.opacity(0.07)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NotchAgentGlyph(provider: agent.kind == .claude ? .claude : .codex, size: 20, working: agent.status == .working)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                // Line 1: title · detail button · time
                HStack(spacing: 8) {
                    Text(agent.displayTitle)
                        .font(.system(size: fs + 2, weight: .semibold))
                        .foregroundStyle(.white.opacity(agent.status == .idle ? 0.6 : 1))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Group {
                        Button(action: onShowDetail) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: fs + 2))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help(sessionString(.conversation))
                        // Grows out of the trailing edge rather than popping in.
                        .transition(.scale(scale: 0.6, anchor: .trailing)
                            .combined(with: .opacity))
                    }
                    if agent.terminalApp != nil {
                        Button { jumpToSession(agent) } label: { Image(systemName: "terminal") }
                            .buttonStyle(.plain).help(sessionString(.terminal))
                    }
                    Text(agent.elapsed)
                        .font(.system(size: fs - 1, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize()
                }

                // Line 2: when the agent is waiting on you, surface its question;
                // otherwise show your last message.
                if agent.status == .waiting, let question = agent.lastMessage, approval == nil {
                    Text(question)
                        .font(.system(size: fs))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(3)
                } else if showLastPrompt, let prompt = agent.lastPrompt {
                    Text(sessionString(.you) + ": " + prompt)
                        .font(.system(size: fs))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                }

                // Line 3: live status on the left, chips on the right
                HStack(alignment: .center, spacing: 8) {
                    statusLine
                    Spacer(minLength: 8)
                    chips
                }
                .padding(.top, 1)

                // Task checklist from the agent's todo list
                if showTasks, !agent.todos.isEmpty {
                    SessionTasksSection(todos: agent.todos, compact: true)
                        .padding(.top, 3)
                }

                // Fan-out subagents (only interesting while any is running)
                if showSubagents, agent.subagents.contains(where: { !$0.done }) {
                    SessionSubagentsSection(subagents: agent.subagents, compact: true)
                        .padding(.top, 3)
                }

                // Pending permission request → answer from the island.
                if approval != nil {
                    approvalBar
                        .padding(.top, 3)
                } else if let question = liveQuestion, agent.terminalApp != nil {
                    // Structured question, live from the PreToolUse hook —
                    // stays up until the answer lands (PostToolUse / busy).
                    questionBar(question)
                        .padding(.top, 3)
                } else if canReply, hovered || selected {
                    // Free-text question → answer inline without leaving.
                    replyBar
                        .padding(.top, 3)
                        // Unfurls downward instead of snapping the card taller.
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -6)),
                            removal: .opacity
                        ))
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.white.opacity(selected ? 0.08 : hovered ? 0.06 : 0.03))
                .overlay(  // a wash of the status color so the card reads at a glance
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(statusWash)
                )
                .overlay(  // specular sheen along the top edge, only while hovered
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.07), .clear],
                            startPoint: .top, endPoint: .center))
                        .opacity(hovered ? 1 : 0)
                )
        )
        .overlay(  // status-tinted left accent bar — elongates as you hover
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(effectiveStatus.color.opacity(effectiveStatus == .idle ? 0.3 : 0.9))
                    .frame(width: hovered || selected ? 3.5 : 3)
                    .padding(.vertical, hovered || selected ? 6 : 10)
                Spacer(minLength: 0)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(borderColor, lineWidth: selected || approval != nil ? 1.5 : 1)
        )
        // Lift: a scale small enough to stay crisp, plus a shadow that gives the
        // card somewhere to lift *from*. Both ride the same spring as the chrome.
        .shadow(color: .black.opacity(hovered ? 0.30 : 0),
                radius: hovered ? 11 : 0, y: hovered ? 4 : 0)
        .scaleEffect(hovered ? 1.012 : 1, anchor: .center)
        .animation(hoverSpring, value: hovered)
        .onHover { hovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            if agent.terminalApp != nil { jumpToSession(agent) }
            else { onShowDetail() }
        }
        .pointingHandCursor(hovered)
    }

    /// Quick and fully damped — the highlight tracks the cursor without any
    /// bounce, which is what makes it read as responsive rather than springy.
    private var hoverSpring: Animation { .spring(response: 0.30, dampingFraction: 0.86) }

    /// "Needs approval: Bash" + Approve / Always / Deny, answering the
    /// terminal prompt (1 / 2 / 3) without leaving the island.
    private var approvalBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(approvalColor)
                Text(approval?.toolName.map { sessionString(.needsApproval) + ": " + $0 } ?? sessionString(.needsApproval))
                    .font(.system(size: fs, weight: .semibold))
                    .foregroundStyle(approvalColor)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                SessionApprovalButton(label: sessionString(.approve), tint: AgentStatus.working.color) {
                    ApprovalCenter.shared.respond(pid: agent.id, action: .approve)
                }
                SessionApprovalButton(label: sessionString(.alwaysAllow), tint: .white.opacity(0.75)) {
                    ApprovalCenter.shared.respond(pid: agent.id, action: .alwaysAllow)
                }
                SessionApprovalButton(label: sessionString(.deny), tint: Color(red: 1.0, green: 0.45, blue: 0.45)) {
                    ApprovalCenter.shared.respond(pid: agent.id, action: .deny)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(approvalColor.opacity(0.10)))
    }

    /// Answer the agent's question straight into its terminal, without opening
    /// the detail view or switching to the terminal.
    private var replyBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 10))
                .foregroundStyle(AgentStatus.waiting.color)
            TextField(sessionString(.reply) + " · " + agent.kind.displayName, text: $replyText)
                .textFieldStyle(.plain)
                .font(.system(size: fs))
                .foregroundStyle(.white)
                .onSubmit(sendReply)
                .simultaneousGesture(TapGesture().onEnded { NotchService.shared.presentationWindow?.makeKey() })
            Button(action: sendReply) {
                Image(systemName: justSent ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(justSent ? AgentStatus.working.color
                        : replyText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? .white.opacity(0.3)
                            : Color(red: 0.45, green: 0.62, blue: 1.0))
            }
            .buttonStyle(.plain)
            .disabled(sending || replyText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AgentStatus.waiting.color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(AgentStatus.waiting.color.opacity(0.25), lineWidth: 1))
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        let target = agent
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = TerminalBridge.send(text: text, to: target)
            DispatchQueue.main.async {
                sending = false
                guard ok else { return }
                if replyText.trimmingCharacters(in: .whitespacesAndNewlines) == text { replyText = "" }
                justSent = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justSent = false }
            }
        }
    }

    /// A structured AskUserQuestion → one tappable button per option, plus a
    /// free-text box for a custom ("Other") answer.
    private func questionBar(_ question: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AgentStatus.waiting.color)
                Text(question.prompt == "Choose an option" ? sessionString(.chooseOption) : question.prompt)
                    .font(.system(size: fs, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                if question.multiSelect {
                    Text(sessionString(.pickAny))
                        .font(.system(size: fs - 2))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            ForEach(Array(question.options.prefix(6).enumerated()), id: \.offset) { index, option in
                Button { answerChoice(index + 1) } label: {
                    HStack(spacing: 7) {
                        Text("\(index + 1)")
                            .font(.system(size: fs - 1, weight: .bold, design: .rounded))
                            .foregroundStyle(AgentStatus.waiting.color)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(AgentStatus.waiting.color.opacity(0.18)))
                        Text(option)
                            .font(.system(size: fs))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.06)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            replyBar // "Other" — type a custom answer
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AgentStatus.waiting.color.opacity(0.10)))
    }

    /// Answer a choice: the digit selects the option in Claude's prompt and
    /// Enter confirms it (TerminalBridge.send types text + Enter).
    private func answerChoice(_ number: Int) {
        ApprovalCenter.shared.clearQuestion(pid: agent.id)
        DispatchQueue.global(qos: .userInitiated).async {
            TerminalBridge.send(text: String(number), to: agent)
        }
        justSent = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justSent = false }
    }

    /// Chips drop least-important-first when the row runs out of width, so
    /// they never squeeze the status text into vertical wrapping.
    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            chipRow(model: showModel, branch: showGitBranch, terminal: showTerminalChip)
            chipRow(model: showModel, branch: showGitBranch, terminal: false)
            chipRow(model: false, branch: showGitBranch, terminal: false)
            chipRow(model: false, branch: false, terminal: false)
        }
    }

    private func chipRow(model: Bool, branch: Bool, terminal: Bool) -> some View {
        HStack(spacing: 4) {
            if agent.bypassPermissions {
                SessionChip(text: "BYPASS",
                     textColor: Color(red: 1.0, green: 0.5, blue: 0.5),
                     background: Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.15))
            }
            SessionChip(text: agent.kind.displayName,
                 textColor: .white.opacity(0.85),
                 background: agent.kind.color.opacity(0.25))
            if model, let name = agent.modelDisplay {
                SessionChip(text: name, textColor: .white.opacity(0.75), background: .white.opacity(0.08))
            }
            if branch, let name = agent.gitBranch {
                // Long branch names would crowd out the status line.
                SessionChip(text: name.count > 16 ? name.prefix(15) + "…" : name,
                     textColor: .white.opacity(0.65), background: .white.opacity(0.08),
                     icon: "arrow.triangle.branch")
            }
            if terminal, let app = agent.terminalApp {
                SessionChip(text: app, textColor: .white.opacity(0.65), background: .white.opacity(0.08))
            }
            if let host = agent.remoteHost {
                SessionChip(text: host, textColor: Color(red: 0.55, green: 0.80, blue: 1.0),
                     background: Color(red: 0.3, green: 0.55, blue: 0.9).opacity(0.18),
                     icon: "network")
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var statusLine: some View {
        if effectiveStatus == .working, showActivity, let activity = agent.activity {
            Text(localizedSessionActivity(activity))
                .font(.system(size: fs, weight: .medium))
                .foregroundStyle(Color(red: 0.45, green: 0.62, blue: 1.0))
                .lineLimit(1)
        } else if effectiveStatus == .waiting {
            Text(sessionString(.waiting))
                .font(.system(size: fs, weight: .medium))
                .foregroundStyle(AgentStatus.waiting.color.opacity(0.9))
                .lineLimit(1)
                .fixedSize()
        } else {
            Text(sessionStatusLabel(effectiveStatus))
                .font(.system(size: fs, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Pointing-hand cursor tied to a hover flag. Tracks its own push so it always
/// balances, including when the view disappears mid-hover — an agent card can
/// vanish out from under the cursor, and a missed `pop()` strands the whole
/// cursor stack on the pointing hand.
private struct SessionPointingHandCursor: ViewModifier {
    let active: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onChange(of: active) { _, now in sync(to: now) }
            .onDisappear { sync(to: false) }
    }

    private func sync(to want: Bool) {
        guard want != pushed else { return }
        pushed = want
        if want { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
}

private extension View {
    func pointingHandCursor(_ active: Bool) -> some View {
        modifier(SessionPointingHandCursor(active: active))
    }
}

private struct SessionApprovalButton: View {
    let label: String
    let tint: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(hovered ? 0.22 : 0.12)))
                .overlay(Capsule().strokeBorder(tint.opacity(hovered ? 0.55 : 0.35), lineWidth: 1))
                .contentShape(Capsule())
                .scaleEffect(hovered ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: hovered)
        .onHover { hovered = $0 }
        .pointingHandCursor(hovered)
    }
}

private struct SessionChip: View {
    let text: String
    let textColor: Color
    let background: Color
    var icon: String?

    var body: some View {
        HStack(spacing: 2.5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(text)
        }
        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
        .foregroundStyle(textColor)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(background))
    }
}

// MARK: - Session detail (click a card)

struct NotchInteractiveSessionDetail: View {
    let agent: AgentSession
    let onBack: () -> Void

    @State private var messages: [ChatMessage] = []
    @State private var replyText = ""
    @State private var sending = false
    @State private var justSent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)

                NotchAgentGlyph(provider: agent.kind == .claude ? .claude : .codex, size: 16, working: agent.status == .working)

                Text(agent.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                SessionChip(text: agent.kind.displayName,
                     textColor: .white.opacity(0.85),
                     background: agent.kind.color.opacity(0.28))
                if let terminal = agent.terminalApp {
                    Button {
                        jumpToSession(agent)
                    } label: {
                        HStack(spacing: 3) {
                            Text(terminal)
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.09)))
                    }
                    .buttonStyle(.plain)
                    .help(sessionString(.terminal) + " · " + terminal)
                }
            }
            .padding(.horizontal, 4)

            if agent.transcriptPath == nil {
                fallbackInfo
            } else {
                transcript
            }

            if let plan = agent.plan {
                SessionPlanSection(markdown: plan)
            }

            if !agent.todos.isEmpty {
                SessionTasksSection(todos: agent.todos)
            }

            if !agent.subagents.isEmpty {
                SessionSubagentsSection(subagents: agent.subagents)
            }

            if agent.status == .working, let activity = agent.activity {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text(localizedSessionActivity(activity))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.40, green: 0.58, blue: 1.0))
                }
                .padding(.horizontal, 6)
            }

            if agent.terminalApp != nil {
                replyField
            }
        }
        .onAppear(perform: load)
        .onChange(of: agent) { _, _ in load() }
    }

    /// Quick-reply straight into the agent's terminal session.
    private var replyField: some View {
        HStack(spacing: 8) {
            TextField(sessionString(.reply) + " · " + agent.kind.displayName, text: $replyText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .onSubmit(sendReply)
                .simultaneousGesture(TapGesture().onEnded { NotchService.shared.presentationWindow?.makeKey() })
            Button(action: sendReply) {
                Image(systemName: justSent ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(justSent ? AgentStatus.working.color
                        : replyText.isEmpty ? .white.opacity(0.3) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(sending || replyText.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        let target = agent
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = TerminalBridge.send(text: text, to: target)
            DispatchQueue.main.async {
                sending = false
                guard ok else { return }
                if replyText.trimmingCharacters(in: .whitespacesAndNewlines) == text { replyText = "" }
                justSent = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justSent = false }
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.isUser ? sessionString(.you) : agent.kind.displayName)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(message.isUser ? .white.opacity(0.4) : agent.kind.color)
                            Text(message.text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(message.isUser ? 0.6 : 0.9))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(message.id)
                    }
                    if messages.isEmpty {
                        Text(sessionString(.noConversation))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 380)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.04)))
            .onChange(of: messages) { _, new in
                if let last = new.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onAppear {
                if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var fallbackInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            SessionInfoRow(label: sessionString(.status), value: sessionStatusLabel(agent.status))
            SessionInfoRow(label: sessionString(.directory), value: agent.cwd ?? "—")
            SessionInfoRow(label: "PID", value: "\(agent.id)")
            SessionInfoRow(label: "CPU", value: String(format: "%.1f%%", locale: L10n.shared.language.formattingLocale(), agent.cpu))
            SessionInfoRow(label: sessionString(.uptime), value: agent.elapsed)
            Text(sessionString(.noConversation))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(0.04)))
    }

    private func load() {
        guard let path = agent.transcriptPath else { return }
        let kind = agent.kind
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded: [ChatMessage]
            switch kind {
            case .codex: loaded = CodexSessions.recentMessages(path: path)
            default: loaded = ClaudeSessions.recentMessages(path: path)
            }
            DispatchQueue.main.async {
                if loaded != messages { messages = loaded }
            }
        }
    }
}

private struct SessionTasksSection: View {
    let todos: [Todo]
    var compact = false

    private var done: Int { todos.filter { $0.status == "completed" }.count }
    private var inProgress: Int { todos.filter { $0.status == "in_progress" }.count }
    private var open: Int { todos.count - done - inProgress }

    /// Active items first, then a couple of recent completions.
    private var visible: [Todo] {
        let active = todos.filter { $0.status != "completed" }
        let completed = todos.filter { $0.status == "completed" }
        return Array((active + completed).prefix(compact ? 4 : 6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(sessionString(.tasks))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("\(done)/\(todos.count) · \(inProgress) ▶ · \(open) ○")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            ForEach(Array(visible.enumerated()), id: \.offset) { _, todo in
                HStack(alignment: .top, spacing: 7) {
                    todoIcon(todo.status)
                        .padding(.top, 2)
                    Text(todo.content)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(todo.status == "completed" ? 0.35 : 0.85))
                        .strikethrough(todo.status == "completed", color: .white.opacity(0.35))
                        .lineLimit(1)
                }
            }

            if todos.count > visible.count {
                Text("… +\(todos.count - visible.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(compact ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
            .fill(.white.opacity(compact ? 0.05 : 0.04)))
    }

    @ViewBuilder
    private func todoIcon(_ status: String) -> some View {
        switch status {
        case "completed":
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        case "in_progress":
            Circle()
                .fill(Color(red: 0.35, green: 0.55, blue: 1.0))
                .frame(width: 8, height: 8)
        default:
            Image(systemName: "square")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

/// Fan-out Task subagents: running ones with a pulsing dot, recent finishes dimmed.
private struct SessionSubagentsSection: View {
    let subagents: [Subagent]
    var compact = false

    private var running: Int { subagents.filter { !$0.done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(sessionString(.subagents))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("\(running) ▶")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            ForEach(Array(subagents.prefix(compact ? 3 : 6).enumerated()), id: \.offset) { _, sub in
                HStack(spacing: 7) {
                    if sub.done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    } else {
                        SessionPulsingDot(color: AgentStatus.working.color)
                    }
                    Text(sub.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(sub.done ? 0.35 : 0.85))
                        .lineLimit(1)
                    if let type = sub.type {
                        Text(type)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                    if sub.done {
                        Text(sessionString(.done))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
        }
        .padding(compact ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
            .fill(.white.opacity(compact ? 0.05 : 0.04)))
    }
}

/// The plan Claude presented via ExitPlanMode, lightly Markdown-rendered.
private struct SessionPlanSection: View {
    let markdown: String
    @State private var collapsed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(sessionString(.plan))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(renderedLines.enumerated()), id: \.offset) { _, line in
                            line
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            } else {
                Text(firstLinePreview)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.04)))
    }

    private var firstLinePreview: String {
        markdown.split(separator: "\n").first(where: { !$0.isEmpty })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) } ?? ""
    }

    /// Line-based Markdown: headers bold, bullets indented, inline styles
    /// via AttributedString. Good enough for plan text.
    private var renderedLines: [Text] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).prefix(80).map { raw in
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            func inline(_ s: String, size: CGFloat, weight: Font.Weight = .regular,
                        opacity: Double = 0.75) -> Text {
                let attributed = (try? AttributedString(
                    markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(s)
                return Text(attributed)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(.white.opacity(opacity))
            }
            if trimmed.hasPrefix("### ") {
                return inline(String(trimmed.dropFirst(4)), size: 11, weight: .semibold, opacity: 0.9)
            } else if trimmed.hasPrefix("## ") {
                return inline(String(trimmed.dropFirst(3)), size: 11.5, weight: .bold, opacity: 0.92)
            } else if trimmed.hasPrefix("# ") {
                return inline(String(trimmed.dropFirst(2)), size: 12, weight: .bold, opacity: 0.95)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return Text("  •  ").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                    + inline(String(trimmed.dropFirst(2)), size: 10.5)
            } else {
                return inline(line, size: 10.5)
            }
        }
    }
}

private struct SessionInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Shared bits

struct SessionPulsingDot: View {
    let color: Color
    var active: Bool = true
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(0.9), radius: pulsing && active ? 4 : 1)
            .opacity(active ? (pulsing ? 1 : 0.55) : 0.45)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
