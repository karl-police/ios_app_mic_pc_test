/*
let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
if socketDescriptor < 0 {
    G_UI_debugTextBoxOut.text += "Error socket\n"
}
var reuse: Int32 = 1
setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

var addr = sockaddr_in()
addr.sin_family = sa_family_t(AF_INET)
addr.sin_port = in_port_t(8125).bigEndian
addr.sin_addr.s_addr = inet_addr("127.0.0.1")

let bindResult = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
}

if bindResult < 0 {
    close(socketDescriptor)
    G_UI_debugTextBoxOut.text += "Error socket 2\n"
}
*/
