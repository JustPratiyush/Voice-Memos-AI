import Combine
import CoreLocation
import Foundation

/// Call only when the user has enabled location-based naming in the app's settings.
/// No location manager, permission prompt, or geocoding request exists before invocation.
@MainActor
public final class LocationNamingService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public private(set) var errorMessage: String?

    private var operationID: UUID?
    private var continuation: CheckedContinuation<String?, Never>?
    private var manager: CLLocationManager?
    private var geocoder: CLGeocoder?
    private var timeoutTask: Task<Void, Never>?
    private var authorizationRequested = false
    private var locationRequested = false
    private var isGeocoding = false

    public override init() {
        super.init()
    }

    /// Resolves a nearby place or street name, falling back to the city.
    /// Returns nil on denial, cancellation, timeout, or unavailable location data.
    public func recordingName() async -> String? {
        guard !Task.isCancelled else { return nil }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                cancel()
                self.operationID = id
                self.continuation = continuation
                self.errorMessage = nil
                self.authorizationRequested = false
                self.locationRequested = false
                self.isGeocoding = false

                // A new manager gives each operation its own delegate identity, so callbacks
                // from a cancelled location request cannot complete a newer request.
                let manager = CLLocationManager()
                self.manager = manager
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                manager.delegate = self
                timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                    } catch {
                        return
                    }
                    self?.complete(id, error: "A location name could not be found in time.")
                }
                handleAuthorization(manager, id: id)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.complete(id)
            }
        }
    }

    public func cancel() {
        guard let id = operationID else { return }
        complete(id)
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let identity = ObjectIdentifier(manager)
        Task { @MainActor [weak self] in
            guard let self, let manager = self.manager, ObjectIdentifier(manager) == identity,
                  let id = self.operationID else { return }
            self.handleAuthorization(manager, id: id)
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let identity = ObjectIdentifier(manager)
        Task { @MainActor [weak self] in
            guard let self, self.manager.map(ObjectIdentifier.init) == identity, let id = self.operationID,
                  !self.isGeocoding else { return }
            guard let location = locations.last(where: {
                $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) <= 120
            }) else {
                self.complete(id, error: "A current location could not be determined.")
                return
            }
            self.reverseGeocode(location, id: id)
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let failure = error.localizedDescription
        let identity = ObjectIdentifier(manager)
        Task { @MainActor [weak self] in
            guard let self, self.manager.map(ObjectIdentifier.init) == identity, let id = self.operationID else { return }
            self.complete(id, error: "A location name is unavailable. \(failure)")
        }
    }

    private func handleAuthorization(_ manager: CLLocationManager, id: UUID) {
        guard operationID == id else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            guard !authorizationRequested else { return }
            authorizationRequested = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard !locationRequested else { return }
            locationRequested = true
            manager.requestLocation()
        case .denied:
            complete(id, error: "Allow Location Services in Settings to name recordings by location.")
        case .restricted:
            complete(id, error: "Location Services are restricted on this device.")
        @unknown default:
            complete(id, error: "Location authorization is unavailable.")
        }
    }

    private func reverseGeocode(_ location: CLLocation, id: UUID) {
        guard operationID == id else { return }
        isGeocoding = true
        let geocoder = CLGeocoder()
        self.geocoder = geocoder
        // Geocoding may use Apple's network service; it runs only for this opt-in feature.
        geocoder.reverseGeocodeLocation(location, preferredLocale: .current) { [weak self] placemarks, error in
            let place = placemarks?.first
            let candidates = [
                place?.areasOfInterest?.first,
                place?.name,
                place?.thoroughfare,
                place?.locality,
                place?.administrativeArea
            ]
            let name = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.operationID == id else { return }
                if let name {
                    self.complete(id, value: name)
                } else {
                    self.complete(id, error: failure.map { "A location name is unavailable. \($0)" }
                        ?? "No name was found for this location.")
                }
            }
        }
    }

    private func complete(_ id: UUID, value: String? = nil, error: String? = nil) {
        guard operationID == id else { return }
        operationID = nil
        let pendingContinuation = continuation
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        manager?.delegate = nil
        manager?.stopUpdatingLocation()
        manager = nil
        geocoder?.cancelGeocode()
        geocoder = nil
        errorMessage = error
        pendingContinuation?.resume(returning: value)
    }
}
