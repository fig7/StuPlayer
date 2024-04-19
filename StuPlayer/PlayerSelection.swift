//
//  PlayerSelection.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 05/03/2024.
//

import Foundation
import SFBAudioEngine

enum RepeatState {
  case None, Track, All
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
  @Published var numTracks = 0

  @Published var repeatTracks   = RepeatState.None
  @Published var shuffleTracks  = false

  @Published var list: [String] = []
  @Published var playbackState: AudioPlayer.PlaybackState = .stopped

  @Published var playPosition = 0
  @Published var playTotal    = 0

  @Published var trackPosition  = 0.0    // 0.0 < 1.0 (used by the slider)
  @Published var trackPosString = "0:00" // Hours, minutes and seconds
  @Published var seekEnabled    = false  // Enable and disable the slider

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

  func setTrack(newTrack: TrackInfo?) {
    setPlaylist(newPlaylist: newTrack?.playlistInfo)

    guard let newTrack else {
      self.track    = ""
      self.trackNum = 0
      return
    }

    self.track    = newTrack.trackURL.lastPathComponent
    self.trackNum = newTrack.trackNum
  }

  func setPlaylist(newPlaylist: PlaylistInfo?) {
    guard let newPlaylist else {
      self.playlist  = ""
      self.numTracks = 0
      return
    }

    self.playlist  = newPlaylist.playlistFile
    self.numTracks = newPlaylist.numTracks
  }

  func setPlaybackState(newPlaybackState: AudioPlayer.PlaybackState) {
    self.playbackState = newPlaybackState
  }

  func setPlayingPosition(playPosition: Int, playTotal: Int) {
    self.playPosition = playPosition
    self.playTotal    = playTotal

    if(playPosition == 0) {
      self.trackPosition  = 0.0
      self.trackPosString = "0:00"
      self.seekEnabled    = false
    }
  }

  func setSeekEnabled(seekEnabled: Bool) {
    self.seekEnabled = seekEnabled
  }

  func peekShuffle() -> Bool {
    return !shuffleTracks
  }

  func toggleShuffle() {
    shuffleTracks = !shuffleTracks
  }

  func peekRepeat() -> RepeatState {
    switch(repeatTracks) {
    case RepeatState.None:
      return RepeatState.Track

    case RepeatState.Track:
      return RepeatState.All

    case RepeatState.All:
      return RepeatState.None
    }
  }

  func toggleRepeatTracks() {
    switch(repeatTracks) {
    case RepeatState.None:
      repeatTracks = RepeatState.Track

    case RepeatState.Track:
      repeatTracks = RepeatState.All

    case RepeatState.All:
      repeatTracks = RepeatState.None
    }
  }
}
