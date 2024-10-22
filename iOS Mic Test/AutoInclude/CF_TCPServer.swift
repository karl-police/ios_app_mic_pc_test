import Foundation
import CoreFoundation

enum CF_NetworkProtocols {
    case TCP
    case UDP
}

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



    static func GetIP_FromCFDataAddress(_ address: CFData, b_includePort: Bool = false) -> String {
        let sockaddrPointer = CFDataGetBytePtr(address)
        let sockaddrLen = CFDataGetLength(address)

        guard let sockaddrPointer = sockaddrPointer else {
            return "Error getting sockaddrPointer"
        }

        var output = ""
        var ipStr = "No IP"
        var port: Int = 0

        sockaddrPointer.withMemoryRebound(to: sockaddr.self, capacity: sockaddrLen) { sockaddrPtr in
            if sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET) {
                // IPv4
                var addr4 = sockaddrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr4.sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))

                ipStr = String(cString: ipBuffer)
                port = Int(ntohs(addr4.sin_port)) // Port

            } else if sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET6) {
                // IPv6
                var addr6 = sockaddrPtr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                var ipBuffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                inet_ntop(AF_INET6, &addr6.sin6_addr, &ipBuffer, socklen_t(INET6_ADDRSTRLEN))

                ipStr = String(cString: ipBuffer)
                port = Int(ntohs(addr6.sin6_port))
            }
        }

        output = ipStr
        // idk about IPv6 yet
        if (b_includePort == true) {
            output += ":\(port)"
        }

        return output
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

    static func GetStringFromNetworkProtocol(_ protocols: CF_NetworkProtocols) -> String {
        switch protocols {
            case CF_NetworkProtocols.TCP:
                return "TCP"
            case CF_NetworkProtocols.UDP:
                return "UDP"
            default:
                return "Unknown Protocol"
        }
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

    // Make TCP the default protocol
    var networkProtocol = CF_NetworkProtocols.TCP
}


class CF_NetworkServer {
    var serverSocket: CFSocket?
    private var activeCFSocketsArray: [CFSocket] = []
    private var arr_activeAcceptedAddresses: [String] = []

    var ServerConfig = CF_SocketServerConfig() // Config

    //private var clientSocketCallback: CFSocketCallBack!
    private var serverSocketCallback: CFSocketCallBack?

    private var semaphore = DispatchSemaphore(value: 0) // this is probably stupid
    private var receivedUDPData: Data? = nil
    private var receivedUDP_lastFromAddr: CFData? = nil

    var portNumber: Int32 = 0;

    init(inputPort: Int32) {
        // Set Port number
        self.portNumber = inputPort;
    }


    // Configurable customizable checks
    func ShouldAcceptClientCFSocket(_ client_cfSocket: CFSocket) -> Bool {
        return true
    }


    private var context: CFSocketContext {
        var context = CFSocketContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        return context
    }


