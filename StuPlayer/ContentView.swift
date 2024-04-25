//
//  ContentView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import SwiftUI
import Carbon.HIToolbox
import SFBAudioEngine

struct DummyView : View {
  init(action: @escaping () -> Void) { self.onPressed = action }

  var onPressed: () -> Void
  var body: some View {
    Button("", action: onPressed).allowsHitTesting(/*@START_MENU_TOKEN@*/false/*@END_MENU_TOKEN@*/).opacity(0).frame(maxWidth: 0, maxHeight: 0)
  }
}

struct ContentView: View {
  let model: PlayerDataModel
  @ObservedObject var playerAlert: PlayerAlert
  @ObservedObject var playerSelection: PlayerSelection

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Button(action: model.setRootFolder) {
          Text("Root folder: ").padding(.horizontal, 10).padding(.vertical, 2)
        }

        Text(playerSelection.rootPath).padding(.horizontal, 10).padding(.vertical, 2)

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

      Spacer().frame(height: 15)

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
          Button(action: model.clearArtist) {
            Text("Artist: ").padding(.horizontal, 10).padding(.vertical, 2)
          }

          Text(playerSelection.artist).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        } else if(playerSelection.filterMode != .Artist) {
          Button(action: model.clearArtist) {
            Text("Artist: ").padding(.horizontal, 10).padding(.vertical, 2)
          }.disabled(true)

          Text(playerSelection.artist).foregroundStyle(.gray).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        }

        Spacer().frame(width: 20)

        if(playerSelection.filterString.isEmpty || (playerSelection.filterMode != .Track)) {
          Button(action: model.clearAlbum) {
            Text("Album: ").padding(.horizontal, 10).padding(.vertical, 2)
          }

          Text(playerSelection.album).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        } else {
          Button(action: model.clearAlbum) {
            Text("Album: ").padding(.horizontal, 10).padding(.vertical, 2)
          }.disabled(true)

          Text(playerSelection.album).foregroundStyle(.gray).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        }

        Spacer().frame(width: 20)
      }

      Spacer().frame(height: 30)

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

        Spacer().frame(width: 35)

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
      }

      Spacer().frame(height: 10)

      ScrollViewReader { scrollViewProxy in
        ScrollView {
          VStack(alignment: .leading) {
            ForEach(Array(playerSelection.list.enumerated()), id: \.offset) { itemIndex, itemText in
              if(itemIndex == playerSelection.scrollPos) {
                Text(itemText).fontWeight(.semibold).frame(minWidth: 150, alignment: .leading).padding(.horizontal, 4)
                  .background(RoundedRectangle(cornerRadius: 5).foregroundColor(.blue.opacity(0.3)))
                  .onTapGesture { model.itemSelected(itemIndex: itemIndex, itemText: itemText) }
              } else {
                Text(itemText).frame(minWidth: 150, maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                  .onTapGesture { model.itemSelected(itemIndex: itemIndex, itemText: itemText) }
              }
            }
          }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

          HStack() {
            DummyView(action: { scrollDown(proxy: scrollViewProxy) }).keyboardShortcut(.downArrow, modifiers: [])
            DummyView(action: { scrollUp  (proxy: scrollViewProxy) }).keyboardShortcut(.upArrow,   modifiers: [])
          }.frame(maxWidth: 0, maxHeight: 0)
        }
        .frame(minWidth: 150, maxWidth: .infinity)
      }

      Spacer().frame(height: 30)

      HStack {
        if(playerSelection.playPosition > 0) {
          Text(String(format: "Playing: %d/%d", playerSelection.playPosition, playerSelection.playTotal)).frame(width: 120, alignment:.leading)
          Slider(value: $playerSelection.trackPosition, in: 0...1, onEditingChanged: { startFinish in
            if(startFinish) { return; }
            model.seekTo(newPosition: playerSelection.trackPosition)
          }).frame(width:300, alignment:.leading).disabled(!playerSelection.seekEnabled)
          Spacer().frame(width: 15)
          Text(playerSelection.trackPosString).monospacedDigit().frame(width:42, alignment: .trailing)
        } else {
          Text("Playing: ").frame(alignment: .leading)
          Slider(value: $playerSelection.trackPosition, in: 0...1).frame(width:300, alignment:.leading).hidden()
          Spacer().frame(width: 15).hidden()
          Text(playerSelection.trackPosString).monospacedDigit().frame(width:42, alignment: .trailing).hidden()
        }
      }

      HStack {
        Text(String(format: "Playlist: %@", playerSelection.playlist)).frame(minWidth: 120, alignment: .leading).padding(.vertical, 2)

        Spacer().frame(width: 20)

        if playerSelection.trackNum > 0 {
          Text(String(format: "Track %d/%d: %@", playerSelection.trackNum, playerSelection.numTracks, playerSelection.track)).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        } else {
          Text("Track: ").frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        }
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

        // Finally, the selection and filter
        playerSelection.scrollPos = -1
        playerSelection.clearFilter(resetMode: false)
        return nil

      case kVK_Return:
        if(playerSelection.scrollPos < 0) { return nil }

        model.itemSelected(itemIndex: playerSelection.scrollPos, itemText: playerSelection.list[playerSelection.scrollPos])
        return nil

      case kVK_ANSI_KeypadEnter:
        model.playAll()
        return nil

      default:
        break
      }

      guard let specialKey = aEvent.specialKey else { return aEvent }
      switch(specialKey) {
      case .tab:
        model.toggleFilter()
        return nil

      default:
        break
      }

      return aEvent
    }
  }

  func scrollDown(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.list.count - 1
    if(playerSelection.scrollPos >= listLimit) { return }

    playerSelection.scrollPos += 1;
    proxy.scrollTo(playerSelection.scrollPos)
  }

  func scrollUp(proxy: ScrollViewProxy) {
    if(playerSelection.scrollPos <= 0) { return }

    playerSelection.scrollPos -= 1;
    proxy.scrollTo(playerSelection.scrollPos)
  }
}
