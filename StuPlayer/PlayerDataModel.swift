//
//  PlayerDataModel.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/03/2024.
//

import Foundation

import AppKit
import OSLog
import SFBAudioEngine

// Type aliases
typealias M3UDict   = [String : [String : String]]
typealias TrackDict = [String : [String : [String]]]

typealias AllM3UDict     = [String : M3UDict]
typealias AllTracksDict  = [String : TrackDict]

typealias Playlists = [Playlist]

// Enumerations
enum StoppingReason { case PlaybackError, EndOfAudio, PlayAllPressed, StopPressed, TrackPressed, PlayingTrackPressed, PreviousPressed, NextPressed, RestartPressed, ReshufflePressed }
enum StorageError: Error { case BookmarkCreationFailed, TypesCreationFailed, DictionaryCreationFailed, ReadingTypesFailed, ReadingDismissedFailed }
enum TrackError:   Error { case ReadingTypesFailed, ReadingArtistsFailed, ReadingAlbumsFailed, MissingM3U }

// Local storage paths
let rootBookmark   = "RootBM.dat"
let rootFormatFile = "RootFormat.dat"

let m3UFile         = "Playlists.dat"
let trackFile       = "Tracks.dat"

let trackCountdownFile = "Countdown.dat"
let dismissedViewsFile = "DismissedViews.dat"

// Loop constants
let loopMin = 1.0
let loopEndBuffer = 0.5

// Audio components
// They should handle their own thread safety,
// so it's probably best not to add them to the model
let player        = AudioPlayer()
let timePitchUnit = AVAudioUnitTimePitch()

@MainActor class PlayerDataModel : NSObject, AudioPlayer.Delegate, PlayerSelection.Delegate {
  var playerAlert: PlayerAlert
  var playerSelection: PlayerSelection

  let fm = FileManager.default
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

  var selectedFormat   = ""
  var selectedType     = ""
  var selectedArtist   = ""
  var selectedAlbum    = ""

  var filteredArtist = ""
  var filteredAlbum  = ""

  var filteredAlbums: [(artist: String, album: String)] = []
  var filteredTracks: [(artist: String, album: String, track: String)] = []

  var playPosition = 0
  var nowPlaying   = false
  var stopReason   = StoppingReason.EndOfAudio

  var pendingTrack: Int?
  var currentTrack: TrackInfo?

  var currentLyrics: [LyricsItem]?
  var currentNotes: String?

  var loopStart: TimeInterval    = 0.0
  var loopEnd: TimeInterval      = 0.0

  var loopEndLimit : TimeInterval = 0.0
  var playerTotal : TimeInterval  = 0.0

  var playbackTimer: Timer?
  var delayTask: Task<Void, Never>?

