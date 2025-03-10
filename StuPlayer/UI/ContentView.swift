//
//  ContentView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import SwiftUI
import StoreKit
import Carbon.HIToolbox
import SFBAudioEngine

struct ContentView: View {
  @Environment(\.controlActiveState) var controlActiveState

  let model: PlayerDataModel
  @ObservedObject var skManager: SKManager
  @ObservedObject var playerAlert: PlayerAlert
  @ObservedObject var playerSelection: PlayerSelection

  @State private var textHeight       = CGFloat(0.0)
  @State private var scrollViewHeight = CGFloat(0.0)
  @FocusState private var scrollViewFocus: ScrollViewFocus?

  @State private var playingPopover   = false
  @State private var playlistPopover  = false
  @State private var trackPopover     = false
  @State private var countdownPopover = false

  @State private var plvProduct: Product? = nil
  @State private var lvProduct: Product? = nil

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

        if(skManager.plViewPurchased) {
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
      }

      Spacer().frame(height: 20)

      HStack {
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
        }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

        if(skManager.lViewPurchased) {
          HStack {
            Spacer().frame(width: 10)

            Button(action: model.toggleLyrics) {
              switch(playerSelection.lyricsMode) {
              case LyricsMode.Navigate:
                Text("Lyrics: Seek to position").frame(width: 150).padding(.horizontal, 10).padding(.vertical, 2)

              case LyricsMode.Update:
                Text("Lyrics: Update times").frame(width: 150).padding(.horizontal, 10).padding(.vertical, 2)
              }
            }

            Spacer().frame(width: 20)

            Button(action: model.refreshLyrics) {
              Text("Refresh lyrics").frame(width: 100).padding(.horizontal, 10).padding(.vertical, 2)
            }.disabled(playerSelection.playPosition <= 0)

            Spacer().frame(width: 20)

            Button(action: model.fetchLyrics) {
              Text("Fetch from lyrics.ovh").frame(width: 140).padding(.horizontal, 10).padding(.vertical, 2)
            }.disabled((playerSelection.playPosition <= 0) || !playerSelection.playingLyrics.isEmpty)

            // Dummy text fields to hold focus
            TextField("", text: $playerSelection.dummyString).frame(width: 0)
              .autocorrectionDisabled(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
              .textSelection(.disabled)
              .focused($scrollViewFocus, equals: .LyricsInfoView)
              .opacity(0.0)

            TextField("", text: $playerSelection.dummyString).frame(width: 0)
              .autocorrectionDisabled(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
              .textSelection(.disabled)
              .focused($scrollViewFocus, equals: .LyricsScrollView)
              .opacity(0.0)
          }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        }
      }

      Spacer().frame(height: 20)

      VStack(alignment: .leading, spacing: 0) {
        HStack {
          let browserFocus = (scrollViewFocus == .BrowserScrollView)
          BrowserScrollView(model: model, playerSelection: playerSelection, hasFocus: browserFocus, textHeight: textHeight, viewHeight: scrollViewHeight)
            .frame(minWidth: 172, maxWidth: .infinity, minHeight: 120, maxHeight: .infinity).padding(7)
            .background() { GeometryReader { proxy in Color.clear.onAppear { scrollViewHeight = proxy.size.height }.onChange(of: proxy.size.height) { newValue in scrollViewHeight = newValue } } }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke((browserFocus && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))

          if((playerSelection.playPosition <= 0) || !skManager.plViewPurchased) {
            let plViewDismissed = playerSelection.dismissedViews.plView || !skManager.canMakePayments
            if(!plViewDismissed && !skManager.plViewPurchased) {
              VStack() {
                VStack() {
                  Text("Playlist View").font(.headline)
                  Spacer().frame(height: 5)

                  Text("The playlist view displays a list of the currently queued tracks. You can use it to see the tracks that have been played and which tracks will be playing next. You can also use it to select another track from the playlist (without changing the playlist).")
                }.padding(.horizontal, 12)

                Spacer().frame(height: 25)

                HStack(spacing: 30) {
                  Button(action: purchasePLV) { (plvProduct == nil) ? Text("Purchase") : Text("Purchase " + plvProduct!.displayPrice) }
                    .disabled(plvProduct == nil)
                    .onChange(of: skManager.spProducts) { _ in
                      Task { plvProduct = skManager.productFromID(plvProductID) }
                    }

                  Button(action: skManager.openInAppHelp)  { Text("More information") }
                  Button(action: model.dismissPLVPurchase) { Text("Dismiss") }
                }
              }.frame(minWidth: 172, maxWidth: .infinity, minHeight: scrollViewHeight).padding(.horizontal, 7)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray, lineWidth: 5).opacity(0.6))
            } else {
              Spacer().frame(minWidth: 172, maxWidth: .infinity).padding(7)
            }
          }

          if((playerSelection.playPosition > 0) && skManager.plViewPurchased) {
            let playingFocus = (scrollViewFocus == .PlayingScrollView)
            PlayingScrollView(model: model, playerSelection: playerSelection, hasFocus: playingFocus, textHeight: textHeight, viewHeight: scrollViewHeight)
              .frame(minWidth: 172, maxWidth: .infinity, minHeight: 120).padding(7)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke((playingFocus && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))
          }
        }

