import Foundation
import DDMCore

// Thin entry point — all logic lives in `MigrateCLI` (in DDMCore) so it's
// unit-testable. Drop the program name and hand the rest to the runner.
exit(MigrateCLI.run(Array(CommandLine.arguments.dropFirst())))
