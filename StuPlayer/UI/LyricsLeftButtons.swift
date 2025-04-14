//
//  LyricsButtons.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 13/04/2025.
//

import SwiftUI

struct LyricsLeftButtons : View {
  let model: PlayerDataModel
  @ObservedObject var lyricsEditor: LyricsEditor
  @ObservedObject var playerSelection: PlayerSelection
  @FocusState.Binding var focusState: ViewFocus?

  var body : some View {
    HStack(spacing: 20) {
      Button(action: model.fetchLyrics) {
        Text("Fetch from lyrics.ovh").frame(width: 140).padding(.horizontal, 10).padding(.vertical, 2)
      }.disabled((playerSelection.playPosition <= 0) || !playerSelection.playingLyrics.isEmpty)

      // Dummy text field to hold focus
      TextField("", text: $playerSelection.dummyString).frame(width: 0)
       .autocorrectionDisabled(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
       .textSelection(.disabled)
       .focused($focusState, equals: .LyricsInfoView)
       .opacity(0.0)
    }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
  }
}
