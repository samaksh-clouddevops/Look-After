import Foundation

/// Unified currency of executive burden — comparable across domains.
/// Negative values mean burden reduction (benefit).
public struct ExecutiveCost: Codable, Sendable, Equatable {
    public var stress: Double
    public var time: Double
    public var money: Double
    public var energy: Double
    public var attention: Double
    public var restartTax: Double
    public var regret: Double
    public var opportunityCost: Double
    public var relationshipCost: Double
    public var healthCost: Double

    public init(
        stress: Double = 0,
        time: Double = 0,
        money: Double = 0,
        energy: Double = 0,
        attention: Double = 0,
        restartTax: Double = 0,
        regret: Double = 0,
        opportunityCost: Double = 0,
        relationshipCost: Double = 0,
        healthCost: Double = 0
    ) {
        self.stress = stress
        self.time = time
        self.money = money
        self.energy = energy
        self.attention = attention
        self.restartTax = restartTax
        self.regret = regret
        self.opportunityCost = opportunityCost
        self.relationshipCost = relationshipCost
        self.healthCost = healthCost
    }

    public var totalBurden: Double {
        stress + time + money + energy + attention + restartTax + regret
            + opportunityCost + relationshipCost + max(0, healthCost)
    }

    public static func + (lhs: ExecutiveCost, rhs: ExecutiveCost) -> ExecutiveCost {
        ExecutiveCost(
            stress: lhs.stress + rhs.stress,
            time: lhs.time + rhs.time,
            money: lhs.money + rhs.money,
            energy: lhs.energy + rhs.energy,
            attention: lhs.attention + rhs.attention,
            restartTax: lhs.restartTax + rhs.restartTax,
            regret: lhs.regret + rhs.regret,
            opportunityCost: lhs.opportunityCost + rhs.opportunityCost,
            relationshipCost: lhs.relationshipCost + rhs.relationshipCost,
            healthCost: lhs.healthCost + rhs.healthCost
        )
    }
}

/// Expected change in executive cost if the intent succeeds.
public struct ExecutiveCostDelta: Codable, Sendable, Equatable {
    public var stress: Double
    public var time: Double
    public var restartTax: Double
    public var energy: Double
    public var attention: Double

    public init(
        stress: Double = 0,
        time: Double = 0,
        restartTax: Double = 0,
        energy: Double = 0,
        attention: Double = 0
    ) {
        self.stress = stress
        self.time = time
        self.restartTax = restartTax
        self.energy = energy
        self.attention = attention
    }

    public var summaryLines: [String] {
        var lines: [String] = []
        if restartTax != 0 { lines.append(String(format: "restartTax %+.0f", restartTax)) }
        if stress != 0 { lines.append(String(format: "stress %+.0f", stress)) }
        if time != 0 { lines.append(String(format: "time %+.0f min", time)) }
        if energy != 0 { lines.append(String(format: "energy %+.0f", energy)) }
        if attention != 0 { lines.append(String(format: "attention %+.0f", attention)) }
        return lines
    }
}
