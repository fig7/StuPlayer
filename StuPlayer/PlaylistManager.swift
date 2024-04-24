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
  var shuffleTracks = false

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
        let trackURL  = baseURL.appendingFile(file: track)
        let trackInfo = TrackInfo(playlistInfo: playlistInfo, trackNum: trackIndex+1, trackURL: trackURL)
        trackList.append(trackInfo)
      }
    }

    trackCount = trackList.count
  }

  func generateShuffleList(startIndex: Int) {
    nextShuffleIndex = 0
    shuffleList.removeAll()

    // Copy the tracks to the shuffle list
    for (trackIndex, track) in trackList.enumerated() {
      if(startIndex == trackIndex) {
        // Skip the track we are going to start with
        continue
      }

      shuffleList.append((trackIndex, track))
    }

    // Shuffle all the tracks
    shuffleList.shuffle()

    // Insert first element into new list at the beginning
    shuffleList.insert((startIndex, trackList[startIndex]), at: 0)
  }

  func generatePlaylist(playlists: Playlists, trackNum: Int, shuffleTracks: Bool) {
    self.playlists = playlists
    self.shuffleTracks = shuffleTracks

    generateTrackList()
    reset(trackNum: trackNum, shuffleTracks: shuffleTracks)
  }

  func peekNextShuffleTrack() -> TrackInfo? {
    return (nextShuffleIndex == trackCount) ? nil : shuffleList[nextShuffleIndex].track
  }

  func peekNextTrack() -> TrackInfo? {
    if(shuffleTracks) { return peekNextShuffleTrack() }
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
    if(shuffleTracks) { return nextShuffleTrack() }

    if(nextTrackIndex == trackCount) {
      return nil
    }

    let track = trackList[nextTrackIndex]
    nextTrackIndex += 1

    return track
  }

  func reset() {
    nextTrackIndex   = 0
    nextShuffleIndex = 0
  }

  func reset(trackNum: Int = 0, shuffleTracks: Bool) {
    if(trackNum == 0) {
      nextTrackIndex = 0
      generateShuffleList(startIndex: (shuffleTracks) ? Int.random(in: 0..<trackCount) : 0)
    } else {
      nextTrackIndex = trackNum-1
      generateShuffleList(startIndex: nextTrackIndex)
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

    if(shuffleTracks) {
      nextShuffleIndex = trackNum-1
      return peekNextTrack()
    }

    nextTrackIndex = trackNum-1
    return peekNextTrack()
  }

  func shuffleChanged(shuffleTracks: Bool) -> Int {
    self.shuffleTracks = shuffleTracks

    if(!shuffleTracks) {
      // Reset nextTrackIndex and return the new track num
      let currentTrack = shuffleList[nextShuffleIndex-1]
      nextTrackIndex = currentTrack.trackIndex + 1

      return nextTrackIndex
    } else {
      // Advance the nextShuffle index, if it hasn't been already
      if(nextShuffleIndex == 0) {
        nextShuffleIndex += 1
      }

      // Return the new shuffled track num
      return nextShuffleIndex
    }
  }
}
