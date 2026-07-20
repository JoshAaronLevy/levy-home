import UIKit

enum CameraOrientation {
    private(set) static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func lockLandscape() {
        set(.landscape)
    }

    static func lockPortrait() {
        set(.portrait)
    }

    private static func set(_ orientations: UIInterfaceOrientationMask) {
        supportedOrientations = orientations

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
        scene.requestGeometryUpdate(preferences) { _ in }
    }
}