    // This one can probably stay the same on both.
    private var clientSocketCallback: CFSocketCallBack = { (_ client_cfSocket, callbackType, _ address, dataPointer, infoPointer) in
        guard let client_cfSocket = client_cfSocket else { return }

        guard callbackType == .readCallBack, let infoPointer = infoPointer else {
            return
        }

        // self reference
        let referencedSelf = Unmanaged<CF_NetworkServer>.fromOpaque(infoPointer).takeUnretainedValue()

        if (callbackType == .readCallBack) {
            let nativeHandle = CFSocketGetNative(client_cfSocket)

            // Apparently getsockopt is used to get the socket status
            // If the errorCode is not 0, it means that there may have been an issue.
            var errorCode: Int32 = 0
            var errorCodeLen = socklen_t(MemoryLayout.size(ofValue: errorCode))
            let result = getsockopt(nativeHandle, SOL_SOCKET, SO_ERROR, &errorCode, &errorCodeLen)

            if (result == 0 && errorCode != 0) {
                // Client Disconnected
                referencedSelf.OnClientStateChanged(client_cfSocket, CF_ClientStates.disconnected)

                CFSocketInvalidate(client_cfSocket)
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
        }
    }




    // Whether to let through a connection or not
    private func internal_shouldLetThroughConnection(
        _ client_cfSocket: CFSocket,
        _ addressQ: CFData?
    ) -> Bool {
        guard let address = addressQ else {
            return false
        }

        // If local IP only
        if (self.ServerConfig.allowLocalOnly == true) {
            // Turn CFSocket to Native Handle
            //let client_NativeCFSocket = CFSocketGetNative(client_cfSocket) // Int32

            let ipStr = CF_SocketNetworkUtils.GetIP_FromCFDataAddress(address)
            self.TemporaryLogging(ipStr)

            if (CF_SocketNetworkUtils.IsPrivateIP(ipStr) == false) {
                self.close_CFSocket(client_cfSocket, address)
                return false
            }
        }

        // Additional checking
        if (self.ShouldAcceptClientCFSocket(client_cfSocket) == false) {
            // If false then close
            self.close_CFSocket(client_cfSocket, address)
            return false
        }

        
        // If we made it through
        return true
    }


    // Apparently to send stuff
    func SendCFData(_ data: CFData, addressData: CFData, toCFSocket: CFSocket? = nil) -> CFSocketError {
        switch self.ServerConfig.networkProtocol {
            // TCP
            case CF_NetworkProtocols.TCP: do {
                guard let socket = toCFSocket else {
                    return CFSocketError.error
                }

                return CFSocketSendData(socket, nil, data, 0)
            }

            // UDP
            case CF_NetworkProtocols.UDP: do {
                guard let socket = self.serverSocket else {
                    self.TemporaryLogging("No Server Socket")
                    return CFSocketError.error
                }

                // Send the message
                return CFSocketSendData(socket, addressData, data, 0)
            }
        }
    }


    func receiveDataWithBuffer(_ buffer: inout [UInt8], addressData: CFData, _ fromCFSocket_Handle: Int32 = 0) -> Int {
        switch self.ServerConfig.networkProtocol {
            // TCP
            case CF_NetworkProtocols.TCP: do {
                return recv(fromCFSocket_Handle, &buffer, buffer.count, 0)
            }
            // UDP
            /*case CF_NetworkProtocols.UDP: do {
                
            }*/

            default:
                break
        }

        return -1
    }

    func receiveData(_ buffer: inout [UInt8], addressData: CFData, _ fromCFSocket_Handle: Int32 = 0) -> Data? {
        var receivedDataQ: Data? = nil

        switch self.ServerConfig.networkProtocol {
            case CF_NetworkProtocols.TCP: do {
                let readResult = self.receiveDataWithBuffer(&buffer, addressData: addressData, fromCFSocket_Handle)

                if (readResult > 0) {
                    receivedDataQ = Data(buffer[0..<readResult])
                }
            }

            case CF_NetworkProtocols.UDP: do {
                receivedDataQ = self.WaitForData(from: addressData)
            } 
        }

        return receivedDataQ
    }


    // For UDP
    func OnServerDataReceived(_ data: Data, from addressData: CFData) {
        self.receivedUDPData = data
        self.receivedUDP_lastFromAddr = addressData
        self.TemporaryLogging("hi: \(addressData)")
        semaphore.signal() // Signal
    }
    func WaitForData(from expectAddr: CFData) -> Data? {
        // yep idk

        /*if (self.receivedUDPData == nil) {
            self.TemporaryLogging("waiting for data")
            semaphore.wait()
        }*/
        semaphore.wait(timeout: .now() + 5)

        guard let receivedUDP_lastFromAddr = self.receivedUDP_lastFromAddr else {
            self.TemporaryLogging("no address")
            return nil
        }

        // Check if from right IP otherwise, wait again
        let ipStr_lastFrom = CF_SocketNetworkUtils.GetIP_FromCFDataAddress(receivedUDP_lastFromAddr, b_includePort: true)
        let str_expectAddr = CF_SocketNetworkUtils.GetIP_FromCFDataAddress(expectAddr, b_includePort: true)
        if (ipStr_lastFrom != str_expectAddr) {
            self.TemporaryLogging("did not match")
            return self.WaitForData(from: expectAddr)
        }

        self.TemporaryLogging("take data!")

        var copyData = self.receivedUDPData

        self.receivedUDPData = nil
        self.receivedUDP_lastFromAddr = nil

        return copyData
    }


    // Process the rest of the callback
    private func serverCallbackProcessClient(
        _ cfSocket: CFSocket,
        _ callbackType: CFSocketCallBackType,
        _ addressQ: CFData?,
        _ dataPointer:  UnsafeRawPointer?,
        _ infoPointer: UnsafeRawPointer,

        _ clientSocketHandle: Int32
    ) {
        // self reference
        let referencedSelf = Unmanaged<CF_NetworkServer>.fromOpaque(infoPointer).takeUnretainedValue()


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
    

        let b_shouldAllowConnection = referencedSelf.internal_shouldLetThroughConnection(client_cfSocket, addressQ)
        if (b_shouldAllowConnection == false) {
            return
        }

        // If we allow the connection to get accepted
        referencedSelf.activeCFSocketsArray.append(client_cfSocket)


        guard let address = addressQ else { return }
        let ipStr = CF_SocketNetworkUtils.GetIP_FromCFDataAddress(address)


        // Let through if TCP...
        let isTCP = self.ServerConfig.networkProtocol == CF_NetworkProtocols.TCP
        let isUDP = self.ServerConfig.networkProtocol == CF_NetworkProtocols.UDP
        let isUDPAndNotAcceptedYet = (isUDP && self.arr_activeAcceptedAddresses.contains(ipStr) == false)

        // But if not TCP ensure for UDP each is unique
        if (isTCP || isUDPAndNotAcceptedYet) {
            // Add run loop for client
            let clientRunLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, client_cfSocket, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), clientRunLoopSource, .defaultMode)

            referencedSelf.OnClientConnectionAccepted(client_cfSocket: client_cfSocket, addressQ: addressQ)

            if (isUDP) {
                // Put into active Addresses, if UDP
                self.arr_activeAcceptedAddresses.append(ipStr)
            }
        }


