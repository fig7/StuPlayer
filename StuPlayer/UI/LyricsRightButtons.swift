//
//  LyricsRightButtons.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 13/04/2025.
//

import SwiftUI

struct LyricsRightButtons : View {
  let model: PlayerDataModel
  @ObservedObject var lyricsEditor: LyricsEditor
  @ObservedObject var playerSelection: PlayerSelection
  @FocusState.Binding var focusState: ViewFocus?

  var body : some View {
    HStack(spacing: 20) {
      Button(action: {
        let trackURL = model.lyricsTrackURL()
        lyricsEditor.editLyrics(trackURL)
      }) {
        Text("Edit notes & lyrics").frame(width: 120).padding(.horizontal, 10).padding(.vertical, 2)
      }.disabled(lyricsEditor.lyricsEdit)

      Button(action: model.toggleLyrics) {
        switch(playerSelection.lyricsMode) {
        case LyricsMode.Navigate:
          Text("Lyrics: Seek to position").frame(width: 150).padding(.horizontal, 10).padding(.vertical, 2)

        case LyricsMode.Update:
          Text("Lyrics: Update times").frame(width: 150).padding(.horizontal, 10).padding(.vertical, 2)
        }
      }

      // Dummy text field to hold focus
      TextField("", text: $playerSelection.dummyString).frame(width: 0)
      .autocorrectionDisabled(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
      .textSelection(.disabled)
      .focused($focusState, equals: .LyricsScrollView)
      .opacity(0.0)    }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
  }
}
