import Foundation
import LogbookCore
import LogbookImport
import LogbookPersistence

// logbook-import — preview, apply and undo imports of the Notes shorthand.
// Format: docs/IMPORT_FORMAT.md

let usage = """
    usage:
      logbook-import preview <file> [--year YYYY] [--tz ZONE] [--db PATH]
      logbook-import apply   <file> [--year YYYY] [--tz ZONE] [--db PATH]
      logbook-import undo    <batch-id> [--db PATH]
      logbook-import batches [--db PATH]

    --db defaults to the live database (~/Library/Application Support/logbook/logbook.sqlite).
    """

struct Options {
    var command = ""
    var argument: String?
    var year = Calendar.current.component(.year, from: Date())
    var timeZone = TimeZone.current
    var db: URL?
    var verbose = false
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty, !["-h", "--help", "help"].contains(args[0]) else { print(usage); exit(0) }
    o.command = args.removeFirst()
    while !args.isEmpty {
        let a = args.removeFirst()
        func value() -> String {
            guard !args.isEmpty else { fail("\(a) needs a value\n\n\(usage)") }
            return args.removeFirst()
        }
        switch a {
        case "--year":
            guard let y = Int(value()) else { fail("--year must be a number") }
            o.year = y
        case "--tz":
            let id = value()
            guard let tz = TimeZone(identifier: id) else { fail("unknown time zone \(id)") }
            o.timeZone = tz
        case "--db": o.db = URL(filePath: (value() as NSString).expandingTildeInPath)
        case "-v", "--verbose": o.verbose = true
        default:
            guard o.argument == nil, !a.hasPrefix("-") else { fail("unexpected argument \(a)\n\n\(usage)") }
            o.argument = a
        }
    }
    return o
}

func openImporter(_ o: Options) throws -> Importer {
    let database = try o.db.map { try AppDatabase.openLive(directory: $0.deletingLastPathComponent(), fileName: $0.lastPathComponent) }
        ?? AppDatabase.openLive()
    let store = LogStore(database: database, boundary: .standard, timeZone: { o.timeZone })
    return Importer(store: store, timeZone: o.timeZone, defaultYear: o.year)
}

func printPlan(_ plan: ImportPlan, verbose: Bool) {
    print("\(plan.batch.sourceName): \(plan.days.count) days · \(plan.blocks.count) blocks · \(plan.foodEntries.count) foods · \(plan.samples.count) metric samples · \(plan.newFoods.count) new library foods")
    if plan.alreadyImported > 0 { print("already imported (skipped): \(plan.alreadyImported) rows") }
    print("")
    for d in plan.days {
        print("  \(d.day)  blocks \(d.blocks)  foods \(d.foods)  samples \(d.samples)  work \(Durations.compact(minutes: d.workMin))  kcal \(Int(d.kcal.rounded()))")
    }
    for severity in [ImportIssue.Severity.error, .warning, .info] {
        let list = plan.issues.filter { $0.severity == severity }
        guard !list.isEmpty else { continue }
        print("\n\(severity.rawValue)s (\(list.count)):")
        for issue in (severity == .info && !verbose ? Array(list.prefix(10)) : list) { print("  \(issue)") }
        if severity == .info && !verbose && list.count > 10 { print("  … \(list.count - 10) more (use --verbose)") }
    }
}

let o = parseOptions()
do {
    switch o.command {
    case "preview", "apply":
        guard let path = o.argument else { fail(usage) }
        let url = URL(filePath: (path as NSString).expandingTildeInPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { fail("can't read \(url.path)") }
        let importer = try openImporter(o)
        let plan = try importer.preview(text, sourceName: url.lastPathComponent)
        printPlan(plan, verbose: o.verbose)
        if o.command == "apply" {
            guard !plan.isEmpty else { print("\nnothing to import"); exit(0) }
            let batch = try importer.apply(plan)
            print("\napplied as batch \(batch.id.uuidString.lowercased())")
            print("undo with: logbook-import undo \(batch.id.uuidString.lowercased())")
        } else {
            print("\npreview only; nothing was written. Run `apply` to import.")
        }
    case "undo":
        guard let arg = o.argument, let id = UUID(uuidString: arg) else { fail("undo needs a batch id\n\n\(usage)") }
        try openImporter(o).undo(batchID: id)
        print("undid batch \(arg)")
    case "batches":
        let list = try openImporter(o).batches()
        if list.isEmpty { print("no imports yet") }
        let f = ISO8601DateFormatter()
        for b in list {
            print("\(b.id.uuidString.lowercased())  \(f.string(from: b.importedAt))  \(b.sourceName)  \(b.lineCount) lines\(b.undoneAt == nil ? "" : "  (undone)")")
        }
    default:
        fail("unknown command \(o.command)\n\n\(usage)")
    }
} catch {
    fail("error: \((error as? Importer.Failure)?.description ?? error.localizedDescription)")
}
