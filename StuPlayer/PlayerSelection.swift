//
//  PlayerSelection.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 05/03/2024.
//

import Foundation

@MainActor class PlayerSelection: ObservableObject
{
  @Published var artist: String = ""
  @Published var album:  String = ""

  @Published var playlist: String = ""
  @Published var track:    String = ""

  @Published var list: [String] = []

  func setArtist(newArtist: String, newList: [String]) {
    self.album  = ""

    self.artist = newArtist
    self.list   = newList
  }

  func setAlbum(newAlbum: String, newList: [String]) {
    self.album    = newAlbum
    self.list  = newList
  }

  func setList(newList: [String]) {
    self.list = newList
  }

  func setAll(newArtist: String, newAlbum: String, newList: [String]) {
    self.artist = newArtist
    self.album  = newAlbum
    self.list   = newList
  }

  func setPlaylist(newPlaylist: String, newTrack: String) {
    self.playlist = newPlaylist
    self.track    = newTrack
  }
}
