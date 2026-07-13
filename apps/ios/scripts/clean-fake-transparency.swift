#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Bounds {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int
}

struct Options {
    let inputPath: String
    let outputPath: String
    let keepMainSubject: Bool
    let removeAllLightCheckerPixels: Bool
    let removePaleWash: Bool
    let cropPadding: Int
}

func parseOptions() throws -> Options {
    var args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 2 else {
        throw NSError(
            domain: "clean-fake-transparency",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Usage: clean-fake-transparency.swift input.png output.png [--keep-main-subject] [--remove-all-light-checker] [--remove-pale-wash] [--padding N]"]
        )
    }

    let inputPath = args.removeFirst()
    let outputPath = args.removeFirst()
    var keepMainSubject = false
    var removeAllLightCheckerPixels = false
    var removePaleWash = false
    var cropPadding = 24

    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--keep-main-subject":
            keepMainSubject = true
        case "--remove-all-light-checker":
            removeAllLightCheckerPixels = true
        case "--remove-pale-wash":
            removePaleWash = true
        case "--padding":
            guard let value = args.first, let padding = Int(value) else {
                throw NSError(domain: "clean-fake-transparency", code: 2, userInfo: [NSLocalizedDescriptionKey: "--padding requires an integer"])
            }
            args.removeFirst()
            cropPadding = max(0, padding)
        default:
            throw NSError(domain: "clean-fake-transparency", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unknown option: \(arg)"])
        }
    }

    return Options(
        inputPath: inputPath,
        outputPath: outputPath,
        keepMainSubject: keepMainSubject,
        removeAllLightCheckerPixels: removeAllLightCheckerPixels,
        removePaleWash: removePaleWash,
        cropPadding: cropPadding
    )
}

func loadRGBA(path: String) throws -> (width: Int, height: Int, pixels: [UInt8]) {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "clean-fake-transparency", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to read image: \(path)"])
    }

    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "clean-fake-transparency", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unable to create bitmap context"])
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (width, height, pixels)
}

func saveRGBA(path: String, width: Int, height: Int, pixels: inout [UInt8]) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
    let image = context.makeImage() else {
        throw NSError(domain: "clean-fake-transparency", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unable to create output image"])
    }

    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "clean-fake-transparency", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unable to create PNG destination: \(path)"])
    }

    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "clean-fake-transparency", code: 8, userInfo: [NSLocalizedDescriptionKey: "Unable to write PNG: \(path)"])
    }
}

func pixelOffset(_ pixel: Int) -> Int {
    pixel * 4
}

func isLightCheckerboardPixel(_ pixels: [UInt8], _ offset: Int) -> Bool {
    let r = Int(pixels[offset])
    let g = Int(pixels[offset + 1])
    let b = Int(pixels[offset + 2])
    let maxChannel = max(r, max(g, b))
    let minChannel = min(r, min(g, b))
    let brightness = (r + g + b) / 3
    return brightness >= 226 && maxChannel - minChannel <= 14
}

func removeBorderReachableCheckerboard(width: Int, height: Int, pixels: inout [UInt8]) -> (removed: Int, remaining: Int) {
    var visited = [Bool](repeating: false, count: width * height)
    var queue = [Int]()
    queue.reserveCapacity(width * height / 2)

    func enqueue(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let pixel = y * width + x
        guard !visited[pixel] else { return }
        let offset = pixelOffset(pixel)
        if pixels[offset + 3] == 0 || isLightCheckerboardPixel(pixels, offset) {
            visited[pixel] = true
            queue.append(pixel)
        }
    }

    for x in 0..<width {
        enqueue(x, 0)
        enqueue(x, height - 1)
    }
    for y in 0..<height {
        enqueue(0, y)
        enqueue(width - 1, y)
    }

    var removed = 0
    var head = 0
    while head < queue.count {
        let pixel = queue[head]
        head += 1
        let x = pixel % width
        let y = pixel / width
        let offset = pixelOffset(pixel)
        if pixels[offset + 3] != 0 {
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
            removed += 1
        }
        enqueue(x + 1, y)
        enqueue(x - 1, y)
        enqueue(x, y + 1)
        enqueue(x, y - 1)
    }

    var remaining = 0
    for pixel in 0..<(width * height) {
        let offset = pixelOffset(pixel)
        if pixels[offset + 3] != 0 && isLightCheckerboardPixel(pixels, offset) {
            remaining += 1
        }
        if pixels[offset + 3] == 0 {
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
        }
    }

    return (removed, remaining)
}

func keepLargestComponent(width: Int, height: Int, pixels: inout [UInt8]) -> Int {
    var visited = [Bool](repeating: false, count: width * height)
    var largest = [Int]()
    var queue = [Int]()

    func isVisible(_ pixel: Int) -> Bool {
        pixels[pixelOffset(pixel) + 3] > 0
    }

    for pixel in 0..<(width * height) where !visited[pixel] && isVisible(pixel) {
        var component = [Int]()
        queue.removeAll(keepingCapacity: true)
        visited[pixel] = true
        queue.append(pixel)

        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            component.append(current)
            let x = current % width
            let y = current / width
            let neighbors = [
                x > 0 ? current - 1 : -1,
                x + 1 < width ? current + 1 : -1,
                y > 0 ? current - width : -1,
                y + 1 < height ? current + width : -1
            ]
            for neighbor in neighbors where neighbor >= 0 && !visited[neighbor] && isVisible(neighbor) {
                visited[neighbor] = true
                queue.append(neighbor)
            }
        }

        if component.count > largest.count {
            largest = component
        }
    }

    var keep = [Bool](repeating: false, count: width * height)
    for pixel in largest {
        keep[pixel] = true
    }

    var removed = 0
    for pixel in 0..<(width * height) where isVisible(pixel) && !keep[pixel] {
        let offset = pixelOffset(pixel)
        pixels[offset] = 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = 0
        removed += 1
    }

    return removed
}

