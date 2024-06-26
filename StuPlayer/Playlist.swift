//
//  Playlist.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 15/03/2024.
//

import Foundation

struct PlaylistInfo {
  let playlistFile: String
  let playlistPath: String
  let numTracks: Int
}

struct TrackInfo {
  let playlist: Playlist
  let trackNum: Int
  let trackURL: URL
}

// A Playlist describes an m3u file and includes the tracks
typealias Playlist = (playlistInfo: PlaylistInfo, tracks: [String])
