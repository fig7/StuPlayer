//
//  PlaylistManager.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 14/03/2024.
//

import Foundation

class PlaylistManager {
  let queueSize = 8

  var playingDict: PlayingDict = [:]
  var playingIterator: PlayingDict.Iterator?
  var playlist: PlayingDict.Element?

  var tracksIterator: [String].Iterator?
  var track: [String].Element?

  var shuffleTracks = false

  var musicPath = ""

  func setMusicPath(musicPath: String) {
    self.musicPath = musicPath
  }

  func generatePlaylist(playingDict: PlayingDict, shuffleTracks: Bool) {
    self.playingDict = playingDict
    reset(shuffleTracks: shuffleTracks)
  }

  func nextTracks() -> [Playlist : [URL]] {
    guard !playingDict.isEmpty else { return [:] }

    var trackDict: [Playlist : [URL]] = [:]
    var urlList: [URL] = []
    for _ in 0..<queueSize {
      if(playlist == nil) { break }
      if(track == nil)    { break }

      let baseURL  = URL(fileURLWithPath: musicPath + playlist!.key.playlistPath)
      let trackURL = baseURL.appending(path: track!, directoryHint: URL.DirectoryHint.notDirectory)
      urlList.append(trackURL)

      // Go through tracks in the playlist. If we come to an end, we go to the next one.
      track = tracksIterator?.next()
      if(track == nil) {
        trackDict[playlist!.key] = urlList
        urlList = []

        playlist = playingIterator?.next()
        if(playlist == nil) {
          break
        }

        tracksIterator = playlist?.value.makeIterator()
        track = tracksIterator?.next()
      }
    }

    if(!urlList.isEmpty) {
      trackDict[playlist!.key] = urlList
    }

    return trackDict
  }

  func reset(shuffleTracks: Bool) {
    self.shuffleTracks = shuffleTracks

    playingIterator = playingDict.makeIterator()
    playlist = playingIterator?.next()

    tracksIterator = playlist?.value.makeIterator()
    track = tracksIterator?.next()
  }
}
