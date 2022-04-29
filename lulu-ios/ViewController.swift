//
//  ViewController.swift
//  lulu-ios
//
//  Created by Dmitriy Zhurbenko on 21.04.2022.
//

import UIKit
import AVFoundation
import MLKit

class ViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate{
    
    private enum Constant {
        static let labelConfidenceThreshold = 0.75
        static let smallDotRadius: CGFloat = 4.0
        static let lineWidth: CGFloat = 3.0
        static let originalScale: CGFloat = 1.0
        static let padding: CGFloat = 10.0
    }
    
    var dualVideoSession = AVCaptureMultiCamSession()
    
    @IBOutlet weak var backPreview: ViewPreview!
    var backDeviceInput:AVCaptureDeviceInput?
    var backVideoDataOutput = AVCaptureVideoDataOutput()
    var backViewLayer:AVCaptureVideoPreviewLayer!
    
    @IBOutlet weak var frontPreview: ViewPreview!
    var frontDeviceInput:AVCaptureDeviceInput?
    var frontVideoDataOutput = AVCaptureVideoDataOutput()
    var frontViewLayer:AVCaptureVideoPreviewLayer!
    
    let dualVideoSessionQueue = DispatchQueue(label: "dual video session queue")
    let dualVideoSessionOutputQueue = DispatchQueue(label: "dual video session data output queue")
    
    @IBOutlet weak var faceDetectedLabel: UILabel!
    
    private var lastFrame: CMSampleBuffer?
    private var circleView: UIView?
    private var lastPoint: CGPoint?
    
    //MARK:- View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setUp()
        
