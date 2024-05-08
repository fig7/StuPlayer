//
//  StuPlayerApp.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return true }
  func applicationWillFinishLaunching(_ notification: Notification) { NSWindow.allowsAutomaticWindowTabbing = false; }
}

@available(macOS 13.0, *)
struct StuPlayerApp13 : App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var playerDataModel: PlayerDataModel

  init() {
    let playerAlert     = PlayerAlert()
    let playerSelection = PlayerSelection()
    playerDataModel     = PlayerDataModel(playerAlert: playerAlert, playerSelection: playerSelection)
  }

  var body: some Scene {
    WindowGroup() {
      ContentView(model: playerDataModel, playerAlert: playerDataModel.playerAlert, playerSelection: playerDataModel.playerSelection)
    }.defaultSize(width: 928, height: 498).commands {
      CommandGroup(replacing: .newItem) { }
      CommandGroup(after: .appInfo, addition: { Link("Make a donation...", destination: URL(string: "https://patreon.com/StuartFisher")!) })
    }
  }
}

struct StuPlayerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var playerDataModel: PlayerDataModel

  init() {
    let playerAlert     = PlayerAlert()
    let playerSelection = PlayerSelection()
    playerDataModel     = PlayerDataModel(playerAlert: playerAlert, playerSelection: playerSelection)
  }

  var body: some Scene {
    WindowGroup() {
      ContentView(model: playerDataModel, playerAlert: playerDataModel.playerAlert, playerSelection: playerDataModel.playerSelection)
    }.commands {
      CommandGroup(replacing: .newItem) { }
      CommandGroup(after: .appInfo, addition: { Link("Make a donation...", destination: URL(string: "https://patreon.com/StuartFisher")!) })
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
