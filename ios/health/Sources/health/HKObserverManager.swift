import Foundation
import HealthKit
import os

class HKObserverManager {
    static let shared = HKObserverManager()

    private static let log = OSLog(
        subsystem: "co.za.apextechnology.womenscalorietracker",
        category: "HealthKitBGDelivery"
    )

    private var activeQueries: [HKObserverQuery] = []
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

    // HealthKit rejects background delivery for workout, audiogram, series and route types.
    private func isBackgroundDeliverySupported(_ sampleType: HKSampleType) -> Bool {
        if sampleType is HKWorkoutType { return false }
        if sampleType is HKAudiogramSampleType { return false }
        if sampleType is HKSeriesType { return false }
        if #available(iOS 14.0, *), sampleType is HKElectrocardiogramType { return false }
        return true
    }

    private func registerObserver(healthStore: HKHealthStore, sampleType: HKSampleType, typeName: String) {
        healthStore.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { success, error in
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
                HKBackgroundDeliveryWorker().run { hkCompletion() }
            }
        }

        healthStore.execute(query)
        activeQueries.append(query)
    }
}
