//
//  PlayingScrollView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 10/01/2025.
//

import SwiftUI

struct PlayingItemView : View {
  @State private var playingPopover = false

  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection

  let itemText: String
  let itemSearched: Bool
  let itemIndex: Int

  let itemPlaying: Bool
  let playerItem: Bool
  let highlighted: Bool
  let currentSearch: Bool

  init(model: PlayerDataModel, playerSelection: PlayerSelection, itemText: String, itemSearched: Bool, itemIndex: Int) {
    self.model = model
    self.playerSelection = playerSelection

    self.itemText     = itemText
    self.itemSearched = itemSearched
    self.itemIndex    = itemIndex

    itemPlaying   = (playerSelection.playbackState == .playing)
    playerItem    = (itemIndex == (playerSelection.playPosition-1))
    highlighted   = (itemIndex == playerSelection.playingScrollPos)
    currentSearch = (itemIndex == playerSelection.searchIndex) && itemSearched
  }

  var body: some View {
    HStack(spacing: 0) {
      Text("         ").onTapGesture { playerItem ? model.togglePause() : nil}
      Text(itemText).fontWeight((highlighted || playerItem) ? .semibold : nil).padding(.horizontal, 4)
        .background(highlighted   ? RoundedRectangle(cornerRadius: 5).foregroundColor(.blue.opacity(0.3)) :
                    currentSearch ? RoundedRectangle(cornerRadius: 5).foregroundColor(.orange.opacity(1.0)) :
                    itemSearched  ? RoundedRectangle(cornerRadius: 5).foregroundColor(.yellow.opacity(0.5)) : nil)
        .onTapGesture { model.playingItemClicked(itemIndex) }
        .onHover(perform: { hovering in
          if(hovering) {
            if(playerSelection.playingPopover == itemIndex) { return }
            model.playingDelayAction(itemIndex) { playerSelection.playingPopover = itemIndex }
          } else {
            model.delayCancel();
            playerSelection.playingPopover = -1 }
          })
        .popover(isPresented: $playingPopover) { Text(playerSelection.playingTrackInfo).font(.headline).padding() }
        .sync($playerSelection.playingPopover, with: $playingPopover, for: itemIndex)
    }
    .background(playerItem ? Image(itemPlaying ? "Playing" : "Paused").resizable().aspectRatio(contentMode: .fit) : nil, alignment: .leading)
    .frame(minWidth: 150, alignment: .leading).padding(.horizontal, 4)
  }
}

struct PlayingScrollView : View {
  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection

  let hasFocus: Bool
  let textHeight: CGFloat
  let viewHeight: CGFloat

