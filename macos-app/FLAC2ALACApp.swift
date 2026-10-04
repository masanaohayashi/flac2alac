import SwiftUI

@main
struct FLAC2ALACApp: App {
    @StateObject private var viewModel = AppViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}

