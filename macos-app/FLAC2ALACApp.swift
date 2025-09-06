import SwiftUI

@main
struct FLAC2ALACApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: AppViewModel())
        }
    }
}

