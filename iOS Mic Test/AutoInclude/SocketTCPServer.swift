abcdefg



/*import Foundation
import Darwin


struct SocketNetworkUtils {
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

    static func GetClientSocketIP(_ clientSocket: Int32) -> String {
        var addr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        if getpeername(clientSocket, UnsafeMutableRawPointer(&addr).assumingMemoryBound(to: sockaddr.self), &addrLen) == 0 {
            let ip = inet_ntoa(addr.sin_addr)
            let port = Int(self.ntohs(addr.sin_port))


            var output = "\(ip)"
            if (port != nil) {
                output += ":\(port)"
            }
            return output
        } else {
            return "Error getting client IP: \(String(cString: strerror(errno)))"
        }
    }
}



// Configurations
class SocketServerConfig {
    // Whether only local addresses can connect
    var allowLocalOnly: Bool = false
}



class SocketServer {
    private var connectionsArray: [Int32] = []
}


class SocketTCPServer : SocketServer {
    var serverSocket: Int32 = -1
    var port: Int32

    var ServerConfig = SocketServerConfig() // Config


    init(inputPort: Int32) {
        self.port = inputPort
    }



    func closeClientSocket(_ clientSocket: Int32) {
        close(clientSocket)
    }

    // Customizable

    // Upon accepting a Client Connection
    // Check regarding thread maybe
    func OnClientConnectionAccepted(_ clientSocket: Int32) {
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        // Receive data from the client
        let bytesRead = recv(clientSocket, &buffer, bufferSize, 0)
        guard bytesRead >= 0 else {
            print("Error reading from client")
            self.closeClientSocket(clientSocket)
            return
        }

        let receivedData = String(bytes: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        print("Received from client: \(receivedData)")

        let response = "Test Reponse\n"
        _ = response.withCString { bytes in
            send(clientSocket, bytes, strlen(bytes), 0)
        }

        // Close Client Socket
        self.closeClientSocket(clientSocket)
    }


    // Start Server
    func startServer() throws {
        // Create socket (IPv4, Stream, TCP)
        self.serverSocket = socket(AF_INET, SOCK_STREAM, 0)


        guard serverSocket >= 0 else {
            throw NSError(domain: "Error creating socket", code: 1)
            return
        }


        // Socket Options
        var reuse = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int>.size))
    
        // Bind socket to IP and Port
        var addr = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: in_port_t(port.bigEndian),
            sin_addr: in_addr(s_addr: INADDR_ANY.bigEndian),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult >= 0 else {
            throw NSError(domain: "Error binding socket", code: 1)

            self.cleanUpServer()
            return
        }



        // Listen
        // Max. 5 Clients in queue
        if listen(serverSocket, 5) >= 0 {
            // Server started
            DispatchQueue.global(qos: .background).async {
                while true {
                    // Handles Listening
                    
                    var clientAddr = sockaddr_in()
                    var clientAddrLen: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)

                    let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            // Blocking Call
                            accept(self.serverSocket, $0, &clientAddrLen)
                        }
                    }

                    guard clientSocket >= 0 else {
                        print("Error accepting client connection")
                        continue
                    }

                    
                    // If we only allow local connections
                    if (self.ServerConfig.allowLocalOnly == true) {
                        let str_clientIP = String(cString: inet_ntoa(clientAddr.sin_addr))

                        if ( !SocketNetworkUtils.IsPrivateIP(str_clientIP) ) {
                            // not a local ip
                            close(clientSocket) // Denies connection
                            continue // Skip handling
                        }
                    }


                    DispatchQueue.global(qos: .userInitiated).async {
                        self.OnClientConnectionAccepted(clientSocket)
                    }
                }
            }
        } else {
            throw NSError(domain: "Error listening on socket", code: 1)

            self.cleanUpServer()
            return
        }
    }

    func stopServer() {
        if serverSocket >= 0 {
            self.cleanUpServer()
        }
    }

    private func cleanUpServer() {
        close(serverSocket)
    }
}


class SocketUDPServer : SocketServer {
    var serverSocket: Int32 = -1
    var port: Int32

    var ServerConfig = SocketServerConfig() // Config


    init(inputPort: Int32) {
        self.port = inputPort
    }


    // Start Server
    func startServer() throws {
        // UDP
        self.serverSocket = socket(AF_INET, SOCK_DGRAM, 0)


        guard serverSocket >= 0 else {
            throw NSError(domain: "Error creating socket", code: 1)
            return
        }


        // Socket Options
        var reuse = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int>.size))
    
        // Bind socket to IP and Port
        var addr = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: in_port_t(port.bigEndian),
            sin_addr: in_addr(s_addr: INADDR_ANY.bigEndian),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )


        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult >= 0 else {
            throw NSError(domain: "Error binding socket", code: 1)

            self.cleanUpServer()
            return
        }


        // Listen
        DispatchQueue.global(qos: .background).async {
            while true {
                var clientAddr = sockaddr_in()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                var buffer = [UInt8](repeating: 0, count: 1024)

                // Receive data
                let bytesReceived = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(self.serverSocket, &buffer, buffer.count, 0, $0, &clientAddrLen)
                    }
                }

                if bytesReceived < 0 {
                    // revfrom error
                    continue
                }

                // Convert to String
                if let message = String(bytes: buffer[0..<bytesReceived], encoding: .utf8) {
                    print("Received message: \(message)")
                }
            }
        }
    }

    func stopServer() {
        if self.serverSocket >= 0 {
            self.cleanUpServer()
        }
    }

    private func cleanUpServer() {
        close(self.serverSocket)
    }
}*/