//
//  PlayerDataModel.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import Foundation
import AppKit
import SFBAudioEngine

// Local storage paths
let rootFile      = "RootFile.dat"
let rootBookmark  = "RootBM.dat"
let rootTypesFile = "RootTypes.dat"

let m3UFile         = "Playlists.dat"
let trackFile       = "Tracks.dat"
let typeFile        = "Type.dat"

typealias M3UDict   = [String : [String : String]]
typealias TrackDict = [String : [String : [String]]]

typealias AllM3UDict     = [String : M3UDict]
typealias AllTracksDict  = [String : TrackDict]

typealias Playlists = [Playlist]

enum StoppingReason { case EndOfAudio, StopPressed, TrackPressed }

@MainActor class PlayerDataModel : NSObject, AudioPlayer.Delegate, PlayerSelection.Delegate {
  let fm    = FileManager.default
  var bmURL = URL(fileURLWithPath: "/")

  var bmData: Data?
  var rootPath: String
  var musicPath: String

  let player: AudioPlayer
  var playerSelection: PlayerSelection

  var allM3UDict: AllM3UDict
  var allTracksDict: AllTracksDict

  var m3UDict: M3UDict
  var tracksDict: TrackDict
  var typesList: [String]

  var selectedType: String
  var selectedArtist: String
  var selectedAlbum: String

  var trackNum: Int
  var stopReason: StoppingReason
  var pendingTrack: String?

  var trackLists: [Tracklist]
  var trackListIterator: [Tracklist].Iterator
  var tracklist: Tracklist?

  var tracks: [URL]
  var trackIterator: [URL].Iterator
  var track: URL?

  var playlistManager: PlaylistManager

