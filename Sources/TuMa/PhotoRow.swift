// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct PhotoRow: View {
    let photo: PhotoRecord
    let thumbnail: NSImage?
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                ZStack {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    } else { Image(systemName: "photo").foregroundStyle(.tertiary) }
                }.frame(width: thumbnailWidth(geometry.size.width), height: min(46, thumbnailWidth(geometry.size.width) * 0.82))
                VStack(alignment: .leading, spacing: 5) {
                    Text(photo.name).font(.callout).lineLimit(1).truncationMode(.middle)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { photoStatus; resolution }
                        VStack(alignment: .leading, spacing: 2) { photoStatus; resolution }
                    }.font(.caption).foregroundStyle(.secondary)
                }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
    }
    private func thumbnailWidth(_ width: CGFloat) -> CGFloat { min(72, max(32, width * 0.25)) }
    private var photoStatus: some View {
        HStack(spacing: 4) {
            if photo.done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary) }
            Text(photo.exported ? "已导出" : photo.done ? "已完成" : photo.strokes.isEmpty ? "待打码" : "已涂抹 · 待确认").fixedSize()
        }
    }
    private var resolution: some View {
        Text("\(photo.width) × \(photo.height)").monospacedDigit().fixedSize()
            .accessibilityLabel("分辨率 \(photo.width) 乘 \(photo.height) 像素")
    }
}

