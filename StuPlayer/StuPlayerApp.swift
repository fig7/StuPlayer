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
  @ObservedObject var skManager: SKManager
  var productID: String

  @State var isPurchased = false
  @State var product: Product? = nil

  var body: some View {
    Button(action: {
      Task {
        guard let product else { print("Error product is nil"); return }
        let displayName = product.displayName

        do {
          let transaction = try await skManager.purchaseProduct(product)
          if(transaction == nil) { print("Purchase of " + displayName + ": no result (transaction cancelled?)"); return }

          print(displayName + " purchased: " + (transaction?.debugDescription ?? "No debug info"))
        } catch {
          print("Error making purchase of " + displayName + ": " + error.localizedDescription)
        }
      }
    }) {
      if(product == nil) { Text("Waiting for update... (or error)") }
      else if(isPurchased) { HStack { Text(product!.displayName + "(purchased)").bold().padding(10); Image(systemName: "checkmark") } }
      else { Text("Purchase " + product!.displayName + " " + product!.displayPrice) }
    }
    .disabled((product == nil) || isPurchased)
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
  @State private var skManager: SKManager
  @State private var playerDataModel: PlayerDataModel

  init() {
    let playerAlert     = PlayerAlert()
    let playerSelection = PlayerSelection()

    skManager = SKManager()
    playerDataModel = PlayerDataModel(playerAlert: playerAlert, playerSelection: playerSelection)
  }

  var body: some Scene {
    WindowGroup() {
      ContentView(model: playerDataModel, skManager: skManager, playerAlert: playerDataModel.playerAlert, playerSelection: playerDataModel.playerSelection)
    }.defaultSize(width: 928, height: 498).commands {
      CommandGroup(replacing: .newItem) { }
      CommandGroup(after: .appInfo, addition: {
        PPView(skManager: skManager, productID: plvProductID)
        PPView(skManager: skManager, productID: lvProductID)
        Button("Restore purchases", action: {
          Task { try? await AppStore.sync() }
        })
      })
    }
  }
}

struct StuPlayerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var skManager: SKManager
  @State private var playerDataModel: PlayerDataModel

  init() {
    let playerAlert     = PlayerAlert()
    let playerSelection = PlayerSelection()

    skManager = SKManager()
    playerDataModel = PlayerDataModel(playerAlert: playerAlert, playerSelection: playerSelection)
  }

  var body: some Scene {
    WindowGroup() {
      ContentView(model: playerDataModel, skManager: skManager, playerAlert: playerDataModel.playerAlert, playerSelection: playerDataModel.playerSelection)
    }.commands {
      CommandGroup(replacing: .newItem) { }
      CommandGroup(after: .appInfo, addition: {
        PPView(skManager: skManager, productID: plvProductID)
        PPView(skManager: skManager, productID: lvProductID)
        Button("Restore purchases", action: {
          Task { try? await AppStore.sync() }
        })
      })
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