  init(playerAlert: PlayerAlert, playerSelection: PlayerSelection) {
    self.playerAlert     = playerAlert
    self.playerSelection = playerSelection

    self.bmData = PlayerDataModel.getBookmarkData()
    if let bmData = self.bmData {
      do {
        var isStale = false
        self.bmURL = try URL(resolvingBookmarkData: bmData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

        if(isStale) {
          self.bmData = try PlayerDataModel.refreshBookmarkData(bmURL: self.bmURL)
        }

        self.rootPath = self.bmURL.folderPath()
        self.logManager.setURL(baseURL: bmURL)
      } catch {
        self.bmData = nil
        self.bmURL  = URL(fileURLWithPath: "/")

        let logger = Logger()
        logger.error("Error reading bookmark data")
        logger.error("Bookmark error: \(error.localizedDescription)")
        playerAlert.triggerAlert(alertMessage: "Error opening root folder. Check Console app (Errors) for details.")

        super.init()
        return
      }
    }

    do {
      try self.selectedFormat = PlayerDataModel.getFormat(formatFile: rootFormatFile)
      self.selectedType = "MP3 & FLAC" // TODO: Hack for now. Just implement as another level.
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

    let trackCountdown: Bool
    do {
      trackCountdown = try PlayerDataModel.getTrackCountdown(countdownFile: trackCountdownFile)
    } catch {
      trackCountdown = false
      logManager.append(logCat: .LogInitError, logMessage: "Error reading track countdown:")
      logManager.append(logCat: .LogInitError, logMessage: "\(error.localizedDescription)")
    }

    let plViewDismissed: Bool
    let lViewDismissed: Bool
    let tViewDismissed: Bool
    do {
      (plViewDismissed, lViewDismissed, tViewDismissed) = try PlayerDataModel.getDismissedViews(dismissedFile: dismissedViewsFile)
    } catch {
      plViewDismissed = false
      lViewDismissed  = false
      tViewDismissed  = false
      logManager.append(logCat: .LogInitError, logMessage: "Error reading dismissed views:")
      logManager.append(logCat: .LogInitError, logMessage: "\(error.localizedDescription)")
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
      playerSelection.setFormat(newFormat: selectedFormat)
      playerSelection.setAll(newArtist: selectedArtist, newAlbum: selectedAlbum, newList: tracksDict.keys.sorted())

      playerSelection.trackCountdown = trackCountdown
      playerSelection.dismissedViews = (plViewDismissed, lViewDismissed, tViewDismissed)

      timePitchUnit.auAudioUnit.shouldBypassEffect = true
      player.withEngine { engine in
        // TODO: Fix for Opus (sample rate converter)
        // TODO: Maybe need to look at reconfigureProcessingGraph !?
        let mainMixer   = engine.mainMixerNode
        let mainMixerIF = mainMixer.inputFormat(forBus: 0)

        guard let mainMixerICP = engine.inputConnectionPoint(for: mainMixer, inputBus: 0) else {
          self.logManager.append(logCat: .LogInitError, logMessage: "Error getting mixer input connection")
          return
        }

        guard let mainMixerIN = mainMixerICP.node else {
          self.logManager.append(logCat: .LogInitError, logMessage: "Error getting mixer input node")
          return
        }

        engine.attach(timePitchUnit)
        engine.disconnectNodeInput(mainMixer, bus: 0)
        engine.connect(timePitchUnit, to: mainMixer, format: mainMixerIF)
        engine.connect(mainMixerIN, to: timePitchUnit, format: nil)
      }
    }
  }

#if !PLAYBACK_TEST
  nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, reconfigureProcessingGraph engine: AVAudioEngine, with format: AVAudioFormat) -> AVAudioNode {
    let mainMixer = engine.mainMixerNode
    engine.disconnectNodeInput(mainMixer, bus: 0)
    engine.connect(timePitchUnit, to: mainMixer, format: format)

    return timePitchUnit
  }

  // Using audioPlayerNowPlayingChanged to handle track changes
  // NB. nowPlaying -> nil is ignored, audioPlayerPlaybackStateChanged() handles end of audio instead (playbackState -> Stopped)
  nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: (any PCMDecoding)?, previouslyPlaying: (any PCMDecoding)?) {
    if(audioPlayer.nowPlaying == nil) { return }

    Task { @MainActor in
      handleNextTrack()
    }
  }

  nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
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

  func lyricTimeParseHH(_ hundrethsStr: Substring) -> TimeInterval? {
    let hundrethsInt = Int(hundrethsStr)
    guard let hundrethsInt else { return nil }
    if((hundrethsInt<0) || (hundrethsInt>99)) { return nil}

    return TimeInterval(hundrethsInt)/100.0
  }

  func lyricTimeParseMS(mins: Substring, secs: Substring) -> TimeInterval? {
    let minsInt = Int(mins)
    guard let minsInt else { return nil }
    if((minsInt<0) || (minsInt>59)) { return nil}
    let minsDbl = TimeInterval(minsInt)

    let timeSplit = secs.split(separator: ".")
    if(timeSplit.count > 2) { return nil }

    let secsWhole = timeSplit[0]
    if(secsWhole.count != 2) { return nil}

    let secsInt = Int(secsWhole)
    guard let secsInt else { return nil }
    if((secsInt<0) || (secsInt>59)) { return nil}
    let secsDbl = TimeInterval(secsInt)

    let hundredths = (timeSplit.count == 2) ? lyricTimeParseHH(timeSplit[1]) : 0.0
    guard let hundredths else { return nil }

    return 60.0*minsDbl + secsDbl + hundredths
  }

  func lyricTimeParseHMS(hours: Substring, mins: Substring, secs: Substring) -> TimeInterval? {
    let hoursInt = Int(hours)
    guard let hoursInt else { return nil }
    if(hoursInt<0) { return nil}
    let hoursDbl = TimeInterval(hoursInt)

    if(mins.count != 2) { return nil }
    let minsSecsDbl = lyricTimeParseMS(mins: mins, secs: secs)
    guard let minsSecsDbl else { return nil }

    return 3600.0*hoursDbl + minsSecsDbl
  }

  func lyricTimeParse(_ lyricTimeStr: Substring) -> TimeInterval? {
    let timeSplit = lyricTimeStr.split(separator: ":")
    switch timeSplit.count {
    case 3:
      return lyricTimeParseHMS(hours: timeSplit[0], mins: timeSplit[1], secs: timeSplit[2])

    case 2:
      return lyricTimeParseMS(mins: timeSplit[0], secs: timeSplit[1])

    default:
      return nil
    }
  }

  func lyricNotes(_ splLines: [Substring]) -> String? {
    var notes: String?
    for splLine in splLines {
      if(splLine.starts(with: "#")) {
        var noteTrimmed = String(splLine)
        noteTrimmed.removeFirst()
        noteTrimmed = noteTrimmed.trimmingCharacters(in: .whitespaces)

        if(notes == nil) { notes = "" }
        notes!.append(noteTrimmed + "\n")
      } else { break }
    }

    if(notes != nil) { notes!.removeLast() }
    return notes
  }

