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

  @State private var textWidth        = CGFloat(0.0)
  @State private var textHeight       = CGFloat(0.0)
  @State private var scrollViewHeight = CGFloat(0.0)
  @FocusState private var viewFocus: ViewFocus?

  @State private var plvProduct: Product? = nil
  @State private var lvProduct: Product?  = nil
  @State private var tvProduct: Product?  = nil

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Button(action: model.setRootFolder) {
          Text("Root folder: ").padding(.horizontal, 10).background() {
            GeometryReader { proxy in Color.clear.onAppear { textWidth = proxy.size.width / 12.0; textHeight = proxy.size.height } } }.padding(.vertical, 2)
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
            .focused($viewFocus, equals: .BrowserScrollView)

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
              .focused($viewFocus, equals: .PlaylistScrollView)

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
              .focused($viewFocus, equals: .LyricsInfoView)
              .opacity(0.0)

            TextField("", text: $playerSelection.dummyString).frame(width: 0)
              .autocorrectionDisabled(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
              .textSelection(.disabled)
              .focused($viewFocus, equals: .LyricsScrollView)
              .opacity(0.0)
          }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        }
      }

      Spacer().frame(height: 20)

      VStack(alignment: .leading, spacing: 0) {
        HStack {
          let browserFocus = (viewFocus == .BrowserScrollView)
          BrowserScrollView(model: model, playerSelection: playerSelection, hasFocus: browserFocus, textHeight: textHeight, viewHeight: scrollViewHeight)
            .frame(minWidth: 172, maxWidth: .infinity, minHeight: 120, maxHeight: .infinity).padding(7)
            .background() { GeometryReader { proxy in Color.clear.onAppear { scrollViewHeight = proxy.size.height }.onChange(of: proxy.size.height) { newValue in scrollViewHeight = newValue } } }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke((browserFocus && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))

          if(!trackPlaying() || !skManager.plViewPurchased) {
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
              }.frame(minWidth: 342, maxWidth: .infinity, minHeight: scrollViewHeight).padding(.horizontal, 7)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray, lineWidth: 5).opacity(0.6))
            } else {
              Spacer().frame(minWidth: 342, maxWidth: .infinity).padding(7)
            }
          }

          if(playlistViewAvailable()) {
            let playingFocus = (viewFocus == .PlaylistScrollView)
            PlaylistScrollView(model: model, playerSelection: playerSelection, hasFocus: playingFocus, textHeight: textHeight, viewHeight: scrollViewHeight)
              .frame(minWidth: 172, maxWidth: .infinity, minHeight: 120).padding(7)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke((playingFocus && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))
          }
        }

        Spacer().frame(height: 20)

        if(!trackPlaying() || !skManager.lViewPurchased) {
          let lViewDismissed = playerSelection.dismissedViews.lView || !skManager.canMakePayments
          if(!lViewDismissed && !skManager.lViewPurchased) {
            VStack() {
              VStack() {
                Text("Lyrics View").font(.headline)
                Spacer().frame(height: 5)

                Text("The lyrics view displays information about the current track and the lyrics for the track (if available). Lyrics can be added manually or downloaded from lyrics.ovh. In both cases, timestamps for each line can be added afterwards (although currently this has to be done manually).")
              }.frame(width: 632)

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
            }.frame(minWidth: 632, maxWidth: .infinity, minHeight: 136).padding(.horizontal, 7)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray, lineWidth: 5).opacity(0.6))
          }
        }

        if(lyricsViewAvailable()) {
          HStack {
            let lyricsInfoFocus = (viewFocus == .LyricsInfoView)
            LyricsInfoView(model: model, playerSelection: playerSelection, hasFocus: lyricsInfoFocus, textHeight: textHeight, viewHeight: scrollViewHeight)
              .frame(minWidth: 172, maxWidth: .infinity, minHeight: 130).padding(7)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke((lyricsInfoFocus && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))

            let lyricsFocus = (viewFocus == .LyricsScrollView)
            LyricsScrollView(model: model, playerSelection: playerSelection, hasFocus: lyricsFocus, textHeight: textHeight, viewHeight: scrollViewHeight)
              .frame(minWidth: 172, maxWidth: .infinity, minHeight: 130).padding(7)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke((lyricsFocus && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))
          }
        }

        Spacer().frame(height: 20)

        HStack {
          CurrentPlayingView(model: model, playerSelection: playerSelection, focusState: $viewFocus, textWidth: textWidth)
            .padding(10).background(RoundedRectangle(cornerRadius: 8).stroke(((viewFocus == .CurrentPlayingView) && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))

          if(!trackPlaying() || !skManager.tViewPurchased) {
            let tViewDismissed = playerSelection.dismissedViews.tView || !skManager.canMakePayments
            if(!tViewDismissed && !skManager.tViewPurchased) {
              VStack() {
                VStack() {
                  Text("Tools View").font(.headline)
                  Spacer().frame(height: 5)

                  Text("The tools view provides tools for adjusting playback. Currently, it is possible to adjust the playback rate and loop part of a track. More tools may be added in future versions.")
                }.padding(.horizontal, 30)

                Spacer().frame(height: 15)

                HStack(spacing: 30) {
                  Button(action: purchaseTV) { (tvProduct == nil) ? Text("Purchase") : Text("Purchase " + tvProduct!.displayPrice) }
                    .disabled(tvProduct == nil)
                    .onChange(of: skManager.spProducts) { _ in
                      Task { tvProduct = skManager.productFromID(tvProductID) }
                    }

                  Button(action: skManager.openInAppHelp) { Text("More information") }
                  Button(action: model.dismissTVPurchase) { Text("Dismiss") }
                }
              }.frame(minWidth: 344, maxWidth: .infinity, minHeight: 106).padding(.horizontal, 7)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray, lineWidth: 5).opacity(0.6))
            }
          }

          if(toolsViewAvailable()) {
            // TODO: Do refactor other views, too.
            ToolsView(model: model, playerSelection: playerSelection, focusState: $viewFocus)
              .frame(maxWidth: .infinity).padding(.horizontal, 7).padding(.vertical, 20)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(((viewFocus == .CurrentPlayingView) && (controlActiveState == .key)) ? .blue : .clear, lineWidth: 5).opacity(0.6))
          } else {
            Spacer().frame(maxWidth: .infinity).padding(7)
          }
        }

        Spacer().frame(height: 10)
      }
    }
    .padding()
    .frame(minWidth:  200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      viewFocus = .BrowserScrollView
      handleKeyEvents()
    }
    .alert(playerAlert.alertMessage, isPresented: $playerAlert.alertTriggered) { }
    .alert("Thank you for purchasing a StuPlayer component! If you change your mind, you can request a refund from the Purchases menu.", isPresented: $skManager.purchaseMade) { }
  }

  func purchaseProduct(_ product: Product?) {
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

  func purchasePLV() { purchaseProduct(skManager.productFromID(plvProductID)) }
  func purchaseLV()  { purchaseProduct(skManager.productFromID(lvProductID)) }
  func purchaseTV()  { purchaseProduct(skManager.productFromID(tvProductID)) }

  func trackPlaying() -> Bool { return (playerSelection.playPosition > 0) }
  func playlistViewPurchased() -> Bool { return skManager.plViewPurchased }
  func playlistViewAvailable() -> Bool { return trackPlaying() && playlistViewPurchased() }

  func lyricsViewPurchased() -> Bool { return skManager.lViewPurchased }
  func lyricsViewAvailable() -> Bool { return trackPlaying() && lyricsViewPurchased() }

  func toolsViewPurchased() -> Bool { return skManager.tViewPurchased }
  func toolsViewAvailable() -> Bool { return trackPlaying() && toolsViewPurchased() }

  func nextFocusView(_ currentView: ViewFocus) -> ViewFocus {
    switch(currentView) {
    case .BrowserScrollView:
      if(!trackPlaying()) { return .BrowserScrollView }

      if(playlistViewPurchased()) { return .PlaylistScrollView }
      if(lyricsViewPurchased())   { return .LyricsInfoView }
      return .CurrentPlayingView

    case .PlaylistScrollView:
      if(lyricsViewPurchased())   { return .LyricsInfoView }
      return .CurrentPlayingView

    case .LyricsInfoView:
      return .LyricsScrollView

    case .LyricsScrollView:
      return .CurrentPlayingView

    case .CurrentPlayingView:
      return toolsViewPurchased() ? .ToolsView : .BrowserScrollView

    case .ToolsView:
      return .BrowserScrollView
    }
  }

  func handleKeyEvents() {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { aEvent -> NSEvent? in
      let keyCode = Int(aEvent.keyCode)
      switch(keyCode) {
      case kVK_Escape:
        if(viewFocus == .BrowserScrollView) {
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
        } else if(viewFocus == .PlaylistScrollView) {
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
        } else if(viewFocus == .LyricsInfoView) {
          // Clear popup first
          model.delayCancel()
          if(playerSelection.lyricsInfoPopover != -1) {
            playerSelection.lyricsInfoPopover = -1
            return nil
          }

          // Clear the selection
          playerSelection.lyricsInfoPos = -1
          return nil
        } else if(viewFocus == .LyricsScrollView) {
          // Clear the selection
          playerSelection.lyricsScrollPos = -1
          return nil
        }

      case kVK_Return:
        if((viewFocus == .BrowserScrollView)) {
          let itemIndex = playerSelection.browserScrollPos
          if((itemIndex < 0) && (playerSelection.browserItems.count > 0)) {
            playerSelection.browserScrollPos = 0
            return nil
          } else if(playerSelection.browserScrollPos < 0) { return nil }

          model.browserItemSelected(itemIndex: itemIndex, itemText: playerSelection.browserItems[itemIndex])
        } else if(viewFocus == .PlaylistScrollView) {
          let itemIndex = playerSelection.playingScrollPos
          if(itemIndex < 0) {
            playerSelection.playingScrollPos = 0
            playerSelection.searchIndex      = 0
            return nil
          }

          model.playingItemSelected(itemIndex)
        } else if(viewFocus == .LyricsInfoView) {
          // No op
        } else if(viewFocus == .LyricsScrollView) {
          let itemIndex = playerSelection.lyricsScrollPos
          if(itemIndex < 0) {
            playerSelection.lyricsScrollPos = 0
            return nil
          }

          model.lyricsItemSelected(itemIndex)
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
        if((viewFocus == .BrowserScrollView)) {
          model.toggleBrowserPopup()
        } else if(viewFocus == .PlaylistScrollView) {
          model.togglePlayingPopup()
        } else if(viewFocus == .LyricsInfoView) {
          model.toggleLyricsInfoPopup()
        }

        return nil

      case kVK_ANSI_LeftBracket:
        if(!skManager.tViewPurchased || playerSelection.loopStartDisabled) { return nil }

        model.setLoopStart()
        return nil

      case kVK_ANSI_RightBracket:
        if(!skManager.tViewPurchased || playerSelection.loopEndDisabled) { return nil }

        model.setLoopEnd()
        return nil

      default:
        break
      }

      guard let specialKey = aEvent.specialKey else { return aEvent }
      switch(specialKey) {
      case .tab:
        guard let viewFocus else { return nil }

        let nextViewFocus = nextFocusView(viewFocus)
        if(nextViewFocus != viewFocus) {
          switch(viewFocus) {
          case .BrowserScrollView:
            playerSelection.browserPopover = -1

          case .PlaylistScrollView:
            playerSelection.playingPopover = -1

          case .LyricsInfoView:
            playerSelection.lyricsInfoPopover = -1

          default:
            break
          }

          self.viewFocus = nextViewFocus
        }

        return nil

      default:
        break
      }

      return aEvent
    }
  }
}
