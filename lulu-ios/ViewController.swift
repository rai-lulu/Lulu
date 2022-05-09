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
        static let sessionQuequeLabel = "lulu video session queue"
        static let sessionOutputQueueLabel = "lulu video session data output queue"
        
        static let labelConfidenceThreshold = 0.75
        static let dotRadius: CGFloat = 20.0
        static let lineWidth: CGFloat = 3.0
        static let originalScale: CGFloat = 1.0
        static let padding: CGFloat = 10.0
        static let circleRadius = 10.0
        static let viewsXCount = 4
        static let viewsYCount = 5
        static let viewBorderWidth = 1.0
        static let viewSelectedBorderWidth = 2.0
        static let choosenCountFrames = 30
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
    
    let dualVideoSessionQueue = DispatchQueue(label: Constant.sessionQuequeLabel)
    let dualVideoSessionOutputQueue = DispatchQueue(label: Constant.sessionOutputQueueLabel)
    
    @IBOutlet weak var faceDetectedLabel: UILabel!
    @IBOutlet weak var startCalibrationButton: UIButton!
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    
    private var circleView: UIView?
    private var lastPoint: CGPoint?
    
    private var isFaceDetected = false
    private var isCalibrated = false
    private var lastPosition = CGPoint.zero
    private var calibrationPosition = CGPoint.zero
    
    let irisTracker = MPPIrisTracker()!
    
    var recViews = [UIView]()
    var selectedViewId = 0
    var countFramesInView = 0
    var isFirstTime = true
    
    var segmentIndex = 0
    
    //MARK:- View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setupMain()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if isFirstTime {
            backPreview.layoutIfNeeded()
            setupView()
            setupDot()
            isFirstTime = false
        }
    }
    
    func setupDot() {
        circleView = UIView(frame: CGRect(x: backPreview.bounds.maxX / 2 - Constant.dotRadius/2, y: backPreview.bounds.maxY / 2 - Constant.dotRadius/2, width: Constant.dotRadius, height: Constant.dotRadius))
        circleView?.backgroundColor = UIColor.red
        circleView?.layer.cornerRadius = Constant.circleRadius
        circleView?.clipsToBounds = true
        backPreview.addSubview(circleView!)
        circleView?.isHidden = true
    }
    
    func setupView() {
        backPreview.layer.borderColor = UIColor.green.cgColor
        backPreview.layer.borderWidth = 3.0
        let recWidth = backPreview.frame.width / CGFloat(Constant.viewsXCount)
        let recHeight = backPreview.frame.height / CGFloat(Constant.viewsYCount)
 
        var currentX = backPreview.frame.minX
        var currentY = backPreview.frame.minY
        var viewId = 0
        for _ in 1...Constant.viewsXCount {
            currentY = 0
            for _ in 1...Constant.viewsYCount  {
                viewId = viewId + 1
                let recView = UIView(frame: CGRect(x: currentX, y: currentY, width: recWidth, height: recHeight))
                recView.layer.borderColor = UIColor.black.cgColor
                recView.layer.borderWidth = Constant.viewBorderWidth
                recView.tag = viewId
                backPreview.addSubview(recView)
                recViews.append(recView)
                currentY = currentY + recHeight
            }
            currentX = currentX + recWidth
        }
    }
    
    func findNeedsView(point: CGPoint) {
        for recView in recViews {
            if point.x > recView.frame.minX &&
                point.x < recView.frame.maxX &&
                point.y > recView.frame.minY &&
                point.y < recView.frame.maxY {
                if selectedViewId == recView.tag {
                    if countFramesInView > Constant.choosenCountFrames {
                        recView.layer.borderColor = UIColor.red.cgColor
                        recView.layer.borderWidth = Constant.viewSelectedBorderWidth
                    }
                    countFramesInView = countFramesInView + 1
                } else {
                    selectedViewId = recView.tag
                    countFramesInView = 0
                }
            } else {
                recView.layer.borderColor = UIColor.black.cgColor
                recView.layer.borderWidth = Constant.viewBorderWidth
            }
        }
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
    
    @IBAction func indexChanged(_ sender: Any) {
        segmentIndex = segmentedControl.selectedSegmentIndex
        isFaceDetected = false
        isCalibrated = false
        circleView?.isHidden = true
    }
    
    //MARK:- Setup main functions
    func setupMain(){
        
        // Set up the back and front video preview views.
        backPreview.videoPreviewLayer.setSessionWithNoConnection(dualVideoSession)
        frontPreview.videoPreviewLayer.setSessionWithNoConnection(dualVideoSession)
        
        // Store the back and front video preview layers so we can connect them to their inputs
        backViewLayer = backPreview.videoPreviewLayer
        frontViewLayer = frontPreview.videoPreviewLayer
        
        // Keep the screen awake
        UIApplication.shared.isIdleTimerDisabled = true
        
        dualVideoPermisson()
        
        irisTracker.startGraph()
        irisTracker.delegate = self
        
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
        //frontOutputConnection.isVideoMirrored = true
        
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
        //frontLayerConnection.isVideoMirrored = true
        
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
    
    @IBAction func startCalibrationPressed(sender: UIButton) {
        faceDetectedLabel.text = "Calibration..."
        isCalibrated = false
        startCalibrationButton.isEnabled = false
        startCalibrationButton.alpha = 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.startCalibrationButton.isEnabled = true
            self.startCalibrationButton.alpha = 1.0
            self.calibrationPosition = self.lastPosition
            self.isCalibrated = true
            self.faceDetectedLabel.text = "Calibrated"
            self.circleView?.center = CGPoint(x: self.backPreview.bounds.maxX / 2, y: self.backPreview.bounds.maxY / 2)
            self.circleView?.isHidden = false
        }
    }
    
    private func setFaceNotDetected() {
        isFaceDetected = false
        isCalibrated = false
        faceDetectedLabel.text = "Face not detected"
        faceDetectedLabel.textColor = .red
        circleView?.isHidden = true
    }
    
    private func setFaceDetected() {
        isFaceDetected = true
        faceDetectedLabel.text = "Face detected"
        faceDetectedLabel.isHidden = false
        faceDetectedLabel.textColor = .black
        startCalibrationButton.isEnabled = true
        startCalibrationButton.alpha = 1.0
    }
    
    private func moveToNewPoint(newCenter: CGPoint, duration: TimeInterval) {
        UIView.animate(withDuration: duration) {
            self.circleView?.center = newCenter
        }
    }
    
    //MARK:- AVCaptureOutput Delegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection){
        
        guard let output = output as? AVCaptureVideoDataOutput,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              output == frontVideoDataOutput else {
            return
        }
        
        switch segmentIndex {
        case 0:
            let visionImage = VisionImage(buffer: sampleBuffer)
            let orientation = UIUtilities.imageOrientation(
                fromDevicePosition: .front
            )
            visionImage.orientation = orientation
            
            let imageWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
            let imageHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
            
            detectFacesOnDevice(in: visionImage, width: imageWidth, height: imageHeight)
        case 1:
            
            autoreleasepool {
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                let timestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                irisTracker.processVideoFrame(imageBuffer, timestamp: timestamp)
            }

        default:
            break
        }
    }
}

