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

enum StoppingReason { case PlaybackError, EndOfAudio, PlayAllPressed, StopPressed, TrackPressed, PreviousPressed, NextPressed, RestartPressed, ReshufflePressed }
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
          playerAlert.triggerAlert(alertMessage: "Error queueing next track. Check log file for details.")
        }
      }
    }
  }

  // Using audioPlayerPlaybackStateChanged to handle state changes and update UI
  nonisolated func audioPlayerPlaybackStateChanged(_ audioPlayer: AudioPlayer) {
    let playbackState = audioPlayer.playbackState

    switch(playbackState) {
    case .stopped:
      Task { @MainActor in
        logManager.append(logCat: .LogInfo, logMessage: "Player stopped: \(stopReason)\n")
        nowPlaying = false

        switch(stopReason) {
        case .PlaybackError:
          playPosition = 0
          playerSelection.setPlayingPosition(playPosition: 0, playTotal: 0)
          playerSelection.setTrack(newTrack: nil)
          playerSelection.setPlaybackState(newPlaybackState: .stopped)
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

          playerSelection.setPlayingPosition(playPosition: 0, playTotal: 0)
          playerSelection.setTrack(newTrack: nil)
          playerSelection.setPlaybackState(newPlaybackState: .stopped)
          bmURL.stopAccessingSecurityScopedResource()

        case .PlayAllPressed:
          playPosition = 0
          playAll()

        case .StopPressed:
          playPosition = 0
          playerSelection.setPlayingPosition(playPosition: 0, playTotal: 0)
          playerSelection.setTrack(newTrack: nil)
          playerSelection.setPlaybackState(newPlaybackState: .stopped)
          bmURL.stopAccessingSecurityScopedResource()

        case .TrackPressed:
          playPosition = 0
          let playlistFile = m3UDict[selectedArtist]![selectedAlbum]!
          let albumTracks = tracksDict[selectedArtist]![selectedAlbum]!

          let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: selectedArtist + "/" + selectedAlbum + "/", numTracks: albumTracks.count)
          playTracks(playlist: Playlist(playlistInfo, albumTracks), trackNum: pendingTrack!)
          pendingTrack = nil

        case .PreviousPressed:
          playPosition -= 2
          let previousTrack = playlistManager.moveTo(trackNum: playPosition+1)

          let trackURL   = previousTrack!.trackURL
          let trackPath  = trackURL.filePath()

          do {
            try player.play(trackURL)
            logManager.append(logCat: .LogInfo, logMessage: "Previous track: Starting playback of " + trackPath)
          } catch {
            logManager.append(logCat: .LogPlaybackError, logMessage: "Previous track: Playback of " + trackPath + " failed")
            logManager.append(logCat: .LogThrownError,   logMessage: "Play error: " + error.localizedDescription)
            playerAlert.triggerAlert(alertMessage: "Error playing previous track. Check log file for details.")
          }

        case .NextPressed:
          var nextTrackNum = playPosition+1
          if(nextTrackNum > playlistManager.trackCount) {
            nextTrackNum = 1
            playPosition = 0
          }
          let nextTrack = playlistManager.moveTo(trackNum: nextTrackNum)

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
          playPosition = 0
          playlistManager.reset(shuffleTracks: playerSelection.shuffleTracks)
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
      }

    // NB: Calling setPlaybackState() with player.playbackState because this event can be erroneous
    // I have raised an issue about this: https://github.com/sbooth/SFBAudioEngine/issues/291
    case .playing:
      Task { @MainActor in
        logManager.append(logCat: .LogInfo, logMessage: "Player playing")
        playerSelection.setPlaybackState(newPlaybackState: player.playbackState)
      }

    // NB: Calling setPlaybackState() with player.playbackState because this event can be erroneous
    // I have raised an issue about this: https://github.com/sbooth/SFBAudioEngine/issues/291
    case .paused:
      Task { @MainActor in
        logManager.append(logCat: .LogInfo, logMessage: "Player paused")
        playerSelection.setPlaybackState(newPlaybackState: player.playbackState)
      }

    @unknown default:
      Task { @MainActor in
        logManager.append(logCat: .LogInfo, logMessage: "Unknown player state received: \(playbackState)")
      }
    }
  }

  // Using audioPlayerEndOfAudio to avoid the player stopping sometimes (when the audio node generates multiple end of audio events)
  // I have raised an issue about this: https://github.com/sbooth/SFBAudioEngine/issues/291
  nonisolated func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
    Task { @MainActor in
      logManager.append(logCat: .LogInfo, logMessage: "Player end of audio")
      if(playlistManager.peekNextTrack() == nil) {
        logManager.append(logCat: .LogInfo, logMessage: "End of playlist, stopping...")
        player.stop()
      }
    }
  }

  nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: any Error) {
    Task { @MainActor in
      logManager.append(logCat: .LogPlaybackError, logMessage: error.localizedDescription)

      stopReason = StoppingReason.PlaybackError
      player.stop()
    }
  }
  #endif

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
      logManager.append(throwType: "URLAccess", logMessage: "Play track failed to access: " + bmURL.filePath())
      playerAlert.triggerAlert(alertMessage: "Unable to play: Access denied. Check log file for details.")
      return
    }

    let playlistFile = m3UDict[selectedArtist]![selectedAlbum]!
    let albumTracks  = tracksDict[selectedArtist]![selectedAlbum]!
    let playlistInfo = PlaylistInfo(playlistFile: playlistFile, playlistPath: selectedArtist + "/" + selectedAlbum + "/", numTracks: albumTracks.count)
    playTracks(playlist: (playlistInfo, albumTracks), trackNum: itemIndex+1)
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

  func playTracks(playlist: Playlist, trackNum: Int) {
    configurePlayback(playlist: playlist, trackNum: trackNum)
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
        logManager.append(logCat: .LogFileError, logMessage:trackPath + " is missing!")
      }
      bmURL.stopAccessingSecurityScopedResource()

      playerAlert.triggerAlert(alertMessage: "Error playing tracks. Check log file for details.")
    }
  }

  func playTracks(playlists: Playlists) {
    configurePlayback(playlists: playlists)
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
        logManager.append(logCat: .LogFileError, logMessage:trackPath + " is missing!")
      }
      bmURL.stopAccessingSecurityScopedResource()

      playerAlert.triggerAlert(alertMessage: "Error playing tracks. Check log file for details.")
    }
  }

  func playAllArtists() {
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
    playTracks(playlists: playlists)
  }

  func playAllAlbums() {
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
    playTracks(playlists: playlists)
  }

  func playAlbum() {
    let albumTracks = tracksDict[selectedArtist]![selectedAlbum]!
    if(albumTracks.isEmpty) { return }

    var playlists = Playlists()
    let playlistInfo = PlaylistInfo(playlistFile: m3UDict[selectedArtist]![selectedAlbum]!, playlistPath: selectedArtist + "/" + selectedAlbum + "/", numTracks: albumTracks.count)
    playlists.append((playlistInfo, albumTracks))

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

    if(selectedArtist.isEmpty) {
      playAllArtists()
      return
    }

    if(selectedAlbum.isEmpty) {
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
    let playing = (player.playbackState == .playing)
    let paused  = (player.playbackState == .paused)
    if(playing || paused) {
      if(playing) {
        logManager.append(logCat: .LogInfo, logMessage: "TogglePause: State is playing -> pausing")
        player.pause()
      } else {
        logManager.append(logCat: .LogInfo, logMessage: "TogglePause: State is paused -> playing")
        player.resume()
      }
    }
  }

  func toggleShuffle() {
    logManager.append(logCat: .LogInfo, logMessage: "ToggleShuffle: Shuffle is \(playerSelection.shuffleTracks) -> \(playerSelection.peekShuffle())")
    playerSelection.toggleShuffle()

    // Nothing more to do if we are not playing
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

    selectedArtist = ""
    selectedAlbum  = ""

    if(selectedType != "")  {
      m3UDict    = allM3UDict[selectedType]!
      tracksDict = allTracksDict[selectedType]!
      musicPath  = rootPath + selectedType + "/"
    }

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

  nonisolated func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
    print("AudioPlayer end of audio")
  }

  nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: any Error) {
    print("AudioPlayer error: \(error.localizedDescription)")
  }
  #endif
}
