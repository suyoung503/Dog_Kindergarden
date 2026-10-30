import KakaoMapsSDK
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Dog_kindergarden

@Suite("Kakao map engine lifetime", .serialized)
@MainActor
struct KakaoMapLifecycleTests {
    @Test("Removing the SwiftUI map pauses and resets its engine exactly once")
    func dismantleResetsEngine() {
        let (viewController, engine) = makeMap()
        setVisible(true, on: viewController)
        engine.calls.removeAll()

        KakaoMapContainer.dismantleUIViewController(viewController, coordinator: ())
        KakaoMapContainer.dismantleUIViewController(viewController, coordinator: ())

        #expect(engine.calls == ["pause", "reset:detached"])
    }

    @Test("A late view-ready callback cannot access a removed map engine")
    func lateReadyCallbackDoesNotReadEngine() async {
        let (viewController, engine) = makeMap()
        KakaoMapContainer.dismantleUIViewController(viewController, coordinator: ())
        engine.calls.removeAll()

        viewController.addViewSucceeded("mapview", viewInfoName: "map")
        viewController.addViews()
        viewController.refreshPins()
        setVisible(true, on: viewController)
        await drainMainQueue()

        #expect(engine.calls.isEmpty)
    }

    @Test("Pin updates before map readiness do not read native map resources")
    func pinsWaitForReadyMap() {
        let (viewController, engine) = makeMap()
        engine.calls.removeAll()

        viewController.refreshPins()

        #expect(engine.calls.isEmpty)
        KakaoMapContainer.dismantleUIViewController(viewController, coordinator: ())
    }

    @Test("Removing a map releases SwiftUI callback captures")
    func dismantleReleasesCallbacks() {
        let (viewController, _) = makeMap()
        weak var retainedOwner: CallbackOwner?
        do {
            let owner = CallbackOwner()
            retainedOwner = owner
            viewController.onPinTapped = { _ in owner.callbackCount += 1 }
            viewController.onProvinceTapped = { _ in owner.callbackCount += 1 }
            viewController.onCameraStopped = { _ in owner.callbackCount += 1 }
            viewController.onCameraStateChanged = { _ in owner.callbackCount += 1 }
        }
        #expect(retainedOwner != nil)

        KakaoMapContainer.dismantleUIViewController(viewController, coordinator: ())

        #expect(retainedOwner == nil)
    }

    @Test("Temporary disappearance pauses without destroying the reusable engine")
    func temporaryDisappearanceCanResume() {
        let (viewController, engine) = makeMap()
        engine.calls.removeAll()

        setVisible(true, on: viewController)
        setVisible(false, on: viewController)
        setVisible(true, on: viewController)

        #expect(engine.calls == ["activate", "pause", "activate"])
        KakaoMapContainer.dismantleUIViewController(viewController, coordinator: ())
    }

    private func makeMap() -> (KakaoMapViewController, RecordingMapEngine) {
        let engine = RecordingMapEngine()
        let container = UIView()
        let viewController = KakaoMapViewController()
        viewController.makeMapResources = { frame in
            container.frame = frame
            return (container, engine)
        }
        viewController.loadViewIfNeeded()
        #expect(viewController.view.subviews.contains { $0 === container })
        #expect(engine.delegate === viewController)
        #expect(engine.calls == ["prepare"])
        return (viewController, engine)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func setVisible(_ visible: Bool, on viewController: KakaoMapViewController) {
        viewController.beginAppearanceTransition(visible, animated: false)
        viewController.endAppearanceTransition()
    }
}

private final class CallbackOwner {
    var callbackCount = 0
}

private final class RecordingMapEngine: KakaoMapEngine {
    weak var delegate: MapControllerDelegate?
    var calls: [String] = []

    func prepareEngine() -> Bool {
        calls.append("prepare")
        return true
    }

    func activateEngine() { calls.append("activate") }
    func pauseEngine() { calls.append("pause") }
    func resetEngine() {
        calls.append(delegate == nil ? "reset:detached" : "reset:attached")
    }

    func getView(_ viewName: String) -> ViewBase? {
        calls.append("getView")
        return nil
    }

    func addView(_ viewInfo: ViewInfo) { calls.append("addView") }
}
