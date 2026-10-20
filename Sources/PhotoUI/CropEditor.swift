import PhotoCore
import PhotoImaging
import SwiftUI

private typealias CropStorage<T> = SwiftUI.State<T>

enum CropGeometry {
  static func fit(_ image: CGSize, in viewport: CGSize) -> CGRect {
    let scale = min(viewport.width / max(1, image.width), viewport.height / max(1, image.height))
    let size = CGSize(width: image.width * scale, height: image.height * scale)
    return CGRect(
      x: (viewport.width - size.width) / 2, y: (viewport.height - size.height) / 2,
      width: size.width, height: size.height)
  }
  static func point(_ point: CGPoint, frame: CGRect) -> CGPoint {
    CGPoint(
      x: min(1, max(0, (point.x - frame.minX) / max(1, frame.width))),
      y: min(1, max(0, (point.y - frame.minY) / max(1, frame.height))))
  }
  static func moved(_ crop: PhotoCrop, delta: CGSize) -> PhotoCrop {
    PhotoCrop(
      x: min(1 - crop.width, max(0, crop.x + delta.width)),
      y: min(1 - crop.height, max(0, crop.y + delta.height)), width: crop.width, height: crop.height
    )
  }
  static func rectangle(_ a: CGPoint, _ b: CGPoint) -> PhotoCrop {
    PhotoCrop(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }
  static func ratio(_ ratio: Double, image: CGSize) -> PhotoCrop {
    let normalizedRatio = ratio * image.height / max(1, image.width)
    let w = min(1, normalizedRatio)
    let h = min(1, 1 / max(0.0001, normalizedRatio))
    return PhotoCrop(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
  }
}

struct CropEditor: View {
  let photo: PhotoItem
  let edit: PhotoEdit
  let pipeline: ImagePipeline
  let sessionID: UUID
  let apply: (PhotoCrop?) -> Void
  @Environment(\.dismiss) private var dismiss
  @CropStorage private var crop: PhotoCrop
  @CropStorage private var imageSize = CGSize(width: 1000, height: 667)
  @CropStorage private var ready = false
  @CropStorage private var start: PhotoCrop?
  init(
    photo: PhotoItem, edit: PhotoEdit, pipeline: ImagePipeline, sessionID: UUID,
    apply: @escaping (PhotoCrop?) -> Void
  ) {
    self.photo = photo
    self.edit = edit
    self.pipeline = pipeline
    self.sessionID = sessionID
    self.apply = apply
    _crop = State(initialValue: edit.crop ?? PhotoCrop(x: 0.05, y: 0.05, width: 0.9, height: 0.9))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Crop · " + photo.filename).font(.title2.bold()).lineLimit(1)
      Text(
        "Drag outside the crop to draw; drag inside to move; drag a corner to resize. Edits are saved in Photo only. Originals and Lightroom develop settings stay untouched."
      ).font(.caption).foregroundStyle(.secondary)
      HStack {
        Menu("Center a Ratio") {
          Button("Original proportions") { crop = PhotoCrop(x: 0, y: 0, width: 1, height: 1) }
          ForEach([1.0, 3.0 / 2, 4.0 / 3, 16.0 / 9], id: \.self) { ratio in
            Button(ratio == 1 ? "Square" : ratio == 1.5 ? "3:2" : ratio < 1.5 ? "4:3" : "16:9") {
              crop = CropGeometry.ratio(ratio, image: imageSize)
            }
          }
        }.fixedSize().help(
          "Creates a centered crop with this ratio. Subsequent dragging is unconstrained.")
        Text("Drag freely after choosing a ratio").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Clear Crop") {
          apply(nil)
          dismiss()
        }
      }.disabled(!ready)
      GeometryReader { geo in
        let frame = CropGeometry.fit(imageSize, in: geo.size)
        let box = CGRect(
          x: frame.minX + crop.x * frame.width, y: frame.minY + crop.y * frame.height,
          width: crop.width * frame.width, height: crop.height * frame.height)
        ZStack(alignment: .topLeading) {
          PhotoImageView(
            photo: photo, pipeline: pipeline, maximumPixelSize: 2560, edit: edit.withoutCrop,
            sessionID: sessionID,
            onLoaded: { preview in
              imageSize = edit.orientedSize(
                CGSize(width: preview.decodedWidth, height: preview.decodedHeight))
              ready = true
            })
          Color.clear.contentShape(Rectangle()).gesture(
            DragGesture(minimumDistance: 2).onChanged { value in
              crop = CropGeometry.rectangle(
                CropGeometry.point(value.startLocation, frame: frame),
                CropGeometry.point(value.location, frame: frame))
            })
          Path { p in
            p.addRect(frame)
            p.addRect(box)
          }.fill(.black.opacity(0.55), style: FillStyle(eoFill: true)).allowsHitTesting(false)
          Rectangle().fill(.clear).contentShape(Rectangle())
            .overlay(Rectangle().stroke(.white, lineWidth: 2))
            .overlay {
              Path { p in
                for fraction in [1.0 / 3, 2.0 / 3] {
                  p.move(to: CGPoint(x: box.width * fraction, y: 0))
                  p.addLine(to: CGPoint(x: box.width * fraction, y: box.height))
                  p.move(to: CGPoint(x: 0, y: box.height * fraction))
                  p.addLine(to: CGPoint(x: box.width, y: box.height * fraction))
                }
              }.stroke(.white.opacity(0.4), lineWidth: 1).allowsHitTesting(false)
            }
            .frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
            .gesture(
              DragGesture(minimumDistance: 1).onChanged { value in
                if start == nil { start = crop }
                crop = CropGeometry.moved(
                  start ?? crop,
                  delta: CGSize(
                    width: value.translation.width / max(1, frame.width),
                    height: value.translation.height / max(1, frame.height)))
              }.onEnded { _ in start = nil })
          ForEach(0..<4) { corner in
            let point = CGPoint(
              x: corner % 2 == 0 ? box.minX : box.maxX, y: corner < 2 ? box.minY : box.maxY)
            Rectangle().fill(.white).frame(width: 12, height: 12).padding(6).contentShape(
              Rectangle()
            ).position(point)
              .gesture(
                DragGesture(minimumDistance: 1).onChanged { value in
                  if start == nil { start = crop }
                  let original = start ?? crop
                  let opposite = CGPoint(
                    x: corner % 2 == 0 ? original.x + original.width : original.x,
                    y: corner < 2 ? original.y + original.height : original.y)
                  let moved = CGPoint(
                    x: (corner % 2 == 0 ? original.x : original.x + original.width) + value
                      .translation.width / max(1, frame.width),
                    y: (corner < 2 ? original.y : original.y + original.height) + value.translation
                      .height / max(1, frame.height))
                  crop = CropGeometry.rectangle(
                    opposite, CGPoint(x: min(1, max(0, moved.x)), y: min(1, max(0, moved.y))))
                }.onEnded { _ in start = nil }
              )
              .accessibilityHidden(true)
          }
        }.clipped().disabled(!ready)
      }.frame(minHeight: 240)
      HStack {
        coordinate("Left", value: crop.x) {
          crop = CropGeometry.moved(crop, delta: CGSize(width: $0 - crop.x, height: 0))
        }
        coordinate("Top", value: crop.y) {
          crop = CropGeometry.moved(crop, delta: CGSize(width: 0, height: $0 - crop.y))
        }
        coordinate("Width", value: crop.width) {
          crop = PhotoCrop(x: crop.x, y: crop.y, width: $0, height: crop.height)
        }
        coordinate("Height", value: crop.height) {
          crop = PhotoCrop(x: crop.x, y: crop.y, width: crop.width, height: $0)
        }
      }.disabled(!ready)
      HStack {
        Text("100% inspection uses the cropped view; Reset Image Edits restores the full photo.")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply Crop") {
          apply(crop)
          dismiss()
        }.keyboardShortcut(.defaultAction).disabled(!ready)
      }
    }.padding(20).frame(width: 780, height: 640)
  }
  private func coordinate(_ title: String, value: Double, set: @escaping (Double) -> Void)
    -> some View
  {
    VStack(alignment: .leading) {
      Text(title + " (%)").font(.caption)
      TextField(
        title, value: Binding(get: { value * 100 }, set: { set($0 / 100) }),
        format: .number.precision(.fractionLength(1))
      ).frame(width: 100).accessibilityLabel("Crop " + title + " percent")
    }
  }
}
