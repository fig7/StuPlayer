//
//  TimeUtil.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 28/06/2024.
//

import Foundation

func timeStr(from time: TimeInterval) -> String {
  if(!time.canMakeInt()) { return "--:--:--" }
  let timeSecs = Int(time)

  let hours = timeSecs / 3600
  let mins  = (timeSecs - 3600*hours) / 60
  let secs  = timeSecs - 60*hours - 60*mins
  return (hours > 0) ? String(format:"%d:%02d:%02d", hours, mins, secs) : String(format:"%d:%02d", mins, secs)
}

func lyricsTimeStr(from time: TimeInterval) -> String {
  if(!time.canMakeInt()) { return "--:--:--" }
  let timeSecs = Int(time)

  let hours = timeSecs / 3600
  let mins  = (timeSecs - 3600*hours) / 60
  let secs  = timeSecs - 60*hours - 60*mins
  let hths  = Int((time - TimeInterval(timeSecs)) * 100.0)
  return (hours > 0) ? String(format:"%d:%02d:%02d.%02d", hours, mins, secs, hths) : String(format:"%d:%02d.%02d", mins, secs, hths)
}
