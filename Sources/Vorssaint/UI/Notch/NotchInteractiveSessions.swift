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

private func sessionWorkTime(_ agent: AgentSession) -> String {
    guard let seconds = agent.workDuration else { return "—" }
    return (agent.workDurationEstimated ? "≈ " : "") + AgentFormat.duration(seconds, locale: L10n.shared.language.formattingLocale())
}

private func jumpToSession(_ agent: AgentSession) {
    NotchService.shared.jumpToAgentSession(agent)
}

struct NotchInteractiveSessionCard: View {
    let agent: AgentSession
    var controlsOnly = false
    let onShowDetail: () -> Void
    private let fs: CGFloat = 11
    @ObservedObject private var approvals = ApprovalCenter.shared
    @State private var replyText = ""
    @State private var sending = false
    @State private var justSent = false
    @State private var rowHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var approval: ApprovalCenter.Approval? { approvals.pending[agent.id] }
    private var approvalColor: Color { AgentStatus.waiting.color }
    /// Live question from the PreToolUse hook — the only real-time source
    /// (the transcript records AskUserQuestion only after it's answered).
    private var liveQuestion: PendingQuestion? { approvals.questions[agent.id]?.question ?? agent.pendingQuestion }

    /// A pending question/approval means "waiting on you" regardless of the
    /// flickery CPU/registry status — pin the card's color to that.
    private var effectiveStatus: AgentStatus {
        (approval != nil || liveQuestion != nil) ? .waiting : agent.status
    }

