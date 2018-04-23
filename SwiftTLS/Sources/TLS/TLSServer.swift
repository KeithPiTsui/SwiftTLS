//
//  TLSServer.swift
//  SwiftTLS
//
//  Created by Nico Schmidt on 05.01.17.
//  Copyright © 2017 Nico Schmidt. All rights reserved.
//

import Foundation

class TLSServer : TLSConnection
{
    internal var serverProtocolHandler: TLSServerProtocol! {
        get {
            return self.protocolHandler as! TLSServerProtocol
        }
    }

    var clientKeyShare: KeyShareEntry? = nil
    var earlyDataResponseHandler: TLSServerSocket.EarlyDataResponseHandler? = nil
    
    override init(configuration: TLSConfiguration, context: TLSContext? = nil, dataProvider : TLSDataProvider? = nil)
    {
        super.init(configuration: configuration, context: context, dataProvider: dataProvider)
        
        if !(context is TLSServerContext) {
            self.context = configuration.createServerContext()
        }

        setupServer(with: configuration)
    }
    
    func acceptConnection() throws
    {
        reset()
        
        do {
            try self.receiveNextTLSMessage()
        } catch TLSError.alert(alert: let alert, alertLevel: let alertLevel) {
            if alertLevel == .fatal {
                try abortHandshake(with: alert)
            }
            
            throw TLSError.alert(alert: alert, alertLevel: alertLevel)
        }
        
        try self.didConnect()
        
        self.handshakeMessages = []
    }
    
    override func handleHandshakeMessage(_ message : TLSHandshakeMessage) throws
    {
        let handshakeType = message.handshakeType
        
        switch (handshakeType)
        {
        case .clientHello:
            let clientHello = (message as! TLSClientHello)
            try self.serverProtocolHandler.handleClientHello(clientHello)
            
        case .clientKeyExchange:
            try self.protocolHandler.handleMessage(message)
            
        case .finished:
            let finished = message as! TLSFinished
            try self.protocolHandler.handleFinished(finished)
            
        default:
            throw TLSError.error("Unsupported handshake message \(handshakeType.rawValue)")
        }
        
        try self.stateMachine?.didReceiveHandshakeMessage(message)
    }

    func setupServer(with configuration: TLSConfiguration, version: TLSProtocolVersion? = nil)
    {
        var version = version
        if version == nil {
            version = configuration.supportedVersions.first
        }
        
        let state = self.stateMachine?.state
        
        switch version!
        {
        case TLSProtocolVersion.v1_2:
            self.protocolHandler    = TLS1_2.ServerProtocol(server: self)
            self.stateMachine       = TLS1_2.ServerStateMachine(server: self)
            self.recordLayer        = TLS1_2.RecordLayer(connection: self, dataProvider: self.recordLayer?.dataProvider)
            
        case TLSProtocolVersion.v1_3:
            self.protocolHandler    = TLS1_3.ServerProtocol(server: self)
            self.stateMachine       = TLS1_3.ServerStateMachine(server: self)
            self.recordLayer        = TLS1_3.RecordLayer(connection: self, dataProvider: self.recordLayer?.dataProvider)
            
        default:
            fatalError("Unsupported protocol \(version!)")
        }
        
        if let state = state {
            self.stateMachine!.state = state
        }

        if let identity = configuration.identity {
            // we are currently only supporting RSA certificates
            if let rsa = identity.rsa {
                self.signer = rsa
            }
        }
    }
}