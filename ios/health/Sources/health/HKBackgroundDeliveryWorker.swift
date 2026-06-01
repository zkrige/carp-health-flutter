import Flutter
import Foundation
import os

class HKBackgroundDeliveryWorker {
    private struct BackgroundChannel {
        static let name = "flutter_health/background_channel"
        static let initialized = "backgroundChannelInitialized"
        static let syncComplete = "syncComplete"
    }

    private static let log = OSLog(
        subsystem: "co.za.apextechnology.womenscalorietracker",
        category: "HealthKitBGDelivery"
    )

    private var flutterEngine: FlutterEngine?
    private var backgroundChannel: FlutterMethodChannel?

    /// Spins up a headless Flutter engine to run the registered Dart callback.
    /// MUST be invoked on the main thread (HKObserverQuery handlers fire off-main).
    func run(completionHandler: @escaping () -> Void) {
        guard let callbackHandle = HKDeliveryUserDefaults.getCallbackHandle(),
              let info = FlutterCallbackCache.lookupCallbackInformation(callbackHandle)
        else {
            os_log("No callback handle registered, skipping background delivery", log: HKBackgroundDeliveryWorker.log, type: .error)
            completionHandler()
            return
        }

        let engine = FlutterEngine(name: "health.bgdelivery", project: nil, allowHeadlessExecution: true)
        flutterEngine = engine

        engine.run(withEntrypoint: info.callbackName, libraryURI: info.callbackLibraryPath)
        SwiftHealthPlugin.pluginRegistrantCallback?(engine)

        let channel = FlutterMethodChannel(name: BackgroundChannel.name, binaryMessenger: engine.binaryMessenger)
        backgroundChannel = channel

        // Strong self keeps the worker and its engine alive across the Dart round-trip;
        // clearing backgroundChannel below releases this closure, breaking the cycle.
        channel.setMethodCallHandler { call, result in
            guard call.method == BackgroundChannel.syncComplete else {
                result(FlutterMethodNotImplemented)
                return
            }
            result(nil)
            self.flutterEngine?.destroyContext()
            self.flutterEngine = nil
            self.backgroundChannel = nil
            completionHandler()
        }

        channel.invokeMethod(BackgroundChannel.initialized, arguments: nil)
    }
}
