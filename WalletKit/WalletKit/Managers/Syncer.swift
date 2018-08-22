import Foundation
import RxSwift
import RealmSwift

class Syncer {

    enum SyncStatus {
        case syncing
        case synced
        case error
    }

    weak var headerSyncer: HeaderSyncer?
    weak var headerHandler: HeaderHandler?
    weak var transactionHandler: TransactionHandler?
    weak var blockSyncer: BlockSyncer?

    private let logger: Logger
    private let realmFactory: RealmFactory

    let syncSubject = BehaviorSubject<SyncStatus>(value: .synced)

    private var status: SyncStatus = .synced {
        didSet {
            syncSubject.onNext(status)
        }
    }

    init(logger: Logger, realmFactory: RealmFactory) {
        self.logger = logger
        self.realmFactory = realmFactory
    }

    private func initialSync() {
        status = .syncing
    }

}

extension Syncer: PeerGroupDelegate {

    func peerGroupDidConnect() {
        do {
            try headerSyncer?.sync()
        } catch {
            logger.log(tag: "Header Syncer Error", message: "\(error)")
        }

        blockSyncer?.enqueueRun()
    }

    func peerGroupDidDisconnect() {
    }

    func peerGroupDidReceive(headers: [BlockHeader]) {
        do {
            try headerHandler?.handle(headers: headers)
        } catch {
            logger.log(tag: "Header Handler Error", message: "\(error)")
        }
    }

    func peerGroupDidReceive(blockHeaderHash: Data, withTransactions transactions: [Transaction]) {
        print("BLOCK: \(blockHeaderHash.reversedHex) --- \(transactions.count)")
        do {
            try transactionHandler?.handle(blockTransactions: transactions, blockHeaderHash: blockHeaderHash)
        } catch {
            logger.log(tag: "Transaction Handler Error", message: "\(error)")
        }
    }

    func peerGroupDidReceive(transaction: Transaction) {
        print("TX: \(transaction.reversedHashHex)")
        do {
            try transactionHandler?.handle(memPoolTransactions: [transaction])
        } catch {
            logger.log(tag: "Transaction Handler Error", message: "\(error)")
        }
    }

    func shouldRequest(inventoryItem: InventoryItem) -> Bool {
        let realm = realmFactory.realm

        switch inventoryItem.objectType {
            case .transaction:
                return realm.objects(Transaction.self).filter("reversedHashHex = %@", inventoryItem.hash.reversedHex).isEmpty
            case .blockMessage:
                return realm.objects(Block.self).filter("reversedHeaderHashHex = %@", inventoryItem.hash.reversedHex).isEmpty
            case .filteredBlockMessage, .compactBlockMessage, .unknown, .error:
                return false
        }
    }

    func transaction(forHash hash: Data) -> Transaction? {
        return realmFactory.realm.objects(Transaction.self).filter("reversedHashHex = %@", hash.reversedHex).first
    }

}