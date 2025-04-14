//
//  NothingPlayingView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 13/04/2025.
//

import SwiftUI

struct NothingPlayingView : View {
  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection

  var body : some View {
    VStack(alignment: .leading) {
      HStack {
        Text("Playing: ").frame(width: 142, alignment: .leading)

        // Needed to keep the height of the HStack the same
        Slider(value: $playerSelection.trackPos, in: 0...1).frame(width: 300, alignment: .leading).hidden()
        Spacer().frame(width: 15).hidden()
        Text(playerSelection.trackPosStr).monospacedDigit().frame(width: 42, alignment: .trailing).hidden()
      }

      HStack {
        Text("Album playlist: ").frame(minWidth: 120, alignment: .leading).padding(.vertical, 2)

        Spacer().frame(width: 20)

        Text("Track: ").frame(minWidth: 120, alignment: .leading)

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
        }.disabled(true)

        Spacer().frame(width: 20)

        Button(action: model.stopAll) {
          Text(" Stop ").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)
        }.disabled(true)

        Spacer().frame(width: 20)

        Button(action: model.playPreviousTrack) {
          Text("Previous").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
        }.disabled(true)

        Spacer().frame(width: 20)

        Button(action: model.playNextTrack) {
          Text("Next").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
        }.disabled(true)

        Spacer().frame(width: 20)

        Button(action: model.restartAll) {
          Text("Restart").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
        }.disabled(true)

        if(playerSelection.shuffleTracks) {
          Spacer().frame(width: 20)

          Button(action: model.reshuffleAll) {
            Text("Reshuffle").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
          }.disabled(true)
        }
      }
    }
  }
}
