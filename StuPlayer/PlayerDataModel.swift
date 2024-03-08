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
let rootFile      = "RootFile.dat"
let rootBookmark  = "RootBM.dat"
let rootTypesFile = "RootTypes.dat"

let m3UFile         = "Playlists.dat"
let trackFile       = "Tracks.dat"
let typeFile        = "Type.dat"

typealias M3UDict   = [String : [String : String]]
typealias TrackDict = [String : [String : [String]]]

typealias AllM3UDict     = [String : M3UDict]
typealias AllTracksDict  = [String : TrackDict]

class PlayerDataModel : NSObject, AudioPlayer.Delegate {
  let fm: FileManager
  var bmData: Data?

  var rootPath  = ""
  var musicPath = ""

  let player: AudioPlayer
  var playerSelection: PlayerSelection

  var allM3UDict: AllM3UDict
  var allTracksDict: AllTracksDict

  var m3UDict: M3UDict
  var tracksDict: TrackDict
  var typesList: [String]

  var type: String
  var artist: String
  var album: String

  var playlist: String
  var track: String

  init(playerSelection: PlayerSelection) {
    self.playerSelection = playerSelection
    self.player = AudioPlayer()

    self.fm = FileManager.default
    self.bmData = PlayerDataModel.getBookmarkData()
    self.rootPath = PlayerDataModel.getRootPath()

    self.allM3UDict = PlayerDataModel.getM3UDict(m3UFile: m3UFile)
    self.allTracksDict = PlayerDataModel.getTrackDict(trackFile: trackFile)

    self.typesList = PlayerDataModel.getTypes(typesFile: rootTypesFile)
    self.type = PlayerDataModel.getSelectedType(typeFile: typeFile)

    self.m3UDict    = allM3UDict[self.type] ?? [:]
    self.tracksDict = allTracksDict[self.type] ?? [:]

    self.artist = ""
    self.album  = ""

    self.playlist = ""
    self.track    = ""

    // NSObject
    super.init()

    Task {
      player.delegate = self

      await playerSelection.setTypes(newType: self.type, newTypeList: self.typesList)
      await playerSelection.setAll(newArtist: self.artist, newAlbum: self.album, newList: self.tracksDict.keys.sorted())
    }
  }

  func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
    playlist = ""
    track = ""