func removeAllLightCheckerboardPixels(width: Int, height: Int, pixels: inout [UInt8]) -> Int {
    var removed = 0
    for pixel in 0..<(width * height) {
        let offset = pixelOffset(pixel)
        if pixels[offset + 3] != 0 && isLightCheckerboardPixel(pixels, offset) {
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
            removed += 1
        }
    }
    return removed
}

func countLightCheckerboardPixels(width: Int, height: Int, pixels: [UInt8]) -> Int {
    var count = 0
    for pixel in 0..<(width * height) {
        let offset = pixelOffset(pixel)
        if pixels[offset + 3] != 0 && isLightCheckerboardPixel(pixels, offset) {
            count += 1
        }
    }
    return count
}

func removePaleWashPixels(width: Int, height: Int, pixels: inout [UInt8]) -> Int {
    var removed = 0
    for pixel in 0..<(width * height) {
        let offset = pixelOffset(pixel)
        guard pixels[offset + 3] != 0 else { continue }

        let r = Int(pixels[offset])
        let g = Int(pixels[offset + 1])
        let b = Int(pixels[offset + 2])
        let maxChannel = max(r, max(g, b))
        let minChannel = min(r, min(g, b))
        let brightness = (r + g + b) / 3
        let chroma = maxChannel - minChannel

        if brightness >= 206 && chroma <= 58 {
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
            removed += 1
        }
    }
    return removed
}

func opaqueBounds(width: Int, height: Int, pixels: [UInt8]) -> Bounds? {
    var bounds = Bounds(left: width, top: height, right: 0, bottom: 0)
    for y in 0..<height {
        for x in 0..<width {
            let pixel = y * width + x
            if pixels[pixelOffset(pixel) + 3] > 0 {
                bounds.left = min(bounds.left, x)
                bounds.top = min(bounds.top, y)
                bounds.right = max(bounds.right, x + 1)
                bounds.bottom = max(bounds.bottom, y + 1)
            }
        }
    }
    return bounds.right > bounds.left && bounds.bottom > bounds.top ? bounds : nil
}

func crop(width: Int, height: Int, pixels: [UInt8], bounds: Bounds, padding: Int) -> (width: Int, height: Int, pixels: [UInt8]) {
    let left = max(0, bounds.left - padding)
    let top = max(0, bounds.top - padding)
    let right = min(width, bounds.right + padding)
    let bottom = min(height, bounds.bottom + padding)
    let croppedWidth = right - left
    let croppedHeight = bottom - top
    var cropped = [UInt8](repeating: 0, count: croppedWidth * croppedHeight * 4)

    for y in 0..<croppedHeight {
        for x in 0..<croppedWidth {
            let src = pixelOffset((top + y) * width + left + x)
            let dst = pixelOffset(y * croppedWidth + x)
            cropped[dst] = pixels[src]
            cropped[dst + 1] = pixels[src + 1]
            cropped[dst + 2] = pixels[src + 2]
            cropped[dst + 3] = pixels[src + 3]
        }
    }

    return (croppedWidth, croppedHeight, cropped)
}

do {
    let options = try parseOptions()
    var image = try loadRGBA(path: options.inputPath)
    let cleanup = removeBorderReachableCheckerboard(width: image.width, height: image.height, pixels: &image.pixels)
    let lightCheckerRemoved = options.removeAllLightCheckerPixels
        ? removeAllLightCheckerboardPixels(width: image.width, height: image.height, pixels: &image.pixels)
        : 0
    let paleWashRemoved = options.removePaleWash
        ? removePaleWashPixels(width: image.width, height: image.height, pixels: &image.pixels)
        : 0
    let componentRemoved = options.keepMainSubject ? keepLargestComponent(width: image.width, height: image.height, pixels: &image.pixels) : 0
    let finalLightCheckerPixels = countLightCheckerboardPixels(width: image.width, height: image.height, pixels: image.pixels)
    guard let bounds = opaqueBounds(width: image.width, height: image.height, pixels: image.pixels) else {
        throw NSError(domain: "clean-fake-transparency", code: 9, userInfo: [NSLocalizedDescriptionKey: "No visible pixels remained after cleanup"])
    }
    var output = crop(width: image.width, height: image.height, pixels: image.pixels, bounds: bounds, padding: options.cropPadding)
    try saveRGBA(path: options.outputPath, width: output.width, height: output.height, pixels: &output.pixels)
    print("removed checkerboard pixels: \(cleanup.removed)")
    print("removed unconnected light checker-like pixels: \(lightCheckerRemoved)")
    print("removed pale wash pixels: \(paleWashRemoved)")
    print("remaining light checker-like pixels: \(finalLightCheckerPixels)")
    print("removed detached subject pixels: \(componentRemoved)")
    print("output: \(options.outputPath) (\(output.width)x\(output.height))")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
