//
//  TLSContext.swift
//
//  Created by Nico Schmidt on 21.03.15.
//  Copyright (c) 2015 Nico Schmidt. All rights reserved.
//

import Foundation
import CommonCrypto

public enum CompressionMethod : UInt8 {
    case null = 0
}

enum HashAlgorithm : UInt8 {
    case none   = 0
    case md5    = 1
    case sha1   = 2
    case sha224 = 3
    case sha256 = 4
    case sha384 = 5
    case sha512 = 6
    
    var macAlgorithm: MACAlgorithm {
        switch self {
        case .md5:
            return .hmac_md5
            
        case .sha1:
            return .hmac_sha1
            
        case .sha256:
            return .hmac_sha256

        case .sha384:
            return .hmac_sha384

        case .sha512:
            return .hmac_sha512

        default:
            fatalError("HMAC with hash function \(self) is not supported.")
        }
    }
}

enum SignatureAlgorithm : UInt8 {
    case anonymous  = 0
    case rsa        = 1
    case dsa        = 2
    case ecdsa      = 3
}

struct TLSSignedData : Streamable
{
    var hashAlgorithm : HashAlgorithm?
    var signatureAlgorithm : SignatureAlgorithm?
    
    var signature : [UInt8]
    
    init(data: [UInt8], context: TLSContext)
    {
        if context.negotiatedProtocolVersion == .v1_2 {
            self.hashAlgorithm = context.configuration.hashAlgorithm
            self.signatureAlgorithm = context.configuration.signatureAlgorithm
        }
        
        self.signature = context.sign(data)
    }
    
    init?(inputStream : InputStreamType, context: TLSContext)
    {
        if context.negotiatedProtocolVersion == .v1_2 {
            guard
                let rawHashAlgorithm : UInt8 = inputStream.read(),
                let hashAlgorithm = HashAlgorithm(rawValue: rawHashAlgorithm),
                let rawSignatureAlgorithm : UInt8 = inputStream.read(),
                let signatureAlgorithm = SignatureAlgorithm(rawValue: rawSignatureAlgorithm)
            else {
                return nil
            }
            
            self.hashAlgorithm = hashAlgorithm
            self.signatureAlgorithm = signatureAlgorithm
        }
        
        if let signature : [UInt8] = inputStream.read16() {
            self.signature = signature
        }
        else {
            return nil
        }
    }
    
    func writeTo<Target : OutputStreamType>(_ target: inout Target)
    {
        if self.hashAlgorithm != nil && self.signatureAlgorithm != nil {
            target.write(self.hashAlgorithm!.rawValue)
            target.write(self.signatureAlgorithm!.rawValue)
        }
        
        target.write(UInt16(self.signature.count))
        target.write(self.signature)
    }
}

enum TLSError : Error
{
    case error(String)
    case alert(alert : TLSAlert, alertLevel : TLSAlertLevel)
}


protocol TLSDataProvider : class
{
    func writeData(_ data : [UInt8]) throws
    func readData(count : Int) throws -> [UInt8]
}

let TLSClientFinishedLabel = [UInt8]("client finished".utf8)
let TLSServerFinishedLabel = [UInt8]("server finished".utf8)

enum ConnectionEnd {
    case client
    case server
}

enum CipherType {
    case block
    case stream
    case aead
}

enum BlockCipherMode {
    case cbc
    case gcm
}

typealias HMACFunction = (_ secret : [UInt8], _ data : [UInt8]) -> [UInt8]
enum MACAlgorithm {
//    case null
    case hmac_md5
    case hmac_sha1
    case hmac_sha256
    case hmac_sha384
    case hmac_sha512
    
    var size: Int {
        get {
            switch self {
//            case .null:
//                fatalError("Null MAC has no size")

            case .hmac_md5:
                return Int(CC_MD5_DIGEST_LENGTH)
            
            case .hmac_sha1:
                return Int(CC_SHA1_DIGEST_LENGTH)

            case .hmac_sha256:
                return Int(CC_SHA256_DIGEST_LENGTH)

            case .hmac_sha384:
                return Int(CC_SHA384_DIGEST_LENGTH)
            
            case .hmac_sha512:
                return Int(CC_SHA512_DIGEST_LENGTH)
                
            }
        }
    }
}

enum CipherAlgorithm
{
    case null
    case aes128
    case aes256
    
    var blockSize : Int {
        get {
            switch self {
            case .null: return 0
            case .aes128: return 16
            case .aes256: return 16
            }
            
        }
    }
    
    var keySize : Int {
        get {
            switch self {
            case .null: return 0
            case .aes128: return 16
            case .aes256: return 32
            }
        }
    }
}

enum KeyExchangeAlgorithm
{
    case rsa
    case dhe
    case ecdhe
}

enum CertificateType
{
    case rsa
    case ecdsa
}

enum KeyExchange
{
    case rsa
    case dhe(DHKeyExchange)
    case ecdhe(ECDHKeyExchange)
}

class TLSSecurityParameters
{
    var connectionEnd : ConnectionEnd = .client
    var bulkCipherAlgorithm : CipherAlgorithm? = nil
    var blockCipherMode : BlockCipherMode? = nil
    var cipherType : CipherType = .block
    var encodeKeyLength : Int = 0
    var blockLength : Int = 0
    var fixedIVLength : Int = 0
    var recordIVLength : Int = 0
    var hmac: MACAlgorithm? = nil
    var masterSecret : [UInt8]? = nil
    var clientRandom : [UInt8]? = nil
    var serverRandom : [UInt8]? = nil {
        didSet {
            
        }
    }
    
