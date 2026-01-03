//
//  CircularStrokeGaugeStyle.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI

struct CircularStrokeGaugeStyle: GaugeStyle {
    var lineWidth: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: lineWidth)

            let progress = configuration.value

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))

            configuration.label
        }
    }
}
