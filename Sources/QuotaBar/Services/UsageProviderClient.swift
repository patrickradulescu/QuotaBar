import Foundation
import QuotaBarCore

protocol UsageProviderClient: AnyObject {
    var provider: ProviderKind { get }
    var onUpdate: ((ProviderUsage) -> Void)? { get set }

    func start()
    func refresh()
    func stop()
}