        circleView = UIView(frame: CGRect(x: view.center.x - 10, y: 250, width: 20, height: 20))
        circleView?.backgroundColor = UIColor.red
        circleView?.layer.cornerRadius = 10.0
        circleView?.clipsToBounds = true
        view.addSubview(circleView!)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    
    //MARK:- User Permission for Dual Video Session
    //ask user permissin for recording video from device
    func dualVideoPermisson(){
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            configureDualVideo()
            break
            
        case .notDetermined:
            
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if granted{
                    self.configureDualVideo()
                }
            })
            
            break
            
        default:
            // The user has previously denied access.
            DispatchQueue.main.async {
                let changePrivacySetting = "Device doesn't have permission to use the camera, please change privacy settings"
                let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                let alertController = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
                
                alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
                
                alertController.addAction(UIAlertAction(title: "Settings", style: .`default`,handler: { _ in
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL,  options: [:], completionHandler: nil)
                    }
                }))
                
                self.present(alertController, animated: true, completion: nil)
            }
        }
    }
    
    //MARK:- Setup Dual Video Session
    func setUp(){
        
        // Set up the back and front video preview views.
        backPreview.videoPreviewLayer.setSessionWithNoConnection(dualVideoSession)
        frontPreview.videoPreviewLayer.setSessionWithNoConnection(dualVideoSession)
        
        // Store the back and front video preview layers so we can connect them to their inputs
        backViewLayer = backPreview.videoPreviewLayer
        frontViewLayer = frontPreview.videoPreviewLayer
        
        // Keep the screen awake
        UIApplication.shared.isIdleTimerDisabled = true
        
        dualVideoPermisson()
    }
    
    
    func configureDualVideo(){
        addNotifer()
        dualVideoSessionQueue.async {
            self.setUpSession()
        }
    }
    
    func setUpSession(){
        if !AVCaptureMultiCamSession.isMultiCamSupported{
            DispatchQueue.main.async {
                let alertController = UIAlertController(title: "Error", message: "Device is not supporting multicam feature", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "OK",style: .cancel, handler: nil))
                self.present(alertController, animated: true, completion: nil)
            }
            return
        }
        
        guard setUpBackCamera() else{
            
            DispatchQueue.main.async {
                let alertController = UIAlertController(title: "Error", message: "issue while setuping back camera", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "OK",style: .cancel, handler: nil))
                self.present(alertController, animated: true, completion: nil)
            }
            return
        }
        
        guard setUpFrontCamera() else{
            DispatchQueue.main.async {
                let alertController = UIAlertController(title: "Error", message: "issue while setuping front camera", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "OK",style: .cancel, handler: nil))
                self.present(alertController, animated: true, completion: nil)
            }
            return
        }
        
        dualVideoSessionQueue.async {
            self.dualVideoSession.startRunning()
        }
        
    }
    
    
    func setUpBackCamera() -> Bool{
        //start configuring dual video session
        dualVideoSession.beginConfiguration()
        defer {
            //save configuration setting
            dualVideoSession.commitConfiguration()
        }
        
        //search back camera
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("no back camera")
            return false
        }
        
        // append back camera input to dual video session
        do {
            backDeviceInput = try AVCaptureDeviceInput(device: backCamera)
            
            guard let backInput = backDeviceInput,dualVideoSession.canAddInput(backInput) else {
                print("no back camera device input")
                return false
            }
            dualVideoSession.addInputWithNoConnections(backInput)
        } catch {
            print("no back camera device input: \(error)")
            return false
        }
        
        // seach back video port
        guard let backDeviceInput = backDeviceInput,
              let backVideoPort = backDeviceInput.ports(for: .video, sourceDeviceType: backCamera.deviceType, sourceDevicePosition: backCamera.position).first else {
            print("no back camera input's video port")
            return false
        }
        
        // append back video ouput
        guard dualVideoSession.canAddOutput(backVideoDataOutput) else {
            print("no back camera output")
            return false
        }
        dualVideoSession.addOutputWithNoConnections(backVideoDataOutput)
        backVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        backVideoDataOutput.setSampleBufferDelegate(self, queue: dualVideoSessionOutputQueue)
        
        // connect back ouput to dual video connection
        let backOutputConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backVideoDataOutput)
        guard dualVideoSession.canAddConnection(backOutputConnection) else {
            print("no connection to the back camera video data output")
            return false
        }
        dualVideoSession.addConnection(backOutputConnection)
        backOutputConnection.videoOrientation = .portrait
        
        // connect back input to back layer
        guard let backLayer = backViewLayer else {
            return false
        }
        let backConnection = AVCaptureConnection(inputPort: backVideoPort, videoPreviewLayer: backLayer)
        guard dualVideoSession.canAddConnection(backConnection) else {
            print("no a connection to the back camera video preview layer")
            return false
        }
        dualVideoSession.addConnection(backConnection)
        
        return true
    }
    
    
    func setUpFrontCamera() -> Bool{
        
        //start configuring dual video session
        dualVideoSession.beginConfiguration()
        defer {
            //save configuration setting
            dualVideoSession.commitConfiguration()
        }
        
        //search front camera for dual video session
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("no front camera")
            return false
        }
        
        // append front camera input to dual video session
        do {
            frontDeviceInput = try AVCaptureDeviceInput(device: frontCamera)
            
            guard let frontInput = frontDeviceInput, dualVideoSession.canAddInput(frontInput) else {
                print("no front camera input")
                return false
            }
            dualVideoSession.addInputWithNoConnections(frontInput)
        } catch {
            print("no front input: \(error)")
            return false
        }
        
        // search front video port for dual video session
        guard let frontDeviceInput = frontDeviceInput,
              let frontVideoPort = frontDeviceInput.ports(for: .video, sourceDeviceType: frontCamera.deviceType, sourceDevicePosition: frontCamera.position).first else {
            print("no front camera device input's video port")
            return false
        }
        
        // append front video output to dual video session
        guard dualVideoSession.canAddOutput(frontVideoDataOutput) else {
            print("no the front camera video output")
            return false
        }
        dualVideoSession.addOutputWithNoConnections(frontVideoDataOutput)
        frontVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        frontVideoDataOutput.alwaysDiscardsLateVideoFrames = true
        frontVideoDataOutput.setSampleBufferDelegate(self, queue: dualVideoSessionOutputQueue)
        
        // connect front output to dual video session
        let frontOutputConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontVideoDataOutput)
        guard dualVideoSession.canAddConnection(frontOutputConnection) else {
            print("no connection to the front video output")
            return false
        }
        dualVideoSession.addConnection(frontOutputConnection)
        //frontOutputConnection.videoOrientation = .portrait
        frontOutputConnection.automaticallyAdjustsVideoMirroring = false
        frontOutputConnection.isVideoMirrored = true
        
        // connect front input to front layer
        guard let frontLayer = frontViewLayer else {
            return false
        }
        let frontLayerConnection = AVCaptureConnection(inputPort: frontVideoPort, videoPreviewLayer: frontLayer)
        guard dualVideoSession.canAddConnection(frontLayerConnection) else {
            print("no connection to front layer")
            return false
        }
        dualVideoSession.addConnection(frontLayerConnection)
        frontLayerConnection.automaticallyAdjustsVideoMirroring = false
        frontLayerConnection.isVideoMirrored = true
        
        return true
    }
    
    //MARK:- Add and Handle Observers
    func addNotifer() {
        
        // A session can run only when the app is full screen. It will be interrupted in a multi-app layout.
        // Add observers to handle these session interruptions and inform the user.
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError,object: dualVideoSession)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: dualVideoSession)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: dualVideoSession)
    }
    
    
    @objc func sessionWasInterrupted(notification: NSNotification) {
        print("Session was interrupted")
    }
    
    @objc func sessionInterruptionEnded(notification: NSNotification) {
        print("Session interrupt ended")
    }
    
    @objc func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        
        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            //Manage according to condition
        } else {
            //Manage according to condition
        }
    }
    
    //MARK:- AVCaptureOutput Delegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection){
        
        guard let output = output as? AVCaptureVideoDataOutput,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              output == frontVideoDataOutput else {
            return
        }
        
        lastFrame = sampleBuffer
        let visionImage = VisionImage(buffer: sampleBuffer)
        let orientation = UIUtilities.imageOrientation(
            fromDevicePosition: .front
        )
        visionImage.orientation = orientation
        
        guard let inputImage = MLImage(sampleBuffer: sampleBuffer) else {
            print("Failed to create MLImage from sample buffer.")
            return
        }
        inputImage.orientation = orientation
        
        let imageWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        
        detectFacesOnDevice(in: visionImage, width: imageWidth, height: imageHeight)
    }
}

