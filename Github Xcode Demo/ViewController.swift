import UIKit
import AVFoundation


protocol UI_Comms_Delegate: AnyObject {
    func showAlert(_ msg: String)
}

class AudioManager {
    private var audioEngine: AVAudioEngine!
    private var selectedDevice: AVCaptureDevice?
    weak var delegate: UI_Comms_Delegate?

    // List available microphones
    func listAvailableMicrophones() -> [AVCaptureDevice] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        for device in devices {
            delegate?.showAlert("Microphone: \(device.localizedName), ID: \(device.uniqueID)")
        }

        return devices
    }

    // Select a microphone by its unique ID
    func selectMicrophone(withID id: String) {
        guard let device = AVCaptureDevice.devices(for: .audio).first(where: { $0.uniqueID == id }) else {
            delegate?.showAlert("Microphone not found")
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
            
            delegate?.showAlert("Using microphone: \(device.localizedName)")
        } catch {
            delegate?.showAlert("Error setting up microphone: \(error.localizedDescription)")
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
            delegate?.showAlert("Audio streaming started.")
        } catch {
            delegate?.showAlert("Error starting audio stream: \(error.localizedDescription)")
        }
    }

    // Stop streaming audio
    func stopAudioStream() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        delegate?.showAlert("Audio streaming stopped.")
    }
}



class ViewController: UIViewController, UI_Comms_Delegate {
    let audioManager = AudioManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        audioManager.delegate = self
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


            } else {
                self.showAlert("Microphone access denied!")
            }
        }
    }
}

