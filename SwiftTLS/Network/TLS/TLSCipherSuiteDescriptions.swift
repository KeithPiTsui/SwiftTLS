//
//  TLSCipherDescriptions.swift
//  SwiftTLS
//
//  Created by Nico Schmidt on 12.04.15.
//  Copyright (c) 2015 Nico Schmidt. All rights reserved.
//

import Foundation
import CommonCrypto

struct HMACDescriptor {
    var algorithm   : MACAlgorithm
    var size        : Int
}

struct CipherSuiteDescriptor {
    var cipherSuite : CipherSuite
    
    var keyExchangeAlgorithm : KeyExchangeAlgorithm
    var certificateType : CertificateType
    var bulkCipherAlgorithm : CipherAlgorithm
    var cipherType : CipherType
    var blockCipherMode : BlockCipherMode?
    var fixedIVLength : Int
    var recordIVLength : Int
    var hmacDescriptor : HMACDescriptor
    
    init(cipherSuite: CipherSuite,
         keyExchangeAlgorithm : KeyExchangeAlgorithm,
         certificateType : CertificateType = .RSA,
         bulkCipherAlgorithm : CipherAlgorithm,
         cipherType : CipherType,
         blockCipherMode : BlockCipherMode? = nil,
         fixedIVLength : Int = 0,
         recordIVLength : Int = 0,
         hmacDescriptor : HMACDescriptor? = nil
    )
    {
        self.cipherSuite = cipherSuite
        self.keyExchangeAlgorithm = keyExchangeAlgorithm
        self.certificateType = certificateType
        self.bulkCipherAlgorithm = bulkCipherAlgorithm
        self.cipherType = cipherType
        self.blockCipherMode = blockCipherMode
        self.fixedIVLength = fixedIVLength
        self.recordIVLength = recordIVLength
        
        if fixedIVLength == 0 {
            self.fixedIVLength = bulkCipherAlgorithm.blockSize
        }

        if recordIVLength == 0 {
            self.recordIVLength = bulkCipherAlgorithm.blockSize
        }

        if let hmacDescriptor = hmacDescriptor {
            self.hmacDescriptor = hmacDescriptor
        }
        else {
            self.hmacDescriptor = HMACDescriptor(algorithm: .NULL, size: 0)
        }
    }
}


let TLSCipherSuiteDescritions : [CipherSuiteDescriptor] = [
    CipherSuiteDescriptor(
        cipherSuite: .TLS_RSA_WITH_NULL_MD5,
        keyExchangeAlgorithm: .RSA,
        bulkCipherAlgorithm: .NULL,
        cipherType: .Stream,
        hmacDescriptor: HMACDescriptor(algorithm: .HMAC_MD5, size: Int(CC_MD5_DIGEST_LENGTH))),
    
    CipherSuiteDescriptor(
        cipherSuite: .TLS_RSA_WITH_NULL_SHA,
        keyExchangeAlgorithm: .RSA,
        bulkCipherAlgorithm: .NULL,
        cipherType: .Stream,
        hmacDescriptor: HMACDescriptor(algorithm: .HMAC_SHA1, size: Int(CC_SHA1_DIGEST_LENGTH))),

    CipherSuiteDescriptor(
        cipherSuite: .TLS_RSA_WITH_AES_256_CBC_SHA,
        keyExchangeAlgorithm: .RSA,
        bulkCipherAlgorithm: .AES256,
        cipherType: .Block,
        blockCipherMode: .CBC,
        hmacDescriptor: HMACDescriptor(algorithm: .HMAC_SHA1, size: Int(CC_SHA1_DIGEST_LENGTH))),

    CipherSuiteDescriptor(
        cipherSuite: .TLS_RSA_WITH_AES_256_CBC_SHA256,
        keyExchangeAlgorithm: .RSA,
        bulkCipherAlgorithm: .AES256,
        cipherType: .Block,
        blockCipherMode: .CBC,
        hmacDescriptor: HMACDescriptor(algorithm: .HMAC_SHA256, size: Int(CC_SHA256_DIGEST_LENGTH))),

    CipherSuiteDescriptor(
        cipherSuite: .TLS_DHE_RSA_WITH_AES_256_CBC_SHA,
        keyExchangeAlgorithm: .DHE,
        bulkCipherAlgorithm: .AES256,
        cipherType: .Block,
        blockCipherMode: .CBC,
        hmacDescriptor: HMACDescriptor(algorithm: .HMAC_SHA1, size: Int(CC_SHA1_DIGEST_LENGTH))),

    CipherSuiteDescriptor(
        cipherSuite: .TLS_DHE_RSA_WITH_AES_256_CBC_SHA256,
        keyExchangeAlgorithm: .DHE,
        bulkCipherAlgorithm: .AES256,
        cipherType: .Block,
        blockCipherMode: .CBC,
        hmacDescriptor: HMACDescriptor(algorithm: .HMAC_SHA256, size: Int(CC_SHA256_DIGEST_LENGTH))),
        
    CipherSuiteDescriptor(
        cipherSuite: .TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,
        keyExchangeAlgorithm: .ECDHE,
        bulkCipherAlgorithm: .AES256,
        cipherType: .Stream,
        blockCipherMode: .CBC,
        hmacDescriptor: HMACDescriptor(algorithm: .HMAC_SHA1, size: Int(CC_SHA1_DIGEST_LENGTH))),

    CipherSuiteDescriptor(
        cipherSuite: .TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,
        keyExchangeAlgorithm: .ECDHE,
        bulkCipherAlgorithm: .AES128,
        cipherType: .Block,
        blockCipherMode: .CBC,
        hmacDescriptor: HMACDescriptor(algorithm: .HMAC_SHA256, size: Int(CC_SHA256_DIGEST_LENGTH))),
    
    CipherSuiteDescriptor(
        cipherSuite: .TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
        keyExchangeAlgorithm: .ECDHE,
        bulkCipherAlgorithm: .AES128,
        cipherType: .AEAD,
        blockCipherMode: .GCM,
        fixedIVLength: 4,
        recordIVLength: 8
    ),
    
    CipherSuiteDescriptor(
        cipherSuite: .TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
        keyExchangeAlgorithm: .ECDHE,
        certificateType: .ECDSA,
        bulkCipherAlgorithm: .AES128,
        cipherType: .AEAD,
        blockCipherMode: .GCM,
        fixedIVLength: 4,
        recordIVLength: 8
    )

]

let TLSCipherSuiteDescriptionDictionary : [CipherSuite:CipherSuiteDescriptor] = {
    var dict = [CipherSuite:CipherSuiteDescriptor]()
    for cipherSuite in TLSCipherSuiteDescritions {
        dict[cipherSuite.cipherSuite] = cipherSuite
    }
    
    return dict
}()