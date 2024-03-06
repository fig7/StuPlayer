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
let rootURLFile = "RootURL.dat"
let mp3File     = "MP3.dat"
let mp3FileU    = "MP3_M3U.dat"

// File system paths
let rootURLPath  = "/Volumes/Mini external/"
let musicURLPath = rootURLPath + "Music/MP3/"
let flacURLPath  = rootURLPath + "Music (FLAC)/"
let modURLPath   = rootURLPath + "Music (MOD)/"

class PlayerDataModel {
  let fm: FileManager
  var bmData: Data?

  let player: AudioPlayer
  var playerSelection: PlayerSelection

  var m3UDict: [String : [String : String]]
  var mp3Dict: [String : [String : [String]]]

  var artist: String
  var album: String

  var playlist: String
  var track: String

  init(playerSelection: PlayerSelection) {
    self.playerSelection = playerSelection

    self.fm = FileManager.default

    self.m3UDict = PlayerDataModel.getM3UDict(m3UFile: mp3FileU)
    self.mp3Dict = PlayerDataModel.getTrackDict(trackFile: mp3File)

    self.bmData = PlayerDataModel.getBookmarkData()
    self.player = AudioPlayer()

    self.artist = ""
    self.album  = ""

    self.playlist = ""
    self.track    = ""

    Task {
      await self.playerSelection.setAll(newArtist: self.artist, newAlbum: self.album, newList: mp3Dict.keys.sorted())
    }
  }

  func clearArtist() {
    if(artist.isEmpty) { return }

    artist = ""
    album  = ""

    Task {
      await playerSelection.setArtist(newArtist: artist, newList: mp3Dict.keys.sorted())
    }

  }

  func clearAlbum() {
    if(album.isEmpty) { return }

    album = ""

    Task {
      await playerSelection.setAlbum(newAlbum: album, newList: mp3Dict[artist]!.keys.sorted())
    }
  }

  func itemSelected(item: String) {
    if(artist.isEmpty) {
      artist = item

      Task {
        await playerSelection.setArtist(newArtist: artist, newList: mp3Dict[artist]!.keys.sorted())
      }
    } else if(album.isEmpty) {
      album = item

      Task {
        await playerSelection.setAlbum(newAlbum: album, newList: mp3Dict[artist]![album]!)
      }
    } else {
      track = item

      if let bmData {
        do {
          var isStale = false
          let bmURL = try URL(resolvingBookmarkData: bmData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
          if(bmURL.startAccessingSecurityScopedResource()) {
            let url = URL(fileURLWithPath: musicURLPath + artist + "/" + album + "/" + track)
            try player.play(url)

            playlist = m3UDict[artist]![album]!

            Task {
              await playerSelection.setPlaylist(newPlaylist: playlist, newTrack: track)
            }
          }
        } catch {
          
        }
      }
    }
  }

  func playAll() {
    
  }

  func toggleShuffle() {

  }

  func toggleRepeat() {
    
  }

  static func getM3UDict(m3UFile: String) -> [String : [String : String]] {
    let m3UData = NSData(contentsOfFile: m3UFile) as Data?
    guard let m3UData else {
      return [:]
    }

    do {
      return try PropertyListDecoder().decode([String : [String : String]].self, from: m3UData)
    }
    catch {
      return [:]
    }
  }

  static func getTrackDict(trackFile: String) -> [String : [String : [String]]] {
    let trackData = NSData(contentsOfFile: trackFile) as Data?
    guard let trackData else {
      return [:]
    }

    do {
      return try PropertyListDecoder().decode([String : [String : [String]]].self, from: trackData)
    }
    catch {
      return [:]
    }
  }

  static func getBookmarkData() -> Data? {
    return NSData(contentsOfFile: rootURLFile) as Data?
  }

  func getPermissionAndScanFolders() {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = true
    openPanel.canCreateDirectories = false
    openPanel.canChooseFiles = false
    openPanel.prompt = "Grant Access"
    openPanel.directoryURL = URL(fileURLWithPath: rootURLPath)

    openPanel.begin { [weak self] result in
      guard let self else { return }
      guard (result == .OK), let url = openPanel.url else {
        // HANDLE ERROR HERE ...
        return
      }

      do {
        let bmData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        fm.createFile(atPath: rootURLFile, contents: bmData, attributes: nil)

        self.scanFolders(fm: fm, bmData: bmData)
      } catch {
        // HANDLE ERROR HERE ...
        return
      }
    }
  }

  func scanM3U(m3UPath: String) -> [String] {
    let m3UData = NSData(contentsOfFile:m3UPath) as Data?
    guard let m3UData else {
      return []
    }

    let m3UStr = String(decoding: m3UData, as: UTF8.self)
    var tracks = m3UStr.split(whereSeparator: \.isNewline).map(String.init)
    tracks.indices.forEach {
      tracks[$0] = tracks[$0].trimmingCharacters(in: .whitespaces)
    }

    return tracks.filter { track in
      return !track.starts(with: "#")
    }
  }

  func scanAlbums(artistPath: String) -> (m3U: [String : String], tracks: [String : [String]]) {
    do {
      let albums = try fm.contentsOfDirectory(atPath: artistPath)
      var m3UDict: [String  : String] = [:]
      var tracksDict: [String  : [String]] = [:]

      for album in albums {
        let filePath = artistPath + album

        var isDir: ObjCBool = false
        if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
          let albumPath = filePath + "/"
          let files = try fm.contentsOfDirectory(atPath: albumPath)
          for file in files {
            if(file.hasSuffix(".m3u")) {
              m3UDict[album]   = file
              tracksDict[album] = scanM3U(m3UPath: albumPath + file)
              break
            }
          }
        }
      }

      return (m3U: m3UDict, tracks: tracksDict)
    } catch {
      // HANDLE ERROR HERE ...
      return (m3U: [:], tracks: [:])
    }
  }

