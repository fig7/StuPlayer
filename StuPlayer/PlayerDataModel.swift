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

enum StoppingReason { case EndOfAudio, PlayAllPressed, StopPressed, TrackPressed, PreviousPressed, NextPressed, RestartPressed }

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

  var playPosition: Int
  var nowPlaying: Bool

  var stopReason: StoppingReason
  var pendingTrack: Int?

  var playlistManager: PlaylistManager
  var currentTrack: TrackInfo?

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

    self.m3UDict    = allM3UDict[selectedType] ?? [:]
    self.tracksDict = allTracksDict[selectedType] ?? [:]
    self.musicPath  = rootPath + selectedType + "/"

    self.selectedArtist = ""
    self.selectedAlbum  = ""

    self.playPosition = 0
    self.nowPlaying   = false
    self.stopReason   = StoppingReason.EndOfAudio

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
      let repeatingTrack = (playerSelection.repeatTracks == RepeatState.Track)
      if(!nowPlaying || !repeatingTrack) {
        playPosition += 1
        currentTrack = playlistManager.nextTrack()
      }

      playerSelection.setTrack(newTrack: currentTrack!)
      playerSelection.setPlayingPosition(playPosition: playPosition, playTotal: playlistManager.trackCount)

      let nextTrack = (repeatingTrack) ? currentTrack : playlistManager.peekNextTrack()
      if(nextTrack != nil) {
        try player.enqueue(nextTrack!.trackURL)
      }

      nowPlaying = true
    }
  }

  // Using audioPlayerPlaybackStateChanged to handle state changes and update UI
  nonisolated func audioPlayerPlaybackStateChanged(_ audioPlayer: AudioPlayer) {
    switch(audioPlayer.playbackState) {
    case AudioPlayer.PlaybackState.stopped:
      Task { @MainActor in
        nowPlaying = false

        switch(stopReason) {
        case .EndOfAudio:
          playPosition = 0
          if(playerSelection.repeatTracks == RepeatState.All) {
            playlistManager.reset(shuffleTracks: playerSelection.shuffleTracks)

            let firstTrack = playlistManager.peekNextTrack()
            try player.play(firstTrack!.trackURL)
          } else {
            bmURL.stopAccessingSecurityScopedResource()

            playerSelection.setPlayingPosition(playPosition: 0, playTotal: 0)
            playerSelection.setTrack(newTrack: nil)

            playerSelection.setPlaybackState(newPlaybackState: PlaybackState.Stopped)
          }

        case .PlayAllPressed:
          playPosition = 0
          playAll()

        case .StopPressed:
          playPosition = 0
          bmURL.stopAccessingSecurityScopedResource()

          playerSelection.setPlayingPosition(playPosition: 0, playTotal: 0)
          playerSelection.setTrack(newTrack: nil)

          playerSelection.setPlaybackState(newPlaybackState: PlaybackState.Stopped)

        case .TrackPressed:
          playPosition = 0
          let playlistFile = m3UDict[selectedArtist]![selectedAlbum]!
          let albumTracks = tracksDict[selectedArtist]![selectedAlbum]!

          let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: selectedArtist + "/" + selectedAlbum + "/", numTracks: albumTracks.count)
          try playTracks(playlist: Playlist(playlistInfo, albumTracks), trackNum: pendingTrack!)
          pendingTrack = nil

        case .PreviousPressed:
          playPosition -= 2
          let previousTrack = playlistManager.moveTo(trackNum: playPosition+1)
          try player.play(previousTrack!.trackURL)

        case .NextPressed:
          var nextTrackNum = playPosition+1
          if(nextTrackNum > playlistManager.trackCount) {
            nextTrackNum = 1
            playPosition = 0
          }

          let nextTrack = playlistManager.moveTo(trackNum: nextTrackNum)
          try player.play(nextTrack!.trackURL)

        case .RestartPressed:
          playPosition = 0
          playlistManager.reset(shuffleTracks: playerSelection.shuffleTracks)

          let firstTrack = playlistManager.peekNextTrack()
          try player.play(firstTrack!.trackURL)
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

  func itemSelected(itemIndex: Int, itemText: String) {
    if(selectedArtist.isEmpty) {
      selectedArtist = itemText
      playerSelection.setArtist(newArtist: selectedArtist, newList: tracksDict[selectedArtist]!.keys.sorted())
      return
    }

    if(selectedAlbum.isEmpty) {
      selectedAlbum = itemText
      playerSelection.setAlbum(newAlbum: selectedAlbum, newList: tracksDict[selectedArtist]![selectedAlbum]!)
      return
    }

    if(player.isPlaying) {
      pendingTrack = itemIndex+1
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

    let playlistFile = m3UDict[selectedArtist]![selectedAlbum]!
    let albumTracks  = tracksDict[selectedArtist]![selectedAlbum]!
    let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: selectedArtist + "/" + selectedAlbum + "/", numTracks: albumTracks.count)

    do {
      try playTracks(playlist: (playlistInfo, albumTracks), trackNum: itemIndex+1)
    } catch {
      // Handle error
    }
  }

  func configurePlayback(playlist: Playlist, trackNum: Int) {
    let shuffleTracks = playerSelection.shuffleTracks
    playlistManager.setMusicPath(musicPath: musicPath)
    playlistManager.generatePlaylist(playlist: playlist, trackNum: trackNum, shuffleTracks: shuffleTracks)

    playPosition = (shuffleTracks) ? 0 : trackNum-1
    stopReason   = StoppingReason.EndOfAudio
  }

  func configurePlayback(playlists: Playlists) {
    let shuffleTracks = playerSelection.shuffleTracks
    playlistManager.setMusicPath(musicPath: musicPath)
    playlistManager.generatePlaylist(playlists: playlists, shuffleTracks: shuffleTracks)

    playPosition = 0
    stopReason   = StoppingReason.EndOfAudio
  }

  func playTracks(playlist: Playlist, trackNum: Int) throws {
    configurePlayback(playlist: playlist, trackNum: trackNum)

    let firstTrack = playlistManager.peekNextTrack()
    try player.play(firstTrack!.trackURL)
  }

  func playTracks(playlists: Playlists) throws {
    configurePlayback(playlists: playlists)

    let firstTrack = playlistManager.peekNextTrack()
    try player.play(firstTrack!.trackURL)
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
    // Can't play if we haven't got the root folder
    guard bmData != nil else { return }

    if(player.isPlaying) {
      stopReason = StoppingReason.PlayAllPressed
      player.stop()
      return
    }

    do {
      if(selectedArtist.isEmpty && !tracksDict.isEmpty) {
        try playAllArtists()
        return
      }

      if(selectedAlbum.isEmpty && !tracksDict[selectedArtist]!.isEmpty) {
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

  func playPreviousTrack() {
    if(!player.isPlaying) { return }
    if(!playlistManager.hasPrevious(trackNum: playPosition)) { return }

    stopReason = StoppingReason.PreviousPressed
    player.stop()
  }

  func playNextTrack() {
    if(!player.isPlaying) { return }
    if(!playlistManager.hasNext(trackNum: playPosition)) {
      stopReason = StoppingReason.EndOfAudio
      player.stop()

      return
    }

    stopReason = StoppingReason.NextPressed
    player.stop()
  }

  func restartAll() {
    if(!player.isPlaying) { return }

    stopReason = StoppingReason.RestartPressed
    player.stop()
  }

  func togglePause() {
    let playing = (playerSelection.playbackState == PlaybackState.Playing)
    let paused  = (playerSelection.playbackState == PlaybackState.Paused)
    if(playing || paused) {
      if(playing) {
        player.pause()
      } else {
        player.resume()
      }
    }
  }

  func toggleShuffle() {
    playerSelection.toggleShuffle()
    if(!player.isPlaying) { return }

    // Inform the playlist manager
    playPosition = playlistManager.shuffleChanged(shuffleTracks: playerSelection.shuffleTracks)
    playerSelection.setPlayingPosition(playPosition: playPosition, playTotal: playlistManager.trackCount)

    // Toggling shuffle when repeating the current track has no further effects
    if(playerSelection.repeatTracks == RepeatState.Track) {
      return
    }

    // Re-queue tracks
    player.clearQueue()
    let nextTrack = playlistManager.peekNextTrack()
    if(nextTrack != nil) {
      do {
        try player.enqueue(nextTrack!.trackURL)
      } catch {
        // Handle error
      }
    }
  }

  func toggleRepeat() {
    // Toggling from repeat all to none has no effect (the next track remains queued)
    // Toggling from repeat none to track clears the queue and re-queues the current track
    // Toggling from repeat track to all clears the queue and queues the next track

    let repeatAll = (playerSelection.repeatTracks == RepeatState.All)
    playerSelection.toggleRepeatTracks()

    if(!player.isPlaying || repeatAll) { return }
    player.clearQueue()

    let repeatingTrack = (playerSelection.repeatTracks == RepeatState.Track)
    let nextTrack = (repeatingTrack) ? currentTrack : playlistManager.peekNextTrack()
    if(nextTrack != nil) {
      do {
        try player.enqueue(nextTrack!.trackURL)
      } catch {
        // Handle error
      }
    }
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

        if let bmData = self.bmData {
          do {
            var isStale = false
            self.bmURL = try URL(resolvingBookmarkData: bmData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

            // TODO: Handle stale bmData
          } catch {
            // Handle error
          }
        }

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
