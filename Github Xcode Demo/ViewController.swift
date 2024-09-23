// Be aware, since I didn't create this with XCode
// nor with a proper Intellisense
// Some parts of the code are literally from ChatGPT

import UIKit
import AVFoundation

/// Returns all cameras on the device.
public func GetListOfCameras() -> [AVCaptureDevice] {
    #if os(iOS)
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .unspecified)
    #elseif os(macOS)
        let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .unspecified)
    #endif
        return session.devices
}

/// Returns all microphones on the device.
public func GetListOfMicrophones() -> [AVCaptureDevice] {
    let session = AVCaptureDevice.DiscoverySession(
        deviceTypes: [
            .builtInMicrophone
        ],
        mediaType: .audio,
        position: .unspecified)
    
    return session.devices
}


/// Returns all available input ports (microphones) on the device.
public func GetAvailableMicrophoneInputs() -> [AVAudioSessionPortDescription]? {
    let audioSession = AVAudioSession.sharedInstance()
    
    do {
        try audioSession.setCategory(
            AVAudioSession.Category.playAndRecord,
            options: AVAudioSession.CategoryOptions.defaultToSpeaker
        )
        try audioSession.setActive(true)
    } catch {
        print("Error activating audio session: \(error)")
        return nil
    }
    
    // Get the available microphone inputs
    let availableInputs = audioSession.availableInputs
    
    // Deactivate the audio session after retrieving inputs
    do {
        try audioSession.setActive(false)
    } catch {
        print("Error deactivating audio session: \(error)")
    }

    return availableInputs
}



class AudioManager {
    private var audioEngine: AVAudioEngine!
    private var selectedDevice: AVCaptureDevice?

    // Select a microphone by its unique ID
    func selectMicrophone(withID id: String) {
        guard let device = AVCaptureDevice.devices(for: .audio).first(where: { $0.uniqueID == id }) else {
            // Microphone not found
            return
        }
        
        selectedDevice = device
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            let input = try AVCaptureDeviceInput(device: device)
            let captureSession = AVCaptureSession()
            captureSession.addInput(input)
            captureSession.startRunning()
            
            print("Using microphone: \(device.localizedName)")
        } catch {
            print("Error setting up microphone: \(error.localizedDescription)")
        }
    }

    // Start streaming audio
    func startAudioStream() {
        audioEngine = AVAudioEngine()
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { (buffer, time) in
            // Handle the audio buffer here
        }
        
        do {
            try audioEngine.start()
            print("Audio streaming started.")
        } catch {
            print("Error starting audio stream: \(error.localizedDescription)")
        }
    }

    // Stop streaming audio
    func stopAudioStream() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        print("Audio streaming stopped.")
    }
}



class ViewController: UIViewController {
    var debugTextBoxOut: UITextView!
    var audioRecorder: AVAudioRecorder?
    let audioManager = AudioManager()
    var isRecordingTest = false

    override func viewDidLoad() {
        super.viewDidLoad()

       // Create UITextView
        debugTextBoxOut = UITextView(frame: CGRect(x: 20, y: 100, width: 300, height: 200))
        debugTextBoxOut.backgroundColor = UIColor.lightGray
        debugTextBoxOut.textColor = UIColor.black
        debugTextBoxOut.font = UIFont.systemFont(ofSize: 18)
        
        // Set initial text
        debugTextBoxOut.text = "Test"

        // Add the UITextView to the view hierarchy
        self.view.addSubview(debugTextBoxOut)

        // Set up constraints
        NSLayoutConstraint.activate([
            // Full width
            debugTextBoxOut.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            debugTextBoxOut.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Small height
            debugTextBoxOut.heightAnchor.constraint(equalToConstant: 100),
            
            // Pin to the bottom of the screen
            debugTextBoxOut.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    @IBAction func buttonClicked(_ sender: UIButton) {
        requestMicrophoneAccess()
    }

    func showAlert(_ msg: String) {
        let alert = UIAlertController(title: "Alert", message: msg, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        present(alert, animated: true, completion: nil)
    }


    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    func setupAudioRecorder() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.wav")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.prepareToRecord()
        } catch {
            self.debugTextBoxOut.text = "Failed to set up audio recorder: \(error)"
        }
    }

    func shareRecordedAudio() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.wav")
        
        let activityViewController = UIActivityViewController(activityItems: [audioFilename], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
    }

    func startRecording() {
        audioRecorder?.record()
        self.showAlert("Recording started...")
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        self.showAlert("Recording stopped.")
        shareRecordedAudio()
    }


    // Request Microphone Permission
    func requestMicrophoneAccess() {
        AVAudioSession.sharedInstance().requestRecordPermission { (granted) in
            if granted {
                //self.showAlert("Microphone access granted!")

                var message = ""

                /*if let micInputs = GetAvailableMicrophoneInputs() {
                    for micInput in micInputs {
                        // Builder string
                        message = "Available Mic Inputs:\n\n"
                        for micInput in micInputs {
                            message += "Port Name: \(micInput.portName)\n"
                            message += "Port Type: \(micInput.portType)\n"
                            message += "\n" // new line
                        }
                    }
                } else {
                    message = "No available microphone inputs."
                }*/
                
                // Set text
                self.debugTextBoxOut.text = message


                if (self.isRecordingTest == false) {
                    self.setupAudioRecorder()
                    self.isRecordingTest = true

                    self.startRecording()
                } else {
                    self.stopRecording()
                    self.isRecordingTest = false
                }

            } else {
                self.showAlert("Microphone access denied!")
            }
        }
    }
}

