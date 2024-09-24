// Be aware, since I didn't create this with XCode
// nor with a proper Intellisense
// Some parts of the code are literally from ChatGPT

import UIKit
import AVFoundation
import Network



public func GetDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0]
}

public func GetLocalIPAddress() -> String? {
    var address: String?
    
    var ifaddrs: UnsafeMutablePointer<ifaddrs>? = nil
    if getifaddrs(&ifaddrs) == 0 {
        var ptr = ifaddrs
        
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            // Check if the interface is IPv4 and not loopback
            if addrFamily == AF_INET {
                let name = String(cString: interface.ifa_name)
                if name == "en0" { // en0 is usually WiFi interface
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                    }
                }
            }
        }
        freeifaddrs(ifaddrs)
    }
    
    return address
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

struct AudioSettings {
    var formatIDKey = Int(kAudioFormatAppleLossless)
    var sampleRate: Double = 44100.0
    var channelCount: AVAudioChannelCount = 1 // This probably means it's Mono
    var qualityEnconder: AVAudioQuality = AVAudioQuality.high

    var polarPatternCfg: AVAudioSession.PolarPattern = AVAudioSession.PolarPattern.cardioid

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

    var bufferSize: AVAudioFrameCount = 1024
}


class CombinedSettingsTableView: NSObject, UITableViewDelegate, UITableViewDataSource {
    var tableView: UITableView!
    var polarPatternSelections: [AVAudioSession.PolarPattern] {
        // Define the polar patterns based on iOS version
        var patterns: [AVAudioSession.PolarPattern] = [.cardioid, .subcardioid, .omnidirectional]
        
        // Check if the iOS version is 14.0 or newer
        if #available(iOS 14.0, *) {
            patterns.append(.stereo) // Add stereo pattern for iOS 14 and above
        }
        