  var body : some View {
    ScrollViewReader { scrollViewProxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if(hasFocus) {
            HStack() {
              DummyView(action: { playingDown     (proxy: scrollViewProxy) }).keyboardShortcut(.downArrow, modifiers: [])
              DummyView(action: { playingPageDown (proxy: scrollViewProxy) }).keyboardShortcut(.pageDown,  modifiers: [])
              DummyView(action: { playingEnd      (proxy: scrollViewProxy) }).keyboardShortcut(.end,       modifiers: [])

              DummyView(action: { playingUp      (proxy: scrollViewProxy) }).keyboardShortcut(.upArrow, modifiers: [])
              DummyView(action: { playingPageUp  (proxy: scrollViewProxy) }).keyboardShortcut(.pageUp,  modifiers: [])
              DummyView(action: { playingHome    (proxy: scrollViewProxy) }).keyboardShortcut(.home,    modifiers: [])

              DummyView(action: { playingCurrent(proxy: scrollViewProxy) }).keyboardShortcut(.clear, modifiers: [])
            }.frame(maxWidth: 0, maxHeight: 0)
          }

          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(playerSelection.playingTracks.enumerated()), id: \.offset) { itemIndex, item in
              PlayingItemView(model: model, playerSelection: playerSelection, itemText: item.name, itemSearched: item.searched, itemIndex: itemIndex)
            }
          }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        }
      }
      .onChange(of: playerSelection.playPosition) { newPos in
        if(newPos == 0) { return }

        playerSelection.prevSel = -1
        playerSelection.currSel = -1
        scrollViewProxy.scrollTo(newPos-1, anchor: .center)
      }
      .onChange(of: playerSelection.playingScrollTo) { _ in
        if(playerSelection.playingScrollTo == -1) { return }

        scrollViewProxy.scrollTo(playerSelection.playingScrollTo, anchor: .center)
        playerSelection.prevSel = playerSelection.playingScrollTo
        playerSelection.currSel = playerSelection.playingScrollTo
        playerSelection.playingScrollTo = -1
      }
    }
  }

  func playingDown(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.playingTracks.count - 1
    if(playerSelection.playingScrollPos >= listLimit) { return }

    playerSelection.playingScrollPos += 1
    playerSelection.searchIndex       = playerSelection.playingScrollPos

    playerSelection.prevSel = playerSelection.playingScrollPos
    playerSelection.currSel = playerSelection.playingScrollPos

    proxy.scrollTo(playerSelection.playingScrollPos)
  }

  func playingPageDown(proxy: ScrollViewProxy) {
    if(playerSelection.searchDownAllowed) {
      _ = playerSelection.searchNext()
      return
    }

    let listLimit = playerSelection.playingTracks.count - 1
    if(playerSelection.playingScrollPos >= listLimit) { return }

    let linesToScroll = Int(0.5 + viewHeight / textHeight)
    var newScrollPos  = ((playerSelection.playingScrollPos < 0) ? 0 : playerSelection.playingScrollPos) + linesToScroll
    if(newScrollPos > listLimit) { newScrollPos = listLimit }

    playerSelection.playingScrollPos = newScrollPos;
    playerSelection.searchIndex      = playerSelection.playingScrollPos

    playerSelection.prevSel = playerSelection.playingScrollPos
    playerSelection.currSel = playerSelection.playingScrollPos

    proxy.scrollTo(playerSelection.playingScrollPos)
  }

  func playingEnd(proxy: ScrollViewProxy) {
    if(playerSelection.searchDownAllowed) {
      _ = playerSelection.searchEnd()
      return
    }

    let listLimit = playerSelection.playingTracks.count - 1
    if(playerSelection.playingScrollPos >= listLimit) { return }

    playerSelection.playingScrollPos = listLimit;
    playerSelection.searchIndex      = playerSelection.playingScrollPos

    playerSelection.prevSel = playerSelection.playingScrollPos
    playerSelection.currSel = playerSelection.playingScrollPos

    proxy.scrollTo(playerSelection.playingScrollPos)
  }

  func playingUp(proxy: ScrollViewProxy) {
    if(playerSelection.playingScrollPos <= 0) { return }

    playerSelection.playingScrollPos -= 1;
    playerSelection.searchIndex = playerSelection.playingScrollPos

    playerSelection.prevSel = playerSelection.playingScrollPos
    playerSelection.currSel = playerSelection.playingScrollPos

    proxy.scrollTo(playerSelection.playingScrollPos)
  }

  func playingPageUp(proxy: ScrollViewProxy) {
    if(playerSelection.searchUpAllowed) {
      _ = playerSelection.searchPrev()
      return
    }

    if(playerSelection.playingScrollPos <= 0) { return }

    let linesToScroll = Int(0.5 + viewHeight / textHeight)
    var newScrollPos = playerSelection.playingScrollPos - linesToScroll
    if(newScrollPos < 0) { newScrollPos = 0 }

    playerSelection.playingScrollPos = newScrollPos;
    playerSelection.searchIndex      = playerSelection.playingScrollPos

    playerSelection.prevSel = playerSelection.playingScrollPos
    playerSelection.currSel = playerSelection.playingScrollPos

    proxy.scrollTo(playerSelection.playingScrollPos)
  }

  func playingHome(proxy: ScrollViewProxy) {
    if(playerSelection.searchUpAllowed) {
      _ = playerSelection.searchHome()
      return
    }

    if(playerSelection.playingScrollPos > 0) {
      playerSelection.playingScrollPos = 0
      playerSelection.searchIndex      = 0

      playerSelection.prevSel = playerSelection.playingScrollPos
      playerSelection.currSel = playerSelection.playingScrollPos
    }

    proxy.scrollTo(0)
  }

  func playingCurrent(proxy: ScrollViewProxy) {
    if(playerSelection.playingScrollPos < 0) {
      playerSelection.playingScrollPos = playerSelection.playPosition - 1
      playerSelection.searchIndex      = playerSelection.playingScrollPos

      playerSelection.prevSel = playerSelection.playingScrollPos
      playerSelection.currSel = playerSelection.playingScrollPos
      proxy.scrollTo(playerSelection.playingScrollPos, anchor: .center)
      return
    }

    if(playerSelection.currSel < 0) {
      playerSelection.prevSel = playerSelection.playingScrollPos
      playerSelection.currSel = playerSelection.playingScrollPos
      proxy.scrollTo(playerSelection.playingScrollPos, anchor: .center)
      return
    }

    let playingSel = playerSelection.playPosition - 1
    if(playerSelection.currSel != playingSel) {
      playerSelection.playingScrollPos = playingSel
      playerSelection.searchIndex      = playerSelection.playingScrollPos

      playerSelection.currSel = playerSelection.playingScrollPos
      proxy.scrollTo(playerSelection.playingScrollPos, anchor: .center)
      return
    }

    playerSelection.playingScrollPos = playerSelection.prevSel
    playerSelection.searchIndex      = playerSelection.playingScrollPos

    playerSelection.currSel = playerSelection.prevSel
    proxy.scrollTo(playerSelection.playingScrollPos, anchor: .center)
  }
}
