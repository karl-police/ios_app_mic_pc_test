import Network


// Store all connections into a global-like variable for AppDelegate to clear them?



// A Class to Host a Server.
class TCPServer {
    var listener: NWListener?
    var connection: NWConnection?

    private var connectionsArray: [NWConnection] = []

    var cfg_nwParameters = NWParameters.tcp()

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
        connection.stateUpdateHandler = { [weak self] state in
            self?.connectionStateHandler(connection: connection, state: state)
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
            print("Connection cancelled")
        default:
            break
        }
    }


    // Use this instead to close connections...
    // ...
    func cancelConnection(_ connection: NWConnection) {
        if let index = self.connectionsArray.firstIndex(where: { $0 === connection }) {
            self.connectionsArray.remove(at: index)
        }
        connection.cancel()
    }



    // This needs to be called to start the server
    func startServer() throws {
        do {
            self.listener = try NWListener(using: self.cfg_nwParameters, on: self.port)

            listener?.newConnectionHandler = { newConnection in 
                self.handleListenerNewConnection(newConnection)
            }

            // Start listening
            listener?.start(queue: .main)
        } catch {
            throw error
        }
    }

    func stopServer() {
        for connection in self.connectionsArray {
            connection.cancel() // This closes the connection
        }

        self.connectionsArray.removeAll()

        self.listener?.cancel()

        //listener.stateUpdateHandler = nil
        //listener.newConnectionHandler = nil
        self.listener = nil
    }
}