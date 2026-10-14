import Foundation
import IOKit.pwr_mgt

final class SleepGuard {

    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    func begin(reason: String = "Aria está grabando una reunión") {
        guard !isActive else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        isActive = result == kIOReturnSuccess
        if !isActive {
            print("[aviso] No se pudo crear la aserción NoDisplaySleep (código \(result)); la pantalla podría dormirse y silenciar la captura del sistema.")
        }
    }

    func end() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit {
        end()
    }
}
