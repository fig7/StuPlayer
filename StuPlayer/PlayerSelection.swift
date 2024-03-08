//
//  PlayerSelection.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 05/03/2024.
//

import Foundation

@MainActor class PlayerSelection: ObservableObject
{
  @Published var rootPath = ""
  @Published var typeList: [String] = []

  @Published var type = ""

  @Published var artist = ""
  @Published var album  = ""

  @Published var playlist = ""
  @Published var track    = ""

  @Published var list: [String] = []

  func setRootPath(newRootPath: String) {
    self.rootPath = newRootPath
  }

  func setTypes(newType: String, newTypeList: [String]) {
    self.type     = newType
    self.typeList = newTypeList
  }

  func setArtist(newArtist: String, newList: [String]) {
    self.album  = ""

    self.artist = newArtist
    self.list   = newList
  }

  func setAlbum(newAlbum: String, newList: [String]) {
    self.album = newAlbum
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
