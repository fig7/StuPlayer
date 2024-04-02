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
let rootBookmark  = "RootBM.dat"
let rootTypesFile = "RootTypes.dat"

let m3UFile         = "Playlists.dat"
let trackFile       = "Tracks.dat"

typealias M3UDict   = [String : [String : String]]
typealias TrackDict = [String : [String : [String]]]

typealias AllM3UDict     = [String : M3UDict]
typealias AllTracksDict  = [String : TrackDict]

typealias Playlists = [Playlist]

enum StoppingReason { case EndOfAudio, PlayAllPressed, StopPressed, TrackPressed, PreviousPressed, NextPressed, RestartPressed }
enum StorageError: Error { case BookmarkCreationFailed, TypesCreationFailed, DictionaryCreationFailed, ReadingTypesFailed }
enum TrackError:   Error { case ReadingTypesFailed, ReadingArtistsFailed, ReadingAlbumsFailed, MissingM3U }

@MainActor class PlayerDataModel : NSObject, AudioPlayer.Delegate, PlayerSelection.Delegate {
  var playerAlert: PlayerAlert
  var playerSelection: PlayerSelection

  let fm     = FileManager.default
  let player = AudioPlayer()

  let logManager      = LogFileManager()
  let playlistManager = PlaylistManager()

  var bmData: Data?
  var bmURL = URL(fileURLWithPath: "/")

  var rootPath    = "/"
  var musicPath   = "/"
  var trackErrors = false

  var allM3UDict: AllM3UDict       = [:]
  var allTracksDict: AllTracksDict = [:]

  var m3UDict: M3UDict      = [:]
  var tracksDict: TrackDict = [:]
  var typesList: [String]   = []

  var selectedType   = ""
  var selectedArtist = ""
  var selectedAlbum  = ""

  var playPosition = 0
  var nowPlaying   = false
  var stopReason   = StoppingReason.EndOfAudio

  var pendingTrack: Int?
  var currentTrack: TrackInfo?

