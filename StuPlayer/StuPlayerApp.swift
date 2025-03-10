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

  // Needed because ".defaultLaunchBehavior(.suppressed)" has only just been added in macOS 15
  // For now, I still want to support older versions of the OS.
  func applicationDidFinishLaunching(_ notification: Notification) {
    let appWindows = NSApp.windows
    for window in appWindows {
      guard let id = window.identifier else { continue }
      if (id.rawValue == "spInApp") { window.close(); break }
    }
  }
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

struct InAppHTML: View {
    var body: some View {
      let html = """
      <head>
        <meta charset="utf-8">
        <style>
          body {
            font-family: Arial, sans-serif;
            font-size: 140%;
          }
        </style>
      </head>

      <body>
        In addition to the Browser View and Track View, two other views are available as In-App purchases. The Playlist view shows the tracks that have been queued for playback (the current playlist) and the Lyrics View shows any lyrics that you have added for the currently playing track. For more details, see the relevant sections below.
        <br><br><br>

        <h3>Playlist View</h3><br>
        The Playlist View shows you the list of tracks currently queued. You can use this view to see the tracks that have played and the tracks that will be played next. You can also use it to change the currently playing track (either by clicking on a track directly or by using the keyboard), and to find a track in the playlist (by entering a few letters from the name).
        <br><br><br>

        <h3>Lyrics View</h3><br>
        The Lyrics View shows notes and lyrics for the current track, if any have been added. Notes and lyrics for each track are stored in .spl files. You can enter lyrics manually by creating a .spl file using a text editor, such as TextEdit, or by clicking on the "Fetch lyrics" button to download the lyrics from lyrics.ovh.<br><br>

        Timestamps can then be added by listening for the start of each line and selecting it. This is a bit fiddly (and time consuming), so I will see if I can get AI to generate the timestamps in future versions of StuPlayer. For an explanation of how .spl files work, see StuPlayer help.<br><br>

        The Lyrics View also comes with three buttons: a toggle button that determines what happens when you select a line (update the timestamp or seek to the position), a refresh button that reloads the lyrics from the .spl file, and the previously mentioned "Fetch lyrics" button.
        <br>
      </body>
      """

      let nsAttributedString = try? NSAttributedString(data: Data(html.utf8), options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
      let attributedString = AttributedString(nsAttributedString!)
      ScrollView { Text(attributedString).padding(.top, 20).padding(.horizontal, 20) }
    }
}

@available(macOS 13.0, *)
struct StuPlayerApp13 : App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.openWindow) var openWindow

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
    }
    .defaultSize(width: 1124, height: 734)
    .commands {
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

    Window("StuPlayer In-App Purchases", id: "spInApp") {
      InAppHTML().frame(width: 560, height: 420)
    }
    .windowResizability(.contentSize)
    .onChange(of: skManager.inAppHelpTriggered) { _ in
      skManager.inAppHelpTriggered = false
      openWindow(id: "spInApp")
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
    }
    .commands {
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
