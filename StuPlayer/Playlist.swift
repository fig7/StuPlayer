//
//  Playlist.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 15/03/2024.
//

import Foundation

struct PlaylistInfo: Hashable {
  let playlistFile: String
  let playlistPath: String
  let numTracks: Int
}

// Collections of tracks
// A Playlist describes an m3u file and includes the contents
typealias Playlist = (playlistInfo: PlaylistInfo, tracks: [String])

// A Tracklist is similar to a playlist, but it contains the processed tracks (URLs ready for playback)
// Unlike a playlist, it might not contain all of the tracks from the m3u
typealias Tracklist = (playlistInfo: PlaylistInfo, tracks: [URL])

