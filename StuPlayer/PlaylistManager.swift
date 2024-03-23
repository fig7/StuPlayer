//
//  PlaylistManager.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 14/03/2024.
//

import Foundation

class PlaylistManager {
  var playlists: Playlists = []
  var playlistIndex = 0
  var trackIndex    = 0
  var trackCount    = 0

  var currentPlaylist: Playlist?
  var currentTrack: String?

  var shuffleTracks = false
  var musicPath = ""

  func setMusicPath(musicPath: String) {
    self.musicPath = musicPath
  }

  func generatePlaylist(playlist: Playlist, trackNum: Int, shuffleTracks: Bool) {
    self.playlists = [playlist]
    calculateTrackCount()

    reset(trackNum:trackNum, shuffleTracks: shuffleTracks)
  }

  func generatePlaylist(playlists: Playlists, shuffleTracks: Bool) {
    self.playlists = playlists
    calculateTrackCount()

    reset(shuffleTracks: shuffleTracks)
  }

  func nextShuffled() {
  }

  func nextTrack() -> TrackInfo? {
    if(currentPlaylist == nil) { return nil }

    let playlistInfo = currentPlaylist!.playlistInfo
    let tracks       = currentPlaylist!.tracks

    let baseURL   = URL(fileURLWithPath: musicPath + playlistInfo.playlistPath)
    let trackURL  = baseURL.appending(path: currentTrack!, directoryHint: URL.DirectoryHint.notDirectory)
    let trackInfo = TrackInfo(playlistInfo: playlistInfo, trackNum: trackIndex+1, trackURL: trackURL)

    trackIndex += 1
    if(trackIndex >= tracks.count) {
      playlistIndex += 1
      trackIndex = 0
    }

    if(playlistIndex < playlists.count) {
      currentPlaylist = playlists[playlistIndex]
      currentTrack    = currentPlaylist!.tracks[trackIndex]
    } else {
      currentPlaylist = nil
      currentTrack    = nil
    }

    return trackInfo
  }

  func generateShuffleList() {
    guard !playlists.isEmpty else { return }

    /* do {
      if(currentPlaylist == nil) { return }
      if(currentTrack == nil)    { return }

      let baseURL  = URL(fileURLWithPath: musicPath + currentPlaylist!.playlistInfo.playlistPath)
      let trackURL = baseURL.appending(path: currentTrack!, directoryHint: URL.DirectoryHint.notDirectory)
      shuffleList.append((currentPlaylist!.playlistInfo, [trackURL]))

      // Go through tracks in the playlist. If we come to an end, we go to the next one.
      track = tracksIterator?.next()
      if(track == nil) {
        playlist = playlistIterator?.next()
        if(playlist == nil) {
          return
        }

        tracksIterator = playlist?.tracks.makeIterator()
        track = tracksIterator?.next()
      }
    } */
  }

  func calculateTrackCount() {
    trackCount = 0
    for playlist in playlists {
      trackCount += playlist.tracks.count
    }
  }

  func reset(trackNum: Int = 1, shuffleTracks: Bool) {
    self.shuffleTracks = shuffleTracks

    playlistIndex = 0
    trackIndex    = trackNum-1
    currentPlaylist = playlists[playlistIndex]
    currentTrack    = currentPlaylist!.tracks[trackIndex]

    if(shuffleTracks) {
      // shuffleList.removeAll()
      generateShuffleList()
    }
  }

  func hasPrevious(trackNum: Int) -> Bool {
    return (trackNum > 1)
  }

  func hasNext(trackNum: Int) -> Bool {
    return (trackNum < trackCount)
  }

  func moveTo(trackNum: Int, shuffleTracks: Bool) -> TrackInfo? {
    if(trackNum > trackCount) { return nil }

    playlistIndex = 0
    var i = 1

    for playlist in playlists {
      currentPlaylist = playlist

      trackIndex = 0
      for track in playlist.tracks {
        currentTrack = track
        if(i == trackNum) {
          return nextTrack()
        }

        i += 1
        trackIndex += 1
      }

      playlistIndex += 1
    }

    return nextTrack()
  }
}