    // secure renegotiation support (RFC 5746)
    var isUsingSecureRenegotiation: Bool = false
    var clientVerifyData: [UInt8] = []
    var serverVerifyData: [UInt8] = []
}



protocol TLSContextStateMachine
{
    func reset()
    func didSendMessage(_ message : TLSMessage) throws
    func didSendHandshakeMessage(_ message : TLSHandshakeMessage) throws
    func didSendChangeCipherSpec() throws
    func didReceiveChangeCipherSpec() throws
    func clientDidReceiveHandshakeMessage(_ message : TLSHandshakeMessage) throws
    func serverDidReceiveHandshakeMessage(_ message : TLSHandshakeMessage) throws
    func shouldContinueHandshakeWithMessage(_ message : TLSHandshakeMessage) -> Bool
    func didReceiveAlert(_ alert : TLSAlertMessage)
    func didConnect() throws
}

extension TLSContextStateMachine
{
    func reset() {}
    func didSendMessage(_ message : TLSMessage) throws {}
    func didSendHandshakeMessage(_ message : TLSHandshakeMessage) throws {}
    func didSendChangeCipherSpec() throws {}
    func didReceiveChangeCipherSpec() throws {}
    func clientDidReceiveHandshakeMessage(_ message : TLSHandshakeMessage) throws {}
    func serverDidReceiveHandshakeMessage(_ message : TLSHandshakeMessage) throws {}
    func shouldContinueHandshakeWithMessage(_ message : TLSHandshakeMessage) -> Bool
    {
        return true
    }
    func didReceiveAlert(_ alert : TLSAlertMessage) {}
    func didConnect() throws {}
}

public class TLSContext
{
    public var configuration : TLSConfiguration
    
    var negotiatedProtocolVersion : TLSProtocolVersion {
        didSet {
            self.recordLayer.protocolVersion = negotiatedProtocolVersion
        }
    }
    
    var hostNames : [String]?
    
    var cipherSuite : CipherSuite?
    var stateMachine : TLSContextStateMachine!
    
    var serverKey : RSA?
    var clientKey : RSA?
    
    var serverCertificates : [X509.Certificate]?
    var clientCertificates : [X509.Certificate]?
    
    var preMasterSecret     : [UInt8]? = nil
    
    var securityParameters  : TLSSecurityParameters
    
    var handshakeMessages : [TLSHandshakeMessage]
    
    var isClient : Bool
    
    var recordLayer : TLSRecordLayer!
    
    var keyExchange : KeyExchange
    
    var signer : Signing?

    // The current session, if there is one already
    var currentSession: TLSSession?
    
    // The session ID that will be used once the handshake is finished and the session
    // can be set up
    var pendingSessionID: TLSSessionID?
    
    // The saved sessions that the server can reuse when a client sends a sessionID
    // we know about from before
    var serverSessionCache: [TLSSessionID: TLSSession] = [:]
    
    // The client session cache is indexed by hostname and port concatenated to
    // a string "\(hostname):\(port)"
    var clientSessionCache: [String : TLSSession] = [:]

    var isReusingSession: Bool
    
    var isInitialHandshake: Bool = true
    var isRenegotiatingSecurityParameters: Bool = false
    
    var hashAlgorithm: HashAlgorithm = .sha256
    
    typealias HashFunction = ([UInt8]) -> [UInt8]
    var hashFunction: HashFunction {
        switch self.hashAlgorithm {
        case .sha256:
            return Hash_SHA256

        case .sha384:
            return Hash_SHA384
            
        default:
            fatalError("Unsupported hash function \(self.hashAlgorithm)")
        }
    }
    
    var hmac: HMACFunction {
        switch self.hashAlgorithm {
        case .sha256:
            return HMAC_SHA256
            
        case .sha384:
            return HMAC_SHA384
            
        default:
            fatalError("Unsupported HMAC hash function \(self.hashAlgorithm)")
        }
    }
    
    private var connectionEstablishedCompletionBlock : ((_ error : TLSError?) -> ())?

    init(configuration: TLSConfiguration, dataProvider : TLSDataProvider? = nil, isClient : Bool = true)
    {
        self.configuration = configuration
        if !isClient {
            if let identity = self.configuration.identity {
                // we are currently only supporting RSA
                if let rsa = identity.rsa {
                    self.signer = rsa
                }
            }
        }
        
        self.negotiatedProtocolVersion = configuration.protocolVersion
        self.isClient = isClient
        self.handshakeMessages = []
        self.securityParameters = TLSSecurityParameters()
        self.keyExchange = .rsa
        self.isReusingSession = false
        
        if let dataProvider = dataProvider {
            self.recordLayer = TLSRecordLayer(context: self, dataProvider: dataProvider)
        }
        self.stateMachine = TLSStateMachine(context: self)
    }
    
