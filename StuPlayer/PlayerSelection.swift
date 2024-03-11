//
//  PlayerSelection.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 05/03/2024.
//

import Foundation

enum PlaybackState {
  case Stopped, Playing, Paused
}

@MainActor class PlayerSelection: ObservableObject
{
  @MainActor protocol Delegate: AnyObject {
    func typeChanged(newType: String)
  }

  @Published var rootPath = ""
  @Published var typeList: [String] = []

  @Published var type: String = "" {
    didSet {
      delegate?.typeChanged(newType: type)
    }
  }

  @Published var artist = ""
  @Published var album  = ""

  @Published var playlist = ""
  @Published var track    = ""

  @Published var trackNum  = 0
  @Published var numTracks = 1
  var tracks: [String]     = []

  @Published var list: [String] = []
  @Published var playbackState  = PlaybackState.Stopped

  weak var delegate: Delegate?

  func setDelegate(delegate: Delegate) {
    self.delegate = delegate
  }

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

  func setPlaylist(newPlaylist: String, newTrackNum: Int) {
    self.playlist = newPlaylist
    self.trackNum = newTrackNum

    if(newTrackNum > 0) {
      self.track = tracks[self.trackNum - 1]
    } else {
      self.track = ""
    }
  }

  func setTracks(newTracks: [String]) {
    self.tracks    = newTracks
    self.numTracks = newTracks.count
  }

  func setPlaybackState(newPlaybackState: PlaybackState) {
    self.playbackState = newPlaybackState
  }
}
