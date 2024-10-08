import Foundation
import CoreFoundation


struct CFSocketNetworkUtils {
    static func IsPrivateIP(_ ip: String) -> Bool {
        let components = ip.split(separator: ".").map { Int($0) }
        guard components.count == 4 else { return false }

        guard let a = components[0], let b = components[1], let c = components[2], let d = components[3] else {
            return false
        }

        // Local Private IP Ranges
        // 10.0.0.0 - 10.255.255.255
        // 172.16.0.0 - 172.31.255.255
        // 192.168.0.0 - 192.168.255.255
        return (a == 10) || // or
            (a == 172 && (b >= 16 && b <= 31)) ||
            (a == 192 && b == 168) ||
            (ip == "127.0.0.1") // localhost
    }
}


enum CF_ServerStates {
    case started
    case stopped
}

class CFSocketServerConfig {
    // Whether only local addresses can connect
    var allowLocalOnly: Bool = false
}


class CF_TCPServer {
    var serverSocket: CFSocket?
    private var connectionsArray: [CFSocket] = []

    var ServerConfig = CFSocketServerConfig() // Config

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

        // self reference
        let referencedSelf = Unmanaged<CF_TCPServer>.fromOpaque(infoPointer).takeUnretainedValue()




        // If we allow the connection to get accepted
        referencedSelf.connectionsArray.append(socket)
        referencedSelf.OnClientConnectionAccepted(cfSocket: socket)
    }


    func OnServerStarted() {
        print("TCP server started on port \(self.portNumber)")
    }


    // When the Server accepted a Client Connection
    func OnClientConnectionAccepted(cfSocket: CFSocket) {
        print("Accepted connection on socket \(cfSocket)")

        self.cancelConnection(cfSocket)
    }


    func TemporaryLogging(_ str: String) {
        print(str)
    }


    // Use this instead to close connections...
    func cancelConnection(_ cfSocket: CFSocket) {
        if let index = self.connectionsArray.firstIndex(where: { $0 === cfSocket }) {
            self.connectionsArray.remove(at: index)
        }
        
        // Get native handle
        let nativeHandle = CFSocketGetNative(cfSocket)
        close(nativeHandle)
    }


    func startServer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            var context = self.context

            self.serverSocket = CFSocketCreate(
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
            let runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, serverSocket, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
            self.OnServerStarted()

            CFRunLoopRun() // Run server loop
        }
    }


    func stopServer() {
        // If the socket exists
        if let serverSocket = self.serverSocket {
            // Remove socket loop
            if let runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, serverSocket, 0) {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
            }
            CFSocketInvalidate(serverSocket)
            

            // Close socket
            let nativeHandle = CFSocketGetNative(serverSocket)
            close(nativeHandle)
            
            self.serverSocket = nil

            self.TemporaryLogging("TCP Server stopped")
        } else {
            self.TemporaryLogging("Server socket doesn't exist")
        }
    }
}