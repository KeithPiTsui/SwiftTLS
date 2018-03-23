//
//  TLSServerNameExtension.swift
//  SwiftTLS
//
//  Created by Nico Schmidt on 02.09.15.
//  Copyright © 2015 Nico Schmidt. All rights reserved.
//

import Foundation

enum TLSServerNameType : UInt8
{
    case hostName = 0
}

struct TLSServerNameExtension : TLSExtension
{
    var extensionType : TLSExtensionType {
        get {
            return .serverName
        }
    }
    
    var serverNames : [String]
    
    init(serverNames: [String])
    {
        self.serverNames = serverNames
    }
    
    init?(inputStream: InputStreamType, messageType: TLSMessageExtensionType) {
        guard
            let serverNamesLength : UInt16 = inputStream.read()
        else {
            return nil
        }
        
        self.serverNames = []
        
        var bytesLeft = Int(serverNamesLength)
        while bytesLeft > 0 {
            if  let rawNameType : UInt8 = inputStream.read(),
                let serverNameBytes : [UInt8] = inputStream.read16()
            {
                if TLSServerNameType(rawValue: rawNameType) == nil {
                    fatalError("Unknown host type \(rawNameType)")
                }
                
                self.serverNames.append(String.fromUTF8Bytes(serverNameBytes)!)
                
                bytesLeft -= 3 + serverNameBytes.count
            }
            else {
                break
            }
        }
    }
    
    func writeTo<Target : OutputStreamType>(_ target: inout Target, messageType: TLSMessageExtensionType) {
        let data = DataBuffer()
        for serverName in self.serverNames {
            let utf8 = [UInt8](serverName.utf8)
            data.write(TLSServerNameType.hostName.rawValue)
            data.write(UInt16(utf8.count))
            data.write(utf8)
        }
        
        let extensionsData = data.buffer
        let extensionsLength = extensionsData.count
        
        target.write(self.extensionType.rawValue)
        target.write(UInt16(extensionsData.count + 2))
        target.write(UInt16(extensionsLength))
        target.write(extensionsData)
    }
}
