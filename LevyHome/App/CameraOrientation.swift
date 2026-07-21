import UIKit

@MainActor
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
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
        scene.requestGeometryUpdate(preferences) { _ in
            // The supported-orientation update above remains in effect if the
            // system temporarily rejects a geometry request (for example while
            // dismissing a full-screen presentation).
        }
    }
}
