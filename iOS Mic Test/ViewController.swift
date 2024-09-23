// Be aware, since I didn't create this with XCode
// nor with a proper Intellisense
// Some parts of the code are literally from ChatGPT

import UIKit
import AVFoundation



public func GetDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0]
}

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


struct AudioSettings {
    let formatID: AVAudioFormatID = Int(kAudioFormatAppleLossless)
    let sampleRate: Double = 44100
    let channels: Int = 1
    let qualityEnconder: AVAudioQuality = AVAudioQuality.high.rawValue

    func getForSettings() {
        return [
            AVFormatIDKey: formatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderAudioQualityKey: qualityEnconder.rawValue
        ]
    }
}


class AudioManager {
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat!

    public var audioSettings: AudioSettings

    private var selectedDevice: AVCaptureDevice?
    var error: Error? // Property to hold error

    init() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        audioFormat = inputNode.inputFormat(forBus: 0)
    }

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

    func startRecording() throws {
        // Create a file URL to save the audio
        let audioFilename = GetDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        do {
            // Create the audio file
            audioFile = try AVAudioFile(forWriting: audioFilename, settings: audioFormat.settings)
            
            // Install a tap on the input node
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { (buffer, time) in
                do {
                    // Write the buffer to the audio file
                    try self.audioFile?.write(from: buffer)
                } catch {
                    self.error = error
                }
            }

            // Start the audio engine
            try audioEngine.start()
        } catch {
            // Clean up in case of an error
            cleanUpReset()
            throw error
        }
    }

    func cleanUpReset() {
        self.audioFile = nil
        self.error = nil
    }

    func stopRecording() {
        // Remove the tap and stop the audio engine
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        cleanUpReset()
    }


    // Start streaming audio
    func startAudioStream() throws {
        audioEngine = AVAudioEngine()
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { (buffer, time) in
            // Handle the audio buffer here
        }
        
        do {
            try audioEngine.start()
            // Started
        } catch {
            //throw "Error starting audio stream: \(error.localizedDescription)"
            throw error
        }
    }

    // Stop streaming audio
    func stopAudioStream() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}



class ViewController: UIViewController {
    var debugTextBoxOut: UITextView!
    var btnMicToggle: UIButton!

    var audioRecorder: AVAudioRecorder?
    let audioManager = AudioManager()
    var isRecordingTest = false


    func initUI() {
        // Create the button
        btnMicToggle = UIButton(type: .system)

        // Set button title
        btnMicToggle.setTitle("Button", for: .normal)

        // Disable automatic translation of autoresizing masks into constraints
        btnMicToggle.translatesAutoresizingMaskIntoConstraints = false

        // Add the button to the view
        view.addSubview(btnMicToggle)

        // Set up constraints
        NSLayoutConstraint.activate([
            // Center
            btnMicToggle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            btnMicToggle.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            // Set width and height
            btnMicToggle.widthAnchor.constraint(equalToConstant: 100),
            btnMicToggle.heightAnchor.constraint(equalToConstant: 50)
        ])

        // Add action to the button
        btnMicToggle.addTarget(self, action: #selector(micToggleClicked), for: .touchUpInside)



        // Create UITextView without setting a frame
        debugTextBoxOut = UITextView()
        debugTextBoxOut.translatesAutoresizingMaskIntoConstraints = false // Enable Auto Layout

        // Customize the appearance of the UITextView
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

    override func viewDidLoad() {
        super.viewDidLoad()

        initUI()


        // Register for keyboard notifications
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit {
        // Remove the observers when the view controller is deallocated
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    // Called when the keyboard will appear
    @objc func keyboardWillShow(notification: NSNotification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let keyboardHeight = keyboardFrame.cgRectValue.height
            
            // Move the view up by the height of the keyboard
            self.view.frame.origin.y = -keyboardHeight
        }
    }
    // Called when the keyboard will disappear
    @objc func keyboardWillHide(notification: NSNotification) {
        // Reset the view position
        self.view.frame.origin.y = 0
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true) // Dismiss the keyboard
    }

    // Toggle button
    @IBAction func micToggleClicked(_ sender: UIButton) {
        requestMicrophoneAccess()
    }

    func showAlert(_ msg: String) {
        let alert = UIAlertController(title: "Alert", message: msg, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        present(alert, animated: true, completion: nil)
    }

    func setupAudioRecorder() {
        let audioFilename = GetDocumentsDirectory().appendingPathComponent("recording.m4a")
        
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
        let audioFilename = GetDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        let activityViewController = UIActivityViewController(activityItems: [audioFilename], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
    }

    func startRecording() {
        do {
            try self.audioManager.startRecording()
            btnMicToggle.setTitle("Stop", for: .normal)
        } catch {
            // Handle Error
            self.debugTextBoxOut.text = "Error starting recording: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        self.audioManager.stopRecording()
        btnMicToggle.setTitle("Start", for: .normal)
        shareRecordedAudio()
    }


    // Request Microphone Permission
    func requestMicrophoneAccess() {
        AVAudioSession.sharedInstance().requestRecordPermission { (granted) in
            if granted {
                DispatchQueue.main.async {
                    //self.showAlert("Microphone access granted!")

                    let message = ""

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
                        self.isRecordingTest = true

                        self.startRecording()
                    } else {
                        self.stopRecording()
                        self.isRecordingTest = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.showAlert("Microphone access denied!")
                }
            }
        }
    }
}

