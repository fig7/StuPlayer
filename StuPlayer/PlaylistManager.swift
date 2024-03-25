//
//  PlaylistManager.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 14/03/2024.
//

import Foundation

class PlaylistManager {
  var musicPath = ""

  var playlists: Playlists = []
  var trackCount = 0

  var trackList: [TrackInfo] = []
  var nextTrackIndex = 0

  var shuffleList: [(trackIndex: Int, track: TrackInfo)] = []
  var nextShuffleIndex = 0

  func setMusicPath(musicPath: String) {
    self.musicPath = musicPath
  }

  func generateTrackList() {
    nextTrackIndex = 0
    trackList.removeAll()

    for playlist in playlists {
      let playlistInfo = playlist.playlistInfo
      for (trackIndex, track) in playlist.tracks.enumerated() {
        let baseURL   = URL(fileURLWithPath: musicPath + playlistInfo.playlistPath)
        let trackURL  = baseURL.appending(path: track, directoryHint: URL.DirectoryHint.notDirectory)
        let trackInfo = TrackInfo(playlistInfo: playlistInfo, trackNum: trackIndex+1, trackURL: trackURL)
        trackList.append(trackInfo)
      }
    }

    trackCount = trackList.count
  }

  func generateShuffleList() {
    nextShuffleIndex = 0
    shuffleList.removeAll()

    // Copy the tracks to the shuffle list
    for (trackIndex, track) in trackList.enumerated() {
      if(nextTrackIndex == trackIndex) {
        // Skip the track we are going to start with
        continue
      }

      shuffleList.append((trackIndex, track))
    }

    // Shuffle all the tracks
    shuffleList.shuffle()

    // Insert first element into new list at the beginning
    shuffleList.insert((nextTrackIndex, trackList[nextTrackIndex]), at: 0)
  }

  func generatePlaylist(playlist: Playlist, trackNum: Int, shuffleTracks: Bool) {
    self.playlists = [playlist]
    generateTrackList()

    reset(trackNum: trackNum, shuffleTracks: shuffleTracks)
  }

  func generatePlaylist(playlists: Playlists, shuffleTracks: Bool) {
    self.playlists = playlists
    generateTrackList()

    reset(shuffleTracks: shuffleTracks)
  }

  func peekNextShuffleTrack() -> TrackInfo? {
    return (nextShuffleIndex == trackCount) ? nil : shuffleList[nextShuffleIndex].track
  }

  func peekNextTrack() -> TrackInfo? {
    if(!shuffleList.isEmpty) { return peekNextShuffleTrack() }
    return (nextTrackIndex == trackCount) ? nil : trackList[nextTrackIndex]
  }

  func nextShuffleTrack() -> TrackInfo? {
    if(nextShuffleIndex == trackCount) {
      return nil
    }

    let track = shuffleList[nextShuffleIndex].track
    nextShuffleIndex += 1

    return track
  }

  func nextTrack() -> TrackInfo? {
    if(!shuffleList.isEmpty) { return nextShuffleTrack() }

    if(nextTrackIndex == trackCount) {
      return nil
    }

    let track = trackList[nextTrackIndex]
    nextTrackIndex += 1

    return track
  }

  func reset(shuffleTracks: Bool) {
    let trackNum = (shuffleTracks) ? Int.random(in: 1...trackCount) : 1
    reset(trackNum: trackNum, shuffleTracks: shuffleTracks)
  }

  func reset(trackNum: Int, shuffleTracks: Bool) {
    nextTrackIndex = trackNum-1

    nextShuffleIndex = 0
    shuffleList.removeAll()

    if(shuffleTracks) {
      generateShuffleList()
    }
  }

  func hasPrevious(trackNum: Int) -> Bool {
    return (trackNum > 1)
  }

  func hasNext(trackNum: Int) -> Bool {
    return (trackNum < trackCount)
  }

  func moveTo(trackNum: Int) -> TrackInfo? {
    if(trackNum > trackCount) { return nil }

    if(!shuffleList.isEmpty) {
      nextShuffleIndex = trackNum-1
      return peekNextTrack()
    }

    nextTrackIndex = trackNum-1
    return peekNextTrack()
  }

  func shuffleChanged(shuffleTracks: Bool) -> Int {
    if(!shuffleTracks) {
      // Reset nextTrackIndex, remove the shuffleList, and return the new track position
      let currentTrack = shuffleList[nextShuffleIndex-1]
      nextTrackIndex = currentTrack.trackIndex + 1

      nextShuffleIndex = 0
      shuffleList.removeAll()

      return nextTrackIndex
    } else {
      // Remove next track (go back 1), generate a new shuffleList, and return the new track position (1)
      nextTrackIndex -= 1

      generateShuffleList()
      nextShuffleIndex = 1
      return 1
    }
  }
}