        switch self.ServerConfig.networkProtocol {
            /*case CF_NetworkProtocols.TCP: do {
                
            }*/

            // UDP
            case CF_NetworkProtocols.UDP: do {
                // If Data was received
                if (callbackType == .dataCallBack) {
                    guard let address = addressQ else { return }

                    if let dataPointer = dataPointer {
                        let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
                        referencedSelf.OnServerDataReceived(data, from: address)
                    }
                }
            }

            default:
                break
        }
    }


    // Setup callbacks depending on the current protocol
    private func setupSocketCallbacks() {
        switch self.ServerConfig.networkProtocol {
            // TCP
            case CF_NetworkProtocols.TCP: do {
                self.serverSocketCallback = { (_ cfSocket, callbackType, _ address, dataPointer, infoPointer) in
                    guard let cfSocket = cfSocket else { return }

                    guard callbackType == .acceptCallBack, let infoPointer = infoPointer,
                        let clientSocketHandle = dataPointer?.assumingMemoryBound(to: CFSocketNativeHandle.self).pointee else {
                            return
                    }

                    // Maybe change this idk
                    let referencedSelf = Unmanaged<CF_NetworkServer>.fromOpaque(infoPointer).takeUnretainedValue()
                    referencedSelf.serverCallbackProcessClient(cfSocket, callbackType, address, dataPointer, infoPointer, clientSocketHandle)
                }
            }

            // UDP
            case CF_NetworkProtocols.UDP: do {
                self.serverSocketCallback = { (_ cfSocket, callbackType, _ address, dataPointer, infoPointer) in
                    guard let cfSocket = cfSocket else { return }

                    guard callbackType == .dataCallBack, let infoPointer = infoPointer,
                        let clientSocketHandle = dataPointer?.assumingMemoryBound(to: CFSocketNativeHandle.self).pointee else {
                            return
                    }

                    let referencedSelf = Unmanaged<CF_NetworkServer>.fromOpaque(infoPointer).takeUnretainedValue()
                    referencedSelf.serverCallbackProcessClient(cfSocket, callbackType, address, dataPointer, infoPointer, clientSocketHandle)
                }
            }

            default:
                break
        }
    }



    // Get set Protocol as String
    internal func GetCurrentProtocolAsString() -> String {
        return CF_SocketNetworkUtils.GetStringFromNetworkProtocol(self.ServerConfig.networkProtocol)
    }

    // Whenever a state changed
    func OnServerStateChanged(_ state: CF_ServerStates) {
        let protocolStr = self.GetCurrentProtocolAsString()

        switch state {
            case .started:
                print("\(protocolStr) Server started on port \(self.portNumber)")
            case .stopped:
                print("\(protocolStr) Server stopped")
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
    func OnClientConnectionAccepted(
        client_cfSocket: CFSocket,
        addressQ: CFData?
    ) {
        guard let address = addressQ else { return }

        //let client_NativeCFSocket = CFSocketGetNative(client_cfSocket) // Int32
        //let ipStr = CF_SocketNetworkUtils.GetIP_FromNativeSocket(client_NativeCFSocket, b_includePort: true)
        let ipStr = CF_SocketNetworkUtils.GetIP_FromCFDataAddress(address, b_includePort: true)

        print("Accepted connection on socket \(ipStr)")

        // Close
        self.close_CFSocket(client_cfSocket, addressQ)
    }


    func TemporaryLogging(_ str: String) {
        print(str)
    }


    // Use this instead to close connections...
    func close_CFSocket(_ cfSocket: CFSocket, _ addressQ: CFData?) {
        if let index = self.activeCFSocketsArray.firstIndex(where: { $0 === cfSocket }) {
            self.activeCFSocketsArray.remove(at: index)
        }

        // Invalidate
        CFSocketInvalidate(cfSocket)

        if (self.ServerConfig.networkProtocol == CF_NetworkProtocols.UDP) {
            // Remove address if UDP
            if let address = addressQ {
                let ipStr = CF_SocketNetworkUtils.GetIP_FromCFDataAddress(address)
                if let index = self.arr_activeAcceptedAddresses.firstIndex(where: { $0 == ipStr }) {
                    self.arr_activeAcceptedAddresses.remove(at: index)
                }
            }
        }
        
        // Get native handle
        let nativeHandle = CFSocketGetNative(cfSocket)
        close(nativeHandle)
    }


    func initServerSocket() {
        guard let serverSocketCallback = serverSocketCallback else {return}

        var context = self.context

        switch self.ServerConfig.networkProtocol {
            case CF_NetworkProtocols.TCP:
                self.serverSocket = CFSocketCreate(
                    kCFAllocatorDefault,
                    PF_INET,
                    SOCK_STREAM,
                    IPPROTO_TCP,
                    CFSocketCallBackType.acceptCallBack.rawValue,
                    serverSocketCallback, // CFSocketCallBack
                    &context
                )

            case CF_NetworkProtocols.UDP:
                self.serverSocket = CFSocketCreate(
                    kCFAllocatorDefault,
                    PF_INET,
                    SOCK_DGRAM, // UDP
                    IPPROTO_UDP, // UDP
                    CFSocketCallBackType.dataCallBack.rawValue,
                    serverSocketCallback, // CFSocketCallBack
                    &context
                )

            default:
                break
        }
    }


    func startServer() {
        self.setupSocketCallbacks() // IMPORTANT

        if (self.serverSocketCallback == nil || self.clientSocketCallback == nil) {
            self.TemporaryLogging("There was an issue with creating the callbacks for the server.")
            return
        }

        // Init server socket
        self.initServerSocket()

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

        DispatchQueue.global(qos: .background).async {
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
                self.close_CFSocket(activeCFSocket, nil)
            }
            self.arr_activeAcceptedAddresses.removeAll()

            CFSocketInvalidate(serverSocket)
            
            // Close server socket
            let nativeHandle = CFSocketGetNative(serverSocket)
            close(nativeHandle)
            
            self.serverSocket = nil

            self.OnServerStateChanged(CF_ServerStates.stopped)
        } else {
            print("Server socket doesn't exist")
        }
    }
}