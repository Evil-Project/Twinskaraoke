//
//  ContentView.swift
//  Twinskaraoke Watch App
//
//  Created by xiaoyuan on 2026/4/19.
//

import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack {
      Text("Welcome to Home")
        .font(.largeTitle)
      MusicGridView()
        .frame(height: 300)
        .cornerRadius(12)
    }
    .padding()
  }
}

#Preview {
  ContentView()
}