  func lyricLyricItems(_ splLines: [Substring]) -> (String?, [LyricsItem]) {
    var lyricItems: [LyricsItem] = [LyricsItem(lyric: "[Track start]", time: 0.0)]
    var lyricLastTime = 0.0
    for (lineNum, lyricLine) in splLines.enumerated() {
      if(lyricLine.starts(with: "#")) { continue }

      if(lyricLine.isEmpty) { lyricItems.append(LyricsItem(lyric: "")); continue }

      let lineSplit = lyricLine.split(separator: "*", omittingEmptySubsequences: false)
      if(lineSplit.count > 2) { return ("Lyric line format is invalid (line \(lineNum+1))", []) }

      var lyricTime: TimeInterval? = nil
      if(lineSplit.count == 2) {
        let lyricText = lineSplit[1]
        if(lyricText.isEmpty) { return ("Empty lyric line with timestamp (line \(lineNum+1))", []) }

        lyricTime = lyricTimeParse(lineSplit[0])
        guard let lyricTime else      { return ("Lyric line timestamp is invalid (line \(lineNum+1))", []) }
        if(lyricTime < lyricLastTime) { return ("Lyric line timestamps must increase (line \(lineNum+1))", []) }

        lyricLastTime = lyricTime
        lyricItems.append(LyricsItem(lyric: lyricText, time: lyricTime))
      } else { lyricItems.append(LyricsItem(lyric: lineSplit[0]))}
    }

    return (nil, lyricItems)
  }

  func lyricsForTrack(_ splStr: String) -> (String?, String?, [LyricsItem]?) {
    if(splStr.isEmpty) { return (nil, "", []) }

    let splLines = splStr.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    let notes = lyricNotes(splLines)
    let lyricItems = lyricLyricItems(splLines)
    return (lyricItems.0, notes, lyricItems.1)
  }

  func lyricsForTrack(_ trackURL: URL?) -> (String?, [LyricsItem]?) {
    guard let trackURL else { return (nil, nil) }

    let splURL  = trackURL.deletingPathExtension().appendingPathExtension("spl")
    let splPath = splURL.filePath()
    let splData = NSData(contentsOfFile: splPath) as Data?
    guard let splData else {
      logManager.append(logCat: .LogFileError, logMessage: "Lyrics missing for: " + splPath)
      return (nil, nil)
    }

    // Decode
    let splStr = String(decoding: splData, as: UTF8.self)
    let splLines = splStr.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

    // Add notes (if any)
    let notes = lyricNotes(splLines)

    // Add lyrics and times
    var lyrics: [LyricsItem] = [LyricsItem(lyric: "[Track start]", time: 0.0)]
    var lyricLastTime = 0.0
    for lyricLine in splLines {
      if(lyricLine.starts(with: "#")) { continue }

      if(lyricLine.isEmpty) { lyrics.append(LyricsItem(lyric: "")); continue }

      let lineSplit = lyricLine.split(separator: "*")
      if(lineSplit.count > 2) {
        logManager.append(logCat: .LogFileError, logMessage: "Error decoding lyrics for: " + splPath)
        return (nil, nil)
      }

      var lyricTime: TimeInterval? = nil
      if(lineSplit.count == 2) {
        let lyricText = lineSplit[1]
        if(lyricText.isEmpty) {
          logManager.append(logCat: .LogFileError, logMessage: "Lyric time given for empty lyric")
          logManager.append(logCat: .LogFileError, logMessage: "Error decoding lyric time for: " + splPath)
        }

        lyricTime = lyricTimeParse(lineSplit[0])
        guard let lyricTime else {
          logManager.append(logCat: .LogFileError, logMessage: "Error decoding lyric time for: " + splPath)
          return (nil, nil)
        }

        if(lyricTime < lyricLastTime) {
          logManager.append(logCat: .LogFileError, logMessage: "Lyric times must increase")
          logManager.append(logCat: .LogFileError, logMessage: "Error decoding lyric time for: " + splPath)
        }

        lyricLastTime = lyricTime
        lyrics.append(LyricsItem(lyric: lyricText, time: lyricTime))
      } else { lyrics.append(LyricsItem(lyric: lineSplit[0]))}
    }

    return (notes, lyrics)
  }

