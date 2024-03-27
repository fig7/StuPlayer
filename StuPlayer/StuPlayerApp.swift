//
//  StuPlayerApp.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import SwiftUI

@main
struct StuPlayerApp: App {
  @State private var playerDataModel: PlayerDataModel

  init() {
    let playerSelection = PlayerSelection()
    playerDataModel     = PlayerDataModel(playerSelection: playerSelection)
  }

  var body: some Scene {
    WindowGroup() {
      ContentView(model: playerDataModel, playerSelection: playerDataModel.playerSelection)
    } .defaultSize(width: 928, height: 494)
  }
}
