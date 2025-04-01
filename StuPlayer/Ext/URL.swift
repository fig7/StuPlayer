//
//  URL.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/04/2024.
//

import Foundation

extension URL {
  func filePath() -> String {
    if #available(macOS 13.0, *) {
      path(percentEncoded: false)
    } else {
      path.removingPercentEncoding! + "/"
    }
  }

  func appendingFile(file: String) -> URL {
    if #available(macOS 13.0, *) {
      return appending(path: file, directoryHint: URL.DirectoryHint.notDirectory)
    } else {
      return appendingPathComponent(file, isDirectory: false)
    }
  }
}
