import UIKit
import AVFoundation



class AudioManager {
    private var audioEngine: AVAudioEngine!
    private var selectedDevice: AVCaptureDevice?

    // Get Available Microphones
    func GetAvailableMicrophones() -> [AVCaptureDevice] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        return devices
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
    @IBOutlet weak var debugTextBoxOut: UITextView!
    let audioManager = AudioManager()

    debugTextBoxOut.text = "Test"

    override func viewDidLoad() {
        super.viewDidLoad()
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
                    let formatDescription = mic.activeFormat.formatDescription
                    
                    let audioFormatDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)

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

