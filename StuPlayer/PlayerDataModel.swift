//
//  PlayerDataModel.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import Foundation
import AppKit
import SFBAudioEngine

// Type aliases
typealias M3UDict   = [String : [String : String]]
typealias TrackDict = [String : [String : [String]]]

typealias AllM3UDict     = [String : M3UDict]
typealias AllTracksDict  = [String : TrackDict]

typealias Playlists = [Playlist]

// Enumerations
enum StoppingReason { case PlaybackError, EndOfAudio, PlayAllPressed, StopPressed, TrackPressed, PlayingTrackPressed, PreviousPressed, NextPressed, RestartPressed, ReshufflePressed }
enum StorageError: Error { case BookmarkCreationFailed, TypesCreationFailed, DictionaryCreationFailed, ReadingTypesFailed }
enum TrackError:   Error { case ReadingTypesFailed, ReadingArtistsFailed, ReadingAlbumsFailed, MissingM3U }

// Local storage paths
let rootBookmark  = "RootBM.dat"
let rootTypesFile = "RootTypes.dat"

let m3UFile         = "Playlists.dat"
let trackFile       = "Tracks.dat"

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

  var filteredArtist = ""
  var filteredAlbum  = ""

  var filteredAlbums: [(artist: String, album: String)] = []
  var filteredTracks: [(artist: String, album: String, track: String)] = []

  var playPosition = 0
  var nowPlaying   = false
  var stopReason   = StoppingReason.EndOfAudio

  var pendingTrack: Int?
  var currentTrack: TrackInfo?

  var playbackTimer: Timer?
  var delayTask: Task<Void, Never>?

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

        self.rootPath = self.bmURL.filePath()
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
      playerAlert.triggerAlert(alertMessage: "Error loading types. Check log file for details.")

      super.init()
      return
    }

    do {
      self.allM3UDict = try PlayerDataModel.getM3UDict(m3UFile: m3UFile)
      if(allM3UDict.isEmpty) {
        logManager.append(logCat: .LogInitError, logMessage: "Empty M3UDict (missing or file error?)")
      }
    } catch {
      logManager.append(logCat: .LogInitError,   logMessage: "Error reading m3u dictionary")
      logManager.append(logCat: .LogThrownError, logMessage: "M3U error: " + error.localizedDescription)
      playerAlert.triggerAlert(alertMessage: "Error loading m3u data. Check log file for details.")

      super.init()
      return
    }

    do {
      self.allTracksDict = try PlayerDataModel.getTrackDict(trackFile: trackFile)
      if(allTracksDict.isEmpty) {
        logManager.append(logCat: .LogInitError, logMessage: "Empty TracksDict (missing or file error?)")
      }
    } catch {
      logManager.append(logCat: .LogInitError,   logMessage: "Error reading tracks dictionary")
      logManager.append(logCat: .LogThrownError, logMessage: "Tracks error: " + error.localizedDescription)
      playerAlert.triggerAlert(alertMessage: "Error loading tracks data. Check log file for details.")

      super.init()
      return
    }

    self.m3UDict    = allM3UDict[selectedType] ?? [:]
    self.tracksDict = allTracksDict[selectedType] ?? [:]
    self.musicPath  = rootPath + selectedType + "/"

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

