import Foundation
import CoreFoundation

class CF_TCPServer {
    var serverSocket: CFSocket?

    var portNumber: Int32 = 0;

    init(inputPort: Int32) {
        // Set Port number
        self.portNumber = inputPort;
    }



    func serverCallback(
        _ socket: CFSocket?,
        _ callbackType: CFSocketCallBackType,
        _ address: CFData?,
        _ data: UnsafeRawPointer?,
        _ info: UnsafeMutableRawPointer?
    )
    {
        guard let socket = socket else { return }

        let handle = CFSocketGetNative(socket)



        // If we allow the connection to get accepted
        self.OnClientConnectionAccepted(handle: handle)
    }


    func OnServerStarted() {
        print("TCP server started on port \(self.portNumber)")
    }


    // When the Server accepted a Client Connection
    func OnClientConnectionAccepted(handle: CFSocketNativeHandle) {
        print("Accepted connection on socket \(handle)")

        close(handle)
    }


    func startServer() {
        serverSocket = CFSocketCreate(
            kCFAllocatorDefault,
            PF_INET,
            SOCK_STREAM,
            IPPROTO_TCP,
            CFSocketCallBackType.acceptCallBack.rawValue
            { (socket, callbackType, address, data, info) in
                self.serverCallback(socket, callbackType, address, data, info)
            },
            CF_TCPServer.serverCallback,
            nil
        )

        // Bind socket to port
        var addressStruct = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: in_port_t(self.portNumber).bigEndian, // Port
            sin_addr: in_addr(s_addr: INADDR_ANY.bigEndian),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let address = withUnsafePointer(to: &addressStruct) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<sockaddr_in>.size) {
                CFDataCreate(kCFAllocatorDefault, $0, MemoryLayout<sockaddr_in>.size)
            }
        }

        // Make socket reuseable
        var yes: Int32 = 1
        setsockopt(CFSocketGetNative(serverSocket!), SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Bind to socket
        let result = CFSocketSetAddress(serverSocket, address)
        if result != .success {
            print("Bind error")
            return
        }

        // Start listening for connections
        let source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, serverSocket, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        self.OnServerStarted()
        CFRunLoopRun() // Keep server alive
    }
}