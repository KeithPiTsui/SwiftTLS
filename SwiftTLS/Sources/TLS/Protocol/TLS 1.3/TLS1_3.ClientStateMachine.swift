//
//  TLS1_3.ClientStateMachine.swift
//  SwiftTLS
//
//  Created by Nico Schmidt on 29.01.17.
//  Copyright © 2017 Nico Schmidt. All rights reserved.
//

import Foundation

extension TLS1_3 {
    class ClientStateMachine : TLSClientStateMachine
    {
        weak var client : TLSClient?
        var protocolHandler: TLS1_3.ClientProtocol? {
            return client?.protocolHandler as? TLS1_3.ClientProtocol
        }
        
        var state : TLSState = .idle {
            willSet {
                if !checkClientStateTransition(newValue) {
                    fatalError("Client: Illegal state transition \(self.state) -> \(newValue)")
                }
            }
        }
        
        init(client : TLSClient)
        {
            self.client = client
            self.state = .idle
        }
        
        func transition(to state: TLSState) throws {
            if !checkClientStateTransition(state) {
                log("Client: Illegal state transition \(self.state) -> \(state)")
                throw TLSError.alert(alert: .unexpectedMessage, alertLevel: .fatal)
            }
            
            self.state = state
        }
        
        func reset() {
            self.state = .idle
        }
        
        func didSendMessage(_ message : TLSMessage)
        {
            log("Client: did send message \(TLSMessageNameForType(message.type))")
        }
        
        func clientDidSendHandshakeMessage(_ message : TLSHandshakeMessage) throws
        {
            self.didSendMessage(message)
            
            switch message.handshakeType
            {
            case .clientHello:
                try self.transition(to: .clientHelloSent)
                
            case .certificate:
                try self.transition(to: .certificateSent)
                
            case .finished:
                try self.transition(to: .finishedSent)
                
            case .endOfEarlyData:
                try self.transition(to: .endOfEarlyDataSent)

            default:
                log("Unsupported handshake message \(message.handshakeType)")
            }
        }
        
        func clientDidReceiveHandshakeMessage(_ message : TLSHandshakeMessage) throws
        {
            log("Client: did receive message \(TLSHandshakeMessageNameForType(message.handshakeType))")
            
            let handshakeType = message.handshakeType
            
            switch (handshakeType)
            {
            case .serverHello:
                try self.transition(to: .serverHelloReceived)

            case .helloRetryRequest:
                try self.transition(to: .helloRetryRequestReceived)
                try self.protocolHandler!.sendClientHello()

            case .certificate:
                try self.transition(to: .certificateReceived)
                
            case .certificateVerify:
                try self.transition(to: .certificateVerifyReceived)
                
            case .finished:
                try self.transition(to: .finishedReceived)
                // FIXME: Handle Certifcate and CertificateVerify if requested
                try self.protocolHandler!.sendFinished()

            case .encryptedExtensions:
                try self.transition(to: .encryptedExtensionsReceived)

            case .newSessionTicket:
                let newSessionTicket = message as! TLSNewSessionTicket
                log("New Session Ticket received:")
                log("    ticket   = \(hex(newSessionTicket.ticket))")
                log("    Nonce    = \(hex(newSessionTicket.ticketNonce))")
                log("    lifeTime = \(newSessionTicket.ticketLifetime)")
                log("    ageAdd   = \(newSessionTicket.ticketAgeAdd)")
                try self.transition(to: .newSessionTicketReceived)

            default:
                log("Unsupported handshake message \(handshakeType.rawValue)")
            }
        }
        
        func clientDidReceiveAlert(_ alert: TLSAlertMessage) {
            log("Client: did receive message \(alert.alertLevel) \(alert.alert)")
        }
        
        func clientDidConnect() throws {
            if let client = self.client {
                if case .accepted = (client.clientProtocolHandler as! ClientProtocol).clientHandshakeState.earlyDataState {
                    client.earlyDataWasSent = true
                } else {
                    client.earlyDataWasSent = false
                }
            }
            try transition(to: .connected)
        }
        
        func checkClientStateTransition(_ state : TLSState) -> Bool
        {
            if state == .idle {
                return true
            }
            
            switch (self.state)
            {
            case .idle:
                return state == .clientHelloSent
                
            case .clientHelloSent:
                return state == .serverHelloReceived || state == .helloRetryRequestReceived
                
            case .helloRetryRequestReceived:
                return state == .clientHelloSent
                
            case .serverHelloReceived:
                return state == .encryptedExtensionsReceived
                
            case .encryptedExtensionsReceived:
                if self.protocolHandler!.isUsingPreSharedKey {
                        return state == .finishedReceived
                }
                
                return state == .certificateRequestReceived || state == .certificateReceived
                
            case .certificateRequestReceived:
                return state == .certificateReceived
                
            case .certificateReceived:
                return state == .certificateVerifyReceived
                
            case .certificateVerifyReceived:
                return state == .finishedReceived
                
            case .finishedSent:
                return state == .connected

            case .finishedReceived:
                return state == .finishedSent || state == .endOfEarlyDataSent
                
            case .endOfEarlyDataSent:
                return state == .finishedSent
                
            case .connected:
                return (state == .closeReceived || state == .closeSent || state == .newSessionTicketReceived)
                                
            default:
                return false
            }
        }
    }
}
