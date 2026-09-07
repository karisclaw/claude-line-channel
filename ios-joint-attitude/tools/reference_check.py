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
    r = math.fmod(deg, 360.0)
    return r + 360.0 if r < 0 else r

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

def plane_from_normal(n):
    m = norm(n)                           # as measured (outward from the rock face)
    up = neg(m) if m[2] < 0 else m        # flipped so it points upward
    dip = D(math.acos(clamp(up[2], -1.0, 1.0)))
    near_vertical = dip > 90.0 - VERT_TOL
    # For a (near-)vertical plane the sign of n_U is pure noise, so the up-flip would
    # make the dip direction flicker by 180 deg. Use the AS-MEASURED normal instead:
    # it encodes which side of the face the phone was held against.
    src = m if near_vertical else up
    dipdir = az(D(math.atan2(-src[1], src[0])))   # atan2(nE, nN), nE = -nW
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
    v = norm(v)
    if v[2] > 0: v = neg(v)               # point down-plunge
    nN, nW, nU = v
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


def main():
    # 1. The specified round-trip accuracy: better than 0.01 deg.
    worst_dip = worst_dipdir = 0.0
    for dip in (0, 5, 15, 30, 45, 60, 75, 89, 90):
        for dipdir in (0, 45, 90, 135, 180, 225, 270, 315, 359):
            for spin in (0, 37, 155, 291):
                gd, gdd = plane_from_device_quaternion(device_quaternion(dip, dipdir, spin))
                worst_dip = max(worst_dip, abs(gd - dip))
                if dip >= 0.5:
                    worst_dipdir = max(worst_dipdir, abs(az(gdd - dipdir + 180) - 180))
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

    # 4. Either face of the plane gives the same attitude.
    for dip in (10, 35, 60, 80):
        for dipdir in (15, 120, 300):
            n = normal_from_plane(dip, dipdir)
            a, b = plane_from_normal(n), plane_from_normal(neg(n))
            check(f"face invariance dip {dip}/{dipdir}", a[0], b[0])
            check_azimuth(f"face invariance dip direction {dip}/{dipdir}", a[1], b[1])

    # 5. Vertical planes: stable against noise on n_U, and each face reports itself.
    for dipdir in (0, 90, 180, 270):
        n = normal_from_plane(90, dipdir)
        for eps in (1e-9, -1e-9, 1e-6, -1e-6):
            d, dd = plane_from_normal((n[0], n[1], n[2] + eps))
            check(f"vertical dip {dipdir}", d, 90.0, 1e-3)
            check_azimuth(f"vertical dip direction {dipdir} under noise {eps}", dd, float(dipdir), 1e-3)
    check_azimuth("vertical east face", plane_from_normal(normal_from_plane(90, 90))[1], 90.0)
    check_azimuth("vertical west face", plane_from_normal(neg(normal_from_plane(90, 90)))[1], 270.0)

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
            if 0 < plunge <= 89.5:
                check_azimuth(f"trend {plunge}->{trend}", gt, float(trend), 1e-2)

    # 10. ARKit .gravityAndHeading -> NWU is a proper rotation.
    m = [from_arkit(1, 0, 0), from_arkit(0, 1, 0), from_arkit(0, 0, 1)]
    check("ARKit east -> west component", m[0][1], -1.0, 1e-15)
    check("ARKit up", m[1][2], 1.0, 1e-15)
    check("ARKit determinant", dot(m[0], cross(m[1], m[2])), 1.0, 1e-12)
    d, dd = plane_from_normal(from_arkit(math.sin(R(30)), math.cos(R(30)), 0))
    check("ARKit plane fit dip", d, 30.0)
    check_azimuth("ARKit plane fit dip direction", dd, 90.0)

    # 11. Plane relations.
    def dihedral(p1, p2):
        return D(math.acos(clamp(abs(dot(normal_from_plane(*p1), normal_from_plane(*p2))), 0, 1)))

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
    check_azimuth("vertical burst keeps east face", plane_from_normal(axial_stats(jitter)[0])[1], 90.0, 0.5)
    check_azimuth("vertical burst keeps west face",
                  plane_from_normal(axial_stats([neg(v) for v in jitter])[0])[1], 270.0, 0.5)

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
