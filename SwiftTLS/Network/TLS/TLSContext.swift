//
//  TLSContext.swift
//  Chat
//
//  Created by Nico Schmidt on 21.03.15.
//  Copyright (c) 2015 Nico Schmidt. All rights reserved.
//

import Foundation

public enum CompressionMethod : UInt8 {
    case NULL = 0
}



enum TLSError : ErrorType
{
    case Error
}


enum TLSDataProviderError : ErrorType
{
    init?(socketError : SocketError?)
    {
        if let error = socketError {
            switch error {
            case .PosixError(let errno):
                self = TLSDataProviderError.PosixError(errno: errno)
            }
        }
        else {
            return nil
        }
    }
    
    case PosixError(errno : Int32)
}

extension TLSDataProviderError : CustomStringConvertible
{
    var description : String {
        get {
            switch (self)
            {
            case let .PosixError(errno):
                return String.fromCString(strerror(errno))!
            }
        }
    }
}



protocol TLSDataProvider : class
{
    func writeData(data : [UInt8], completionBlock : ((TLSDataProviderError?) -> ())?)
    func readData(count count : Int, completionBlock : ((data : [UInt8]?, error : TLSDataProviderError?) -> ()))
}

let TLSClientFinishedLabel = [UInt8]("client finished".utf8)
let TLSServerFinishedLabel = [UInt8]("server finished".utf8)

enum ConnectionEnd {
    case Client
    case Server
}

enum CipherType {
    case Block
    case Stream
}

enum BlockCipherMode {
    case CBC
}

enum MACAlgorithm {
    case HMAC_MD5
    case HMAC_SHA1
    case HMAC_SHA256
    case HMAC_SHA384
    case HMAC_SHA512
}

enum CipherAlgorithm
{
    case NULL
    case TRIPLE_DES
    case AES
}

enum KeyExchangeAlgorithm
{
    case RSA
    case DHE_RSA
}

enum PRFAlgorithm {
    case PRF_TLS_1_0
}



class TLSSecurityParameters
{
    var                     connectionEnd : ConnectionEnd = .Client
    var                     prfAlgorithm : PRFAlgorithm = .PRF_TLS_1_0
    var                     bulkCipherAlgorithm : CipherAlgorithm? = nil
    var                     cipherType : CipherType? = nil
    var                     encodeKeyLength : Int = 0
    var                     blockLength : Int = 0
    var                     fixedIVLength : Int = 0
    var                     recordIVLength : Int = 0
    var                     hmacDescriptor : HMACDescriptor? = nil
    var                     masterSecret : [UInt8]? = nil
    var                     clientRandom : [UInt8]? = nil
    var                     serverRandom : [UInt8]? = nil
    
    // Calculate master secret as described in RFC 2246, section 8.1, p. 46
    func calculateMasterSecret(preMasterSecret : [UInt8])
    {
        self.masterSecret = PRF(secret: preMasterSecret, label: [UInt8]("master secret".utf8), seed: self.clientRandom! + self.serverRandom!, outputLength: 48)
        print("master secret: \(hex(self.masterSecret!))")
    }
}



protocol TLSContextStateMachine
{
    func didSendMessage(message : TLSMessage)
    func didSendHandshakeMessage(message : TLSHandshakeMessage)
    func didSendChangeCipherSpec()
    func didReceiveChangeCipherSpec()
    func didReceiveHandshakeMessage(message : TLSHandshakeMessage)
}


public class TLSContext
{
    var protocolVersion : TLSProtocolVersion
    var negotiatedProtocolVersion : TLSProtocolVersion! = nil
    public var cipherSuites : [CipherSuite]?
    
    var cipherSuite : CipherSuite?
    
    var stateMachine : TLSContextStateMachine!
    
    var serverKey : CryptoKey?
    var clientKey : CryptoKey?
    
    var identity : Identity?
    
    var serverCertificates : [Certificate]?
    var clientCertificates : [Certificate]?
    
    var preMasterSecret     : [UInt8]? = nil {
        didSet {
            print("pre master secret = \(hex(preMasterSecret!))")
        }
    }

    var securityParameters  : TLSSecurityParameters
    
    var handshakeMessages : [TLSHandshakeMessage]
    
    let isClient : Bool
    
    var recordLayer : TLSRecordLayer!
    
    var dhKeyExchange : DiffieHellmanKeyExchange?
    
    private var connectionEstablishedCompletionBlock : ((error : TLSError?) -> ())?
    
    init(protocolVersion: TLSProtocolVersion, dataProvider : TLSDataProvider, isClient : Bool = true)
    {
        self.protocolVersion = protocolVersion
        self.isClient = isClient

        self.handshakeMessages = []
        
        self.securityParameters = TLSSecurityParameters()
        
        self.cipherSuites = [.TLS_RSA_WITH_AES_256_CBC_SHA]
        
        self.recordLayer = TLSRecordLayer(context: self, dataProvider: dataProvider)
        
        self.stateMachine = TLSStateMachine(context: self)
    }
    
