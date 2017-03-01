//
//  Server.swift
//  ServerSocket
//
//  Created by Dmitry Bespalov on 01/03/17.
//  Copyright © 2017 Dmitry Bespalov. All rights reserved.
//

import Foundation

class Server: NSObject, StreamDelegate {

    var socket: CFSocket!
    var port: Int!

    var inputStream: InputStream!
    var outputStream: OutputStream!

    func start(port: Int) {
        self.port = port
        bind()
    }

    func startConnection() {
        configureSSL(for: inputStream)
        open(stream: inputStream)
    }

    func open(stream: Stream) {
        stream.delegate = self
        stream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        stream.open()
    }

    func configureSSL(for stream: Stream) {
        guard let certs = certificates() else { return }
        let sslSettings: [String: AnyObject] = [
            kCFStreamSSLIsServer as String: NSNumber(booleanLiteral: true),
            kCFStreamSSLCertificates as String: certs as AnyObject,
            kCFStreamSSLLevel as String: (kCFStreamSocketSecurityLevelNegotiatedSSL as AnyObject),
            ]
        let result = stream.setProperty(sslSettings,
                                        forKey: Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String))
        if !result {
            print("Failed to set SSL settings")
        }
    }

    func certificates() -> [AnyObject]? {
        guard let certPath = Bundle(for: Server.self).url(forResource: "MyLocalServer",
                                                          withExtension: "p12") else {
            print("Certificate not found")
            return nil
        }
        do {
            let certData = try Data(contentsOf: certPath, options: [])
            let password = "123456"
            let options: NSDictionary = [kSecImportExportPassphrase: password]
            var items: CFArray? = nil
            let status = SecPKCS12Import(certData as CFData, options, &items)
            if status != errSecSuccess {
                fatalError("Error importing SSL certificate: \(status)")
            }
            guard let certArray = items as? [[String: Any]] else {
                fatalError("No items imported from certificate")
            }
            let identity = certArray[0][kSecImportItemIdentity as String] as! SecIdentity
            let certChain = certArray[0][kSecImportItemCertChain as String] as! [SecCertificate]
            let certs: [AnyObject] = [identity as AnyObject] + certChain
            return certs
        } catch {
            print("Error configuring SSL")
        }
        return nil
    }

    func bind() {
        let callback: CFSocketCallBack = {
            (s: CFSocket?, callbackType: CFSocketCallBackType, address: CFData?,
            data: UnsafeRawPointer?, info: UnsafeMutableRawPointer?) in

            guard callbackType == CFSocketCallBackType.acceptCallBack else { return }
            guard let info = info else {
                fatalError("Socket callback without info")
            }
            let this = Unmanaged<Server>.fromOpaque(info).takeUnretainedValue()
            guard let socket = data?.assumingMemoryBound(to: CFSocketNativeHandle.self).pointee else { return }
            var read: Unmanaged<CFReadStream>? = nil
            var write: Unmanaged<CFWriteStream>? = nil
            CFStreamCreatePairWithSocket(kCFAllocatorDefault,
                                         socket,
                                         &read,
                                         &write)
            guard let inputStream: InputStream = read?.takeUnretainedValue() as? InputStream,
                let outputStream: OutputStream = write?.takeUnretainedValue() as? OutputStream else { return }
            this.inputStream = inputStream
            this.outputStream = outputStream
            this.startConnection()
        }

        let this = Unmanaged.passUnretained(self).toOpaque()
        var context = CFSocketContext(version: 0,
                                      info: this,
                                      retain: {
                                        guard let this = $0 else { return $0 }
                                        _ = Unmanaged<Server>.fromOpaque(this).retain()
                                        return $0 },
                                      release: {
                                        guard let this = $0 else { return }
                                        _ = Unmanaged<Server>.fromOpaque(this).release() },
                                      copyDescription: nil)

        socket = CFSocketCreate(kCFAllocatorDefault,
                                PF_INET,
                                SOCK_STREAM,
                                IPPROTO_TCP,
                                CFSocketCallBackType.acceptCallBack.rawValue,
                                callback,
                                &context)
        let portInBigEndian = UInt16(port).bigEndian
        var addr = sockaddr_in(sin_len: __uint8_t(MemoryLayout<sockaddr_in>.size),
                               sin_family: sa_family_t(AF_INET),
                               sin_port: in_port_t(portInBigEndian),
                               sin_addr: in_addr(s_addr: INADDR_ANY),
                               sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        let result = withUnsafePointer(to: &addr) { (pointer: UnsafePointer<sockaddr_in>) -> Bool in
            return pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<sockaddr_in>.size, {
                (addrPtr: UnsafePointer<UInt8>) -> Bool in

                let addrData = CFDataCreate(kCFAllocatorDefault, addrPtr, MemoryLayout<sockaddr_in>.size)
                let result = CFSocketSetAddress(self.socket, addrData)
                switch result {
                case .error:
                    print("Error setting address")
                    return false
                case .success:
                    print("Successfully set socket address")
                    return true
                case .timeout:
                    print("Timeout while setting socket address")
                    return false
                }
            })
        }
        if !result {
            stop()
            return
        }

        let socketSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault,
                                                       socket,
                                                       0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           socketSource,
                           CFRunLoopMode.defaultMode)
    }

    func htons(_ value: UInt16) -> UInt16 {
        return (value << 8) + (value >> 8)
    }

    func stop() {
        CFSocketInvalidate(socket)
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event.openCompleted:
            print("\(aStream) opened")
        case Stream.Event.hasBytesAvailable:
            read()
        case Stream.Event.hasSpaceAvailable:
            write()
        case Stream.Event.errorOccurred:
            print("\(aStream) error occured: \(inputStream.streamError?.localizedDescription ?? "")")
            fallthrough
        case Stream.Event.endEncountered:
            shutDown(stream: aStream)
        default:
            print("\(aStream) default action for event \(eventCode)")
        }
    }

    var readData = Data()
    var totalBytesRead = 0

    func read() {
        print("Reading bytes from input")
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let result = inputStream.read(&buffer, maxLength: bufferSize)
        if result > 0 {
            let bytesRead = result
            print("Read \(bytesRead) bytes in")
            readData.append(&buffer, count: bytesRead)
            totalBytesRead += bytesRead
            if !inputStream.hasBytesAvailable {
                print("Handling request")
                handleRequest()
            }
        } else if result == 0 {
            print("Reached end of buffer")
        } else {
            print("Input stream read error: \(inputStream.streamError?.localizedDescription ?? "")")
            shutDown(stream: inputStream)
        }
    }

    func handleRequest() {
        print("*** Request: \(String(data: readData, encoding: String.Encoding.utf8) ?? "")")
        let body = "<html><body><h1>Hello, world!</h1></body></html>"
        let length = body.lengthOfBytes(using: String.Encoding.utf8)
        let response = "HTTP/1.1 200 OK \r\nConnection: Closed\r\n" +
            "Content-Type: text/html; charset=utf8\r\nContent-Length: \(length)\r\n\r\n\(body)"
        print("*** Response: \(response)")
        guard let data = response.data(using: String.Encoding.utf8) else {
            print("Failed to convert response to Data")
            return
        }
        writeData = data
        open(stream: outputStream)
    }

    func shutDown(stream: Stream) {
        stream.close()
        stream.remove(from: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        print("Stream is closed")
    }

    var writeData = Data()
    var totalBytesWritten = 0

    func write() {
        print("Preparing to write bytes")

        writeData.withUnsafeMutableBytes({ (pointer: UnsafeMutablePointer<UInt8>) in
            let startBytePointer = pointer.advanced(by: totalBytesWritten)
            let bytesLeft = writeData.count - totalBytesWritten
            let maxBufferSize = 1024
            let bufferSize = (bytesLeft >= maxBufferSize) ? maxBufferSize : bytesLeft
            let buffer = [UInt8](repeating: 0, count: bufferSize)
            let dst = UnsafeMutableRawPointer(mutating: buffer)
            let src = UnsafeMutableRawPointer(startBytePointer)
            memcpy(dst, src, bufferSize)
            let result = outputStream.write(buffer, maxLength: bufferSize)
            if result > 0 {
                let bytesWritten = result
                print("Wrote \(bytesWritten) bytes out")
                totalBytesWritten += bytesWritten
            } else if result == 0 {
                print("Reached the end of the buffer while writing")
            } else {
                print("Output stream read error: \(outputStream.streamError?.localizedDescription ?? "")")
                shutDown(stream: outputStream)
            }
        })
    }
    
}