    Task {
      await playerSelection.setPlaylist(newPlaylist: playlist, newTrack: track)
    }
  }

  func clearArtist() {
    if(artist.isEmpty) { return }

    artist = ""
    album  = ""

    Task {
      await playerSelection.setArtist(newArtist: artist, newList: tracksDict.keys.sorted())
    }

  }

  func clearAlbum() {
    if(album.isEmpty) { return }

    album = ""

    Task {
      await playerSelection.setAlbum(newAlbum: album, newList: tracksDict[artist]!.keys.sorted())
    }
  }

  func itemSelected(item: String) {
    if(artist.isEmpty) {
      artist = item

      Task {
        await playerSelection.setArtist(newArtist: artist, newList: tracksDict[artist]!.keys.sorted())
      }
    } else if(album.isEmpty) {
      album = item

      Task {
        await playerSelection.setAlbum(newAlbum: album, newList: tracksDict[artist]![album]!)
      }
    } else {
      if let bmData {
        do {
          var isStale = false
          let bmURL = try URL(resolvingBookmarkData: bmData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
          if(bmURL.startAccessingSecurityScopedResource()) {
            let url = URL(fileURLWithPath: musicPath + artist + "/" + album + "/" + item)
            try player.play(url)

            playlist = m3UDict[artist]![album]!
            track = item

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

  func stopAll() {
    player.stop()

    playlist = ""
    track = ""

    Task {
      await playerSelection.setPlaylist(newPlaylist: playlist, newTrack: track)
    }
  }

  func toggleShuffle() {
  }

  func toggleRepeat() {
  }

  static func getM3UDict(m3UFile: String) -> AllM3UDict {
    let m3UData = NSData(contentsOfFile: m3UFile) as Data?
    guard let m3UData else {
      return [:]
    }

    do {
      return try PropertyListDecoder().decode(AllM3UDict.self, from: m3UData)
    }
    catch {
      return [:]
    }
  }

  static func getTrackDict(trackFile: String) -> AllTracksDict {
    let trackData = NSData(contentsOfFile: trackFile) as Data?
    guard let trackData else {
      return [:]
    }

    do {
      return try PropertyListDecoder().decode(AllTracksDict.self, from: trackData)
    }
    catch {
      return [:]
    }
  }

  static func getTypes(typesFile: String) -> [String] {
    let typesData = NSData(contentsOfFile: typesFile) as Data?
    guard let typesData else {
      return []
    }

    let typesStr = String(decoding: typesData, as: UTF8.self)
    return typesStr.split(whereSeparator: \.isNewline).map(String.init)
  }

  static func getSelectedType(typeFile: String) -> String {
    let typeData = NSData(contentsOfFile: typeFile) as Data?
    guard let typeData else {
      return ""
    }

    return String(decoding: typeData, as: UTF8.self)
  }

  static func getBookmarkData() -> Data? {
    return NSData(contentsOfFile: rootBookmark) as Data?
  }

  static func getRootPath() -> String {
    let pathData = NSData(contentsOfFile:rootFile) as Data?
    guard let pathData else {
      return ""
    }

    return String(decoding: pathData, as: UTF8.self)
  }

  func getPermissionAndScanFolders() {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = true
    openPanel.canCreateDirectories = false
    openPanel.canChooseFiles = false
    openPanel.prompt = "Grant Access"
    openPanel.directoryURL = URL(fileURLWithPath: rootPath)

    openPanel.begin { [weak self] result in
      guard let self else { return }
      guard (result == .OK), let url = openPanel.url else {
        // HANDLE ERROR HERE ...
        return
      }

      do {
        let bmData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        fm.createFile(atPath: rootBookmark, contents: bmData, attributes: nil)

        rootPath = url.path().removingPercentEncoding!
        scanFolders()

        Task {
          await self.playerSelection.setRootPath(newRootPath:self.rootURLPath)
        }
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

  func scanAlbums(artistPath: String) -> (m3Us: [String : String], tracks: [String : [String]]) {
    do {
      let albums = try fm.contentsOfDirectory(atPath: artistPath)
      var m3Us: [String  : String] = [:]
      var tracks: [String  : [String]] = [:]

      for album in albums {
        let filePath = artistPath + album

        var isDir: ObjCBool = false
        if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
          let albumPath = filePath + "/"
          let files = try fm.contentsOfDirectory(atPath: albumPath)
          for file in files {
            if(file.hasSuffix(".m3u")) {
              m3Us[album]   = file
              tracks[album] = scanM3U(m3UPath: albumPath + file)
              break
            }
          }
        }
      }

      return (m3Us, tracks)
    } catch {
      // HANDLE ERROR HERE ...
      return ([:], [:])
    }
  }

  func scanTypes() throws {
    typesList.removeAll()
    type = ""

    let types = try fm.contentsOfDirectory(atPath: rootURLPath)
    for type in types {
      let filePath = rootURLPath + type

      var isDir: ObjCBool = false
      if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
        typesList.append(type)
      }
    }

    typesList.sort()
    let joinedTypes = typesList.joined(separator: "\n")
    try joinedTypes.write(toFile: rootTypesFile, atomically: true, encoding: .utf8)

    if(typesList.count > 0) { type = typesList[0] }
    try type.write(toFile: typeFile, atomically: true, encoding: .utf8)
  }

  func scanArtists() throws {
    let mp3Artists = try fm.contentsOfDirectory(atPath: musicURLPath)
    var m3Us: [String : [String : String]] = [:]
    var tracks: [String : [String : [String]]] = [:]

    // Make a dictionary for each one and write it out
    for artist in mp3Artists {
      let filePath = musicURLPath + artist

      var isDir: ObjCBool = false
      if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
        let albumDict = scanAlbums(artistPath: filePath + "/")

        m3Us[artist]   = albumDict.m3Us
        tracks[artist] = albumDict.tracks
      }
    }
  }

  func scanFolders() {
    guard let bmData else { return }
    var bmURL = URL(fileURLWithPath: "/")

    do {
      var isStale = false
      bmURL = try URL(resolvingBookmarkData: bmData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
    } catch {
      // Handle error
      return
    }

    if(bmURL.startAccessingSecurityScopedResource()) {
      do {
        try scanTypes()

        for type in typesList {
          musicURLPath = rootURLPath + type + "/"
          try scanArtists()
        }

        let data1 = try PropertyListEncoder().encode(allM3UDict)
        try data1.write(to: URL(fileURLWithPath:m3UFile))

        let data2 = try PropertyListEncoder().encode(allTracksDict)
        try data2.write(to: URL(fileURLWithPath:trackFile))
        bmURL.stopAccessingSecurityScopedResource()

        artist = ""
        album  = ""

        Task {
          await playerSelection.setTypes(newType: self.type, newTypeList: self.typesList)
          await self.playerSelection.setAll(newArtist: artist, newAlbum: album, newList: tracksDict.keys.sorted())
        }
      } catch {
          // Handle error
      }
    }
  }

  func setRootFolder() {
    stopAll()
    bmData = nil

    rootPath  = ""
    musicPath = ""

    getPermissionAndScanFolders()
  }
}