/// Extension of ViewController for On-Device detection.
extension ViewController {
    
    // MARK: - Vision On-Device Detection
    private func detectFacesOnDevice(in image: VisionImage, width: CGFloat, height: CGFloat) {
        // When performing latency tests to determine ideal detection settings, run the app in 'release'
        // mode to get accurate performance metrics.
        let options = FaceDetectorOptions()
        options.landmarkMode = .all
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
                self.setFaceNotDetected()
            }
            return
        }
        guard !faces.isEmpty else {
            print("On-Device face detector returned no results.")
            DispatchQueue.main.async {
                self.setFaceNotDetected()
            }
            return
        }
        weak var weakSelf = self
        DispatchQueue.main.sync {
            guard let strongSelf = weakSelf else {
                print("Self is nil!")
                return
            }
            
            if !self.isFaceDetected {
                DispatchQueue.main.async {
                    self.setFaceDetected()
                }
            }
            
            guard let face = faces.first else {
                return
            }
            
            strongSelf.setRectForCircle(for: face, width: width, height: height)
        }
    }
    
    private func setRectForCircle(for face: Face, width: CGFloat, height: CGFloat) {
        // Nose
        if let noseBridgeContour = face.contour(ofType: .noseBridge),
           let lastPoint = noseBridgeContour.points.last {
            let cgPoint = normalizedPoint(fromVisionPoint: lastPoint, width: width, height: height)
            if isFaceDetected && isCalibrated {
                let deltaX = cgPoint.x - calibrationPosition.x
                let deltaY = cgPoint.y - calibrationPosition.y
                var newX = self.backPreview.bounds.maxX / 2 + deltaX*1.5
                var newY = self.backPreview.bounds.maxY / 2 + deltaY*3.5
                if newX < backPreview.bounds.minX + Constant.dotRadius / 2 {
                    newX = backPreview.bounds.minX + Constant.dotRadius / 2
                } else if newX > backPreview.bounds.maxX - Constant.dotRadius / 2 {
                    newX = backPreview.bounds.maxX - Constant.dotRadius / 2
                }
                
                if newY < backPreview.bounds.minY + Constant.dotRadius / 2 {
                    newY = backPreview.bounds.minY + Constant.dotRadius / 2
                } else if newY > backPreview.bounds.maxY - Constant.dotRadius / 2 {
                    newY = backPreview.bounds.maxY - Constant.dotRadius / 2
                }
                self.moveToNewPoint(newCenter: CGPoint(x: newX, y: newY), duration: 0.1)
                self.findNeedsView(point: self.circleView?.center ?? CGPoint.zero)
            } else {
                lastPosition = cgPoint
            }
        }
    }
    
    private func setRectForCircle(point: CGPoint) {
        // Eyes
        if isFaceDetected && isCalibrated {
            let deltaX = point.x - calibrationPosition.x
            let deltaY = point.y - calibrationPosition.y
            DispatchQueue.main.async {
                var newX = self.backPreview.bounds.maxX / 2 + deltaX*600
                var newY = self.backPreview.bounds.maxY / 2 + deltaY*900
                
                if newX < self.backPreview.bounds.minX + Constant.dotRadius / 2 {
                    newX = self.backPreview.bounds.minX + Constant.dotRadius / 2
                } else if newX > self.backPreview.bounds.maxX - Constant.dotRadius / 2 {
                    newX = self.backPreview.bounds.maxX - Constant.dotRadius / 2
                }
                
                if newY < self.backPreview.bounds.minY + Constant.dotRadius / 2 {
                    newY = self.backPreview.bounds.minY + Constant.dotRadius / 2
                } else if newY > self.backPreview.bounds.maxY - Constant.dotRadius / 2 {
                    newY = self.backPreview.bounds.maxY - Constant.dotRadius / 2
                }
                self.moveToNewPoint(newCenter: CGPoint(x: newX, y: newY), duration: 0.4)
                self.findNeedsView(point: self.circleView?.center ?? CGPoint.zero)
            }
        } else {
            lastPosition = point
        }
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

extension ViewController: MPPIrisTrackerDelegate {
    func irisTracker(_ irisTracker: MPPIrisTracker, didOutputTransform transform: simd_float4x4) {
                
        if !self.isFaceDetected {
            DispatchQueue.main.async {
                self.setFaceDetected()
            }
        }
        
        setRectForCircle(point: CGPoint(x: Double(-transform.columns.3.y), y: Double(transform.columns.3.x)))
    }
    
    func irisTracker(_ irisTracker: MPPIrisTracker, didOutputPixelBuffer pixelBuffer: CVPixelBuffer) {
        
    }
}


