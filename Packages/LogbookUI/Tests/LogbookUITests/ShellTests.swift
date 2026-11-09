import Foundation
import LogbookCore
import LogbookPersistence
import Testing
@testable import LogbookUI

@Suite struct ShellTests {
    @Test func paletteMatchesWordsInAnyOrder() {
        #expect(PaletteCommand.matches("Start sleep timer", "sleep st"))
        #expect(PaletteCommand.matches("Go to Backups & Export", "back"))
        #expect(!PaletteCommand.matches("Start work timer", "sleep"))
        #expect(PaletteCommand.matches("Anything", ""))
    }

    @Test func screenShortcutsAreUniqueDigits() {
        let digits = RootScreen.allCases.compactMap(\.shortcutDigit)
        #expect(digits.count == 10 && Set(digits).count == 10)
        #expect(RootScreen.today.shortcutDigit == "1")
    }

    @Test func routerOpensCloseTheDayOnToday() {
        let r = AppRouter()
        r.go(.trends)
        r.showingPalette = true
        r.closeTheDay()
        #expect(r.screen == .today && r.showingCloseDay && !r.showingPalette)
        #expect(UserDefaults.standard.string(forKey: "selectedScreen") == "today")
    }

    @Test func customKindsGetTheOtherLane() {
        #expect(Domain(kind: BlockKind(rawValue: "gym")) == .other)
        #expect(Domain(kind: .work) == .work)
    }
}
