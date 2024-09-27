// Be aware, since I didn't create this with XCode
// nor with a proper Intellisense
// Some parts of the code are literally from ChatGPT

import UIKit
import AVFoundation
import Foundation
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
        // Access is already granted
        completion(true)
    case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { granted in
            completion(granted)
        }
    case .denied, .restricted:
        // Access has been denied or is restricted
        completion(false)
    @unknown default:
        completion(false)
    }
}

public func RequestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        // Access is already granted
        completion(true)
    case .notDetermined:
        // Request microphone access
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            completion(granted)
        }
    case .denied, .restricted:
        // Access has been denied or is restricted
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

class AudioSettingsClass {
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



/***
    =================================
    So there's a couple of ways.
    A cool way is if Laptop/PC can directly go to the IP-Address of the Phone
    to ask it if it can connect.

    But the other way around is also possible.
    =================================

    The next part in what format to send data as.
    And then there's also the protocol.
***/
class NetworkVoiceTCPServer : TCPServer {
    var activeConnection: NWConnection? // Active Connection

    var m_onAcceptedConnectionEstablished: ((NWConnection) -> Void)!

    override func handleNewConnection(_ newConnection: NWConnection) {
        if (activeConnection != nil) {
            // Only allow one accepted connection.
            return
        }

        super.handleNewConnection(newConnection)
    }

    override func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            self?.connectionStateHandler(connection: connection, state: state)
        }

        connection.start(queue: .main)
    }

    // Handshake
    private func m_customHandshake(_ incomingConnection: NWConnection) {
        let handshakeTimeout: TimeInterval = 10

        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: handshakeTimeout, repeats: false) { [weak self] _ in
            // Cancel when timeout
            incomingConnection.cancel()

            DispatchQueue.main.async {
                G_UI_Class_connectionLabel.setStatusConnectionText("Handshake Timeout")
            }
        }

        /***
            IMPORTANT
        ***/
        // We need to receive this
        // And the incoming request has to send this
        let expectedWord = ("iOS_Mic_Test").data(using: .utf8)

        incomingConnection.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self] data, context, isComplete, error in
            G_UI_Class_connectionLabel.setStatusConnectionText("Received something...")

            if (data == expectedWord) {
                timeoutTimer.invalidate() // Erase the timeout

                // We are alright!
                // Let's tell that back
                // Just note that... seeing how this works
                // Perhaps whatever you try to connect, whether this is a safe way
                // To check that it's the actual app is another question

                let response = ("Accepted").data(using: .utf8)!
                incomingConnection.send(
                    content: response,
                    completion: .contentProcessed({ error in 
                        if let error = error {
                            G_UI_Class_connectionLabel.setStatusConnectionText("Error Sending Handshake Back")
                        } else {
                            G_UI_Class_connectionLabel.setStatusConnectionText("Response sent to \(incomingConnection.endpoint)")

                            // Accept it
                            // After we sent
                            self?.m_acceptIncomingConnection(incomingConnection)
                        }
                    })
                )

            }
        }
    }


    // Alright, we real
    func m_acceptIncomingConnection(_ connection: NWConnection) {
        activeConnection = connection;

        G_UI_Class_connectionLabel.setStatusConnectionText("Connection established with \(connection.endpoint)")

        // We can now do the streaming thing
        // Trigger this
        self.m_onAcceptedConnectionEstablished(connection)
    }


    override func connectionStateHandler(connection: NWConnection, state: NWConnection.State) {
        switch state {
        case .ready:
            // If this part reaches
            // It means that we should verify whether we really want to connect or not.
            G_UI_Class_connectionLabel.setStatusConnectionText("Incoming request from  \(connection.endpoint)")

            // Check for handshake
            self.m_customHandshake(connection)
        case .failed(let error):
            G_UI_Class_connectionLabel.setStatusConnectionText("Connection failed: \(error)")
        case .cancelled:
            G_UI_Class_connectionLabel.setStatusConnectionText("Connection cancelled")
        default:
            break
        }
    }

    func cleanUp() {
        self.activeConnection = nil
    }

    override func startServer() throws {
        G_UI_Class_connectionLabel.setStatusConnectionText("Starting Server...")

        do {
            try super.startServer()

            G_UI_Class_connectionLabel.setStatusConnectionText("Server started, Port \(self.port.rawValue)")
        } catch {
            G_UI_Class_connectionLabel.setStatusConnectionText("Error when starting: \(error.localizedDescription)")
        }
    }

    override func stopServer() {
        super.stopServer()

        cleanUp()

        G_UI_Class_connectionLabel.setStatusConnectionText("Server stopped")
    }
}

class NetworkVoiceManager {
    var networkVoice_TCPServer: NetworkVoiceTCPServer!

    var DEFAULT_TCP_PORT: UInt16 = 8125
    var audioEngineManager: AudioEngineManager!

