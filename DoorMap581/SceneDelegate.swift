import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var rootController: DoorMapViewController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let launchURL = connectionOptions.urlContexts.first?.url
            ?? connectionOptions.userActivities.first?.webpageURL
        let controller = DoorMapViewController(initialDeepLink: launchURL)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.makeKeyAndVisible()

        self.rootController = controller
        self.window = window
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        rootController?.handleIncomingURL(url)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL else { return }
        rootController?.handleIncomingURL(url)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        rootController?.notifyLifecycle("willForeground")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        rootController?.notifyLifecycle("foreground")
    }

    func sceneWillResignActive(_ scene: UIScene) {
        rootController?.notifyLifecycle("inactive")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        rootController?.notifyLifecycle("background")
    }
}
