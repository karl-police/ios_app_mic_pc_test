import Foundation
import CoreFoundation


struct CF_SocketNetworkUtils {
    static func ntohs(_ value: in_port_t) -> UInt16 {
        return (UInt16(value) >> 8) | (UInt16(value) << 8)
    }

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


    static func GetIP_FromNativeSocket(_ nativeSocket: Int32, b_includePort: Bool = false ) -> String {
        var addr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        if getpeername(nativeSocket, UnsafeMutableRawPointer(&addr).assumingMemoryBound(to: sockaddr.self), &addrLen) == 0 {
            guard let ipCString = inet_ntoa(addr.sin_addr) else {
                return "Error getting IP with inet_ntoa"
            }

            let ip = String(cString: ipCString)
            let port = Int(self.ntohs(addr.sin_port))

            var output = "\(ip)"
            
            if (b_includePort == true /*&& port != nil*/) {
                output += ":\(port)"
            }

            return output
        } else {
            return "Error getting IP: \(String(cString: strerror(errno)))"
        }
    }

    static func GetIP_FromCFSocket(_ cfSocket: CFSocket, b_includePort: Bool = false) -> String {
        let nativeCFSocket = CFSocketGetNative(cfSocket) // Int32
        return CF_SocketNetworkUtils.GetIP_FromNativeSocket(nativeCFSocket, b_includePort: b_includePort)
    }
}


enum CF_ServerStates {
    case started
    case stopped
}

enum CF_ClientStates {
    case disconnected
}


// Server Config
class CF_SocketServerConfig {
    // Whether only local addresses can connect
    var allowLocalOnly: Bool = false
}

class CF_TCPServer {
    var serverSocket: CFSocket?
    private var activeCFSocketsArray: [CFSocket] = []

    var ServerConfig = CF_SocketServerConfig() // Config

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


    private var clientSocketCallback: CFSocketCallBack = { (_ client_cfSocket, callbackType, _ address, dataPointer, infoPointer) in
        guard let client_cfSocket = client_cfSocket else { return }

        guard callbackType == .readCallBack, let infoPointer = infoPointer else {
            return
        }

        // self reference
        let referencedSelf = Unmanaged<CF_TCPServer>.fromOpaque(infoPointer).takeUnretainedValue()

        if (callbackType == .readCallBack) {
            let nativeHandle = CFSocketGetNative(client_cfSocket)

            // Apparently getsockopt is used to get the socket status
            // If the errorCode is not 0, it means that there may have been an issue.
            var errorCode: Int32 = 0
            var errorCodeLen = socklen_t(MemoryLayout.size(ofValue: errorCode))
            let result = getsockopt(nativeHandle, SOL_SOCKET, SO_ERROR, &errorCode, &errorCodeLen)

            if (result == 0 && errorCode != 0) {
                referencedSelf.OnClientStateChanged(client_cfSocket, CF_ClientStates.disconnected)

                CFSocketInvalidate(client_cfSocket)
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
        }
    }


    // Configurable customizable checks
    func ShouldAcceptClientCFSocket(_ client_cfSocket: CFSocket) -> Bool {
        return true
    }

    private var serverSocketCallback: CFSocketCallBack = { (_ cfSocket, callbackType, _ address, dataPointer, infoPointer) in
        guard let cfSocket = cfSocket else { return }

        guard callbackType == .acceptCallBack, let infoPointer = infoPointer,
            let clientSocketHandle = dataPointer?.assumingMemoryBound(to: CFSocketNativeHandle.self).pointee else {
                return
        }

        // self reference
        let referencedSelf = Unmanaged<CF_TCPServer>.fromOpaque(infoPointer).takeUnretainedValue()


        // Create CFSocket from client native socket
        var clientContext = CFSocketContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        clientContext.info = UnsafeMutableRawPointer(Unmanaged.passUnretained(referencedSelf).toOpaque())

        let clientCallbackTypes: CFOptionFlags = CFSocketCallBackType.readCallBack.rawValue

        guard let client_cfSocket = CFSocketCreateWithNative(
            kCFAllocatorDefault, clientSocketHandle, clientCallbackTypes,
            referencedSelf.clientSocketCallback, // Add callback for client
            &clientContext
        ) else {
            return
        }
    

        // If local IP only
        if (referencedSelf.ServerConfig.allowLocalOnly == true) {
            // Turn CFSocket to Native Handle
            let client_NativeCFSocket = CFSocketGetNative(client_cfSocket) // Int32

            let ipStr = CF_SocketNetworkUtils.GetIP_FromNativeSocket(client_NativeCFSocket)

            if (CF_SocketNetworkUtils.IsPrivateIP(ipStr) == false) {
                referencedSelf.close_CFSocket(client_cfSocket)
                return
            }
        }


        // Additional checking
        if (referencedSelf.ShouldAcceptClientCFSocket(client_cfSocket) == false) {
            // If false then close
            referencedSelf.close_CFSocket(client_cfSocket)
            return
        }


        // If we allow the connection to get accepted
        referencedSelf.activeCFSocketsArray.append(client_cfSocket)

        // Add run loop for client
        let clientRunLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, client_cfSocket, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), clientRunLoopSource, .defaultMode)

        referencedSelf.OnClientConnectionAccepted(client_cfSocket: client_cfSocket)
    }



    // Whenever a state changed
    func OnServerStateChanged(_ state: CF_ServerStates) {
        switch state {
            case .started:
                print("TCP server started on port \(self.portNumber)")
            case .stopped:
                print("TCP Server stopped")
            default:
                break
        }
    }

    func OnClientStateChanged(_ client_cfSocket: CFSocket, _ state: CF_ClientStates) {
        switch state {
            case .disconnected:
                let ipStr = CF_SocketNetworkUtils.GetIP_FromCFSocket(client_cfSocket, b_includePort: true)
                print("Client Disconnected, \(ipStr)")
            default:
                break
        }
    }


    // When the Server accepted a Client Connection
    func OnClientConnectionAccepted(client_cfSocket: CFSocket) {
        print("Accepted connection on socket \(client_cfSocket)")

        self.close_CFSocket(client_cfSocket)
    }


    func TemporaryLogging(_ str: String) {
        print(str)
    }


    // Use this instead to close connections...
    func close_CFSocket(_ cfSocket: CFSocket) {
        if let index = self.activeCFSocketsArray.firstIndex(where: { $0 === cfSocket }) {
            self.activeCFSocketsArray.remove(at: index)
        }
        
        // Get native handle
        let nativeHandle = CFSocketGetNative(cfSocket)
        close(nativeHandle)
    }


    func startServer() {
        var context = self.context

        self.serverSocket = CFSocketCreate(
            kCFAllocatorDefault,
            PF_INET,
            SOCK_STREAM,
            IPPROTO_TCP,
            CFSocketCallBackType.acceptCallBack.rawValue,
            serverSocketCallback, // CFSocketCallBack
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

        // Make socket re-useable
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
        self.OnServerStateChanged(CF_ServerStates.started)

        DispatchQueue.global(qos: .userInitiated).async {
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

            // Close active sockets
            for activeCFSocket in activeCFSocketsArray {
                self.close_CFSocket(activeCFSocket)
            }

            CFSocketInvalidate(serverSocket)
            
            // Close socket
            let nativeHandle = CFSocketGetNative(serverSocket)
            close(nativeHandle)
            
            self.serverSocket = nil

            self.OnServerStateChanged(CF_ServerStates.stopped)
        } else {
            self.TemporaryLogging("Server socket doesn't exist")
        }
    }
}