    func reset() {
        self.currentSession = nil
        self.pendingSessionID = nil
        
        self.isInitialHandshake = true
        
        self.negotiatedProtocolVersion = configuration.protocolVersion
        self.handshakeMessages = []
        self.securityParameters = TLSSecurityParameters()
        self.keyExchange = .rsa
        
        self.recordLayer = TLSRecordLayer(context: self, dataProvider: self.recordLayer.dataProvider!)
        self.stateMachine = TLSStateMachine(context: self)
    }
    
    func startConnection() throws
    {
        reset()
        
        try self.sendClientHello()
        try self.receiveNextTLSMessage()
        
        try self.didConnect()
        
        self.handshakeMessages = []
    }
    
    func acceptConnection() throws
    {
        reset()
        
        try self.receiveNextTLSMessage()
        
        try self.didConnect()
        
        self.handshakeMessages = []
    }
    
    func didConnect() throws
    {
        print("Connection established.")
        try self.stateMachine.didConnect()
    }
    
    func didRenegotiate()
    {
        print("Renegotiated security parameters successfully.")
    }

    
    func sendApplicationData(_ data : [UInt8]) throws
    {
        try self.recordLayer.sendData(contentType: .applicationData, data: data)
    }
    
    func sendMessage(_ message : TLSMessage) throws
    {
        try self.recordLayer.sendMessage(message)
        
        switch message.contentType
        {
        case .handshake:
            break

        default:
            try self.stateMachine!.didSendMessage(message)
        }
    }
    
    func sendAlert(_ alert : TLSAlert, alertLevel : TLSAlertLevel) throws
    {
        let alertMessage = TLSAlertMessage(alert: alert, alertLevel: alertLevel)
        try self.sendMessage(alertMessage)
    }
    
    func abortHandshake() throws
    {
        try self.sendAlert(.handshakeFailure, alertLevel: .fatal)
        throw TLSError.alert(alert: .handshakeFailure, alertLevel: .fatal)
    }
    
    private func sendHandshakeMessage(_ message : TLSHandshakeMessage) throws
    {
        try self.sendMessage(message)
        self.handshakeMessages.append(message)
        try self.stateMachine!.didSendHandshakeMessage(message)
    }
    
    func didReceiveHandshakeMessage(_ message : TLSHandshakeMessage)
    {
        if let clientHello = message as? TLSClientHello {
            print("TLS version: \(clientHello.clientVersion)")
            print("Supported Cipher Suites:")
            for cipherSuite in clientHello.cipherSuites {
                print("\(cipherSuite)")
            }
        }
    }
    
    func _didReceiveMessage(_ message : TLSMessage) throws
    {
        print((self.isClient ? "Client" : "Server" ) + ": did receive message \(TLSMessageNameForType(message.type))")

        switch (message.type)
        {
        case .changeCipherSpec:
            self.recordLayer.activateReadEncryptionParameters()
            try self.stateMachine!.didReceiveChangeCipherSpec()
            try self.receiveNextTLSMessage()
            
            break
            
        case .handshake:
            let handshakeMessage = message as! TLSHandshakeMessage
            if self.stateMachine.shouldContinueHandshakeWithMessage(handshakeMessage) {
                try self._didReceiveHandshakeMessage(handshakeMessage)
            }

        case .alert:
            let alert = message as! TLSAlertMessage
            self.stateMachine.didReceiveAlert(alert)
            if alert.alertLevel == .fatal {
                throw TLSError.alert(alert: alert.alert, alertLevel: alert.alertLevel)
            }
            
            break
            
        case .applicationData:
            break
        }
    }

