#!/usr/bin/env python3
"""Reference implementation of GeoStructuralKit's OrientationCore, in Python.

Why this exists: the Swift package is the product, but Swift toolchains are not
available everywhere (CI containers, the machine this was first written on). This
file is a line-for-line port of the same maths, run against the same expected
values as the XCTest suite, so the numerical behaviour can be checked anywhere
python3 exists.

It is a cross-check, NOT a substitute for `swift test`. If you change the Swift,
change this too, and keep the expected values in both in step.

    python3 tools/reference_check.py

Frame: NWU (x = true north, y = west, z = up), right-handed.
"""
import math

D = math.degrees
R = math.radians

def norm(v):
    L = math.sqrt(sum(c*c for c in v))
    return tuple(c/L for c in v)

def dot(a,b): return sum(x*y for x,y in zip(a,b))
def cross(a,b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def neg(a): return tuple(-x for x in a)
def clamp(x, lo, hi): return max(lo, min(hi, x))
def az(deg):
    """Wrap into 0..<360, matching GeoAngle.normalizedAzimuth.

    The >= 360 case is not decoration: 360 - 7e-15 rounds to exactly 360.0 in
    double, and letting that through reports a dip direction of 360, which then
    canonicalizes to 180 instead of 0.
    """
    r = math.fmod(deg, 360.0)
    w = r + 360.0 if r < 0 else r
    return 0.0 if (w >= 360.0 or w == 0) else w

# ---- quaternion (w,x,y,z) ----
def qrotate(q, v):
    w,x,y,z = q
    u = (x,y,z)
    t = cross(u,v)
    t = tuple(2.0*c for c in t)
    return tuple(v[i] + w*t[i] + cross(u,t)[i] for i in range(3))

def q_from_columns(c0, c1, c2):
    """Rotation matrix given by its columns (images of basis vectors). Shepperd's method."""
    m00,m10,m20 = c0
    m01,m11,m21 = c1
    m02,m12,m22 = c2
    tr = m00+m11+m22
    if tr > 0:
        s = math.sqrt(tr+1.0)*2
        w = 0.25*s; x = (m21-m12)/s; y = (m02-m20)/s; z = (m10-m01)/s
    elif m00 > m11 and m00 > m22:
        s = math.sqrt(1.0+m00-m11-m22)*2
        w = (m21-m12)/s; x = 0.25*s; y = (m01+m10)/s; z = (m02+m20)/s
    elif m11 > m22:
        s = math.sqrt(1.0+m11-m00-m22)*2
        w = (m02-m20)/s; x = (m01+m10)/s; y = 0.25*s; z = (m12+m21)/s
    else:
        s = math.sqrt(1.0+m22-m00-m11)*2
        w = (m10-m01)/s; x = (m02+m20)/s; y = (m12+m21)/s; z = 0.25*s
    return norm((w,x,y,z))

# ---- plane <-> normal ----
HORIZ_TOL = 0.5   # deg
VERT_TOL  = 0.5   # deg

def upper_hemisphere(n):
    """The representative of an axis that lies in the upper hemisphere.

    On the equator neither representative points up, so the tie is broken on the
    horizontal components. Without that, an exactly horizontal normal arriving as
    0.0 rather than -0.0 would flip the reported dip direction by 180 degrees.
    """
    u = norm(n)
    if u[2] > 0:
        return u
    if u[2] < 0:
        return neg(u)
    if u[0] > 0:
        return u
    if u[0] < 0:
        return neg(u)
    return u if u[1] >= 0 else neg(u)


def plane_from_normal(n):
    """Dip and dip direction of the plane with this normal.

    Both components come from the SAME vector, the upward normal. Taking the dip
    from one vector and the dip direction from another is what puts a reading 180
    degrees out -- see docs/conventions.md section 2.
    """
    up = upper_hemisphere(n)
    dip = D(math.acos(clamp(up[2], -1.0, 1.0)))
    dipdir = az(D(math.atan2(-up[1], up[0])))      # atan2(n_E, n_N), n_E = -n_W
    return dip, dipdir


def canonicalized(dip, dipdir, vertical_tol=0.5):
    """Noise-stable description: a vertical plane is reported with dipdir < 180."""
    if dip > 90.0 - vertical_tol and dipdir >= 180.0:
        return dip, dipdir - 180.0
    return dip, dipdir


def normal_from_plane(dip, dipdir):
    d, a = R(dip), R(dipdir)
    nN = math.sin(d)*math.cos(a)
    nE = math.sin(d)*math.sin(a)
    nU = math.cos(d)
    return (nN, -nE, nU)                  # NWU

def dip_vector(dip, dipdir):
    d, a = R(dip), R(dipdir)
    nN = math.cos(d)*math.cos(a); nE = math.cos(d)*math.sin(a); nU = -math.sin(d)
    return (nN, -nE, nU)

def strike_vector(dipdir):
    a = R(az(dipdir - 90.0))
    return (math.cos(a), -math.sin(a), 0.0)

def apparent_dip2(dip, dipdir, trend):
    """Signed apparent dip in a vertical section along `trend`.

    Positive: the plane descends toward `trend`. Negative: away from it.
    """
    beta = R(az(trend - dipdir))
    return D(math.atan(math.tan(R(dip)) * math.cos(beta)))

# ---- line (trend/plunge) ----
def line_from_axis(v):
    nN, nW, nU = neg(upper_hemisphere(v))   # the down-plunge end
    nE = -nW
    plunge = D(math.asin(clamp(-nU, -1.0, 1.0)))
    trend = az(D(math.atan2(nE, nN)))
    return trend, plunge

def axis_from_line(trend, plunge):
    t, p = R(trend), R(plunge)
    nN = math.cos(p)*math.cos(t); nE = math.cos(p)*math.sin(t); nU = -math.sin(p)
    return (nN, -nE, nU)

# ---- device axes ----
def plane_from_device_quaternion(q):
    return plane_from_normal(qrotate(q, (0.0,0.0,1.0)))

def line_from_device_quaternion(q):
    return line_from_axis(qrotate(q, (0.0,-1.0,0.0)))

# ---- ARKit .gravityAndHeading (+x east, +y up, -z north) -> NWU ----
def from_arkit(x,y,z):
    return (-z, -x, y)

# ---- symmetric 3x3 Jacobi ----
def jacobi(a):
    a = [row[:] for row in a]
    v = [[1.0 if i==j else 0.0 for j in range(3)] for i in range(3)]
    for _ in range(50):
        off = abs(a[0][1])+abs(a[0][2])+abs(a[1][2])
        if off < 1e-18: break
        for p,q in ((0,1),(0,2),(1,2)):
            if abs(a[p][q]) < 1e-18: continue
            theta = (a[q][q]-a[p][p]) / (2.0*a[p][q])
            t = math.copysign(1.0, theta)/(abs(theta)+math.sqrt(theta*theta+1.0))
            c = 1.0/math.sqrt(t*t+1.0); s = t*c
            for k in range(3):
                akp = a[k][p]; akq = a[k][q]
                a[k][p] = c*akp - s*akq
                a[k][q] = s*akp + c*akq
            for k in range(3):
                apk = a[p][k]; aqk = a[q][k]
                a[p][k] = c*apk - s*aqk
                a[q][k] = s*apk + c*aqk
            for k in range(3):
                vkp = v[k][p]; vkq = v[k][q]
                v[k][p] = c*vkp - s*vkq
                v[k][q] = s*vkp + c*vkq
    pairs = sorted([(a[i][i], (v[0][i],v[1][i],v[2][i])) for i in range(3)],
                   key=lambda t: -t[0])
    return pairs

def axial_stats(vs):
    n = len(vs)
    us = [norm(v) for v in vs]
    T = [[sum(u[i]*u[j] for u in us)/n for j in range(3)] for i in range(3)]
    pairs = jacobi(T)
    lam = [p[0] for p in pairs]
    mean = norm(pairs[0][1])
    if sum(dot(u, mean) for u in us) < 0:      # align with the majority of samples
        mean = neg(mean)
    angs = [D(math.acos(clamp(abs(dot(u, mean)), 0.0, 1.0))) for u in us]
    if n > 1:
        sd = math.sqrt(sum(t*t for t in angs)/(n-1))
    else:
        sd = 0.0
    return mean, lam, sd, max(angs), sum(angs)/n


# acos loses half its significant digits near an argument of 1, so two identical
# planes compare as ~8.5e-7 degrees apart rather than 0. That is the conditioning of
# acos, not an error in the conversion, so assertions on a near-zero dihedral angle
# use this floor. Dip and dip direction themselves are still checked at 1e-9.
DIHEDRAL_FLOOR = 1e-5


def dihedral(p1, p2):
    """Acute angle between two planes given as (dip, dip direction)."""
    return D(math.acos(clamp(abs(dot(normal_from_plane(*p1), normal_from_plane(*p2))), 0, 1)))



# ---- quadrant notation (mirrors QuadrantNotation.swift / QuadrantAttitude.swift) ----

QUADRANTS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


def azimuth_separation(a, b):
    d = abs(az(a) - az(b))
    return min(d, 360.0 - d)


def nearest_quadrant(azimuth):
    return min(QUADRANTS, key=lambda q: azimuth_separation(QUADRANTS.index(q) * 45.0, azimuth))


def quadrant_azimuth(label):
    return QUADRANTS.index(label) * 45.0


def bearing_of(azimuth):
    a = az(azimuth)
    if a <= 90:  return ("N", a, "E")
    if a <= 180: return ("S", 180 - a, "E")
    if a <= 270: return ("S", a - 180, "W")
    return ("N", 360 - a, "W")


def bearing_azimuth(b):
    ns, angle, ew = b
    return az({("N", "E"): angle, ("S", "E"): 180 - angle,
               ("S", "W"): 180 + angle, ("N", "W"): 360 - angle}[(ns, ew)])


def format_angle(value):
    r = round(value * 10) / 10
    return f"{r:.0f}" if r == round(r) else f"{r:.1f}"


def axial_description(b):
    ns, angle, ew = b
    if angle < 0.05:  return "N-S"
    if angle > 89.95: return "E-W"
    return f"{ns}{format_angle(angle)}{ew}"


def quadrant_strike(dipdir):
    s = az(dipdir - 90)
    axis = s - 180 if s >= 180 else s
    return bearing_of(axis if axis <= 90 else axis + 180)


def plane_quadrant_description(dip, dipdir):
    if dip < 0.5:
        return "Horizontal"
    text = f"{axial_description(quadrant_strike(dipdir))}, {format_angle(dip)}"
    return text if dip > 89.5 else text + nearest_quadrant(dipdir)


def parse_plane_quadrant(text):
    """Returns (dip, dip direction), or None where the record is unresolvable."""
    s = "".join("-" if c in "-\u2013\u2014_" else c
                for c in text.upper()
                if not c.isspace() and c not in "\u00b0,/;\u2192")
    if not s:
        return None
    if s == "HORIZONTAL":
        return (0.0, 0.0)

    if len(s) > 1 and s[0] in "NS" and s[1].isdigit():
        j = 1
        while j < len(s) and (s[j].isdigit() or s[j] == "."):
            j += 1
        if j >= len(s) or s[j] not in "EW":
            return None
        angle = float(s[1:j])
        if not 0 <= angle <= 90:
            return None
        bearing, i = (s[0], angle, s[j]), j + 1
    elif s.startswith("N-S"):
        bearing, i = ("N", 0.0, "E"), 3
    elif s.startswith("E-W"):
        bearing, i = ("N", 90.0, "E"), 3
    elif s[0] in "NSEW":
        bearing = {"N": ("N", 0.0, "E"), "S": ("S", 0.0, "E"),
                   "E": ("N", 90.0, "E"), "W": ("N", 90.0, "W")}[s[0]]
        i = 1
    else:
        return None

    j = i
    while j < len(s) and (s[j].isdigit() or s[j] == "."):
        j += 1
    if j == i:
        return None
    dip = float(s[i:j])
    if not 0 <= dip <= 90:
        return None

    letters = s[j:]
    candidates = [az(bearing_azimuth(bearing) + 90), az(bearing_azimuth(bearing) - 90)]
    if not letters:
        # Only a plane with no side to dip toward may omit the quadrant.
        return (dip, candidates[0]) if (dip > 89.5 or dip < 0.5) else None
    if letters not in QUADRANTS:
        return None
    target = quadrant_azimuth(letters)
    seps = [azimuth_separation(c, target) for c in candidates]
    if abs(seps[0] - seps[1]) < 1e-9:
        return None          # the letter lies along the strike: it picks neither side
    return (dip, candidates[0] if seps[0] < seps[1] else candidates[1])


# ---- device placement (mirrors DevicePlacement.outwardNormalAxis) ----

# The outward normal points from the rock into the air, so it is the OPPOSITE of the
# axis the contacting face looks along. The phone's back looks along -z, its left side
# along -x, its bottom edge along -y.
OUTWARD_NORMAL_AXIS = {
    "backOnFace": (0.0, 0.0, 1.0),        # +z
    "screenOnFace": (0.0, 0.0, -1.0),     # -z
    "leftSideOnFace": (1.0, 0.0, 0.0),    # +x
    "rightSideOnFace": (-1.0, 0.0, 0.0),  # -x
    "bottomEdgeOnFace": (0.0, 1.0, 0.0),  # +y
    "topEdgeOnFace": (0.0, -1.0, 0.0),    # -y
}


# ---- A2: sampling and quality (mirrors StillnessDetector / BurstCollector /
#          MagneticEnvironment / CalibrationCheck / PlacementCrossCheck) ----

def vector_standard_deviation(vectors):
    """Deviation of the acceleration VECTOR about its mean, not of its magnitude.

    A phone rocked steadily holds its magnitude almost constant while the direction
    swings; a magnitude-only test calls that still.
    """
    n = len(vectors)
    mean = [sum(v[i] for v in vectors) / n for i in range(3)]
    total = sum(sum((v[i] - mean[i]) ** 2 for i in range(3)) for v in vectors)
    return math.sqrt(total / (n - 1))


def burst_shape(rate, duration, minimum_samples):
    """(first index collected, last index, sample count, effective rate)."""
    start = minimum_samples - 1          # the first sample whose window is full
    end = start
    while (end - start) / rate < duration:
        end += 1
    elapsed = (end - start) / rate
    count = end - start + 1
    return start, end, count, (count - 1) / elapsed


def magnetic_verdict(strength, accuracy, heading,
                     field_range=(25.0, 65.0), marginal=10.0, unusable=20.0):
    reasons, severity = [], 0

    def raise_to(level):
        nonlocal severity
        severity = max(severity, level)

    if strength is None:
        reasons.append("fieldStrengthUnknown")
        raise_to(1)
    elif not field_range[0] <= strength <= field_range[1]:
        reasons.append("fieldStrengthOutsideEarthRange")
        raise_to(2)

    if accuracy == -1:
        reasons.append("magnetometerUncalibrated")
        raise_to(2)
    elif accuracy == 0:
        reasons.append("magnetometerPoorlyCalibrated")
        raise_to(2)

    if heading is not None:
        if heading < 0:
            reasons.append("headingInvalid")
            raise_to(2)
        elif heading > unusable:
            reasons.append("headingAccuracyUnusable")
            raise_to(2)
        elif heading > marginal:
            reasons.append("headingAccuracyMarginal")
            raise_to(1)

    return ["good", "marginal", "disturbed"][severity], reasons


def calibration_error(reference, measured):
    """(tilt error, signed azimuth error, total dihedral angle)."""
    tilt = abs(measured[0] - reference[0])
    delta = az(measured[1] - reference[1])
    azimuth = delta - 360 if delta > 180 else delta
    return tilt, azimuth, dihedral(reference, measured)


def impulse_axis(accelerations, minimum_peak=0.15, minimum_confidence=0.6):
    """(implied axis or None, confidence, peak). Never returns a correction."""
    energy = {"x": 0.0, "y": 0.0, "z": 0.0}
    peak = 0.0
    for a in accelerations:
        energy["x"] += a[0] ** 2
        energy["y"] += a[1] ** 2
        energy["z"] += a[2] ** 2
        peak = max(peak, math.sqrt(sum(c * c for c in a)))
    total = sum(energy.values())
    if total <= 0 or peak < minimum_peak:
        return None, 0.0, peak
    leading = max(energy, key=energy.get)
    confidence = energy[leading] / total
    return (leading if confidence >= minimum_confidence else None), confidence, peak


# ---- B: ISRM class boundaries (mirrors ISRMDescriptors.swift) ----
#
# Half-open throughout: a value exactly on a boundary belongs to the UPPER class.
# ISRM writes its tables as "20-60 mm" without saying which end owns the boundary, so
# this is a choice, applied the same way to every scale.

SPACING_CLASSES_MM = [
    ("extremelyClose", 0.0, 20.0),
    ("veryClose", 20.0, 60.0),
    ("close", 60.0, 200.0),
    ("moderate", 200.0, 600.0),
    ("wide", 600.0, 2000.0),
    ("veryWide", 2000.0, 6000.0),
    ("extremelyWide", 6000.0, math.inf),
]

PERSISTENCE_CLASSES_M = [
    ("veryLow", 0.0, 1.0),
    ("low", 1.0, 3.0),
    ("medium", 3.0, 10.0),
    ("high", 10.0, 20.0),
    ("veryHigh", 20.0, math.inf),
]

# The published aperture table overlaps: "wide, > 10 mm" ends the gapped group while
# "very wide, 1-10 cm" starts the open group, so a 50 mm aperture has two valid names.
# The open-ended "wide" is dropped here and veryWide carries 10-100 mm.
APERTURE_CLASSES_MM = [
    ("veryTight", 0.0, 0.1),
    ("tight", 0.1, 0.25),
    ("partlyOpen", 0.25, 0.5),
    ("open", 0.5, 2.5),
    ("moderatelyWide", 2.5, 10.0),
    ("veryWide", 10.0, 100.0),
    ("extremelyWide", 100.0, 1000.0),
    ("cavernous", 1000.0, math.inf),
]

# ISRM gives TWO seepage tables. Both run I-V, but a rating means different things on
# each, so a stored reading has to say which table it came from.
UNFILLED_SEEPAGE = [
    (1, "tightAndDry"), (2, "dryWithEvidenceOfFlow"), (3, "damp"),
    (4, "seepage"), (5, "continuousFlow"),
]

FILLED_SEEPAGE = [
    (1, "fillingConsolidatedAndDry"), (2, "fillingDamp"),
    (3, "fillingWetWithOccasionalDrops"),
    (4, "fillingShowsOutwashWithContinuousFlow"), (5, "fillingWashedOutWithHeavyFlow"),
]

# The published open-ended aperture class, kept storable but never derived: its range
# overlaps three of the others.
APERTURE_LEGACY_WIDE = ("wide", 10.0, math.inf)

DISCONTINUITY_TYPES = [
    "joint", "sheetingJoint", "bedding", "fault", "faultZone", "shearZone",
    "foliation", "schistosity", "cleavage", "vein", "tensionGash", "stylolite",
    "unconformity", "intrusiveContact", "flowBanding",
]

ZONE_TYPES = {"faultZone", "shearZone"}

SURVEY_GEOMETRIES = {
    "scanline": "terzaghi",
    "borehole": "terzaghi",
    "window": "terzaghi",
    "traceMap": "terzaghi",
    "surfaceModel": "areaWeightedSurface",
    "selective": "unavailable",
}


def discontinuity_storage_key(case, label=None):
    return f"other:{label}" if case == "other" else case


def discontinuity_from_storage_key(key):
    if key.startswith("other:"):
        return ("other", key[len("other:"):])
    return (key, None) if key in DISCONTINUITY_TYPES else None


ROUGHNESS_CLASSES = [
    (waviness, profile, waviness_index * 3 + profile_index + 1)
    for waviness_index, waviness in enumerate(("stepped", "undulating", "planar"))
    for profile_index, profile in enumerate(("rough", "smooth", "slickensided"))
]


def classify(value, table):
    """The one class whose half-open range holds `value`, or None."""
    if not math.isfinite(value) or value < 0:
        return None
    for name, lower, upper in table:
        if lower <= value < upper:
            return name
    return None


def print_isrm_tables():
    """Prints the boundaries for checking against a copy of ISRM (1978)."""
    for title, table, unit in (
        ("Spacing", SPACING_CLASSES_MM, "mm"),
        ("Persistence", PERSISTENCE_CLASSES_M, "m"),
        ("Aperture", APERTURE_CLASSES_MM, "mm"),
    ):
        print(f"  {title}:")
        for name, lower, upper in table:
            top = "and up" if upper == math.inf else f"< {upper:g}"
            print(f"    {name:16s} {lower:>8g} {unit} .. {top} {unit if upper != math.inf else ''}")
    print(f"    {APERTURE_LEGACY_WIDE[0]:16s} {APERTURE_LEGACY_WIDE[1]:>8g} mm .. and up"
          "   (published, storable, never derived)")
    print("  Roughness (ISRM I-IX):")
    for waviness, profile, number in ROUGHNESS_CLASSES:
        print(f"    {number:>2d}  {profile:14s} {waviness}")
    print("  Seepage, unfilled discontinuity (I-V):")
    for rating, name in UNFILLED_SEEPAGE:
        print(f"    {rating}  {name}")
    print("  Seepage, filled discontinuity (I-V):")
    for rating, name in FILLED_SEEPAGE:
        print(f"    {rating}  {name}")


# ---- B: sampling bias (mirrors SamplingElement / SurveyGeometry) ----
#
# One relation covers every correctable geometry: the apparent frequency of a set is
# proportional to the SINE of the angle between the discontinuity and the sampling
# element, so the bias weight is its reciprocal.
#
#   against a LINE  s (scanline, borehole):  sine = |pole . s|      <- Terzaghi's original
#   against a PLANE m (window, trace map):   sine = |pole x m|
#
# The two depend on the pole in OPPOSITE directions. A set lying parallel to the outcrop
# face shows no trace on it, needing the largest correction there is, while a scanline
# along that face's normal samples it perfectly. Feeding a face normal to the line
# formula therefore inverts the correction.


def line_sampling_efficiency(pole, direction):
    return min(1.0, abs(dot(norm(pole), norm(direction))))


def plane_sampling_efficiency(pole, face_normal):
    c = cross(norm(pole), norm(face_normal))
    return min(1.0, math.sqrt(dot(c, c)))


def surface_model_efficiency(pole, facets):
    """Area-weighted mean of the per-facet planar efficiencies.

    Not a different theory from the planar case -- the same relation, summed. Each facet
    is a tiny mapped face, so this reduces exactly to `plane_sampling_efficiency` for a
    single facet, which is the property worth testing.
    """
    total = sum(max(area, 0.0) for _, area in facets)
    if total <= 0:
        return None
    weighted = sum(
        max(area, 0.0) * plane_sampling_efficiency(pole, normal)
        for normal, area in facets
    )
    return min(1.0, weighted / total)


# ---- B2: what a press means in each state (mirrors MeasurementRecorder) ----
#
# One button, which may be a Bluetooth key the geologist cannot see, so the same press
# has to mean the obviously right thing everywhere. The second row is the important one:
# a press while measuring CANCELS. Starting a second burst would discard the first
# silently, and a cancellation is recoverable where a lost measurement is not.
PRESS_MEANING = {
    "idle": "started",
    "saved": "started",
    "settling": "cancelled",
    "collecting": "cancelled",
    "review-clean": "saved",
    "review-flagged": "refusedBlindConfirmation",
}

# A warning withdraws the blind path and nothing else: an on-screen confirmation always
# saves. The geologist is at the outcrop and the app is not.
ON_SCREEN_CONFIRM_ALWAYS_SAVES = True

# Which warnings withdraw the blind path under the standard policy.
WARNINGS_REQUIRING_A_LOOK = {
    "magneticDisturbance": True,
    "placementDisagreement": True,
    "excessiveScatter": True,
    "sampleRateShortfall": False,   # a short stream still averages correctly
    "positionUnavailable": False,   # there may never be a fix in a gorge
    "descriptionInconsistency": True,
}

REPEAT_PRESS_INTERVAL = 0.35        # seconds


def press_outcome(state, elapsed_since_last_press=None):
    if elapsed_since_last_press is not None and elapsed_since_last_press < REPEAT_PRESS_INTERVAL:
        return "ignoredRepeatPress"
    return PRESS_MEANING[state]


# ---- C1: projection and Kamb density (mirrors FabricAnalysis) ----


def projection_radius(theta_deg, equal_area=True):
    """Radial distance on a unit primitive, theta measured from the downward vertical."""
    half = R(min(max(theta_deg, 0.0), 90.0)) / 2
    return math.sqrt(2) * math.sin(half) if equal_area else math.tan(half)


def kamb_counting_circle(sample_count, criterion=3.0):
    """(area fraction, angular radius in radians, expected count, standard deviation).

    Two routes to the same circle, and they are worth stating because each checks the
    other. Statistically, E = Na and sigma = sqrt(Na(1-a)), so E = k*sigma forces
    a = k^2/(N + k^2). Geometrically, the equal-area projection preserves area, so the
    circle's projected radius is sqrt(a) = k/sqrt(N + k^2) -- the form usually quoted.
    """
    a = criterion * criterion / (sample_count + criterion * criterion)
    rho = math.acos(1 - a)
    return a, rho, sample_count * a, math.sqrt(sample_count * a * (1 - a))


def spiral_axes(count):
    """Deterministic, exactly area-uniform axial sample. Uniform in cos(theta)."""
    golden = math.pi * (3 - math.sqrt(5))
    out = []
    for k in range(count):
        up = (k + 0.5) / count
        ring = math.sqrt(max(0.0, 1 - up * up))
        phi = k * golden
        out.append(neg(upper_hemisphere((ring * math.cos(phi), ring * math.sin(phi), up))))
    return out


def kamb_grid_mean(axes, steps, criterion=3.0):
    """Mean density over the grid nodes inside the primitive, in sigma."""
    n = len(axes)
    _, rho, _, sigma = kamb_counting_circle(n, criterion)
    total = 0.0
    nodes = 0
    for iy in range(steps):
        for ix in range(steps):
            x = -1 + 2 * (ix + 0.5) / steps
            y = -1 + 2 * (iy + 0.5) / steps
            r = math.hypot(x, y)
            if r > 1:
                continue
            theta = 2 * math.asin(clamp(r / math.sqrt(2), 0, 1))
            azm = math.atan2(x, y)
            node = (math.sin(theta) * math.cos(azm),
                    -math.sin(theta) * math.sin(azm),
                    -math.cos(theta))
            count = sum(1 for u in axes
                        if math.acos(clamp(abs(dot(norm(u), node)), 0, 1)) <= rho)
            total += count / sigma
            nodes += 1
    return total / nodes if nodes else 0.0


def octant(vector):
    return (1 if vector[0] >= 0 else 0) | (2 if vector[1] >= 0 else 0) | (4 if vector[2] >= 0 else 0)


def in_magnetic_frame(azimuth, declination_east):
    """true = magnetic + declination, declination positive east."""
    return az(azimuth - declination_east)


# ---------------------------------------------------------------- checks ----

FAILURES = []


def check(name, got, want, tol=1e-9):
    if not (abs(got - want) <= tol):
        FAILURES.append(f"{name}: got {got!r}, want {want!r} (tol {tol})")


def check_azimuth(name, got, want, tol=1e-9):
    sep = min(abs(got - want), 360.0 - abs(got - want))
    if not (sep <= tol):
        FAILURES.append(f"{name}: azimuths {got} and {want} differ by {sep} (tol {tol})")


def device_quaternion(dip, dipdir, spin):
    """Device attitude that places +Z along a plane's upward normal, then spins."""
    n = normal_from_plane(dip, dipdir)
    r = (1.0, 0.0, 0.0) if abs(n[0]) < 0.9 else (0.0, 1.0, 0.0)
    ex = norm(cross(r, n))
    ey = cross(n, ex)
    s = R(spin)
    c0 = tuple(math.cos(s) * ex[i] + math.sin(s) * ey[i] for i in range(3))
    c1 = tuple(-math.sin(s) * ex[i] + math.cos(s) * ey[i] for i in range(3))
    return q_from_columns(c0, c1, n)


def placement_test_frame(dip, dipdir, placement):
    """Columns of a device->world rotation that rests `placement` on a known plane.

    Mirrors the test helper in MeasurementRecorderTests: the contacting axis is put along
    the outward normal and the other two device axes go anywhere orthogonal, because how
    far the phone is rolled against the rock cannot change the attitude it reads. Each
    triple has to be right-handed, or it is not a rotation at all.
    """
    n = normal_from_plane(dip, dipdir)
    r = (1.0, 0.0, 0.0) if abs(n[0]) < 0.9 else (0.0, 1.0, 0.0)
    u = norm(cross(r, n))
    v = cross(n, u)
    axis = OUTWARD_NORMAL_AXIS[placement]
    if axis == (0.0, 0.0, 1.0):
        return u, v, n
    if axis == (0.0, 0.0, -1.0):
        return u, neg(v), neg(n)
    if axis == (1.0, 0.0, 0.0):
        return n, u, v
    if axis == (-1.0, 0.0, 0.0):
        return neg(n), u, neg(v)
    if axis == (0.0, 1.0, 0.0):
        return v, n, u
    return neg(v), neg(n), u


def kamb_moments(radius, weighting="kamb", steps=20000, to_quadrant=False):
    """Weight moments by midpoint quadrature.

    `to_quadrant` integrates to pi/2 instead of stopping at the radius, which is the
    version that was wrong: for the hard circle the weight steps from 1 to 0 at the
    radius, and a midpoint cell straddling a step is only O(h) accurate.
    """
    upper = math.pi / 2 if to_quadrant else min(radius, math.pi / 2)
    h = upper / steps
    first = second = 0.0
    for i in range(steps):
        phi = (i + 0.5) * h
        if phi >= radius:
            continue
        w = 1.0 if weighting == "kamb" else (1 - (phi / radius) ** 2) ** 2
        measure = math.sin(phi) * h
        first += w * measure
        second += w * w * measure
    return first, second


def project_curve_point(v, equal_area=True):
    """(east, north) on the net, folding only what is STRICTLY above the horizon."""
    u = norm(v)
    down = neg(u) if u[2] > 0 else u
    theta = D(math.acos(clamp(-down[2], -1, 1)))
    radius = projection_radius(theta, equal_area)
    azimuth = math.atan2(-down[1], down[0])
    return radius * math.sin(azimuth), radius * math.cos(azimuth)


def project_axis_point(v, equal_area=True):
    """(east, north) on the net for an AXIS, folded by the equator tie-break."""
    return project_curve_point(neg(upper_hemisphere(v)), equal_area)


def point_azimuth(point):
    east, north = point
    return az(D(math.atan2(east, north)))


def main():
    # 1. The specified round-trip accuracy: better than 0.01 deg.
    worst_dip = worst_dipdir = 0.0
    for dip in (0, 5, 15, 30, 45, 60, 75, 89, 90):
        for dipdir in (0, 45, 90, 135, 180, 225, 270, 315, 359):
            for spin in (0, 37, 155, 291):
                gd, gdd = plane_from_device_quaternion(device_quaternion(dip, dipdir, spin))
                worst_dip = max(worst_dip, abs(gd - dip))
                # A horizontal plane has no dip direction; a vertical one has two
                # equally valid ones. Outside that band the value itself must match.
                if 0.5 <= dip <= 89.5:
                    worst_dipdir = max(worst_dipdir, abs(az(gdd - dipdir + 180) - 180))
                else:
                    check(f"round trip geometry {dip}/{dipdir} spin {spin}",
                          dihedral((gd, gdd), (dip, dipdir)), 0.0, DIHEDRAL_FLOOR)
    print(f"round trip: worst dip error {worst_dip:.2e} deg, worst dip direction error {worst_dipdir:.2e} deg")
    check("round trip dip", worst_dip, 0.0, 1e-2)
    check("round trip dip direction", worst_dipdir, 0.0, 1e-2)

    # 2. The upward normal leans TOWARD the dip direction. Ground truth comes from a
    #    surface defined independently of the conversion: up = -tan(30)*east.
    n = (0.0, -math.tan(R(30)), 1.0)          # NWU: west = -east
    d, dd = plane_from_normal(n)
    check("east-sloping surface dip", d, 30.0)
    check_azimuth("east-sloping surface dip direction", dd, 90.0)

    # 3. Cardinal facing directions.
    for dip, dipdir in ((20, 0), (30, 90), (55, 180), (70, 270)):
        d, dd = plane_from_normal(normal_from_plane(dip, dipdir))
        check(f"cardinal dip {dip}/{dipdir}", d, float(dip))
        check_azimuth(f"cardinal dip direction {dip}/{dipdir}", dd, float(dipdir))

    # 5. Vertical planes: two valid descriptions, one geometry. The reported dip
    #    direction may flip under noise; the plane it denotes must not.
    for dipdir in (0, 90, 180, 270):
        n = normal_from_plane(90, dipdir)
        for eps in (1e-9, -1e-9, 1e-6, -1e-6):
            got = plane_from_normal((n[0], n[1], n[2] + eps))
            check(f"vertical dip {dipdir}", got[0], 90.0, 1e-3)
            check(f"vertical geometry preserved {dipdir} under noise {eps}",
                  dihedral(got, (90, dipdir)), 0.0, 1e-3)   # noise itself dominates here
            check_azimuth(f"vertical canonical form {dipdir} under noise {eps}",
                          canonicalized(*got)[1], canonicalized(90, float(dipdir))[1], 1e-3)

    # Either face of a plane gives one attitude, vertical included -- and the
    # 89.7-degree case a "keep the measured face" rule would get 180 degrees wrong.
    for dip in (10, 45, 80, 89, 89.7, 90):
        for dipdir in (0, 15, 90, 270):
            n = normal_from_plane(dip, dipdir)
            a, b = plane_from_normal(n), plane_from_normal(neg(n))
            check(f"face invariance dip {dip}/{dipdir}", a[0], b[0])
            check_azimuth(f"face invariance dip direction {dip}/{dipdir}", a[1], b[1])
            check(f"attitude recovered from either face {dip}/{dipdir}",
                  dihedral(a, (dip, dipdir)), 0.0, DIHEDRAL_FLOOR)

    # An exactly horizontal normal must not depend on the sign of a zero.
    for n in ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.6, -0.8, 0.0)):
        a, b = plane_from_normal(n), plane_from_normal(neg(n))
        check(f"equator tie-break dip {n}", a[0], b[0], 0.0)
        check(f"equator tie-break dip direction {n}", a[1], b[1], 0.0)

    # 6. Continuity approaching vertical.
    for dip in (88.0, 89.0, 89.4, 89.6, 90.0):
        d, dd = plane_from_normal(normal_from_plane(dip, 90))
        check(f"continuity dip {dip}", d, dip)
        check_azimuth(f"continuity dip direction {dip}", dd, 90.0)

    # 7. Normal / dip vector / strike vector are an orthonormal triad.
    for dip in (0, 15, 45, 75, 90):
        for dipdir in (0, 77, 200, 333):
            n, dv, sv = normal_from_plane(dip, dipdir), dip_vector(dip, dipdir), strike_vector(dipdir)
            check(f"|dv| {dip}/{dipdir}", math.sqrt(dot(dv, dv)), 1.0, 1e-12)
            check(f"n.dv {dip}/{dipdir}", dot(n, dv), 0.0, 1e-12)
            check(f"n.sv {dip}/{dipdir}", dot(n, sv), 0.0, 1e-12)
            check(f"dv.sv {dip}/{dipdir}", dot(dv, sv), 0.0, 1e-12)

    # 8. Apparent dip.
    check("apparent dip along dip direction", apparent_dip2(45, 0, 0), 45.0)
    check("apparent dip along strike", apparent_dip2(45, 0, 90), 0.0)
    check("apparent dip 45/000 along 060", apparent_dip2(45, 0, 60), 26.5650511771, 1e-8)
    check("apparent dip 45/000 along 240", apparent_dip2(45, 0, 240), -26.5650511771, 1e-8)
    check("apparent dip 60/090 along 135", apparent_dip2(60, 90, 135), 50.7684795164, 1e-8)

    # 9. Lineations through the device -Y axis.
    for trend in (0, 45, 90, 180, 270, 359):
        for plunge in (0, 15, 45, 75, 90):
            v = axis_from_line(trend, plunge)
            c1 = neg(v)
            r = (1.0, 0.0, 0.0) if abs(c1[0]) < 0.9 else (0.0, 0.0, 1.0)
            c2 = norm(cross(c1, r))
            c0 = cross(c1, c2)
            gt, gp = line_from_device_quaternion(q_from_columns(c0, c1, c2))
            check(f"plunge {plunge}->{trend}", gp, float(plunge), 1e-2)
            if 0.5 <= plunge <= 89.5:
                check_azimuth(f"trend {plunge}->{trend}", gt, float(trend), 1e-2)
            else:
                # A vertical line has no trend and a horizontal one has two ends;
                # the line itself must still come back.
                axial = D(math.acos(clamp(abs(dot(axis_from_line(gt, gp),
                                                  axis_from_line(trend, plunge))), 0, 1)))
                check(f"line geometry {plunge}->{trend}", axial, 0.0, DIHEDRAL_FLOOR)

    # A horizontal lineation must resolve to one trend from either end.
    for axis in ((1.0, 0.0, 0.0), (0.6, -0.8, 0.0)):
        a, b = line_from_axis(axis), line_from_axis(neg(axis))
        check(f"horizontal lineation trend is sign-independent {axis}", a[0], b[0], 0.0)
        check(f"horizontal lineation plunge is sign-independent {axis}", a[1], b[1], 0.0)

    # 10. ARKit .gravityAndHeading -> NWU is a proper rotation.
    m = [from_arkit(1, 0, 0), from_arkit(0, 1, 0), from_arkit(0, 0, 1)]
    check("ARKit east -> west component", m[0][1], -1.0, 1e-15)
    check("ARKit up", m[1][2], 1.0, 1e-15)
    check("ARKit determinant", dot(m[0], cross(m[1], m[2])), 1.0, 1e-12)
    d, dd = plane_from_normal(from_arkit(math.sin(R(30)), math.cos(R(30)), 0))
    check("ARKit plane fit dip", d, 30.0)
    check_azimuth("ARKit plane fit dip direction", dd, 90.0)

    # 11. Plane relations.
    check("dihedral 45/000 vs 45/180", dihedral((45, 0), (45, 180)), 90.0)
    check("dihedral 30/090 vs 60/090", dihedral((30, 90), (60, 90)), 30.0)
    inter = line_from_axis(cross(normal_from_plane(45, 0), normal_from_plane(45, 180)))
    check("intersection plunge", inter[1], 0.0)
    check("intersection trend (axial)", min(abs(inter[0] - 90), abs(inter[0] - 270)), 0.0)

    # 12. Axial averaging.
    mean, lam, sd, mx, mean_dev = axial_stats([normal_from_plane(45, 90)] * 5)
    check("identical samples sigma", sd, 0.0)
    check("identical samples lambda1", lam[0], 1.0, 1e-12)

    samples = [normal_from_plane(43, 90), normal_from_plane(47, 90),
               normal_from_plane(45, 88), normal_from_plane(45, 92)]
    mean, lam, sd, mx, mean_dev = axial_stats(samples)
    pd, pdd = plane_from_normal(mean)
    # 44.991, not 45: averaging happens on the sphere, not on the dip angles.
    check("burst mean dip", pd, 44.9912635961, 1e-9)
    check_azimuth("burst mean dip direction", pdd, 90.0)
    check("burst sigma", sd, 1.9999576883, 1e-9)
    check("burst mean deviation", mean_dev, 1.7070484085, 1e-9)
    check("burst max deviation", mx, 2.0087364039, 1e-9)

    flipped = [neg(v) if i % 2 == 0 else v for i, v in enumerate(samples)]
    fmean, flam, fsd, _, _ = axial_stats(flipped)
    check("sign-flipped mean dip", plane_from_normal(fmean)[0], pd)
    check("sign-flipped sigma", fsd, sd)
    arithmetic = [sum(v[i] for v in flipped) / 4 for i in range(3)]
    arithmetic_length = math.sqrt(sum(c * c for c in arithmetic))
    print(f"axial mean survives sign flips; the arithmetic mean collapses to length {arithmetic_length:.4f}")
    check("arithmetic mean collapses", arithmetic_length, 0.0, 0.1)

    jitter = [normal_from_plane(90 - abs(x), 90 + x) for x in (-0.3, -0.1, 0.0, 0.2, 0.4)]
    east_axis = axial_stats(jitter)[0]
    west_axis = axial_stats([neg(v) for v in jitter])[0]
    # One plane whichever face the burst came from ...
    check("near-vertical burst mean dip", plane_from_normal(east_axis)[0], 89.8, 1e-3)
    check_azimuth("near-vertical burst mean dip direction", plane_from_normal(east_axis)[1], 90.04, 1e-3)
    check("near-vertical burst same plane from either face",
          plane_from_normal(east_axis)[0], plane_from_normal(west_axis)[0], 1e-12)
    check_azimuth("near-vertical burst same dip direction from either face",
                  plane_from_normal(east_axis)[1], plane_from_normal(west_axis)[1], 1e-12)
    # ... while the mean axis still remembers which way the phone faced.
    check_azimuth("mean axis keeps the measured sense (east)", az(D(math.atan2(-east_axis[1], east_axis[0]))), 90.04, 1e-3)
    check_azimuth("mean axis keeps the measured sense (west)", az(D(math.atan2(-west_axis[1], west_axis[0]))), 270.04, 1e-3)

    girdle = [normal_from_plane(90, a) for a in (0, 30, 60, 90, 120, 150)]
    _, glam, _, _, _ = axial_stats(girdle)
    check("girdle lambda1", glam[0], 0.5)
    check("girdle lambda2", glam[1], 0.5)
    check("girdle lambda3", glam[2], 0.0)
    check("eigenvalue sum", sum(glam), 1.0, 1e-12)

    cluster = [normal_from_plane(30 + i, 100 + 2 * i) for i in range(10)]
    _, clam, _, _, _ = axial_stats(cluster)
    check("tight cluster lambda1", clam[0], 0.994312, 1e-6)

    lines = [axis_from_line(118, 29), axis_from_line(122, 31), axis_from_line(120, 30)]
    lmean, _, lsd, _, _ = axial_stats(lines)
    lt, lp = line_from_axis(lmean)
    check_azimuth("lineation mean trend", lt, 120.0, 0.2)
    check("lineation mean plunge", lp, 30.0, 0.2)

    # 13. Quadrant notation.
    known = {
        (45, 120): "N30E, 45SE",
        (45, 240): "N30W, 45SW",
        (30, 90): "N-S, 30E",
        (60, 0): "E-W, 60N",
        (20, 315): "N45E, 20NW",
        (75, 200): "N70W, 75S",
        (90, 90): "N-S, 90",
        (0, 0): "Horizontal",
    }
    for (dip, dipdir), expected in known.items():
        got = plane_quadrant_description(float(dip), float(dipdir))
        if got != expected:
            FAILURES.append(f"quadrant text {dip}/{dipdir}: got {got!r}, want {expected!r}")

    for dip in (1, 5, 15, 30, 45, 60, 75, 85, 89):
        for dipdir in range(0, 360, 3):
            text = plane_quadrant_description(float(dip), float(dipdir))
            got = parse_plane_quadrant(text)
            if got is None:
                FAILURES.append(f"quadrant round trip {dip}/{dipdir}: {text!r} did not parse")
                continue
            check(f"quadrant round trip dip {dip}/{dipdir}", got[0], float(dip))
            check_azimuth(f"quadrant round trip dip direction {dip}/{dipdir}", got[1], float(dipdir))

    # A vertical plane keeps its geometry, not its description.
    for dipdir in (0, 90, 180, 270):
        text = plane_quadrant_description(90.0, float(dipdir))
        got = parse_plane_quadrant(text)
        check(f"vertical quadrant round trip {dipdir}", dihedral(got, (90, dipdir)), 0.0, DIHEDRAL_FLOOR)

    for text in ("N45E, 45NE", "N45E, 45SW", "N30E, 45", "N30E, 45XY",
                 "N30E, 120SE", "hello", "45SE", ""):
        if parse_plane_quadrant(text) is not None:
            FAILURES.append(f"quadrant parse should have rejected {text!r}")
    for text in ("N45E, 45SE", "N30E, 90", "N30E/45SE", "n 30 e 45 se",
                 "E-W, 60N", "N-S, 30E", "N30E, 90SE"):
        if parse_plane_quadrant(text) is None:
            FAILURES.append(f"quadrant parse should have accepted {text!r}")

    # 14. Magnetic declination: true = magnetic + declination, positive east.
    check_azimuth("Taiwan declination", in_magnetic_frame(0.0, -4.0), 4.0)
    check_azimuth("east declination", in_magnetic_frame(90.0, 10.0), 80.0)
    for true_azimuth in (0.0, 5.0, 90.0, 180.0, 355.0, 359.0):
        for declination in (-4.0, 10.0, 0.0):
            magnetic = in_magnetic_frame(true_azimuth, declination)
            check_azimuth(f"declination round trip {true_azimuth}/{declination}",
                          az(magnetic + declination), true_azimuth)

    # 15. Device placement signs, checked physically: rest the phone on a horizontal
    #     surface and the outward normal of that surface must point UP, never down.
    #     An attitude cannot catch a flipped sign here, because attitudes are axial.
    resting = {
        # placement: device axis images in world NWU (x, y, z columns)
        "backOnFace": ((1, 0, 0), (0, 1, 0), (0, 0, 1)),            # flat on its back
        "leftSideOnFace": ((0, 0, 1), (1, 0, 0), (0, 1, 0)),        # standing on left side
        "bottomEdgeOnFace": ((1, 0, 0), (0, 0, 1), (0, -1, 0)),     # standing on bottom edge
    }
    for placement, (cx, cy, cz) in resting.items():
        determinant = dot(cx, cross(cy, cz))
        check(f"{placement} test frame is a rotation", determinant, 1.0, 1e-12)
        axis = OUTWARD_NORMAL_AXIS[placement]
        world = tuple(axis[0] * cx[i] + axis[1] * cy[i] + axis[2] * cz[i] for i in range(3))
        check(f"{placement} outward normal points up", world[2], 1.0, 1e-12)
        check(f"{placement} reads a horizontal plane", plane_from_normal(world)[0], 0.0, 1e-9)

    # Opposite placements are the two faces of one plane: same attitude, reversed
    # measured direction.
    for a, b in (("backOnFace", "screenOnFace"),
                 ("leftSideOnFace", "rightSideOnFace"),
                 ("bottomEdgeOnFace", "topEdgeOnFace")):
        check(f"{a}/{b} are opposite directions",
              dot(OUTWARD_NORMAL_AXIS[a], OUTWARD_NORMAL_AXIS[b]), -1.0, 1e-15)

    # 16. Stillness: the vector test catches steady rocking that a magnitude test misses.
    rocking = [(0.05 * math.cos(k * 0.7), 0.05 * math.sin(k * 0.7), 0.0) for k in range(15)]
    magnitudes = [math.sqrt(sum(c * c for c in v)) for v in rocking]
    mean_magnitude = sum(magnitudes) / len(magnitudes)
    magnitude_spread = math.sqrt(
        sum((m - mean_magnitude) ** 2 for m in magnitudes) / (len(magnitudes) - 1))
    check("rocking holds its magnitude constant", magnitude_spread, 0.0, 1e-12)
    vector_spread = vector_standard_deviation(rocking)
    print(f"steady rocking: magnitude spread {magnitude_spread:.2e} g "
          f"(reads as still), vector spread {vector_spread:.4f} g (does not)")
    if vector_spread <= 0.02:
        FAILURES.append("steady rocking should not pass the stillness threshold")

    quiet = [(0.002 * math.sin(k), 0.002 * math.cos(k), 0.001) for k in range(15)]
    if vector_standard_deviation(quiet) > 0.02:
        FAILURES.append("a quiet hand-held phone should pass the stillness threshold")

    # 17. Burst shape at the documented settings.
    start, end, count, rate = burst_shape(64.0, 1.5, 10)
    check("burst first collected index", float(start), 9.0, 0.0)
    check("burst last index", float(end), 105.0, 0.0)
    check("burst sample count", float(count), 97.0, 0.0)
    check("burst effective rate", rate, 64.0, 1e-9)
    _, _, slow_count, slow_rate = burst_shape(32.0, 1.5, 10)
    check("slow burst sample count", float(slow_count), 49.0, 0.0)
    check("slow burst effective rate", slow_rate, 32.0, 1e-9)
    if slow_rate >= 50.0 * 0.8:
        FAILURES.append("32 Hz should not satisfy a 50 Hz request")

    # 18. Magnetic verdicts.
    magnetic_cases = [
        ((48, 2, 5), "good", []),
        ((48, 1, None), "good", []),
        ((120, 2, 5), "disturbed", ["fieldStrengthOutsideEarthRange"]),
        ((24.9, 2, 5), "disturbed", ["fieldStrengthOutsideEarthRange"]),
        ((25, 2, 5), "good", []),
        ((65, 2, 5), "good", []),
        ((48, 0, 5), "disturbed", ["magnetometerPoorlyCalibrated"]),
        ((48, -1, 5), "disturbed", ["magnetometerUncalibrated"]),
        ((48, 2, -1), "disturbed", ["headingInvalid"]),
        ((48, 2, 15), "marginal", ["headingAccuracyMarginal"]),
        ((48, 2, 25), "disturbed", ["headingAccuracyUnusable"]),
        ((None, 2, 5), "marginal", ["fieldStrengthUnknown"]),
        ((120, 2, 15), "disturbed",
         ["fieldStrengthOutsideEarthRange", "headingAccuracyMarginal"]),
    ]
    for (strength, accuracy, heading), expected_verdict, expected_reasons in magnetic_cases:
        verdict, reasons = magnetic_verdict(strength, accuracy, heading)
        if verdict != expected_verdict or reasons != expected_reasons:
            FAILURES.append(
                f"magnetic {strength}/{accuracy}/{heading}: got {verdict} {reasons}, "
                f"want {expected_verdict} {expected_reasons}")

    # 19. Calibration error decomposition.
    tilt, azimuth, total = calibration_error((45, 90), (45, 95))
    check("magnetometer-only tilt error", tilt, 0.0, 1e-12)
    check("magnetometer-only azimuth error", azimuth, 5.0, 1e-12)
    check("magnetometer-only total error", total, 3.534973, 1e-5)
    tilt, azimuth, total = calibration_error((45, 90), (46, 90))
    check("gravity-only tilt error", tilt, 1.0, 1e-12)
    check("gravity-only azimuth error", azimuth, 0.0, 1e-12)
    check("gravity-only total error", total, 1.0, 1e-9)
    tilt, azimuth, total = calibration_error((45, 90), (46, 95))
    check("combined total error", total, 3.703097, 1e-5)
    _, azimuth, _ = calibration_error((30, 2), (30, 358))
    check("azimuth error wraps across north", azimuth, -4.0, 1e-12)

    # 20. Placement cross-check: an opinion only when the impulse earns one.
    impulse_cases = [
        ([(0.01, 0.01, -0.4), (0.02, -0.01, -0.9), (0.0, 0.01, -0.5), (0.01, 0.0, -0.1)], "z"),
        ([(0.7, 0.02, 0.01), (0.4, -0.01, 0.02), (0.1, 0.0, 0.0)], "x"),
        ([(0.01, 0.0, -0.03), (0.0, 0.01, -0.02)], None),      # placed gently
        ([(0.3, 0.31, 0.29), (0.28, 0.3, 0.32)], None),        # slid in, or hand tremor
        ([], None),
    ]
    for accelerations, expected in impulse_cases:
        axis, confidence, peak = impulse_axis(accelerations)
        if axis != expected:
            FAILURES.append(
                f"impulse {accelerations}: got {axis} (confidence {confidence:.3f}, "
                f"peak {peak:.3f}), want {expected}")

    # 21. Octant coverage: eight sign combinations, eight distinct bins.
    bins = {octant((sx, sy, sz)) for sx in (1, -1) for sy in (1, -1) for sz in (1, -1)}
    check("octant count", float(len(bins)), 8.0, 0.0)
    check("all-positive octant", float(octant((1, 1, 1))), 7.0, 0.0)
    check("all-negative octant", float(octant((-1, -1, -1))), 0.0, 0.0)

    # 22. ISRM class boundaries: the tables tile their scale, with no gaps and no
    #     overlaps. A gap or an overlap would make a classification depend on the order
    #     the cases happen to be declared in - which is the defect in the published
    #     aperture table.
    for title, table, limit, step in (
        ("spacing", SPACING_CLASSES_MM, 7000.0, 0.5),
        ("persistence", PERSISTENCE_CLASSES_M, 25.0, 0.01),
        ("aperture", APERTURE_CLASSES_MM, 1200.0, 0.05),
    ):
        value = 0.0
        while value <= limit:
            matches = [name for name, lower, upper in table if lower <= value < upper]
            if len(matches) != 1:
                FAILURES.append(f"{title} {value:g} matched {matches}")
                break
            value += step

    boundary_cases = [
        (SPACING_CLASSES_MM, 0.0, "extremelyClose"), (SPACING_CLASSES_MM, 20.0, "veryClose"),
        (SPACING_CLASSES_MM, 60.0, "close"), (SPACING_CLASSES_MM, 200.0, "moderate"),
        (SPACING_CLASSES_MM, 600.0, "wide"), (SPACING_CLASSES_MM, 2000.0, "veryWide"),
        (SPACING_CLASSES_MM, 6000.0, "extremelyWide"),
        (PERSISTENCE_CLASSES_M, 1.0, "low"), (PERSISTENCE_CLASSES_M, 3.0, "medium"),
        (PERSISTENCE_CLASSES_M, 10.0, "high"), (PERSISTENCE_CLASSES_M, 20.0, "veryHigh"),
        (APERTURE_CLASSES_MM, 0.1, "tight"), (APERTURE_CLASSES_MM, 0.25, "partlyOpen"),
        (APERTURE_CLASSES_MM, 0.5, "open"), (APERTURE_CLASSES_MM, 2.5, "moderatelyWide"),
        (APERTURE_CLASSES_MM, 10.0, "veryWide"), (APERTURE_CLASSES_MM, 100.0, "extremelyWide"),
        (APERTURE_CLASSES_MM, 1000.0, "cavernous"),
    ]
    for table, value, expected in boundary_cases:
        got = classify(value, table)
        if got != expected:
            FAILURES.append(f"boundary {value:g}: got {got}, want {expected}")

    for table in (SPACING_CLASSES_MM, PERSISTENCE_CLASSES_M, APERTURE_CLASSES_MM):
        for bad in (-1.0, float("nan"), math.inf):
            if classify(bad, table) is not None:
                FAILURES.append(f"{bad} should not classify")

    numbers = [number for _, _, number in ROUGHNESS_CLASSES]
    check("roughness class count", float(len(numbers)), 9.0, 0.0)
    check("roughness numbers are 1..9", float(len(set(numbers))), 9.0, 0.0)
    if numbers != list(range(1, 10)):
        FAILURES.append(f"roughness numbering is {numbers}, want 1..9 in order")

    # 23. Both seepage tables are numbered I-V and must stay distinguishable.
    check("unfilled seepage ratings", float(len(UNFILLED_SEEPAGE)), 5.0, 0.0)
    check("filled seepage ratings", float(len(FILLED_SEEPAGE)), 5.0, 0.0)
    if [r for r, _ in UNFILLED_SEEPAGE] != [1, 2, 3, 4, 5]:
        FAILURES.append("unfilled seepage ratings are not 1..5 in order")
    if [r for r, _ in FILLED_SEEPAGE] != [1, 2, 3, 4, 5]:
        FAILURES.append("filled seepage ratings are not 1..5 in order")
    unfilled_names = {name for _, name in UNFILLED_SEEPAGE}
    filled_names = {name for _, name in FILLED_SEEPAGE}
    if unfilled_names & filled_names:
        FAILURES.append(f"the two seepage tables share case names: {unfilled_names & filled_names}")

    # 24. The legacy aperture class really does overlap, which is why it is not derivable.
    overlapping = [
        name for name, lower, upper in APERTURE_CLASSES_MM
        if name != "wide" and lower < APERTURE_LEGACY_WIDE[2] and APERTURE_LEGACY_WIDE[1] < upper
    ]
    if set(overlapping) != {"veryWide", "extremelyWide", "cavernous"}:
        FAILURES.append(f"legacy 'wide' overlaps {overlapping}, expected the three open classes")
    if classify(50.0, APERTURE_CLASSES_MM) != "veryWide":
        FAILURES.append("50 mm must derive veryWide, not the legacy class")

    # 25. Discontinuity type storage keys round trip, including a labelled `other`.
    if len(set(DISCONTINUITY_TYPES)) != len(DISCONTINUITY_TYPES):
        FAILURES.append("duplicate discontinuity type key")
    check("discontinuity type count", float(len(DISCONTINUITY_TYPES)), 15.0, 0.0)
    for case in DISCONTINUITY_TYPES:
        if discontinuity_from_storage_key(discontinuity_storage_key(case)) != (case, None):
            FAILURES.append(f"type key {case} did not round trip")
        if ":" in case:
            FAILURES.append(f"standard key {case} must not look like other:…")
    for label in ("擠壓帶", "", "zone: sheared"):
        key = discontinuity_storage_key("other", label)
        if discontinuity_from_storage_key(key) != ("other", label):
            FAILURES.append(f"other label {label!r} did not round trip through {key!r}")
    for bad_key in ("sandwich", "", "Joint"):
        if discontinuity_from_storage_key(bad_key) is not None:
            FAILURES.append(f"{bad_key!r} should not resolve to a type")
    check("zone type count", float(len(ZONE_TYPES & set(DISCONTINUITY_TYPES))), 2.0, 0.0)
    if "fault" in ZONE_TYPES:
        FAILURES.append("a discrete fault surface is not a zone")

    # 26. Every survey geometry names a correction method, and only the surface model
    #     asks for the area-weighted one.
    for name, method in SURVEY_GEOMETRIES.items():
        if method not in ("terzaghi", "areaWeightedSurface", "unavailable"):
            FAILURES.append(f"{name} names an unknown correction method {method}")
    area_weighted = {n for n, m in SURVEY_GEOMETRIES.items() if m == "areaWeightedSurface"}
    if area_weighted != {"surfaceModel"}:
        FAILURES.append(f"area-weighted correction claimed by {area_weighted}")

    # 27. Sampling bias. Terzaghi's original relation against a line.
    set_pole = normal_from_plane(30, 0)
    check("scanline along the pole", line_sampling_efficiency(set_pole, set_pole), 1.0)
    check("scanline in the plane",
          line_sampling_efficiency(set_pole, axis_from_line(270, 0)), 0.0)
    check("scanline at 60 deg to the pole",
          line_sampling_efficiency(set_pole, axis_from_line(0, 0)), 0.5)

    # Against a plane, the efficiency is the sine of the dihedral angle. Verified against
    # the trace spacing it comes from: parallel planes spaced S cut a face in lines
    # spaced S / sin(dihedral) apart, measured within that face.
    face_normal = normal_from_plane(90, 0)
    # Named `dihedral_angle`, not `dihedral`: a local of that name would shadow the
    # module-level dihedral() for the whole of main(), and Python then refuses the
    # earlier calls to it.
    for dihedral_angle in (0.0, 30.0, 45.0, 60.0, 90.0):
        pole = normal_from_plane(90, dihedral_angle)
        check(f"window efficiency at {dihedral_angle:g} deg",
              plane_sampling_efficiency(pole, face_normal), math.sin(R(dihedral_angle)))

    spacing = 0.5
    for (dip, dipdir), (face_dip, face_dipdir) in (
        ((60, 90), (90, 0)), ((30, 0), (85, 120)), ((45, 45), (90, 45)), ((20, 310), (70, 15))
    ):
        pole = norm(normal_from_plane(dip, dipdir))
        face = norm(normal_from_plane(face_dip, face_dipdir))
        trace = cross(pole, face)
        if math.sqrt(dot(trace, trace)) < 1e-12:
            continue
        trace = norm(trace)
        across = cross(face, trace)                 # in the face, across the traces
        measured = abs(spacing / dot(pole, across))  # in-face spacing of adjacent traces
        predicted = spacing / plane_sampling_efficiency(pole, face)
        check(f"trace spacing {dip}/{dipdir} on {face_dip}/{face_dipdir}", measured, predicted)

    # The inversion the typed sampling element exists to prevent.
    outcrop = normal_from_plane(90, 90)
    parallel_set = normal_from_plane(90, 90)
    perpendicular_set = normal_from_plane(0, 0)
    check("parallel set, plane formula", plane_sampling_efficiency(parallel_set, outcrop), 0.0)
    check("parallel set, line formula misused",
          line_sampling_efficiency(parallel_set, outcrop), 1.0)
    check("perpendicular set, plane formula",
          plane_sampling_efficiency(perpendicular_set, outcrop), 1.0)
    check("perpendicular set, line formula misused",
          line_sampling_efficiency(perpendicular_set, outcrop), 0.0)

    # 28. The area-weighted surface method reduces exactly to the planar one.
    face = normal_from_plane(85, 120)
    worst = 0.0
    for dip in range(0, 91, 5):
        for dipdir in range(0, 360, 15):
            pole = normal_from_plane(dip, dipdir)
            one_facet = surface_model_efficiency(pole, [(face, 17.0)])
            worst = max(worst, abs(one_facet - plane_sampling_efficiency(pole, face)))
    check("one-facet surface model equals the window", worst, 0.0, 1e-12)
    print(f"area-weighted surface vs window, one facet: worst difference {worst:.2e}")

    if surface_model_efficiency(normal_from_plane(45, 90), []) is not None:
        FAILURES.append("an empty surface model should have no efficiency")
    if surface_model_efficiency(normal_from_plane(45, 90), [(face, 0.0)]) is not None:
        FAILURES.append("a zero-area surface model should have no efficiency")

    # Area cancels: it is the orientations that matter, not the scale of the model.
    probe = normal_from_plane(40, 10)
    check("facet area cancels",
          surface_model_efficiency(probe, [(face, 1700.0)]),
          surface_model_efficiency(probe, [(face, 17.0)]), 1e-12)

    # 29. Blind zones. An exposure facing one way cannot see the joints parallel to it,
    #     and a cap would turn that zero into a finite weight and under-report the set.
    single = [(normal_from_plane(85, 120), 100.0)]
    mixed = [(normal_from_plane(85, 120), 60.0),
             (normal_from_plane(20, 300), 25.0),
             (normal_from_plane(70, 10), 15.0)]
    blind = surface_model_efficiency(normal_from_plane(85, 120), single)
    seen = surface_model_efficiency(normal_from_plane(85, 120), mixed)
    check("single-orientation exposure is blind to a parallel set", blind, 0.0, 1e-12)
    if not seen > 0.3:
        FAILURES.append(f"a multi-orientation exposure should see that set, got {seen}")
    print(f"blind zone: a set parallel to a one-orientation exposure scores {blind:.4f}, "
          f"and {seen:.4f} on a three-orientation one")

    for facets in (single, mixed):
        for dip in range(0, 91, 10):
            for dipdir in range(0, 360, 45):
                value = surface_model_efficiency(normal_from_plane(dip, dipdir), facets)
                if not 0.0 <= value <= 1.0:
                    FAILURES.append(f"efficiency {value} out of range")

    # 30. The press table, and the rules that make one blind button safe.
    for state, expected in PRESS_MEANING.items():
        got = press_outcome(state)
        if got != expected:
            FAILURES.append(f"a press in {state} should {expected}, got {got}")
    if PRESS_MEANING["settling"] != "cancelled" or PRESS_MEANING["collecting"] != "cancelled":
        FAILURES.append("a press while measuring must cancel, never start a second burst")
    if PRESS_MEANING["review-flagged"] == "saved":
        FAILURES.append("a flagged measurement must not accept a blind press")
    if PRESS_MEANING["review-clean"] != "saved":
        FAILURES.append("a clean measurement must accept a press, or the key is useless")
    if not ON_SCREEN_CONFIRM_ALWAYS_SAVES:
        FAILURES.append("an on-screen confirmation must always be allowed to save")

    # Key repeat and a cold-thumb double tap are swallowed; the deliberate accepting
    # press, which comes after a burst of well over a second, is not.
    for elapsed in (0.0, 0.05, 0.2, 0.34):
        if press_outcome("settling", elapsed) != "ignoredRepeatPress":
            FAILURES.append(f"a press {elapsed}s after the last should be ignored")
    for elapsed in (0.36, 1.5, 2.0):
        if press_outcome("settling", elapsed) == "ignoredRepeatPress":
            FAILURES.append(f"a press {elapsed}s after the last is deliberate")
    if REPEAT_PRESS_INTERVAL >= 1.0:
        FAILURES.append("the repeat interval must stay well under a burst's duration")

    looks = sum(1 for required in WARNINGS_REQUIRING_A_LOOK.values() if required)
    check("warnings that withdraw the blind path", float(looks), 4.0, 0.0)
    for name in ("sampleRateShortfall", "positionUnavailable"):
        if WARNINGS_REQUIRING_A_LOOK[name]:
            FAILURES.append(f"{name} should not stop the geologist")

    print("a press means:")
    for state, outcome in PRESS_MEANING.items():
        print(f"  {state:16s} -> {outcome}")

    # 31. Projection: both put the vertical at the centre and the horizontal on the
    #     primitive, and only the equal-area one preserves area.
    for equal_area in (True, False):
        check(f"centre radius (equal_area={equal_area})",
              projection_radius(0, equal_area), 0.0, 1e-12)
        check(f"primitive radius (equal_area={equal_area})",
              projection_radius(90, equal_area), 1.0, 1e-12)
    for cap in (5.0, 15.0, 30.0, 45.0, 60.0, 90.0):
        area = 1 - math.cos(R(cap))
        r = projection_radius(cap, True)
        check(f"equal-area preserves area at {cap:g} deg", r * r, area, 1e-12)
    r30 = projection_radius(30.0, False)
    if abs(r30 * r30 - (1 - math.cos(R(30.0)))) < 0.05:
        FAILURES.append("the equal-angle projection must NOT preserve area")

    # 32. The Kamb counting circle, by both routes.
    for n in (20, 50, 100, 200, 500, 1000):
        a, rho, expected, sigma = kamb_counting_circle(n)
        check(f"E = 3 sigma at N={n}", expected / sigma, 3.0)
        check(f"projected radius at N={n}", math.sqrt(a), 3.0 / math.sqrt(n + 9), 1e-12)
    check("counting circle at N=100", D(kamb_counting_circle(100)[1]), 23.447, 1e-3)
    check("counting circle at N=1000", D(kamb_counting_circle(1000)[1]), 7.658, 1e-3)
    radii = [kamb_counting_circle(n)[1] for n in (20, 50, 100, 500, 1000)]
    if any(b >= a for a, b in zip(radii, radii[1:])):
        FAILURES.append("a larger sample must earn a smaller counting circle")

    # 33. The whole normalization, end to end: a sample with no preferred orientation
    #     averages to the criterion over the grid, because the equal-area grid samples
    #     the hemisphere by equal area.
    for n in (200, 400, 800):
        mean = kamb_grid_mean(spiral_axes(n), 21)
        check(f"uniform grid mean at N={n}", mean, 3.0, 0.05)
    print(f"uniform sample, N=400: grid mean {kamb_grid_mean(spiral_axes(400), 21):.4f} sigma "
          f"(expected 3.0000)")

    # 34. Density saturates once a set is tighter than the counting circle, so a capped
    #     peak carries no information about concentration.
    _, rho, _, sigma = kamb_counting_circle(200)
    ceiling = 200 / sigma
    check("saturation ceiling at N=200", ceiling, 69.67, 0.01)
    if D(rho) < 16.0 or D(rho) > 17.5:
        FAILURES.append(f"counting circle at N=200 is {D(rho):.2f} deg, expected about 16.9")

    # 35. The test attitude has to be built for the placement the recorder is set to.
    #     Building it around the phone's back and then claiming the left side was used
    #     describes two different physical acts, and the plane that comes back is
    #     neither: for dip 61/020 it reads 58.32, which is what the suite caught.
    for placement in OUTWARD_NORMAL_AXIS:
        c0, c1, c2 = placement_test_frame(61, 20, placement)
        determinant = dot(c0, cross(c1, c2))
        check(f"{placement} attitude frame is a rotation", determinant, 1.0, 1e-12)
        world = qrotate(q_from_columns(c0, c1, c2), OUTWARD_NORMAL_AXIS[placement])
        read_dip, read_dipdir = plane_from_normal(world)
        check(f"{placement} reads the plane it was built for (dip)", read_dip, 61.0, 1e-9)
        check_azimuth(f"{placement} reads the plane it was built for (dipdir)",
                      read_dipdir, 20.0, 1e-9)

    # 36. The hard circle's moments have closed forms, m1 = m2 = a. Integrating over the
    #     weight's support reproduces them; integrating over the whole quadrant does not,
    #     and the error is far worse than the 1e-6 the suite asks for. Both directions are
    #     checked so the domain cannot quietly go back to pi/2.
    for sample_count in (50, 200, 1000):
        area, rho, _, _ = kamb_counting_circle(sample_count)
        first, second = kamb_moments(rho)
        check(f"m1 over the support at N={sample_count}", first, area, 1e-9)
        check(f"m2 over the support at N={sample_count}", second, area, 1e-9)
        stale_first, _ = kamb_moments(rho, to_quadrant=True)
        if abs(stale_first - area) < 1e-6:
            FAILURES.append(
                f"integrating to pi/2 at N={sample_count} is accurate to 1e-6, so the "
                f"reason for stopping at the radius no longer holds"
            )

    # 37. A recorded horizontal lineation plots at the trend it was recorded at. The axial
    #     fold would move half of them to trend + 180 -- correct for a pole, wrong for a
    #     datum the geologist wrote a trend for.
    for trend in (0, 45, 90, 135, 180, 225, 270, 315):
        axis = axis_from_line(trend, 0)
        check_azimuth(f"horizontal lineation at trend {trend} plots there",
                      point_azimuth(project_curve_point(axis)), trend, 1e-9)
        check(f"horizontal lineation at trend {trend} lands on the primitive",
              math.hypot(*project_curve_point(axis)), 1.0, 1e-9)
    moved = [t for t in (0, 45, 90, 135, 180, 225, 270, 315)
             if abs(azimuth_separation(point_azimuth(project_axis_point(axis_from_line(t, 0))), t)) > 1e-6]
    if len(moved) != 4:
        FAILURES.append(
            f"the axial fold should move exactly half of the horizontal trends, moved {moved}"
        )

    print("ISRM class boundaries, for checking against the standard:")
    print_isrm_tables()

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)} check(s)")
        for f in FAILURES:
            print("  -", f)
        return 1
    print("all reference checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
