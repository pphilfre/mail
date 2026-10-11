import SwiftUI
import VisionKit

struct MailDocumentScanner: UIViewControllerRepresentable {
    let finish: (Result<Data, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, @MainActor VNDocumentCameraViewControllerDelegate {
        let finish: (Result<Data, Error>) -> Void
        init(finish: @escaping (Result<Data, Error>) -> Void) { self.finish = finish }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { controller.dismiss(animated: true) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { finish(.failure(error)) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount <= 40 else { finish(.failure(ComposeAttachmentError.tooLarge)); return }
            let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
            let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
                for index in 0..<scan.pageCount {
                    context.beginPage()
                    let image = scan.imageOfPage(at: index)
                    let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
                }
            }
            finish(.success(data))
        }
    }
}
