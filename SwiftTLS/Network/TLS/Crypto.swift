//
//  Crypto.swift
//  SwiftTLS
//
//  Created by Nico Schmidt on 29.12.15.
//  Copyright © 2015 Nico Schmidt. All rights reserved.
//

protocol Signing
{
    func sign(data data : [UInt8], hashAlgorithm: HashAlgorithm) -> [UInt8]
    func verify(signature signature : [UInt8], data : [UInt8]) -> Bool
}