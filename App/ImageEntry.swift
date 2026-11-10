import SwiftUI
import Vision
import PhotosUI
import UIKit
import ImageIO

struct GroceryImageFindings: Sendable { var text: String; var candidates: [String] }
enum GroceryImageReader {
    static func read(_ data: Data, vocabulary: [String]) async throws -> GroceryImageFindings {
        try await Task.detached(priority: .userInitiated) {
            let textRequest = VNRecognizeTextRequest(); textRequest.recognitionLevel = .accurate; textRequest.usesLanguageCorrection = true
            let classify = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(data: data, options: [:])
            try handler.perform([textRequest, classify])
            let text = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }.prefix(150).joined(separator: "\n")
            let labels = (classify.results ?? []).filter { $0.confidence >= 0.35 }.prefix(12).map(\.identifier)
            let foods = Set(vocabulary.map { IngredientRules.key($0) })
            let candidates = labels.flatMap { $0.components(separatedBy: ",") }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { foods.contains(IngredientRules.key($0)) }
            return GroceryImageFindings(text: text, candidates: Array(Set(candidates)).sorted())
        }.value
    }
}
struct CameraCapture: UIViewControllerRepresentable {
    var onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraCapture
        init(parent: CameraCapture) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) { parent.onImage(data) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
