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

  var currentPlaylist: Playlist?
  var currentPlaylistIndex = 0

  var currentTrack: String?
  var currentTrackIndex = 0

  var shuffleList: [(playlistIndex: Int, trackIndex: Int, track: TrackInfo)] = []
  var currentShuffleIndex = 0

  func setMusicPath(musicPath: String) {
    self.musicPath = musicPath
  }

  func generatePlaylist(playlist: Playlist, trackNum: Int, shuffleTracks: Bool) {
    self.playlists = [playlist]
    calculateTrackCount()

    reset(trackNum: trackNum, shuffleTracks: shuffleTracks)
  }

  func generatePlaylist(playlists: Playlists, shuffleTracks: Bool) {
    self.playlists = playlists
    calculateTrackCount()

    var playlistIndex = 0
    var trackIndex    = 0
    if(shuffleTracks) {
      var randomIndex = Int.random(in: 0..<trackCount)
      randomTrackSearch: for playlist in playlists {
        trackIndex = 0
        for _ in playlist.tracks {
          if(randomIndex == 0) {
            break randomTrackSearch
          }

          randomIndex -= 1
          trackIndex  += 1
        }

        playlistIndex += 1
      }
    }

    reset(playlistNum: playlistIndex+1, trackNum: trackIndex+1, shuffleTracks: shuffleTracks)
  }

  func nextTrack() -> TrackInfo? {
    if(currentPlaylist == nil) { return nil }
    if(!shuffleList.isEmpty) {
      if(currentShuffleIndex == trackCount) {
        return nil
      }

      let shuffledTrack = shuffleList[currentShuffleIndex]
      let trackInfo = shuffledTrack.track
      currentPlaylistIndex = shuffledTrack.playlistIndex
      currentTrackIndex    = shuffledTrack.trackIndex

      currentPlaylist = playlists[currentPlaylistIndex]
      currentTrack    = currentPlaylist!.tracks[currentTrackIndex]

      currentShuffleIndex += 1
      return trackInfo
    }

    let playlistInfo = currentPlaylist!.playlistInfo
    let tracks       = currentPlaylist!.tracks

    let baseURL   = URL(fileURLWithPath: musicPath + playlistInfo.playlistPath)
    let trackURL  = baseURL.appending(path: currentTrack!, directoryHint: URL.DirectoryHint.notDirectory)
    let trackInfo = TrackInfo(playlistInfo: playlistInfo, trackNum: currentTrackIndex+1, trackURL: trackURL)

    currentTrackIndex += 1
    if(currentTrackIndex >= tracks.count) {
      currentPlaylistIndex += 1
      currentTrackIndex = 0
    }

    if(currentPlaylistIndex < playlists.count) {
      currentPlaylist = playlists[currentPlaylistIndex]
      currentTrack    = currentPlaylist!.tracks[currentTrackIndex]
    } else {
      currentPlaylist = nil
      currentTrack    = nil
    }

    return trackInfo
  }

  func generateShuffleList() {
    guard !playlists.isEmpty else { return }

    // Copy the tracks to the shuffle list
    var playlistIndex = 0
    for playlist in playlists {
      let playlistInfo = playlist.playlistInfo

      var trackIndex = 0
      for track in playlist.tracks {
        if((playlistIndex == currentPlaylistIndex) && (trackIndex == currentTrackIndex)) {
          // Skip the track we are going to start with
          trackIndex += 1
          continue
        }

        let baseURL   = URL(fileURLWithPath: musicPath + playlistInfo.playlistPath)
        let trackURL  = baseURL.appending(path: track, directoryHint: URL.DirectoryHint.notDirectory)
        let trackInfo = TrackInfo(playlistInfo: playlistInfo, trackNum: trackIndex+1, trackURL: trackURL)

        shuffleList.append((playlistIndex, trackIndex, trackInfo))
        trackIndex += 1
      }

      playlistIndex += 1
    }

    // Shuffle all the tracks
    shuffleList.shuffle()

    // Insert first element into new list at the beginning
    let playlistInfo = currentPlaylist!.playlistInfo

    let baseURL   = URL(fileURLWithPath: musicPath + playlistInfo.playlistPath)
    let trackURL  = baseURL.appending(path: currentTrack!, directoryHint: URL.DirectoryHint.notDirectory)
    let trackInfo = TrackInfo(playlistInfo: playlistInfo, trackNum: currentTrackIndex+1, trackURL: trackURL)

    shuffleList.insert((currentPlaylistIndex, currentTrackIndex, trackInfo), at: 0)
  }

  func calculateTrackCount() {
    trackCount = 0
    for playlist in playlists {
      trackCount += playlist.tracks.count
    }
  }

  func reset(playlistNum: Int = 1, trackNum: Int = 1, shuffleTracks: Bool) {
    currentPlaylistIndex = playlistNum-1
    currentTrackIndex    = trackNum-1

    currentPlaylist = playlists[currentPlaylistIndex]
    currentTrack    = currentPlaylist!.tracks[currentTrackIndex]

    currentShuffleIndex = 0
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
      currentShuffleIndex = trackNum-1
      return nextTrack()
    }

    currentPlaylistIndex = 0
    var i = 1

    for playlist in playlists {
      currentPlaylist = playlist

      currentTrackIndex = 0
      for track in playlist.tracks {
        currentTrack = track
        if(i == trackNum) {
          return nextTrack()
        }

        i += 1
        currentTrackIndex += 1
      }

      currentPlaylistIndex += 1
    }

    // Unreachable
    return nil
  }
}
