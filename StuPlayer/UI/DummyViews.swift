//
//  DummyViews.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 10/01/2025.
//

import SwiftUI

struct DummyView : View {
  init(action: @escaping () -> Void) { self.onPressed = action }

  var onPressed: () -> Void
  var body: some View {
    Button("", action: onPressed).allowsHitTesting(/*@START_MENU_TOKEN@*/false/*@END_MENU_TOKEN@*/).opacity(0).frame(maxWidth: 0, maxHeight: 0)
  }
}

// Really just to extend the two ItemView types, but I don't know how to do that
extension View {
  func sync(_ published: Binding<Int>, with binding: Binding<Bool>, for itemIndex: Int) -> some View {
    self
      .onChange(of: published.wrappedValue) { published in binding.wrappedValue = (published == itemIndex) }
      .onChange(of: binding.wrappedValue)   { binding   in if(binding) { published.wrappedValue = itemIndex } else if(published.wrappedValue == itemIndex) { published.wrappedValue = -1 } }
  }
}