    func copy() -> TLSContext
    {
        let context = TLSContext(protocolVersion: self.protocolVersion, dataProvider: self.recordLayer.dataProvider!, isClient: self.isClient)
        
        context.cipherSuites = self.cipherSuites
        context.cipherSuite = self.cipherSuite
        
        context.serverKey = self.serverKey
        context.clientKey = self.clientKey
        context.identity = self.identity
        
        context.serverCertificates = self.serverCertificates
        context.clientCertificates = self.clientCertificates
        
        
        if let preMasterSecret = self.preMasterSecret {
            context.preMasterSecret = preMasterSecret
        }
        
        context.securityParameters = self.securityParameters
        
        context.handshakeMessages = self.handshakeMessages

        return context
    }
    
    func startConnection(completionBlock : (error : TLSError?) -> ())
    {
        self.connectionEstablishedCompletionBlock = completionBlock
        
        self.sendClientHello()
        
        self.receiveNextTLSMessage(completionBlock)
    }
    
    func acceptConnection(completionBlock : (error : TLSError?) -> ())
    {
        self.connectionEstablishedCompletionBlock = completionBlock

        self.receiveNextTLSMessage(completionBlock)
    }
    
    func sendApplicationData(data : [UInt8], completionBlock : ((TLSDataProviderError?) -> ())? = nil)
    {
        self.recordLayer.sendData(contentType: .ApplicationData, data: data, completionBlock: completionBlock)
    }
    
    func sendMessage(message : TLSMessage, completionBlock : ((TLSDataProviderError?) -> ())? = nil)
    {
        self.recordLayer.sendMessage(message, completionBlock: completionBlock)
        
        switch message.contentType
        {
        case .Handshake:
            break

        default:
            self.stateMachine!.didSendMessage(message)
        }
    }
    
    func sendAlert(alert : TLSAlert, alertLevel : TLSAlertLevel, completionBlock : ((TLSDataProviderError?) -> ())? = nil)
    {
        let alertMessage = TLSAlertMessage(alert: alert, alertLevel: alertLevel)
        self.sendMessage(alertMessage, completionBlock: completionBlock)
    }
    
    private func sendHandshakeMessage(message : TLSHandshakeMessage, completionBlock : ((TLSDataProviderError?) -> ())? = nil)
    {
        self.sendMessage(message, completionBlock: completionBlock)
        
        self.handshakeMessages.append(message)
        
        self.stateMachine!.didSendHandshakeMessage(message)
    }
    
    func didReceiveHandshakeMessage(message : TLSHandshakeMessage)
    {
        if let clientHello = message as? TLSClientHello {
            print("TLS version: \(clientHello.clientVersion)")
            print("Supported Cipher Suites:")
            for cipherSuite in clientHello.cipherSuites {
                print("\(cipherSuite)")
            }
        }
    }
    
    func _didReceiveMessage(message : TLSMessage, completionBlock: ((TLSError?) -> ())?)
    {
        print((self.isClient ? "Client" : "Server" ) + ": did receive message \(TLSMessageNameForType(message.type))")

        switch (message.type)
        {
        case .ChangeCipherSpec:
            self.recordLayer.activateReadEncryptionParameters()
            
            self.stateMachine!.didReceiveChangeCipherSpec()
            
            self.receiveNextTLSMessage(completionBlock)
            
            break
            
        case .Handshake:
            let handshakeMessage = message as! TLSHandshakeMessage
            self._didReceiveHandshakeMessage(handshakeMessage, completionBlock: completionBlock)

        case .Alert:
            break
            
        case .ApplicationData:
            break
        }
    }

