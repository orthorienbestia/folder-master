import Foundation
import Darwin

enum IsolationProbe {
    static func observe(port: UInt16) -> [String:Int32] {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var networkError: Int32 = errno
        if fd >= 0 {
            defer { close(fd) }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            networkError = result == 0 ? 0 : errno
        }
        var service: mach_port_t = 0
        let lookup = bootstrap_look_up(bootstrap_port, "com.apple.coreservices.launchservicesd", &service)
        if service != 0 { mach_port_deallocate(mach_task_self_, service) }
        return ["network_errno":networkError, "launchservices_lookup":lookup]
    }

    static func listener() throws -> (Int32, UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw error() }
        do {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = 0
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard result == 0, listen(fd, 4) == 0 else { throw error() }
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            guard withUnsafeMutablePointer(to: &address, { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
            }) == 0 else { throw error() }
            return (fd, UInt16(bigEndian: address.sin_port))
        } catch { close(fd); throw error }
    }
    private static func error() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
