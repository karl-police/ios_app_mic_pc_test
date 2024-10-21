import Network


// Store all connections into a global-like variable for AppDelegate to clear them?


struct Utils_NWDump {
    static func getStringDump_forNWProtocolOptions(_ OPT_NwProtocolOptions: NWProtocolOptions?) -> String {
        var debugText = ""

        guard let nwProtocolOptions = OPT_NwProtocolOptions else {
            debugText += "Protocol was not available."
            return debugText
        }

        if let options = nwProtocolOptions as? NWProtocolTCP.Options {
            debugText += "enableFastOpen: \(options.enableFastOpen)\n"
                    + "maximumSegmentSize: \(options.maximumSegmentSize)\n"
                    + "noDelay: \(options.noDelay)\n"
                    + "noOptions: \(options.noOptions)\n"
                    + "noPush: \(options.noPush)\n"
                    + "retransmitFinDrop: \(options.retransmitFinDrop)\n"
                    + "disableAckStretching: \(options.disableAckStretching)\n"
                    + "disableECN: \(options.disableECN)\n"
                    + "\n"
                    + "enableKeepalive: \(options.enableKeepalive)\n"
                    + "keepaliveIdle: \(options.keepaliveIdle)\n"
                    + "keepaliveCount: \(options.keepaliveCount)\n"
                    + "keepaliveInterval: \(options.keepaliveInterval)\n"
                    + "\n"
                    + "connectionTimeout: \(options.connectionTimeout)\n"
                    + "connectionDropTime: \(options.connectionDropTime)\n"
                    + "persistTimeout: \(options.persistTimeout)\n"

        } else if let options = nwProtocolOptions as? NWProtocolUDP.Options {
            debugText += "preferNoChecksum: \(options.preferNoChecksum)\n"

        } else if let options = nwProtocolOptions as? NWProtocolIP.Options {
            debugText += "version: \(options.version)\n"
                    + "shouldCalculateReceiveTime: \(options.shouldCalculateReceiveTime)\n"
                    + "hopLimit: \(options.hopLimit)\n"
                    + "useMinimumMTU: \(options.useMinimumMTU)\n"
                    + "disableFragmentation: \(options.disableFragmentation)\n"
                    + "disableMulticastLoopback: \(options.disableMulticastLoopback)\n"
                    + "localAddressPreference: \(options.localAddressPreference)\n"
        } else {
            debugText = "NOT HANDLED\n"
        }

        return debugText
    }
}



// A Class to Host a Server.
class TCPServer {
    var listener: NWListener? = nil
    private var connectionsArray: [NWConnection] = []

    var cfg_nwParameters = NWParameters.tcp

    // Different Type
    var port: NWEndpoint.Port!

    // Init
    init(inputPort: UInt16) {
        // Port Constructor takes UInt16
        self.port = NWEndpoint.Port(rawValue: inputPort)
    }
    

    // For new connections
    func handleListenerNewConnection(_ newConnection: NWConnection) {
        self.connectionsArray.append(newConnection)

        self.handleConnection(newConnection)
    }

