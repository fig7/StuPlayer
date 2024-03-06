//
//  ContentView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import SwiftUI

struct ContentView: View {
  @State private var typeSelection = "MP3"
  let musicTypes = ["MP3", "FLAC", "MOD"]

  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Button(action: model.setRootFolder) {
          Text("Root folder: ").padding(.horizontal, 10).padding(.vertical, 2)
        }

        Text("/Volumes/Mini external/Music").padding(.horizontal, 10).padding(.vertical, 2)

        Button(action: model.scanFolders) {
          Text("Rescan").padding(.horizontal, 10).padding(.vertical, 2)
        }
      }

      Spacer().frame(height: 15)

      HStack {
        Picker("Type:", selection: $typeSelection) {
          ForEach(musicTypes, id: \.self) {
            Text($0)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 125)

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
          Text("Play all").padding(.horizontal, 10).padding(.vertical, 2)
        }

        Spacer().frame(width: 20)

        Button(action: model.toggleShuffle) {
          Text("Order: from m3u").padding(.horizontal, 10).padding(.vertical, 2)
        }

        Spacer().frame(width: 20)

        Button(action: model.toggleRepeat) {
          Text("Repeat: off").padding(.horizontal, 10).padding(.vertical, 2)
        }
      }

      Spacer().frame(height: 10)

      ScrollView {
        VStack(alignment: .leading) {
          ForEach(playerSelection.list, id: \.self) {
            let itemText = $0
            Text(itemText).frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
              .onTapGesture { model.itemSelected(item: itemText) }
          }
        }
      }
      .frame(minWidth: 150, maxWidth: .infinity)

      Spacer().frame(height: 30)

      HStack {
        Text("Playlist: " + playerSelection.playlist).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

        Text("Track 1/10: " + playerSelection.track).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
      }

      Spacer().frame(height: 20)
    }
    .padding()
    .frame(minWidth:  200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
  }
}
