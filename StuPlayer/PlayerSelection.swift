//
//  PlayerSelection.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 05/03/2024.
//

import Foundation
import SFBAudioEngine

enum RepeatState { case None, Track, All }
enum FilterMode  { case Artist, Album, Track }

struct PlayingItem {
  let name: String
  var searched: Bool
}

@MainActor class PlayerSelection: ObservableObject
{
  @MainActor protocol Delegate: AnyObject {
    func typeChanged(newType: String)
    func filterChanged(newFilter: String)
    func scrollPosChanged(newScrollPos: Int)
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

  @Published var playingTracks: [PlayingItem] = []

  @Published var filterMode   = FilterMode.Artist
  @Published var filterString = "" {
    didSet {
      delegate?.filterChanged(newFilter: filterString)
    }
  }

  @Published var scrollPos = -1 {
    didSet {
      delegate?.scrollPosChanged(newScrollPos: scrollPos)
    }
  }

  @Published var scrollTo = false
  @Published var scrollPos2 = -1 { didSet { updateSearchUpDown() } }

  @Published var searchUpAllowed   = false
  @Published var searchDownAllowed = false
  @Published var searchString = "" {
    didSet {
      if(searchString.isEmpty) {
        for i in playingTracks.indices { playingTracks[i].searched = false }

        searchUpAllowed   = false
        searchDownAllowed = false
        return
      }

      let lcSearchString = searchString.lowercased()
      var firstIndex = -1
      for i in playingTracks.indices {
        if(playingTracks[i].name.lowercased().hasPrefix(lcSearchString)) {
          playingTracks[i].searched = true
          if(firstIndex == -1) { firstIndex = i }
        } else { playingTracks[i].searched = false }
      }

      if(firstIndex == -1) {
        searchUpAllowed   = false
        searchDownAllowed = false
      }

      if((scrollPos2 != -1) && (playingTracks[scrollPos2].searched)) {
        updateSearchUpDown()
        return
      }

      if(!searchNext()) {
        _ = searchHome()
      }
    }
  }

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
    self.artist = newArtist
    self.album  = ""

    if((self.scrollPos >= 0) && (newList.count > 0)) { self.scrollPos = 0 } else { self.scrollPos = -1 }
    self.list = newList
  }

  func setAlbum(newAlbum: String, newList: [String]) {
    self.album = newAlbum

    if((self.scrollPos >= 0) && (newList.count > 0)) { self.scrollPos = 0 } else { self.scrollPos = -1 }
    self.list = newList
  }

  func setAll(newArtist: String, newAlbum: String, newList: [String]) {
    self.artist = newArtist
    self.album  = newAlbum

    if((self.scrollPos >= 0) && (newList.count > 0)) { self.scrollPos = 0 } else { self.scrollPos = -1 }
    self.list = newList
  }

  func setArtistAndAlbum(newArtist: String, newAlbum: String) {
    self.artist = newArtist
    self.album  = newAlbum
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
    case .None:
      return .Track

    case .Track:
      return .All

    case .All:
      return .None
    }
  }

  func toggleRepeatTracks() {
    switch(repeatTracks) {
    case .None:
      repeatTracks = .Track

    case .Track:
      repeatTracks = .All

    case .All:
      repeatTracks = .None
    }
  }

  func toggleFilterMode() {
    switch(filterMode) {
    case .Artist:
      filterMode = .Album

    case .Album:
      filterMode = .Track

    case .Track:
      filterMode = .Artist
    }

    if(!filterString.isEmpty) {
      delegate?.filterChanged(newFilter: filterString)
    }
  }

  func clearFilter(resetMode: Bool) {
    if(resetMode) { filterMode = .Artist }
    if(!filterString.isEmpty) {
      filterString = ""
    }
  }

  func clearSearch() {
    if(!searchString.isEmpty) {
      searchString = ""
    }
  }

  func searchPrev() -> Bool {
    var prevIndex = scrollPos2 - 1
    if(prevIndex < 0) { return false }

    repeat {
      if(playingTracks[prevIndex].searched) {
        scrollPos2 = prevIndex;
        scrollTo   = true
        return true
      }

      prevIndex -= 1
    } while(prevIndex >= 0)

    return false
  }

  func searchNext() -> Bool {
    let indexLimit = playingTracks.count - 1

    var nextIndex = scrollPos2 + 1
    if(nextIndex > indexLimit) { return false }

    repeat {
      if(playingTracks[nextIndex].searched) {
        scrollPos2 = nextIndex;
        scrollTo   = true
        return true
      }

      nextIndex += 1
    } while(nextIndex <= indexLimit)

    return false
  }

  func searchHome() -> Bool {
    let indexLimit = playingTracks.count - 1
    var index      = 0

    repeat {
      if(playingTracks[index].searched) {
        scrollPos2 = index;
        scrollTo   = true
        return true
      }

      index += 1
    } while(index <= indexLimit)

    return false
  }

  func searchEnd() -> Bool {
    let indexLimit = playingTracks.count - 1
    var index      = indexLimit

    repeat {
      if(playingTracks[index].searched) {
        scrollPos2 = index;
        scrollTo   = true
        return true
      }

      index -= 1
    } while(index >= 0)

    return false
  }

  func updateSearchUpDown() {
    var upAllowed   = false
    var downAllowed = false

    for i in playingTracks.indices {
      let searched = playingTracks[i].searched
      if(searched && (i < scrollPos2)) {
        upAllowed = true
      } else if(searched && (i > scrollPos2)) {
        downAllowed = true
        break
      }
    }

    searchUpAllowed   = upAllowed
    searchDownAllowed = downAllowed
  }
}