    init(withAudioEngineManager: AudioEngineManager) {
        self.audioEngineManager = withAudioEngineManager

        self.networkVoice_TCPServer = NetworkVoiceTCPServer(inputPort: DEFAULT_TCP_PORT)

        // Event when we actually got a real connection going
        self.networkVoice_TCPServer.m_onAcceptedConnectionEstablished = { [weak self] connection in
            self?.handleAcceptedConnection(connection)
        }
    }

    // When we have connection we can start streaming
    // This will make us start streaming
    func handleAcceptedConnection(_ connection: NWConnection) {
        var audioEngine = audioEngineManager.audioEngine
        let audioSettings = audioEngineManager.audioSettings
        guard let audioEngine = audioEngine else { return }
        guard let audioSettings = audioSettings else { return }

        G_UI_Class_connectionLabel.setStatusConnectionText("Streaming for \(connection.endpoint)")


        var inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        // Testing
        inputNode.installTap(
            onBus: 0, bufferSize: audioSettings.bufferSize, format: audioEngineManager.audioFormat
        ) { (buffer, time) in
            self.transmitAudio(buffer: buffer, connection)
        }

        
        /*do {
            try audioEngine.start()
        } catch {
            G_UI_Class_connectionLabel.setStatusConnectionText("AudioEngine Error: \(error)")
        }*/
    }

    func transmitAudio(buffer: AVAudioPCMBuffer, _ connection: NWConnection) {
        let audioData = buffer.audioBufferList.pointee.mBuffers
        let dataSize = audioData.mDataByteSize
        
        // Check if data is available
        guard let dataPointer = audioData.mData else {
            G_UI_Class_connectionLabel.setStatusConnectionText("Problem")
            return
        }

        // Data
        let audioBytes = Data(bytes: dataPointer, count: Int(dataSize))
        
        // Send audio data
        connection.send(
            content: audioBytes,
            completion: .contentProcessed({ error in
                if let error = error {
                    G_UI_Class_connectionLabel.setStatusConnectionText("Error sending audio data: \(error)")
                }
            })
        )
    }



    func start() throws {
        do {
            try self.networkVoice_TCPServer.startServer()
        } catch {
            throw error
        }
    }

    func stop() {
        self.networkVoice_TCPServer.stopServer()
    }
}


// Example usage from a copy of an Apple Example
// https://github.com/winstondu/Voice-Processing-Demo/blob/master/AVEchoTouch/ViewController.swift
class AudioEngineManager {
    var audioEngine: AVAudioEngine!
    var inputNode: AVAudioInputNode!
    var audioFormat: AVAudioFormat!

    var tempError: Error? // Property to hold temporary error
    var audioFile: AVAudioFile?

    var audioSettings: AudioSettingsClass!


    init(withAudioSettings: AudioSettingsClass) {
        self.audioEngine = AVAudioEngine()
        self.audioSettings = withAudioSettings
    }

    // It's important to call this function before starting the Engine
    // Or anything else, e.g. installTap
    func setupInit() {
        self.inputNode = audioEngine.inputNode
        self.audioFormat = inputNode.inputFormat(forBus: 0)
    }


    // For Testing
    func startRecordingEngine() throws {
        // Create a file URL to save the audio
        let audioFilename = GetDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        do {
            // Create the audio file
            self.audioFile = try AVAudioFile(forWriting: audioFilename, settings: audioSettings.getForSettings())
            
            // Install a tap on the input node
            inputNode.installTap(
                onBus: 0, bufferSize: self.audioSettings.bufferSize, format: audioFormat
            ) { (buffer, time) in
                do {
                    // Write the buffer to the audio file
                    try self.audioFile?.write(from: buffer)
                } catch {
                    self.tempError = error
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
        self.tempError = nil
    }
    func stopRecordingEngine() {
        // Remove the tap and stop the audio engine
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        self.cleanUpReset()
    }
}


class AudioManager {
    var audioRecorder: AVAudioRecorder?
    var audioSettings = AudioSettingsClass()

    var audioEngineManager: AudioEngineManager!
    var networkVoiceManager: NetworkVoiceManager!

    // Init function
    init() {
        self.audioEngineManager = AudioEngineManager(withAudioSettings: audioSettings)
        self.networkVoiceManager = NetworkVoiceManager(withAudioEngineManager: self.audioEngineManager)
    }


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
            // self. would also work
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



    // VoIP
    func setup_AudioSessionForVoIP() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.multiRoute, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            throw error
        }
    }

    func setup_VoIP() {

    }

    func start_VoIP() throws {
        do {
            // Call this because .stop() used with .preare() may be removing
            // some allocated nodes that we need to ensure
            // exist
            audioEngineManager.setupInit()

            // Calling this requires setupInit to be called again when stopped
            // Hence why the start function has setupInit again
            audioEngineManager.audioEngine.prepare()

            try self.setup_AudioSessionForVoIP()

            try self.networkVoiceManager.start()
            // audioEngine start function appears somewhere else for network


            //try audioEngineManager.startRecordingEngine()
        } catch {
            throw error
        }
    }

    func stop_VoIP() throws {
        //audioEngineManager.stopRecordingEngine()

        try self.networkVoiceManager.stop()

        if (audioEngineManager.audioEngine.isRunning) {
            audioEngineManager.audioEngine.stop()
        }
        
        // The order on when this gets called seems to be important
        try AVAudioSession.sharedInstance().setActive(false)
    }
}


// Collection of some Strings
struct STR_TBL {
    var BTN_START_TEST_RECORD = "Record Test"
    var BTN_STOP_RECORDING = "Stop Recording"
}



class UI_NetworkStatus_SingletonClass {
    struct NetworkStatusInfoStruct {
        var connectionStatusText = "Not Connected"
        var localIP = "Not Retrieved"
    }

    
    // Function to retrieve the singleton instance
    static func shared() -> UI_NetworkStatus_SingletonClass {
        if sharedInstance == nil {
            sharedInstance = UI_NetworkStatus_SingletonClass()
        }
        return sharedInstance!
    }