        return patterns
    }

    // Input data sources for selection
    var dataSourceSelections: [AVAudioSessionDataSourceDescription] = []
    // inputDataSources

    enum TableSection: Int, CaseIterable {
        case SectionDataSource = 0
        case SectionPolarPattern
        
        var title: String {
            switch self {
            case .SectionDataSource:
                return "Input Data Sources"
            case .SectionPolarPattern:
                return "Polar Patterns"
            }
        }
    }


    func polarPatternName(for pattern: AVAudioSession.PolarPattern?) -> String {
        if #available(iOS 14.0, *) {
            switch pattern {
            case .stereo:
                return "Stereo"
            case .cardioid:
                return "Cardioid"
            case .subcardioid:
                return "Subcardioid"
            case .omnidirectional:
                return "Omnidirectional"
            default:
                return "Unknown Pattern"
            }
        } else {
            // Fallback for earlier versions
            switch pattern {
            case .cardioid:
                return "Cardioid"
            case .subcardioid:
                return "Subcardioid"
            case .omnidirectional:
                return "Omnidirectional"
            default:
                return "Unknown Pattern"
            }
        }
    }

    var selectedPattern: AVAudioSession.PolarPattern?
    var selectedDataSource: AVAudioSessionDataSourceDescription?

    var onPatternSelected: ((AVAudioSession.PolarPattern) -> Void)? // Callback to notify selection
    var onDataSourceSelected: ((AVAudioSessionDataSourceDescription) -> Void)? // Callback for data source


    // Update the input data sources when needed
    func updateInputDataSources(_ sources: [AVAudioSessionDataSourceDescription]) {
        dataSourceSelections = sources
        tableView.reloadSections([TableSection.SectionDataSource.rawValue], with: .automatic)
    }


    // Init
    override init() {
        super.init()
        setupTableView()
    }

    private func setupTableView()  {
        // Initialize and set up the table view
        tableView = UITableView()
        tableView.delegate = self
        tableView.dataSource = self

        // If these things are not registered, the app can crash.
        // Crash logs on iOS are found in the Analytics
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "polarPatternCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "inputDataSourceCell")

        tableView.layer.cornerRadius = 8
        tableView.clipsToBounds = true
        tableView.backgroundColor = .white

        tableView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    // MARK: - TableView DataSource Methods
    func numberOfSections(in tableView: UITableView) -> Int {
        return TableSection.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = TableSection(rawValue: section) else { return 0 }
        switch sectionType {
        case .SectionDataSource:
            return dataSourceSelections.count
        case .SectionPolarPattern:
            return polarPatternSelections.count
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return TableSection(rawValue: section)?.title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sectionType = TableSection(rawValue: indexPath.section)!
        
        switch sectionType {
        case .SectionDataSource:
            let cell = tableView.dequeueReusableCell(withIdentifier: "inputDataSourceCell", for: indexPath)
            let dataSource = dataSourceSelections[indexPath.row]
            cell.textLabel?.text = dataSource.dataSourceName
            
            // Add checkmark if this is the selected input data source
            if selectedDataSource == dataSource {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
            return cell
            
        case .SectionPolarPattern:
            let cell = tableView.dequeueReusableCell(withIdentifier: "polarPatternCell", for: indexPath)
            let pattern = polarPatternSelections[indexPath.row]
            cell.textLabel?.text = polarPatternName(for: pattern)
            
            // Add checkmark if this is the selected polar pattern
            if selectedPattern == pattern {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
            return cell
        }
    }

    // MARK: - TableView Delegate Methods
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sectionType = TableSection(rawValue: indexPath.section)!
        
        switch sectionType {
        case .SectionDataSource:
            selectedDataSource = dataSourceSelections[indexPath.row]
            tableView.reloadData() // Reload to update checkmarks

            onDataSourceSelected?(selectedDataSource!)
            
        case .SectionPolarPattern:
            selectedPattern = polarPatternSelections[indexPath.row]
            tableView.reloadData() // Reload to update checkmarks

            onPatternSelected?(selectedPattern!)
        }
    }
}


class AudioManager {
    var audioRecorder: AVAudioRecorder?
    var audioSettings = AudioSettings()

    func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        
        do {
            // Set the audio session category to Record
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            
            // Activate the audio session
            try session.setActive(true)
            
            // Get the input data sources (e.g., microphone)
            /*if let inputDataSources = session.inputDataSources {
                for dataSource in inputDataSources {
                    // Check if the Subcardioid pattern is supported
                    if dataSource.supportedPolarPatterns?.contains(audioSettings.polarPatternCfg) == true {
                        
                        // Set the preferred polar pattern to Subcardioid
                        try dataSource.setPreferredPolarPattern(audioSettings.polarPatternCfg)
                        
                        // Optionally set this as the preferred input data source
                        //try session.setInputDataSource(dataSource)
                    }
                }
            }*/
        } catch {
            throw error
        }
    }

    func startRecording() throws {
        do {
            try setupAudioSession()
        } catch {
            throw error
        }

        let audioFilename = GetDocumentsDirectory().appendingPathComponent("recording.m4a")

        let audioSettings: [String: Any] = [
            // other was kAudioFormatMPEG4AAC
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            // Initialize the recorder with the file URL and settings
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: audioSettings)
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
        } catch {
            throw error
        }
    }

    func stopRecording() throws {
        audioRecorder?.stop()
        try AVAudioSession.sharedInstance().setActive(false)
    }
}


// Collection of some Strings
struct STR_TBL {
    var BTN_START_TEST_RECORD = "Record Test"
    var BTN_STOP_RECORDING = "Stop Recording"
}


struct StatusInfoStruct {
    var connectionStatusText = "Not Connected"
    var localIP = "Not Retrieved"
}


class ViewController: UIViewController {
    var tableView: UITableView!
    var debugTextBoxOut: UITextView!
    var btnRecordTestToggle: UIButton!
    var btnMicToggle: UIButton!
    

    var statusInfoStruct = StatusInfoStruct()
    var ui_connectionLabel: UILabel!

    var polarPatternTableView: CombinedSettingsTableView!

    let audioManager = AudioManager()
    var is_RecordingTest = false
    var is_VoIP_active = false


    func initUI() {
        // Create the info label
        ui_connectionLabel = UILabel()
        ui_connectionLabel.text = "Status"
        ui_connectionLabel.font = UIFont.systemFont(ofSize: 18)
        ui_connectionLabel.textAlignment = .center
        ui_connectionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ui_connectionLabel)


