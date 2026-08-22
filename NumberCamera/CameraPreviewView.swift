import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var orientation: AVCaptureVideoOrientation
    var onPinchZoom: (CGFloat) -> Void
    var onTapToFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        view.onPinchZoom = onPinchZoom
        view.onTapToFocus = onTapToFocus
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.onPinchZoom = onPinchZoom
        uiView.onTapToFocus = onTapToFocus
        uiView.updateOrientation(orientation)
    }
}

class PreviewUIView: UIView {
    var onPinchZoom: ((CGFloat) -> Void)?
    var onTapToFocus: ((CGPoint) -> Void)?
    private var focusSquareView: UIView?

    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    var session: AVCaptureSession? {
        get { return videoPreviewLayer.session }
        set {
            videoPreviewLayer.session = newValue
            // 비율 왜곡 없이 꽉 차게 프레임 내부 설정
            videoPreviewLayer.videoGravity = .resizeAspectFill
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }

    func updateOrientation(_ orientation: AVCaptureVideoOrientation) {
        guard let connection = videoPreviewLayer.connection, connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = orientation
    }

    private func setupGestures() {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        self.addGestureRecognizer(pinchGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        self.addGestureRecognizer(tapGesture)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            onPinchZoom?(gesture.scale)
            gesture.scale = 1.0
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        let devicePoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: location)
        onTapToFocus?(devicePoint)
        showFocusSquare(at: location)
    }

    private func showFocusSquare(at point: CGPoint) {
        focusSquareView?.removeFromSuperview()

        let square = UIView(frame: CGRect(x: 0, y: 0, width: 70, height: 70))
        square.center = point
        square.layer.borderColor = UIColor.yellow.cgColor
        square.layer.borderWidth = 1.5
        square.backgroundColor = .clear
        square.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        square.alpha = 0.0

        self.addSubview(square)
        self.focusSquareView = square

        UIView.animate(withDuration: 0.15, animations: {
            square.transform = CGAffineTransform.identity
            square.alpha = 1.0
        }) { _ in
            UIView.animate(withDuration: 0.25, delay: 0.4, options: [], animations: {
                square.alpha = 0.0
            }) { _ in
                square.removeFromSuperview()
            }
        }
    }
}