    // Set a pre-defined empty handleConnection
    func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            self.connectionStateHandler(connection: connection, state: state)
        }

        connection.start(queue: .main)
    }

    func connectionStateHandler(connection: NWConnection, state: NWConnection.State) {
        switch state {
            case .ready:
                print("Connection established with \(connection.endpoint)")
            case .failed(let nwError):
                print("Connection failed: \(nwError)")
            case .cancelled:
                print("Connection cancelled with \(connection.endpoint)")
            default:
                break
        }
    }


    // Use this instead to close connections...
    func cancelConnection(_ connection: NWConnection) {
        if let index = self.connectionsArray.firstIndex(where: { $0 === connection }) {
            self.connectionsArray.remove(at: index)
        }

        connection.stateUpdateHandler = nil // remove stateUpdateHandler
        connection.cancel()
    }


    // Whenever the state updates
    func OnListenerStateUpdated(listener: NWListener, state: NWListener.State) {
        switch state {
        case .ready:
            print("Listener is ready")
        case .failed(let nwError):
            print("Listener failed: \(nwError)")
        case .cancelled:
            print("Listener cancelled")
        default:
            break
        }
    }

    func OnListenerStopped() {
        print("Listener stopped")
    }



    func getDump_nwParams() -> String {
        var debugText = ""

        guard let listener = self.listener else {
            debugText = "No Listener found."
            return debugText
        }

        // Current Parameters
        let nwParameters = listener.parameters

        debugText += "defaultProtocolStack: \(nwParameters.defaultProtocolStack)\n"
            + "\t \(nwParameters.defaultProtocolStack.transportProtocol)\n"
            + "\t \(nwParameters.defaultProtocolStack.internetProtocol)\n"

        debugText += "requiredInterfaceType: \(nwParameters.requiredInterfaceType)\n"
        debugText += "requiredInterface: \(nwParameters.requiredInterface)\n"
        debugText += "requiredLocalEndpoint: \(nwParameters.requiredLocalEndpoint)\n"
        debugText += "prohibitConstrainedPaths: \(nwParameters.prohibitConstrainedPaths)\n"
        debugText += "prohibitExpensivePaths: \(nwParameters.prohibitExpensivePaths)\n"
        debugText += "prohibitedInterfaceTypes: \(nwParameters.prohibitedInterfaceTypes)\n"
        debugText += "prohibitedInterfaces: \(nwParameters.prohibitedInterfaces)\n"
        debugText += "\n"

        debugText += "multipathServiceType: \(nwParameters.multipathServiceType)\n"
        debugText += "serviceClass: \(nwParameters.serviceClass)\n"
        debugText += "allowFastOpen: \(nwParameters.allowFastOpen)\n"
        debugText += "expiredDNSBehavior: \(nwParameters.expiredDNSBehavior)\n"
        debugText += "includePeerToPeer: \(nwParameters.includePeerToPeer)\n"
        debugText += "allowLocalEndpointReuse: \(nwParameters.allowLocalEndpointReuse)\n"
        debugText += "acceptLocalOnly: \(nwParameters.acceptLocalOnly)\n"
        debugText += "\ndebugDescription: \(nwParameters.debugDescription)\n"

        return debugText
    }


    func getDump_nwListener() -> String {
        var debugText = "Listener:\n"

        guard let listener = self.listener else {
            debugText = "No Listener found."
            return debugText
        }

        // Current Parameters
        let cur_nwParameters = listener.parameters

        debugText += "newConnectionLimit: \(listener.newConnectionLimit)\n"
        debugText += "\ndebugDescription: \(listener.debugDescription)"


        // e.g. TCP Options
        let transportProtocolOptions = cur_nwParameters.defaultProtocolStack.transportProtocol
        // NWProtocolIPOptions
        let internetProtocolOptions = cur_nwParameters.defaultProtocolStack.internetProtocol

        // NWProtocol
        debugText += "\n" + "Transport Options:\n"
        debugText += Utils_NWDump.getStringDump_forNWProtocolOptions(transportProtocolOptions)

        debugText += "\n" + "Internet Protocol:\n"
        debugText += Utils_NWDump.getStringDump_forNWProtocolOptions(internetProtocolOptions)

        return debugText
    }




    // This needs to be called to start the server
    func startServer() throws {
        do {
            self.listener = try NWListener(using: self.cfg_nwParameters, on: self.port)

            self.listener?.newConnectionHandler = { newConnection in 
                self.handleListenerNewConnection(newConnection)
            }

            self.listener?.stateUpdateHandler = { state in
                guard let listener = self.listener else {
                    //fatalError("There's no Listener") // if nil
                    return
                }

                self.OnListenerStateUpdated(listener: listener, state: state)
            }

            // Start listening
            self.listener?.start(queue: .main)
        } catch {
            throw error
        }
    }

    func stopServer() {
        for connection in self.connectionsArray {
            self.cancelConnection(connection) // This closes the connection
        }

        self.connectionsArray.removeAll() // Ensure removal of all

        if let listener = self.listener {
            listener.cancel()

            listener.stateUpdateHandler = nil
            listener.newConnectionHandler = nil
            self.listener = nil
        }

        self.OnListenerStopped()
    }
}