  init(playerAlert: PlayerAlert, playerSelection: PlayerSelection) {
    self.playerAlert     = playerAlert
    self.playerSelection = playerSelection
    self.bmData          = PlayerDataModel.getBookmarkData()

    if let bmData = self.bmData {
      do {
        var isStale = false
        self.bmURL = try URL(resolvingBookmarkData: bmData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

        if(isStale) {
          self.bmData = try PlayerDataModel.refreshBookmarkData(bmURL: self.bmURL)
        }

        self.rootPath = self.bmURL.path(percentEncoded: false)
        self.logManager.setURL(baseURL: bmURL)
      } catch {
        self.bmData = nil
        self.bmURL  = URL(fileURLWithPath: "/")
        logManager.append(logCat: .LogInitError,   logMessage: "Error reading bookmark data")
        logManager.append(logCat: .LogThrownError, logMessage: "Bookmark error: " + error.localizedDescription)

        playerAlert.triggerAlert(alertMessage: "Error opening root folder. Check log file for details.")
        super.init()
        return
      }
    }

    do {
      try (self.selectedType, self.typesList) = PlayerDataModel.getTypes(typesFile: rootTypesFile)
    } catch {
      logManager.append(logCat: .LogInitError,   logMessage: "Error reading types")
      logManager.append(logCat: .LogThrownError, logMessage: "Types error: " + error.localizedDescription)
      
      playerAlert.triggerAlert(alertMessage: "Error reading types. Check log file for details.")
      super.init()
      return
    }

    // TODO: Handle errors occuring here
    self.allM3UDict    = PlayerDataModel.getM3UDict(m3UFile: m3UFile)
    self.allTracksDict = PlayerDataModel.getTrackDict(trackFile: trackFile)

    self.m3UDict    = allM3UDict[selectedType] ?? [:]
    self.tracksDict = allTracksDict[selectedType] ?? [:]
    self.musicPath  = rootPath + selectedType + "/"
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
        if(!nowPlaying) {
          logManager.append(logCat: .LogInfo, logMessage: "Now playing: true")
          nowPlaying = true
        }

        playPosition += 1
        currentTrack = playlistManager.nextTrack()
      }

      playerSelection.setTrack(newTrack: currentTrack!)
      playerSelection.setPlayingPosition(playPosition: playPosition, playTotal: playlistManager.trackCount)
      logManager.append(logCat: .LogInfo, logMessage: "Track playing: " + currentTrack!.trackURL.path(percentEncoded: false))

      let nextTrack = (repeatingTrack) ? currentTrack : playlistManager.peekNextTrack()
      if(nextTrack != nil) {
        do {
          try player.enqueue(nextTrack!.trackURL)
          logManager.append(logCat: .LogInfo, logMessage: "Track queued:  " + nextTrack!.trackURL.path(percentEncoded: false))
        } catch {
          logManager.append(logCat: .LogPlaybackError, logMessage: "Track enqueue failed for " + nextTrack!.trackURL.path(percentEncoded: false))
          logManager.append(logCat: .LogThrownError,   logMessage: "Enqueue error: " + error.localizedDescription)

          // Handle error somehow
        }
      }
    }
  }

  // Using audioPlayerPlaybackStateChanged to handle state changes and update UI
  nonisolated func audioPlayerPlaybackStateChanged(_ audioPlayer: AudioPlayer) {
    switch(audioPlayer.playbackState) {
    case AudioPlayer.PlaybackState.stopped:
      Task { @MainActor in
        logManager.append(logCat: .LogInfo, logMessage: "Player stopped: \(stopReason)\n")
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
        logManager.append(logCat: .LogInfo, logMessage: "Player playing")
        playerSelection.setPlaybackState(newPlaybackState: PlaybackState.Playing)
      }

    case AudioPlayer.PlaybackState.paused:
      Task { @MainActor in
        logManager.append(logCat: .LogInfo, logMessage: "Player paused")
        playerSelection.setPlaybackState(newPlaybackState: PlaybackState.Paused)
      }

    @unknown default:
      break
    }
  }

  nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: any Error) {
    Task { @MainActor in
      logManager.append(logCat: .LogPlaybackError, logMessage: error.localizedDescription)

      // Handle the error (stop or skip to next track, somehow!?)
      player.stop()
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
      // Handle error somehow
      return
    }

    let playlistFile = m3UDict[selectedArtist]![selectedAlbum]!
    let albumTracks  = tracksDict[selectedArtist]![selectedAlbum]!
    let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: selectedArtist + "/" + selectedAlbum + "/", numTracks: albumTracks.count)

    do {
      try playTracks(playlist: (playlistInfo, albumTracks), trackNum: itemIndex+1)
    } catch {
      bmURL.stopAccessingSecurityScopedResource()
      logManager.append(logCat: .LogPlaybackError, logMessage: "Play track failed for " + albumTracks[itemIndex])
      logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)

      // Handle error somehow
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
      throw SPError.URLAccess
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
      throw SPError.URLAccess
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
      throw SPError.URLAccess
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
    } catch SPError.URLAccess {
      logManager.append(throwType: "URLAccess", logMessage: "Play all failed to access URL")

      // Handle error somehow
    } catch {
      bmURL.stopAccessingSecurityScopedResource()
      logManager.append(logCat: .LogPlaybackError, logMessage: "Play all start failed")
      logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)

      // Handle error somehow
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
    logManager.append(logCat: .LogInfo, logMessage: "Queue cleared")

    let nextTrack = playlistManager.peekNextTrack()
    if(nextTrack != nil) {
      do {
        try player.enqueue(nextTrack!.trackURL)
        logManager.append(logCat: .LogInfo, logMessage: "Track queued:  " + nextTrack!.trackURL.path(percentEncoded: false))
      } catch {
        logManager.append(logCat: .LogPlaybackError, logMessage: "Track enqueue failed: " + nextTrack!.trackURL.path(percentEncoded: false))
        logManager.append(logCat: .LogThrownError,   logMessage: "Enqueue error: " + error.localizedDescription)

        // Handle error somehow
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
    logManager.append(logCat: .LogInfo, logMessage: "Queue cleared")

    let repeatingTrack = (playerSelection.repeatTracks == RepeatState.Track)
    let nextTrack = (repeatingTrack) ? currentTrack : playlistManager.peekNextTrack()
    if(nextTrack != nil) {
      do {
        try player.enqueue(nextTrack!.trackURL)
        logManager.append(logCat: .LogInfo, logMessage: "Track queued:  " + nextTrack!.trackURL.path(percentEncoded: false))
      } catch {
        logManager.append(logCat: .LogPlaybackError, logMessage: "Track enqueue failed: " + nextTrack!.trackURL.path(percentEncoded: false))
        logManager.append(logCat: .LogThrownError,   logMessage: "Enqueue error: " + error.localizedDescription)

        // Handle error somehow
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

  static func getTypes(typesFile: String) throws -> (String, [String]) {
    let typesData = NSData(contentsOfFile: typesFile) as Data?
    guard let typesData else {
      return ("", [])
    }

    let typesStr   = String(decoding: typesData, as: UTF8.self)
    let typesSplit = typesStr.split(whereSeparator: \.isNewline)
    switch(typesSplit.count) {
    case 0:
      return ("", [])

    case 1:
      // Unexpected (there should be no entries or >= 2 entries)
      throw StorageError.ReadingTypesFailed

    default:
      return (String(typesSplit[0]), typesSplit.dropFirst().map(String.init))
    }
  }

  static func getBookmarkData() -> Data? {
    return NSData(contentsOfFile: rootBookmark) as Data?
  }

  static func refreshBookmarkData(bmURL: URL) throws -> Data? {
    let fm = FileManager.default

    let bmData = try bmURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    if(!fm.createFile(atPath: rootBookmark, contents: bmData, attributes: nil)) {
      throw StorageError.BookmarkCreationFailed
    }

    return bmData
  }

  func reconfigureRoot(rootURL: URL) {
    stopAll()

    var newBMData: Data?
    do {
      newBMData = try rootURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
      if(!fm.createFile(atPath: rootBookmark, contents: newBMData, attributes: nil)) {
        throw StorageError.BookmarkCreationFailed
      }
    } catch {
      playerAlert.triggerAlert(alertMessage: "Setting root folder failed")
      return
    }

    // Update stored data
    bmData = newBMData

    // Update URL and path
    bmURL    = rootURL
    rootPath = rootURL.path(percentEncoded: false)

    logManager.setURL(baseURL: bmURL)
    playerSelection.setRootPath(newRootPath: self.rootPath)

    // Scan folders
    scanFolders()
  }

  func setRootFolder() {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories    = true
    openPanel.canCreateDirectories    = false
    openPanel.canChooseFiles          = false

    openPanel.directoryURL = URL(fileURLWithPath: "/")
    openPanel.prompt       = "Grant Access"

    openPanel.begin { [weak self] result in
      guard let self else { return }
      guard (result == .OK), let url = openPanel.url else {
        if((result == .OK) && (openPanel.url == nil)) {
          playerAlert.triggerAlert(alertMessage: "Invalid folder selected")
        }

        return
      }

      self.reconfigureRoot(rootURL: url)
    }
  }

  func scanM3U(m3UPath: String) -> [String] {
    let m3UData = NSData(contentsOfFile: m3UPath) as Data?
    guard let m3UData else {
      trackErrors = true
      logManager.append(logCat: .LogScanError, logMessage: "Nil data for " + m3UPath)
      return []
    }

    let m3UStr = String(data: m3UData, encoding: .utf8)
    guard let m3UStr else {
      trackErrors = true
      logManager.append(logCat: .LogScanError, logMessage: "Nil string for " + m3UPath)
      return []
    }

    var tracks = m3UStr.split(whereSeparator: \.isNewline).map(String.init)
    tracks.indices.forEach {
      tracks[$0] = tracks[$0].trimmingCharacters(in: .whitespaces)
    }

    return tracks.filter { track in
      return !track.starts(with: "#")
    }
  }

  func scanAlbum(albumPath: String) -> (String, [String]) {
    var m3U = ""
    var tracks: [String] = []

    do {
      let files = try fm.contentsOfDirectory(atPath: albumPath)

      var m3UFound = false
      for file in files {
        if(file.hasSuffix(".m3u")) {
          if(m3UFound) {
            trackErrors = true
            logManager.append(logCat: .LogScanError,   logMessage: "Skipping " + file + "for: " + albumPath)
            continue
          }

          m3U      = file
          tracks   = scanM3U(m3UPath: albumPath + file)
          m3UFound = true
        }
      }

      if(!m3UFound) {
        trackErrors = true
        logManager.append(logCat: .LogScanError,   logMessage: "Missing m3U for: " + albumPath)
      }
    } catch {
      trackErrors = true
      logManager.append(logCat: .LogScanError,   logMessage: "Scanning album: " + albumPath + " failed")
      logManager.append(logCat: .LogThrownError, logMessage: "Scan error: " + error.localizedDescription)
    }

    return (m3U, tracks)
  }

  func scanAlbums(artistPath: String) -> (m3Us: [String : String], tracks: [String : [String]]) {
    var m3Us: [String : String] = [:]
    var tracks: [String : [String]] = [:]

    do {
      let albums = try fm.contentsOfDirectory(atPath: artistPath)
      for album in albums {
        let filePath = artistPath + album

        var isDir: ObjCBool = false
        if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
          (m3Us[album], tracks[album]) = scanAlbum(albumPath: filePath + "/")
        }
      }
    } catch {
      trackErrors = true
      logManager.append(logCat: .LogScanError,   logMessage: "Scanning artist: " + artistPath + " failed")
      logManager.append(logCat: .LogThrownError, logMessage: "Scan error: " + error.localizedDescription)
    }

    return (m3Us, tracks)
  }

  func saveTypes() throws {
    let joinedTypes = selectedType + "\n" + typesList.joined(separator: "\n")
    try joinedTypes.write(toFile: rootTypesFile, atomically: true, encoding: .utf8)
  }

  func scanTypes() throws {
    typesList.removeAll()
    selectedType = ""

    do {
      let types = try fm.contentsOfDirectory(atPath: rootPath)
      for type in types {
        let filePath = rootPath + type

        var isDir: ObjCBool = false
        if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
          typesList.append(type)
        }
      }

      typesList.sort()
      if(typesList.count > 0) {
        selectedType = typesList[0]
      }

      try saveTypes()
    } catch {
      logManager.append(logCat: .LogScanError,   logMessage: "Updating types failed")
      logManager.append(logCat: .LogThrownError, logMessage: "Scan error: " + error.localizedDescription)
      throw StorageError.TypesCreationFailed
    }
  }

  func saveDicts() throws {
    do {
      let data1 = try PropertyListEncoder().encode(allM3UDict)
      try data1.write(to: URL(fileURLWithPath: m3UFile))

      let data2 = try PropertyListEncoder().encode(allTracksDict)
      try data2.write(to: URL(fileURLWithPath: trackFile))
    } catch {
      logManager.append(logCat: .LogScanError,   logMessage: "Saving tracks failed")
      logManager.append(logCat: .LogThrownError, logMessage: "Scan error: " + error.localizedDescription)
      throw StorageError.DictionaryCreationFailed
    }
  }

  func scanArtists() throws {
    trackErrors = false
    for type in typesList {
      let artistDict = scanArtists(typePath: rootPath + type + "/")

      allM3UDict[type]    = artistDict.m3Us
      allTracksDict[type] = artistDict.tracks
    }

    if(trackErrors) {
      throw TrackError.ReadingArtistsFailed
    }
  }

  func scanArtists(typePath: String) -> (m3Us: M3UDict, tracks: TrackDict) {
    var m3Us: M3UDict = [:]
    var tracks: TrackDict = [:]

    do {
      let artists = try fm.contentsOfDirectory(atPath: typePath)

      // Make a dictionary for each one and write it out
      for artist in artists {
        let filePath = typePath + artist

        var isDir: ObjCBool = false
        if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
          (m3Us[artist], tracks[artist]) = scanAlbums(artistPath: filePath + "/")
        }
      }
    } catch {
      trackErrors = true
      logManager.append(logCat: .LogScanError,   logMessage: "Scanning type: " + typePath + " failed")
      logManager.append(logCat: .LogThrownError, logMessage: "Scan error: " + error.localizedDescription)
    }

    return (m3Us, tracks)
  }

  func scanFolders() {
    guard bmData != nil else { return }

    if(!bmURL.startAccessingSecurityScopedResource()) {
      playerAlert.triggerAlert(alertMessage: "Unable to scan folders: access denied")
      return
    }
    defer { bmURL.stopAccessingSecurityScopedResource() }

    allM3UDict.removeAll()
    allTracksDict.removeAll()

    var scanError = ""
    do {
      try scanTypes()
      try scanArtists()
    } catch {
      scanError += "Errors found while scanning. "
    }

    do {
      try saveDicts()
    } catch {
      scanError += "Error saving tracks. "
    }

    selectedArtist = ""
    selectedAlbum  = ""

    m3UDict    = allM3UDict[selectedType]!
    tracksDict = allTracksDict[selectedType]!
    musicPath  = rootPath + selectedType + "/"

    playerSelection.setAll(newArtist: selectedArtist, newAlbum: selectedAlbum, newList: tracksDict.keys.sorted())
    playerSelection.setTypes(newType: selectedType, newTypeList: typesList)

    if(!scanError.isEmpty) {
      scanError += "Check log file for details."
      playerAlert.triggerAlert(alertMessage: scanError)
    }
  }

  func typeChanged(newType: String) {
    if(selectedType == newType) { return }

    do {
      selectedType = newType
      try saveTypes()
    } catch {
      // Ignore error
      // (it's not critical)
    }

    m3UDict      = allM3UDict[selectedType]!
    tracksDict   = allTracksDict[selectedType]!
    musicPath    = rootPath + selectedType + "/"

    selectedArtist = ""
    selectedAlbum  = ""
    playerSelection.setAll(newArtist: "", newAlbum: "", newList: tracksDict.keys.sorted())
  }
}
