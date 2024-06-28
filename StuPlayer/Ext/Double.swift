//
//  Double.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 28/06/2024.
//

import Foundation

extension Double {
  func canMakeInt() -> Bool {
    let roundedValue = rounded()
    return ((roundedValue >= Double(Int.min)) && (roundedValue <= Double(Int.max)))
  }

  func toIntStr() -> String {
    if(!canMakeInt()) { return "INVALID" }

    let roundedValue = rounded()
    return "\(Int(roundedValue))"
  }
}
