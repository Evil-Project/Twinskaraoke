import SwiftUI

struct SplashWebsiteEditor: View {
    @Binding var website: SplashWebsite?

    var body: some View {
        Section {
            Picker("Slide type", selection: Binding(
                get: { website != nil },
                set: { website = $0 ? (website ?? SplashWebsite()) : nil }
            )) {
                Text("Standard").tag(false)
                Text("Website").tag(true)
            }
            if let configuration = Binding($website) {
                TextField("Website URL", text: configuration.url)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Paste an HTTPS URL or leave it blank to use the local test page in Preview.")
                    .font(.caption)
            }
        }
    }
}
