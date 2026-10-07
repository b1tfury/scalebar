import Testing
@testable import ScaleBarCore

@Test func compositionMatchesWeighPy() {
    // health.db row 2026-10-04T11:15:21, computed by scale/weigh.py.
    let c = Composition(weight: 94.2, impedance: 600, profile: .sahil)
    #expect(c.bmi == 28.1)
    #expect(c.fatPct == 34.1)
    #expect(c.waterPct == 45.7)
    #expect(c.skeletalMuscleKg == 29.0)
    #expect(c.boneKg == 3.5)
    #expect(c.bmrKcal == 1711)
}

@Test func compositionWithoutImpedanceIsBmiOnly() {
    let c = Composition(weight: 94.7, impedance: nil, profile: .sahil)
    #expect(c.bmi == 28.3)
    #expect(c.fatPct == nil)
}

@Test func parsesFrames() {
    func frame(_ b2: UInt8, _ b3: UInt8, _ b4: UInt8, _ b5: UInt8, _ b6: UInt8) -> [UInt8] {
        [0xAC, 0x02, b2, b3, b4, b5, b6, b2 &+ b3 &+ b4 &+ b5 &+ b6]
    }
    #expect(ScaleProtocol.parse(frame(0x24, 0xFE, 0, 0, 0xCE)) == .live(94.70))
    #expect(ScaleProtocol.parse(frame(0x24, 0xFE, 0, 0, 0xCA)) == .locked(94.70))
    #expect(ScaleProtocol.parse(frame(0xFD, 0x01, 0x02, 0x58, 0xCB)) == .impedance(600))
    #expect(ScaleProtocol.parse(frame(0xFD, 0x00, 0x00, 0x01, 0xCB)) == nil)
    #expect(ScaleProtocol.parse(frame(0xFD, 0xFF, 0, 0, 0xCB)) == .impedanceUnavailable)
    var bad = frame(0x24, 0xFE, 0, 0, 0xCA)
    bad[7] &+= 1
    #expect(ScaleProtocol.parse(bad) == nil)
}

@Test func silhouetteParses() throws {
    let path = try #require(ManSilhouette.path)
    let b = path.boundingBoxOfPath
    // Document is 939 x 2795; the figure should fill most of it.
    #expect(b.width > 600 && b.width < 940)
    #expect(b.height > 2500 && b.height < 2800)
}

@Test func svgPathRelativeCommands() throws {
    let p = try #require(SVGPath.parse("m 10,10 l 5,0 c 0,5 0,5 -5,5 z m 2,2 l 1,1 z"))
    let b = p.boundingBoxOfPath
    #expect(b.minX == 10 && b.minY == 10 && b.maxX == 15 && b.maxY == 15)
}

@Test func configPacketChecksum() {
    for p in ScaleProtocol.configPackets(profile: .sahil) {
        #expect(p.count == 8)
        #expect(p[2..<7].reduce(0, { $0 &+ $1 }) == p[7])
    }
}
