//  Author: Nevin Brackett-Rozinsky
//
// This is a proof-of-concept implementation to generate random integer values
// less than an upper bound. It showcases a potential optimization for the
// Swift standard library RandomNumberGenerator.next(upperBound:) method.
//
// In particular, the newNext(upperBound:) method shown here makes 10-20% fewer
// calls to next() when upperBound is between 1/2 and 2/3 the maximum range of
// the integer type, with no change outside that interval.
//
// It is based on and uses all the optimizations from the standard library
// next(upperBound:) method, including Lemire's technique of using full-width
// multiplication to avoid division.
//
// The novel development here is to reuse the leftover value when the result
// of next() falls outside the usable range. This is non-trivial to accomplish,
// because the leftover value:
//
// 1) is less than upperBound
// 2) has at least as many trailing zeros as upperBound
// 3) is usually not from a power-of-2 sized interval, so its bits are biased
//
// Nonetheless it can be and is done here, resulting in a reduction of the
// expected number of calls to next() in the worst-case from 2 to 1.6, when
// upperBound is just over half the maximum possible.

extension RandomNumberGenerator {
  @inlinable
  public mutating func newNext<T: FixedWidthInteger & UnsignedInteger>(upperBound: T) -> T {
    precondition(upperBound != 0, "upperBound cannot be zero.")
    
    var random: T = next()
    var m = random.multipliedFullWidth(by: upperBound)
    if m.low >= upperBound { return m.high }
    
    // We will use this difference quite frequently
    let diff = 0 &- upperBound
    
    // Bottom half of T. This "if" is new: the standard library treats all
    // values this way, but we are more selective.
    if upperBound <= (T.max &>> 1) &+ 1 {
      let t = diff % upperBound
      
      while m.low < t {
        random = next()
        m = random.multipliedFullWidth(by: upperBound)
      }
      return m.high
    }
    
    // In the top half of T we don't need to take a remainder.
    if m.low >= diff { return m.high }
    
    // Top third of T. This "if" is also new.
    if (diff &<< 1) < upperBound {
      while true {
        random = next()
        if random < upperBound { return random }
      }
    }
    
    
    // MARK: New stuff
    
    // Everything above this line is essentially equivalent to the existing
    // Swift standard library version, just rearranged a bit. (We do avoid
    // calling multipliedFullWidth when upperBound is in the top third of T,
    // but in practice that doesn't really gain much.)
    //
    // The rest of this function is an optimization to reduce the expected
    // number of calls to next() when upperBound is between 1/2 and 2/3 of T.
    // That is the "worst case" region in the following sense:
    //
    // In that range, the existing implementation is expected to call next()
    // n = 2^T.bitWidth / upperBound times. Thus for upperBound just above 1/2
    // of T it averages 2 calls, and for upperBound just below 2/3 of T it
    // averages 1.5 calls. Nothing outside that range averages more than 1.5.
    //
    // In the same range, this implementation is expected to call next() about
    // f(n) times, where f(n) is a quotient of 4th-degree polynomials:
    //
    // f(n) = (2 - 1/n) / (1 - ((1 - 1/n)(2 - 3/n))^2)
    //
    // Thus for upperBound just above 1/2 of T it averages 1.6 calls (20% less),
    // and for upperBound just below 2/3 of T it averages 4/3 calls (11% less).
    
    
    // Between 1/2 and 2/3 of T
    
    // We will need to check parity a few times.
    @inline(__always)
    func isEven(_ n: T) -> Bool { n._lowWord & 1 == 0 }
    
    // This is not actually a type conversion, but the compiler doesn’t know
    // that T == T.Magnitude for UnsignedInteger types.
    var bits = T(truncatingIfNeeded: m.low)
    
    // If upperBound is odd, then bits is uniformly random in 0..<diff.
    //
    // If upperBound is even, we can construct such a value by appending the
    // high bits of the original random number. This is valid because two
    // numbers a and b, when multiplied by upperBound, will have the same .low
    // value if and only if they differ solely in those high bits.
    if isEven(upperBound) {
      bits |= random &>> (T.bitWidth &- upperBound.trailingZeroBitCount)
    }
    
    // We will "pair up" small values by appending a bit. It is important to
    // note that diff/2 < halfBound <= diff, which we know because upperBound
    // is between 1/2 and 2/3 of T.
    let halfBound = (upperBound &+ 1) &>> 1
    
    // The interesting part
    repeat {
      random = next()
      if random < upperBound { return random }
      let newBits = T.max &- random
      
      // At this point, bits and newBits are both uniformly random in 0..<diff,
      // and together they can usually produce a result. Here's how:
      //
      // Consider the pair (bits, newBits) as a point in a d×d square lattice.
      // In other words, as a square on a d×d chessboard.
      //
      //       |<-------- bits -------->|
      // ----- ┏━━━━━━━━━━━━━┳━━━━━━━━━━┓ d (diff)
      //   ^   ┃╴ ╴ ╴ ╴ ╴ ╴ ╴┃          ┃
      //   |   ┠─────────────┨          ┃
      //   |   ┃╴ ╴ ╴ ╴ ╴ ╴ ╴┃          ┃
      //       ┠─────────────┨          ┃
      //  new  ┃╴ ╴ ╴ ╴ ╴ ╴ ╴┣━━┯━━━┯━━━┫ h (halfBound)
      //  bits ┠─────────────┨  │ ╵ │ ╵ ┃
      //       ┃╴ ╴ ╴ ╴ ╴ ╴ ╴┃  │ ╵ │ ╵ ┃
      //   |   ┠─────────────┨  │ ╵ │ ╵ ┃
      //   |   ┃╴ ╴ ╴ ╴ ╴ ╴ ╴┃  │ ╵ │ ╵ ┃
      //   v   ┠─────────────┨  │ ╵ │ ╵ ┃
      // ----- ┗━━━━━━━━━━━━━┻━━┷━┷━┷━┷━┛ 0
      //       0             h          d
      //
      // On the left side, when bits < h, pair up the adjacent rows to form
      // "two-lane roads". Note that there may be an unpaired "one-lane road"
      // at the end. The first parity check ensures we don't use it.
      //
      // On the right side, do the same thing with columns when newBits < h.
      // The second parity check avoids any one-lane road there.
      //
      // Note that every complete two-lane road has 2*h lattice points
      // (chessboard squares) in it, and 2*h is either upperBound or 1 higher.
      //
      // We can number the positions within a road by counting them in order,
      // alternating lanes as we proceed down the length:
      //
      // ┏━━━┯━━━┯━━━┯━━━┯━━━┯━━━┯━━━┯━━━┯━━━┯━━━┯━━━┯━━━┯━━━┯━━━┯━━━┯━━━┓
      // ┃ 1 │ 3 │ 5 │ 7 │ 9 │11 │13 │15 │17 │19 │21 │23 │25 │27 │29 │...┃
      // ┠───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┨
      // ┃ 0 │ 2 │ 4 │ 6 │ 8 │10 │12 │14 │16 │18 │20 │22 │24 │26 │28 │...┃
      // ┗━━━┷━━━┷━━━┷━━━┷━━━┷━━━┷━━━┷━━━┷━━━┷━━━┷━━━┷━━━┷━━━┷━━━┷━━━┷━━━┛
      //
      // If the pair (bits, newBits) falls within a complete road, we can find
      // its position in that road by appending a bit from one (for the lane)
      // onto the other (for the distance down the road).
      //
      // The resulting value is uniform in 0..<2*h, so it is at most equal to
      // upperBound. If it is less than upperBound we are done.
      
      if bits < halfBound {
        // The left side of the box drawing, first parity check
        if isEven(diff) || (newBits != 0) {
          // On a two-lane road
          let x = (bits &<< 1) | (newBits & 1)
          if x < upperBound { return x }
        }
      } else if newBits < halfBound {
        // The lower right side, second parity check
        if isEven(diff &- halfBound) || (bits != halfBound) {
          // On a two-lane road
          let x = (newBits &<< 1) | (bits & 1)
          if x < upperBound { return x }
        }
      }
      
      // If we missed all the two-lane roads, generate more bits and try again
      random = next()
      if random < upperBound { return random }
      bits = T.max &- random
    } while true
  }
}