    func handleClientHandshakeMessage(_ message : TLSHandshakeMessage) throws
    {
        let handshakeType = message.handshakeType

        switch (handshakeType)
        {
        case .serverHello:
            let serverHello = message as! TLSServerHello
            let version = serverHello.version
            print("Server wants to speak \(version)")
            
            if version < self.configuration.minimumFallbackVersion {
                try abortHandshake()
            }
            
            self.recordLayer.protocolVersion = version
            self.negotiatedProtocolVersion = version
            
            self.cipherSuite = serverHello.cipherSuite
            self.securityParameters.serverRandom = DataBuffer(serverHello.random).buffer
            
            print("ServerHello extensions = \(serverHello.extensions)")
            
            if let secureRenegotiationInfo = serverHello.extensions.filter({$0 is TLSSecureRenegotiationInfoExtension}).first as? TLSSecureRenegotiationInfoExtension {
                print("Client setting secure renegotiation")
                self.securityParameters.isUsingSecureRenegotiation = true
                
                if self.isInitialHandshake {
                    if secureRenegotiationInfo.renegotiatedConnection.count != 0 {
                        try abortHandshake()
                    }
                }
                else {
                    if secureRenegotiationInfo.renegotiatedConnection != self.securityParameters.clientVerifyData + self.securityParameters.serverVerifyData {
                        try abortHandshake()
                    }
                }
            }
            else {
                if !isInitialHandshake && self.securityParameters.isUsingSecureRenegotiation {
                    // When we are using secure renegotiation and the server hello doesn't include
                    // the extension, we need to abort the handshake
                    try abortHandshake()
                }
                self.securityParameters.isUsingSecureRenegotiation = false
            }
            
            if let sessionID = serverHello.sessionID {
                if  let pendingSessionID = self.pendingSessionID,
                    sessionID == pendingSessionID {
                    let hostname = hostNames!.first!
                    let session = clientSessionCache[hostname]!
                    if session.sessionID == sessionID {
                        self.currentSession = session
                        self.isReusingSession = true
                        setPendingSecurityParametersForCipherSuite(session.cipherSpec)
                    }
                    else {
                        fatalError("Session lost. This should not be possible.")
                    }
                }
                else {
                    self.pendingSessionID = sessionID
                }
                print("Session ID: \(sessionID.sessionID)")
            }

            if currentSession == nil && !serverHello.cipherSuite.needsServerKeyExchange()
            {
                let preMasterSecret = DataBuffer(PreMasterSecret(clientVersion: self.configuration.protocolVersion)).buffer
                self.setPreMasterSecretAndCommitSecurityParameters(preMasterSecret, cipherSuite: serverHello.cipherSuite)
            }
            
        case .certificate:
            let certificateMessage = message as! TLSCertificateMessage
            self.serverCertificates = certificateMessage.certificates
            self.serverKey = serverCertificates!.first!.rsa
            
        case .serverKeyExchange:
            let keyExchangeMessage = message as! TLSServerKeyExchange
            
            switch keyExchangeMessage.parameters {
            
            case .dhe(let diffieHellmanParameters):
                
                let p = diffieHellmanParameters.p
                let g = diffieHellmanParameters.g
                let Ys = diffieHellmanParameters.Ys
                
                let dhKeyExchange = DHKeyExchange(primeModulus: p, generator: g)
                dhKeyExchange.peerPublicKey = Ys
                
                self.keyExchange = .dhe(dhKeyExchange)
            
            case .ecdhe(let ecdhParameters):
                if ecdhParameters.curveType != .namedCurve {
                    throw TLSError.error("Unsupported curve type \(ecdhParameters.curveType)")
                }
                
                guard
                    let namedCurve = ecdhParameters.namedCurve,
                    let curve = EllipticCurve.named(namedCurve)
                    else {
                        throw TLSError.error("Unsupported curve \(ecdhParameters.namedCurve)")
                }
                print("Using curve \(namedCurve)")
                
                let ecdhKeyExchange = ECDHKeyExchange(curve: curve)
                ecdhKeyExchange.peerPublicKey = ecdhParameters.publicKey
                self.keyExchange = .ecdhe(ecdhKeyExchange)
            }
            
            // verify signature
            if let certificate = self.serverCertificates?.first {
                if let rsa = certificate.publicKeySigner {
                    let signedData = keyExchangeMessage.signedParameters
                    var data = self.securityParameters.clientRandom!
                    data += self.securityParameters.serverRandom!
                    data += keyExchangeMessage.parametersData
                    
                    if !rsa.verify(signature: signedData.signature, data: data) {
                        throw TLSError.error("Signature error on server key exchange")
                    }
                }
            }
            
        case .serverHelloDone:
            break
            
        case .finished:
            if (self.verifyFinishedMessage(message as! TLSFinished, isClient: false, saveForSecureRenegotiation: true)) {
                print("Client: Finished verified.")
                if self.isRenegotiatingSecurityParameters {
                    print("Client: Renegotiated security parameters successfully.")
                    self.isRenegotiatingSecurityParameters = false
                }
                
                if currentSession != nil {
                    self.handshakeMessages.append(message)
                    
                    try self.stateMachine!.clientDidReceiveHandshakeMessage(message)

                    try self.sendChangeCipherSpec()
                    
                    return
                }
                else if let sessionID = self.pendingSessionID {
                    if let hostname = hostNames?.first {
                        let session = TLSSession(sessionID: sessionID, cipherSpec: self.cipherSuite!, masterSecret: self.securityParameters.masterSecret!)
                        clientSessionCache[hostname] = session
                        print("Save session for \(hostname)")
                    }
                }

            }
            else {
                print("Error: could not verify Finished message.")
                try sendAlert(.decryptionFailed, alertLevel: .fatal)
            }
            
        default:
            throw TLSError.error("Unsupported handshake \(handshakeType.rawValue)")
        }
    
        try self.stateMachine!.clientDidReceiveHandshakeMessage(message)
    }
    
