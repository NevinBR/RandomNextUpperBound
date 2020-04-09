// Author: Nevin Brackett-Rozinsky, inspired by Jens Persson (@jens-bc)

extension RandomNumberGenerator {
  @inlinable
  public mutating func newNext2<T: FixedWidthInteger & UnsignedInteger>(upperBound: T) -> T {
    precondition(upperBound != 0, "upperBound cannot be zero.")

    var random: T = next()
    var m = random.multipliedFullWidth(by: upperBound)
    if m.low >= upperBound { return m.high }

    let t = (0 &- upperBound) % upperBound
    if m.low >= t { return m.high }
    
    
    // MARK: New declarations
    
    let halfBound = (upperBound &>> 1) &+ (upperBound & 1)
    var bitBound = t
    
    @inline(__always)
    func isEven(_ n: T) -> Bool { n._lowWord & 1 == 0 }
    
    @inline(__always)
    func uniformRemainder() -> T {
      var n = T(truncatingIfNeeded: m.low)
      if isEven(upperBound) {
        n |= random &>> (T.bitWidth &- upperBound.trailingZeroBitCount)
      }
      return n
    }
    
    @inline(__always)
    func calculateBitsNeeded() -> Int {
      if bitBound >= halfBound { return 0 }
      var n = bitBound.leadingZeroBitCount &- halfBound.leadingZeroBitCount
      if (bitBound &<< n) < halfBound { n &+= 1 }
      return n
    }
    
    var bits = uniformRemainder()
    var newBits: T
    var bitsAvailable: Int
    var bitsNeeded = calculateBitsNeeded()
    
    @inline(__always)
    func consumeBits(count n: Int) {
      let mask: T = (1 &<< n) &- 1
      bits = (bits &<< n) | (newBits & mask)
      newBits &>>= n
      bitBound &<<= n
      bitsNeeded &-= n
      bitsAvailable &-= n
    }
    
    @inline(__always)
    func decreaseBounds(by n: T) {
      bits &-= n
      bitBound &-= n
      bitsNeeded = calculateBitsNeeded()
    }
    
    
    // MARK: Primary loop
    
    while true {
      random = next()
      m = random.multipliedFullWidth(by: upperBound)
      if m.low >= t { return m.high }
      
      
      // MARK: New logic
      
      newBits = uniformRemainder()
      bitsAvailable = (t ^ newBits)._binaryLogarithm()
      
      while bitsNeeded < bitsAvailable {
        consumeBits(count: bitsNeeded)
        
        if bits < halfBound {
          consumeBits(count: 1)
          if bits < upperBound { return bits }
          decreaseBounds(by: upperBound)
        } else {
          decreaseBounds(by: halfBound)
        }
      }
      
      consumeBits(count: bitsAvailable)
    }
  }
}
