//
//  ContentView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import SwiftUI
import Carbon.HIToolbox
import SFBAudioEngine

enum ScrollViewFocus { case BrowserScrollView, PlayingScrollView }

struct DummyView : View {
  init(action: @escaping () -> Void) { self.onPressed = action }

  var onPressed: () -> Void
  var body: some View {
    Button("", action: onPressed).allowsHitTesting(/*@START_MENU_TOKEN@*/false/*@END_MENU_TOKEN@*/).opacity(0).frame(maxWidth: 0, maxHeight: 0)
  }
}

struct BrowserItemView : View {
  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection

  let itemText: String
  let itemIndex: Int

  let highlighted: Bool

  init(model: PlayerDataModel, playerSelection: PlayerSelection, itemText: String, itemIndex: Int) {
    self.model = model
    self.playerSelection = playerSelection

    self.itemText     = itemText
    self.itemIndex    = itemIndex

    highlighted = (itemIndex == playerSelection.browserScrollPos)

  }

  var body: some View {
    Text(itemText).fontWeight(highlighted ? .semibold : nil).frame(minWidth: 150, alignment: .leading).padding(.horizontal, 4)
      .background(highlighted ? RoundedRectangle(cornerRadius: 5).foregroundColor(.blue.opacity(0.3)) : nil)
      .onTapGesture { model.itemClicked(itemIndex: itemIndex, itemText: itemText) }
  }
}

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
      Text("         ")
      Text(itemText).fontWeight((highlighted || playerItem) ? .semibold : nil).padding(.horizontal, 4)
        .background(highlighted   ? RoundedRectangle(cornerRadius: 5).foregroundColor(.blue.opacity(0.3)) :
                    currentSearch ? RoundedRectangle(cornerRadius: 5).foregroundColor(.orange.opacity(1.0)) :
                    itemSearched  ? RoundedRectangle(cornerRadius: 5).foregroundColor(.yellow.opacity(0.5)) : nil)
    }
    .background(playerItem ? Image(itemPlaying ? "Playing" : "Paused").resizable().aspectRatio(contentMode: .fit) : nil, alignment: .leading)
    .frame(minWidth: 150, alignment: .leading).padding(.horizontal, 4)
    .onTapGesture { playerItem ? model.togglePause() : model.playingItemClicked(itemIndex) }
    .onHover(perform: { hovering in
      if(hovering) {
        model.delayAction(itemIndex) { playingPopover = true }
      } else { model.delayCancel(); playingPopover = false } })
    .popover(isPresented: $playingPopover) { Text("Hi!") }
  }
}

struct ContentView: View {
  @Environment(\.controlActiveState) var controlActiveState

  let model: PlayerDataModel
  @ObservedObject var playerAlert: PlayerAlert
  @ObservedObject var playerSelection: PlayerSelection

  @State private var textHeight       = CGFloat(0.0)
  @State private var scrollViewHeight = CGFloat(0.0)
  @FocusState private var scrollViewFocus: ScrollViewFocus?

  @State private var playlistPopover  = false
  @State private var trackPopover     = false
  @State private var countdownPopover = false

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Button(action: model.setRootFolder) {
          Text("Root folder: ").padding(.horizontal, 10).background() { GeometryReader { proxy in Color.clear.onAppear { textHeight = proxy.size.height } } }.padding(.vertical, 2)
        }

        Text((playerSelection.rootPath == "/") ? "Not set" : playerSelection.rootPath).padding(.horizontal, 10).padding(.vertical, 2)

        Button(action: model.scanFolders) {
          Text("Rescan").padding(.horizontal, 10).padding(.vertical, 2)
        }

#if PLAYBACK_TEST
        Spacer().frame(width: 20)