        Spacer().frame(height: 10)

        if((playerSelection.playPosition <= 0) || !skManager.lViewPurchased) {
          let lViewDismissed = playerSelection.dismissedViews.lView || !skManager.canMakePayments
          if(!lViewDismissed && !skManager.lViewPurchased) {
            VStack() {
              VStack() {
                Text("Lyrics View").font(.headline)
                Spacer().frame(height: 5)

                Text("The lyrics view displays information about the current track and the lyrics for the track (if available). Lyrics can be added manually or downloaded from lyrics.ovh. In both cases, timestamps for each line can be added afterwards (although currently this has to be done manually).")
              }.padding(.horizontal, 112)

              Spacer().frame(height: 25)

              HStack(spacing: 30) {
                Button(action: purchaseLV) { (lvProduct == nil) ? Text("Purchase") : Text("Purchase " + lvProduct!.displayPrice) }
                  .disabled(lvProduct == nil)
                  .onChange(of: skManager.spProducts) { _ in
                    Task { lvProduct = skManager.productFromID(lvProductID) }
                  }

                Button(action: skManager.openInAppHelp) { Text("More information") }
                Button(action: model.dismissLVPurchase) { Text("Dismiss") }
              }
            }.frame(minWidth: 344, maxWidth: .infinity, minHeight: 130).padding(.horizontal, 7)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray, lineWidth: 5).opacity(0.6))
          }
        }

        if((playerSelection.playPosition > 0) && skManager.lViewPurchased) {
          HStack {
            let lyricsInfoFocus = (scrollViewFocus == .LyricsInfoView)
            LyricsInfoView(model: model, playerSelection: playerSelection, hasFocus: lyricsInfoFocus, textHeight: textHeight, viewHeight: scrollViewHeight)
              .frame(minWidth: 172, maxWidth: .infinity, minHeight: 130).padding(7)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke((lyricsInfoFocus && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))

            if((playerSelection.playPosition > 0) && skManager.lViewPurchased) {
              let lyricsFocus = (scrollViewFocus == .LyricsScrollView)
              LyricsScrollView(model: model, playerSelection: playerSelection, hasFocus: lyricsFocus, textHeight: textHeight, viewHeight: scrollViewHeight)
                .frame(minWidth: 172, maxWidth: .infinity, minHeight: 130).padding(7)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke((lyricsFocus && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))
            }
          }
        }

        Spacer().frame(height: 30)

        VStack(alignment: .leading) {
          HStack {
            if(playerSelection.playPosition > 0) {
              Text(String(format: "Playing: %d/%d", playerSelection.playPosition, playerSelection.playTotal)).frame(width: 142, alignment:.leading)
                .onHover(perform: { hovering in
                  if(hovering) {
                    model.delayAction() { playingPopover = true }
                  } else { model.delayCancel(); playingPopover = false } })
                .popover(isPresented: $playingPopover) { Text("\(playerSelection.playingInfo)").font(.headline).padding() }

              Slider(value: $playerSelection.trackPos, in: 0...1, onEditingChanged: { startFinish in
                if(startFinish) { return; }
                model.seekTo(newPosition: playerSelection.trackPos)
              }).frame(width:300, alignment:.leading).disabled(!playerSelection.seekEnabled).focused($scrollViewFocus, equals: .CurrentPlayingView)

              Spacer().frame(width: 15)

              Text(playerSelection.trackCountdown ? playerSelection.trackLeftStr : playerSelection.trackPosStr).monospacedDigit().frame(width: 42, alignment: .trailing).padding(.horizontal, 6)
                .onTapGesture { model.toggleTrackCountdown() }
                .onHover(perform: { hovering in
                  if(hovering) {
                    model.delayAction() { countdownPopover = true }
                  } else { model.delayCancel(); countdownPopover = false } })
                .popover(isPresented: $countdownPopover) { Text("\(playerSelection.countdownInfo)").font(.headline).monospacedDigit().padding() }
            } else {
              Text("Playing: ").frame(alignment: .leading)

              // Needed to keep the height of the HStack the same
              Slider(value: $playerSelection.trackPos, in: 0...1).frame(width: 300, alignment: .leading).hidden()
              Spacer().frame(width: 15).hidden()
              Text(playerSelection.trackPosStr).monospacedDigit().frame(width: 42, alignment: .trailing).hidden()
            }
          }

          HStack {
            Text(String(format: "Album playlist: %@", playerSelection.playlist)).frame(minWidth: 120, alignment: .leading).padding(.vertical, 2)
              .onHover(perform: { hovering in
                if(hovering && !playerSelection.playlist.isEmpty) {
                  model.delayAction() { playlistPopover = true }
                } else { model.delayCancel(); playlistPopover = false } })
              .popover(isPresented: $playlistPopover) { Text("\(playerSelection.playlistInfo)").font(.headline).padding() }

            Spacer().frame(width: 20)

            if playerSelection.trackNum > 0 {
              Text(String(format: "Track %d/%d: %@", playerSelection.trackNum, playerSelection.numTracks, playerSelection.fileName)).frame(minWidth: 120, alignment: .leading)
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
        }.padding(10).background(
          RoundedRectangle(cornerRadius: 8).stroke(((scrollViewFocus == .CurrentPlayingView) && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))

        Spacer().frame(height: 10)
      }
    }
    .padding()
    .frame(minWidth:  200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      scrollViewFocus = .BrowserScrollView
      handleKeyEvents()
    }
    .alert(playerAlert.alertMessage, isPresented: $playerAlert.alertTriggered) { }
    .alert("Thank you for purchasing a StuPlayer component! If you change your mind, you can request a refund from the Purchases menu.", isPresented: $skManager.purchaseMade) { }
  }

  func purchasePLV() {
    let product = skManager.productFromID(plvProductID)
    guard let product else { print("Error product is nil"); return }

    Task {
      let displayName = product.displayName

      do {
        let transaction = try await skManager.purchaseProduct(product)
        if(transaction == nil) { print("Purchase of " + displayName + ": no result (transaction cancelled?)"); return }

        print(displayName + " purchased: " + (transaction?.debugDescription ?? "No debug info"))
      } catch {
        print("Error making purchase of " + displayName + ": " + error.localizedDescription)
        return
      }
    }
  }

  func purchaseLV() {
    let product = skManager.productFromID(lvProductID)
    guard let product else { print("Error product is nil"); return }

    Task {
      let displayName = product.displayName

      do {
        let transaction = try await skManager.purchaseProduct(product)
        if(transaction == nil) { print("Purchase of " + displayName + ": no result (transaction cancelled?)"); return }

        print(displayName + " purchased: " + (transaction?.debugDescription ?? "No debug info"))
      } catch {
        print("Error making purchase of " + displayName + ": " + error.localizedDescription)
        return
      }
    }
  }

  func handleKeyEvents() {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { aEvent -> NSEvent? in
      let keyCode = Int(aEvent.keyCode)
      switch(keyCode) {
      case kVK_Escape:
        if(scrollViewFocus == .BrowserScrollView) {
          // Clear popup first
          model.delayCancel()
          if(playerSelection.browserPopover != -1) {
            playerSelection.browserPopover = -1
            return nil
          }

          // Clear album next
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
        } else if(scrollViewFocus == .PlayingScrollView) {
          // Clear popup first
          model.delayCancel()
          if(playerSelection.playingPopover != -1) {
            playerSelection.playingPopover = -1
            return nil
          }

          // Clear search next
          if(!playerSelection.searchString.isEmpty) {
            playerSelection.clearSearch()
            return nil
          }

          // Finally, clear the selection
          playerSelection.playingScrollPos = -1
          return nil
        } else if(scrollViewFocus == .LyricsInfoView) {
          // Clear popup first
          model.delayCancel()
          if(playerSelection.lyricsInfoPopover != -1) {
            playerSelection.lyricsInfoPopover = -1
            return nil
          }

          // Clear the selection
          playerSelection.lyricsInfoPos = -1
          return nil
        } else if(scrollViewFocus == .LyricsScrollView) {
          // Clear the selection
          playerSelection.lyricsScrollPos = -1
          return nil
        } else if(scrollViewFocus == .CurrentPlayingView) {
          // Clear popup
          if(!playingPopover && !countdownPopover && !playlistPopover && !trackPopover) { return nil }

          model.delayCancel()
          if(playingPopover)   { playingPopover = false}
          if(countdownPopover) { countdownPopover = false }
          if(playlistPopover)  { playlistPopover = false }
          if(trackPopover)     { trackPopover = false }
          return nil
        }

      case kVK_Return:
        if((scrollViewFocus == .BrowserScrollView)) {
          let itemIndex = playerSelection.browserScrollPos
          if((itemIndex < 0) && (playerSelection.browserItems.count > 0)) {
            playerSelection.browserScrollPos = 0
            return nil
          } else if(playerSelection.browserScrollPos < 0) { return nil }

          model.browserItemSelected(itemIndex: itemIndex, itemText: playerSelection.browserItems[itemIndex])
        } else if(scrollViewFocus == .PlayingScrollView) {
          let itemIndex = playerSelection.playingScrollPos
          if(itemIndex < 0) {
            playerSelection.playingScrollPos = 0
            playerSelection.searchIndex      = 0
            return nil
          }

          model.playingItemSelected(itemIndex)
        } else if(scrollViewFocus == .LyricsInfoView) {
          // No op
        } else if(scrollViewFocus == .LyricsScrollView) {
          let itemIndex = playerSelection.lyricsScrollPos
          if(itemIndex < 0) {
            playerSelection.lyricsScrollPos = 0
            return nil
          }

          model.lyricsItemSelected(itemIndex)
        } else if(scrollViewFocus == .CurrentPlayingView) {
          model.togglePause()
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

      case kVK_F5:
        model.toggleFilter()
        return nil

      case kVK_ANSI_KeypadEnter:
        model.togglePause()
        return nil

      case kVK_ANSI_Grave:
        if((scrollViewFocus == .BrowserScrollView)) {
          model.toggleBrowserPopup()
        } else if(scrollViewFocus == .PlayingScrollView) {
          model.togglePlayingPopup()
        } else if(scrollViewFocus == .LyricsInfoView) {
          model.toggleLyricsInfoPopup()
        } else if(scrollViewFocus == .CurrentPlayingView) {
          trackPopover.toggle()
        }
        return nil

      case kVK_UpArrow:
        if((scrollViewFocus == .CurrentPlayingView)) {
          trackPopover = false
          model.playPreviousTrack()
          return nil
        }

      case kVK_DownArrow:
        if((scrollViewFocus == .CurrentPlayingView)) {
          trackPopover = false
          model.playNextTrack()
          return nil
        }

      default:
        break
      }

      guard let specialKey = aEvent.specialKey else { return aEvent }
      switch(specialKey) {
      case .tab:
        if(skManager.plViewPurchased && skManager.lViewPurchased) {
          let browserFocus = (scrollViewFocus == .BrowserScrollView)
          let playingFocus = (scrollViewFocus == .PlayingScrollView)
          let lyricsFocus  = (scrollViewFocus == .LyricsInfoView)
          let lyricsFocus2  = (scrollViewFocus == .LyricsScrollView)
          if(browserFocus && (playerSelection.playPosition > 0)) { playerSelection.browserPopover = -1; scrollViewFocus = .PlayingScrollView  }
          else if(playingFocus)                                  { playerSelection.playingPopover = -1; scrollViewFocus = .LyricsInfoView }
          else if(lyricsFocus)                                   {                                      scrollViewFocus = .LyricsScrollView }
          else if(lyricsFocus2)                                  {                                      scrollViewFocus = .CurrentPlayingView }
          else if(!browserFocus)                                 { trackPopover = false;                scrollViewFocus = .BrowserScrollView  }
        } else if(skManager.plViewPurchased) {
          let browserFocus = (scrollViewFocus == .BrowserScrollView)
          let playingFocus = (scrollViewFocus == .PlayingScrollView)
          if(browserFocus && (playerSelection.playPosition > 0)) { playerSelection.browserPopover = -1; scrollViewFocus = .PlayingScrollView  }
          else if(playingFocus)                                  { playerSelection.playingPopover = -1; scrollViewFocus = .CurrentPlayingView }
          else if(!browserFocus)                                 { trackPopover = false;                scrollViewFocus = .BrowserScrollView  }
        } else if(skManager.lViewPurchased) {
          let browserFocus = (scrollViewFocus == .BrowserScrollView)
          let lyricsFocus  = (scrollViewFocus == .LyricsInfoView)
          let lyricsFocus2 = (scrollViewFocus == .LyricsScrollView)
          if(browserFocus && (playerSelection.playPosition > 0)) { playerSelection.browserPopover = -1; scrollViewFocus = .LyricsInfoView }
          else if(lyricsFocus)                                   {                                      scrollViewFocus = .LyricsScrollView }
          else if(lyricsFocus2)                                  {                                      scrollViewFocus = .CurrentPlayingView }
          else if(!browserFocus)                                 { trackPopover = false;                scrollViewFocus = .BrowserScrollView  }
        } else {
          let browserFocus = (scrollViewFocus == .BrowserScrollView)
          if(browserFocus && (playerSelection.playPosition > 0)) { playerSelection.browserPopover = -1; scrollViewFocus = .CurrentPlayingView  }
          else if(!browserFocus)                                 { trackPopover = false;                scrollViewFocus = .BrowserScrollView   }
        }

        return nil

      default:
        break
      }

      return aEvent
    }
  }
}
