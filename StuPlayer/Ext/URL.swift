//
//  URL.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 04/04/2024.
//

import Foundation

extension URL {
  func filePath() -> String {
    guard !hasDirectoryPath else { fatalError("URL.filePath called: hasDirectoryPath is true") }

    if #available(macOS 13.0, *) {
      return path(percentEncoded: false)
    } else {
      return path.removingPercentEncoding!
    }
  }

  func folderPath() -> String {
    guard hasDirectoryPath else { fatalError("URL.folderPath called: hasDirectoryPath is false") }

    if #available(macOS 13.0, *) {
      return path(percentEncoded: false)
    } else {
      // On macOS 12.x, extracting directory paths from a URL doesn't add a "/". So we add one here.
      return path.removingPercentEncoding! + "/"
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