    func _didReceiveHandshakeMessage(message : TLSHandshakeMessage, completionBlock: ((TLSError?) -> ())?)
    {
        let tlsConnectCompletionBlock = completionBlock

        let handshakeType = message.handshakeType

        if (handshakeType != .Finished) {
            // don't add the incoming Finished message to handshakeMessages.
            // We need to verify it's data against the handshake messages before it.
            self.handshakeMessages.append(message)
        }
        
        switch (handshakeType)
        {
        case .ClientHello:
            let clientHello = (message as! TLSClientHello)
            self.securityParameters.clientRandom = DataBuffer(clientHello.random).buffer
            
            self.cipherSuite = self.selectCipherSuite(clientHello.cipherSuites)
            
            if self.cipherSuite == nil {
                self.sendAlert(.HandshakeFailure, alertLevel: .Fatal, completionBlock: nil)
            }
            
        case .ServerHello:
            let serverHello = message as! TLSServerHello
            let version = serverHello.version
            print("Server wants to speak \(version)")
            
            self.recordLayer.protocolVersion = version
            
            self.cipherSuite = serverHello.cipherSuite
            self.securityParameters.serverRandom = DataBuffer(serverHello.random).buffer
            if !serverHello.cipherSuite.needsServerKeyExchange()
            {
                self.preMasterSecret = DataBuffer(PreMasterSecret(clientVersion: self.protocolVersion)).buffer
                self.setPendingSecurityParametersForCipherSuite(serverHello.cipherSuite)
                self.recordLayer.pendingSecurityParameters = self.securityParameters
            }
            
        case .Certificate:
            let certificateMessage = message as! TLSCertificateMessage
            self.serverCertificates = certificateMessage.certificates
            self.serverKey = certificateMessage.publicKey
            
        case .ServerKeyExchange:
            let keyExchangeMessage = message as! TLSServerKeyExchange
            
            let p = BigInt(keyExchangeMessage.dh_p.reverse())
            let g = BigInt(keyExchangeMessage.dh_g.reverse())
            let Ys = BigInt(keyExchangeMessage.dh_Ys.reverse())
            
            let dhKeyExchange = DiffieHellmanKeyExchange(primeModulus: p, generator: g)
            dhKeyExchange.peerPublicValue = Ys
            self.dhKeyExchange = dhKeyExchange
            
        case .ServerHelloDone:
            break
            
        case .ClientKeyExchange:
            let clientKeyExchange = message as! TLSClientKeyExchange
            if let dhKeyExchange = self.dhKeyExchange {
                // Diffie-Hellman
                if let diffieHellmanPublicValue = clientKeyExchange.diffieHellmanPublicValue {
                    let secret = BigInt.random(dhKeyExchange.primeModulus)
                    dhKeyExchange.peerPublicValue = BigInt(diffieHellmanPublicValue.reverse())
                    self.preMasterSecret = BigIntImpl<UInt8>(dhKeyExchange.calculateSharedSecret(secret)!).parts.reverse()
                }
                else {
                    fatalError("Client Key Exchange has no encrypted master secret")
                }
            }
            else {
                // RSA
                if let encryptedPreMasterSecret = clientKeyExchange.encryptedPreMasterSecret {
                    self.preMasterSecret = self.identity!.privateKey.decrypt(encryptedPreMasterSecret)
                }
                else {
                    fatalError("Client Key Exchange has no encrypted master secret")
                }
            }
            
            
            self.setPendingSecurityParametersForCipherSuite(self.cipherSuite!)
            self.recordLayer.pendingSecurityParameters = self.securityParameters
            
        case .Finished:
            if (self.verifyFinishedMessage(message as! TLSFinished, isClient: !self.isClient)) {
                print((self.isClient ? "Client" : "Server" ) + ": Finished verified.")
                
                if !self.isClient {
                    self.handshakeMessages.append(message)
                }
                
                if let connectionEstablishedBlock = self.connectionEstablishedCompletionBlock {
                    connectionEstablishedBlock(error: nil)
                }
            }
            else {
                print("Error: could not verify Finished message.")
            }
            
        default:
            print("unsupported handshake \(handshakeType.rawValue)")
            if let block = tlsConnectCompletionBlock {
                block(TLSError.Error)
            }
        }

        self.stateMachine!.didReceiveHandshakeMessage(message)
    
        if handshakeType != .Finished {
            self.receiveNextTLSMessage(completionBlock)
        }
    }
    
    func sendClientHello()
    {
        let clientHelloRandom = Random()
        let clientHello = TLSClientHello(
            clientVersion: self.protocolVersion,
            random: clientHelloRandom,
            sessionID: nil,
            cipherSuites: self.cipherSuites!,
//            cipherSuites: [.TLS_RSA_WITH_NULL_SHA],
            compressionMethods: [.NULL])
        
        self.securityParameters.clientRandom = DataBuffer(clientHelloRandom).buffer
        self.sendHandshakeMessage(clientHello)
    }
    
    func sendServerHello()
    {
        let serverHelloRandom = Random()
        let serverHello = TLSServerHello(
            serverVersion: self.protocolVersion,
            random: serverHelloRandom,
            sessionID: nil,
            cipherSuite: self.cipherSuite!,
            compressionMethod: .NULL)
        
        self.securityParameters.serverRandom = DataBuffer(serverHelloRandom).buffer
        self.sendHandshakeMessage(serverHello)
    }
    
    func sendCertificate()
    {
        let certificate = self.identity!.certificate
        let certificateMessage = TLSCertificateMessage(certificates: [certificate])
        
        self.sendHandshakeMessage(certificateMessage);
    }
    
    func sendServerHelloDone()
    {
        self.sendHandshakeMessage(TLSServerHelloDone())
    }
    
