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
    var sampleRate: Double = 48000.0 //44100.0
    var channelCount: AVAudioChannelCount = 1 // This probably means it's Mono
    //var audioCommonFormat: AVAudioCommonFormat = AVAudioCommonFormat.pcmFormatFloat32
    var qualityEnconder: AVAudioQuality = AVAudioQuality.high

    var polarPatternCfg: AVAudioSession.PolarPattern = AVAudioSession.PolarPattern.cardioid

    var bufferSize: AVAudioFrameCount = 1024
    var bUseCustomFormat: Bool = false // Whether to use a custom format for network voice

    func getForSettings() -> [String: Any] {
        return [
            AVFormatIDKey: formatIDKey,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderAudioQualityKey: qualityEnconder.rawValue
        ]
    }
    func getForFormat() -> AVAudioFormat? {
        return AVAudioFormat(
            standardFormatWithSampleRate: self.sampleRate,
            channels: self.channelCount
        )
    }
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




struct struct_NetworkVoice_ConfigurationData {
    // Order needs to stay the same
    let bUseCustomFormat: Bool
    let sampleRate: Double
    let bufferSize: UInt32
}


var G_cfg_b_NetworkMode = CF_NetworkProtocols.TCP // TCP by default
var G_cfg_b_useNW = false // CFSocket by default


/***
    =================================
    So there's a couple of ways.
    A cool way is if Laptop/PC can directly go to the IP-Address of the Phone
    to ask it if it can connect.

    But the other way around is also possible.
    =================================

    The next part in what format to send data as.
    And then there's also the protocol, e.g. TCP and UDP.
***/
protocol NetworkVoiceDelegate: AnyObject {
    func handleAcceptedConnection(_ connection: NWConnection)
    func handleAcceptedCFSocket(_ client_cfSocket: CFSocket, _ addressData: CFData)

    func handleReceivedConfiguration(_ data: Data)
}

class NetworkVoiceTCPServer : TCPServer {
    var activeConnection: NWConnection? = nil // Active Connection
    
    weak var delegate: NetworkVoiceDelegate?


    override func handleListenerNewConnection(_ newConnection: NWConnection) {
        if (activeConnection != nil) {
            // Only allow one accepted connection.
            return
        }

        // Call original one now
        super.handleListenerNewConnection(newConnection)


        // Custom Handshake
        self.m_customHandshake(newConnection)
    }