    @ViewBuilder var body: some View {
        if controlsOnly {
            if approval != nil { approvalBar }
            else if let question = liveQuestion, agent.terminalApp != nil { questionBar(question) }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Button {
                        if agent.terminalApp != nil { jumpToSession(agent) }
                        else { onShowDetail() }
                    } label: {
                        HStack(spacing: 9) {
                            NotchAgentMark(provider: agent.kind == .claude ? .claude : .codex, size: 13)
                                .frame(width: 17, height: 17)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 7) {
                                    Text(agent.displayTitle == agent.cwdDisplay ? agent.displayTitle : agent.cwdDisplay + " / " + agent.displayTitle)
                                        .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                    Text(sessionWorkTime(agent)).font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .help(sessionString(.uptime))
                                }
                                Text(localizedSessionActivity(agent.listPreview))
                                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 9).padding(.trailing, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 6, lifts: false, highlights: false))
                    .help(sessionString(agent.terminalApp != nil ? .terminal : .conversation))
                    .accessibilityLabel(agent.displayTitle + " · " + sessionString(agent.terminalApp != nil ? .terminal : .conversation))
                    NotchAgentStatusIndicator(status: effectiveStatus)
                        .padding(.horizontal, 9)
                    Button(action: onShowDetail) {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 42).contentShape(Rectangle())
                    }.buttonStyle(NotchButtonStyle(cornerRadius: 6, lifts: false, highlights: false))
                        .help(sessionString(.conversation)).accessibilityLabel(sessionString(.conversation))
                }
                .padding(.horizontal, 6)
                .background(.white.opacity(rowHovered ? 0.09 : 0),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                .onHover { rowHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: rowHovered)
                .padding(.horizontal, -6)
                if approval != nil { approvalBar }
                else if let question = liveQuestion, agent.terminalApp != nil { questionBar(question) }
            }
            .padding(.bottom, approval != nil || liveQuestion != nil ? 9 : 0)
            .contentShape(Rectangle())
        }
    }

    /// Approve once or cancel the terminal prompt. Permanent permissions stay
    /// in the terminal, whose numbered choices vary across Claude versions.
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
                SessionApprovalButton(label: sessionString(.deny), tint: Color(red: 1.0, green: 0.45, blue: 0.45)) {
                    ApprovalCenter.shared.respond(pid: agent.id, action: .deny)
                }
                if agent.terminalApp != nil {
                    SessionApprovalButton(label: sessionString(.terminal), tint: .white.opacity(0.75)) {
                        jumpToSession(agent)
                    }
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
                Image(systemName: justSent ? "checkmark" : "arrow.up")
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
                .disabled(sending)
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
        guard !sending, let question = liveQuestion,
              let response = ApprovalCenter.shared.beginQuestionResponse(pid: agent.id, question: question) else { return }
        sending = true
        DispatchQueue.global(qos: .userInitiated).async {
            let sent = TerminalBridge.send(text: String(number), to: agent)
            DispatchQueue.main.async {
                sending = false
                ApprovalCenter.shared.finishQuestionResponse(pid: agent.id, response: response, sent: sent)
                if sent {
                    justSent = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justSent = false }
                }
            }
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

// MARK: - Session detail (click a card)

struct NotchInteractiveSessionDetail: View {
    let agent: AgentSession
    let onBack: () -> Void

    @State private var messages: [ChatMessage] = []
    @State private var replyText = ""
    @State private var sending = false
    @State private var justSent = false

    @ObservedObject private var approvals = ApprovalCenter.shared
    @ObservedObject private var l10n = L10n.shared
    private var hasApproval: Bool { approvals.pending[agent.id] != nil }
    private var hasQuestion: Bool { approvals.questions[agent.id] != nil || agent.pendingQuestion != nil }
    private var needsResponseControl: Bool { hasApproval || hasQuestion }
    private var effectiveStatus: AgentStatus { needsResponseControl ? .waiting : agent.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                NotchAgentBackButton(action: onBack, label: NotchAgentStrings.panel(.back, language: l10n.language))
                Text(agent.displayTitle).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NotchAgentMark(provider: agent.kind == .claude ? .claude : .codex, size: 13)
                    .frame(width: 17, height: 17).help(agent.kind.displayName)
                NotchAgentStatusIndicator(status: effectiveStatus)
                Text(sessionWorkTime(agent)).font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit().fixedSize()
                    .help(sessionString(.uptime))
            }
            HStack(spacing: 8) {
                Text([agent.cwdDisplay, agent.gitBranch, agent.modelDisplay].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                if agent.bypassPermissions { Text("BYPASS").font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange) }
                Spacer(minLength: 0)
                if let terminal = agent.terminalApp {
                    Button { jumpToSession(agent) } label: {
                        Image(systemName: "terminal").font(.system(size: 12)).frame(width: 26, height: 24)
                    }.buttonStyle(.plain).help(sessionString(.terminal) + " · " + terminal)
                        .accessibilityLabel(sessionString(.terminal) + " · " + terminal)
                }
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if agent.transcriptPath == nil { fallbackInfo } else { transcript }
                        if hasQuestion, !hasApproval {
                            NotchInteractiveSessionCard(agent: agent, controlsOnly: true, onShowDetail: {})
                        }
                        if let plan = agent.plan { SessionPlanSection(markdown: plan) }
                        if !agent.todos.isEmpty { SessionTasksSection(todos: agent.todos) }
                        if !agent.subagents.isEmpty { SessionSubagentsSection(subagents: agent.subagents) }
                        if agent.status == .working, let activity = agent.activity {
                            Text(localizedSessionActivity(activity)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentMargins(.trailing, 12, for: .scrollContent)
                .onChange(of: messages) { _, new in
                    if let last = new.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            if hasApproval {
                Divider()
                NotchInteractiveSessionCard(agent: agent, controlsOnly: true, onShowDetail: {})
            } else if !hasQuestion, agent.terminalApp != nil {
                Divider()
                replyField
            }
        }
        .padding(.horizontal, 3)
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
                Image(systemName: justSent ? "checkmark" : "arrow.up")
                    .font(.system(size: 14)).frame(width: 26, height: 26)
                    .foregroundStyle(justSent ? AgentStatus.working.color
                        : replyText.isEmpty ? .white.opacity(0.3) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(sending || replyText.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages) { message in
                SessionTranscriptMessage(message: message, kind: agent.kind, language: l10n.language)
                    .id(message.id)
            }
            if messages.isEmpty {
                Text(sessionString(.noConversation)).font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 12)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fallbackInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            SessionInfoRow(label: sessionString(.status), value: sessionStatusLabel(agent.status))
            SessionInfoRow(label: sessionString(.directory), value: agent.cwd ?? "—")
            SessionInfoRow(label: "PID", value: "\(agent.id)")
            SessionInfoRow(label: "CPU", value: String(format: "%.1f%%", locale: L10n.shared.language.formattingLocale(), agent.cpu))
            SessionInfoRow(label: sessionString(.uptime), value: sessionWorkTime(agent))
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

/// Authorship is explicit on every message; color is supplementary.
private struct SessionTranscriptMessage: View {
    let message: ChatMessage
    let kind: AgentKind
    let language: AppLanguage

    private var author: String {
        switch message.source {
        case .user: return NotchAgentStrings.session(.you, language: language)
        case .assistant: return kind.displayName
        case .terminal: return NotchAgentStrings.session(.terminalOutput, language: language)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                if message.source == .assistant {
                    NotchAgentMark(provider: kind == .claude ? .claude : .codex, size: 9)
                        .frame(width: 13, height: 13).accessibilityHidden(true)
                } else {
                    Image(systemName: message.isUser ? "person.fill" : "terminal")
                        .font(.system(size: 9)).frame(width: 13, height: 13).accessibilityHidden(true)
                }
                Text(author).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            if message.source == .terminal {
                Text(message.text).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SessionMarkdownMessage(text: message.text, language: language).equatable()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(message.isUser ? 0.055 : message.source == .terminal ? 0.025 : 0),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Parse only when a message or language changes, not on every monitor scan.
private struct SessionMarkdownMessage: View, Equatable {
    let text: String
    let language: AppLanguage
    var body: some View {
        let strings = FeatureStrings.scratchpad(language)
        MarkdownPreview(blocks: ScratchpadSupport.markdownPreview(text), baseSize: 12,
                        fitsContent: true, textInset: .zero,
                        taskStates: (done: strings.taskDone, notDone: strings.taskNotDone))
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
