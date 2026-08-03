import Foundation
import EVPCore

@main
struct EVPCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            exit(1)
        }

        let options = parseOptions(Array(args.dropFirst()))
        changeToRepoRoot()

        do {
            if command == "index" {
                let index = try RequirementsRegistry().writeRTM()
                print("Indexed \(index.requirements.count) requirements → Documentation/qa/.engine/rtm.json")
                exit(0)
            }
            let summary = try await EVPOrchestrator().run(command: command, options: options)
            if command == "trace" {
                exit(0)
            }
            printSummary(summary)
            exit(summary.failed > 0 ? 1 : 0)
        } catch {
            fputs("evp error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func changeToRepoRoot() {
        let root = EVPPaths.findRepoRoot()
        FileManager.default.changeCurrentDirectoryPath(root)
    }

    private static func parseOptions(_ args: [String]) -> EVPRunOptions {
        var tier: Int?
        var layer: ValidationLayer?
        var requirementId: String?
        var days: Int?
        var scenario: String?
        var fixture: String?
        var failScenario: String?
        var compareVersions: (String, String)?
        var skipUI = false

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--tier":
                if i + 1 < args.count { tier = Int(args[i + 1]); i += 1 }
            case "--layer":
                if i + 1 < args.count { layer = ValidationLayer(rawValue: args[i + 1]); i += 1 }
            case "--days":
                if i + 1 < args.count { days = Int(args[i + 1]); i += 1 }
            case "--scenario":
                if i + 1 < args.count { scenario = args[i + 1]; i += 1 }
            case "--fixture":
                if i + 1 < args.count { fixture = args[i + 1]; i += 1 }
            case "--week":
                fixture = "REPLAY-001"
            case "--fail":
                if i + 1 < args.count { failScenario = args[i + 1]; i += 1 }
            case "--skip-ui":
                skipUI = true
            case "--compare":
                if i + 2 < args.count {
                    compareVersions = (args[i + 1], args[i + 2])
                    i += 2
                }
            default:
                if requirementId == nil && !args[i].hasPrefix("-") {
                    requirementId = args[i]
                }
            }
            i += 1
        }

        return EVPRunOptions(
            tier: tier,
            layer: layer,
            requirementId: requirementId,
            days: days,
            scenario: scenario,
            fixture: fixture,
            compareVersions: compareVersions,
            failScenario: failScenario,
            skipUI: skipUI
        )
    }

    private static func printSummary(_ summary: EVPRunSummary) {
        print("\nEVP \(summary.command): \(summary.success ? "PASS" : "FAIL")")
        print("  pass=\(summary.passed) fail=\(summary.failed) skip=\(summary.skipped)")
        for r in summary.results where r.status == .fail {
            print("  FAIL \(r.requirementId): \(r.message ?? r.evidence.joined(separator: ", "))")
        }
        print("  reports → Documentation/qa/.engine/")
    }

    private static func printUsage() {
        print("""
        Executive Validation Platform (evp)

        Usage: evp <command> [options]

        Commands:
          index              Parse docs → RTM
          run [--tier N] [--skip-ui]   Full Phase 2 pipeline
          flows                UI flow automation (22 flows)
          visual               Visual regression snapshots
          perf                 Performance benchmarks
          a11y                 Accessibility audit
          decisions            Decision regression (CI-blocking)
          replay [--fixture ID] [--compare v1 v2]
          simulate [--days N] [--scenario ID] [--fail FAIL-001]
          counterfactual [CF-001]
          calibrate          Confidence calibration report
          explain [EXPL-001]
          memory-drift [MEM-001]
          cost-audit         Executive + AI cost
          trust              Trust score aggregate
          satisfaction       Human satisfaction ingest
          release            Release checklist gate
          readiness          Production readiness score
          compare-versions [v1 v2]
          trace <ID>         Requirement traceability
        """)
    }
}