  init(playerSelection: PlayerSelection) {
    self.playerSelection = playerSelection
    self.player = AudioPlayer()

    self.bmData = PlayerDataModel.getBookmarkData()
    if let bmData = self.bmData {
      do {
        var isStale = false
        self.bmURL = try URL(resolvingBookmarkData: bmData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

        // TODO: Handle stale bmData
      } catch {
        // Handle error
      }
    }

    // TODO: Handle errors when initialising from stored data
    self.rootPath = PlayerDataModel.getRootPath()

    self.allM3UDict    = PlayerDataModel.getM3UDict(m3UFile: m3UFile)
    self.allTracksDict = PlayerDataModel.getTrackDict(trackFile: trackFile)

    self.typesList    = PlayerDataModel.getTypes(typesFile: rootTypesFile)
    self.selectedType = PlayerDataModel.getSelectedType(typeFile: typeFile)

    self.m3UDict    = allM3UDict[selectedType]!
    self.tracksDict = allTracksDict[selectedType]!
    self.musicPath  = rootPath + selectedType + "/"

    self.selectedArtist = ""
    self.selectedAlbum  = ""

    self.trackNum = 0
    self.stopReason = StoppingReason.EndOfAudio

    self.trackLists = []
    self.trackListIterator = self.trackLists.makeIterator()

    self.tracks = []
    self.trackIterator = self.tracks.makeIterator()

    self.playlistManager = PlaylistManager()

    // NSObject
    super.init()

    Task { @MainActor in
      player.delegate = self

      playerSelection.setDelegate(delegate: self)
      playerSelection.setRootPath(newRootPath: rootPath)
      playerSelection.setTypes(newType: selectedType, newTypeList: typesList)
      playerSelection.setAll(newArtist: selectedArtist, newAlbum: selectedAlbum, newList: tracksDict.keys.sorted())
    }
  }

  // Using audioPlayerNowPlayingChanged to handle track changes
  // NB. nowPlaying -> nil is ignored, audioPlayerPlaybackStateChanged() handles end of audio instead (playbackState -> Stopped)
  nonisolated func audioPlayerNowPlayingChanged(_ audioPlayer: AudioPlayer) {
    if(audioPlayer.nowPlaying == nil) { return }

    // Handle next track
    Task { @MainActor in
      trackNum += 1
      track = trackIterator.next()
      if(track == nil) {
        tracklist = trackListIterator.next()

        tracks = tracklist?.tracks ?? []
        trackIterator = tracks.makeIterator()

        track = trackIterator.next()
        trackNum = 1
      }

      let playlistInfo = tracklist!.playlistInfo
      playerSelection.setTrack(newTrack: track!.lastPathComponent, newTrackNum: trackNum)
      playerSelection.setPlaylist(newPlaylist: playlistInfo.playlistFile, newNumTracks: playlistInfo.numTracks)

      if(player.queueIsEmpty) {
        fetchNextTracks()

        for trackList in trackLists {
          for track in trackList.tracks {
            try player.enqueue(track)
          }
        }
      }
    }
  }

  // Using audioPlayerPlaybackStateChanged to handle state changes and update UI
  nonisolated func audioPlayerPlaybackStateChanged(_ audioPlayer: AudioPlayer) {
    // print("StateChange: Playing = \(audioPlayer.isPlaying), Paused = \(audioPlayer.isPaused), Stopped = \(audioPlayer.isStopped)")

    switch(audioPlayer.playbackState) {
    case AudioPlayer.PlaybackState.stopped:
      Task { @MainActor in
        trackNum = 0

        switch(stopReason) {
        case .EndOfAudio:
          if(playerSelection.repeatTracks) {
            playlistManager.reset(shuffleTracks: playerSelection.shuffleTracks)
            fetchNextTracks()

            for trackList in trackLists {
              for track in trackList.tracks {
                try player.enqueue(track)
              }
            }

            try player.play()
          } else {
            bmURL.stopAccessingSecurityScopedResource()

            playerSelection.setTrack(newTrack: "", newTrackNum: trackNum)
            playerSelection.setPlaylist(newPlaylist: "", newNumTracks: 0)
            playerSelection.setPlaybackState(newPlaybackState: PlaybackState.Stopped)
          }

        case .StopPressed:
          bmURL.stopAccessingSecurityScopedResource()

          playerSelection.setTrack(newTrack: "", newTrackNum: trackNum)
          playerSelection.setPlaylist(newPlaylist: "", newNumTracks: 0)
          playerSelection.setPlaybackState(newPlaybackState: PlaybackState.Stopped)

        case .TrackPressed:
          var playlists    = Playlists()
          let playlistInfo = PlaylistInfo(playlistFile: m3UDict[selectedArtist]![selectedAlbum]!, playlistPath: selectedArtist + "/" + selectedAlbum + "/", numTracks: 1)
          playlists.append((playlistInfo, [pendingTrack!]))

          try playTracks(playlists: playlists)
          pendingTrack = nil
        }

        stopReason = StoppingReason.EndOfAudio
      }

    case AudioPlayer.PlaybackState.playing:
      Task { @MainActor in
        playerSelection.setPlaybackState(newPlaybackState: PlaybackState.Playing)
      }

    case AudioPlayer.PlaybackState.paused:
      Task { @MainActor in
        playerSelection.setPlaybackState(newPlaybackState: PlaybackState.Paused)
      }

    @unknown default:
      break
    }
  }

  func clearArtist() {
    if(selectedArtist.isEmpty) { return }

    selectedArtist = ""
    selectedAlbum  = ""
    playerSelection.setArtist(newArtist: "", newList: tracksDict.keys.sorted())
  }

  func clearAlbum() {
    if(selectedAlbum.isEmpty) { return }

    selectedAlbum = ""
    playerSelection.setAlbum(newAlbum: "", newList: tracksDict[selectedArtist]!.keys.sorted())
  }

  func itemSelected(item: String) {
    if(selectedArtist.isEmpty) {
      selectedArtist = item
      playerSelection.setArtist(newArtist: selectedArtist, newList: tracksDict[selectedArtist]!.keys.sorted())
      return
    }

    if(selectedAlbum.isEmpty) {
      selectedAlbum = item
      playerSelection.setAlbum(newAlbum: selectedAlbum, newList: tracksDict[selectedArtist]![selectedAlbum]!)
      return
    }

    if(player.isPlaying) {
      pendingTrack = item
      stopReason   = StoppingReason.TrackPressed

      player.stop()
      return
    }

    // Can't play if we haven't got the root folder
    guard bmData != nil else { return }

    if(!bmURL.startAccessingSecurityScopedResource()) {
      // Handle error
      return
    }

    var playlists    = Playlists()
    let playlistInfo = PlaylistInfo(playlistFile: m3UDict[selectedArtist]![selectedAlbum]!, playlistPath: selectedArtist + "/" + selectedAlbum + "/", numTracks: 1)
    playlists.append((playlistInfo, [item]))

    do {
      try playTracks(playlists: playlists)
    } catch {
        // Handle error
    }
  }

  func configurePlayback(playlists: Playlists) {
    playlistManager.setMusicPath(musicPath: musicPath)
    playlistManager.generatePlaylist(playlists: playlists, shuffleTracks: false)

    trackNum = 0
    stopReason = StoppingReason.EndOfAudio

    fetchNextTracks()
  }

  func fetchNextTracks() {
    trackLists = playlistManager.nextTracks()

    trackListIterator = trackLists.makeIterator()
    tracklist = trackListIterator.next()

    tracks = tracklist?.tracks ?? []
    trackIterator = tracks.makeIterator()
  }

  func playTracks(playlists: Playlists) throws {
    configurePlayback(playlists: playlists)

    for tracklist in trackLists {
      for track in tracklist.tracks {
        try player.enqueue(track)
      }
    }

    try player.play()
  }

  func playAllArtists() throws {
    if(!bmURL.startAccessingSecurityScopedResource()) {
      // TODO: Throw an error
      return
    }

    var playlists = Playlists()
    for artist in tracksDict.keys.sorted() {
      let albums = tracksDict[artist]!
      for album in albums.keys.sorted() {
        let albumTracks = albums[album]!
        if(!albumTracks.isEmpty) {
          let playlistInfo = PlaylistInfo(playlistFile: m3UDict[artist]![album]!, playlistPath: artist + "/" + album + "/", numTracks: albumTracks.count)
          playlists.append((playlistInfo, albumTracks))
        }
      }
    }

    if(playlists.isEmpty) { return }
    try playTracks(playlists: playlists)
  }

  func playAllAlbums() throws {
    if(!bmURL.startAccessingSecurityScopedResource()) {
      // TODO: Throw an error
      return
    }

    var playlists = Playlists()
    let albums = tracksDict[selectedArtist]!
    for album in albums.keys.sorted() {
      let albumTracks = albums[album]!
      if(!albumTracks.isEmpty) {
        let playlistInfo = PlaylistInfo(playlistFile: m3UDict[selectedArtist]![album]!, playlistPath: selectedArtist + "/" + album + "/", numTracks: albumTracks.count)
        playlists.append((playlistInfo, albumTracks))
      }
    }

    if(playlists.isEmpty) { return }
    try playTracks(playlists: playlists)
  }

  func playAlbum() throws {
    if(!bmURL.startAccessingSecurityScopedResource()) {
      // TODO: Throw an error
      return
    }

    let albumTracks = tracksDict[selectedArtist]![selectedAlbum]!
    if(albumTracks.isEmpty) { return }

    var playlists = Playlists()
    let playlistInfo = PlaylistInfo(playlistFile: m3UDict[selectedArtist]![selectedAlbum]!, playlistPath: selectedArtist + "/" + selectedAlbum + "/", numTracks: albumTracks.count)
    playlists.append((playlistInfo, albumTracks))

    try playTracks(playlists: playlists)
  }

  func playAll() {
    let playing = (playerSelection.playbackState == PlaybackState.Playing)
    let paused  = (playerSelection.playbackState == PlaybackState.Paused)
    if(playing || paused) {
      if(playing) {
        player.pause()
      } else {
        player.resume()
      }
      return
    }

    // Can't play if we haven't got the root folder
    guard bmData != nil else { return }

    do {
      if(selectedArtist.isEmpty && !tracksDict.isEmpty) {
        try playAllArtists()
        return
      }

      if(selectedArtist.isEmpty && !tracksDict[selectedArtist]!.isEmpty) {
        try playAllAlbums()
        return
      }

      try playAlbum()
    } catch {
      // Handle error
    }
  }

  func stopAll() {
    stopReason = StoppingReason.StopPressed
    player.stop()
  }

  func toggleShuffle() {
    playerSelection.toggleShuffle()
  }

  func toggleRepeat() {
    playerSelection.toggleRepeatTracks()
  }

  static func getM3UDict(m3UFile: String) -> AllM3UDict {
    let m3UData = NSData(contentsOfFile: m3UFile) as Data?
    guard let m3UData else {
      return [:]
    }

    do {
      return try PropertyListDecoder().decode(AllM3UDict.self, from: m3UData)
    }
    catch {
      return [:]
    }
  }

  static func getTrackDict(trackFile: String) -> AllTracksDict {
    let trackData = NSData(contentsOfFile: trackFile) as Data?
    guard let trackData else {
      return [:]
    }

    do {
      return try PropertyListDecoder().decode(AllTracksDict.self, from: trackData)
    }
    catch {
      return [:]
    }
  }

  static func getTypes(typesFile: String) -> [String] {
    let typesData = NSData(contentsOfFile: typesFile) as Data?
    guard let typesData else {
      return []
    }

    let typesStr = String(decoding: typesData, as: UTF8.self)
    return typesStr.split(whereSeparator: \.isNewline).map(String.init)
  }

  static func getSelectedType(typeFile: String) -> String {
    let typeData = NSData(contentsOfFile: typeFile) as Data?
    guard let typeData else {
      return ""
    }

    return String(decoding: typeData, as: UTF8.self)
  }

  static func getBookmarkData() -> Data? {
    return NSData(contentsOfFile: rootBookmark) as Data?
  }

  static func getRootPath() -> String {
    let pathData = NSData(contentsOfFile:rootFile) as Data?
    guard let pathData else { return "" }

    return String(decoding: pathData, as: UTF8.self)
  }

  func setRootFolder() {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = true
    openPanel.canCreateDirectories = false
    openPanel.canChooseFiles = false
    openPanel.prompt = "Grant Access"
    openPanel.directoryURL = URL(fileURLWithPath: "/")

    openPanel.begin { [weak self] result in
      guard let self else { return }
      guard (result == .OK), let url = openPanel.url else {
        // HANDLE ERROR HERE ...
        return
      }

      do {
        stopAll()

        bmData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        fm.createFile(atPath: rootBookmark, contents: bmData, attributes: nil)

        rootPath = url.path().removingPercentEncoding!
        try rootPath.write(toFile: rootFile, atomically: true, encoding: .utf8)

        scanFolders()

        self.playerSelection.setRootPath(newRootPath: self.rootPath)
      } catch {
        // Handle error
        return
      }
    }
  }

  func scanM3U(m3UPath: String) -> [String] {
    let m3UData = NSData(contentsOfFile:m3UPath) as Data?
    guard let m3UData else {
      return []
    }

    let m3UStr = String(decoding: m3UData, as: UTF8.self)
    var tracks = m3UStr.split(whereSeparator: \.isNewline).map(String.init)
    tracks.indices.forEach {
      tracks[$0] = tracks[$0].trimmingCharacters(in: .whitespaces)
    }

    return tracks.filter { track in
      return !track.starts(with: "#")
    }
  }

  func scanAlbums(artistPath: String) throws -> (m3Us: [String : String], tracks: [String : [String]]) {
    let albums = try fm.contentsOfDirectory(atPath: artistPath)
    var m3Us: [String  : String] = [:]
    var tracks: [String  : [String]] = [:]

    for album in albums {
      let filePath = artistPath + album

      var isDir: ObjCBool = false
      if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
        let albumPath = filePath + "/"
        let files = try fm.contentsOfDirectory(atPath: albumPath)
        for file in files {
          if(file.hasSuffix(".m3u")) {
            m3Us[album]   = file
            tracks[album] = scanM3U(m3UPath: albumPath + file)
            break
          }
        }
      }
    }

    return (m3Us, tracks)
  }

