//
//  BrowserScrollView.swift
//  StuPlayer
//
//  Created by Stuart Fisher on 10/01/2025.
//

import SwiftUI

private struct BrowserItemView : View {
  @State private var browserPopover = false

  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection

  let itemText: String
  let itemIndex: Int

  let highlighted: Bool

  init(model: PlayerDataModel, playerSelection: PlayerSelection, itemText: String, itemIndex: Int) {
    self.model = model
    self.playerSelection = playerSelection

    self.itemText     = itemText
    self.itemIndex    = itemIndex

    highlighted = (itemIndex == playerSelection.browserScrollPos)
  }

  var body: some View {
    Text(itemText).fontWeight(highlighted ? .semibold : nil).padding(.horizontal, 4)
      .background(highlighted ? RoundedRectangle(cornerRadius: 5).foregroundColor(.blue.opacity(0.3)) : nil)
      .onTapGesture { model.browserItemClicked(itemIndex: itemIndex, itemText: itemText) }
      .onHover(perform: { hovering in
        if(hovering) {
          if(playerSelection.browserPopover == itemIndex) { return }
          model.browserDelayAction(itemIndex) { playerSelection.browserPopover = itemIndex }
        } else {
          model.delayCancel()
          playerSelection.browserPopover = -1
        } })
      .popover(isPresented: $browserPopover) { Text(playerSelection.browserItemInfo).font(.headline).padding() }
      .sync($playerSelection.browserPopover, with: $browserPopover, for: itemIndex)
  }
}

struct BrowserScrollView : View {
  let model: PlayerDataModel
  @ObservedObject var playerSelection: PlayerSelection

  let hasFocus: Bool
  let textHeight: CGFloat
  let viewHeight: CGFloat

  var body : some View {
    ScrollViewReader { scrollViewProxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if(hasFocus) {
            HStack() {
              DummyView(action: { browserDown     (proxy: scrollViewProxy) }).keyboardShortcut(.downArrow, modifiers: [])
              DummyView(action: { browserPageDown (proxy: scrollViewProxy) }).keyboardShortcut(.pageDown,  modifiers: [])
              DummyView(action: { browserEnd      (proxy: scrollViewProxy) }).keyboardShortcut(.end,       modifiers: [])

              DummyView(action: { browserUp      (proxy: scrollViewProxy) }).keyboardShortcut(.upArrow, modifiers: [])
              DummyView(action: { browserPageUp  (proxy: scrollViewProxy) }).keyboardShortcut(.pageUp,  modifiers: [])
              DummyView(action: { browserHome    (proxy: scrollViewProxy) }).keyboardShortcut(.home,    modifiers: [])
            }.frame(maxWidth: 0, maxHeight: 0)
          }

          LazyVStack(alignment: .leading) {
            ForEach(Array(playerSelection.browserItems.enumerated()), id: \.offset) { itemIndex, itemText in
              BrowserItemView(model: model, playerSelection: playerSelection, itemText: itemText, itemIndex: itemIndex)
            }
          }.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  func browserDown(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.browserItems.count - 1
    if(playerSelection.browserScrollPos >= listLimit) { return }

    playerSelection.browserScrollPos += 1;
    proxy.scrollTo(playerSelection.browserScrollPos)
  }

  func browserPageDown(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.browserItems.count - 1
    if(playerSelection.browserScrollPos >= listLimit) { return }

    let linesToScroll = Int(0.5 + viewHeight / textHeight)
    var newScrollPos  = ((playerSelection.browserScrollPos < 0) ? 0 : playerSelection.browserScrollPos) + linesToScroll
    if(newScrollPos > listLimit) { newScrollPos = listLimit }

    playerSelection.browserScrollPos = newScrollPos;
    proxy.scrollTo(playerSelection.browserScrollPos)
  }

  func browserEnd(proxy: ScrollViewProxy) {
    let listLimit = playerSelection.browserItems.count - 1
    if(playerSelection.browserScrollPos >= listLimit) { return }

    playerSelection.browserScrollPos = listLimit;
    proxy.scrollTo(playerSelection.browserScrollPos)
  }

  func browserUp(proxy: ScrollViewProxy) {
    if(playerSelection.browserScrollPos <= 0) { return }

    playerSelection.browserScrollPos -= 1;
    proxy.scrollTo(playerSelection.browserScrollPos)
  }

  func browserPageUp(proxy: ScrollViewProxy) {
    if(playerSelection.browserScrollPos <= 0) { return }

    let linesToScroll = Int(0.5 + viewHeight / textHeight)
    var newScrollPos = playerSelection.browserScrollPos - linesToScroll
    if(newScrollPos < 0) { newScrollPos = 0 }

    playerSelection.browserScrollPos = newScrollPos;
    proxy.scrollTo(playerSelection.browserScrollPos)
  }

  func browserHome(proxy: ScrollViewProxy) {
    if(playerSelection.browserScrollPos > 0) { playerSelection.browserScrollPos = 0 }
    proxy.scrollTo(0)
  }
}
