import Flutter
import UIKit
import Photos

/// Saves raw image bytes (original format) to the iOS photo library.
class SaveImagePlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "ereader/save_image",
      binaryMessenger: registrar.messenger()
    )
    let instance = SaveImagePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "saveImage" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let bytes = args["bytes"] as? FlutterStandardTypedData else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing image bytes", details: nil))
      return
    }
    // SVG cannot be decoded into UIImage; report a clear error.
    guard let image = UIImage(data: bytes.data) else {
      result(FlutterError(code: "SAVE_FAILED", message: "Could not decode image", details: nil))
      return
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "PERMISSION_DENIED", message: "Photo library permission denied", details: nil))
        }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAsset(from: image)
      }) { success, error in
        DispatchQueue.main.async {
          if success {
            result(true)
          } else {
            result(FlutterError(code: "SAVE_FAILED", message: error?.localizedDescription ?? "Save failed", details: nil))
          }
        }
      }
    }
  }
}