    func handleServerHandshakeMessage(_ message : TLSHandshakeMessage) throws
    {
        let handshakeType = message.handshakeType

        switch (handshakeType)
        {
        case .clientHello:
            let clientHello = (message as! TLSClientHello)
            
            if clientHello.clientVersion < self.configuration.minimumFallbackVersion {
                try abortHandshake()
            }

            // Secure Renegotiation
            let clientHelloContainsEmptyRenegotiationSCSV = clientHello.cipherSuites.contains(.TLS_EMPTY_RENEGOTIATION_INFO_SCSV)
            let secureRenegotiationInfo = clientHello.extensions.filter({$0 is TLSSecureRenegotiationInfoExtension}).first as? TLSSecureRenegotiationInfoExtension
            
            print("CLientHello extensions: \(clientHello.extensions)")
            if self.isInitialHandshake {
                // RFC 5746, Section 3.6
                if clientHelloContainsEmptyRenegotiationSCSV {
                    self.securityParameters.isUsingSecureRenegotiation = true
                }
                else if let secureRenegotiationInfo = secureRenegotiationInfo {
                    if secureRenegotiationInfo.renegotiatedConnection.count == 0 {
                        self.securityParameters.isUsingSecureRenegotiation = true
                    }
                    else {
                        // abort handshake if the renegotiationInfo isn't empty
                        try abortHandshake()
                    }
                }
                else {
                    self.securityParameters.isUsingSecureRenegotiation = false
                }
            }
            else if self.securityParameters.isUsingSecureRenegotiation {
                // Renegotiated handshake (RFC 5746, Section 3.7)
                if clientHelloContainsEmptyRenegotiationSCSV {
                    try abortHandshake()
                }
                else if let secureRenegotiationInfo = secureRenegotiationInfo {
                    if secureRenegotiationInfo.renegotiatedConnection.count == 0 {
                        try abortHandshake()
                    }
                    else {
                        if secureRenegotiationInfo.renegotiatedConnection != self.securityParameters.clientVerifyData {
                            try abortHandshake()
                        }
                        
                        self.isRenegotiatingSecurityParameters = true
                    }
                }
                else {
                    // abort if secureRenegotiationInfo is missing
                    try abortHandshake()
                }
            }
            else {
                print("Renegotiation initiated")

                self.securityParameters.isUsingSecureRenegotiation = false
            }

            
            self.negotiatedProtocolVersion = clientHello.clientVersion
            self.securityParameters.clientRandom = DataBuffer(clientHello.random).buffer
            
            self.cipherSuite = self.selectCipherSuite(clientHello.cipherSuites)
            
            if self.cipherSuite == nil {
                try self.sendAlert(.handshakeFailure, alertLevel: .fatal)
                throw TLSError.error("No shared cipher suites. Client supports:" + clientHello.cipherSuites.map({"\($0)"}).reduce("", {$0 + "\n" + $1}))
            }
            else {
                print("Selected cipher suite is \(self.cipherSuite!)")
            }
            
            print("client hello session ID: \(clientHello.sessionID)")
            if let sessionID = clientHello.sessionID {
                if let session = self.serverSessionCache[sessionID] {
                    print("Using cached session ID: \(sessionID.sessionID)")
                    self.currentSession = session
                    self.isReusingSession = true
                }
            }
            
        case .clientKeyExchange:
            let clientKeyExchange = message as! TLSClientKeyExchange
            var preMasterSecret : [UInt8]
            
            
            switch self.keyExchange {
                
            case .dhe(let dhKeyExchange):
                // Diffie-Hellman
                if let diffieHellmanPublicKey = clientKeyExchange.diffieHellmanPublicKey {
                    dhKeyExchange.peerPublicKey = diffieHellmanPublicKey
                    preMasterSecret = dhKeyExchange.calculateSharedSecret()!.asBigEndianData()
                }
                else {
                    fatalError("Client Key Exchange has no DH public key")
                }
            
            case .ecdhe(let ecdhKeyExchange):
                if let ecdhPublicKey = clientKeyExchange.ecdhPublicKey {
                    ecdhKeyExchange.peerPublicKey = ecdhPublicKey
                    preMasterSecret = ecdhKeyExchange.calculateSharedSecret()!.asBigEndianData()
                }
                else {
                    fatalError("Client Key Exchange has no ECDH public key")
                }
            
            case .rsa:
                // RSA
                if let encryptedPreMasterSecret = clientKeyExchange.encryptedPreMasterSecret {
                    preMasterSecret = self.configuration.identity!.rsa!.decrypt(encryptedPreMasterSecret)
                }
                else {
                    fatalError("Client Key Exchange has no encrypted master secret")
                }
            }
            
            self.setPreMasterSecretAndCommitSecurityParameters(preMasterSecret)
            
        case .finished:
            if (self.verifyFinishedMessage(message as! TLSFinished, isClient: true, saveForSecureRenegotiation: true)) {
                print("Server: Finished verified.")
                if self.isRenegotiatingSecurityParameters {
                    print("Server: Renegotiated security parameters successfully.")
                    self.isRenegotiatingSecurityParameters = false
                }

                if let sessionID = self.pendingSessionID {
                    let session = TLSSession(sessionID: sessionID, cipherSpec: self.cipherSuite!, masterSecret: self.securityParameters.masterSecret!)
                    serverSessionCache[sessionID] = session
                    print("Save session \(session)")
                }

                self.handshakeMessages.append(message)
            }
            else {
                print("Error: could not verify Finished message.")
                try sendAlert(.decryptionFailed, alertLevel: .fatal)
            }
            
        default:
            throw TLSError.error("Unsupported handshake \(handshakeType.rawValue)")
        }

        try self.stateMachine!.serverDidReceiveHandshakeMessage(message)
    }

    func _didReceiveHandshakeMessage(_ message : TLSHandshakeMessage) throws
    {
        let handshakeType = message.handshakeType

        self.didReceiveHandshakeMessage(message)
        
        if (handshakeType != .finished) {
            // don't add the incoming Finished message to handshakeMessages.
            // We need to verify it's data against the handshake messages before it.
            self.handshakeMessages.append(message)
        }
        
        if self.isClient {
            try self.handleClientHandshakeMessage(message)
        }
        else {
            try self.handleServerHandshakeMessage(message)
        }
        
        if handshakeType != .finished {
            try self.receiveNextTLSMessage()
        }
    }
    
