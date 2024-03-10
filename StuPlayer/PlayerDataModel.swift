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

@MainActor class PlayerDataModel : NSObject, AudioPlayer.Delegate, PlayerSelection.Delegate {
  let fm    = FileManager.default
  var bmURL = URL(fileURLWithPath: "/")

  var bmData: Data?
  var rootPath: String
  var musicPath: String

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
  var trackNum: Int

  init(playerSelection: PlayerSelection) {
    self.playerSelection = playerSelection
    self.player = AudioPlayer()

    self.bmData = PlayerDataModel.getBookmarkData()
    if let bmData = self.bmData {
      do {
        var isStale = false
        self.bmURL = try URL(resolvingBookmarkData: bmData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

        // TODO: Handle stale bmData
      } catch {
        // Handle error
      }
    }

    self.rootPath = PlayerDataModel.getRootPath()

    self.allM3UDict = PlayerDataModel.getM3UDict(m3UFile: m3UFile)
    self.allTracksDict = PlayerDataModel.getTrackDict(trackFile: trackFile)

    self.typesList = PlayerDataModel.getTypes(typesFile: rootTypesFile)
    self.type = PlayerDataModel.getSelectedType(typeFile: typeFile)

    self.m3UDict    = allM3UDict[self.type] ?? [:]
    self.tracksDict = allTracksDict[self.type] ?? [:]
    self.musicPath  = rootPath + type + "/"

    self.artist = ""
    self.album  = ""

    self.playlist = ""
    self.trackNum = 0

    // NSObject
    super.init()

    Task { @MainActor in
      player.delegate = self

      playerSelection.setDelegate(delegate: self)
      playerSelection.setRootPath(newRootPath: rootPath)
      playerSelection.setTypes(newType: type, newTypeList: typesList)
      playerSelection.setAll(newArtist: artist, newAlbum: album, newList: tracksDict.keys.sorted())
    }
  }

  nonisolated func audioPlayerEndOfAudio(_: AudioPlayer) {
    Task { @MainActor in
      player.stop()
      bmURL.stopAccessingSecurityScopedResource()

      playlist = ""
      trackNum = 0

      playerSelection.setPlaylist(newPlaylist: playlist, newTrackNum: trackNum)
    }
  }

  nonisolated func audioPlayer(_: AudioPlayer, renderingWillStart: PCMDecoding, at: UInt64) {
    Task { @MainActor in
      trackNum += 1

      playerSelection.setPlaylist(newPlaylist: playlist, newTrackNum: trackNum)
    }
  }

  func clearArtist() {
    if(artist.isEmpty) { return }

    artist = ""
    album  = ""

    playerSelection.setArtist(newArtist: artist, newList: tracksDict.keys.sorted())
  }

  func clearAlbum() {
    if(album.isEmpty) { return }

    album = ""

    playerSelection.setAlbum(newAlbum: album, newList: tracksDict[artist]!.keys.sorted())
  }

  func itemSelected(item: String) {
    if(artist.isEmpty) {
      artist = item

      playerSelection.setArtist(newArtist: artist, newList: tracksDict[artist]!.keys.sorted())
    } else if(album.isEmpty) {
      album = item

      playerSelection.setAlbum(newAlbum: album, newList: tracksDict[artist]![album]!)
    } else {
      if bmData != nil {
        do {
          if(player.isPlaying || bmURL.startAccessingSecurityScopedResource()) {
            playlist = m3UDict[artist]![album]!
            trackNum = 0

            let url = URL(fileURLWithPath: musicPath + artist + "/" + album + "/" + item)
            try player.play(url)

            playerSelection.setTracks(newTracks: [item])
          }
        } catch {
          // Handle error
        }
      }
    }
  }

  func playAll() {
    if(artist.isEmpty) {
    } else if(album.isEmpty) {
    } else {
      if bmData != nil {
        do {
          if(player.isPlaying || bmURL.startAccessingSecurityScopedResource()) {
            player.stop()

            let tracks = tracksDict[artist]![album]!
            if(!tracks.isEmpty) {
              for track in tracks {
                let url  = URL(fileURLWithPath: musicPath + artist + "/" + album + "/" + track)
                try player.enqueue(url)
              }

              playlist = m3UDict[artist]![album]!
              trackNum = 0

              try player.play()

              playerSelection.setTracks(newTracks: tracks)
            }
          }
        } catch {
          // Handle error
        }
      }
    }
  }

  func stopAll() {
    if(!player.isPlaying) { return }

    player.stop()
    bmURL.stopAccessingSecurityScopedResource()

    playlist = ""
    trackNum = 0

    playerSelection.setPlaylist(newPlaylist: playlist, newTrackNum: trackNum)
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

  func setRootFolder() {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = true
    openPanel.canCreateDirectories = false
    openPanel.canChooseFiles = false
    openPanel.prompt = "Grant Access"
    openPanel.directoryURL = URL(fileURLWithPath: "/")

    openPanel.begin { [weak self] result in
      guard let self else { return }
      guard (result == .OK), let url = openPanel.url else {
        // HANDLE ERROR HERE ...
        return
      }

      do {
        stopAll()

        bmData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        fm.createFile(atPath: rootBookmark, contents: bmData, attributes: nil)

        rootPath = url.path().removingPercentEncoding!
        try rootPath.write(toFile: rootFile, atomically: true, encoding: .utf8)

        scanFolders()

        self.playerSelection.setRootPath(newRootPath: self.rootPath)
      } catch {
        // Handle error
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

  func scanAlbums(artistPath: String) throws -> (m3Us: [String : String], tracks: [String : [String]]) {
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
  }

  func scanTypes() throws {
    typesList.removeAll()
    type = ""

    let types = try fm.contentsOfDirectory(atPath: rootPath)
    for type in types {
      let filePath = rootPath + type

      var isDir: ObjCBool = false
      if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
        typesList.append(type)
      }
    }

    typesList.sort()
    let joinedTypes = typesList.joined(separator: "\n")
    try joinedTypes.write(toFile: rootTypesFile, atomically: true, encoding: .utf8)
  }

  func scanArtists(typePath: String) throws -> (m3Us: M3UDict, tracks: TrackDict) {
    let artists = try fm.contentsOfDirectory(atPath: typePath)
    var m3Us: M3UDict = [:]
    var tracks: TrackDict = [:]

    // Make a dictionary for each one and write it out
    for artist in artists {
      let filePath = typePath + artist

      var isDir: ObjCBool = false
      if(fm.fileExists(atPath: filePath, isDirectory: &isDir) && isDir.boolValue) {
        let albumDict = try scanAlbums(artistPath: filePath + "/")

        m3Us[artist]   = albumDict.m3Us
        tracks[artist] = albumDict.tracks
      }
    }

    return (m3Us, tracks)
  }

  func scanFolders() {
    guard bmData != nil else { return }

    if(bmURL.startAccessingSecurityScopedResource()) {
      do {
        allM3UDict.removeAll()
        allTracksDict.removeAll()

        try scanTypes()

        for type in typesList {
          let artistDict = try scanArtists(typePath: rootPath + type + "/")

          allM3UDict[type]    = artistDict.m3Us
          allTracksDict[type] = artistDict.tracks
        }

        if(typesList.count > 0) { type = typesList[0] }
        try type.write(toFile: typeFile, atomically: true, encoding: .utf8)

        m3UDict    = allM3UDict[self.type] ?? [:]
        tracksDict = allTracksDict[self.type] ?? [:]
        musicPath  = rootPath + type + "/"

        let data1 = try PropertyListEncoder().encode(allM3UDict)
        try data1.write(to: URL(fileURLWithPath:m3UFile))

        let data2 = try PropertyListEncoder().encode(allTracksDict)
        try data2.write(to: URL(fileURLWithPath:trackFile))
        bmURL.stopAccessingSecurityScopedResource()

        artist = ""
        album  = ""

        playerSelection.setTypes(newType: type, newTypeList: typesList)
        playerSelection.setAll(newArtist: artist, newAlbum: album, newList: tracksDict.keys.sorted())
      } catch {
          // Handle error
      }
    }
  }

  func typeChanged(newType: String) {
    if(type == newType) { return }

    type = newType
    do {
      try type.write(toFile: typeFile, atomically: true, encoding: .utf8)
    } catch {
      // Ignore error
    }

    m3UDict    = allM3UDict[self.type] ?? [:]
    tracksDict = allTracksDict[self.type] ?? [:]
    musicPath = rootPath + type + "/"

    artist = ""
    album  = ""

    playerSelection.setAll(newArtist: artist, newAlbum: album, newList: tracksDict.keys.sorted())
  }
}
