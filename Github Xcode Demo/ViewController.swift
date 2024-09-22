import UIKit
import AVFoundation

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func buttonClicked(_ sender: UIButton) {
        showAlert("Button Clicked!")
    }

    func showAlert(msg: String) {
        let alert = UIAlertController(title: "Alert", message: msg, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        present(alert, animated: true, completion: nil)
    }


    // Request Microphone Permission
    func requestMicrophoneAccess() {
        AVAudioSession.sharedInstance().requestRecordPermission { (granted) in
            if granted {
                showAlert("Microphone access granted!")


            } else {
                showAlert("Microphone access denied!")
            }
        }
    }
}

