import Foundation

/// Conversions from other frames into this package's NWU world frame.
public enum ReferenceFrame {

    /// Converts a vector from ARKit's `.gravityAndHeading` world alignment into NWU.
    ///
    /// ARKit's heading-aligned frame is `+x` east, `+y` up, `-z` north, so:
    /// ```
    ///   north =  -z
    ///   west  =  -x
    ///   up    =   y
    /// ```
    /// The map is a proper rotation (determinant `+1`), so handedness — and with it
    /// the sign of every cross product downstream — is preserved.
    ///
    /// Once converted, a LiDAR plane fit goes through exactly the same
    /// ``PlaneOrientation/init(measuredNormal:)`` as a contact measurement.
    public static func fromARKitGravityAndHeading(x: Double, y: Double, z: Double) -> Vector3 {
        Vector3(north: -z, west: -x, up: y)
    }

    /// Converts an NWU vector back into ARKit's `.gravityAndHeading` frame.
    public static func toARKitGravityAndHeading(_ v: Vector3) -> (x: Double, y: Double, z: Double) {
        (x: -v.west, y: v.up, z: -v.north)
    }

    /// Converts a vector from a local ENU frame (`+x` east, `+y` north, `+z` up)
    /// into NWU. Useful for imported survey data.
    public static func fromENU(x: Double, y: Double, z: Double) -> Vector3 {
        Vector3(north: y, west: -x, up: z)
    }
}