    func sendClientHello() throws
    {
        // reset current pending session ID
        self.pendingSessionID = nil
        self.currentSession = nil
        self.isReusingSession = false
        
        self.handshakeMessages = []

        var cipherSuites = self.configuration.cipherSuites
        if self.isInitialHandshake {
            // Only the initial handshake may contain the empty renegotiation info signalling cipher suite
            if !cipherSuites.contains(.TLS_EMPTY_RENEGOTIATION_INFO_SCSV) {
                cipherSuites.append(.TLS_EMPTY_RENEGOTIATION_INFO_SCSV)
            }
        }
        else {
            self.isRenegotiatingSecurityParameters = self.securityParameters.isUsingSecureRenegotiation
        }

//        if !self.isRenegotiatingSecurityParameters {
            if let hostname = self.hostNames?.first {
                self.pendingSessionID = clientSessionCache[hostname]?.sessionID
            }
//        }
        
        let clientHelloRandom = Random()
        let clientHello = TLSClientHello(
            clientVersion: self.configuration.protocolVersion,
            random: clientHelloRandom,
            sessionID: pendingSessionID,
            cipherSuites: cipherSuites,
            compressionMethods: [.null])
        
        if self.hostNames != nil {
            clientHello.extensions.append(TLSServerNameExtension(serverNames: self.hostNames!))
        }
        
        print("initial handshake = \(self.isInitialHandshake), secure renegotiation = \(self.securityParameters.isUsingSecureRenegotiation)")
        if self.isRenegotiatingSecurityParameters {
            clientHello.extensions.append(TLSSecureRenegotiationInfoExtension(renegotiatedConnection: self.securityParameters.clientVerifyData))
            print("ClientHello extensions = \(clientHello.extensions)")
        }
        
        if self.configuration.cipherSuites.contains(where: { if let descriptor = TLSCipherSuiteDescriptorForCipherSuite($0) { return descriptor.keyExchangeAlgorithm == .ecdhe} else { return false } }) {
            clientHello.extensions.append(TLSEllipticCurvesExtension(ellipticCurves: [.secp256r1, .secp521r1]))
            clientHello.extensions.append(TLSEllipticCurvePointFormatsExtension(ellipticCurvePointFormats: [.uncompressed]))
        }
        
        self.isInitialHandshake = false
        
        self.securityParameters.clientRandom = DataBuffer(clientHelloRandom).buffer
        try self.sendHandshakeMessage(clientHello)
    }
    
    func sendServerHello() throws
    {
        var sessionID: TLSSessionID
        if let session = currentSession {
            sessionID = session.sessionID
        }
        else {
            // create new session id
            repeat {
                sessionID = TLSSessionID.new()
            } while serverSessionCache[sessionID] != nil
            
            self.pendingSessionID = sessionID
        }
        
        let serverHelloRandom = Random()
        let serverHello = TLSServerHello(
            serverVersion: self.negotiatedProtocolVersion,
            random: serverHelloRandom,
            sessionID: sessionID,
            cipherSuite: self.cipherSuite!,
            compressionMethod: .null)
        
        if self.securityParameters.isUsingSecureRenegotiation {
            if self.isInitialHandshake {
                serverHello.extensions.append(TLSSecureRenegotiationInfoExtension())
            }
            else {
                let renegotiationInfo = self.securityParameters.clientVerifyData + self.securityParameters.serverVerifyData
                serverHello.extensions.append(TLSSecureRenegotiationInfoExtension(renegotiatedConnection: renegotiationInfo))
            }
        }
        
        print("ServerHello extensions = \(serverHello.extensions)")

        self.securityParameters.serverRandom = DataBuffer(serverHelloRandom).buffer
        if let session = currentSession {
            setPendingSecurityParametersForCipherSuite(session.cipherSpec)
        }
        
        self.isInitialHandshake = false

        try self.sendHandshakeMessage(serverHello)
        
        usleep(300000)
    }
    
    func renegotiate() throws
    {
        if self.isClient {
            try sendClientHello()
            try self.readTLSMessage()
            
            self.didRenegotiate()
        }
    }
    
    func sendCertificate() throws
    {
        let certificates = self.configuration.identity!.certificateChain
        let certificateMessage = TLSCertificateMessage(certificates: certificates)
        
        try self.sendHandshakeMessage(certificateMessage);
    }
    
    func sendServerHelloDone() throws
    {
        try self.sendHandshakeMessage(TLSServerHelloDone())
    }
    
    func sendServerKeyExchange() throws
    {
        guard let cipherSuiteDescriptor = TLSCipherSuiteDescriptorForCipherSuite(self.cipherSuite!) else {
            throw TLSError.error("No cipher suite")
        }
        
        switch cipherSuiteDescriptor.keyExchangeAlgorithm
        {
        case .dhe:
            guard var dhParameters = self.configuration.dhParameters else {
                throw TLSError.error("No DH parameters set in configuration")
            }
            
            let dhKeyExchange = DHKeyExchange(dhParameters: dhParameters)

            // use new public key for each key exchange
            dhParameters.Ys = dhKeyExchange.calculatePublicKey()
            
            self.keyExchange = .dhe(dhKeyExchange)
            
            let message = TLSServerKeyExchange(dhParameters: dhParameters, context: self)
            try self.sendHandshakeMessage(message)
            
        case .ecdhe:
            guard var ecdhParameters = self.configuration.ecdhParameters else {
                throw TLSError.error("No ECDH parameters set in configuration")
            }

            let ecdhKeyExchange = ECDHKeyExchange(curve: ecdhParameters.curve)
            let Q = ecdhKeyExchange.calculatePublicKey()
            self.keyExchange = .ecdhe(ecdhKeyExchange)
            
            ecdhParameters.publicKey = Q
            let message = TLSServerKeyExchange(ecdhParameters: ecdhParameters, context:self)
            try self.sendHandshakeMessage(message)
            break
            
        default:
            throw TLSError.error("Cipher suite \(self.cipherSuite) doesn't need server key exchange")
        }
    }

