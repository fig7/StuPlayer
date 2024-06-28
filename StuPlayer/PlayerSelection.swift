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
    func browserScrollPosChanged(newScrollPos: Int)
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
  @Published var fileName = ""

  @Published var trackNum  = 0
  @Published var numTracks = 0

  @Published var repeatTracks   = RepeatState.None
  @Published var shuffleTracks  = false

  @Published var browserItems: [String] = []
  @Published var playbackState: AudioPlayer.PlaybackState = .stopped

  @Published var playPosition = 0
  @Published var playTotal    = 0

  @Published var trackPos     = 0.0    // 0.0 < 1.0 (used by the slider)
  @Published var trackPosStr  = "0:00" // Hours, minutes and seconds
  @Published var trackLeftStr = "0:00" // Hours, minutes and seconds

  @Published var trackCountdown = false  // Time ticks up or down
  @Published var seekEnabled    = false  // Enable and disable the slider

  @Published var playingTracks: [PlayingItem] = []

  @Published var filterMode   = FilterMode.Artist
  @Published var filterString = "" {
    didSet {
      delegate?.filterChanged(newFilter: filterString)
    }
  }

  @Published var browserScrollPos = -1 {
    didSet {
      delegate?.browserScrollPosChanged(newScrollPos: browserScrollPos)
    }
  }

  @Published var playingScrollTo   = -1
  @Published var playingScrollPos  = -1

  var prevSel = -1
  var currSel = -1

  @Published var searchIndex = -1 { didSet { updateSearchUpDown() } }
  @Published var searchUpAllowed   = false
  @Published var searchDownAllowed = false
  @Published var searchString = "" {
    didSet {
      if(searchString.isEmpty) {
        for i in playingTracks.indices { playingTracks[i].searched = false }

        searchIndex       = playingScrollPos
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
        searchIndex       = playingScrollPos
        searchUpAllowed   = false
        searchDownAllowed = false
        return
      }

      if((searchIndex != -1) && (playingTracks[searchIndex].searched)) {
        updateSearchUpDown()
        return
      }

      if(!searchNext()) {
        _ = searchHome()
      }
    }
  }

  @Published var browserItemInfo   = ""
  @Published var playingTrackInfo  = ""

  @Published var playingInfo   = ""
  @Published var playlistInfo  = ""
  @Published var trackInfo     = ""
  @Published var countdownInfo = ""

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

    if((self.browserScrollPos >= 0) && (newList.count > 0)) { self.browserScrollPos = 0 } else { self.browserScrollPos = -1 }
    self.browserItems = newList
  }

  func setAlbum(newAlbum: String, newList: [String]) {
    self.album = newAlbum

    if((self.browserScrollPos >= 0) && (newList.count > 0)) { self.browserScrollPos = 0 } else { self.browserScrollPos = -1 }
    self.browserItems = newList
  }

  func setAll(newArtist: String, newAlbum: String, newList: [String]) {
    self.artist = newArtist
    self.album  = newAlbum

    if((self.browserScrollPos >= 0) && (newList.count > 0)) { self.browserScrollPos = 0 } else { self.browserScrollPos = -1 }
    self.browserItems = newList
  }

  func setArtistAndAlbum(newArtist: String, newAlbum: String) {
    self.artist = newArtist
    self.album  = newAlbum
  }

  private func fetchMetadata(trackURL: URL) -> String {
    let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: trackURL)
    guard let audioFile else { return "" }

    var meta: [String] = []
    let title = audioFile.metadata.title
    if(title != nil) { meta.append("Title:\t\(title!)") }

    let metaArtist = audioFile.metadata.artist
    if(metaArtist != nil) { meta.append("Artist:\t\(metaArtist!)") }

    let metaAlbum = audioFile.metadata.albumTitle
    if(metaAlbum != nil) { meta.append("Album:\t\(metaAlbum!)") }

    let genre = audioFile.metadata.genre
    if(genre != nil) { meta.append("Genre:\t\(genre!)") }

    var metadataStr = ""
    if(!meta.isEmpty) {
      metadataStr = "Metadata:\n\t" + meta.joined(separator: "\n\t")
    }

    var props: [String] = []
    let sampleRate = audioFile.properties.sampleRate
    if(sampleRate != nil) { props.append("Sample rate:\t\(sampleRate!.toIntStr())") }

    let numChannels = audioFile.properties.channelCount
    if(numChannels != nil) { props.append("Channels:\t\(numChannels!)") }

    let duration = audioFile.properties.duration
    if(duration != nil) { props.append("Duration:\t\(timeStr(from: duration!))") }

    let bitrate = audioFile.properties.bitrate
    if(bitrate != nil) { props.append("Bit rate:\t\t\(bitrate!.toIntStr()) KB/s") }

    if(!props.isEmpty) {
      if(!metadataStr.isEmpty) { metadataStr += "\n\n" }
      metadataStr += "Properties:\n\t" + props.joined(separator: "\n\t")
    }

    return metadataStr
  }

  func setTrack(newTrack: TrackInfo?) {
    setPlaylist(newPlaylist: newTrack?.playlist)

    guard let newTrack else {
      self.fileName = ""
      self.trackNum = 0

      self.playingInfo = ""
      self.trackInfo   = ""
      return
    }

    self.fileName = newTrack.trackURL.lastPathComponent
    self.trackNum = newTrack.trackNum

    let playlist = newTrack.playlist
    let playlistInfo = playlist.playlistInfo

    let playlistSplit = playlistInfo.playlistPath.split(separator: "/")
    let artist = playlistSplit[0]
    let album  = playlistSplit[1]

    let trackInfo   = "File:\t\t\(fileName)\nArtist:\t\(artist)\nAlbum:\t\(album)\nTrack:\t\(trackNum) of \(numTracks)"
    let metadataStr = fetchMetadata(trackURL: newTrack.trackURL)
    self.trackInfo  = !metadataStr.isEmpty ? trackInfo + "\n\n" + metadataStr : trackInfo
  }

  func setBrowserItemInfo(itemIndex: Int, artist: String, album: String, m3U: String?, trackURL: URL?) {
    let trackNum  = itemIndex+1
    let numTracks = browserItems.count
    let itemText  = browserItems[itemIndex]

    if(artist.isEmpty) {
      browserItemInfo = "Artist:\t\(browserItems[itemIndex])"
      return
    }

    if(album.isEmpty) {
      browserItemInfo = "Artist:\t\(artist)\nAlbum:\t\(itemText)\nM3U:\t\(m3U!)"
      return
    }

    let fileName = itemText
    let browserInfo = "File:\t\t\(fileName)\nArtist:\t\(artist)\nAlbum:\t\(album)\nTrack:\t\(trackNum) of \(numTracks)"
    let metadataStr = fetchMetadata(trackURL: trackURL!)
    self.browserItemInfo = !metadataStr.isEmpty ? browserInfo + "\n\n" + metadataStr : browserInfo
  }

  func setPlayingTrackInfo(trackNum: Int, trackInfo: TrackInfo) {
    let fileName = trackInfo.trackURL.lastPathComponent
    let playlist = trackInfo.playlist
    let playlistInfo = playlist.playlistInfo

    let playlistSplit = playlistInfo.playlistPath.split(separator: "/")
    let artist = playlistSplit[0]
    let album  = playlistSplit[1]

    let playingInfo   = "File:\t\t\(fileName)\nArtist:\t\(artist)\nAlbum:\t\(album)\nTrack:\t\(trackNum) of \(playTotal)"
    let metadataStr   = fetchMetadata(trackURL: trackInfo.trackURL)
    self.playingTrackInfo = !metadataStr.isEmpty ? playingInfo + "\n\n" + metadataStr : playingInfo
  }

  func setPlaylist(newPlaylist: Playlist?) {
    guard let newPlaylist else {
      self.playlist  = ""
      self.numTracks = 0

      self.playlistInfo = ""
      return
    }

    let playlistInfo = newPlaylist.playlistInfo
    self.playlist  = playlistInfo.playlistFile
    self.numTracks = playlistInfo.numTracks

    let playlistSplit = playlistInfo.playlistPath.split(separator: "/")
    let artist = playlistSplit[0]
    let album  = playlistSplit[1]

    let baseStr  = "Playlist:\t\(playlist)\nArtist:\t\(artist)\nAlbum:\t\(album)\nTracks:\t"
    let trackStr = newPlaylist.tracks.joined(separator: "\n\t\t")
    self.playlistInfo = baseStr + trackStr
  }

  func setPlaybackState(newPlaybackState: AudioPlayer.PlaybackState) {
    self.playbackState = newPlaybackState
  }

  func setPlayingPosition(playPosition: Int, playTotal: Int) {
    self.playPosition = playPosition
    self.playTotal    = playTotal

    if(playPosition == 0) {
      self.trackPos    = 0.0
      self.trackPosStr  = "0:00"
      self.trackLeftStr = "0:00"
      self.seekEnabled = false
    }
  }

  func setPlayingInfo() {
    // NB: Call after both setTrack() and setPlayingPosition()
    self.playingInfo = (playPosition > 0) ? "Playing:\t\(fileName)\nTrack:\t\(playPosition) of \(playTotal)" : ""
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
    var prevIndex = searchIndex - 1
    if(prevIndex < 0) { return false }

    repeat {
      if(playingTracks[prevIndex].searched) {
        if(playingScrollPos >= 0) { playingScrollPos = prevIndex }
        searchIndex      = prevIndex
        playingScrollTo  = prevIndex
        return true
      }

      prevIndex -= 1
    } while(prevIndex >= 0)

    return false
  }

  func searchNext() -> Bool {
    let indexLimit = playingTracks.count - 1

    var nextIndex = searchIndex + 1
    if(nextIndex > indexLimit) { return false }

    repeat {
      if(playingTracks[nextIndex].searched) {
        if(playingScrollPos >= 0) { playingScrollPos = nextIndex }
        searchIndex     = nextIndex
        playingScrollTo = nextIndex
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
        if(playingScrollPos >= 0) { playingScrollPos = index }
        searchIndex     = index
        playingScrollTo = index
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
        if(playingScrollPos >= 0) { playingScrollPos = index }
        searchIndex     = index
        playingScrollTo = index
        return true
      }

      index -= 1
    } while(index >= 0)

    return false
  }

  func updateSearchUpDown() {
    if(searchString.isEmpty) { return }

    var upAllowed   = false
    var downAllowed = false

    for i in playingTracks.indices {
      let searched = playingTracks[i].searched
      if(searched && (i < searchIndex)) {
        upAllowed = true
      } else if(searched && (i > searchIndex)) {
        downAllowed = true
        break
      }
    }

    searchUpAllowed   = upAllowed
    searchDownAllowed = downAllowed
  }
}
