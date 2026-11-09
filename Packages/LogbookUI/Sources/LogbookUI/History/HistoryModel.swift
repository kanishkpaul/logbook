import Foundation
import LogbookCore
import LogbookPersistence
import Observation

/// A live range of days ending today, for Work, Sleep, Body and Trends.
@Observable
public final class HistoryModel {
    public let store: LogStore
    public var range: HistoryRange { didSet { if range != oldValue { observe() } } }
    public private(set) var snapshot: RangeSnapshot?
    public var lastError: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(store: LogStore, range: HistoryRange = .month) {
        self.store = store
        self.range = range
    }

    public var presenter: HistoryPresenter { HistoryPresenter(timeZone: store.timeZone()) }

    public func start() {
        if task == nil { observe() }
    }

    private func observe() {
        task?.cancel()
        let last = store.boundary.logicalDay(containing: store.now(), in: store.timeZone())
        let first = last.adding(days: -(range.days - 1))
        let stream = store.observeRange(first, through: last, in: store.timeZone())
        task = Task { [weak self] in
            do {
                for try await r in stream { self?.snapshot = r }
            } catch {
                self?.lastError = "\(error)"
            }
        }
    }
}