  func handleNextTrack() {
    let repeatingTrack = (playerSelection.repeatTracks == RepeatState.Track)
    if(!nowPlaying || !repeatingTrack) {
      if(!nowPlaying) {
        logManager.append(logCat: .LogInfo, logMessage: "Now playing: true")
        nowPlaying = true
      }

      playPosition += 1
      currentTrack = playlistManager.nextTrack()

      // Display lyrics (if available)
      let trackURL = currentTrack?.trackURL
      (currentNotes, currentLyrics) = lyricsForTrack(trackURL)

      playerSelection.adjustRate = false
      playerSelection.loopTrack  = false
      var loopTrackDisabled = true

      loopStart = 0.0
      playerTotal = player.totalTime ?? -1.0
      loopTrackDisabled = (playerTotal < loopMin)
      if(!loopTrackDisabled) {
        loopEndLimit = playerTotal - loopEndBuffer
        loopEnd = loopEndLimit
      } else {
        loopEndLimit = 0.0
        loopEnd      = 0.0
      }

      playerSelection.loopStart = lyricsTimeStr(from: loopStart)
      playerSelection.loopEnd   = lyricsTimeStr(from: loopEnd)
      playerSelection.loopTrackDisabled = loopTrackDisabled || !player.supportsSeeking
    }

    playerSelection.setTrack(newTrack: currentTrack!, newLyrics: (currentNotes, currentLyrics))
    playerSelection.setSeekEnabled(seekEnabled: player.supportsSeeking, totalTime: playerTotal)
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

      playerSelection.adjustRate = false
      playerSelection.loopTrack  = false

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
    clearAlbum()
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

  func clearAlbumOrArtist() {
    if(playerSelection.canClearAlbum())  { clearAlbum(); return }
    if(playerSelection.canClearArtist()) { clearArtist(); return }
  }

  func clearAlbumAndArtist() {
    if(playerSelection.canClearAlbum())  { clearAlbum()  }
    if(playerSelection.canClearArtist()) { clearArtist() }
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
      logManager.append(throwType: "URLAccess", logMessage: "Play track failed to access: " + bmURL.folderPath())
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
      logManager.append(throwType: "URLAccess", logMessage: "Play track failed to access: " + bmURL.folderPath())
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
      logManager.append(throwType: "URLAccess", logMessage: "Play track failed to access: " + bmURL.folderPath())
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
      logManager.append(throwType: "URLAccess", logMessage: "Play track failed to access: " + bmURL.folderPath())
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
    playerSelection.lyricsScrollPos = -1

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
    playerSelection.adjustRate = false
    playerSelection.loopTrack  = false

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

  func resetTrackPos() {
    playerSelection.trackPos     = 0.0
    playerSelection.trackPosStr  = "--:--"
    playerSelection.trackLeftStr = "--:--"
    playerSelection.countdownInfo = "Track position:\tUnknown\nTrack length:\tUnknown"
  }

  func performLyricsUpdate(playerPosition: TimeInterval) {
    guard let currentLyrics else { return }

    for (index, lyric) in currentLyrics.enumerated().reversed() {
      guard let lyricTime = lyric.time else { continue }
      if(playerPosition >= lyricTime) {
        playerSelection.lyricsPosition = index
        break
      }
    }
  }

  func performPositionUpdate() {
    let currentTime = player.currentTime
    guard var currentTime else { resetTrackPos(); return }
    playerSelection.trackPosStr = timeStr(from: currentTime)

    if((playerTotal > 0.0)) {
      if(playerSelection.loopTrack) {
        if((currentTime < loopStart) || (currentTime >= loopEnd)) {
          currentTime = loopStart
          player.seek(position: loopStart / playerTotal)
        }
      }

      playerSelection.loopStartDisabled = ((currentTime + loopMin) > loopEnd)   && (currentTime < loopEnd)
      playerSelection.loopEndDisabled   = (currentTime < (loopStart + loopMin)) && (currentTime >= loopStart)

      playerSelection.trackPos     = currentTime / playerTotal
      playerSelection.trackLeftStr = timeStr(from: playerTotal - currentTime)
    } else {
      playerSelection.trackPos     = 0.0
      playerSelection.trackLeftStr = "--:--"
    }

    playerSelection.countdownInfo  = "Track position:\t\(playerSelection.trackPosStr)\n"
                                   + "Track length:\t\((playerTotal > 0.0) ? timeStr(from: playerTotal) : "Unknown")"

    performLyricsUpdate(playerPosition: currentTime)
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
    performPositionUpdate()
  }

  func seekToLoopStart() {
    seekTo(newPosition: loopStart / playerTotal)
  }

  func seekToSL(newPosition: Double) {
    if(playerSelection.loopTrack) {
      let trackPosition = newPosition * playerTotal
      if(trackPosition < loopStart) { setLoopStart(trackPosition) }
      if(trackPosition > loopEnd)   { setLoopEnd(trackPosition) }
    }

    player.seek(position: newPosition)
    performPositionUpdate()
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
    playerSelection.adjustRate = false
    playerSelection.loopTrack  = false

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

    if(playerSelection.lyricsScrollPos >= 0) {
      playerSelection.lyricsScrollPos = 0
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
      logManager.append(throwType: "URLAccess", logMessage: "Play all failed to access: " + bmURL.folderPath())
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

  func toggleLyrics() {
    playerSelection.toggleLyricsMode()
  }

  struct LyricsJSON : Decodable {
    let lyrics: String
  }

  func fetchLyricsError(_ error: (any Error)?) {
    logManager.append(logCat: .LogThrownError, logMessage: "Fetching lyrics from lyrics.ovh: " + ((error != nil) ? error!.localizedDescription : "Unknown error"))
    playerAlert.triggerAlert(alertMessage: "Error fetching lyrics. Check the log file for details.")
  }

  func lyricsDecodeError(_ error: (any Error)) {
    logManager.append(logCat: .LogThrownError, logMessage: "Decoding lyrics: " + error.localizedDescription)
    playerAlert.triggerAlert(alertMessage: "Error fetching lyrics. Check the log file for details.")
  }

  func saveOVHLyrics(_ newLyrics:[LyricsItem]) {
    currentNotes  = nil
    currentLyrics = newLyrics

    playerSelection.setLyrics(newLyrics: (currentNotes, currentLyrics))
    updateLyricsFile(trackURL: currentTrack?.trackURL, notesToWrite: currentNotes, lyricsToWrite: currentLyrics)
  }

  func fetchLyrics() {
    let lyricsInfo = playerSelection.lyricsInfo
    let url = URL(string: "https://api.lyrics.ovh/v1/" + lyricsInfo.artist + "/" + lyricsInfo.track)!

    let task = URLSession.shared.dataTask(with: url) { jsonData, response, error in
      guard error == nil, let jsonData else {
        Task { @MainActor in self.fetchLyricsError(error) }
        return
      }

      do {
        let lyricsJSON = try JSONDecoder().decode(LyricsJSON.self, from: jsonData)
        let lyricsStr = lyricsJSON.lyrics

        var lyrics: [LyricsItem] = [LyricsItem(lyric: "[Track start]", time: 0.0)]
        let lyricLines = lyricsStr.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        for lyricLine in lyricLines {
          lyrics.append(LyricsItem(lyric: lyricLine.trimmingCharacters(in: .whitespaces)))
        }

        Task { @MainActor in self.saveOVHLyrics(lyrics) }
      } catch {
        Task { @MainActor in self.lyricsDecodeError(error) }
      }
    }

    task.resume()
  }

func refreshLyrics() {
     // Refetch lyrics (if available)
     let trackURL = currentTrack?.trackURL

     (currentNotes, currentLyrics) = lyricsForTrack(trackURL)
     playerSelection.setLyrics(newLyrics: (currentNotes, currentLyrics))

    performPositionUpdate()
  }

  static func getM3UDict(m3UFile: String) throws -> AllM3UDict {
    let m3UData = NSData(contentsOfFile: m3UFile) as Data?
    guard let m3UData else { return [:] }

    return try PropertyListDecoder().decode(AllM3UDict.self, from: m3UData)
  }

  static func getTrackDict(trackFile: String) throws -> AllTracksDict {
    let trackData = NSData(contentsOfFile: trackFile) as Data?
    guard let trackData else { return [:] }

    return try PropertyListDecoder().decode(AllTracksDict.self, from: trackData)
  }

  static func getDismissedViews(dismissedFile: String) throws -> (Bool, Bool, Bool) {
    let dismissedData = try NSData(contentsOfFile: dismissedFile) as Data
    let dismissedStr  = String(decoding: dismissedData, as: UTF8.self)
    let dismissed = dismissedStr.split(separator: ",")
    if((dismissed.count != 2) && (dismissed.count != 3)) { throw StorageError.ReadingDismissedFailed }

    return (dismissed.count == 3) ? ((dismissed[0] == "TRUE"), (dismissed[1] == "TRUE"), (dismissed[2] == "TRUE"))
                                  : ((dismissed[0] == "TRUE"), (dismissed[1] == "TRUE"), false)
  }

  static func getTrackCountdown(countdownFile: String) throws -> Bool {
    let countdownData = try NSData(contentsOfFile: countdownFile) as Data
    let countdownStr  = String(decoding: countdownData, as: UTF8.self)
    return (countdownStr == "TRUE")
  }

  static func getFormat(formatFile: String) throws -> String {
    let formatData = NSData(contentsOfFile: formatFile) as Data?
    guard let formatData else { return "From folders" }

    let formatStr = String(decoding: formatData, as: UTF8.self)
    return formatStr
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
    rootPath = rootURL.folderPath()

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

    var m3ULines = m3UStr.split(whereSeparator: \.isNewline).map(String.init)
    m3ULines.indices.forEach { m3ULines[$0] = m3ULines[$0].trimmingCharacters(in: .whitespaces) }
    return m3ULines.filter { m3ULine in return !m3ULine.starts(with: "#") }
  }

  func scanAlbum(_ albumPath: String) -> (String, [String]) {
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

  func scanAlbums(_ artistPath: String) -> (m3Us: [String : String], tracks: [String : [String]]) {
    var m3Us: [String : String] = [:]
    var tracks: [String : [String]] = [:]

    do {
      let albums = try fm.contentsOfDirectory(atPath: artistPath)

      // Make a dictionary for each one and write it out
      var albumFolders = false
      for album in albums {
        let filePath = artistPath + album

        var isDir: ObjCBool = false
        if(fm.fileExists(atPath: filePath, isDirectory: &isDir)) {
          if(isDir.boolValue) {
            // Valid album directory found
            let albumPath = filePath + "/"
            (m3Us[album], tracks[album]) = scanAlbum(albumPath)
            albumFolders = true
          }
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

  func saveFormat() throws {
    try selectedFormat.write(toFile: rootFormatFile, atomically: true, encoding: .utf8)
  }

  func scanTypes() throws {
    typesList.removeAll()
    selectedType = ""

    do {
      logManager.append(logCat: .LogInfo, logMessage: "Scanning for types in \(rootPath)")
      let types = try fm.contentsOfDirectory(atPath: rootPath)
      for type in types {
        let filePath = rootPath + type
        logManager.append(logCat: .LogInfo, logMessage: "Checking \(filePath)")

        var isDir: ObjCBool = false
        if(fm.fileExists(atPath: filePath, isDirectory: &isDir)) {
          if(isDir.boolValue) {
            // Valid type directory found
            typesList.append(type)
          }
        }
      }

      typesList.sort()
      if(typesList.count > 0) {
        selectedType = typesList[0]
      } else {
        logManager.append(logCat: .LogScanError, logMessage: "Updating types: No type folders found")
      }

      try saveFormat()
      logManager.append(logCat: .LogInfo, logMessage: "Scanning for types... done")
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
      let typePath = rootPath + type + "/"
      logManager.append(logCat: .LogInfo, logMessage: "Scanning for artists in \(typePath)")

      let artistDict = scanArtists(typePath)
      allM3UDict[type]    = artistDict.m3Us
      allTracksDict[type] = artistDict.tracks
    }

    if(trackErrors) {
      logManager.append(logCat: .LogInfo, logMessage: "Scanning for artists... done (with errors)")
      throw TrackError.ReadingArtistsFailed
    }

    logManager.append(logCat: .LogInfo, logMessage: "Scanning for artists... done")
  }

  func scanArtists(_ typePath: String) -> (m3Us: M3UDict, tracks: TrackDict) {
    var m3Us: M3UDict = [:]
    var tracks: TrackDict = [:]

    do {
      let artists = try fm.contentsOfDirectory(atPath: typePath)

      // Make a dictionary for each one and write it out
      var artistFolders = false
      for artist in artists {
        let filePath = typePath + artist

        var isDir: ObjCBool = false
        if(fm.fileExists(atPath: filePath, isDirectory: &isDir)) {
          if(isDir.boolValue) {
            // Valid artist directory found
            let artistPath = filePath + "/"
            (m3Us[artist], tracks[artist]) = scanAlbums(artistPath)
            artistFolders = true
          }
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
      logManager.append(throwType: "URLAccess", logMessage: "Scan folders failed to access: " + bmURL.folderPath())
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
    playerSelection.setFormat(newFormat: selectedType)

    if(!scanError.isEmpty) {
      scanError += "Check log file for details."
      playerAlert.triggerAlert(alertMessage: scanError)
    }
  }

  func formatChanged(newFormat: String) {
    do {
      selectedFormat = newFormat
      try saveFormat()
    } catch {
      // Ignore error
      // (it's not critical)
    }

    m3UDict      = allM3UDict[selectedType]    ?? [:]
    tracksDict   = allTracksDict[selectedType] ?? [:]
    musicPath    = rootPath + selectedType + "/"

    selectedArtist = ""
    selectedAlbum  = ""

    playerSelection.browserScrollPos = -1

    let artistList = tracksDict.keys.sorted()
    playerSelection.setAll(newArtist: "", newAlbum: "", newList: artistList)
    playerSelection.clearFilter(resetMode: true)
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

  func trackPosChanged(newTrackPos: Double) {
    let playerPosition = player.time
    guard let playerPosition else { return }

    let total = playerPosition.total
    guard let total else { return }

    performLyricsUpdate(playerPosition: newTrackPos*total)
  }

  func trackRateChanged(adjustRate: Bool, newTrackRate: Double) {
    timePitchUnit.auAudioUnit.shouldBypassEffect = !adjustRate
    timePitchUnit.rate = Float(newTrackRate)
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

  func setLoopStart() {
    let newLoopStart = player.currentTime
    guard let newLoopStart else { return }

    setLoopStart(newLoopStart)
  }

  private func setLoopStart(_ newLoopStart: TimeInterval) {
    self.loopStart = newLoopStart
    playerSelection.loopStart = lyricsTimeStr(from: loopStart)

    if(loopStart >= loopEnd) { setLoopEnd(loopEndLimit) }
  }

  func setLoopEnd() {
    let newLoopEnd = player.currentTime
    guard let newLoopEnd else { return }

    setLoopEnd(newLoopEnd)
  }

  private func setLoopEnd(_ newLoopEnd: TimeInterval) {
    self.loopEnd = (newLoopEnd > loopEndLimit) ? loopEndLimit : newLoopEnd
    playerSelection.loopEnd = lyricsTimeStr(from: loopEnd)

    if(loopEnd <= loopStart) { setLoopStart(0.0) }
  }

  func adjustLoopStart(_ wheelDelta: CGFloat) {
    let hundreths = playerSelection.loopStart.last
    var increment, decrement: Double
    switch hundreths {
    case "1":
      increment = 0.09
      decrement = 0.01

    case "2":
      increment = 0.08
      decrement = 0.02

    case "3":
      increment = 0.07
      decrement = 0.03

    case "4":
      increment = 0.06
      decrement = 0.04

    case "5":
      increment = 0.05
      decrement = 0.05

    case "6":
      increment = 0.04
      decrement = 0.06

    case "7":
      increment = 0.03
      decrement = 0.07

    case "8":
      increment = 0.02
      decrement = 0.08

    case "9":
      increment = 0.01
      decrement = 0.09

    default: // "0"
      increment = 0.10
      decrement = 0.10
    }

    var newLoopStart = loopStart
    if(wheelDelta > 0.0) { newLoopStart += increment } else { newLoopStart -= decrement }
    newLoopStart = round(10.0*newLoopStart) / 10.0
    if(newLoopStart < 0.0) { newLoopStart = 0.0 }

    if((newLoopStart + loopMin) <= loopEnd) {
      loopStart = newLoopStart
      playerSelection.loopStart = lyricsTimeStr(from: loopStart)

      if(playerSelection.loopTrack) { seekTo(newPosition: loopStart / playerTotal) }
    }
  }

  func adjustLoopEnd(_ wheelDelta: CGFloat) {
    let hundreths = playerSelection.loopEnd.last
    var increment, decrement: Double
    switch hundreths {
    case "1":
      increment = 0.09
      decrement = 0.01

    case "2":
      increment = 0.08
      decrement = 0.02

    case "3":
      increment = 0.07
      decrement = 0.03

    case "4":
      increment = 0.06
      decrement = 0.04

    case "5":
      increment = 0.05
      decrement = 0.05

    case "6":
      increment = 0.04
      decrement = 0.06

    case "7":
      increment = 0.03
      decrement = 0.07

    case "8":
      increment = 0.02
      decrement = 0.08

    case "9":
      increment = 0.01
      decrement = 0.09

    default: // "0"
      increment = 0.10
      decrement = 0.10
    }

    var newLoopEnd = loopEnd
    if(wheelDelta > 0.0) { newLoopEnd += increment } else { newLoopEnd -= decrement }
    newLoopEnd = round(10.0*newLoopEnd) / 10.0
    if(newLoopEnd > loopEndLimit) { newLoopEnd = loopEndLimit }

    if(newLoopEnd >= (loopStart + loopMin)) {
      loopEnd = newLoopEnd
      playerSelection.loopEnd = lyricsTimeStr(from: loopEnd)
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

  func lyricsDelayAction(_ action: @escaping () -> Void) {
    delayTask?.cancel()
    delayTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: 1000000000)
      } catch { return }

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

  func toggleLyricsInfoPopup() {
    if(playerSelection.lyricsInfoPos < 0) { return }
    if(playerSelection.lyricsInfoPos == playerSelection.lyricsInfoPopover) { playerSelection.lyricsInfoPopover = -1; return }

    playerSelection.lyricsInfoPopover = playerSelection.lyricsInfoPos
  }

  func toggleTrackCountdown() {
    playerSelection.trackCountdown.toggle()

    let trackCountdown = playerSelection.trackCountdown ? "TRUE" : "FALSE"
    try? trackCountdown.write(toFile: trackCountdownFile, atomically: true, encoding: .utf8)
  }

  func saveDismissedViews() {
    let plDismiss = playerSelection.dismissedViews.plView ? "TRUE" : "FALSE"
    let lDismiss  = playerSelection.dismissedViews.lView  ? "TRUE" : "FALSE"
    let tDismiss  = playerSelection.dismissedViews.tView  ? "TRUE" : "FALSE"
    let dismissedViews = plDismiss + "," + lDismiss + "," + tDismiss

    do {
      try dismissedViews.write(toFile: dismissedViewsFile, atomically: true, encoding: .utf8)
    } catch {
      logManager.append(logCat: .LogFileError,   logMessage: "Error saving dismissed view")
      logManager.append(logCat: .LogThrownError, logMessage: "File error: " + error.localizedDescription)
    }
  }

  func dismissPLVPurchase() {
    playerSelection.dismissedViews.plView = true
    playerAlert.triggerAlert(alertMessage: "If you change your mind, you can purchase views from the Purchases menu.")

    saveDismissedViews()
  }

  func dismissLVPurchase() {
    playerSelection.dismissedViews.lView = true
    playerAlert.triggerAlert(alertMessage: "If you change your mind, you can purchase views from the Purchases menu.")

    saveDismissedViews()
  }

  func dismissTVPurchase() {
    playerSelection.dismissedViews.tView = true
    playerAlert.triggerAlert(alertMessage: "If you change your mind, you can purchase views from the Purchases menu.")

    saveDismissedViews()
  }

  func validateLyricTimes(_ lyrics: [LyricsItem]) -> Bool {
    var testTime = 0.0
    for lyric in lyrics {
      guard let lyricTime = lyric.time else { continue }
      if(lyricTime < testTime) { return false}

      testTime = lyricTime
    }

    return true
  }

  func lyricTimeValid(lyricIndex: Int, newTime: TimeInterval) -> Bool {
    guard let currentLyrics else { return false }
    guard !currentLyrics[lyricIndex].text.isEmpty else { return false }

    var newLyrics = currentLyrics
    newLyrics[lyricIndex].time = newTime

    if(validateLyricTimes(newLyrics)) {
      self.currentLyrics = newLyrics
      return true
    }

    return false
  }

  func updateLyricsFile(trackURL: URL?, notesToWrite: String?, lyricsToWrite: [LyricsItem]? ) {
    guard let trackURL else { return }
    guard var lyricsToWrite else { return }
    lyricsToWrite.removeFirst()

    var ouputStr = ""
    if let notesToWrite {
      let noteLines = notesToWrite.split(whereSeparator: \.isNewline)
      for noteLine in noteLines {
        ouputStr.append("# " + noteLine + "\n")
      }

      ouputStr.append("#\n")
    }

    for lyric in lyricsToWrite {
      var lyricLine = ""
      if(lyric.time != nil) { lyricLine.append(lyricsTimeStr(from: lyric.time!) + "*") }
      lyricLine.append(lyric.text)
      ouputStr.append(lyricLine + "\n")
    }

    // Remove final \n
    ouputStr.removeLast()

    let lyricsURL  = trackURL.deletingPathExtension().appendingPathExtension("spl")
    let lyricsPath = lyricsURL.filePath()
    try! ouputStr.write(toFile: lyricsPath, atomically: true, encoding: .utf8) // TODO: Handle error (e.g. won't save after stop pressed) Maybe hold lock, somehow? i.e. until window closed.
  }

  func lyricsNavigateSelected(_ itemIndex: Int) {
    guard let currentLyrics else { return }
    guard let lyricTime = currentLyrics[itemIndex].time else { return }

    if(playerTotal > 0.0) {
      let trackPos = (lyricTime / playerTotal) + 0.000001 // (try to avoid rounding error)
      self.seekTo(newPosition: trackPos)

      if(playerSelection.loopTrack && ((lyricTime < loopStart) || (lyricTime > loopEnd))) {
        // Adjust loop, if selection is outside loop bounds
        if(lyricTime < loopStart) { setLoopStart(lyricTime) }
        if(lyricTime > loopEnd) { setLoopEnd(lyricTime) }
      }
    }
  }

  func lyricsUpdateSelected(_ itemIndex: Int) {
    if(itemIndex == 0) { return }

    let playPosition = player.time
    guard let playPosition else { return }

    let current = playPosition.current
    guard let current else { return }

    var lyricTime = current - 0.5
    if(lyricTime<0.0) { lyricTime = 0.0 }

    if(lyricTimeValid(lyricIndex: itemIndex, newTime: lyricTime)) {
      currentLyrics![itemIndex].time = lyricTime
      playerSelection.setLyrics(newLyrics: (currentNotes, currentLyrics))

      updateLyricsFile(trackURL: currentTrack?.trackURL, notesToWrite: currentNotes, lyricsToWrite: currentLyrics)
    }
  }

  func lyricsTrackURL() -> URL? {
    if #unavailable(macOS 13.0) {
      playerAlert.triggerAlert(alertMessage: "On macOS 12.x, please use a text editor to edit lyrics (the .spl files)")
      return nil
    }

    return currentTrack?.trackURL
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

