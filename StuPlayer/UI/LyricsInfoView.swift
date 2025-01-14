//
//  LyricsInfoView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 10/01/2025.
//

import SwiftUI

struct LyricsTrackInfo : View {
  let lyricsInfo: (artist: String, album: String, track: String)
  let highlighted: Bool

  var body : some View {
    VStack(alignment: .leading) {
      HStack {
        Text("Artist:").font(.headline).frame(width: 50, alignment: .leading)
        Text(lyricsInfo.artist).font(.headline)
      }.padding(.horizontal, 4)

      HStack {
        Text("Album:").font(.headline).frame(width: 50, alignment: .leading)
        Text(lyricsInfo.album).font(.headline)
      }.padding(.horizontal, 4)

      HStack {
        Text("Track:").font(.headline).frame(width: 50, alignment: .leading)
        Text(lyricsInfo.track).font(.headline)
      }.padding(.horizontal, 4)
    }.background(highlighted ? RoundedRectangle(cornerRadius: 5).foregroundColor(.blue.opacity(0.3)) : nil)
  }
}

struct LyricsNotes : View {
  let playingNotes: String
  let playingLyrics: [LyricsItem]
  let highlighted: Bool

  var body : some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Notes:").font(.headline).frame(width: 50, alignment: .leading).padding(.horizontal, 4)
      Text(playingNotes.isEmpty ? "No notes added"  : playingNotes).font(.headline).padding(.leading, 20).padding(.trailing, 4)
      if(playingLyrics.isEmpty) { Text("No lyrics added").font(.headline).padding(.leading, 20).padding(.trailing, 4) }
    }.background(highlighted ? RoundedRectangle(cornerRadius: 5).foregroundColor(.blue.opacity(0.3)) : nil)
  }
}

struct LyricsInfoView : View {
  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection

  let hasFocus: Bool
  let textHeight: CGFloat
  let viewHeight: CGFloat

  @State private var lyricsInfoPopover = false
  @State private var lyricsNotesPopover = false

  var body : some View {
    ScrollViewReader { scrollViewProxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if(hasFocus) {
            HStack() {
              DummyView(action: { infoDown (proxy: scrollViewProxy) }).keyboardShortcut(.downArrow, modifiers: [])
              DummyView(action: { infoDown (proxy: scrollViewProxy) }).keyboardShortcut(.pageDown,  modifiers: [])
              DummyView(action: { infoDown (proxy: scrollViewProxy) }).keyboardShortcut(.end,       modifiers: [])

              DummyView(action: { infoUp (proxy: scrollViewProxy) }).keyboardShortcut(.upArrow, modifiers: [])
              DummyView(action: { infoUp (proxy: scrollViewProxy) }).keyboardShortcut(.pageUp,  modifiers: [])
              DummyView(action: { infoUp (proxy: scrollViewProxy) }).keyboardShortcut(.home,    modifiers: [])
            }.frame(maxWidth: 0, maxHeight: 0)
          }

          VStack(alignment: .leading, spacing: 10) {
            LyricsTrackInfo(lyricsInfo: playerSelection.lyricsInfo, highlighted: (playerSelection.lyricsInfoPos == 0))
            .onHover(perform: { hovering in
              if(hovering) {
                if(playerSelection.lyricsInfoPopover == 0) { return }
                model.lyricsDelayAction() { playerSelection.lyricsInfoPopover = 0 }
              } else {
                model.delayCancel();
                playerSelection.lyricsInfoPopover = -1 }
              })
            .popover(isPresented: $lyricsInfoPopover) { Text(playerSelection.trackInfo).font(.headline).padding() }
            .sync($playerSelection.lyricsInfoPopover, with: $lyricsInfoPopover, for: 0)

            LyricsNotes(playingNotes: playerSelection.playingNotes, playingLyrics: playerSelection.playingLyrics, highlighted: (playerSelection.lyricsInfoPos == 1))
            .onHover(perform: { hovering in
              if(hovering) {
                if(playerSelection.lyricsInfoPopover == 1) { return }
                model.lyricsDelayAction() { playerSelection.lyricsInfoPopover = 1 }
              } else {
                model.delayCancel();
                playerSelection.lyricsInfoPopover = -1 }
              })
            .popover(isPresented: $lyricsNotesPopover) {
              Text(playerSelection.playingNotes.isEmpty ? "No notes for " + playerSelection.lyricsInfo.track
                                                        : "Notes for "    + playerSelection.lyricsInfo.track + ":\n\n" + playerSelection.playingNotes)
              .font(.headline).padding() }
            .sync($playerSelection.lyricsInfoPopover, with: $lyricsNotesPopover, for: 1)
          }.frame(minWidth: 150, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }
  }

  func infoDown(proxy: ScrollViewProxy) {
    let listLimit = 1
    if(playerSelection.lyricsInfoPos >= listLimit) { return }

    playerSelection.lyricsInfoPos += 1
    proxy.scrollTo(playerSelection.lyricsInfoPos)
  }

  func infoUp(proxy: ScrollViewProxy) {
    if(playerSelection.lyricsInfoPos <= 0) { return }

    playerSelection.lyricsInfoPos -= 1;
    proxy.scrollTo(playerSelection.lyricsInfoPos)
  }
}
