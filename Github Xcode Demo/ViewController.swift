import UIKit
import AVFoundation



class AudioManager {
    private var audioEngine: AVAudioEngine!
    private var selectedDevice: AVCaptureDevice?

    // Get Available Microphones
    func GetAvailableMicrophones() -> [AVCaptureDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.filter { $0.hasMediaType(.audio) }
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
    let audioManager = AudioManager()

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


    // Request Microphone Permission
    func requestMicrophoneAccess() {
        AVAudioSession.sharedInstance().requestRecordPermission { (granted) in
            if granted {
                self.showAlert("Microphone access granted!")

                let microphones = self.audioManager.GetAvailableMicrophones()

                // Builder string
                var message = "Available Microphones:\n\n"

                for mic in microphones {
                    message += "Microphone: \(mic.localizedName)\n"
                    message += "ID: \(mic.uniqueID)\n"
                    message += "Position: \(mic.position.rawValue)\n"
                }
                
                // Set text
                self.debugTextBoxOut.text = message

            } else {
                self.showAlert("Microphone access denied!")
            }
        }
    }
}

