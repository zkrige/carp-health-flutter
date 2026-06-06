import Foundation
import HealthKit
import os
import UIKit

class HKObserverManager {
    static let shared = HKObserverManager()

    private static let log = OSLog(
        subsystem: "co.za.apextechnology.womenscalorietracker",
        category: "HealthKitBGDelivery"
    )

    private var activeQueries: [HKObserverQuery] = []
    // Workers are retained until their headless engine signals syncComplete; without this
    // the temporary worker is deallocated when run() returns, tearing down the engine mid-sync.
    private var activeWorkers: [ObjectIdentifier: HKBackgroundDeliveryWorker] = [:]
    private weak var healthStore: HKHealthStore?

    private init() {}

    func configure(healthStore: HKHealthStore, typeNames: [String], dataTypesDict: [String: HKSampleType]) {
        self.healthStore = healthStore

        for query in activeQueries {
            healthStore.stop(query)
        }
        activeQueries.removeAll()

        for typeName in typeNames {
            guard let sampleType = dataTypesDict[typeName] else {
                os_log("Unknown type %{public}@ requested for background delivery, skipping", log: HKObserverManager.log, type: .info, typeName)
                continue
            }
            guard isBackgroundDeliverySupported(sampleType) else {
                os_log("Type %{public}@ does not support background delivery, skipping", log: HKObserverManager.log, type: .info, typeName)
                continue
            }
            registerObserver(healthStore: healthStore, sampleType: sampleType, typeName: typeName)
        }
    }

    func reRegisterFromStored(healthStore: HKHealthStore, dataTypesDict: [String: HKSampleType]) {
        let storedTypes = HKDeliveryUserDefaults.getRegisteredTypes()
        guard !storedTypes.isEmpty else { return }
        configure(healthStore: healthStore, typeNames: storedTypes, dataTypesDict: dataTypesDict)
    }

    // HealthKit supports background delivery for HKWorkoutType (a regular HKSample),
    // so a finished workout can wake the app. Only series types (HKWorkoutRoute),
    // audiograms and ECGs are genuinely unsupported.
    private func isBackgroundDeliverySupported(_ sampleType: HKSampleType) -> Bool {
        if sampleType is HKAudiogramSampleType { return false }
        if sampleType is HKSeriesType { return false }
        if #available(iOS 14.0, *), sampleType is HKElectrocardiogramType { return false }
        return true
    }

    private func registerObserver(healthStore: HKHealthStore, sampleType: HKSampleType, typeName: String) {
        healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { success, error in
            if let error = error {
                os_log("enableBackgroundDelivery failed for %{public}@: %{public}@", log: HKObserverManager.log, type: .error, typeName, error.localizedDescription)
            } else {
                os_log("enableBackgroundDelivery succeeded for %{public}@: %{public}@", log: HKObserverManager.log, type: .info, typeName, success ? "true" : "false")
            }
        }

        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, hkCompletion, error in
            if let error = error {
                os_log("Observer query error for %{public}@: %{public}@", log: HKObserverManager.log, type: .error, typeName, error.localizedDescription)
                hkCompletion()
                return
            }
            DispatchQueue.main.async {
                // HKObserverQuery fires in the foreground too; spinning a headless FlutterEngine
                // while the live app is running re-runs plugin/Firebase init and crashes. The
                // foreground app already syncs via its normal in-app path, so only the background
                // case needs the headless engine.
                guard UIApplication.shared.applicationState == .background else {
                    hkCompletion()
                    return
                }
                let worker = HKBackgroundDeliveryWorker()
                let workerKey = ObjectIdentifier(worker)
                HKObserverManager.shared.activeWorkers[workerKey] = worker
                worker.run {
                    hkCompletion()
                    HKObserverManager.shared.activeWorkers[workerKey] = nil
                }
            }
        }

        healthStore.execute(query)
        activeQueries.append(query)
    }
}
