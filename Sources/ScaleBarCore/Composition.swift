import Foundation

public struct Profile {
    public var sex: Int  // 1 = male
    public var age: Int
    public var heightCm: Int
    public init(sex: Int, age: Int, heightCm: Int) { (self.sex, self.age, self.heightCm) = (sex, age, heightCm) }

    /// Keep in sync with SEX, AGE, HEIGHT_CM in scale/weigh.py.
    public static let sahil = Profile(sex: 1, age: 33, heightCm: 183)
}

/// openScale StandardImpedanceLib, same formulas as scale/weigh.py `composition`.
public struct Composition: Equatable {
    public var bmi: Double
    public var fatPct: Double?
    public var fatKg: Double?
    public var ffmKg: Double?
    public var waterPct: Double?
    public var skeletalMuscleKg: Double?
    public var boneKg: Double?
    public var bmrKcal: Int?

    public init(weight w: Double, impedance imp: Int?, profile p: Profile) {
        let h = Double(p.heightCm)
        bmi = r1(w / pow(h / 100, 2))
        guard let imp, imp >= 1, imp < 1500 else { return }
        let z = Double(imp)
        let k = h * h / z
        let ffm = -10.68 + 0.65 * k + 0.26 * w + 0.02 * z
        let smm = 0.401 * k + 3.825 * Double(p.sex) - 0.071 * Double(p.age) + 5.102
        fatPct = r1(100 * (1 - ffm / w))
        fatKg = r1(w - ffm)
        ffmKg = r1(ffm)
        waterPct = r1(100 * 0.99513 * (1.2 + 0.45 * k + 0.18 * w) / w)
        skeletalMuscleKg = r1(smm)
        boneKg = r1(0.057 * ffm)
        bmrKcal = Int((ffm * 21.6 + 370).rounded())
    }
}

private func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
