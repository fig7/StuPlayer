//
//  SKManager.swift
//  
//
//  Created by Stuart Fisher on 01/01/2025.
//

import Foundation

import OSLog
import StoreKit

let plvProductID = "com.fig7.spplv"
let lvProductID  = "com.fig7.splv"

enum StoreError: Error { case failedVerification }

class SKManager : ObservableObject {
  @Published var spProducts : [Product] = []
  @Published var purchasedProducts: [Product] = []

  @Published var plViewPurchased = false
  @Published var lViewPurchased  = false

  private let productDict : [String : String]
  private var updateListenerTask: Task<Void, Error>? = nil

  init() {
    let plistPath = Bundle.main.path(forResource: "SPSKPL", ofType: "plist")
    if (plistPath == nil) {
      productDict = [:]

      let logger = Logger()
      logger.error("Product dictionary not found!")
      return
    }

    let plist = FileManager.default.contents(atPath: plistPath!)
    if( plist == nil) {
      productDict = [:]

      let logger = Logger()
      logger.error("Product dictionary failed to open!")
      return
    }

    productDict = (try? PropertyListSerialization.propertyList(from: plist!, format: nil) as? [String : String]) ?? [:]
    if(productDict.isEmpty) {
      let logger = Logger()
      logger.error("Product dictionary is empty!")
    }

    updateListenerTask = listenForTransactions()

    Task {
      await requestProducts()
      await updateCustomerProductStatus()
    }
  }

  deinit {
    updateListenerTask?.cancel()
  }

  @MainActor func requestProducts() async {
    do {
      spProducts = try await Product.products(for: productDict.values)
      if(spProducts.count != productDict.count) {
        let logger = Logger()
        let invalidIDs = spProducts.map { $0.id }
        logger.error("Store products are invalid, spIDs: \(invalidIDs, privacy: .public)")
        return
      }

      spProducts.sort { a, b in return a.displayName.contains("Playlist") }
    } catch {
      let logger = Logger()
      logger.error("Error retrieving store products: \(error.localizedDescription)")
      print("")
    }
  }

  func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified:
      throw StoreError.failedVerification

    case .verified(let transaction):
      return transaction
    }
  }

  @MainActor func updateCustomerProductStatus() async {
    var purchasedProducts: [Product] = []
    for await result in Transaction.currentEntitlements {
      do {
        let transaction = try checkVerified(result)
        if let product = spProducts.first(where: { $0.id == transaction.productID }) { purchasedProducts.append(product) }
      } catch {
        let logger = Logger()
        logger.error("Product failed validation, product ID: \(result.unsafePayloadValue.id)")
      }
    }

    self.purchasedProducts = purchasedProducts
    self.plViewPurchased = self.isPurchased(plvProductID)
    self.lViewPurchased  = self.isPurchased(lvProductID)
  }

  func purchaseProduct(_ product: Product) async throws -> Transaction? {
    let result = try await product.purchase()

    switch result {
    case .success(let verificationResult):
      let transaction = try checkVerified(verificationResult)
      await updateCustomerProductStatus()

      await transaction.finish()
      return transaction

    case .pending:
      return nil

    case .userCancelled:
      return nil

    default:
      return nil
    }
  }

  func productFromID(_ productID: String) -> Product? {
    return spProducts.first { product in return (product.id == productID) }
  }

  func isPurchased(_ product: Product?) -> Bool {
    guard let product else { return false }
    return purchasedProducts.contains(product)
  }

  func isPurchased(_ productID: String) -> Bool {
    let product = self.productFromID(productID)
    return isPurchased(product)
  }

  func listenForTransactions() -> Task<Void, Error> {
    Task(priority: .background) {
      for await result in Transaction.updates {
        do {
          let transaction = try self.checkVerified(result)

          await self.updateCustomerProductStatus()
          await transaction.finish()
        } catch {
          print("Transaction failed verification")
        }
      }

      print("Startup listener exit.")
    }
  }

  // Next steps:
  // Implement UI changes for new views (when purchased)
  // Read documents and go to app connect and sort out real transactions?
}
