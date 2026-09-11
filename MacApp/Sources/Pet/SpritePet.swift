//  SpritePet.swift
//  Desktop Pet
//
//  A spritesheet pet from codex-pets.net: atlas slicing and drawing.

import Cocoa

final class SpritePet {
    /// Row order of the atlas. Rows 0-8 exist in both v1 and v2 sheets; the
    /// two look-around rows are v2 only.
    enum Track: Int, CaseIterable {
        case idle = 0, runningRight, runningLeft, waving, jumping
        case failed, waiting, running, review
        case lookAroundRight, lookAroundLeft

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .runningRight: return "Run right"
            case .runningLeft: return "Run left"
            case .waving: return "Waving"
            case .jumping: return "Jumping"
            case .failed: return "Failed"
            case .waiting: return "Waiting"
            case .running: return "Running"
            case .review: return "Review"
            case .lookAroundRight: return "Look around - right side"
            case .lookAroundLeft: return "Look around - left side"
            }
        }
    }

    /// v1 sheets stop at `review`; anything past the end falls back to idle.
    func resolve(_ track: Track) -> Track {
        track.rawValue < rows ? track : .idle
    }

    let id: String
    let name: String
    let folder: URL
    let image: NSImage
    private let sheet: CGImage?
    private var cells: [Int: CGImage] = [:]
    let cell: NSSize
    let columns: Int
    let rows: Int
    /// Frames actually drawn in each row.
    let frameCounts: [Int]

    init?(folder: URL) {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("pet.json")),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let sheetName = json["spritesheetPath"] as? String ?? "spritesheet.webp"
        let sheet = folder.appendingPathComponent(sheetName)
        guard let image = NSImage(contentsOf: sheet),
            let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
        else { return nil }

        self.sheet = rep.cgImage
        self.id = json["id"] as? String ?? folder.lastPathComponent
        self.name = json["displayName"] as? String ?? self.id
        self.folder = folder
        self.image = image

        // 8 columns is the atlas constant; the cell is square-ish 192x208, so
        // the row count follows from the sheet height.
        let pixelsWide = CGFloat(rep.pixelsWide), pixelsHigh = CGFloat(rep.pixelsHigh)
        columns = 8
        let cellW = pixelsWide / CGFloat(columns)
        let cellH = cellW * 208.0 / 192.0
        rows = max(1, Int((pixelsHigh / cellH).rounded()))
        cell = NSSize(width: cellW, height: pixelsHigh / CGFloat(rows))

        frameCounts = SpritePet.measureFrames(
            rep, columns: columns, rows: rows,
            cell: NSSize(
                width: cellW,
                height: pixelsHigh / CGFloat(rows)))
        image.size = NSSize(width: pixelsWide, height: pixelsHigh)
    }

    /// A cell counts as used when it has a meaningful number of opaque pixels.
    private static func measureFrames(
        _ rep: NSBitmapImageRep, columns: Int, rows: Int,
        cell: NSSize
    ) -> [Int] {
        guard let data = rep.bitmapData, rep.samplesPerPixel >= 4 else {
            return Array(repeating: columns, count: rows)
        }
        let spp = rep.samplesPerPixel, rowBytes = rep.bytesPerRow
        let cw = Int(cell.width), chh = Int(cell.height)
        var counts: [Int] = []
        for r in 0..<rows {
            var used = 0
            for c in 0..<columns {
                var filled = 0
                let y0 = r * chh, x0 = c * cw
                var y = y0
                while y < min(y0 + chh, rep.pixelsHigh) {
                    var x = x0
                    while x < min(x0 + cw, rep.pixelsWide) {
                        if data[y * rowBytes + x * spp + 3] > 8 { filled += 1 }
                        x += 2  // sampling every other pixel is plenty
                    }
                    y += 2
                }
                if filled > 50 { used += 1 }
            }
            counts.append(max(1, used))
        }
        return counts
    }

    func frames(in track: Track) -> Int {
        let row = resolve(track).rawValue
        return row < frameCounts.count ? frameCounts[row] : 1
    }

    /// Draw one frame, scaled to fit `rect` and anchored to its bottom.
    func draw(track: Track, frame: Int, in rect: NSRect, flipped: Bool = false) {
        let row = min(resolve(track).rawValue, rows - 1)
        let column = min(frame, (row < frameCounts.count ? frameCounts[row] : 1) - 1)
        // the sheet's origin is top-left; NSImage draws from bottom-left
        let source = NSRect(
            x: CGFloat(column) * cell.width,
            y: image.size.height - CGFloat(row + 1) * cell.height,
            width: cell.width, height: cell.height)

        // Snap to 1:1 when the cell nearly fits: an unscaled blit is far
        // cheaper than resampling every frame, and pixel art looks better for
        // it too.
        var scale = min(rect.width / cell.width, rect.height / cell.height)
        if scale > 0.92 && scale < 1.08 { scale = 1 }
        let size = NSSize(
            width: (cell.width * scale).rounded(),
            height: (cell.height * scale).rounded())
        let target = NSRect(
            x: (rect.midX - size.width / 2).rounded(), y: rect.minY.rounded(),
            width: size.width, height: size.height)

        NSGraphicsContext.saveGraphicsState()
        if flipped {
            let t = NSAffineTransform()
            t.translateX(by: target.midX * 2, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
            t.concat()
        }
        if let cropped = cellImage(row: row, column: column),
            let context = NSGraphicsContext.current?.cgContext
        {
            context.interpolationQuality = scale == 1 ? .none : .medium
            context.draw(cropped, in: target)
        } else {
            image.draw(
                in: target, from: source, operation: .sourceOver, fraction: 1,
                respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Each cell is baked into its own small bitmap the first time it is
    /// drawn.
    ///
    /// Cropping alone is not enough: a cropped CGImage is only a window onto
    /// the parent's data provider, so every draw re-locks the whole
    /// 1536x2288 sheet — which profiling showed as CGSImageDataLock eating
    /// most of the frame. Copying the cell into a standalone buffer turns
    /// each draw into a plain blit.
    private func cellImage(row: Int, column: Int) -> CGImage? {
        let key = row * 100 + column
        if let cached = cells[key] { return cached }
        guard let sheet else { return nil }
        let rect = CGRect(
            x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height,
            width: cell.width, height: cell.height)
        guard let cropped = sheet.cropping(to: rect) else { return nil }

        let width = Int(cell.width), height = Int(cell.height)
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            cells[key] = cropped
            return cropped
        }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        let baked = context.makeImage() ?? cropped
        cells[key] = baked
        return baked
    }
}

/// Where sprite pets live and how they are found.
