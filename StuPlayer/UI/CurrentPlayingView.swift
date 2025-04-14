//
//  CurrentPlayingView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 08/04/2025.
//

import SwiftUI
import Carbon.HIToolbox

struct CurrentPlayingView : View {
  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection
  @FocusState.Binding var focusState: ViewFocus?

  let textWidth: CGFloat
  let tViewPurchased: Bool

  // TODO: Remove once keyboard handling is done properly
  @Binding var lyricsEdit: Bool

  @State private var playingPopover   = false
  @State private var playlistPopover  = false
  @State private var trackPopover     = false
  @State private var sliderPopover    = false
  @State private var countdownPopover = false

  var body : some View {
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
            if(startFinish) { sliderPopover = true; return }

            sliderPopover = false
            model.seekToSL(newPosition: playerSelection.trackPos)
          }).frame(width:300, alignment:.leading).disabled(!playerSelection.seekEnabled).focused($focusState, equals: .CurrentPlayingView)
          // The slider popover has a few hacks to get it in the right place and make sure it is big enough.
          // Not sure why popovers don't resize properly, that might be Apple's fault.
            .popover(isPresented: $sliderPopover, attachmentAnchor: .point(UnitPoint(x: 0.935*playerSelection.trackPos + 0.0325, y: 0.2))) { Text("\(playerSelection.sliderPosStr)").font(.headline).monospacedDigit().frame(width: CGFloat(playerSelection.sliderPosStr.count)*textWidth).padding() }

          Spacer().frame(width: 15)

          Text(playerSelection.trackCountdown ? playerSelection.trackLeftStr : playerSelection.trackPosStr).monospacedDigit().frame(width: 42, alignment: .trailing).padding(.horizontal, 6)
            .onTapGesture { model.toggleTrackCountdown() }
            .onHover(perform: { hovering in
              if(hovering) {
                model.delayAction() { countdownPopover = true }
              } else { model.delayCancel(); countdownPopover = false } })
            .popover(isPresented: $countdownPopover) { Text("\(playerSelection.countdownInfo)").font(.headline).monospacedDigit().padding() }
        } else {
          Text("Playing: ").frame(width: 142, alignment: .leading)

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

        Spacer().frame(width: 20)

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
    }.onAppear {
      handleKeyEvents()
    }
  }

  func handleKeyEvents() {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { aEvent -> NSEvent? in
      if(focusState != .CurrentPlayingView) { return aEvent }
      if(lyricsEdit) { return aEvent}

      let keyCode = Int(aEvent.keyCode)
      switch(keyCode) {
      case kVK_Escape:
        // Clear popup
        if(!playingPopover && !countdownPopover && !playlistPopover && !trackPopover) { return nil }

        model.delayCancel()
        if(playingPopover)   { playingPopover = false}
        if(countdownPopover) { countdownPopover = false }
        if(playlistPopover)  { playlistPopover = false }
        if(trackPopover)     { trackPopover = false }
        return nil

      case kVK_Space:
        model.togglePause()
        return nil

      case kVK_ANSI_Grave:
        trackPopover.toggle()
        return nil

      case kVK_UpArrow:
        trackPopover = false
        model.playPreviousTrack()
        return nil

      case kVK_DownArrow:
        trackPopover = false
        model.playNextTrack()
        return nil

      case kVK_ANSI_LeftBracket:
        if(!tViewPurchased || playerSelection.loopStartDisabled) { return nil }

        model.setLoopStart()
        return nil

      case kVK_ANSI_RightBracket:
        if(!tViewPurchased || playerSelection.loopEndDisabled) { return nil }

        model.setLoopEnd()
        return nil

      default:
        break
      }

      guard let specialKey = aEvent.specialKey else { return aEvent }
      if(specialKey == .tab) { trackPopover = false }
      return aEvent
    }
  }
}
