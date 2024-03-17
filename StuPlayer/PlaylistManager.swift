//
//  PlaylistManager.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 14/03/2024.
//

import Foundation

class PlaylistManager {
  let queueSize = 8

  var playlists: Playlists = []

  var playlistIterator: Playlists.Iterator?
  var playlist: Playlist?

  var tracksIterator: [String].Iterator?
  var track: String?

  var shuffleTracks = false

  var musicPath = ""

  func setMusicPath(musicPath: String) {
    self.musicPath = musicPath
  }

  func generatePlaylist(playlists: Playlists, shuffleTracks: Bool) {
    self.playlists = playlists
    reset(shuffleTracks: shuffleTracks)
  }

  func nextTracks() -> [Tracklist] {
    guard !playlists.isEmpty else { return [] }

    var trackList: [Tracklist] = []
    var urlList: [URL] = []
    for _ in 0..<queueSize {
      if(playlist == nil) { break }
      if(track == nil)    { break }

      let baseURL  = URL(fileURLWithPath: musicPath + playlist!.playlistInfo.playlistPath)
      let trackURL = baseURL.appending(path: track!, directoryHint: URL.DirectoryHint.notDirectory)
      urlList.append(trackURL)

      // Go through tracks in the playlist. If we come to an end, we go to the next one.
      track = tracksIterator?.next()
      if(track == nil) {
        trackList.append((playlist!.playlistInfo, urlList))
        urlList = []

        playlist = playlistIterator?.next()
        if(playlist == nil) {
          break
        }

        tracksIterator = playlist?.tracks.makeIterator()
        track = tracksIterator?.next()
      }
    }

    if(!urlList.isEmpty) {
      trackList.append((playlist!.playlistInfo, urlList))
    }

    return trackList
  }

  func reset(shuffleTracks: Bool) {
    self.shuffleTracks = shuffleTracks

    playlistIterator = playlists.makeIterator()
    playlist = playlistIterator?.next()

    tracksIterator = playlist?.tracks.makeIterator()
    track = tracksIterator?.next()
  }
}