    override func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            self.connectionStateHandler(connection: connection, state: state)
        }

        connection.start(queue: .main)
    }

    // Handshake
    private func m_customHandshake(_ incomingConnection: NWConnection) {
        let handshakeTimeout: TimeInterval = 10.0

        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: handshakeTimeout, repeats: false) { [weak self] _ in
            // Cancel on timeout
            self?.cancelConnection(incomingConnection)

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
                // Wait for configuration
                incomingConnection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] dataQ, context, isComplete, error in
                    timeoutTimer.invalidate() // Erase the timeout

                    // Setup data
                    guard let data = dataQ else { return }
                    self?.delegate?.handleReceivedConfiguration(data)


                    // We are alright!
                    // Let's tell that back
                    // Just note that... seeing how this works
                    // Perhaps whatever you try to connect, whether this is a safe way
                    // To check that it's the actual app is another question

                    guard let response = ("Accepted").data(using: .utf8) else { return }

                    incomingConnection.send(
                        content: response,
                        completion: .contentProcessed({ error in 
                            if let error = error {
                                DispatchQueue.main.async {
                                    G_UI_debugTextBoxOut.text = "Error Sending Handshake Back"
                                        + "\n\n"
                                        + G_UI_debugTextBoxOut.text
                                }
                                
                                self?.cancelConnection(incomingConnection) // Ensure
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
    }


    // Alright, we real
    func m_acceptIncomingConnection(_ connection: NWConnection) {
        activeConnection = connection;

        G_UI_Class_connectionLabel.setStatusConnectionText("Connection established with \(connection.endpoint)")

        // Debug test
        G_UI_debugTextBoxOut.text = "Connection:\n"
            + Utils_NWDump.getStringDump_forNWProtocolOptions(connection.parameters.defaultProtocolStack.transportProtocol)
            + "\n\n"
            + G_UI_debugTextBoxOut.text

        // We can now do the streaming thing
        // Trigger this
        self.delegate?.handleAcceptedConnection(connection)
    }


    override func connectionStateHandler(connection: NWConnection, state: NWConnection.State) {
        switch state {
        case .ready:
            // If this part reaches
            // It means that we should verify whether we really want to connect or not.
            G_UI_Class_connectionLabel.setStatusConnectionText("Incoming request from  \(connection.endpoint)")
        case .failed(let error):
            G_UI_Class_connectionLabel.setStatusConnectionText("Connection failed: \(error.localizedDescription)")
            self.cancelConnection(connection) // Ensure
        case .cancelled:
            G_UI_Class_connectionLabel.setStatusConnectionText("Connection cancelled with \(connection.endpoint)")
            self.cancelConnection(connection) // Ensure

        case .waiting(let error):
            G_UI_Class_connectionLabel.setStatusConnectionText("Connection waiting: \(error.localizedDescription)")
        case .preparing:
            G_UI_Class_connectionLabel.setStatusConnectionText("Connection preparing")
        case .setup:
            G_UI_Class_connectionLabel.setStatusConnectionText("Connection setup")

        default:
            break
        }
    }

    override func OnListenerStateUpdated(listener: NWListener, state: NWListener.State) {
        switch state {
        case .ready:
            G_UI_Class_connectionLabel.setStatusConnectionText("Server started, Port \(self.port.rawValue)")
        case .failed(let nwError):
            G_UI_Class_connectionLabel.setStatusConnectionText("Listener failed: \(nwError)")
        case .cancelled:
            G_UI_debugTextBoxOut.text = "!! Listener cancelled !!\n\n" + G_UI_debugTextBoxOut.text
        case .waiting:
            G_UI_Class_connectionLabel.setStatusConnectionText("Listener waiting state")
        case .setup:
            G_UI_Class_connectionLabel.setStatusConnectionText("Listener setup state")
        default:
            break
        }
    }

    override func OnListenerStopped() {
        G_UI_Class_connectionLabel.setStatusConnectionText("Server stopped")
    }


    func m_cleanUp() {
        self.activeConnection = nil
    }

    // Start Server
    override func startServer() throws {
        if (G_cfg_b_NetworkMode == CF_NetworkProtocols.UDP) {
            // UDP
            self.cfg_nwParameters = NWParameters.udp

            G_UI_Class_connectionLabel.setStatusConnectionText("Starting UDP Server...")
        } else {
            // TCP
            G_UI_Class_connectionLabel.setStatusConnectionText("Starting TCP Server...")
        }

        // Force this on both
        self.cfg_nwParameters.allowLocalEndpointReuse = true // SO_REUSEADDR?
        self.cfg_nwParameters.includePeerToPeer = true
        self.cfg_nwParameters.acceptLocalOnly = true

        do {
            try super.startServer()

            // The log that the server started is located at the listener state update function.
        } catch {
            G_UI_Class_connectionLabel.setStatusConnectionText("Error when trying to start: \(error.localizedDescription)")
        }

        G_UI_debugTextBoxOut.text = self.getDump_nwParams()
            + "\n" + self.getDump_nwListener()
    }

    override func stopServer() {
        G_UI_Class_connectionLabel.setStatusConnectionText("Stopping server...")

        for connection in self.connectionsArray {
            self.cancelConnection(connection) // This closes the connection
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            super.stopServer() // should remove all connections as well

            self.m_cleanUp()
        }
    }
}


// CFSocket method
class NetworkVoice_CF_NetworkServer : CF_NetworkServer {
    var activeClient_CFSocket: CFSocket?

    weak var delegate: NetworkVoiceDelegate?

    override func OnServerStateChanged(_ state: CF_ServerStates) {
        let protocolStr = self.GetCurrentProtocolAsString()

        switch state {
            case .started:
                G_UI_Class_connectionLabel.setStatusConnectionText("\(protocolStr) Server started, Port \(self.portNumber)")
            case .stopped:
                G_UI_Class_connectionLabel.setStatusConnectionText("\(protocolStr) Server stopped")
            default:
                break
        }
    }


    // Manually called when the Client State changes, e.g. disconnection
    override func OnClientStateChanged(_ client_cfSocket: CFSocket, _ state: CF_ClientStates) {
        switch state {
            case .disconnected:
                let nativeHandle = CFSocketGetNative(client_cfSocket)

                var isOurActive = false
                if (client_cfSocket == activeClient_CFSocket) {
                    isOurActive = true
                    activeClient_CFSocket = nil
                }

                G_UI_Class_connectionLabel.setStatusConnectionText("Client Disconnected, \(nativeHandle), \(isOurActive)")

                // Ensure
                // I think might only happen if TCP
                self.close_CFSocket(client_cfSocket, nil)
            default:
                break
        }
    }


    override func ShouldAcceptClientCFSocket(_ client_cfSocket: CFSocket) -> Bool {
        // Do this for now
        if (self.ServerConfig.networkProtocol == CF_NetworkProtocols.UDP) {
            return true
        }

        // If we already have a thing, don't accept
        if (activeClient_CFSocket != nil) {
            return false
        }

        return true
    }


    private func m_customHandshake(_ incomingCFSocket: CFSocket, _ addressData: CFData) {
        let handshakeTimeout: TimeInterval = 10.0

        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: handshakeTimeout, repeats: false) { [weak self] _ in
            // Cancel on timeout
            self?.close_CFSocket(incomingCFSocket, addressData)

            DispatchQueue.main.async {
                G_UI_Class_connectionLabel.setStatusConnectionText("Handshake Timeout")
            }
        }

        
        let client_NativeCFSocket = CFSocketGetNative(incomingCFSocket) // Int32

        /***
            IMPORTANT
        ***/
        // We need to receive this
        // And the incoming request has to send this
        let expectedWord = ("iOS_Mic_Test").data(using: .utf8)

        var buffer = [UInt8](repeating: 0, count: 512)
        var receivedDataQ: Data? = nil


        // Receive data either for TCP or UDP
        receivedDataQ = self.receiveData(&buffer, addressData: addressData, client_NativeCFSocket)

        if let receivedData = receivedDataQ {
            G_UI_Class_connectionLabel.setStatusConnectionText("Received something...")
            
            if (receivedData == expectedWord) {
                G_UI_Class_connectionLabel.setStatusConnectionText("Received expected string...")
                timeoutTimer.invalidate() // Erase the timeout
                

                buffer = [UInt8](repeating: 0, count: 1024)
                var recv_cfgDataQ: Data? = nil
                recv_cfgDataQ = self.receiveData(&buffer, addressData: addressData, client_NativeCFSocket)

                guard let recv_cfgData = recv_cfgDataQ else { return }
                self.delegate?.handleReceivedConfiguration(recv_cfgData)


                guard let response = ("Accepted").data(using: .utf8) else { return }
                
                // Something so it works with TCP and UDP as well
                //let sendResult = CFSocketSendData(incomingCFSocket, nil, response as CFData, 0)
                let sendResult = self.SendCFData(response as CFData, addressData: addressData, toCFSocket: incomingCFSocket)
                
                if (sendResult != .success) {
                    G_UI_debugTextBoxOut.text = "Error Sending Handshake Back"
                        + "\n\n"
                        + G_UI_debugTextBoxOut.text

                    self.close_CFSocket(incomingCFSocket, addressData)
                } else {
                    G_UI_Class_connectionLabel.setStatusConnectionText(
                        "Response sent to \(CF_SocketNetworkUtils.GetIP_FromNativeSocket(client_NativeCFSocket, b_includePort: true))"
                    )

                    // Accept after send

                    // We can now do the streaming thing
                    // Trigger this
                    self.delegate?.handleAcceptedCFSocket(incomingCFSocket, addressData)
                }
            }
        }

    }

    // Whenever we accept a new client connection
    override func OnClientConnectionAccepted(
        client_cfSocket: CFSocket,
        addressQ: CFData?
    ) {
        guard let address = addressQ else { return }


        let client_NativeCFSocket = CFSocketGetNative(client_cfSocket) // Int32
        //let ipStr = CF_SocketNetworkUtils.GetIP_FromNativeSocket(client_NativeCFSocket, b_includePort: true)
        let ipStr = CF_SocketNetworkUtils.GetIP_FromCFDataAddress(address, b_includePort: true)

        G_UI_Class_connectionLabel.setStatusConnectionText("Accepted connection with \(ipStr)")

        G_UI_debugTextBoxOut.text = "Accepted connection with \(ipStr), \(client_NativeCFSocket)"
            + "\n\n"
            + G_UI_debugTextBoxOut.text



        // Set active connection
        self.activeClient_CFSocket = client_cfSocket

        // Handshake
        DispatchQueue.main.async {
            self.m_customHandshake(client_cfSocket, address)
        }
    }


    private func m_cleanUp() {
        self.activeClient_CFSocket = nil
    }

    override func TemporaryLogging(_ str: String) {
        G_UI_Class_connectionLabel.setStatusConnectionText(str)
        /*DispatchQueue.main.async {
            G_UI_debugTextBoxOut.text = str + "\n" + G_UI_debugTextBoxOut.text
        }*/
    }

    override func startServer() {
        // We set the protocol now
        self.ServerConfig.networkProtocol = G_cfg_b_NetworkMode

        if (G_cfg_b_NetworkMode == CF_NetworkProtocols.UDP) {
            // UDP
            G_UI_Class_connectionLabel.setStatusConnectionText("Starting UDP Server...")
        } else {
            // TCP
            G_UI_Class_connectionLabel.setStatusConnectionText("Starting TCP Server...")
        }

        // Set this on both
        self.ServerConfig.allowLocalOnly = true

        do {
            try super.startServer()
        } catch {
            G_UI_Class_connectionLabel.setStatusConnectionText("Error when trying to start: \(error.localizedDescription)")
        }

        G_UI_debugTextBoxOut.text = ""
    }


    override func stopServer() {
        G_UI_Class_connectionLabel.setStatusConnectionText("Stopping CF server...")

        super.stopServer()

        m_cleanUp()
    }
}



// Network Voice Manager
class NetworkVoiceManager: NetworkVoiceDelegate {
    var networkVoice_TCPServer: NetworkVoiceTCPServer!
    var networkVoice_CF_TCPServer: NetworkVoice_CF_NetworkServer!

    var DEFAULT_TCP_PORT = 8125

    var audioManager: AudioManager!
    var audioEngineManager: AudioEngineManager!

    let networkVoiceQueue = DispatchQueue(label: "networkVoiceQueue")


    init(withAudioEngineManager: AudioEngineManager, withAudioManager: AudioManager) {
        self.audioManager = withAudioManager
        self.audioEngineManager = withAudioEngineManager

        self.networkVoice_TCPServer = NetworkVoiceTCPServer(inputPort: UInt16(DEFAULT_TCP_PORT))

        // Used for event when we actually got a real connection going
        self.networkVoice_TCPServer.delegate = self

        // Testing CF Network
        self.networkVoice_CF_TCPServer = NetworkVoice_CF_NetworkServer(inputPort: Int32(DEFAULT_TCP_PORT))

        self.networkVoice_CF_TCPServer.delegate = self
    }


    func getAudioConnectionDebugText(
        input_audioFormat: AVAudioFormat,
        audioSettings: AudioSettingsClass
    ) -> String {
        let streamDescription = input_audioFormat.streamDescription.pointee

        var debugText = ""
        debugText += "Sample Rate: \(input_audioFormat.sampleRate) Hz\n"
        debugText += "Channels: \(input_audioFormat.channelCount)\n"
        debugText += "Bit Depth: \(streamDescription.mBitsPerChannel)\n"
        debugText += "Format ID: \(streamDescription.mFormatID)\n"
        debugText += "\n"
        debugText += "Buffer Size: \(audioSettings.bufferSize)\n"

        return debugText
    }


    func m_getAudioFormatForInputNode(
        _ inputNode: AVAudioInputNode,
        audioSettings: AudioSettingsClass
    ) -> AVAudioFormat {
        let input_audioFormat = inputNode.inputFormat(forBus: 0)
        var audioFormat = input_audioFormat

        // TODO: Test
        if (audioSettings.bUseCustomFormat == true) {
            if var retrievedFormat = audioSettings.getForFormat() {
                audioFormat = retrievedFormat
            }
        }

        return audioFormat
    }


    // For CF
    func handleAcceptedCFSocket(_ client_cfSocket: CFSocket, _ addressData: CFData) {
        guard let audioEngine = self.audioEngineManager.audioEngine else { return }
        guard let audioSettings = self.audioEngineManager.audioSettings else { return }

        guard let inputNode = self.audioEngineManager.inputNode else { return }

        G_UI_Class_connectionLabel.setStatusConnectionText("Prepare streaming...")


        var audioFormat = m_getAudioFormatForInputNode(inputNode, audioSettings: audioSettings)
        inputNode.installTap(
            onBus: 0, bufferSize: audioSettings.bufferSize, format: audioFormat
        ) { (buffer, time) in
            // Transmit
            self.transmitAudioCF(buffer: buffer, client_cfSocket, addressData)
        }


        var debugText = self.getAudioConnectionDebugText(
            input_audioFormat: audioFormat,
            audioSettings: audioSettings
        )
        G_UI_debugTextBoxOut.text = debugText
            + "\n\n" + G_UI_debugTextBoxOut.text


        // Prepare
        audioEngine.prepare()


        do {
            try audioEngine.start()
            
            DispatchQueue.main.async {
                G_UI_Class_connectionLabel.setStatusConnectionText(
                    //"Streaming for \(CF_SocketNetworkUtils.GetIP_FromCFSocket(client_cfSocket, b_includePort: true))"
                    "Streaming for \(CF_SocketNetworkUtils.GetIP_FromCFDataAddress(addressData, b_includePort: true))"
                )
            }
        } catch {
            DispatchQueue.main.async {
                G_UI_Class_connectionLabel.setStatusConnectionText("AudioEngine Error: \(error.localizedDescription)")
            }
        }
    }


    func transmitAudioCF(buffer: AVAudioPCMBuffer, _ client_cfSocket: CFSocket, _ addressData: CFData) {
        let audioData = buffer.audioBufferList.pointee.mBuffers
        let dataSize = audioData.mDataByteSize
        
        // Check if data is available
        guard let dataPointer = audioData.mData else {
            DispatchQueue.main.async {
                G_UI_debugTextBoxOut.text = "Problem"
                    + "\n\n" + G_UI_debugTextBoxOut.text
            }
            return
        }

        // Data
        let audioBytes = Data(bytes: dataPointer, count: Int(dataSize))
        let cfData = CFDataCreate(kCFAllocatorDefault, audioBytes.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }, audioBytes.count)
        
        guard let cfDataToSend = cfData else {
            DispatchQueue.main.async {
                G_UI_debugTextBoxOut.text = "Problem 2"
                    + "\n\n" + G_UI_debugTextBoxOut.text   
            }
            return
        }

        // Send audio data
        //let sendResult = CFSocketSendData(client_cfSocket, nil, cfDataToSend, 0)
        let sendResult = self.networkVoice_CF_TCPServer.SendCFData(cfDataToSend, addressData: addressData, toCFSocket: client_cfSocket)

        if (sendResult != .success) {
            DispatchQueue.main.async {
                G_UI_debugTextBoxOut.text = "Error sending data"
                    + "\n\(addressData)"
                    + "\n\n" + G_UI_debugTextBoxOut.text
            }
        }
    }





    // When we have connection we can start streaming
    // This will make us start streaming
    func handleAcceptedConnection(_ connection: NWConnection) {
        guard let audioEngine = self.audioEngineManager.audioEngine else { return }
        guard let audioSettings = self.audioEngineManager.audioSettings else { return }

        guard let inputNode = self.audioEngineManager.inputNode else { return } // If there are issues, change this as well

        G_UI_Class_connectionLabel.setStatusConnectionText("Prepare streaming...")

        let input_audioFormat = inputNode.inputFormat(forBus: 0)
        //var audioFormat = m_getAudioFormatForInputNode(inputNode, audioSettings: audioSettings)
        var audioFormat = input_audioFormat
        inputNode.installTap(
            onBus: 0, bufferSize: audioSettings.bufferSize, format: audioFormat
        ) { (buffer, time) in
            // Transmit
            //self.networkVoiceQueue.async {
                self.transmitAudio(buffer: buffer, connection)
            //}
        }


        var debugText = self.getAudioConnectionDebugText(
            input_audioFormat: audioFormat,
            audioSettings: audioSettings
        )
        G_UI_debugTextBoxOut.text = debugText
            + "\n\n" + G_UI_debugTextBoxOut.text


        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            
            DispatchQueue.main.async {
                G_UI_Class_connectionLabel.setStatusConnectionText("Streaming for \(connection.endpoint)")
            }
        } catch {
            DispatchQueue.main.async {
                G_UI_Class_connectionLabel.setStatusConnectionText("AudioEngine Error: \(error.localizedDescription)")
            }
        }
    }

    func transmitAudio(buffer: AVAudioPCMBuffer, _ connection: NWConnection) {
        let audioData = buffer.audioBufferList.pointee.mBuffers
        let dataSize = audioData.mDataByteSize
        
        // Check if data is available
        guard let dataPointer = audioData.mData else {
            DispatchQueue.main.async {
                G_UI_debugTextBoxOut.text = "Problem"
                    + "\n\n" + G_UI_debugTextBoxOut.text
            }
            return
        }

        // Data
        let audioBytes = Data(bytes: dataPointer, count: Int(dataSize))
        
        // Send audio data
        connection.send(
            content: audioBytes,
            completion: .contentProcessed({ error in
            
                DispatchQueue.main.async {
                    if let error = error {
                        G_UI_debugTextBoxOut.text = "Error sending audio data: \(error)"
                            + "\n\n" + G_UI_debugTextBoxOut.text
                        
                        // Try to disconnect, if that's the case
                        if (connection.state == .cancelled) {
                            do {
                                try self.audioManager.stop_VoIP()
                            } catch {
                                G_UI_debugTextBoxOut.text = "Error: \(error)"
                                    + "\n\n" + G_UI_debugTextBoxOut.text
                            }

                            G_UI_debugTextBoxOut.text = "Force Stopped Network Voice"
                                + "\n\n" + G_UI_debugTextBoxOut.text
                        }
                    }
                }

            })
        )
    }


    func tryToStartAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
        } catch {
            DispatchQueue.main.async {
                G_UI_debugTextBoxOut.text = "Error Starting: \(error)"
                    + "\n\n" + G_UI_debugTextBoxOut.text
            }
        }
    }


    // For Voice Config
    func handleReceivedConfiguration(_ data: Data) {
        var receivedConfigDataQ: struct_NetworkVoice_ConfigurationData? = nil

        data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
            guard let baseAddress = pointer.baseAddress else {
                DispatchQueue.main.async {
                    G_UI_debugTextBoxOut.text = "baseAddress is nil"
                        + "\n\n" + G_UI_debugTextBoxOut.text
                }
                return
            }
            let typedPointer  = baseAddress.assumingMemoryBound(to: struct_NetworkVoice_ConfigurationData.self)
            let value = typedPointer.pointee // Read in one go?
            
            receivedConfigDataQ = value
        }


        guard let receivedConfigData = receivedConfigDataQ else {
            DispatchQueue.main.async {
                G_UI_debugTextBoxOut.text = "Error with config: \(receivedConfigDataQ)"
                    + "\n\n" + G_UI_debugTextBoxOut.text
            }
            return
        }

        DispatchQueue.main.async {
            G_UI_debugTextBoxOut.text = "Received config \(receivedConfigData)"
                + "\n\n" + G_UI_debugTextBoxOut.text

            G_UI_debugTextBoxOut.text = "App Restart may be required to reset config when not using VoIP"
                + "\n\n" + G_UI_debugTextBoxOut.text
        }

        

        // Don't modify anything if not true
        if (receivedConfigData.bUseCustomFormat == false) {
            DispatchQueue.main.async {
                G_UI_debugTextBoxOut.text = "Use pre-defined audio config"
                    + "\n\n" + G_UI_debugTextBoxOut.text
            }
            return
        }


        /***
            Configure Audio things
        ***/
        let session = AVAudioSession.sharedInstance()

        guard var audioSettings = self.audioEngineManager.audioSettings else { return }

        // Change Values
        audioSettings.bUseCustomFormat = receivedConfigData.bUseCustomFormat // Set this

        audioSettings.sampleRate = receivedConfigData.sampleRate
        audioSettings.bufferSize = receivedConfigData.bufferSize

        // The inputNode needs to have its format changed in some other way
    
        // Change Hz
        do {
            try session.setPreferredSampleRate(audioSettings.sampleRate)
        } catch {
            DispatchQueue.main.async {
                G_UI_debugTextBoxOut.text = "Error Configuring: \(error)"
                    + "\n\n" + G_UI_debugTextBoxOut.text
            }
        }
    }



    // It just switches
    func changeNetworkProtocol() {
        if (G_cfg_b_NetworkMode == CF_NetworkProtocols.TCP) {
            // If it's TCP, set it to UDP.
            G_cfg_b_NetworkMode = CF_NetworkProtocols.UDP
        } else {
            G_cfg_b_NetworkMode = CF_NetworkProtocols.TCP
        }
    }



    func start() throws {
        do {
            if (G_cfg_b_useNW == true) {
                // NWListener
                try self.networkVoice_TCPServer.startServer()
            } else {
                // CFSocket
                try self.networkVoice_CF_TCPServer.startServer()
            }
            
            // Debug
            G_UI_debugTextBoxOut.text = "\(self)"
                + "\n\n" + G_UI_debugTextBoxOut.text
                + "\n\n" + "\(self.audioEngineManager.audioEngine)"
                + "\n\n" + "\(self.audioEngineManager.audioSettings)"
                + "\n\n" + "\(self.audioEngineManager.audioEngine.inputNode)"
                + "\n\n" + "\(self.audioEngineManager.audioEngine.outputNode)"
                + "\n\n" + G_UI_debugTextBoxOut.text

        } catch {
            throw error
        }
    }

    func stop() {
        // Do this I guess?
        if (G_cfg_b_useNW == true) {
            // NWListener
            self.networkVoice_TCPServer.stopServer()
        } else {
            // CFSocket
            self.networkVoice_CF_TCPServer.stopServer()
        }
    }
}