    func sendClientKeyExchange() throws
    {
        switch self.keyExchange {
        case .dhe(let diffieHellmanKeyExchange):
            // Diffie-Hellman
            let publicKey = diffieHellmanKeyExchange.calculatePublicKey()
            let sharedSecret = diffieHellmanKeyExchange.calculateSharedSecret()!

            self.setPreMasterSecretAndCommitSecurityParameters(sharedSecret.asBigEndianData())
            
            let message = TLSClientKeyExchange(diffieHellmanPublicKey: publicKey)
            try self.sendHandshakeMessage(message)
        
        case .ecdhe(let ecdhKeyExchange):
            let Q = ecdhKeyExchange.calculatePublicKey()
            let sharedSecret = ecdhKeyExchange.calculateSharedSecret()!
            
            self.setPreMasterSecretAndCommitSecurityParameters(sharedSecret.asBigEndianData())
            
            let message = TLSClientKeyExchange(ecdhPublicKey: Q)
            try self.sendHandshakeMessage(message)
        
        case .rsa:
            if let rsa = self.serverKey {
                // RSA
                let message = TLSClientKeyExchange(preMasterSecret: self.preMasterSecret!, rsa: rsa)
                try self.sendHandshakeMessage(message)
            }
        }
    }

    func sendChangeCipherSpec() throws
    {
        let message = TLSChangeCipherSpec()
        try self.sendMessage(message)
        self.recordLayer.activateWriteEncryptionParameters()
        try self.stateMachine!.didSendChangeCipherSpec()
    }
    
    func sendFinished() throws
    {
        let verifyData = self.verifyDataForFinishedMessage(isClient: self.isClient)
        if self.securityParameters.isUsingSecureRenegotiation {
            saveVerifyDataForSecureRenegotiation(data: verifyData, forClient: self.isClient)
        }
        try self.sendHandshakeMessage(TLSFinished(verifyData: verifyData))
    }

    func saveVerifyDataForSecureRenegotiation(data: [UInt8], forClient isClient: Bool)
    {
        if self.securityParameters.isUsingSecureRenegotiation {
            if isClient {
                self.securityParameters.clientVerifyData = data
            }
            else {
                self.securityParameters.serverVerifyData = data
            }
        }
    }

    private func verifyFinishedMessage(_ finishedMessage : TLSFinished, isClient: Bool, saveForSecureRenegotiation: Bool) -> Bool
    {
        guard finishedMessage.verifyData == self.verifyDataForFinishedMessage(isClient: isClient) else {
            return false
        }

        if saveForSecureRenegotiation {
            saveVerifyDataForSecureRenegotiation(data: finishedMessage.verifyData, forClient: isClient)
        }
        
        return true
    }

    private func verifyDataForFinishedMessage(isClient: Bool) -> [UInt8]
    {
        let finishedLabel = isClient ? TLSClientFinishedLabel : TLSServerFinishedLabel
        
        var handshakeData = [UInt8]()
        for message in self.handshakeMessages {
            let handshakeMessageData : [UInt8]
            if let messageData = message.rawHandshakeMessageData {
                handshakeMessageData = messageData
            }
            else {
                var messageBuffer = DataBuffer()
                message.writeTo(&messageBuffer)
                
                handshakeMessageData = messageBuffer.buffer
            }

            handshakeData.append(contentsOf: handshakeMessageData)

        }
        
        if self.negotiatedProtocolVersion < TLSProtocolVersion.v1_2 {
            let clientHandshakeMD5  = Hash_MD5(handshakeData)
            let clientHandshakeSHA1 = Hash_SHA1(handshakeData)
            
            let seed = clientHandshakeMD5 + clientHandshakeSHA1
            
            return PRF(secret: self.securityParameters.masterSecret!, label: finishedLabel, seed: seed, outputLength: 12)
        }
        else {
            let clientHandshake = self.hashFunction(handshakeData)

            assert(self.securityParameters.masterSecret != nil)
            
            return PRF(secret: self.securityParameters.masterSecret!, label: finishedLabel, seed: clientHandshake, outputLength: 12)
        }
    }
    
    internal func sign(_ data : [UInt8]) -> [UInt8]
    {
        guard let signer = self.signer else {
            fatalError("Unsupported signature algorithm \(self.configuration.signatureAlgorithm)")
        }
        
        return signer.sign(data: data, hashAlgorithm: self.configuration.hashAlgorithm)
    }
    
