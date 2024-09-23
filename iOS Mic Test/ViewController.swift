// Be aware, since I didn't create this with XCode
// nor with a proper Intellisense
// Some parts of the code are literally from ChatGPT

import UIKit
import AVFoundation



public func GetDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0]
}

public func RequestCameraAccess(completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
        // Camera access is already granted
        completion(true)
    case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { granted in
            completion(granted)
        }
    case .denied, .restricted:
        // Camera access has been denied or is restricted
        completion(false)
    @unknown default:
        completion(false)
    }
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
    let formatIDKey = Int(kAudioFormatAppleLossless)
    let sampleRate: Double = 44100.0
    let channelCount: AVAudioChannelCount = 1 // This probably means it's Mono
    let qualityEnconder: AVAudioQuality = AVAudioQuality.high

    func getForSettings() -> [String: Any] {
        return [
            AVFormatIDKey: formatIDKey,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderAudioQualityKey: qualityEnconder.rawValue
        ]
    }
    func getForFormat() -> AVAudioFormat? {
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)
    }

    let bufferSize: AVAudioFrameCount = 1024
}


/*class AudioEngineManager {
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
        audioSettings = AudioSettings()
    }

    func setupAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            throw error
        }
    }

    func startRecording() throws {
        // Create a file URL to save the audio
        let audioFilename = GetDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        do {
            // Create the audio file
            audioFile = try AVAudioFile(forWriting: audioFilename, settings: audioSettings.getForSettings())
            
            // Install a tap on the input node
            inputNode.installTap(
                onBus: 0, bufferSize: self.audioSettings.bufferSize, format: audioFormat
            ) { (buffer, time) in
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
        self.cleanUpReset()
    }


    // Start streaming audio
    func startAudioStream() throws {
        audioEngine = AVAudioEngine()
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: self.audioSettings.bufferSize, format: inputFormat) { (buffer, time) in
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
}*/



class ViewController: UIViewController {
    var debugTextBoxOut: UITextView!
    var btnMicToggle: UIButton!
    var ui_connectionLabel: UILabel!

    //let audioEngineManager = AudioEngineManager()
    var isRecordingTest = false
    var audioRecorder: AVAudioRecorder?


    func initUI() {
        // Create the info label
        ui_connectionLabel = UILabel()
        ui_connectionLabel.text = "Status"
        ui_connectionLabel.font = UIFont.systemFont(ofSize: 18)
        ui_connectionLabel.textAlignment = .center
        ui_connectionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ui_connectionLabel)


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
            ui_connectionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            ui_connectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui_connectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),


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
        RequestCameraAccess() { (granted) in
            self.m_requestMicrophoneAccess()
        }
    }

    func showAlert(_ msg: String) {
        let alert = UIAlertController(title: "Alert", message: msg, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        present(alert, animated: true, completion: nil)
    }

    func shareRecordedAudio() {
        let audioFilename = GetDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        let activityViewController = UIActivityViewController(activityItems: [audioFilename], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
    }

    /*func startRecording() {
        do {
            try self.audioEngineManager.startRecording()
            btnMicToggle.setTitle("Stop", for: .normal)
        } catch {
            // Handle Error
            self.debugTextBoxOut.text = "Error starting recording: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        self.audioEngineManager.stopRecording()
        btnMicToggle.setTitle("Start", for: .normal)
        shareRecordedAudio()
    }*/

    func setupAudioSessionWithPolarPattern() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            // Set the audio session category to Record
            try session.setCategory(.record, mode: .default, options: [])
            
            // Activate the audio session
            try session.setActive(true)
            
            // Get the input data sources (e.g., microphone)
            if let inputDataSources = session.inputDataSources {
                for dataSource in inputDataSources {
                    // Check if the Subcardioid pattern is supported
                    if dataSource.supportedPolarPatterns?.contains(AVAudioSession.PolarPattern.subcardioid) == true {
                        
                        // Set the preferred polar pattern to Subcardioid
                        try dataSource.setPreferredPolarPattern(AVAudioSession.PolarPattern.subcardioid)
                        
                        // Optionally set this as the preferred input data source
                        try session.setInputDataSource(dataSource)
                    }
                }
            }
        } catch {
            self.debugTextBoxOut.text = "Error setting up audio session or polar pattern: \(error)"
        }
    }

    func startRecording() {
        setupAudioSessionWithPolarPattern()

        let audioFilename = GetDocumentsDirectory().appendingPathComponent("recording.m4a")

        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            // Initialize the recorder with the file URL and settings
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: audioSettings)
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            print("Recording started...")
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        shareRecordedAudio()
    }

    // Request Microphone Permission
    func m_requestMicrophoneAccess() {
        AVAudioSession.sharedInstance().requestRecordPermission { (granted) in
            if granted {
                DispatchQueue.main.async {
                    //self.showAlert("Microphone access granted!")


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

