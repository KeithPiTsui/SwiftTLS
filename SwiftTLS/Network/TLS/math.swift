//
//  math.swift
//  SwiftTLS
//
//  Created by Nico Schmidt on 18.11.15.
//  Copyright © 2015 Nico Schmidt. All rights reserved.
//

func division<T : IntegerArithmeticType>(a : T, _ b : T, inout remainder: T?) -> T
{
    if remainder != nil {
        remainder = a % b
    }
    
    return a / b
}

public func modular_pow(base : BigInt, _ exponent : Int, _ mod : BigInt) -> BigInt
{
    let numBits = sizeof(Int) * 8
    
    var result = BigInt(1)
    var r = base % mod
    for var i = 0; i < numBits; ++i
    {
        if (exponent & (1 << i)) != 0 {
            result = (result * r) % mod
        }
        
        r = (r * r) % mod
    }
    
    return result
}

public func modular_pow(base : BigInt, _ exponent : BigInt, _ mod : BigInt) -> BigInt
{
    let numBits = exponent.numberOfBits
    
    var result = BigInt(1)
    var r = base % mod
    for var i = 0; i < numBits; ++i
    {
        if (exponent.isBitSet(i)) {
            result = (result * r) % mod
        }
        
        r = (r * r) % mod
    }
    
    return result
}

func gcd<T : IntegerArithmeticType where T : IntegerLiteralConvertible>(var x : T, var _ y : T) -> T
{
    var g : T = y
    
    while x > 0 {
        g = x
        x = y % x
        y = g
    }
    
    return g
}

func extended_euclid<T : IntegerArithmeticType where T : IntegerLiteralConvertible>(z z : T, a : T) -> T
{
    var i = a
    var j = z
    var y1 : T = 1
    var y2 : T = 0
    
    let zero : T = 0
    while j > zero
    {
        var remainder : T? = 0
        let quotient = division(i, j, remainder: &remainder)
        
        let y = y2 - y1 * quotient
        
        i = j
        j = remainder!
        y2 = y1
        y1 = y
        
    }
    
    return y2 % a
}

public func modular_inverse<T : IntegerArithmeticType where T : IntegerLiteralConvertible>(x : T, _ y : T, mod : T) -> T
{
    let inverse = extended_euclid(z: y, a: mod)
    
    return inverse * x
}