    var statusInfoStruct = NetworkStatusInfoStruct()
    var ui_connectionLabel: UILabel!
    
    // Private static variable to hold the singleton instance
    private static var sharedInstance: UI_NetworkStatus_SingletonClass?


    // Private initializer to prevent instantiation from outside
    private init() {
        ui_connectionLabel = UILabel()
        ui_connectionLabel.text = "Status"
        ui_connectionLabel.font = UIFont.systemFont(ofSize: 18)
        ui_connectionLabel.textAlignment = .center
        ui_connectionLabel.numberOfLines = 0  // Allow multiple lines
        ui_connectionLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    // Update Connection Label
    func updateStatusConnectionLabel() {
        ui_connectionLabel.text = "Status: \(self.statusInfoStruct.connectionStatusText)" + "\n" +
            "Local IP: \(self.statusInfoStruct.localIP)" + "\n"

        // Change Label size to fit content.
        ui_connectionLabel.sizeToFit()
    }

    func updateLocalIPStatusText() {
        if let localIP = GetLocalIPAddress() {
            self.statusInfoStruct.localIP = localIP
        } else {
            self.statusInfoStruct.localIP = "N/A"
        }

        self.updateStatusConnectionLabel()
    }

    func setStatusConnectionText(_ text: String) {
        statusInfoStruct.connectionStatusText = text
        self.updateStatusConnectionLabel() // Update
    }
}


// not global but I want to access this from anywhere
var G_UI_Class_connectionLabel = UI_NetworkStatus_SingletonClass.shared()


class ViewController: UIViewController {
    var tableView: UITableView!
    var debugTextBoxOut: UITextView!
    var btnRecordTestToggle: UIButton!
    var btnMicToggle: UIButton!
    

    var UI_Class_connectionLabel = UI_NetworkStatus_SingletonClass.shared()
    var ui_connectionLabel: UILabel!

    var polarPatternTableView: CombinedSettingsTableView!

    let audioManager = AudioManager()
    var is_RecordingTest = false
    var is_VoIP_active = false


    func initUI() {
        // Create the info label
        self.ui_connectionLabel = UI_Class_connectionLabel.ui_connectionLabel
        view.addSubview(self.ui_connectionLabel)


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
            self.ui_connectionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            self.ui_connectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            self.ui_connectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),


            // Center with offset
            btnRecordTestToggle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            btnRecordTestToggle.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50), // Moved up by 50 points
            // Set width and height
            btnRecordTestToggle.widthAnchor.constraint(equalToConstant: 150),
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

        UI_Class_connectionLabel.updateLocalIPStatusText()


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

    // Recalculate constraints on orientation change
    // This probably isn't needed though...
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { _ in
            self.view.setNeedsUpdateConstraints()  // Request constraint updates
            self.view.layoutIfNeeded()  // Apply updated constraints immediately
        })
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
            
            // Is this even needed?
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

            DispatchQueue.main.async { // This is needed or else it will crash
                if granted {
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
                } else {
                    self.showAlert("Microphone access denied!")
                }
            }

        }
    }


    // VoIP
    func start_VoIPMic() {
        do {
            try self.audioManager.start_VoIP()
        } catch {
            // Handle Error
            self.debugTextBoxOut.text = "Error starting: \(error.localizedDescription)"
        }

        btnMicToggle.setTitle("Stop Mic", for: .normal)
    }
    func stop_VoIPMic() {
        do {
            try self.audioManager.stop_VoIP()
        } catch {
            self.debugTextBoxOut.text = "Error stopping: \(error.localizedDescription)"
        }

        btnMicToggle.setTitle("Start Mic", for: .normal)
        //shareRecordedAudio() // temp test
    }

    func m_toggle_MicVoIP() {
        AVAudioSession.sharedInstance().requestRecordPermission { (granted) in

            DispatchQueue.main.async {
                if granted {
                    if (self.is_VoIP_active == false) {
                        self.is_VoIP_active = true

                        self.start_VoIPMic()
                    } else {
                        self.stop_VoIPMic()
                        self.is_VoIP_active = false
                    }
                } else {
                    self.showAlert("Microphone access denied!")
                }
            }
            
        }
    }
}