  func scanFolders(fm: FileManager, bmData: Data) {
    do {
      var isStale = false
      let bmURL = try URL(resolvingBookmarkData: bmData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
      if(bmURL.startAccessingSecurityScopedResource()) {
        do {
          let mp3Artists = try fm.contentsOfDirectory(atPath: musicURLPath)
          var m3UDict: [String : [String : String]] = [:]
          var trackDict: [String : [String : [String]]] = [:]

          // Make a dictionary for each one and write it out
          for artist in mp3Artists {
            let filePath = musicURLPath + artist

            var isDir: ObjCBool = false
            if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
              let albumDict = scanAlbums(artistPath: filePath + "/")

              m3UDict[artist]   = albumDict.m3U
              trackDict[artist] = albumDict.tracks
            }
          }

          let data1 = try PropertyListEncoder().encode(m3UDict)
          try data1.write(to: URL(fileURLWithPath:mp3FileU))

          let data2 = try PropertyListEncoder().encode(trackDict)
          try data2.write(to: URL(fileURLWithPath:mp3File))

          // let flacArtists   = try fm.contentsOfDirectory(atPath: "/Volumes/Mini external/Music (FLAC)")
          // let modFiles      = try fm.contentsOfDirectory(atPath: "/Volumes/Mini external/Music (MOD)")

          // Re-read lists
          m3UDict = PlayerDataModel.getM3UDict(m3UFile: mp3FileU)
          mp3Dict = PlayerDataModel.getTrackDict(trackFile: mp3File)
          bmURL.stopAccessingSecurityScopedResource()

          Task {
            artist = ""
            album  = ""
            await self.playerSelection.setAll(newArtist: artist, newAlbum: album, newList: mp3Dict.keys.sorted())
          }
        } catch {
          print("ERROR: \(error)")
        }
      }
    } catch {
      // HANDLE ERROR HERE ...
      return
    }
  }

  func setRootFolder() {
    bmData = nil
    getPermissionAndScanFolders()
  }

  func scanFolders() {
    if let bmData {
      scanFolders(fm: FileManager.default, bmData: bmData)
    }
  }
}
