//
//  SHA256Tests.swift
//  SwiftTLSTests
//
//  Created by Nico Schmidt on 14.04.18.
//  Copyright © 2018 Nico Schmidt. All rights reserved.
//

import XCTest
@testable import SwiftTLS

class SHA256Tests: XCTestCase {

    func test_sha256_withOneBlockMessage_givesCorrectDigest() {
        let sha = SHA256()
        sha.update([UInt8]("abc".utf8))
        let digest = sha.finalize()
        
        XCTAssert(digest == [0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, 0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23, 0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c, 0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad])
    }

    func test_sha256_withMultiBlockMessage_givesCorrectDigest() {
        let digest = SHA256.hash([UInt8]("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
        
        XCTAssert(digest == [0x24, 0x8d, 0x6a, 0x61, 0xd2, 0x06, 0x38, 0xb8, 0xe5, 0xc0, 0x26, 0x93, 0x0c, 0x3e, 0x60, 0x39, 0xa3, 0x3c, 0xe4, 0x59, 0x64, 0xff, 0x21, 0x67, 0xf6, 0xec, 0xed, 0xd4, 0x19, 0xdb, 0x06, 0xc1])
    }

    func test_sha256_withLongMessage_givesCorrectDigest() {
        let message = [UInt8](repeating: [UInt8]("a".utf8)[0], count: 1_000_000)
        let digest = SHA256.hash(message)
        
        XCTAssert(digest == [0xcd, 0xc7, 0x6e, 0x5c, 0x99, 0x14, 0xfb, 0x92, 0x81, 0xa1, 0xc7, 0xe2, 0x84, 0xd7, 0x3e, 0x67, 0xf1, 0x80, 0x9a, 0x48, 0xa4, 0x97, 0x20, 0x0e, 0x04, 0x6d, 0x39, 0xcc, 0xc7, 0x11, 0x2c, 0xd0])
    }

}

