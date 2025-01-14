//
//  PlayerAlert.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 02/04/2024.
//

import Foundation

@MainActor class PlayerAlert: ObservableObject
{
  @Published var alertTriggered = false
  @Published var alertMessage   = ""

  func triggerAlert(alertMessage: String) {
    self.alertMessage = alertMessage
    alertTriggered = true
  }
}