        // Create the button
        btnRecordTestToggle = UIButton(type: .system)
        btnRecordTestToggle.setTitle("Record Test", for: .normal)
        // Disable automatic translation of autoresizing masks into constraints
        btnRecordTestToggle.translatesAutoresizingMaskIntoConstraints = false
        // Add the button to the view
        view.addSubview(btnRecordTestToggle)


        btnMicToggle = UIButton(type: .system)
        btnMicToggle.setTitle("Start Mic", for: .normal)
        btnMicToggle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btnMicToggle)


        // Set up constraints
        NSLayoutConstraint.activate([
            ui_connectionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            ui_connectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ui_connectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),


            // Center with offset
            btnRecordTestToggle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            btnRecordTestToggle.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50), // Moved up by 50 points
            // Set width and height
            btnRecordTestToggle.widthAnchor.constraint(equalToConstant: 100),
            btnRecordTestToggle.heightAnchor.constraint(equalToConstant: 50),

            
            // VoIP Button
            btnMicToggle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            btnMicToggle.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            btnMicToggle.widthAnchor.constraint(equalToConstant: 150),
            btnMicToggle.heightAnchor.constraint(equalToConstant: 50),
        ])

        // Add action to the button
        btnRecordTestToggle.addTarget(self, action: #selector(action_recordTestToggleClicked), for: .touchUpInside)
        btnMicToggle.addTarget(self, action: #selector(action_micToggleClicked), for: .touchUpInside)


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


    // Fast made Settings
    func setupCombinedSettingsTableView() {
        // Init
        polarPatternTableView = CombinedSettingsTableView()
        tableView = polarPatternTableView.tableView
        
        self.view.addSubview(polarPatternTableView.tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: self.debugTextBoxOut.topAnchor, constant: -10),
            tableView.heightAnchor.constraint(equalToConstant: 180)
        ])


        // Update the data sources, I guess
        let session = AVAudioSession.sharedInstance()
        if let inputDataSources = session.inputDataSources, !inputDataSources.isEmpty {
            self.polarPatternTableView.updateInputDataSources(inputDataSources)
        }

        // Set up callback when a polar pattern is selected
        polarPatternTableView.onDataSourceSelected = { [weak self] selectedDataSource in
            self?.updateDataSource(selectedDataSource)
        }

        polarPatternTableView.onPatternSelected = { [weak self] selectedPattern in
            self?.updatePolarPattern(selectedPattern)
        }
    }

    // Update DataSource
    func updateDataSource(_ dataSource: AVAudioSessionDataSourceDescription) {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setInputDataSource(dataSource)
            self.debugTextBoxOut.text = "Data Source set to: \(dataSource.dataSourceName)"
        } catch {
            self.debugTextBoxOut.text = "Error setting dataSource: \(error.localizedDescription)"
        }
    }

    // Update Polar Pattern
    func updatePolarPattern(_ pattern: AVAudioSession.PolarPattern) {
        // Update in the settings struct
        audioManager.audioSettings.polarPatternCfg = pattern

        let session = AVAudioSession.sharedInstance()

        do {
            if let inputDataSources = session.inputDataSources {
                var isSupported = false
                
                for dataSource in inputDataSources {
                    if dataSource.supportedPolarPatterns?.contains(pattern) == true {
                        isSupported = true

                        try dataSource.setPreferredPolarPattern(pattern)
                        self.debugTextBoxOut.text = "Polar pattern set to: \(polarPatternTableView.polarPatternName(for: pattern))"
                    }

                    if (isSupported == false) {
                        self.debugTextBoxOut.text
                            = "Selected polar pattern \(polarPatternTableView.polarPatternName(for: pattern)) is not supported on any data source."
                    }
                }
            }
        } catch {
            self.debugTextBoxOut.text = "Error setting polar pattern: \(error.localizedDescription)"
        }
    }


    // On view loaded
    override func viewDidLoad() {
        super.viewDidLoad()

        initUI()
        setupCombinedSettingsTableView()

        updateLocalIPStatusText()


        // Register for keyboard notifications
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    // Deinit
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

    
    // Pop-up Prompt thing
    func showAlert(_ msg: String) {
        let alert = UIAlertController(title: "Alert", message: msg, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        present(alert, animated: true, completion: nil)
    }


    // Toggle button
    @IBAction func action_recordTestToggleClicked(_ sender: UIButton) {
        RequestCameraAccess() { (granted) in
            self.m_toggleTestRecord()
        }
    }
    @IBAction func action_micToggleClicked(_ sender: UIButton) {
        self.m_toggle_MicVoIP()
    }


    // Prompt to save file
    func shareRecordedAudio() {
        let audioFilename = GetDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        let activityViewController = UIActivityViewController(activityItems: [audioFilename], applicationActivities: nil)

        // Handle completion with deletion of the file
        activityViewController.completionWithItemsHandler = { (activityType, completed, returnedItems, activityError) in
            if completed {
                // File shared successfully
            } else {
                // File sharing canceled or failed
            }
            
            // Now we can safely delete the file whether or not the sharing was completed
            do {
                try FileManager.default.removeItem(at: audioFilename)
                print("Recording file deleted.")
            } catch {
                self.debugTextBoxOut.text = "Error deleting recording file: \(error)"
            }
        }

        present(activityViewController, animated: true, completion: nil)
    }

    func startRecording() {
        do {
            try self.audioManager.startRecording()
            btnRecordTestToggle.setTitle("Stop Recording", for: .normal)
        } catch {
            // Handle Error
            self.debugTextBoxOut.text = "Error starting recording: \(error.localizedDescription)"
        }
    }
    func stopRecording() {
        do {
            try self.audioManager.stopRecording()
        } catch {
            self.debugTextBoxOut.text = "Error stopping recording: \(error.localizedDescription)"
        }

        btnRecordTestToggle.setTitle("Start Recording", for: .normal)
        shareRecordedAudio()
    }

    func m_toggleTestRecord() {
        // Request Microphone Permission
        AVAudioSession.sharedInstance().requestRecordPermission { (granted) in
            if granted {
                DispatchQueue.main.async {
                    //self.showAlert("Microphone access granted!")

                    // Quick Debug
                    let session = AVAudioSession.sharedInstance()
                    var message = "Data Sources:\n"
                    if let inputDataSources = session.inputDataSources {
                        for dataSource in inputDataSources {
                            message += "Name: \(dataSource.dataSourceName)\n"
                            message += "Polar Pattern: \(self.polarPatternTableView.polarPatternName(for: dataSource.selectedPolarPattern))\n"
                        }
                    }
                    self.debugTextBoxOut.text = message


                    if (self.is_RecordingTest == false) {
                        self.is_RecordingTest = true

                        self.startRecording()
                    } else {
                        self.stopRecording()
                        self.is_RecordingTest = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.showAlert("Microphone access denied!")
                }
            }
        }
    }



    // Update Connection Label
    func updateStatusConnectionLabel() {
        ui_connectionLabel.text = "Status: \(statusInfoStruct.connectionStatusText)" + "\n"
            + "Local IP: \(statusInfoStruct.localIP)" + "\n"

        // Change Label size to fit content.
        ui_connectionLabel.sizeToFit()
    }
    func updateLocalIPStatusText() {
        if let localIP = GetLocalIPAddress() {
            statusInfoStruct.localIP = localIP
        } else {
            statusInfoStruct.localIP = "N/A"
        }

        updateStatusConnectionLabel()
    }


    // VoIP
    func start_VoIPMic() {
        do {
            //try self.audioManager.startRecording()
        } catch {
            // Handle Error
            self.debugTextBoxOut.text = "Error starting: \(error.localizedDescription)"
        }

        btnRecordTestToggle.setTitle("Stop Mic", for: .normal)
    }
    func stop_startVoIPMic() {
        do {
            //try self.audioManager.stopRecording()
        } catch {
            self.debugTextBoxOut.text = "Error stopping: \(error.localizedDescription)"
        }

        btnRecordTestToggle.setTitle("Start Mic", for: .normal)
    }

    func m_toggle_MicVoIP() {
        AVAudioSession.sharedInstance().requestRecordPermission { (granted) in
            if granted {
                DispatchQueue.main.async {
                    if (self.is_VoIP_active == false) {
                        self.is_VoIP_active = true

                        self.start_VoIPMic()
                    } else {
                        self.stop_startVoIPMic()
                        self.is_VoIP_active = false
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

