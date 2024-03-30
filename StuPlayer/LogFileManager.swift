//
//  LogFileManager.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 29/03/2024.
//

import Foundation

enum LogCategory {
  case LogInfo, LogThrownError, LogPlaybackError
}

class LogFileManager {
  let fm = FileManager.default
  var logFileURL: URL?

  func setURL(baseURL: URL) {
    if(!baseURL.startAccessingSecurityScopedResource()) {
      print("Error creating log file 1")
      return
    }

    self.logFileURL = nil
    defer { baseURL.stopAccessingSecurityScopedResource() }

    // Create logfile, if it does not exist
    let logFileURL  = baseURL.appending(path: "SPLogFile.0", directoryHint: URL.DirectoryHint.notDirectory)
    let logFilePath = logFileURL.path(percentEncoded: false)

    let logStart = "StuPlayer log for " + baseURL.path(percentEncoded: false) + " at " + Date().description + "...\n"
    print(logStart)

    do {
      var isDir: ObjCBool = false
      if(!fm.fileExists(atPath: logFilePath, isDirectory: &isDir)) {
        let success = fm.createFile(atPath: logFilePath, contents: nil)
        if(!success) {
          print("Error creating log file 2")
        }

        try (logStart + "\n").write(toFile: logFilePath, atomically: true, encoding: .utf8)
        self.logFileURL = logFileURL
        return
      } else if(isDir.boolValue) {
        print("Error creating log file 3")
        return
      }

      // Check file size. If > 100KB, move existing to .1 and truncate .0
      do {
        let logFileAtt = try fm.attributesOfItem(atPath: logFilePath)
        let fileSize = logFileAtt[.size] as? UInt64
        guard let fileSize else { print("Error creating log file 4"); return }

        if(fileSize > 100000) {
          let logFile2URL  = baseURL.appending(path: "SPLogFile.1", directoryHint: URL.DirectoryHint.notDirectory)
          let logFile2Path = logFile2URL.path()

          if(fm.fileExists(atPath: logFile2Path)) {
            try fm.removeItem(atPath: logFile2Path)
          }
          try fm.copyItem(atPath: logFilePath, toPath: logFile2Path)

          try (logStart + "\n").write(toFile: logFilePath, atomically: true, encoding: .utf8)
          self.logFileURL = logFileURL
          return
        }
      } catch {
        print("Error creating log file 5")
      }
    } catch {
      print("Error creating log file 6")
      return
    }

    self.logFileURL = logFileURL
    append(logString: "\n\n" + logStart)
  }

  func append(throwType: String, logMessage: String) {
    append(logCat: .LogThrownError, logMessage: String(format: "%@, %@", throwType, logMessage))
  }

  func append(logCat: LogCategory, logMessage: String) {
    var logString = ""
    switch(logCat) {
    case .LogInfo:
      logString = "Info: "
    case .LogThrownError:
      logString = "Exception: "
    case .LogPlaybackError:
      logString = "Playback error: "
    }

    logString = logString + logMessage
    print(logString)

    do {
      guard let logFileURL else { print("Log file not set"); return }
      let fileHandle = try FileHandle(forWritingTo: logFileURL)
      fileHandle.seekToEndOfFile()

      let textData = Data((logString + "\n").utf8)
      fileHandle.write(textData)
      fileHandle.closeFile()
    } catch {
      print("Logging to file failed")
    }
  }

  func append(logString: String) {
    print(logString)

    do {
      guard let logFileURL else { print("Log file not set"); return }
      let fileHandle = try FileHandle(forWritingTo: logFileURL)
      fileHandle.seekToEndOfFile()

      let textData = Data((logString + "\n").utf8)
      fileHandle.write(textData)
      fileHandle.closeFile()
    } catch {
      print("Logging to file failed")
    }
  }
}
