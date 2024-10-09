class NetworkVoiceTCPServer : TCPServer {
    var activeConnection: NWConnection? // Active Connection

    var m_onAcceptedConnectionEstablished: ((NWConnection) -> Void)?

    override func handleListenerNewConnection(_ newConnection: NWConnection) {
        if (activeConnection != nil) {
            // Only allow one accepted connection.
            return
        }

        // Call original one now
        super.handleListenerNewConnection(newConnection)
    }

    override func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            self?.connectionStateHandler(connection: connection, state: state)
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


    // Alright, we real
    func m_acceptIncomingConnection(_ connection: NWConnection) {
        activeConnection = connection;

        G_UI_Class_connectionLabel.setStatusConnectionText("Connection established with \(connection.endpoint)")

        // Debug test
        G_UI_debugTextBoxOut.text = "Connection:\n"
            + Utils_NWDump.getStringDump_forNWProtocolOptions(connection.parameters.defaultProtocolStack.transportProtocol)
            + "\n\n"
            + G_UI_debugTextBoxOut.text


        // Check
        guard let guard_m_onAcceptedConnectionEstablished = self.m_onAcceptedConnectionEstablished else {
            G_UI_Class_connectionLabel.setStatusConnectionText("Function is missing")
            return
        }
        // We can now do the streaming thing
        // Trigger this
        guard_m_onAcceptedConnectionEstablished(connection)
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
            //G_UI_Class_connectionLabel.setStatusConnectionText("Listener cancelled")
        case .waiting:
            G_UI_Class_connectionLabel.setStatusConnectionText("Listener waiting state")
        case .setup:
            G_UI_Class_connectionLabel.setStatusConnectionText("Listener setup state")
        default:
            break
        }
    }


    func m_cleanUp() {
        self.activeConnection = nil
    }

    // Start Server
    override func startServer() throws {
        if (G_cfg_b_DoUDP == true) {
            // UDP
            self.cfg_nwParameters = NWParameters.udp

            G_UI_Class_connectionLabel.setStatusConnectionText("Starting UDP Server...")
        } else {
            // TCP

            G_UI_Class_connectionLabel.setStatusConnectionText("Starting TCP Server...")
        }

        // Force this on both
        //self.cfg_nwParameters.allowLocalEndpointReuse = true // SO_REUSEADDR?
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

        super.stopServer() // should remove all connections as well

        m_cleanUp()
    }
}