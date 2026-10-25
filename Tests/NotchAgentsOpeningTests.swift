// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum NotchAgentsOpeningTests {
    enum Module: Hashable { case agents }
    enum Page { case sessions, limits }
    enum NotchLayout { static let pageContentHeight: CGFloat = 320 }
    final class Publisher { func send() {} }
    class State {
        var reportedAgentsHeight: CGFloat?
        let objectWillChange = Publisher()
        var resizes: [CGFloat?] = []
        var pageLayers: [Module: () -> Void] = [:]
        var layer: (() -> Void)? { pageLayers[.agents] }
        func setPageLayer(_ module: Module, close: (() -> Void)?) { pageLayers[module] = close }
        func refreshPresentation() { resizes.append(layer != nil ? NotchLayout.pageContentHeight : reportedAgentsHeight) }
    }
    enum NotchService { static var shared = Service() }
    final class Usage {
        func pageDidDisappear() {}
    }
    class PageState {
        var preview = false
        var selectedSession: Int?
        var page = Page.sessions
        var hasLayer: Bool { selectedSession != nil || page != .sessions }
        var overviewHeight: CGFloat?
        let usage = Usage()
        let accounts = Usage()
    }
    static func run(_ suite: TestSuite) {
        NotchService.shared = Service()
        let service = NotchService.shared
        let cold = AgentPage()
        cold.syncPresentation()
        suite.expect(service.reportedAgentsHeight == nil && service.resizes.isEmpty,
                     "a first visit with no measurement leaves the initial layout budget alone")
        let first = AgentPage()
        first.overviewHeight = 160
        first.syncPresentation()
        first.disappear()
        suite.expect(service.reportedAgentsHeight == 160,
                     "closing AI Agents retains its measured overview height for the next opening")
        let reopened = AgentPage()
        reopened.syncPresentation()
        suite.expect(service.reportedAgentsHeight == 160 && service.resizes == [160],
                     "a recreated page without its first measurement does not retarget the opening to the full budget")
        reopened.selectedSession = 7
        reopened.syncPresentation()
        suite.expect(service.layer != nil && service.reportedAgentsHeight == 160,
                     "session details use the page layer without replacing the cached overview height")
        suite.expect(service.resizes == [160, 320], "opening a detail still requests the full reading budget")
        reopened.selectedSession = nil
        reopened.syncPresentation()
        suite.expect(service.resizes == [160, 320, 160], "returning from a detail requests the cached overview height")
        reopened.page = .limits
        reopened.syncPresentation()
        suite.expect(service.resizes.last == 320, "limits open with the full reading budget too")
        reopened.disappear()
        let again = AgentPage()
        again.syncPresentation()
        suite.expect(service.layer == nil && service.reportedAgentsHeight == 160,
                     "closing a detail reopens at the overview's height, not the detail panel's")
        again.overviewHeight = 208
        again.syncPresentation()
        suite.expect(service.reportedAgentsHeight == 208, "changed content still updates the dynamic overview height")
        let preview = AgentPage()
        preview.preview = true
        preview.overviewHeight = 300
        preview.syncPresentation()
        preview.disappear()
        suite.expect(service.reportedAgentsHeight == 208 && service.resizes.last == 208,
                     "settings previews cannot replace the live overview height")
    }
}
