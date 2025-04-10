//
//  LogFileManager.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 29/03/2024.
//

import Foundation

enum LogCategory { case LogInfo, LogInitError, LogScanError, LogThrownError, LogPlaybackError, LogFileError }
enum LogError: Error { case URLNotSet, ExtendLogFailed }

class LogFileManager {
  let fm = FileManager.default
  var baseURL: URL?
  var logFileURL: URL?
  var logFile2URL: URL?
  var logStartDate = ""

  func extendLogFile(newLogFile: Bool) throws -> Bool {
    guard let baseURL, let logFileURL, let logFile2URL else { throw LogError.URLNotSet }

    // Check file size. If > 100KB, move existing to .1 and truncate .0
    let logFilePath = logFileURL.filePath()
    do {
      let logFileAtt  = try fm.attributesOfItem(atPath: logFilePath)
      let fileSize    = logFileAtt[.size] as? UInt64
      guard let fileSize else {
        print("Error creating log file: " + logFilePath + " has no size attribute");
        throw LogError.ExtendLogFailed
      }

      if(fileSize > 100000) {
        let logFile2Path = logFile2URL.filePath()
        if(fm.fileExists(atPath: logFile2Path)) {
          try fm.removeItem(atPath: logFile2Path)
        }

        try fm.copyItem(atPath: logFilePath, toPath: logFile2Path)

        if(newLogFile) {
          let logStart = "StuPlayer log for " + baseURL.filePath() + " at " + logStartDate + "...\n"
          try (logStart + "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
        } else {
          let logContd = "StuPlayer log contd. for " + baseURL.filePath() + " at " + logStartDate + "...\n"
          try (logContd + "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
        }
        
        return true
      }
    } catch {
      print("Error extending log file: " + logFilePath)
      print("Error thrown:" + error.localizedDescription)
      throw LogError.ExtendLogFailed
    }

    return false
  }

  private func clearURL() {
    self.baseURL     = nil
    self.logFileURL  = nil
    self.logFile2URL = nil
  }

  func setURL(baseURL: URL) {
    self.baseURL = baseURL

    if(!baseURL.startAccessingSecurityScopedResource()) {
      print("Error creating log file: URL access denied")
      self.baseURL = nil

      return
    }
    defer { baseURL.stopAccessingSecurityScopedResource() }

    // Create logfile, if it does not exist
    logFileURL  = baseURL.appendingFile(file: "StuPlayer0.log")
    logFile2URL = baseURL.appendingFile(file: "StuPlayer1.log")
    guard let logFileURL else {
      print("Error malformed log file URL")
      clearURL()

      return
    }

    logStartDate = Date().description
    let logStart = "StuPlayer log for " + baseURL.folderPath() + " at " + logStartDate + "...\n"
    print(logStart)

    let logFilePath = logFileURL.filePath()
    do {
      var isDir: ObjCBool = false
      if(!fm.fileExists(atPath: logFilePath, isDirectory: &isDir)) {
        try (logStart + "\n").write(toFile: logFilePath, atomically: true, encoding: .utf8)
        return
      } else if(isDir.boolValue) {
        print("Error creating log file: " + logFilePath + " is a directory")
        clearURL()

        return
      }

      if(try extendLogFile(newLogFile: true)) { return }
    } catch {
      print("Error creating log file: " + logFilePath)
      print("Error thrown:" + error.localizedDescription)
      clearURL()

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
      print("Error appending header to log file: " + logFilePath)
      clearURL()
    }
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
      _ = try extendLogFile(newLogFile: false)

      guard let logFileURL else {
        print("Log file not set")
        return
      }

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
