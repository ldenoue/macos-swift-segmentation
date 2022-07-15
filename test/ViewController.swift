//
//  ViewController.swift
//  test
//
//  Created by laurent denoue on 7/14/22.
//

import Cocoa
import Vision
import AVFoundation
import MetalKit
import CoreImage.CIFilterBuiltins

class ViewController: NSViewController {

    let bgQueue = DispatchQueue.global(qos: .background)
    var processing = false
    private let requestHandler = VNSequenceRequestHandler()
    private var segmentationRequest = VNGeneratePersonSegmentationRequest()
    public var session: AVCaptureSession?

    override func viewDidAppear() {
        if let window = self.view.window {
            window.title = "Segmentation"
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        intializeRequests()
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.yellow.cgColor
        self.view.layer?.frame = self.view.bounds
        setupCaptureSession()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    private func intializeRequests() {
        // Create a request to segment a person from an image.
        segmentationRequest = VNGeneratePersonSegmentationRequest()
        //segmentationRequest.qualityLevel = .balanced
        segmentationRequest.qualityLevel = .fast
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    private func processVideoFrame(_ framePixelBuffer: CVPixelBuffer) {
        // Perform the requests on the pixel buffer that contains the video frame.
        try? requestHandler.perform([segmentationRequest], on: framePixelBuffer)
        
        // Get the pixel buffer that contains the mask image.
        guard let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer else { return }
        
        // Process the images.
        //blend(original: framePixelBuffer, mask: maskPixelBuffer)
        DispatchQueue.main.async {
            self.view.layer?.contents = maskPixelBuffer
        }
    }
    
    // MARK: - Process Results
    
    // Performs the blend operation.
    private func blend(original framePixelBuffer: CVPixelBuffer,
                       mask maskPixelBuffer: CVPixelBuffer) {
        
        // Create CIImage objects for the video frame and the segmentation mask.
        let originalImage = CIImage(cvPixelBuffer: framePixelBuffer)//.oriented(.right)
        var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        
        // Scale the mask image to fit the bounds of the video frame.
        let scaleX = originalImage.extent.width / maskImage.extent.width
        let scaleY = originalImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: .init(scaleX: scaleX, y: scaleY))
        
        // Define RGB vectors with GREEN
        let vectors = [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0.0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1.0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0.0)
        ]
        // Create a colored background image.
        let backgroundImage = maskImage.applyingFilter("CIColorMatrix",
                                                       parameters: vectors)
        // Blend the original, background, and mask images.
        let blendFilter = CIFilter.blendWithRedMask()
        blendFilter.inputImage = originalImage
        blendFilter.backgroundImage = backgroundImage
        blendFilter.maskImage = maskImage
        
        // Set the new, blended image as current.
        if let image = blendFilter.outputImage/*?.oriented(.left)*/ {
            DispatchQueue.main.async {
                self.view.layer?.contents = maskPixelBuffer
                //self.view.layer?.contents = image
            }
        }
    }

}

extension ViewController {
    
    func setupCaptureSession() {
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            fatalError("Error getting AVCaptureDevice.")
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            fatalError("Error getting AVCaptureDeviceInput")
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session = AVCaptureSession()
            self.session?.sessionPreset = .low
            self.session?.addInput(input)
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.bgQueue)
            
            self.session?.addOutput(output)
            self.session?.startRunning()
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Grab the pixelbuffer frame from the camera output
        if processing {
            //print("processing, exiting early")
        }
        processing = true
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        /*DispatchQueue.main.async {
            self.view.layer?.contents = pixelBuffer
        }*/
        processVideoFrame(pixelBuffer)
        processing = false
    }
}