    func sendClientKeyExchange()
    {
        if let diffieHellmanKeyExchange = self.dhKeyExchange {
            // Diffie-Hellman
            let secret = BigInt.random(diffieHellmanKeyExchange.primeModulus)
            let publicValue = diffieHellmanKeyExchange.calculatePublicValue(secret)
            let sharedSecret = diffieHellmanKeyExchange.calculateSharedSecret(secret)!
            self.preMasterSecret = BigIntImpl<UInt8>(sharedSecret).parts.reverse()
            self.setPendingSecurityParametersForCipherSuite(self.cipherSuite!)
            self.recordLayer.pendingSecurityParameters = self.securityParameters

            let message = TLSClientKeyExchange(diffieHellmanPublicValue: BigIntImpl<UInt8>(publicValue).parts.reverse())
            self.sendHandshakeMessage(message)
        }
        else {
            if let serverKey = self.serverKey {
                // RSA
                let message = TLSClientKeyExchange(preMasterSecret: self.preMasterSecret!, publicKey: serverKey)
                self.sendHandshakeMessage(message)
            }
        }
    }

    func sendChangeCipherSpec()
    {
        let message = TLSChangeCipherSpec()
        
        self.sendMessage(message)

        self.recordLayer.activateWriteEncryptionParameters()
        
        self.stateMachine!.didSendChangeCipherSpec()
    }
    
    func sendFinished()
    {
        let verifyData = self.verifyDataForFinishedMessage(isClient: self.isClient)
        print("send finished -> before messages: \(self.handshakeMessages)")

        self.sendHandshakeMessage(TLSFinished(verifyData: verifyData), completionBlock: nil)

        print("send finished -> after messages: \(self.handshakeMessages)")
    }

    private func verifyFinishedMessage(finishedMessage : TLSFinished, isClient: Bool) -> Bool
    {
        let verifyData = self.verifyDataForFinishedMessage(isClient: isClient)
        
        return finishedMessage.verifyData == verifyData
    }

    private func verifyDataForFinishedMessage(isClient isClient: Bool) -> [UInt8]
    {
        let finishedLabel = isClient ? TLSClientFinishedLabel : TLSServerFinishedLabel
        
        var handshakeData = [UInt8]()
        for message in self.handshakeMessages {
            if let messageData = message.rawHandshakeMessageData {
                handshakeData.appendContentsOf(messageData)
            }
            else {
                var messageBuffer = DataBuffer()
                message.writeTo(&messageBuffer)
                
                handshakeData.appendContentsOf(messageBuffer.buffer)
            }
        }
        
        let clientHandshakeMD5  = Hash_MD5(handshakeData)
        let clientHandshakeSHA1 = Hash_SHA1(handshakeData)
        
        let d = clientHandshakeMD5 + clientHandshakeSHA1

        let verifyData = PRF(secret: self.securityParameters.masterSecret!, label: finishedLabel, seed: d, outputLength: 12)
        
        return verifyData
    }
    
    
    private func receiveNextTLSMessage(completionBlock: ((TLSError?) -> ())?)
    {
//        let tlsConnectCompletionBlock = completionBlock
        
        self._readTLSMessage {
            (message : TLSMessage?) -> () in
            
            if let m = message {
                self._didReceiveMessage(m, completionBlock: completionBlock)
            }
        }
    }

    func readTLSMessage(completionBlock: (message : TLSMessage?) -> ())
    {
        self._readTLSMessage(completionBlock)
    }
    
    private func _readTLSMessage(completionBlock: (message : TLSMessage?) -> ())
    {
        self.recordLayer.readMessage(completionBlock: completionBlock)
    }
    
    private func setPendingSecurityParametersForCipherSuite(cipherSuite : CipherSuite)
    {
        let cipherSuiteDescriptor = TLSCipherSuiteDescriptorForCipherSuite(cipherSuite)
        let cipherAlgorithmDescriptor = cipherSuiteDescriptor.bulkCipherAlgorithm

        self.securityParameters.bulkCipherAlgorithm  = cipherAlgorithmDescriptor.algorithm
        self.securityParameters.encodeKeyLength      = cipherAlgorithmDescriptor.keySize
        self.securityParameters.blockLength          = cipherAlgorithmDescriptor.blockSize
        self.securityParameters.fixedIVLength        = cipherAlgorithmDescriptor.blockSize
        self.securityParameters.recordIVLength       = cipherAlgorithmDescriptor.blockSize
        self.securityParameters.hmacDescriptor       = cipherSuiteDescriptor.hmacDescriptor
        
        self.securityParameters.calculateMasterSecret(self.preMasterSecret!)
    }
    
    func selectCipherSuite(cipherSuites : [CipherSuite]) -> CipherSuite?
    {
        for clientCipherSuite in cipherSuites {
            for myCipherSuite in self.cipherSuites! {
                if clientCipherSuite == myCipherSuite {
                    return myCipherSuite
                }
            }
        }
        
        return nil
    }
}