/// Extension of ViewController for On-Device detection.
extension ViewController {
    
    // MARK: - Vision On-Device Detection
    private func detectFacesOnDevice(in image: VisionImage, width: CGFloat, height: CGFloat) {
        // When performing latency tests to determine ideal detection settings, run the app in 'release'
        //self.detectLabel.isHidden = true
        // mode to get accurate performance metrics.
        let options = FaceDetectorOptions()
        options.landmarkMode = .none
        options.contourMode = .all
        options.classificationMode = .none
        options.performanceMode = .fast
        let faceDetector = FaceDetector.faceDetector(options: options)
        var faces: [Face]
        do {
            faces = try faceDetector.results(in: image)
        } catch let error {
            print("Failed to detect faces with error: \(error.localizedDescription).")
            DispatchQueue.main.async {
                self.faceDetectedLabel.isHidden = true
            }
            return
        }
        guard !faces.isEmpty else {
            print("On-Device face detector returned no results.")
            DispatchQueue.main.async {
                self.faceDetectedLabel.isHidden = true
            }
            return
        }
        weak var weakSelf = self
        DispatchQueue.main.sync {
            guard let strongSelf = weakSelf else {
                print("Self is nil!")
                return
            }
            
            DispatchQueue.main.async {
                strongSelf.faceDetectedLabel.isHidden = false
            }
            
            guard let face = faces.first else {
                return
            }
            
            strongSelf.setRectForCircle(for: face, width: width, height: height)
        }
    }
    
    private func setRectForCircle(for face: Face, width: CGFloat, height: CGFloat) {
        var leftPoint = CGPoint()
        var rightPoint = CGPoint()
        
        if let leftEyeContour = face.contour(ofType: .leftEye) {
            for point in leftEyeContour.points {
                leftPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
                //print("left - \(cgPoint)")
            }
        }
        if let rightEyeContour = face.contour(ofType: .rightEye) {
            for point in rightEyeContour.points {
                rightPoint = normalizedPoint(fromVisionPoint: point, width: width, height: height)
                //print("right - \(cgPoint)")
            }
        }
        let centerY = (leftPoint.y + rightPoint.y)/2
        let delta = view.center.y - centerY
        print(delta)
        let y = view.center.y + delta*2 - 100
        circleView?.center = CGPoint(x: (leftPoint.x + rightPoint.x)/2, y: y)
    }
    
    private func convertedPoints(
        from points: [NSValue]?,
        width: CGFloat,
        height: CGFloat
    ) -> [NSValue]? {
        return points?.map {
            let cgPointValue = $0.cgPointValue
            let normalizedPoint = CGPoint(x: cgPointValue.x / width, y: cgPointValue.y / height)
            let cgPoint = frontViewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
            let value = NSValue(cgPoint: cgPoint)
            return value
        }
    }
    
    private func normalizedPoint(
        fromVisionPoint point: VisionPoint,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        var normalizedPoint = CGPoint(x: cgPoint.x / width, y: cgPoint.y / height)
        normalizedPoint = frontViewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
        return normalizedPoint
    }
}