    internal func PRF(secret : [UInt8], label : [UInt8], seed : [UInt8], outputLength : Int) -> [UInt8]
    {
        if self.negotiatedProtocolVersion < TLSProtocolVersion.v1_2 {
            /// PRF function as defined in RFC 2246, section 5, p. 12

            let halfSecretLength = secret.count / 2
            let S1 : [UInt8]
            let S2 : [UInt8]
            if (secret.count % 2 == 0) {
                S1 = [UInt8](secret[0..<halfSecretLength])
                S2 = [UInt8](secret[halfSecretLength..<secret.count])
            }
            else {
                S1 = [UInt8](secret[0..<halfSecretLength + 1])
                S2 = [UInt8](secret[halfSecretLength..<secret.count])
            }
            
            assert(S1.count == S2.count)
            
            var md5data  = P_hash(HMAC_MD5,  secret: S1, seed: label + seed, outputLength: outputLength)
            var sha1data = P_hash(HMAC_SHA1, secret: S2, seed: label + seed, outputLength: outputLength)
            
            var output = [UInt8](repeating: 0, count: outputLength)
            for i in 0 ..< output.count
            {
                output[i] = md5data[i] ^ sha1data[i]
            }
            
            return output
        }
        else {
            return P_hash(self.hmac, secret: secret, seed: label + seed, outputLength: outputLength)
        }
    }
    
    private func receiveNextTLSMessage() throws
    {
        let message = try self._readTLSMessage()

        try self._didReceiveMessage(message)
    }

    func readTLSMessage() throws -> TLSMessage
    {
        while true {
            let message = try self._readTLSMessage()
            
            if message.contentType == .applicationData {
                return message
            }
            
            try self._didReceiveMessage(message)
        }
    }
    
    private func _readTLSMessage() throws -> TLSMessage
    {
        return try self.recordLayer.readMessage()
    }
    
    private func setPreMasterSecretAndCommitSecurityParameters(_ preMasterSecret : [UInt8], cipherSuite : CipherSuite? = nil)
    {
        var cipherSuite = cipherSuite
        if cipherSuite == nil {
            cipherSuite = self.cipherSuite
        }
        
        self.cipherSuite = cipherSuite
        self.preMasterSecret = preMasterSecret
        self.setPendingSecurityParametersForCipherSuite(cipherSuite!)
    }
    
    private func setPendingSecurityParametersForCipherSuite(_ cipherSuite : CipherSuite)
    {
        guard let cipherSuiteDescriptor = TLSCipherSuiteDescriptorForCipherSuite(cipherSuite)
        else {
            fatalError("Unkown cipher suite \(cipherSuite)")
        }
        let cipherAlgorithm = cipherSuiteDescriptor.bulkCipherAlgorithm

        self.securityParameters.bulkCipherAlgorithm = cipherAlgorithm
        self.securityParameters.blockCipherMode     = cipherSuiteDescriptor.blockCipherMode
        self.securityParameters.cipherType          = cipherSuiteDescriptor.cipherType
        self.securityParameters.encodeKeyLength     = cipherAlgorithm.keySize
        self.securityParameters.blockLength         = cipherAlgorithm.blockSize
        self.securityParameters.fixedIVLength       = cipherSuiteDescriptor.fixedIVLength
        self.securityParameters.recordIVLength      = cipherSuiteDescriptor.recordIVLength
        self.securityParameters.hmac                = cipherSuiteDescriptor.hashFunction.macAlgorithm
        
        var useConfiguredHashFunctionForPRF = self.securityParameters.blockCipherMode! == .gcm || cipherSuiteDescriptor.keyExchangeAlgorithm == .ecdhe
        
        switch cipherSuiteDescriptor.hashFunction
        {
        case .sha256, .sha384:
            break
            
        default:
            useConfiguredHashFunctionForPRF = false
        }
        
        if !useConfiguredHashFunctionForPRF {
            // for non GCM or ECDHE cipher suites TLS 1.2 uses SHA256 for its PRF
            self.hashAlgorithm = .sha256
        }
        else {
            switch cipherSuiteDescriptor.hashFunction {
            case .sha256:
                self.hashAlgorithm = .sha256
                
            case .sha384:
                self.hashAlgorithm = .sha384
                
            default:
                print("Error: cipher suite \(cipherSuite) has \(cipherSuiteDescriptor.hashFunction)")
                fatalError("AEAD cipher suites can only use SHA256 or SHA384")
                break
            }
        }
        
        if let session = currentSession {
            self.securityParameters.masterSecret = session.masterSecret
        }
        else {
            self.securityParameters.masterSecret = calculateMasterSecret()
        }
        self.recordLayer.pendingSecurityParameters = self.securityParameters
    }
    
    // Calculate master secret as described in RFC 2246, section 8.1, p. 46
    private func calculateMasterSecret() -> [UInt8]
    {
        return PRF(secret: self.preMasterSecret!, label: [UInt8]("master secret".utf8), seed: self.securityParameters.clientRandom! + self.securityParameters.serverRandom!, outputLength: 48)
    }

    func selectCipherSuite(_ cipherSuites : [CipherSuite]) -> CipherSuite?
    {
        for clientCipherSuite in cipherSuites {
            for myCipherSuite in self.configuration.cipherSuites {
                if clientCipherSuite == myCipherSuite {
                    return myCipherSuite
                }
            }
        }
        
        return nil
    }
}
