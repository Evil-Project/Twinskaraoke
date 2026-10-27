import Foundation
import UIKit

enum AppLogoData {
    static let shared: Data = NSDataAsset(name: "AppLogo")?.data ?? Data()
}
