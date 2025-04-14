//
//  ToolsView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 28/03/2025.
//

import SwiftUI
import Carbon.HIToolbox

struct ToolsView : View {
  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection
  @FocusState.Binding var focusState: ViewFocus?

  // TODO: Remove once keyboard handling is done properly
  @Binding var lyricsEdit: Bool

  @State private var loopStartHover = false
  @State private var loopEndHover   = false

  var body : some View {
    VStack(alignment: .leading, spacing: 20.0) {
      HStack {
        Toggle("Set playback rate", isOn: $playerSelection.adjustRate).toggleStyle(.checkbox).frame(width: 140, alignment: .leading)

        Spacer().frame(width: 20)

        Slider(value: $playerSelection.trackRate, in: 0.5...2.0).frame(width:150, alignment:.leading).focused($focusState, equals: .ToolsView)

        Spacer().frame(width: 15)

        Text("\(playerSelection.trackRate, specifier: "%.2f")").monospacedDigit().frame(width: 42, alignment: .trailing).padding(.horizontal, 6)
      }

      HStack {
        Toggle("Loop for Luke™", isOn: $playerSelection.loopTrack).toggleStyle(.checkbox).frame(width: 140, alignment: .leading)
          .disabled(playerSelection.loopTrackDisabled)

        Spacer().frame(width: 20)

        Button(action: model.setLoopStart) { Text("Loop start:").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2) }
          .disabled(playerSelection.loopStartDisabled)

        Text("\(playerSelection.loopStart)").monospacedDigit().frame(width: 75, alignment: .trailing).padding(.horizontal, 6)
          .onHover { hovering in
            loopStartHover = hovering
          }
          .onTapGesture {
            if(!playerSelection.loopTrackDisabled) { model.seekToLoopStart() }
          }

        Spacer().frame(width: 30)

        Button(action: model.setLoopEnd) { Text("Loop end:").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2) }
          .disabled(playerSelection.loopEndDisabled)

        Text("\(playerSelection.loopEnd)").monospacedDigit().frame(width: 75, alignment: .trailing).padding(.horizontal, 6)
          .onHover { hovering in
            loopEndHover = hovering
          }
      }
    }
    .onAppear() {
      handleKeyEvents()
      handleWheelEvents()
    }
  }

  func handleKeyEvents() {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { aEvent -> NSEvent? in
      if(focusState != .ToolsView) { return aEvent }
      if(lyricsEdit) { return aEvent}

      let keyCode = Int(aEvent.keyCode)
      switch(keyCode) {

      case kVK_Space:
        model.togglePause()
        return nil

      case kVK_UpArrow:
        playerSelection.adjustRate.toggle()
        return nil

      case kVK_DownArrow:
        playerSelection.loopTrack.toggle()
        return nil

      case kVK_ANSI_LeftBracket:
        if(playerSelection.loopStartDisabled) { return nil }

        model.setLoopStart()
        return nil

      case kVK_ANSI_RightBracket:
        if(playerSelection.loopEndDisabled) { return nil }

        model.setLoopEnd()
        return nil

      default:
        break
      }

      return aEvent
    }
  }

  func handleWheelEvents() {
    NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
      if(playerSelection.loopTrackDisabled) { return event }

      if(loopStartHover) {
        model.adjustLoopStart(event.scrollingDeltaY)
      }

      if(loopEndHover) {
        model.adjustLoopEnd(event.scrollingDeltaY)
      }

      return event
    }
  }
}
