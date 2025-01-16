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

struct TestyView: View {
    @StateObject var sK = SKManager()

    var body: some View {
        VStack(alignment: .leading) {
            Text("In-App Purchase Demo")
                .bold()
            Divider()
            ForEach(sK.spProducts) {product in
                HStack {
                    Text(product.displayName)
                    Spacer()
                    Button(action: {
                        // purchase this product
                      Task { try await sK.purchaseProduct(product)
                        }
                    }) {
                        CourseItem(storeKit: sK, product: product)

                    }
                }

            }
            Divider()
            Button("Restore Purchases", action: {
                Task {
                    //This call displays a system prompt that asks users to authenticate with their App Store credentials.
                    //Call this function only in response to an explicit user action, such as tapping a button.
                    try? await AppStore.sync()
                }
            })
        }
        .padding()

    }
}

struct CourseItem: View {
    @ObservedObject var storeKit : SKManager
    @State var isPurchased: Bool = false
    var product: Product

    var body: some View {
        VStack {
            if isPurchased {
                Text(Image(systemName: "checkmark"))
                    .bold()
                    .padding(10)
            } else {
                Text(product.displayPrice)
                    .padding(10)
            }
        }
        .onChange(of: storeKit.purchasedProducts) { course in
            Task {
                isPurchased = storeKit.isPurchased(product)
            }
        }
    }
}

@available(macOS 13.0, *)
struct StuPlayerApp13 : App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  // @StateObject private var skManager = SKManager()
  // @State private var playerDataModel: PlayerDataModel

  init() {
    // let playerAlert     = PlayerAlert()
    // let playerSelection = PlayerSelection()
    // playerDataModel = PlayerDataModel(playerAlert: playerAlert, playerSelection: playerSelection)
  }

  var body: some Scene {
    WindowGroup() {
      TestyView()
      // ContentView(model: playerDataModel, skManager: skManager, playerAlert: playerDataModel.playerAlert, playerSelection: playerDataModel.playerSelection)
      Text("Hi there!")
    }.defaultSize(width: 928, height: 498).commands {
      CommandGroup(replacing: .newItem) { }
      /* CommandGroup(after: .appInfo, addition: {
        PPView(skManager: skManager, productID: plvProductID)
        PPView(skManager: skManager, productID: lvProductID)
        Button("Restore purchases", action: {
          Task { try? await AppStore.sync() }
        })
      }) */
    }
  }
}

struct StuPlayerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var skManager = SKManager()
  // @State private var playerDataModel: PlayerDataModel

  init() {
    // let playerAlert     = PlayerAlert()
    // let playerSelection = PlayerSelection()
    // playerDataModel = PlayerDataModel(playerAlert: playerAlert, playerSelection: playerSelection)
  }

  var body: some Scene {
    WindowGroup() {
      // ContentView(model: playerDataModel, skManager: skManager, playerAlert: playerDataModel.playerAlert, playerSelection: playerDataModel.playerSelection)
      Text("Hi there2!")
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
