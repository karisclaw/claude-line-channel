import Foundation

/// The conventions every stored attitude in this project is expressed in.
///
/// Stamp records with ``version`` as they are written. Nothing about a stored
/// `dip` / `dipDirection` pair reveals which convention produced it, so the only way
/// a later reader can know is if the record says so. Bump the version whenever a
/// change here would make an existing record mean something different.
public enum AttitudeConvention {

    /// Version 1 was the project specification as originally written, whose dip
    /// direction was 180° out — it paired `dip = acos(n_U)`, which needs the upward
    /// normal, with `atan2(-n_E, -n_N)`, which is the lower-hemisphere pole formula.
    /// No data was ever recorded under it.
    ///
    /// Version 2 is what this package implements, described in
    /// `docs/conventions.md`: attitudes are true-north referenced, dip direction is
    /// the azimuth of the steepest downslope, strike follows the right-hand rule, and
    /// both components of an attitude come from the upward normal.
    public static let version = 2
}

extension PlaneOrientation {

    /// What a record means if its dip direction was stored as the **pole** azimuth —
    /// the 180°-out convention the project specification originally carried, and the
    /// one a source may be using if its dip directions all look reversed.
    ///
    /// This cannot be detected from the numbers: a plane at 45°/090 under one
    /// convention and 45°/270 under the other are both perfectly valid attitudes.
    /// Only apply it to data from a source you have confirmed uses that convention.
    public var reinterpretingDipDirectionAsPoleAzimuth: PlaneOrientation {
        PlaneOrientation(dip: dip, dipDirection: dipDirection + 180)
    }
}
