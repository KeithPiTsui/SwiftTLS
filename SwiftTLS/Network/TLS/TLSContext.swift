//
//  TLSContext.swift
//  SwiftTLS
//
//  Created by Nico Schmidt on 06.01.17.
//  Copyright © 2017 Nico Schmidt. All rights reserved.
//

import Foundation

public protocol TLSContext {
}

class TLSClientContext : TLSContext
{
    // The client session cache is indexed by hostname and port concatenated to
    // a string "\(hostname):\(port)"
    var sessionCache: [String : TLSSession] = [:]
}

class TLSServerContext : TLSContext
{
    // The saved sessions that the server can reuse when a client sends a sessionID
    // we know about from before
    var sessionCache: [TLSSessionID: TLSSession] = [:]
}