        Button(action: model.testPlay) {
          Text("Test").padding(.horizontal, 10).padding(.vertical, 2)
        }
#endif
      }

      Spacer().frame(height: 30)

      HStack {
        Picker("Type:", selection: $playerSelection.type) {
          ForEach(playerSelection.typeList, id: \.self) {
            Text($0)
          }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 125, maxWidth: 180)

        Spacer().frame(width: 20)

        if(playerSelection.filterString.isEmpty || (playerSelection.filterMode == .Artist)) {
          Button(action: model.artistClicked) {
            Text("Artist: ").padding(.horizontal, 10).padding(.vertical, 2)
          }

          Text(playerSelection.artist).frame(minWidth: 50)
        } else if(playerSelection.filterMode != .Artist) {
          Button(action: { }) {
            Text("Artist: ").padding(.horizontal, 10).padding(.vertical, 2)
          }.disabled(true)

          Text(playerSelection.artist).foregroundStyle(.gray).frame(minWidth: 50)
        }

        Spacer().frame(width: 20)

        if(playerSelection.filterString.isEmpty || (playerSelection.filterMode != .Track)) {
          Button(action: model.albumClicked) {
            Text("Album: ").padding(.horizontal, 10).padding(.vertical, 2)
          }

          Text(playerSelection.album).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        } else {
          Button(action: { }) {
            Text("Album: ").padding(.horizontal, 10).padding(.vertical, 2)
          }.disabled(true)

          Text(playerSelection.album).foregroundStyle(.gray).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        }

        Spacer().frame(width: 20)
      }

      Spacer().frame(height: 20)

      HStack {
        HStack {
          Button(action: model.toggleFilter) {
            switch(playerSelection.filterMode) {
            case FilterMode.Artist:
              Text("Artist").frame(width: 40).padding(.horizontal, 10).padding(.vertical, 2)

            case FilterMode.Album:
              Text("Album").frame(width: 40).padding(.horizontal, 10).padding(.vertical, 2)

            case FilterMode.Track:
              Text("Track").frame(width: 40).padding(.horizontal, 10).padding(.vertical, 2)
            }
          }

          Spacer().frame(width: 10)

          TextField("Filter", text: $playerSelection.filterString).frame(width: 120)
            .autocorrectionDisabled(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
            .textSelection(.disabled)
            .textFieldStyle(.roundedBorder)
            .focused($scrollViewFocus, equals: .BrowserScrollView)

          Button(action: { playerSelection.clearFilter(resetMode: false) }) {
            Text("✖")
          }
        }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

        HStack {
          Text("Track:").padding(.horizontal, 10).padding(.vertical, 2).foregroundStyle((playerSelection.playPosition > 0) ? .black : .gray)

          Spacer().frame(width: 10)

          TextField("Search", text: $playerSelection.searchString).frame(width: 120)
            .autocorrectionDisabled(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
            .textSelection(.disabled)
            .textFieldStyle(.roundedBorder)
            .focused($scrollViewFocus, equals: .PlayingScrollView)

          Button(action: { _ = playerSelection.searchPrev() }) {
            Text("▲")
          }.disabled(!playerSelection.searchUpAllowed)

          Button(action: { _ = playerSelection.searchNext() }) {
            Text("▼")
          }.disabled(!playerSelection.searchDownAllowed)

          Button(action: playerSelection.clearSearch) {
            Text("✖")
          }
        }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading).disabled(playerSelection.playPosition == 0)
      }

      Spacer().frame(height: 20)

      HStack {
        Button(action: model.playAll) {
          Text("Play all").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)
        }

        Spacer().frame(width: 40)

        Button(action: model.toggleShuffle) {
          switch(playerSelection.shuffleTracks) {
          case false:
            Text("Order: from m3u").frame(width: 110).padding(.horizontal, 10).padding(.vertical, 2)
          case true:
            Text("Order: random").frame(width: 110).padding(.horizontal, 10).padding(.vertical, 2)
          }
        }

        Spacer().frame(width: 20)

        Button(action: model.toggleRepeat) {
          switch(playerSelection.repeatTracks) {
          case RepeatState.None:
            Text("Repeat: none").frame(width: 90).padding(.horizontal, 10).padding(.vertical, 2)

          case RepeatState.Track:
            Text("Repeat: track").frame(width: 90).padding(.horizontal, 10).padding(.vertical, 2)

          case RepeatState.All:
            Text("Repeat: all").frame(width: 90).padding(.horizontal, 10).padding(.vertical, 2)
          }
        }
      }

      Spacer().frame(height: 20)

      HStack {
        ScrollViewReader { scrollViewProxy in
          let hasFocus = (scrollViewFocus == .BrowserScrollView)

          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              if(hasFocus) {
                HStack() {
                  DummyView(action: { browserDown     (proxy: scrollViewProxy) }).keyboardShortcut(.downArrow, modifiers: [])
                  DummyView(action: { browserPageDown (proxy: scrollViewProxy) }).keyboardShortcut(.pageDown,  modifiers: [])
                  DummyView(action: { browserEnd      (proxy: scrollViewProxy) }).keyboardShortcut(.end,       modifiers: [])

                  DummyView(action: { browserUp      (proxy: scrollViewProxy) }).keyboardShortcut(.upArrow, modifiers: [])
                  DummyView(action: { browserPageUp  (proxy: scrollViewProxy) }).keyboardShortcut(.pageUp,  modifiers: [])
                  DummyView(action: { browserHome    (proxy: scrollViewProxy) }).keyboardShortcut(.home,    modifiers: [])
                }.frame(maxWidth: 0, maxHeight: 0)
              }

              LazyVStack(alignment: .leading) {
                ForEach(Array(playerSelection.list.enumerated()), id: \.offset) { itemIndex, itemText in
                  BrowserItemView(model: model, playerSelection: playerSelection, itemText: itemText, itemIndex: itemIndex)
                }
              }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            }
          }
          .frame(minWidth: 150, maxWidth: .infinity).padding(7).background() {
            GeometryReader { proxy in Color.clear.onAppear { scrollViewHeight = proxy.size.height }.onChange(of: proxy.size.height) { newValue in scrollViewHeight = newValue } }
          }.overlay(
            RoundedRectangle(cornerRadius: 8).stroke((hasFocus && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))
        }

        if(playerSelection.playPosition > 0) {
          ScrollViewReader { scrollViewProxy in
            let hasFocus = (scrollViewFocus == .PlayingScrollView)

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

                    DummyView(action: { playingSelected(proxy: scrollViewProxy) }).keyboardShortcut(.clear, modifiers: [])
                  }.frame(maxWidth: 0, maxHeight: 0)
                }

                LazyVStack(alignment: .leading, spacing: 0) {
                  ForEach(Array(playerSelection.playingTracks.enumerated()), id: \.offset) { itemIndex, item in
                    PlayingItemView(model: model, playerSelection: playerSelection, itemText: item.name, itemSearched: item.searched, itemIndex: itemIndex)
                  }
                }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
              }
            }.frame(minWidth: 150, maxWidth: .infinity).padding(7).overlay(
              RoundedRectangle(cornerRadius: 8).stroke((hasFocus && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))
            .onChange(of: playerSelection.playPosition) { newPos in
              if(newPos == 0) { scrollViewFocus = .BrowserScrollView; return }

              playerSelection.prevSel = -1
              playerSelection.currSel = -1
              scrollViewProxy.scrollTo(playerSelection.playPosition, anchor: .center)
            }
            .onChange(of: playerSelection.playingScrollTo) { _ in
              if(playerSelection.playingScrollTo == -1) { return }

              scrollViewProxy.scrollTo(playerSelection.playingScrollTo, anchor: .center)
              playerSelection.prevSel = playerSelection.playingScrollTo
              playerSelection.currSel = playerSelection.playingScrollTo
              playerSelection.playingScrollTo = -1
            }
          }
        } else {
          Spacer().frame(minWidth: 150, maxWidth: .infinity).padding(7)
        }
      }

      Spacer().frame(height: 30)

      HStack {
        if(playerSelection.playPosition > 0) {
          Text(String(format: "Playing: %d/%d", playerSelection.playPosition, playerSelection.playTotal)).frame(width: 142, alignment:.leading)
          Slider(value: $playerSelection.trackPos, in: 0...1, onEditingChanged: { startFinish in
            if(startFinish) { return; }
            model.seekTo(newPosition: playerSelection.trackPos)
          }).frame(width:300, alignment:.leading).disabled(!playerSelection.seekEnabled)
          Spacer().frame(width: 15)
          Text(playerSelection.trackCountdown ? playerSelection.trackLeftStr : playerSelection.trackPosStr).monospacedDigit().frame(width: 42, alignment: .trailing).padding(.horizontal, 6)
            .onTapGesture { playerSelection.trackCountdown.toggle() }
            .onHover(perform: { hovering in
              if(hovering) {
                model.delayAction() { countdownPopover = true }
              } else { model.delayCancel(); countdownPopover = false } })
            .popover(isPresented: $countdownPopover) { Text("\(playerSelection.countdownInfo)").font(.headline).monospacedDigit().padding() }
        } else {
          Text("Playing: ").frame(alignment: .leading)
          Slider(value: $playerSelection.trackPos, in: 0...1).frame(width: 300, alignment: .leading).hidden()
          Spacer().frame(width: 15).hidden()
          Text(playerSelection.trackPosStr).monospacedDigit().frame(width: 42, alignment: .trailing).hidden()
        }
      }

      HStack {
        Text(String(format: "Playlist: %@", playerSelection.playlist)).frame(minWidth: 120, alignment: .leading).padding(.vertical, 2)
          .onHover(perform: { hovering in
            if(hovering && !playerSelection.playlist.isEmpty) {
              model.delayAction() { playlistPopover = true }
            } else { model.delayCancel(); playlistPopover = false } })
          .popover(isPresented: $playlistPopover) { Text("\(playerSelection.playlistInfo)").font(.headline).padding() }

        Spacer().frame(width: 20)

        if playerSelection.trackNum > 0 {
          Text(String(format: "Track %d/%d: %@", playerSelection.trackNum, playerSelection.numTracks, playerSelection.track)).frame(minWidth: 120, alignment: .leading)
            .onHover(perform: { hovering in
              if(hovering) {
                model.delayAction() { trackPopover = true }
              } else { model.delayCancel(); trackPopover = false } })
            .popover(isPresented: $trackPopover) { Text("\(playerSelection.trackInfo)").font(.headline).padding() }
        } else {
          Text("Track: ").frame(minWidth: 120, alignment: .leading)
        }

        Spacer()
      }

      Spacer().frame(height: 15)

      HStack {
        Button(action: model.togglePause) {
          switch(playerSelection.playbackState) {
          case .stopped:
            Text("Pause").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)

          case .playing:
            Text("Pause").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)

          case .paused:
            Text("Resume").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)

          @unknown default:
            Text("??????").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)
          }
        }.disabled(playerSelection.playbackState == .stopped)

        Spacer().frame(width: 20)

        Button(action: model.stopAll) {
          Text(" Stop ").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)
        }.disabled(playerSelection.playbackState == .stopped)

        Spacer().frame(width: 40)

        Button(action: model.playPreviousTrack) {
          Text("Previous").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
        }.disabled((playerSelection.playbackState == .stopped) || (playerSelection.playPosition == 1))

        Spacer().frame(width: 20)

        Button(action: model.playNextTrack) {
          Text("Next").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
        }.disabled(playerSelection.playbackState == .stopped)

        Spacer().frame(width: 20)

        Button(action: model.restartAll) {
          Text("Restart").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
        }.disabled(playerSelection.playbackState == .stopped)

        if(playerSelection.shuffleTracks) {
          Spacer().frame(width: 20)

          Button(action: model.reshuffleAll) {
            Text("Reshuffle").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
          }.disabled(playerSelection.playbackState == .stopped)
        }
      }

      Spacer().frame(height: 10)
    }
    .padding()
    .frame(minWidth:  200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
    .alert(playerAlert.alertMessage, isPresented: $playerAlert.alertTriggered) { }
    .onAppear { handleKeyEvents() }
  }

  func handleKeyEvents() {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { aEvent -> NSEvent? in
      let keyCode = Int(aEvent.keyCode)
      switch(keyCode) {
      case kVK_Escape:
        if(scrollViewFocus == .BrowserScrollView) {
          // Clear album first
          if((playerSelection.filterString.isEmpty || (playerSelection.filterMode != .Track)) && !playerSelection.album.isEmpty) {
            model.clearAlbum()
            return nil
          }

          // Then artist
          if((playerSelection.filterString.isEmpty || (playerSelection.filterMode == .Artist)) && !playerSelection.artist.isEmpty) {
            model.clearArtist()
            return nil
          }

          // Then filter
          if(!playerSelection.filterString.isEmpty) {
            playerSelection.clearFilter(resetMode: false)
            return nil
          }

          // Finally, clear the selection
          playerSelection.browserScrollPos = -1
          return nil
        } else { // (scrollViewFocus == .PlayingScrollView)
          // Clear search first
          if(!playerSelection.searchString.isEmpty) {
            playerSelection.clearSearch()
            return nil
          }

          // Finally, clear the selection
          playerSelection.playingScrollPos = -1
          return nil
        }

      case kVK_Return:
        if((scrollViewFocus == .BrowserScrollView)) {
          let itemIndex = playerSelection.browserScrollPos
          if((itemIndex < 0) && (playerSelection.list.count > 0)) {
            playerSelection.browserScrollPos = 0
            return nil
          } else if(playerSelection.browserScrollPos < 0) { return nil }

          model.itemSelected(itemIndex: itemIndex, itemText: playerSelection.list[itemIndex])
        } else { // (scrollViewFocus == .PlayingScrollView)
          let itemIndex = playerSelection.playingScrollPos
          if(itemIndex < 0) {
            playerSelection.playingScrollPos = 0
            playerSelection.searchIndex      = 0
            return nil
          }

          let playerItem = (itemIndex == (playerSelection.playPosition-1))
          playerItem ? model.togglePause() : model.playingItemSelected(itemIndex)
        }
        return nil

      case kVK_F1:
        model.playAll()
        return nil

      case kVK_F2:
        model.toggleShuffle()
        return nil

      case kVK_F3:
        model.toggleRepeat()
        return nil

      case kVK_F4:
        model.toggleFilter()
        return nil

      case kVK_ANSI_KeypadEnter:
        model.togglePause()
        return nil

      default:
        break
      }

      guard let specialKey = aEvent.specialKey else { return aEvent }
      switch(specialKey) {
      case .tab:
        let browserFocus = (scrollViewFocus == .BrowserScrollView)
        if(browserFocus && (playerSelection.playPosition > 0)) { scrollViewFocus = .PlayingScrollView  }
        else if(!browserFocus) { scrollViewFocus = .BrowserScrollView }
        return nil

      default:
        break
      }

      return aEvent
    }
  }

  func browserDown(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.list.count - 1
    if(playerSelection.browserScrollPos >= listLimit) { return }

    playerSelection.browserScrollPos += 1;
    proxy.scrollTo(playerSelection.browserScrollPos)
  }

  func browserPageDown(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.list.count - 1
    if(playerSelection.browserScrollPos >= listLimit) { return }

    let linesToScroll = Int(0.5 + scrollViewHeight / textHeight)
    var newScrollPos  = ((playerSelection.browserScrollPos < 0) ? 0 : playerSelection.browserScrollPos) + linesToScroll
    if(newScrollPos > listLimit) { newScrollPos = listLimit }

    playerSelection.browserScrollPos = newScrollPos;
    proxy.scrollTo(playerSelection.browserScrollPos)
  }

  func browserEnd(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.list.count - 1
    if(playerSelection.browserScrollPos >= listLimit) { return }

    playerSelection.browserScrollPos = listLimit;
    proxy.scrollTo(playerSelection.browserScrollPos)
  }

  func browserUp(proxy: ScrollViewProxy) {
    if(playerSelection.browserScrollPos <= 0) { return }

    playerSelection.browserScrollPos -= 1;
    proxy.scrollTo(playerSelection.browserScrollPos)
  }

  func browserPageUp(proxy: ScrollViewProxy) {
    if(playerSelection.browserScrollPos <= 0) { return }

    let linesToScroll = Int(0.5 + scrollViewHeight / textHeight)
    var newScrollPos = playerSelection.browserScrollPos - linesToScroll
    if(newScrollPos < 0) { newScrollPos = 0 }

    playerSelection.browserScrollPos = newScrollPos;
    proxy.scrollTo(playerSelection.browserScrollPos)
  }

  func browserHome(proxy: ScrollViewProxy) {
    if(playerSelection.browserScrollPos > 0) { playerSelection.browserScrollPos = 0 }
    proxy.scrollTo(0)
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

    let linesToScroll = Int(0.5 + scrollViewHeight / textHeight)
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
    
    let linesToScroll = Int(0.5 + scrollViewHeight / textHeight)
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

  func playingSelected(proxy: ScrollViewProxy) {
    print("Selected to:")
    print(playerSelection.prevSel)
    print(playerSelection.currSel)
    print("")

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
