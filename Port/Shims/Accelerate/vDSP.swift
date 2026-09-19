// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// `import Accelerate` off macOS. Only the vDSP entry points upstream's portable
// sources call are provided, as plain loops with the same signatures and
// semantics (stride-aware, in-place safe). The compiler auto-vectorises these
// at -O; the buffers involved are one audio chunk long.

public typealias vDSP_Length = UInt
public typealias vDSP_Stride = Int

/// Root mean square of `__N` elements of `__A`, read with stride `__IA`.
public func vDSP_rmsqv(
    _ __A: UnsafePointer<Float>, _ __IA: vDSP_Stride,
    _ __C: UnsafeMutablePointer<Float>, _ __N: vDSP_Length
) {
    guard __N > 0 else { __C.pointee = 0; return }
    var sum: Float = 0
    var index = 0
    for _ in 0..<Int(__N) {
        let value = __A[index]
        sum += value * value
        index += __IA
    }
    __C.pointee = (sum / Float(__N)).squareRoot()
}

/// `__C[i] = __A[i] * __B[0]`. `__A` and `__C` may be the same buffer.
public func vDSP_vsmul(
    _ __A: UnsafePointer<Float>, _ __IA: vDSP_Stride,
    _ __B: UnsafePointer<Float>,
    _ __C: UnsafeMutablePointer<Float>, _ __IC: vDSP_Stride,
    _ __N: vDSP_Length
) {
    let scalar = __B.pointee
    var source = 0
    var destination = 0
    for _ in 0..<Int(__N) {
        __C[destination] = __A[source] * scalar
        source += __IA
        destination += __IC
    }
}