#if !PLAYBACK_TEST
  // Using audioPlayerNowPlayingChanged to handle track changes
  // NB. nowPlaying -> nil is ignored, audioPlayerPlaybackStateChanged() handles end of audio instead (playbackState -> Stopped)
  nonisolated func audioPlayerNowPlayingChanged(_ audioPlayer: AudioPlayer) {
    if(audioPlayer.nowPlaying == nil) { return }

    Task { @MainActor in
      handleNextTrack()
    }
  }

  nonisolated func audioPlayerPlaybackStateChanged(_ audioPlayer: AudioPlayer) {
    Task { @MainActor in
      handlePlaybackStateChange()
    }
  }

  nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: any Error) {
    Task { @MainActor in
      handlePlaybackError(error.localizedDescription)
    }
  }
  #endif

  func handleNextTrack() {
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
    playerSelection.setSeekEnabled(seekEnabled: player.supportsSeeking)
    playerSelection.setPlayingPosition(playPosition: playPosition, playTotal: playlistManager.trackCount)
    playerSelection.setPlayingInfo()

    logManager.append(logCat: .LogInfo, logMessage: "Track playing: " + currentTrack!.trackURL.filePath())

    let nextTrack = (repeatingTrack) ? currentTrack : playlistManager.peekNextTrack()
    if(nextTrack != nil) {
      let trackURL  = nextTrack!.trackURL
      let trackPath = trackURL.filePath()

      do {
        try player.enqueue(trackURL)
        logManager.append(logCat: .LogInfo, logMessage: "Track queued:  " + trackPath)
      } catch {
        logManager.append(logCat: .LogPlaybackError, logMessage: "Track enqueue failed for " + trackPath)
        logManager.append(logCat: .LogThrownError,   logMessage: "Enqueue error: " + error.localizedDescription)

        // Undefined error: 0 isn't very helpful (it's probably a missing file)
        // So, check that here and add a log entry if the file is AWOL
        if(!fm.fileExists(atPath: trackPath)) {
          logManager.append(logCat: .LogFileError, logMessage: trackPath + " is missing!")
        }

        playerAlert.triggerAlert(alertMessage: "Error queueing next track. The current track will finish playing. Check log file for details.")
      }
    }
  }

  func handlePlaybackStateChange() {
    let playbackState = player.playbackState
    switch(playbackState) {
    case .stopped:
      logManager.append(logCat: .LogInfo, logMessage: "Player stopped: \(stopReason)\n")

      playbackTimer?.invalidate()
      playbackTimer = nil
      nowPlaying = false

      switch(stopReason) {
      case .PlaybackError:
        playPosition = 0

        playerSelection.setTrack(newTrack: nil)
        playerSelection.setPlayingPosition(playPosition: 0, playTotal: 0)
        playerSelection.setPlaybackState(newPlaybackState: .stopped)
        playerSelection.setPlayingInfo()

        bmURL.stopAccessingSecurityScopedResource()
        playerAlert.triggerAlert(alertMessage: "A playback error occurred. Check log file for details.")

      case .EndOfAudio:
        playPosition = 0

        if(playerSelection.repeatTracks == RepeatState.All) {
          playlistManager.reset(shuffleTracks: playerSelection.shuffleTracks)
          let firstTrack = playlistManager.peekNextTrack()

          let trackURL   = firstTrack!.trackURL
          let trackPath  = trackURL.filePath()

          do {
            try player.play(trackURL)
            logManager.append(logCat: .LogInfo, logMessage: "Repeat all: Starting playback of " + trackPath)
            return
          } catch {
            logManager.append(logCat: .LogPlaybackError, logMessage: "Repeat all: Playback of " + trackPath + " failed")
            logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)
            playerAlert.triggerAlert(alertMessage: "Error repeating tracks. Check log file for details.")
          }
        }

        playerSelection.setTrack(newTrack: nil)
        playerSelection.setPlayingPosition(playPosition: 0, playTotal: 0)
        playerSelection.setPlaybackState(newPlaybackState: .stopped)
        playerSelection.setPlayingInfo()

        bmURL.stopAccessingSecurityScopedResource()

      case .PlayAllPressed:
        playPosition = 0

        playAll()

      case .StopPressed:
        playPosition = 0

        playerSelection.setTrack(newTrack: nil)
        playerSelection.setPlayingPosition(playPosition: 0, playTotal: 0)
        playerSelection.setPlaybackState(newPlaybackState: .stopped)
        playerSelection.setPlayingInfo()

        bmURL.stopAccessingSecurityScopedResource()

      case .TrackPressed:
        playPosition = 0

        let album = playerSelection.album
        if(album.hasPrefix("from filter")) {
          // Filtered tracks
          var playlists = Playlists()
          for artistAlbumAndTrack in filteredTracks {
            let artist = artistAlbumAndTrack.artist
            let album  = artistAlbumAndTrack.album

            let playlistFile = m3UDict[artist]![album]!
            let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: artist + "/" + album + "/", numTracks: 1)
            playlists.append(Playlist(playlistInfo: playlistInfo, tracks: [artistAlbumAndTrack.track]))
          }

          playTracks(playlists: playlists, trackNum: pendingTrack!)
          break
        }

        var artist = playerSelection.artist
        if(artist.hasPrefix("from filter")) {
          let start = artist.index(artist.startIndex, offsetBy: 13)
          artist.removeSubrange(artist.startIndex..<start)

          let end = artist.index(artist.endIndex, offsetBy: -1)
          artist.removeSubrange(end..<artist.endIndex)
        }

        let playlistFile = m3UDict[artist]![album]!
        let albumTracks  = tracksDict[artist]![album]!

        let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: artist + "/" + album + "/", numTracks: albumTracks.count)
        playTracks(playlists: [Playlist(playlistInfo: playlistInfo, tracks: albumTracks)], trackNum: pendingTrack!)
        pendingTrack = nil

      case .PlayingTrackPressed:
        playPosition = pendingTrack!

        let newTrack = playlistManager.moveTo(trackNum: playPosition+1)
        let trackURL      = newTrack!.trackURL
        let trackPath     = trackURL.filePath()

        do {
          try player.play(trackURL)
          logManager.append(logCat: .LogInfo, logMessage: "Playing track: Starting playback of " + trackPath)
        } catch {
          logManager.append(logCat: .LogPlaybackError, logMessage: "Playing track: Playback of " + trackPath + " failed")
          logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)
          playerAlert.triggerAlert(alertMessage: "Error playing track. Check log file for details.")
        }

      case .PreviousPressed:
        playPosition -= 2

        let previousTrack = playlistManager.moveTo(trackNum: playPosition+1)
        let trackURL      = previousTrack!.trackURL
        let trackPath     = trackURL.filePath()

        do {
          try player.play(trackURL)
          logManager.append(logCat: .LogInfo, logMessage: "Previous track: Starting playback of " + trackPath)
        } catch {
          logManager.append(logCat: .LogPlaybackError, logMessage: "Previous track: Playback of " + trackPath + " failed")
          logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)
          playerAlert.triggerAlert(alertMessage: "Error playing previous track. Check log file for details.")
        }

      case .NextPressed:
        let nextTrackNum = playPosition+1
        if(nextTrackNum > playlistManager.trackCount) {
          playPosition = 0
        }

        let nextTrack  = playlistManager.moveTo(trackNum: playPosition+1)
        let trackURL   = nextTrack!.trackURL
        let trackPath  = trackURL.filePath()

        do {
          try player.play(trackURL)
          logManager.append(logCat: .LogInfo, logMessage: "Next track: Starting playback of " + trackPath)
        } catch {
          logManager.append(logCat: .LogPlaybackError, logMessage: "Next track: Playback of " + trackPath + " failed")
          logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)
          playerAlert.triggerAlert(alertMessage: "Error playing next track. Check log file for details.")
        }

      case .RestartPressed:
        playPosition = 0

        playlistManager.reset()
        let firstTrack = playlistManager.peekNextTrack()

        let trackURL   = firstTrack!.trackURL
        let trackPath  = trackURL.filePath()

        do {
          try player.play(trackURL)
          logManager.append(logCat: .LogInfo, logMessage: "Restart: Starting playback of " + trackPath)
        } catch {
          logManager.append(logCat: .LogPlaybackError, logMessage: "Restart: Playback of " + trackPath + " failed")
          logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)
          playerAlert.triggerAlert(alertMessage: "Error restarting tracks. Check log file for details.")
        }

      case .ReshufflePressed:
        // Get info for the selected track
        var selectedTrack: TrackInfo? = nil
        if(playerSelection.playingScrollPos >= 0) { selectedTrack = playlistManager.trackAt(position: playerSelection.playingScrollPos) }

        // Reshuffle the tracks
        playPosition = 0
        playlistManager.reset(shuffleTracks: true)
        refreshPlayingTracks()

        // Stay on the same track
        if(selectedTrack != nil) {
          playerSelection.playingScrollPos = playlistManager.indexFor(track: selectedTrack!)
          playerSelection.searchIndex      = playerSelection.playingScrollPos
        }

        // Restart playback
        let firstTrack = playlistManager.peekNextTrack()
        let trackURL   = firstTrack!.trackURL
        let trackPath  = trackURL.filePath()

        do {
          try player.play(trackURL)
          logManager.append(logCat: .LogInfo, logMessage: "Reshuffle: Starting playback of " + trackPath)
        } catch {
          logManager.append(logCat: .LogPlaybackError, logMessage: "Reshuffle: Playback of " + trackPath + " failed")
          logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)
          playerAlert.triggerAlert(alertMessage: "Error reshuffling tracks. Check log file for details.")
        }
      }

      stopReason = StoppingReason.EndOfAudio

    case .paused:
      playbackTimer?.invalidate()
      playbackTimer = nil

      logManager.append(logCat: .LogInfo, logMessage: "Player paused")
      playerSelection.setPlaybackState(newPlaybackState: .paused)

    case .playing:
      updatePlayingPosition()

      logManager.append(logCat: .LogInfo, logMessage: "Player playing")
      playerSelection.setPlaybackState(newPlaybackState: .playing)

    @unknown default:
      logManager.append(logCat: .LogInfo, logMessage: "Unknown player state received: \(playbackState)")
    }
  }

  func handlePlaybackError(_ playbackError: String) {
    stopReason = StoppingReason.PlaybackError
    player.stop()

    logManager.append(logCat: .LogPlaybackError, logMessage: playbackError)
  }

  func clearFilteredArtist() {
    if(filteredArtist.isEmpty) { return }
    filteredArtist = ""

    let artistList = artists(filteredBy: playerSelection.filterString)
    playerSelection.setArtist(newArtist: "", newList: artistList);
  }

  func artistClicked() {
    playerSelection.browserScrollPos = -1
    clearArtist()
  }

  func clearArtist() {
    if(!playerSelection.filterString.isEmpty) {
      clearFilteredArtist()
      return
    }

    if(selectedArtist.isEmpty) { return }
    selectedArtist = ""
    selectedAlbum  = ""

    let artistList = tracksDict.keys.sorted()
    playerSelection.setArtist(newArtist: "", newList: artistList)
  }

  func clearFilteredAlbum() {
    if(filteredAlbum.isEmpty) { return }
    filteredAlbum = ""

    var albumList: [String] = []
    if(playerSelection.filterMode == .Artist) {
      albumList = tracksDict[filteredArtist]!.keys.sorted()
    } else {
      for artistAndAlbum in filteredAlbums {
        albumList.append(artistAndAlbum.album)
      }
    }

    playerSelection.setAlbum(newAlbum: "", newList: albumList);
  }

  func albumClicked() {
    playerSelection.browserScrollPos = -1
    clearAlbum()
  }

  func clearAlbum() {
    if(!playerSelection.filterString.isEmpty) {
      clearFilteredAlbum()
      return
    }

    if(selectedAlbum.isEmpty) { return }
    selectedAlbum = ""

    let albumList = tracksDict[selectedArtist]!.keys.sorted()
    playerSelection.setAlbum(newAlbum: "", newList: albumList)
  }

  func artistFilterItemSelected(itemIndex: Int, itemText: String) {
    if(filteredArtist.isEmpty) {
      filteredArtist = itemText

      let albumList = tracksDict[filteredArtist]!.keys.sorted()
      playerSelection.setArtist(newArtist: filteredArtist, newList: albumList)
      return
    }

    if(filteredAlbum.isEmpty) {
      filteredAlbum = itemText

      let trackList = tracksDict[filteredArtist]![filteredAlbum]!
      playerSelection.setAlbum(newAlbum: filteredAlbum, newList: trackList)
      return
    }

    // Track selected, play it
    if(player.isPlaying) {
      pendingTrack = itemIndex+1
      stopReason   = StoppingReason.TrackPressed

      player.stop()
      return
    }

    // Can't play if we haven't got the root folder
    guard bmData != nil else { return }

    if(!bmURL.startAccessingSecurityScopedResource()) {
      logManager.append(throwType: "URLAccess", logMessage: "Play track failed to access: " + bmURL.filePath())
      playerAlert.triggerAlert(alertMessage: "Unable to play: Access denied. Check log file for details.")
      return
    }

    let playlistFile = m3UDict[filteredArtist]![filteredAlbum]!
    let albumTracks  = tracksDict[filteredArtist]![filteredAlbum]!
    let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: filteredArtist + "/" + filteredAlbum + "/", numTracks: albumTracks.count)
    playTracks(playlists: [Playlist(playlistInfo: playlistInfo, tracks: albumTracks)], trackNum: itemIndex+1)
  }

  func albumFilterItemSelected(itemIndex: Int, itemText: String) {
    if(filteredAlbum.isEmpty) {
      let artistAndAlbum = filteredAlbums[itemIndex]
      let artist = artistAndAlbum.artist
      let album  = artistAndAlbum.album

      filteredArtist = "from filter (\(artist))"
      filteredAlbum  = album

      let trackList = tracksDict[artist]![album]!
      playerSelection.setAll(newArtist: filteredArtist, newAlbum: filteredAlbum, newList: trackList)
      return
    }

    // Track selected, play it
    if(player.isPlaying) {
      pendingTrack = itemIndex+1
      stopReason   = StoppingReason.TrackPressed

      player.stop()
      return
    }

    // Can't play if we haven't got the root folder
    guard bmData != nil else { return }

    if(!bmURL.startAccessingSecurityScopedResource()) {
      logManager.append(throwType: "URLAccess", logMessage: "Play track failed to access: " + bmURL.filePath())
      playerAlert.triggerAlert(alertMessage: "Unable to play: Access denied. Check log file for details.")
      return
    }

    var artist = filteredArtist
    let start = artist.index(artist.startIndex, offsetBy: 13)
    artist.removeSubrange(artist.startIndex..<start)

    let end = artist.index(artist.endIndex, offsetBy: -1)
    artist.removeSubrange(end..<artist.endIndex)

    let album = filteredAlbum
    let playlistFile = m3UDict[artist]![album]!
    let albumTracks  = tracksDict[artist]![album]!
    let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: artist + "/" + album + "/", numTracks: albumTracks.count)
    playTracks(playlists: [Playlist(playlistInfo: playlistInfo, tracks: albumTracks)], trackNum: itemIndex+1)
  }

  func trackFilterItemSelected(itemIndex: Int, itemText: String) {
    // Track selected, play it
    if(player.isPlaying) {
      pendingTrack = itemIndex+1
      stopReason   = StoppingReason.TrackPressed

      player.stop()
      return
    }

    // Can't play if we haven't got the root folder
    guard bmData != nil else { return }

    if(!bmURL.startAccessingSecurityScopedResource()) {
      logManager.append(throwType: "URLAccess", logMessage: "Play track failed to access: " + bmURL.filePath())
      playerAlert.triggerAlert(alertMessage: "Unable to play: Access denied. Check log file for details.")
      return
    }

    // From filtered tracks
    var playlists = Playlists()
    for artistAlbumAndTrack in filteredTracks {
      let artist = artistAlbumAndTrack.artist
      let album  = artistAlbumAndTrack.album

      let playlistFile = m3UDict[artist]![album]!
      let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: artist + "/" + album + "/", numTracks: 1)
      playlists.append(Playlist(playlistInfo: playlistInfo, tracks: [artistAlbumAndTrack.track]))
    }

    playTracks(playlists: playlists, trackNum: itemIndex+1)
  }

  func filteredItemSelected(itemIndex: Int, itemText: String) {
    switch(playerSelection.filterMode) {
    case .Artist:
      artistFilterItemSelected(itemIndex: itemIndex, itemText: itemText)

    case .Album:
      albumFilterItemSelected(itemIndex: itemIndex, itemText: itemText)
      break

    case .Track:
      trackFilterItemSelected(itemIndex: itemIndex, itemText: itemText)
      break
    }
  }

  func browserItemClicked(itemIndex: Int, itemText: String) {
    delayCancel()
    playerSelection.browserScrollPos = -1

    browserItemSelected(itemIndex: itemIndex, itemText: itemText)
  }

  func browserItemSelected(itemIndex: Int, itemText: String) {
    if(!playerSelection.filterString.isEmpty) {
      filteredItemSelected(itemIndex: itemIndex, itemText: itemText)
      return
    }

    if(selectedArtist.isEmpty) {
      selectedArtist = itemText

      let albumList = tracksDict[selectedArtist]!.keys.sorted()
      playerSelection.setArtist(newArtist: selectedArtist, newList: albumList)
      return
    }

    if(selectedAlbum.isEmpty) {
      selectedAlbum = itemText

      let trackList = tracksDict[selectedArtist]![selectedAlbum]!
      playerSelection.setAlbum(newAlbum: selectedAlbum, newList: trackList)
      return
    }

    // Track selected, play it
    if(player.isPlaying) {
      pendingTrack = itemIndex+1
      stopReason   = StoppingReason.TrackPressed

      player.stop()
      return
    }

    // Can't play if we haven't got the root folder
    guard bmData != nil else { return }

    if(!bmURL.startAccessingSecurityScopedResource()) {
      logManager.append(throwType: "URLAccess", logMessage: "Play track failed to access: " + bmURL.filePath())
      playerAlert.triggerAlert(alertMessage: "Unable to play: Access denied. Check log file for details.")
      return
    }

    let playlistFile = m3UDict[selectedArtist]![selectedAlbum]!
    let albumTracks  = tracksDict[selectedArtist]![selectedAlbum]!
    let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: selectedArtist + "/" + selectedAlbum + "/", numTracks: albumTracks.count)
    playTracks(playlists: [Playlist(playlistInfo: playlistInfo, tracks: albumTracks)], trackNum: itemIndex+1)
  }

  func playingItemClicked(_ itemIndex: Int) {
    delayCancel()
    playerSelection.playingScrollPos = -1

    playingItemSelected(itemIndex)
  }

  func playingItemSelected(_ itemIndex: Int) {
    // New track selected, play it
    if(player.isPlaying) {
      pendingTrack = itemIndex
      stopReason   = StoppingReason.PlayingTrackPressed

      player.stop()
      return
    }

    playPosition = itemIndex
    let newTrack = playlistManager.moveTo(trackNum: playPosition+1)
    let trackURL      = newTrack!.trackURL
    let trackPath     = trackURL.filePath()

    do {
      try player.play(trackURL)
      logManager.append(logCat: .LogInfo, logMessage: "Playing track: Starting playback of " + trackPath)
    } catch {
      logManager.append(logCat: .LogPlaybackError, logMessage: "Playing track: Playback of " + trackPath + " failed")
      logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)
      playerAlert.triggerAlert(alertMessage: "Error playing track. Check log file for details.")
    }
  }

  func performPositionUpdate() {
    playerSelection.trackPos     = 0.0
    playerSelection.trackPosStr  = "--:--"
    playerSelection.trackLeftStr = "--:--"
    playerSelection.countdownInfo = "Track position:\tUnknown\nTrack length:\tUnknown"

    let playPosition = player.time
    guard let playPosition else { return }

    let current = playPosition.current
    guard let current else { return }
    playerSelection.trackPosStr = timeStr(from: current)

    let total = playPosition.total ?? 0.0
    if((total > 0.0)) {
      playerSelection.trackPos     = current / total
      playerSelection.trackLeftStr = timeStr(from: total - current)
    }

    playerSelection.countdownInfo  = "Track position:\t\(playerSelection.trackPosStr)\n"
                                   + "Track length:\t\((total > 0.0) ? timeStr(from: total) : "Unknown")"
  }

  func updatePlayingPosition() {
    playbackTimer?.invalidate()
    playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true, block: { _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        performPositionUpdate()
       }
    })
  }

  func seekTo(newPosition: Double) {
    player.seek(position: newPosition)
  }

  func configurePlayback(playlists: Playlists, trackNum: Int) {
    let shuffleTracks = playerSelection.shuffleTracks
    playlistManager.setMusicPath(musicPath: musicPath)
    playlistManager.generatePlaylist(playlists: playlists, trackNum: trackNum, shuffleTracks: shuffleTracks)

    playPosition = (trackNum == 0) ? 0 : (shuffleTracks) ? 0 : trackNum-1
    stopReason   = StoppingReason.EndOfAudio
  }

  // Start playback function (see also configurePlayback)
  // Call with a list of playlists and a track number
  // A track number of 0 means start with track 1 (or a random track if shuffle is enabled)
  func playTracks(playlists: Playlists, trackNum: Int = 0) {
    configurePlayback(playlists: playlists, trackNum: trackNum)
    let firstTrack = playlistManager.peekNextTrack()

    let trackURL   = firstTrack!.trackURL
    let trackPath  = trackURL.filePath()

    do {
      try player.play(trackURL)
      logManager.append(logCat: .LogInfo, logMessage: "Play tracks: Starting playback of " + trackPath)
    } catch {
      logManager.append(logCat: .LogPlaybackError, logMessage: "Play tracks: Playback of " + trackPath + " failed")
      logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)

      // Undefined error: 0 isn't very helpful (it's probably a missing file)
      // So, check that here and add a log entry if the file is AWOL
      if(!fm.fileExists(atPath: trackPath)) {
        logManager.append(logCat: .LogFileError, logMessage: trackPath + " is missing!")
      }
      bmURL.stopAccessingSecurityScopedResource()

      playerAlert.triggerAlert(alertMessage: "Error playing tracks. Check log file for details.")
    }

    // Update playing tracks and clear search
    let trackList = (playerSelection.shuffleTracks) ? playlistManager.shuffleList.map { $0.track } : playlistManager.trackList
    playerSelection.playingTracks = trackList.map { PlayingItem(name: $0.trackURL.lastPathComponent, searched: false) }

    playerSelection.clearSearch()
    if(playerSelection.playingScrollPos >= 0) {
      playerSelection.playingScrollPos = 0
      playerSelection.playingScrollTo  = 0
      playerSelection.playingPopover   = -1
    }
  }

  func playAllArtists() {
    var playlists = Playlists()
    for artist in playerSelection.browserItems {
      let albums = tracksDict[artist]!
      for album in albums.keys.sorted() {
        let albumTracks = albums[album]!
        if(!albumTracks.isEmpty) {
          let playlistInfo = PlaylistInfo(playlistFile: m3UDict[artist]![album]!, playlistPath: artist + "/" + album + "/", numTracks: albumTracks.count)
          playlists.append(Playlist(playlistInfo: playlistInfo, tracks: albumTracks))
        }
      }
    }

    if(playlists.isEmpty) { return }
    playTracks(playlists: playlists)
  }

  func playAlbumsFromFilter() {
    var playlists = Playlists()
    for artistAndAlbum in filteredAlbums {
      let artist = artistAndAlbum.artist
      let album  = artistAndAlbum.album
      let albumTracks = tracksDict[artist]![album]!
      if(!albumTracks.isEmpty) {
        let playlistInfo = PlaylistInfo(playlistFile: m3UDict[artist]![album]!, playlistPath: artist + "/" + album + "/", numTracks: albumTracks.count)
        playlists.append(Playlist(playlistInfo: playlistInfo, tracks: albumTracks))
      }
    }

    if(playlists.isEmpty) { return }
    playTracks(playlists: playlists)
  }

  func playAllAlbums() {
    let artist = playerSelection.artist
    if(artist.hasPrefix("from filter")) {
      playAlbumsFromFilter()
      return
    }

    var playlists = Playlists()
    for album in playerSelection.browserItems {
      let albumTracks = tracksDict[artist]![album]!
      if(!albumTracks.isEmpty) {
        let playlistInfo = PlaylistInfo(playlistFile: m3UDict[artist]![album]!, playlistPath: artist + "/" + album + "/", numTracks: albumTracks.count)
        playlists.append(Playlist(playlistInfo: playlistInfo, tracks: albumTracks))
      }
    }

    if(playlists.isEmpty) { return }
    playTracks(playlists: playlists)
  }

  func playAlbum() {
    let album = playerSelection.album
    if(album.hasPrefix("from filter")) {
      // Filtered tracks
      var playlists = Playlists()
      for artistAlbumAndTrack in filteredTracks {
        let artist = artistAlbumAndTrack.artist
        let album  = artistAlbumAndTrack.album

        let playlistFile = m3UDict[artist]![album]!
        let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: artist + "/" + album + "/", numTracks: 1)
        playlists.append(Playlist(playlistInfo: playlistInfo, tracks: [artistAlbumAndTrack.track]))
      }

      playTracks(playlists: playlists)
      return
    }

    var artist = playerSelection.artist
    if(artist.hasPrefix("from filter")) {
      let start = artist.index(artist.startIndex, offsetBy: 13)
      artist.removeSubrange(artist.startIndex..<start)

      let end = artist.index(artist.endIndex, offsetBy: -1)
      artist.removeSubrange(end..<artist.endIndex)
    }

    let albumTracks = tracksDict[artist]![album]!
    if(albumTracks.isEmpty) { return }

    var playlists = Playlists()
    let playlistInfo = PlaylistInfo(playlistFile: m3UDict[artist]![album]!, playlistPath: artist + "/" + album + "/", numTracks: albumTracks.count)
    playlists.append(Playlist(playlistInfo: playlistInfo, tracks: albumTracks))

    playTracks(playlists: playlists)
  }

  func playAll() {
    // Can't play if we haven't got the root folder
    guard bmData != nil else { return }

    // Or if there are no tracks
    guard !tracksDict.isEmpty else { return }

    if(player.isPlaying) {
      stopReason = StoppingReason.PlayAllPressed
      player.stop()
      return
    }

    if(!bmURL.startAccessingSecurityScopedResource()) {
      logManager.append(throwType: "URLAccess", logMessage: "Play all failed to access: " + bmURL.filePath())
      playerAlert.triggerAlert(alertMessage: "Unable to play: Access denied. Check log file for details.")
      return
    }

    if(playerSelection.artist.isEmpty) {
      playAllArtists()
      return
    }

    if(playerSelection.album.isEmpty) {
      playAllAlbums()
      return
    }

    playAlbum()
  }

  func stopAll() {
    if(!player.isPlaying && !player.isPaused) { return }

    stopReason = StoppingReason.StopPressed
    player.stop()
  }

  func playPreviousTrack() {
    if(!player.isPlaying && !player.isPaused) { return }
    if(!playlistManager.hasPrevious(trackNum: playPosition)) { return }

    stopReason = StoppingReason.PreviousPressed
    player.stop()
  }

  func playNextTrack() {
    if(!player.isPlaying && !player.isPaused) { return }
    if(!playlistManager.hasNext(trackNum: playPosition)) {
      stopReason = StoppingReason.EndOfAudio
      player.stop()

      return
    }

    stopReason = StoppingReason.NextPressed
    player.stop()
  }

  func restartAll() {
    if(!player.isPlaying && !player.isPaused) { return }

    stopReason = StoppingReason.RestartPressed
    player.stop()
  }

  func reshuffleAll() {
    if(!player.isPlaying && !player.isPaused) { return }

    stopReason = StoppingReason.ReshufflePressed
    player.stop()
  }

  func togglePause() {
    let playbackState = player.playbackState
    switch(playbackState) {
    case .playing:
      logManager.append(logCat: .LogInfo, logMessage: "TogglePause: Playing -> pausing")
      player.pause()

    case .paused:
      logManager.append(logCat: .LogInfo, logMessage: "TogglePause: Paused -> resuming")
      player.resume()

    default:
      // Nothing to do
      break
    }
  }

  func toggleShuffle() {
    logManager.append(logCat: .LogInfo, logMessage: "ToggleShuffle: Shuffle is \(playerSelection.shuffleTracks) -> \(playerSelection.peekShuffle())")
    playerSelection.toggleShuffle()

    // Nothing more to do if we are not playing
    if(!player.isPlaying) { return }

    // Get info for the selected track
    var selectedTrack: TrackInfo? = nil
    if(playerSelection.playingScrollPos >= 0) { selectedTrack = playlistManager.trackAt(position: playerSelection.playingScrollPos) }

    // Refresh the view
    refreshPlayingTracks()

    // Inform the playlist manager
    playPosition = playlistManager.shuffleChanged(shuffleTracks: playerSelection.shuffleTracks)
    playerSelection.setPlayingPosition(playPosition: playPosition, playTotal: playlistManager.trackCount)
    playerSelection.setPlayingInfo()

    // Stay on the same track
    if(selectedTrack != nil) {
      playerSelection.playingScrollPos  = playlistManager.indexFor(track: selectedTrack!)
      playerSelection.searchIndex = playerSelection.playingScrollPos
    }

    // Toggling shuffle when repeating the current track has no further effects
    if(playerSelection.repeatTracks == RepeatState.Track) {
      return
    }

    // Re-queue tracks
    player.clearQueue()
    logManager.append(logCat: .LogInfo, logMessage: "Queue cleared")

    let nextTrack = playlistManager.peekNextTrack()
    if(nextTrack != nil) {
      let trackURL  = nextTrack!.trackURL
      let trackPath = trackURL.filePath()

      do {
        try player.enqueue(trackURL)
        logManager.append(logCat: .LogInfo, logMessage: "Track queued:  " + trackPath)
      } catch {
        logManager.append(logCat: .LogPlaybackError, logMessage: "Track enqueue failed for " + trackPath)
        logManager.append(logCat: .LogThrownError,   logMessage: "Enqueue error: " + error.localizedDescription)
        playerAlert.triggerAlert(alertMessage: "Error queueing next track. Check log file for details.")
      }
    }
  }

  func toggleRepeat() {
    // Toggling from repeat all to none has no effect (the next track remains queued)
    // Toggling from repeat none to track clears the queue and re-queues the current track
    // Toggling from repeat track to all clears the queue and queues the next track
    logManager.append(logCat: .LogInfo, logMessage: "ToggleRepeat: Repeat is \(playerSelection.repeatTracks) -> \(playerSelection.peekRepeat())")

    let repeatAll = (playerSelection.repeatTracks == RepeatState.All)
    playerSelection.toggleRepeatTracks()

    // If we are not playing or repeating all, there is nothing more to do
    if(!player.isPlaying || repeatAll) { return }

    player.clearQueue()
    logManager.append(logCat: .LogInfo, logMessage: "Queue cleared")

    let repeatingTrack = (playerSelection.repeatTracks == RepeatState.Track)
    let nextTrack = (repeatingTrack) ? currentTrack : playlistManager.peekNextTrack()
    if(nextTrack != nil) {
      let trackURL  = nextTrack!.trackURL
      let trackPath = trackURL.filePath()

      do {
        try player.enqueue(trackURL)
        logManager.append(logCat: .LogInfo, logMessage: "Track queued:  " + trackPath)
      } catch {
        logManager.append(logCat: .LogPlaybackError, logMessage: "Track enqueue failed for " + trackPath)
        logManager.append(logCat: .LogThrownError,   logMessage: "Enqueue error: " + error.localizedDescription)
        playerAlert.triggerAlert(alertMessage: "Error queueing next track. Check log file for details.")
      }
    }
  }

  func toggleFilter() {
    playerSelection.toggleFilterMode()
  }

  static func getM3UDict(m3UFile: String) throws -> AllM3UDict {
    let m3UData = NSData(contentsOfFile: m3UFile) as Data?
    guard let m3UData else {
      return [:]
    }

    return try PropertyListDecoder().decode(AllM3UDict.self, from: m3UData)
  }

  static func getTrackDict(trackFile: String) throws -> AllTracksDict {
    let trackData = NSData(contentsOfFile: trackFile) as Data?
    guard let trackData else {
      return [:]
    }

    return try PropertyListDecoder().decode(AllTracksDict.self, from: trackData)
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
    rootPath = rootURL.filePath()

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
        if(file.hasSuffix(".m3u") || file.hasSuffix(".m3u8")) {
          if(m3UFound) {
            trackErrors = true
            logManager.append(logCat: .LogScanError,   logMessage: "Skipping " + file + " for: " + albumPath)
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

      // Make a dictionary for each one and write it out
      var albumFolders = false
      for album in albums {
        let filePath = artistPath + album

        var isDir: ObjCBool = false
        if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
          (m3Us[album], tracks[album]) = scanAlbum(albumPath: filePath + "/")
          albumFolders = true
        }
      }

      if(!albumFolders) {
        trackErrors = true
        logManager.append(logCat: .LogScanError,   logMessage: "No Album folders for: " + artistPath)
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
      } else {
        logManager.append(logCat: .LogScanError, logMessage: "Updating types: No type folders found")
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
      var artistFolders = false
      for artist in artists {
        let filePath = typePath + artist

        var isDir: ObjCBool = false
        if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
          (m3Us[artist], tracks[artist]) = scanAlbums(artistPath: filePath + "/")
          artistFolders = true
        }
      }

      if(!artistFolders) {
        trackErrors = true
        logManager.append(logCat: .LogScanError,   logMessage: "No Artist folders for: " + typePath)
      }
    } catch {
      trackErrors = true
      logManager.append(logCat: .LogScanError,   logMessage: "Scanning " + typePath + " failed")
      logManager.append(logCat: .LogThrownError, logMessage: "Scan error: " + error.localizedDescription)
    }

    return (m3Us, tracks)
  }

  func scanFolders() {
    guard bmData != nil else { return }

    if(!bmURL.startAccessingSecurityScopedResource()) {
      logManager.append(throwType: "URLAccess", logMessage: "Scan folders failed to access: " + bmURL.filePath())
      playerAlert.triggerAlert(alertMessage: "Unable to scan folders: Access denied. Check log file for details.")
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

    if(selectedType != "")  {
      m3UDict    = allM3UDict[selectedType]    ?? [:]
      tracksDict = allTracksDict[selectedType] ?? [:]
      musicPath  = rootPath + selectedType + "/"
    }
    playerSelection.setTypes(newType: selectedType, newTypeList: typesList)

    if(!scanError.isEmpty) {
      scanError += "Check log file for details."
      playerAlert.triggerAlert(alertMessage: scanError)
    }
  }

  func typeChanged(newType: String) {
    do {
      selectedType = newType
      try saveTypes()
    } catch {
      // Ignore error
      // (it's not critical)
    }

    playerSelection.browserScrollPos = -1
    playerSelection.clearFilter(resetMode: true)

    m3UDict      = allM3UDict[selectedType]    ?? [:]
    tracksDict   = allTracksDict[selectedType] ?? [:]
    musicPath    = rootPath + selectedType + "/"

    selectedArtist = ""
    selectedAlbum  = ""

    let artistList = tracksDict.keys.sorted()
    playerSelection.setAll(newArtist: "", newAlbum: "", newList: artistList)
  }

  func artists(filteredBy: String) -> [String] {
    return tracksDict.keys.filter({ artist in return artist.localizedStandardContains(filteredBy) }).sorted()
  }

  func albums(filteredBy: String) -> [(artist: String, album: String)] {
    var albums: [(artist: String, album: String)] = []
    for artist in tracksDict.keys {
      let matchingAlbums = tracksDict[artist]!.keys.filter({ album in return album.localizedStandardContains(filteredBy) })
      for album in matchingAlbums {
        albums.append((artist, album))
      }
    }

    return albums.sorted {
      $0.album < $1.album
    }
  }

  func tracks(filteredBy: String) -> [(artist: String, album: String, track: String)] {
    let lowerCasedFilter = filteredBy.lowercased()
    var tracks: [(artist: String, album: String, track: String)] = []
    for artist in tracksDict.keys {
      for album in tracksDict[artist]!.keys {
        let matchingTracks = tracksDict[artist]![album]!.filter({ track in return track.lowercased().hasPrefix(lowerCasedFilter) })
        for track in matchingTracks {
          tracks.append((artist, album, track))
        }
      }
    }

    return tracks.sorted {
      $0.track < $1.track
    }
  }

  func filterChanged(newFilter: String) {
    filteredArtist = ""
    filteredAlbum  = ""

    filteredAlbums.removeAll();
    filteredTracks.removeAll();

    if(newFilter.isEmpty) {
      if(selectedArtist.isEmpty) {
        let artistList = tracksDict.keys.sorted()
        playerSelection.setAll(newArtist: "", newAlbum: "", newList: artistList)
      } else if(selectedAlbum.isEmpty) {
        let albumList = tracksDict[selectedArtist]!.keys.sorted()
        playerSelection.setAll(newArtist: selectedArtist, newAlbum: "", newList: albumList)
      } else {
        let trackList = tracksDict[selectedArtist]![selectedAlbum]!
        playerSelection.setAll(newArtist: selectedArtist, newAlbum: selectedAlbum, newList: trackList)
      }

      return
    }

    if(playerSelection.filterMode == .Artist) {
      let artistList = artists(filteredBy: playerSelection.filterString)
      playerSelection.setAll(newArtist: filteredArtist, newAlbum: filteredAlbum, newList: artistList)
    } else if(playerSelection.filterMode == .Album) {
      filteredArtist = "from filter"
      filteredAlbums = albums(filteredBy: playerSelection.filterString)

      var albumList: [String] = []
      for artistAndAlbum in filteredAlbums {
        albumList.append(artistAndAlbum.album)
      }

      playerSelection.setAll(newArtist: filteredArtist, newAlbum: filteredAlbum, newList: albumList)
    } else {
      filteredArtist = "from filter"
      filteredAlbum  = "from filter"
      filteredTracks = tracks(filteredBy: playerSelection.filterString)

      var trackList: [String] = []
      for artistAlbumAndTrack in filteredTracks {
        trackList.append(artistAlbumAndTrack.track)
      }

      playerSelection.setAll(newArtist: filteredArtist, newAlbum: filteredAlbum, newList: trackList)
    }
  }

  func browserScrollPosChanged(newScrollPos: Int) {
    if(playerSelection.filterString.isEmpty) { return }
    if(playerSelection.filterMode == .Artist) { return }

    if((playerSelection.filterMode == .Album) && filteredAlbum.isEmpty) {
      if(newScrollPos >= 0) {
        let album = filteredAlbums[playerSelection.browserScrollPos]
        filteredArtist = "from filter (\(album.artist))"
      } else {
        filteredArtist = "from filter"
      }

      playerSelection.setArtistAndAlbum(newArtist: filteredArtist, newAlbum: filteredAlbum)
    } else if(playerSelection.filterMode == .Track) {
      if(newScrollPos >= 0) {
        let track = filteredTracks[playerSelection.browserScrollPos]
        filteredArtist = "from filter (\(track.artist))"
        filteredAlbum  = "from filter (\(track.album))"
      } else {
        filteredArtist = "from filter"
        filteredAlbum  = "from filter"
      }

      playerSelection.setArtistAndAlbum(newArtist: filteredArtist, newAlbum: filteredAlbum)
    }
  }

  func refreshPlayingTracks() {
    let newTrackList   = (playerSelection.shuffleTracks) ? playlistManager.shuffleList.map { $0.track } : playlistManager.trackList
    let searchedTracks = playerSelection.playingTracks.filter({ $0.searched })
    playerSelection.playingTracks = newTrackList.map {
      let trackName     = $0.trackURL.lastPathComponent
      let trackSearched = searchedTracks.contains(where: { return ($0.name == trackName) })
      return PlayingItem(name: trackName, searched: trackSearched)
    }
  }

  private func setBrowserInfo(_ itemIndex: Int) {
    let artist, album: String
    var m3U: String? = nil
    var trackURL: URL? = nil
    if(playerSelection.filterString.isEmpty) {
      artist = selectedArtist
      album  = selectedAlbum
      if(!artist.isEmpty && album.isEmpty) {
        let itemAlbum = playerSelection.browserItems[itemIndex]
        m3U = m3UDict[artist]![itemAlbum]!
      }

      if(!artist.isEmpty && !album.isEmpty) {
        let track = playerSelection.browserItems[itemIndex]

        let baseURL   = URL(fileURLWithPath: musicPath + artist + "/" + album)
        trackURL      = baseURL.appendingFile(file: track)
      }
    }
    else {
      switch(playerSelection.filterMode) {
      case .Artist:
        artist = filteredArtist
        album  = filteredAlbum
        if(!artist.isEmpty && album.isEmpty) {
          let itemAlbum = playerSelection.browserItems[itemIndex]
          m3U = m3UDict[artist]![itemAlbum]!
        }

        if(!artist.isEmpty && !album.isEmpty) {
          let itemTrack = playerSelection.browserItems[itemIndex]
          let baseURL   = URL(fileURLWithPath: musicPath + "/" + artist + "/" + album)
          trackURL      = baseURL.appendingFile(file: itemTrack)
        }

      case .Album:
        if(filteredAlbum.isEmpty) {
          album = ""

          let itemAlbum: String
          (artist, itemAlbum) = filteredAlbums[itemIndex]
          m3U = m3UDict[artist]![itemAlbum]!
        } else {
          artist = String(filteredArtist.dropFirst(13).dropLast())
          album  = filteredAlbum

          let itemTrack = playerSelection.browserItems[itemIndex]
          let baseURL   = URL(fileURLWithPath: musicPath + "/" + artist + "/" + album)
          trackURL      = baseURL.appendingFile(file: itemTrack)
        }

      case .Track:
        let track: String
        (artist, album, track) = filteredTracks[itemIndex]

        let baseURL   = URL(fileURLWithPath: musicPath + "/" + artist + "/" + album)
        trackURL      = baseURL.appendingFile(file: track)
      }
    }

    var trackAccess = false
    if(trackURL != nil) { trackAccess = bmURL.startAccessingSecurityScopedResource() }
    playerSelection.setBrowserItemInfo(itemIndex: itemIndex, artist: artist, album: album, m3U: m3U, trackURL: trackURL)
    if(trackAccess) { bmURL.stopAccessingSecurityScopedResource() }
  }

  func browserDelayAction(_ itemIndex: Int, _ action: @escaping () -> Void) {
    delayTask?.cancel()
    delayTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: 1000000000)
      } catch { return }

      setBrowserInfo(itemIndex)
      action()

      delayTask = nil
    }
  }

  func playingDelayAction(_ itemIndex: Int, _ action: @escaping () -> Void) {
    delayTask?.cancel()
    delayTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: 1000000000)
      } catch { return }

      playerSelection.setPlayingTrackInfo(trackNum: itemIndex+1, trackInfo: playlistManager.trackAt(position: itemIndex))
      action()

      delayTask = nil
    }
  }

  func delayAction(_ action: @escaping () -> Void) {
    delayTask?.cancel()
    delayTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: 1000000000)
      } catch { return }

      action()
      delayTask = nil
    }
  }

  func delayCancel() {
    delayTask?.cancel()
  }

  func toggleBrowserPopup() {
    if(playerSelection.browserScrollPos < 0) { return }
    if(playerSelection.browserScrollPos == playerSelection.browserPopover) { playerSelection.browserPopover = -1; return }

    setBrowserInfo(playerSelection.browserScrollPos)
    playerSelection.browserPopover = playerSelection.browserScrollPos
  }

  func togglePlayingPopup() {
    if(playerSelection.playingScrollPos < 0) { return }
    if(playerSelection.playingScrollPos == playerSelection.playingPopover) { playerSelection.playingPopover = -1; return }

    playerSelection.setPlayingTrackInfo(trackNum: playerSelection.playingScrollPos+1, trackInfo: playlistManager.trackAt(position: playerSelection.playingScrollPos))
    playerSelection.playingPopover = playerSelection.playingScrollPos
  }

  #if PLAYBACK_TEST
  let testURL1 = URL(fileURLWithPath: "/Volumes/Mini external/Music/MP3/Tori Amos/Winter (CD Single)/Winter.ogg")
  let testURL2 = [URL(fileURLWithPath: "/Volumes/Mini external/Music/MP3/Alan Parsons/Live in Columbia/Damned If I Do.opus"),
                  URL(fileURLWithPath: "/Volumes/Mini external/Music/MP3/The Icicle Works/Seven Singles Deep (Tape)/Love Is A Wonderful Colour.ogg")]

  func testPlay() {
    do {
      if(bmURL.startAccessingSecurityScopedResource()) {
        try player.play(testURL1)
      }
    } catch {
      print("AudioPlayer catch: \(error.localizedDescription)")
      bmURL.stopAccessingSecurityScopedResource()
    }
  }

  var i = 0
  nonisolated func audioPlayerNowPlayingChanged(_ audioPlayer: AudioPlayer) {
    print("AudioPlayer nowPlaying: \(audioPlayer.nowPlaying?.inputSource.url?.filePath() ?? "nil")")

    Task { @MainActor in
      do {
        if( i < 2) {
          try player.enqueue(testURL2[i])
          i += 1
        }
      } catch {
        print("AudioPlayer nowPlaying catch: \(error.localizedDescription)")
      }
    }
  }

  nonisolated func audioPlayerPlaybackStateChanged(_ audioPlayer: AudioPlayer) {
    print("AudioPlayer state: \(audioPlayer.playbackState)")
  }

  /* nonisolated func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
    print("AudioPlayer end of audio")
    audioPlayer.stop()
  } */

  nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: any Error) {
    print("AudioPlayer error: \(error.localizedDescription)")
    audioPlayer.stop()
  }
  #endif
}
