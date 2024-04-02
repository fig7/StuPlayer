//
//  ContentView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import SwiftUI

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

        Button(action: model.clearArtist) {
          Text("Artist: ").padding(.horizontal, 10).padding(.vertical, 2)
        }

        Text(playerSelection.artist).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

        Spacer().frame(width: 20)

        Button(action: model.clearAlbum) {
          Text("Album: ").padding(.horizontal, 10).padding(.vertical, 2)
        }

        Text(playerSelection.album).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

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
      }

      Spacer().frame(height: 10)

      ScrollView {
        VStack(alignment: .leading) {
          ForEach(Array(playerSelection.list.enumerated()), id: \.element) { itemIndex, itemText in
            Text(itemText).frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
              .onTapGesture { model.itemSelected(itemIndex: itemIndex, itemText: itemText) }
          }
        }
      }
      .frame(minWidth: 150, maxWidth: .infinity)

      Spacer().frame(height: 30)

      if(playerSelection.playPosition > 0) {
        Text(String(format: "Playing: %d/%d", playerSelection.playPosition, playerSelection.playTotal))
      } else {
        Text("Playing: ")
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
          case .Stopped:
            Text("Pause").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)

          case .Playing:
            Text("Pause").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)

          case .Paused:
            Text("Resume").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)
          }
        }

        Spacer().frame(width: 20)

        Button(action: model.stopAll) {
          Text(" Stop ").frame(width: 50).padding(.horizontal, 10).padding(.vertical, 2)
        }

        Spacer().frame(width: 40)

        Button(action: model.playPreviousTrack) {
          Text("Previous").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
        }

        Spacer().frame(width: 20)

        Button(action: model.playNextTrack) {
          Text("Next").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
        }

        Spacer().frame(width: 20)

        Button(action: model.restartAll) {
          switch(playerSelection.shuffleTracks) {
          case false:
            Text("Restart").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
            
          case true:
            Text("Reshuffle").frame(width: 80).padding(.horizontal, 10).padding(.vertical, 2)
          }
        }
      }

      Spacer().frame(height: 10)
    }
    .padding()
    .frame(minWidth:  200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
    .alert(playerAlert.alertMessage, isPresented: $playerAlert.alertTriggered) { }
  }
}
