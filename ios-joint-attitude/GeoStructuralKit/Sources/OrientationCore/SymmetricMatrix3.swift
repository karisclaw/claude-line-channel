import Foundation

/// A symmetric 3×3 matrix, stored as its six independent entries.
///
/// Used for the orientation tensor of a set of axes, which is the basis of both
/// the sampling mean (A2) and the Woodcock fabric shape parameters (C3).
public struct SymmetricMatrix3: Equatable, Sendable {
    public var m00: Double, m01: Double, m02: Double
    public var m11: Double, m12: Double
    public var m22: Double

    public init(m00: Double, m01: Double, m02: Double, m11: Double, m12: Double, m22: Double) {
        self.m00 = m00; self.m01 = m01; self.m02 = m02
        self.m11 = m11; self.m12 = m12
        self.m22 = m22
    }

    public static let zero = SymmetricMatrix3(m00: 0, m01: 0, m02: 0, m11: 0, m12: 0, m22: 0)

    public subscript(row: Int, column: Int) -> Double {
        let (i, j) = row <= column ? (row, column) : (column, row)
        switch (i, j) {
        case (0, 0): return m00
        case (0, 1): return m01
        case (0, 2): return m02
        case (1, 1): return m11
        case (1, 2): return m12
        case (2, 2): return m22
        default: return .nan
        }
    }

    public var trace: Double { m00 + m11 + m22 }

    /// The normalized orientation tensor `T = (1/n) Σ uᵢuᵢᵀ` of a set of unit axes.
    ///
    /// The outer product `uuᵀ` is unchanged by `u → -u`, which is precisely why the
    /// tensor is the right tool for axial data: no sign convention has to be
    /// imposed on the samples first.
    ///
    /// Non-unit and zero-length inputs are normalized and dropped respectively.
    /// Returns `nil` if no usable axis remains.
    public static func orientationTensor(of axes: [Vector3]) -> SymmetricMatrix3? {
        let units = axes.compactMap(\.normalized)
        guard !units.isEmpty else { return nil }
        var t = SymmetricMatrix3.zero
        for u in units {
            t.m00 += u.x * u.x
            t.m01 += u.x * u.y
            t.m02 += u.x * u.z
            t.m11 += u.y * u.y
            t.m12 += u.y * u.z
            t.m22 += u.z * u.z
        }
        let n = Double(units.count)
        return SymmetricMatrix3(
            m00: t.m00 / n, m01: t.m01 / n, m02: t.m02 / n,
            m11: t.m11 / n, m12: t.m12 / n, m22: t.m22 / n
        )
    }
}

/// Eigenvalues and eigenvectors of a symmetric 3×3 matrix, sorted with the largest
/// eigenvalue first.
public struct Eigen3: Equatable, Sendable {
    /// Eigenvalues in descending order, `λ1 ≥ λ2 ≥ λ3`.
    public let values: [Double]
    /// Unit eigenvectors, in the same order as ``values``. Signs are arbitrary.
    public let vectors: [Vector3]

    public var largestValue: Double { values[0] }
    public var principalVector: Vector3 { vectors[0] }
}

extension SymmetricMatrix3 {

    /// Eigen-decomposition by the cyclic Jacobi method.
    ///
    /// Jacobi rather than a closed-form cubic solve: the matrices here are tiny, so
    /// speed is irrelevant, and Jacobi stays accurate for the near-degenerate cases
    /// that matter geologically — a perfect cluster (`λ2 ≈ λ3`) and a perfect
    /// girdle (`λ1 ≈ λ2`), where the closed form loses precision.
    public func eigen(maxSweeps: Int = 50, tolerance: Double = 1e-18) -> Eigen3 {
        var a = [[m00, m01, m02], [m01, m11, m12], [m02, m12, m22]]
        var v = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
        let pairs = [(0, 1), (0, 2), (1, 2)]

        for _ in 0..<maxSweeps {
            let off = abs(a[0][1]) + abs(a[0][2]) + abs(a[1][2])
            if off < tolerance { break }
            for (p, q) in pairs {
                if abs(a[p][q]) < tolerance { continue }
                let theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
                let t = (theta >= 0 ? 1.0 : -1.0) / (abs(theta) + (theta * theta + 1).squareRoot())
                let c = 1 / (t * t + 1).squareRoot()
                let s = t * c

                for k in 0..<3 {            // A := A · J
                    let akp = a[k][p], akq = a[k][q]
                    a[k][p] = c * akp - s * akq
                    a[k][q] = s * akp + c * akq
                }
                for k in 0..<3 {            // A := Jᵀ · A
                    let apk = a[p][k], aqk = a[q][k]
                    a[p][k] = c * apk - s * aqk
                    a[q][k] = s * apk + c * aqk
                }
                for k in 0..<3 {            // V := V · J
                    let vkp = v[k][p], vkq = v[k][q]
                    v[k][p] = c * vkp - s * vkq
                    v[k][q] = s * vkp + c * vkq
                }
            }
        }

        let indexed = (0..<3)
            .map { (value: a[$0][$0], vector: Vector3(v[0][$0], v[1][$0], v[2][$0])) }
            .sorted { $0.value > $1.value }

        return Eigen3(
            values: indexed.map(\.value),
            vectors: indexed.map { $0.vector.normalized ?? .upAxis }
        )
    }
}
