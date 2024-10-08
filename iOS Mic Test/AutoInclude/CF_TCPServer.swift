import Foundation
import CoreFoundation

class CF_TCPServer {
    var serverSocket: CFSocket?

    var portNumber: Int32 = 0;

    init(inputPort: Int32) {
        // Set Port number
        self.portNumber = inputPort;
    }



    private var context: CFSocketContext {
        var context = CFSocketContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        return context
    }

    var serverSocketCallback: CFSocketCallBack = { (_ socket, callbackType, _ address, dataPointer, infoPointer) in
        guard let socket = socket else { return }

        guard callbackType == .acceptCallBack, let infoPointer = infoPointer,
            let clientSocketHandle = dataPointer?.assumingMemoryBound(to: CFSocketNativeHandle.self).pointee else {
                return
        }

        let handle = CFSocketGetNative(socket)


        let referencedSelf = Unmanaged<CF_TCPServer>.fromOpaque(infoPointer).takeUnretainedValue()

        // If we allow the connection to get accepted
        referencedSelf.OnClientConnectionAccepted(handle: handle)
    }


    func OnServerStarted() {
        print("TCP server started on port \(self.portNumber)")
    }


    // When the Server accepted a Client Connection
    func OnClientConnectionAccepted(handle: CFSocketNativeHandle) {
        print("Accepted connection on socket \(handle)")

        close(handle)
    }


    func TemporaryLogging(_ str: String) {
        print(str)
    }

    func startServer() {
        var context = self.context

        serverSocket = CFSocketCreate(
            kCFAllocatorDefault,
            PF_INET,
            SOCK_STREAM,
            IPPROTO_TCP,
            CFSocketCallBackType.acceptCallBack.rawValue,
            serverSocketCallback as CFSocketCallBack, // conversion?
            &context
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
            //print("Bind error")
            return
        }

        // Listen for connections
        let source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, serverSocket, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        self.OnServerStarted()
        CFRunLoopRun() // Run server loop
    }


    func stopServer() {
        // If the socket exists
        if let serverSocket = self.serverSocket {
            CFSocketInvalidate(serverSocket)
            
            let nativeHandle = CFSocketGetNative(serverSocket)
            
            // Close socket
            close(nativeHandle)
            
            // Remove socket loop
            if let runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, serverSocket, 0) {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
            }
            
            self.serverSocket = nil

            self.TemporaryLogging("TCP Server stopped")
        } else {
            self.TemporaryLogging("Server socket doesn't exist")
        }
    }
}