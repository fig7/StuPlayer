//
//  StuPlayerApp.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import SwiftUI
import StoreKit

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return true }
  func applicationWillFinishLaunching(_ notification: Notification) { NSWindow.allowsAutomaticWindowTabbing = false; }
}

struct PPView: View {
  var productID: String
  @ObservedObject var storeManager: SKManager

  @State var isPurchased = false
  @State var product: Product? = nil

  var body: some View {
    Button(action: {
      Task {
        guard let product else { print("Error product is nil"); return }
        let displayName = product.displayName

        do {
          let transaction = try await storeManager.purchaseProduct(product)
          if(transaction == nil) { print("Purchase of " + displayName + ": no result (transaction cancelled?)"); return }

          print(displayName + " purchased: " + (transaction?.debugDescription ?? "No debug info"))
        } catch {
          print("Error making purchase of " + displayName + ": " + error.localizedDescription)
        }
      }
    }) {
      if(product == nil) { Text("Waiting for update... (or error)") }
      else if(isPurchased) { HStack { Text(product!.displayName + " (purchased)").bold().padding(10); Image(systemName: "checkmark") } }
      else { Text("Purchase " + product!.displayName + " " + product!.displayPrice) }
    }
    .disabled((product == nil) || isPurchased)
    .onChange(of: storeManager.spProducts) { _ in
      Task { product = storeManager.productFromID(productID) }
    }
    .onChange(of: storeManager.purchasedProducts) { _ in
      Task { isPurchased = storeManager.isPurchased(product) }
    }
  }
}

struct RPView: View {
  @ObservedObject var skManager: SKManager
  var productID: String

  @State var isPurchased = false
  @State var product: Product? = nil

  var body: some View {
    Button(action: {
      Task {
        guard let product else { print("Error product is nil"); return }

        let result = await product.latestTransaction
        guard let result else { print("Error transaction is nil"); return }

        switch result {
        case .verified(let transaction):
          let vc = NSApplication.shared.orderedWindows.first?.contentViewController
          guard let vc else { print("Error vc is nil"); return }
          do {
            let requestStatus = try await transaction.beginRefundRequest(in: vc)
            print("Refund request status: \(requestStatus)")
          } catch {
            print("RefundRequest failed: " + error.localizedDescription); return
          }

        default:
          print("Error transaction is not verified")
        }
      }
    }) {
      if(product == nil) { Text("Waiting for update... (or error)") }
      else { Text("Request refund for " + product!.displayName) }
    }
    .disabled((product == nil) || !isPurchased)
    .onChange(of: skManager.spProducts) { _ in
      Task { product = skManager.productFromID(productID) }
    }
    .onChange(of: skManager.purchasedProducts) { _ in
      Task { isPurchased = skManager.isPurchased(product) }
    }
  }
}


@available(macOS 13.0, *)
struct StuPlayerApp13 : App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var skManager = SKManager()
  @State private var playerDataModel: PlayerDataModel

  init() {
    let playerAlert     = PlayerAlert()
    let playerSelection = PlayerSelection()
    playerDataModel = PlayerDataModel(playerAlert: playerAlert, playerSelection: playerSelection)
  }

  var body: some Scene {
    WindowGroup() {
      ContentView(model: playerDataModel, skManager: skManager, playerAlert: playerDataModel.playerAlert, playerSelection: playerDataModel.playerSelection)
    }.defaultSize(width: 1124, height: 734).commands {
      CommandGroup(replacing: .newItem) { }
      CommandMenu("Purchases") {
        PPView(productID: plvProductID, storeManager: skManager).disabled(!skManager.canMakePayments)
        RPView(skManager: skManager, productID: plvProductID).disabled(!skManager.canMakePayments)

        Divider()

        PPView(productID: lvProductID, storeManager: skManager).disabled(!skManager.canMakePayments)
        RPView(skManager: skManager, productID: lvProductID).disabled(!skManager.canMakePayments)

        Divider()

        Button("Restore purchases", action: { skManager.sync() })
      }
    }
  }
}

struct StuPlayerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var skManager = SKManager()
  @State private var playerDataModel: PlayerDataModel

  init() {
    let playerAlert     = PlayerAlert()
    let playerSelection = PlayerSelection()
    playerDataModel = PlayerDataModel(playerAlert: playerAlert, playerSelection: playerSelection)
  }

  var body: some Scene {
    WindowGroup() {
      ContentView(model: playerDataModel, skManager: skManager, playerAlert: playerDataModel.playerAlert, playerSelection: playerDataModel.playerSelection)
    }.commands {
      CommandGroup(replacing: .newItem) { }
      CommandMenu("Purchases") {
        PPView(productID: plvProductID, storeManager: skManager).disabled(!skManager.canMakePayments)
        RPView(skManager: skManager, productID: plvProductID).disabled(!skManager.canMakePayments)

        Divider()

        PPView(productID: lvProductID, storeManager: skManager).disabled(!skManager.canMakePayments)
        RPView(skManager: skManager, productID: lvProductID).disabled(!skManager.canMakePayments)

        Divider()

        Button("Restore purchases", action: { skManager.sync() })
      }
    }
  }
}

@main
struct Main {
    static func main() {
        if #available(macOS 13.0, *) {
          StuPlayerApp13.main()
        } else {
          StuPlayerApp.main()
        }
    }
}
