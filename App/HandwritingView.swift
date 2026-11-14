import PencilKit
import SwiftUI

/// Kalemle ya da parmakla serbest yazı alanı.
struct HandwritingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var eraser: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.drawingPolicy = .anyInput
        v.backgroundColor = .clear
        v.isOpaque = false
        v.overrideUserInterfaceStyle = .dark
        v.drawing = drawing
        v.delegate = context.coordinator
        v.tool = tool
        return v
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        v.tool = tool
        // Dışarıdan temizlendiyse tuvali de temizle
        if drawing.strokes.isEmpty && !v.drawing.strokes.isEmpty {
            v.drawing = drawing
        }
    }

    private var tool: PKTool {
        eraser ? PKEraserTool(.vector) : PKInkingTool(.pen, color: .white, width: 4)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: HandwritingCanvas
        init(_ p: HandwritingCanvas) { parent = p }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

/// Tam ekran yazma sayfası: Kalem · Silgi · Temizle · Bitti.
struct HandwritingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drawing: PKDrawing
    @State private var eraser = false
    let onSave: (Data?) -> Void

    init(data: Data?, onSave: @escaping (Data?) -> Void) {
        _drawing = State(initialValue: data.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing())
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text(L("Kalemle ya da parmağınla yaz. Sadece bu uçuş için kaydedilir.", "Write with Apple Pencil or your finger. Saved for this flight only."))
                    .font(.footnote).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HandwritingCanvas(drawing: $drawing, eraser: eraser)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08)))
                HStack(spacing: 10) {
                    Picker("", selection: $eraser) {
                        Label(L("Kalem", "Pen"), systemImage: "pencil.tip").tag(false)
                        Label(L("Silgi", "Eraser"), systemImage: "eraser").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Button(role: .destructive) { drawing = PKDrawing() } label: {
                        Label(L("Temizle", "Clear"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .background(Palette.bg)
            .navigationTitle(L("El yazısı not", "Handwritten note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Vazgeç", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Bitti", "Done")) {
                        onSave(drawing.strokes.isEmpty ? nil : drawing.dataRepresentation())
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(!drawing.strokes.isEmpty)
    }
}

/// Kayıtlı çizimin önizlemesi.
struct DrawingPreview: View {
    let data: Data

    var body: some View {
        if let d = try? PKDrawing(data: data), !d.strokes.isEmpty {
            let rect = d.bounds.insetBy(dx: -12, dy: -12)
            Image(uiImage: render(d, rect))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 220)
                .accessibilityLabel(L("El yazısı not", "Handwritten note"))
        }
    }

    private func render(_ d: PKDrawing, _ rect: CGRect) -> UIImage {
        var img = UIImage()
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            img = d.image(from: rect, scale: UIScreen.main.scale)
        }
        return img
    }
}
