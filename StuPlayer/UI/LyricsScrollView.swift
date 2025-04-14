//
//  LyricsScrollView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 10/01/2025.
//

import SwiftUI

struct LyricsItemView : View {
  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection
  @ObservedObject var lyricsEditor: LyricsEditor

  let itemText: String
  let itemIndex: Int

  let itemPlaying: Bool
  let lyricsItem: Bool
  let highlighted: Bool

  let updateLyrics: Bool
  let updateAllowed: Bool

  init(model: PlayerDataModel, playerSelection: PlayerSelection, lyricsEditor: LyricsEditor, itemText: String, itemIndex: Int) {
    self.model = model
    self.playerSelection = playerSelection
    self.lyricsEditor    = lyricsEditor

    self.itemText     = itemText
    self.itemIndex    = itemIndex

    itemPlaying   = (playerSelection.playbackState == .playing)
    lyricsItem    = (itemIndex == (playerSelection.lyricsPosition))
    highlighted   = (itemIndex == playerSelection.lyricsScrollPos)

    updateLyrics  = (playerSelection.lyricsMode == .Update)
    updateAllowed = (!lyricsEditor.lyricsEdit)
  }

  var body: some View {
    HStack(spacing: 0) {
      Text("         ").onTapGesture { lyricsItem ? model.togglePause() : nil}
      Text(itemText).fontWeight((highlighted || lyricsItem) ? .semibold : nil).padding(.horizontal, 4)
        .background(highlighted  ? updateLyrics ? updateAllowed ? RoundedRectangle(cornerRadius: 5).foregroundColor(.orange.opacity(0.8))
                                                                : RoundedRectangle(cornerRadius: 5).foregroundColor(.red.opacity(0.8))
                                                : RoundedRectangle(cornerRadius: 5).foregroundColor(.blue.opacity(0.3))
                                 : nil)
        .onTapGesture { if(!updateLyrics || updateAllowed) { model.lyricsItemSelected(itemIndex) } }
    }
    .background(lyricsItem ? Image(itemPlaying ? "Playing" : "Paused").resizable().aspectRatio(contentMode: .fit) : nil, alignment: .leading)
    .frame(minWidth: 150, alignment: .leading).padding(.horizontal, 4)
  }
}

struct LyricsScrollView : View {
  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection
  @ObservedObject var lyricsEditor: LyricsEditor

  let hasFocus: Bool
  let textHeight: CGFloat
  let viewHeight: CGFloat

  var body : some View {
    ScrollViewReader { scrollViewProxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if(hasFocus) {
            HStack() {
              DummyView(action: { lyricsDown     (proxy: scrollViewProxy) }).keyboardShortcut(.downArrow, modifiers: [])
              DummyView(action: { lyricsPageDown (proxy: scrollViewProxy) }).keyboardShortcut(.pageDown,  modifiers: [])
              DummyView(action: { lyricsEnd      (proxy: scrollViewProxy) }).keyboardShortcut(.end,       modifiers: [])

              DummyView(action: { lyricsUp      (proxy: scrollViewProxy) }).keyboardShortcut(.upArrow, modifiers: [])
              DummyView(action: { lyricsPageUp  (proxy: scrollViewProxy) }).keyboardShortcut(.pageUp,  modifiers: [])
              DummyView(action: { lyricsHome    (proxy: scrollViewProxy) }).keyboardShortcut(.home,    modifiers: [])

              DummyView(action: { lyricsSelected(proxy: scrollViewProxy) }).keyboardShortcut(.clear, modifiers: [])
            }.frame(maxWidth: 0, maxHeight: 0)
          }

          LazyVStack(alignment: .leading, spacing: 0) {
            if(playerSelection.playingLyrics.count > 1) {
              ForEach(Array(playerSelection.playingLyrics.enumerated()), id: \.offset) { itemIndex, item in
                LyricsItemView(model: model, playerSelection: playerSelection, lyricsEditor: lyricsEditor, itemText: item.text, itemIndex: itemIndex)
              }
            }
          }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        }
      }
      .onChange(of: playerSelection.lyricsPosition) { newPos in
        if(newPos == -1) { return }
        scrollViewProxy.scrollTo(newPos, anchor: .center)
      }
    }
  }

  func lyricsDown(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.playingLyrics.count - 1
    if(playerSelection.lyricsScrollPos >= listLimit) { return }

    playerSelection.lyricsScrollPos += 1
    proxy.scrollTo(playerSelection.lyricsScrollPos)
  }

  func lyricsPageDown(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.playingLyrics.count - 1
    if(playerSelection.lyricsScrollPos >= listLimit) { return }

    let linesToScroll = Int(0.5 + viewHeight / textHeight)
    var newScrollPos  = ((playerSelection.lyricsScrollPos < 0) ? 0 : playerSelection.lyricsScrollPos) + linesToScroll
    if(newScrollPos > listLimit) { newScrollPos = listLimit }

    playerSelection.lyricsScrollPos = newScrollPos;
    proxy.scrollTo(playerSelection.lyricsScrollPos)
  }

  func lyricsEnd(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.playingLyrics.count - 1
    if(playerSelection.lyricsScrollPos >= listLimit) { return }

    playerSelection.lyricsScrollPos = listLimit;
    proxy.scrollTo(playerSelection.lyricsScrollPos)
  }

  func lyricsUp(proxy: ScrollViewProxy) {
    if(playerSelection.lyricsScrollPos <= 0) { return }

    playerSelection.lyricsScrollPos -= 1;
    proxy.scrollTo(playerSelection.lyricsScrollPos)
  }

  func lyricsPageUp(proxy: ScrollViewProxy) {
    if(playerSelection.lyricsScrollPos <= 0) { return }

    let linesToScroll = Int(0.5 + viewHeight / textHeight)
    var newScrollPos = playerSelection.lyricsScrollPos - linesToScroll
    if(newScrollPos < 0) { newScrollPos = 0 }

    playerSelection.lyricsScrollPos = newScrollPos;
    proxy.scrollTo(playerSelection.lyricsScrollPos)
  }

  func lyricsHome(proxy: ScrollViewProxy) {
    if(playerSelection.lyricsScrollPos > 0) {
      playerSelection.lyricsScrollPos = 0
    }

    proxy.scrollTo(0)
  }

  func lyricsSelected(proxy: ScrollViewProxy) {
    playerSelection.lyricsScrollPos = playerSelection.lyricsPosition
    proxy.scrollTo(playerSelection.lyricsScrollPos, anchor: .center)
  }
}