  func scanTypes() throws {
    typesList.removeAll()
    selectedType = ""

    let types = try fm.contentsOfDirectory(atPath: rootPath)
    for type in types {
      let filePath = rootPath + type

      var isDir: ObjCBool = false
      if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
        typesList.append(type)
      }
    }

    typesList.sort()
    let joinedTypes = typesList.joined(separator: "\n")
    try joinedTypes.write(toFile: rootTypesFile, atomically: true, encoding: .utf8)

    if(typesList.count > 0) {
      selectedType = typesList[0]
    }

    try selectedType.write(toFile: typeFile, atomically: true, encoding: .utf8)
  }

  func scanArtists(typePath: String) throws -> (m3Us: M3UDict, tracks: TrackDict) {
    let artists = try fm.contentsOfDirectory(atPath: typePath)
    var m3Us: M3UDict = [:]
    var tracks: TrackDict = [:]

    // Make a dictionary for each one and write it out
    for artist in artists {
      let filePath = typePath + artist

      var isDir: ObjCBool = false
      if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
        let albumDict = try scanAlbums(artistPath: filePath + "/")

        m3Us[artist]   = albumDict.m3Us
        tracks[artist] = albumDict.tracks
      }
    }

    return (m3Us, tracks)
  }

  func scanFolders() {
    guard bmData != nil else { return }

    if(!bmURL.startAccessingSecurityScopedResource()) {
      // Handle error
      return
    }

    allM3UDict.removeAll()
    allTracksDict.removeAll()

    do {
      try scanTypes()

      for type in typesList {
        let artistDict = try scanArtists(typePath: rootPath + type + "/")

        allM3UDict[type]    = artistDict.m3Us
        allTracksDict[type] = artistDict.tracks
      }

      m3UDict    = allM3UDict[selectedType]!
      tracksDict = allTracksDict[selectedType]!
      musicPath  = rootPath + selectedType + "/"

      let data1 = try PropertyListEncoder().encode(allM3UDict)
      try data1.write(to: URL(fileURLWithPath:m3UFile))

      let data2 = try PropertyListEncoder().encode(allTracksDict)
      try data2.write(to: URL(fileURLWithPath:trackFile))
      bmURL.stopAccessingSecurityScopedResource()
    } catch {
      // Handle error
    }

    selectedArtist = ""
    selectedAlbum  = ""
    playerSelection.setAll(newArtist: selectedArtist, newAlbum: selectedAlbum, newList: tracksDict.keys.sorted())
    playerSelection.setTypes(newType: selectedType, newTypeList: typesList)
  }

  func typeChanged(newType: String) {
    if(selectedType == newType) { return }

    selectedType = newType
    do {
      try selectedType.write(toFile: typeFile, atomically: true, encoding: .utf8)
    } catch {
      // Ignore error
    }

    m3UDict    = allM3UDict[selectedType]!
    tracksDict = allTracksDict[selectedType]!
    musicPath  = rootPath + selectedType + "/"

    selectedArtist = ""
    selectedAlbum  = ""
    playerSelection.setAll(newArtist: "", newAlbum: "", newList: tracksDict.keys.sorted())
  }
}
