import SwiftUI

@main
struct FloatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            VStack(spacing: 10) {
                Image(systemName: "gearshape").font(.largeTitle).foregroundStyle(.secondary)
                Text("Float's settings are in the ⚙ drawer on the panel.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(width: 280)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}
