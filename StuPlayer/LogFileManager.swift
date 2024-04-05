//
//  LogFileManager.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 29/03/2024.
//

import Foundation

enum LogCategory {
  case LogInfo, LogInitError, LogScanError, LogThrownError, LogPlaybackError, LogFileError
}

class LogFileManager {
  let fm = FileManager.default
  var logFileURL: URL?

  func setURL(baseURL: URL) {
    if(!baseURL.startAccessingSecurityScopedResource()) {
      print("Error creating log file: URL access denied")
      return
    }

    self.logFileURL = nil
    defer { baseURL.stopAccessingSecurityScopedResource() }

    // Create logfile, if it does not exist
    let logFileURL  = baseURL.appendingFile(file: "StuPlayer0.log")
    let logFilePath = logFileURL.filePath()

    let logStart = "StuPlayer log for " + baseURL.filePath() + " at " + Date().description + "...\n"
    print(logStart)

    do {
      var isDir: ObjCBool = false
      if(!fm.fileExists(atPath: logFilePath, isDirectory: &isDir)) {
        try (logStart + "\n").write(toFile: logFilePath, atomically: true, encoding: .utf8)

        self.logFileURL = logFileURL
        return
      } else if(isDir.boolValue) {
        print("Error creating log file: " + logFilePath + " is a directory")
        return
      }

      // Check file size. If > 100KB, move existing to .1 and truncate .0
      do {
        let logFileAtt = try fm.attributesOfItem(atPath: logFilePath)
        let fileSize = logFileAtt[.size] as? UInt64
        guard let fileSize else { print("Error creating log file: " + logFilePath + " has no size attribute"); return }

        if(fileSize > 100000) {
          let logFile2URL  = baseURL.appendingFile(file: "StuPlayer1.log")
          let logFile2Path = logFile2URL.filePath()

          if(fm.fileExists(atPath: logFile2Path)) {
            try fm.removeItem(atPath: logFile2Path)
          }

          try fm.copyItem(atPath: logFilePath, toPath: logFile2Path)
          try (logStart + "\n").write(toFile: logFilePath, atomically: true, encoding: .utf8)

          self.logFileURL = logFileURL
          return
        }
      } catch {
        print("Error extending log file: " + logFilePath)
        print("Error thrown:" + error.localizedDescription)
      }
    } catch {
      print("Error creating log file: " + logFilePath)
      print("Error thrown:" + error.localizedDescription)
      return
    }

    // Append logStart to existing log file
    do {
      let fileHandle = try FileHandle(forWritingTo: logFileURL)
      fileHandle.seekToEndOfFile()

      let textData = Data(("\n\n" + logStart + "\n").utf8)
      fileHandle.write(textData)
      fileHandle.closeFile()
    } catch {
      print("Error appending to log file: " + logFilePath)
    }

    self.logFileURL = logFileURL
  }

  func append(throwType: String, logMessage: String) {
    append(logCat: .LogThrownError, logMessage: String(format: "%@, %@", throwType, logMessage))
  }

  func append(logCat: LogCategory, logMessage: String) {
    var logString = ""
    switch(logCat) {
    case .LogInfo:
      logString = "Info: "
    case .LogInitError:
      logString = "Init error: "
    case .LogScanError:
      logString = "Scan error: "
    case .LogThrownError:
      logString = "Exception error: "
    case .LogPlaybackError:
      logString = "Playback error: "
    case .LogFileError:
      logString = "File error: "
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
}