// Example usage from a copy of an Apple Example
// https://github.com/winstondu/Voice-Processing-Demo/blob/master/AVEchoTouch/ViewController.swift
class AudioEngineManager {
    var audioEngine: AVAudioEngine!
    var inputNode: AVAudioInputNode!

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
    }


    // For Testing
    func startRecordingEngine() throws {
        // Create a file URL to save the audio
        let audioFilename = GetDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        do {
            // Create the audio file
            self.audioFile = try AVAudioFile(forWriting: audioFilename, settings: audioSettings.getForSettings())

            let input_audioFormat = inputNode.inputFormat(forBus: 0)

            // Install a tap on the input node
            inputNode.installTap(
                onBus: 0, bufferSize: self.audioSettings.bufferSize, format: input_audioFormat
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


// Audio Manager
class AudioManager {
    var audioRecorder: AVAudioRecorder?
    var audioSettings = AudioSettingsClass()

    var audioEngineManager: AudioEngineManager!
    var networkVoiceManager: NetworkVoiceManager!

    // Init function
    init() {
        self.audioEngineManager = AudioEngineManager(withAudioSettings: audioSettings)
        self.networkVoiceManager = NetworkVoiceManager(withAudioEngineManager: self.audioEngineManager, withAudioManager: self)
    }


    func setupRecordingAudioSession() throws {
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
            try setupRecordingAudioSession()
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
            // Removing this prevents a direct crash for some reason
            // But it wouldn't allow mixing
            try session.setCategory(.multiRoute, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            
            try session.setActive(true)
        } catch {
            throw error
        }
    }


    func start_VoIP_Server() throws {

    }
    func stop_VoIP_Server() throws {

    }

    func start_VoIP() throws {
        do {
            // Call this because .stop() used with .prepare() may be removing
            // some allocated nodes that we need to ensure
            // exist
            self.audioEngineManager.setupInit()

            // Calling this requires setupInit to be called again when stopped
            // Hence why the start function has setupInit again
            //audioEngineManager.audioEngine.prepare()

            try self.setup_AudioSessionForVoIP()

            try self.networkVoiceManager.start()
            // audioEngine prepare and start function appears somewhere else for network


            //try audioEngineManager.startRecordingEngine()
        } catch {
            throw error
        }
    }

    func stop_VoIP() throws {
        do {
            //audioEngineManager.stopRecordingEngine()

            //self.networkVoiceManager.stop()

            self.audioEngineManager.audioEngine.inputNode.removeTap(onBus: 0)
            if (self.audioEngineManager.audioEngine.isRunning) {
                self.audioEngineManager.audioEngine.stop()

                self.audioEngineManager.audioEngine.reset()
            }

            // Stop after stopping audioEngine
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.networkVoiceManager.stop()
            
                do {
                    // The order on when this gets called seems to be important
                    try AVAudioSession.sharedInstance().setActive(false)
                } catch {
                    G_UI_debugTextBoxOut.text = "setActive Error: \(error)"
                        + "\n\n" + G_UI_debugTextBoxOut.text
                }
            }

            /*self.networkVoiceManager.stop()
    
            try AVAudioSession.sharedInstance().setActive(false)*/
        } catch {
            throw error
        }
    }
}


// Collection of some Strings
struct STR_TBL {
    static let BTN_START_TEST_RECORD = "Record Test"
    static let BTN_STOP_RECORDING = "Stop Recording"

    static let BTN_TCP_MODE = "Using TCP"
    static let BTN_UDP_MODE = "Using UDP"

    static let BTN_USE_NW = "Using NW"
    static let BTN_USE_CFSOCKET = "Using CFSocket"

    static let NOT_AVAILABLE_ABBR = "N/A"
    static let STATUS = "Status"
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
        ui_connectionLabel.text = STR_TBL.STATUS // Status
        ui_connectionLabel.font = UIFont.systemFont(ofSize: 18)
        ui_connectionLabel.textAlignment = .center
        ui_connectionLabel.numberOfLines = 0  // Allow multiple lines
        ui_connectionLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    // Update Connection Label
    func updateStatusConnectionLabel() {
        ui_connectionLabel.text = "\(STR_TBL.STATUS): \(self.statusInfoStruct.connectionStatusText)" + "\n" +
            "Local IP: \(self.statusInfoStruct.localIP)" + "\n"

        // Change Label size to fit content.
        ui_connectionLabel.sizeToFit()
    }

    func updateLocalIPStatusText() {
        if let localIP = GetLocalIPAddress() {
            self.statusInfoStruct.localIP = localIP
        } else {
            self.statusInfoStruct.localIP = STR_TBL.NOT_AVAILABLE_ABBR // N/A
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

//var G_UI_Class_debugLogging = nil
var G_UI_debugTextBoxOut = UITextView()


class ViewController: UIViewController {
    var tableView: UITableView!
    var debugTextBoxOut = G_UI_debugTextBoxOut

    var btnNetworkFrameworkToggle: UIButton!
    var btnProtocolToggle: UIButton!
    var btnRecordTestToggle: UIButton!
    var btnMicToggle: UIButton!
    

    var UI_Class_connectionLabel = UI_NetworkStatus_SingletonClass.shared()
    var ui_connectionLabel: UILabel!

    var polarPatternTableView: CombinedSettingsTableView!

    let audioManager = AudioManager() // Handles everything related to Audio Operations
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


        // Network Toggle
        btnNetworkFrameworkToggle = UIButton(type: .system)
        self.updateNetworkFrameworkToggleButton()
        btnNetworkFrameworkToggle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btnNetworkFrameworkToggle)

        // Protocol Toggle
        btnProtocolToggle = UIButton(type: .system)
        btnProtocolToggle.setTitle( STR_TBL.BTN_TCP_MODE, for: .normal )
        btnProtocolToggle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btnProtocolToggle)


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


            // Protocol Button
            btnProtocolToggle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            btnProtocolToggle.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -85),
            btnProtocolToggle.widthAnchor.constraint(equalToConstant: 150),
            btnProtocolToggle.heightAnchor.constraint(equalToConstant: 50),

            // Network Framework Button
            btnNetworkFrameworkToggle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            btnNetworkFrameworkToggle.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -155),
            btnNetworkFrameworkToggle.widthAnchor.constraint(equalToConstant: 150),
            btnNetworkFrameworkToggle.heightAnchor.constraint(equalToConstant: 50),
        ])

        // Add action to the button
        btnRecordTestToggle.addTarget(self, action: #selector(action_recordTestToggleClicked), for: .touchUpInside)
        btnMicToggle.addTarget(self, action: #selector(action_micToggleClicked), for: .touchUpInside)
        btnProtocolToggle.addTarget(self, action: #selector(action_protocolToggleClicked), for: .touchUpInside)
        btnNetworkFrameworkToggle.addTarget(self, action: #selector(action_networkFrameworkToggleClicked), for: .touchUpInside)


        // Create UITextView without setting a frame
        //debugTextBoxOut = UITextView()
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
    @IBAction func action_protocolToggleClicked(_ sender: UIButton) {
        self.m_toggle_NetworkProtocol()
    }
    @IBAction func action_networkFrameworkToggleClicked(_ sender: UIButton) {
        if (G_cfg_b_useNW == true) {
            G_cfg_b_useNW = false // CF
        } else {
            G_cfg_b_useNW = true // NW
        }
        updateNetworkFrameworkToggleButton() // Update
    }

    func updateNetworkFrameworkToggleButton() {
        if (G_cfg_b_useNW == true) {
            btnNetworkFrameworkToggle.setTitle(STR_TBL.BTN_USE_NW, for: .normal) // NW
        } else {
            btnNetworkFrameworkToggle.setTitle(STR_TBL.BTN_USE_CFSOCKET, for: .normal) // CF
        }
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

    func m_toggle_NetworkProtocol() {
        self.audioManager.networkVoiceManager.changeNetworkProtocol()

        switch G_cfg_b_NetworkMode {
            case CF_NetworkProtocols.TCP:
                btnProtocolToggle.setTitle(STR_TBL.BTN_TCP_MODE, for: .normal)
            case CF_NetworkProtocols.UDP:
                btnProtocolToggle.setTitle(STR_TBL.BTN_UDP_MODE, for: .normal)
            default:
                break
        }
    }


    // VoIP
    func start_VoIPMic() {
        do {
            try self.audioManager.start_VoIP()
        } catch {
            // Handle Error
            DispatchQueue.main.async {
                self.debugTextBoxOut.text = "Error starting: \(error.localizedDescription)"
                    + "\n\n" + self.debugTextBoxOut.text
            }
        }

        btnMicToggle.setTitle("Stop Mic", for: .normal)
    }
    func stop_VoIPMic() {
        do {
            try self.audioManager.stop_VoIP()
        } catch {
            DispatchQueue.main.async {
                self.debugTextBoxOut.text = "Error stopping: \(error.localizedDescription)"
            }
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

