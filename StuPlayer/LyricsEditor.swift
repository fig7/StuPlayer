//
//  LyricsEditor.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 13/04/2025.
//

import Foundation

class LyricsEditor : ObservableObject {
  @Published var lyricsEdit = false

  @Published var lyricsTrack: URL? = nil
  @Published var lyricsContent = ""
  @Published var lyricsText    = ""

  func editLyrics(_ trackURL: URL?) {
    guard let trackURL else { return }

    let splURL = trackURL.deletingPathExtension().appendingPathExtension("spl")
    let lyricsData = NSData(contentsOf: splURL)

    lyricsTrack   = trackURL
    lyricsContent = (lyricsData != nil) ? String(decoding: lyricsData!, as: UTF8.self) : ""

    lyricsText = lyricsContent
    lyricsEdit = true
  }
}
