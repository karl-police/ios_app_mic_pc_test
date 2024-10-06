import Foundation
import CoreFoundation

class CF_TCPServer {
    var serverSocket: CFSocket?

    var portNumber = 0;

    init(inputPort: Int) {
        // Set Port number
        self.portNumber = inputPort;
    }



    func serverCallback(
        socket: CFSocket?,
        callbackType: CFSocketCallBackType,
        address: CFData?,
        data: UnsafeRawPointer?,
        info: UnsafeMutableRawPointer?
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
            CFSocketCallBackType.acceptCallBack.rawValue,
            serverCallback,
            nil
        )

        // Bind socket to port
        var sin = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: in_port_t(self.portNumber).bigEndian, // Port
            sin_addr: in_addr(s_addr: INADDR_ANY.bigEndian),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let address = withUnsafePointer(to: &sin) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<sockaddr_in>.size) {
                CFDataCreate(kCFAllocatorDefault, $0, MemoryLayout<sockaddr_in>.size)
            }
        }

        // Make socket reuseable
        var yes: Int32 = 1
        setsockopt(CFSocketGetNative(socket!), SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Bind to socket
        let result = CFSocketSetAddress(socket, address)
        if result != .success {
            print("Bind error")
            return
        }

        // Start listening for connections
        let source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, socket, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        self.OnServerStarted()
        CFRunLoopRun() // Keep server alive
    }
}