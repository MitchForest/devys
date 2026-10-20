/// `GET /api/models`: the models employees can use and the deployment's defaults.
public struct ModelCatalog: Equatable, Sendable, Decodable {
    public let defaults: Defaults
    public let models: [Model]

    public init(defaults: Defaults, models: [Model]) {
        self.defaults = defaults
        self.models = models
    }

    public struct Defaults: Equatable, Sendable, Decodable {
        /// The model new employees start with.
        public let employee: String
        /// The model background work such as memory uses.
        public let background: String

        public init(employee: String, background: String) {
            self.employee = employee
            self.background = background
        }
    }

    public struct Model: Equatable, Sendable, Decodable, Identifiable {
        public let id: String
        public let label: String
        /// Who makes the model; the apps group by it.
        public let vendor: String
        /// Where the model runs, by name.
        public let provider: String
        public let summary: String
        public let effort: String
        public let price: Price
        /// Dollars for a typical employee turn, as the server estimates it.
        public let typicalTurnUsd: Double

        public init(
            id: String,
            label: String,
            vendor: String,
            provider: String,
            summary: String,
            effort: String,
            price: Price,
            typicalTurnUsd: Double
        ) {
            self.id = id
            self.label = label
            self.vendor = vendor
            self.provider = provider
            self.summary = summary
            self.effort = effort
            self.price = price
            self.typicalTurnUsd = typicalTurnUsd
        }
    }

    /// Dollars per million tokens.
    public struct Price: Equatable, Sendable, Decodable {
        public let input: Double
        public let output: Double
        public let cacheRead: Double

        public init(input: Double, output: Double, cacheRead: Double) {
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
        }
    }

    public func model(_ id: String) -> Model? {
        models.first { $0.id == id }
    }

    /// Models grouped by vendor, in the order the server lists them.
    public var vendors: [(vendor: String, models: [Model])] {
        var order: [String] = []
        var grouped: [String: [Model]] = [:]
        for model in models {
            if grouped[model.vendor] == nil { order.append(model.vendor) }
            grouped[model.vendor, default: []].append(model)
        }
        return order.map { (vendor: $0, models: grouped[$0] ?? []) }
    }
}

/// What an employee's runtime has spent, from `state.usage` in its status.
public struct RuntimeUsage: Equatable, Sendable, Decodable {
    /// Keyed by `provider/modelId`.
    public let models: [String: ModelUsage]

    public init(models: [String: ModelUsage]) {
        self.models = models
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = try container.decodeIfPresent([String: ModelUsage].self, forKey: .models) ?? [:]
    }

    /// Dollars across every model the employee has used.
    public var totalCost: Double { models.values.reduce(0) { $0 + $1.cost.total } }

    /// The share of prompt tokens read from cache, 0 to 1; nil before any prompt.
    public var cacheShare: Double? {
        let cached = models.values.reduce(0) { $0 + $1.cacheRead }
        let prompt = models.values.reduce(0) { $0 + $1.input + $1.cacheRead + $1.cacheWrite }
        return prompt > 0 ? Double(cached) / Double(prompt) : nil
    }

    enum CodingKeys: String, CodingKey { case models }

    public struct ModelUsage: Equatable, Sendable, Decodable {
        public let input: Int
        public let output: Int
        public let cacheRead: Int
        public let cacheWrite: Int
        public let cost: Cost

        public init(input: Int, output: Int, cacheRead: Int, cacheWrite: Int, cost: Cost) {
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
            self.cost = cost
        }
    }

    public struct Cost: Equatable, Sendable, Decodable {
        /// Dollars.
        public let total: Double

        public init(total: Double) {
            self.total = total
        }
    }
}

extension ModelCatalog {
    /// A small catalog for previews and tests.
    public static let fixture = ModelCatalog(
        defaults: Defaults(employee: "claude-opus-5-5", background: "gemini-3.8-flash"),
        models: [
            Model(
                id: "claude-opus-5-5",
                label: "Claude Opus 5.5",
                vendor: "Anthropic",
                provider: "Gateway",
                summary: "Best judgment and the most reliable long, tool-heavy work.",
                effort: "medium",
                price: Price(input: 5, output: 25, cacheRead: 0.5),
                typicalTurnUsd: 0.0625
            ),
            Model(
                id: "gpt-6.1-sol",
                label: "GPT-6.1 Sol",
                vendor: "OpenAI",
                provider: "Gateway",
                summary: "Strong all-round reasoning at half the price of Opus.",
                effort: "medium",
                price: Price(input: 2.5, output: 15, cacheRead: 0.25),
                typicalTurnUsd: 0.035
            ),
            Model(
                id: "gemini-3.8-flash",
                label: "Gemini 3.8 Flash",
                vendor: "Google",
                provider: "Gateway",
                summary: "Fast and inexpensive.",
                effort: "low",
                price: Price(input: 0.5, output: 3, cacheRead: 0.05),
                typicalTurnUsd: 0.007
            )
        ]
    )
}
