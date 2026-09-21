import Foundation
import TokenampKit

// Everything lives in TokenampKit; this target exists only to bind a provider to the UI
// (see ProviderFactory.swift) and to be the one place UsageCore and TokenampKit may meet.
exit(TokenampMain.run(arguments: CommandLine.arguments,
                      providerFactory: makeProvider(demo:),
                      liveProviderAvailable: liveProviderIsWired,
                      providerDiagnostics: providerDiagnostics(_:)))
