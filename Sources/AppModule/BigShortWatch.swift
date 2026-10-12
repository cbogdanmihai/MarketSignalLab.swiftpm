import Foundation

enum BigShortWatchStatus:
    String,
    Codable,
    Sendable {

    case ready = "WATCH_READY"
    case review = "REVIEW"
    case insufficientEvents =
        "INSUFFICIENT_EVENTS"
}

struct TailRiskDefinition:
    Identifiable,
    Codable,
    Sendable {

    let id: String
    let title: String
    let minimumDropPct: Double
    let atrMultiple: Double
    let severityRank: Int

    static let developmentCandidates:
        [TailRiskDefinition] = [
            TailRiskDefinition(
                id: "tail_watch_4",
                title: "Tail Watch",
                minimumDropPct: 0.0075,
                atrMultiple: 4.0,
                severityRank: 1
            ),
            TailRiskDefinition(
                id: "big_short_6",
                title: "Big Short",
                minimumDropPct: 0.0125,
                atrMultiple: 6.0,
                severityRank: 2
            ),
            TailRiskDefinition(
                id: "crash_watch_8",
                title: "Crash Watch",
                minimumDropPct: 0.015,
                atrMultiple: 8.0,
                severityRank: 3
            )
        ]
}

struct BigShortWatchExperiment:
    Codable,
    Sendable {

    let symbol: String
    let generatedAt: Date
    let candidates: [BigShortWatchResult]
    let recommended:
        BigShortWatchResult?

    var hasFrozenCandidate: Bool {
        recommended?
            .architectureFrozen
        == true
    }
}

struct BigShortFoldMetrics:
    Identifiable,
    Codable,
    Sendable {

    let fold: Int
    let trainSamples: Int
    let validationSamples: Int
    let testSamples: Int

    let trainEvents: Int
    let validationEvents: Int
    let testEvents: Int

    let trainEventRows: Int
    let validationEventRows: Int
    let testEventRows: Int

    let selectedThreshold: Double
    let selectedL2: Double

    let alertRate: Double
    let recall: Double
    let precision: Double
    let f2: Double
    let brierScore: Double
    let meanProbability: Double

    var id: Int {
        fold
    }
}

struct BigShortWatchResult:
    Codable,
    Sendable {

    let symbol: String
    let generatedAt: Date
    let tierID: String
    let tierTitle: String
    let severityRank: Int
    let horizonMinutes: Int
    let minimumDropPct: Double
    let atrMultiple: Double
    let featureCount: Int
    let contextCoverage: Double
    let folds: [BigShortFoldMetrics]

    var eventFoldCount: Int {
        folds.filter {
            $0.testEvents > 0
        }
        .count
    }

    var totalTestEvents: Int {
        folds.reduce(0) {
            $0 + $1.testEvents
        }
    }

    var meanRecall: Double {
        mean(
            folds
                .filter {
                    $0.testEvents > 0
                }
                .map {
                    $0.recall
                }
        )
    }

    var meanPrecision: Double {
        mean(
            folds
                .filter {
                    $0.testEvents > 0
                }
                .map {
                    $0.precision
                }
        )
    }

    var meanAlertRate: Double {
        mean(
            folds.map {
                $0.alertRate
            }
        )
    }

    var meanF2: Double {
        mean(
            folds
                .filter {
                    $0.testEvents > 0
                }
                .map {
                    $0.f2
                }
        )
    }

    var status: BigShortWatchStatus {
        if eventFoldCount < 2
            || totalTestEvents < 4 {

            return .insufficientEvents
        }

        if meanRecall >= 0.60
            && meanPrecision >= 0.10
            && meanAlertRate <= 0.20 {

            return .ready
        }

        return .review
    }

    var architectureFrozen: Bool {
        status == .ready
    }

    private func mean(
        _ values: [Double]
    ) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        return values.reduce(
            0,
            +
        )
        / Double(values.count)
    }
}

enum BigShortWatchEngine {
    private struct Example {
        let timestamp: Date
        let sessionKey: String
        let x: [Double]
        let y: Double
    }

    private struct Standardizer {
        let mean: [Double]
        let scale: [Double]

        func transform(
            _ values: [Double]
        ) -> [Double] {
            zip(
                zip(values, mean),
                scale
            )
            .map {
                pair,
                denominator in

                let (
                    value,
                    center
                ) = pair

                return (
                    value - center
                )
                / denominator
            }
        }
    }

    private struct LogisticModel {
        let weights: [Double]
        let bias: Double

        func probability(
            _ x: [Double]
        ) -> Double {
            var z = bias

            for index in x.indices {
                z +=
                    weights[index]
                    * x[index]
            }

            return sigmoid(z)
        }
    }

    private struct PlattScaler {
        let slope: Double
        let intercept: Double

        func probability(
            rawProbability: Double
        ) -> Double {
            let raw =
                min(
                    max(
                        rawProbability,
                        0.000_001
                    ),
                    0.999_999
                )

            let logit =
                log(
                    raw / (1 - raw)
                )

            return sigmoid(
                slope * logit
                + intercept
            )
        }
    }

    static func runExperiment(
        symbol: String,
        rows: [ResearchRow],
        folds: [WalkForwardFold],
        horizonMinutes: Int,
        contextBars:
            [String: [MarketBar]]
    ) -> BigShortWatchExperiment {
        let context =
            buildMarketContextFeatures(
                rows: rows,
                contextBars:
                    contextBars
            )

        let coverage =
            rows.isEmpty
            ? 0
            : Double(context.count)
                / Double(rows.count)

        var candidates:
            [BigShortWatchResult] = []

        for definition in
            TailRiskDefinition
                .developmentCandidates {

            if Task.isCancelled {
                break
            }

            candidates.append(
                runCandidate(
                    symbol: symbol,
                    definition:
                        definition,
                    rows: rows,
                    folds: folds,
                    horizonMinutes:
                        horizonMinutes,
                    context:
                        context,
                    contextCoverage:
                        coverage
                )
            )
        }

        let ready =
            candidates
                .filter {
                    $0.status == .ready
                }
                .max {
                    $0.severityRank
                        < $1.severityRank
                }

        let review =
            candidates
                .filter {
                    $0.status == .review
                }
                .max {
                    lhs,
                    rhs in

                    let lhsScore =
                        lhs.meanF2
                        - max(
                            0,
                            lhs.meanAlertRate
                                - 0.20
                        )

                    let rhsScore =
                        rhs.meanF2
                        - max(
                            0,
                            rhs.meanAlertRate
                                - 0.20
                        )

                    if abs(
                        lhsScore
                            - rhsScore
                    ) > 1e-12 {
                        return lhsScore
                            < rhsScore
                    }

                    return lhs.severityRank
                        < rhs.severityRank
                }

        let fallback =
            candidates.max {
                lhs,
                rhs in

                if lhs.totalTestEvents
                    != rhs.totalTestEvents {

                    return lhs.totalTestEvents
                        < rhs.totalTestEvents
                }

                return lhs.severityRank
                    < rhs.severityRank
            }

        return BigShortWatchExperiment(
            symbol: symbol,
            generatedAt: Date(),
            candidates:
                candidates,
            recommended:
                ready
                ?? review
                ?? fallback
        )
    }

    private static func runCandidate(
        symbol: String,
        definition:
            TailRiskDefinition,
        rows: [ResearchRow],
        folds: [WalkForwardFold],
        horizonMinutes: Int,
        context:
            [String: [Double]],
        contextCoverage: Double
    ) -> BigShortWatchResult {
        var results:
            [BigShortFoldMetrics] = []

        for fold in folds {
            if Task.isCancelled {
                break
            }

            if let result =
                runFold(
                    fold: fold,
                    rows: rows,
                    context:
                        context,
                    definition:
                        definition
                ) {

                results.append(
                    result
                )
            }
        }

        return BigShortWatchResult(
            symbol: symbol,
            generatedAt: Date(),
            tierID:
                definition.id,
            tierTitle:
                definition.title,
            severityRank:
                definition.severityRank,
            horizonMinutes:
                horizonMinutes,
            minimumDropPct:
                definition.minimumDropPct,
            atrMultiple:
                definition.atrMultiple,
            featureCount: 38,
            contextCoverage:
                contextCoverage,
            folds: results
        )
    }

    private static func runFold(
        fold: WalkForwardFold,
        rows: [ResearchRow],
        context:
            [String: [Double]],
        definition:
            TailRiskDefinition
    ) -> BigShortFoldMetrics? {
        let trainRows =
            rows.filter {
                $0.timestamp
                    >= fold.trainStart
                && $0.timestamp
                    <= fold.trainEnd
            }

        let validationRows =
            rows.filter {
                $0.timestamp
                    >= fold.validationStart
                && $0.timestamp
                    <= fold.validationEnd
            }

        let testRows =
            rows.filter {
                $0.timestamp
                    >= fold.testStart
                && $0.timestamp
                    <= fold.testEnd
            }

        let rawTrain =
            examples(
                rows: trainRows,
                context: context,
                definition:
                    definition
            )

        let rawValidation =
            examples(
                rows:
                    validationRows,
                context: context,
                definition:
                    definition
            )

        let rawTest =
            examples(
                rows: testRows,
                context: context,
                definition:
                    definition
            )

        guard
            rawTrain.count >= 200,
            rawValidation.count >= 50,
            rawTest.count >= 50
        else {
            return nil
        }

        let standardizer =
            fitStandardizer(
                rawTrain.map {
                    $0.x
                }
            )

        let train =
            rawTrain.map {
                Example(
                    timestamp:
                        $0.timestamp,
                    sessionKey:
                        $0.sessionKey,
                    x:
                        standardizer
                            .transform(
                                $0.x
                            ),
                    y: $0.y
                )
            }

        let validation =
            rawValidation.map {
                Example(
                    timestamp:
                        $0.timestamp,
                    sessionKey:
                        $0.sessionKey,
                    x:
                        standardizer
                            .transform(
                                $0.x
                            ),
                    y: $0.y
                )
            }

        let test =
            rawTest.map {
                Example(
                    timestamp:
                        $0.timestamp,
                    sessionKey:
                        $0.sessionKey,
                    x:
                        standardizer
                            .transform(
                                $0.x
                            ),
                    y: $0.y
                )
            }

        let selectedL2 =
            selectRegularization(
                examples: train
            )

        let model =
            trainLogistic(
                examples: train,
                l2: selectedL2,
                epochs: 50
            )

        let validationRaw =
            validation.map {
                model.probability(
                    $0.x
                )
            }

        let validationLabels =
            validation.map {
                $0.y
            }

        let scaler =
            fitPlattScaler(
                probabilities:
                    validationRaw,
                labels:
                    validationLabels
            )

        let validationProbabilities =
            validationRaw.map {
                scaler.probability(
                    rawProbability: $0
                )
            }

        let threshold =
            selectRecallThreshold(
                probabilities:
                    validationProbabilities,
                examples:
                    validation
            )

        let testProbabilities =
            test.map {
                scaler.probability(
                    rawProbability:
                        model.probability(
                            $0.x
                        )
                )
            }

        let metrics =
            metrics(
                probabilities:
                    testProbabilities,
                examples:
                    test,
                threshold:
                    threshold
            )

        return BigShortFoldMetrics(
            fold: fold.fold,
            trainSamples:
                train.count,
            validationSamples:
                validation.count,
            testSamples:
                test.count,
            trainEvents:
                positiveSessionCount(
                    train
                ),
            validationEvents:
                positiveSessionCount(
                    validation
                ),
            testEvents:
                positiveSessionCount(
                    test
                ),
            trainEventRows:
                positiveCount(train),
            validationEventRows:
                positiveCount(
                    validation
                ),
            testEventRows:
                positiveCount(test),
            selectedThreshold:
                threshold,
            selectedL2:
                selectedL2,
            alertRate:
                metrics.alertRate,
            recall:
                metrics.recall,
            precision:
                metrics.precision,
            f2:
                metrics.f2,
            brierScore:
                metrics.brier,
            meanProbability:
                metrics.meanProbability
        )
    }

    private struct Metrics {
        let alertRate: Double
        let recall: Double
        let precision: Double
        let f2: Double
        let brier: Double
        let meanProbability: Double
    }

    private static func metrics(
        probabilities: [Double],
        examples: [Example],
        threshold: Double
    ) -> Metrics {
        let count =
            min(
                probabilities.count,
                examples.count
            )

        guard count > 0 else {
            return Metrics(
                alertRate: 0,
                recall: 0,
                precision: 0,
                f2: 0,
                brier: 0,
                meanProbability: 0
            )
        }

        struct SessionState {
            var hasEvent = false
            var hasAlert = false
            var hasMatchedPreEventAlert = false
        }

        var sessions:
            [String: SessionState] = [:]

        var brierSum = 0.0
        var probabilitySum = 0.0

        for index in 0..<count {
            let probability =
                probabilities[index]

            let example =
                examples[index]

            var state =
                sessions[
                    example.sessionKey
                ]
                ?? SessionState()

            let isEventRow =
                example.y >= 0.5

            let isAlertRow =
                probability >= threshold

            if isEventRow {
                state.hasEvent = true
            }

            if isAlertRow {
                state.hasAlert = true
            }

            if isEventRow
                && isAlertRow {

                state.hasMatchedPreEventAlert =
                    true
            }

            sessions[
                example.sessionKey
            ] = state

            let delta =
                probability
                - example.y

            brierSum +=
                delta * delta

            probabilitySum +=
                probability
        }

        let states =
            Array(
                sessions.values
            )

        let eventSessions =
            states.filter {
                $0.hasEvent
            }
            .count

        let alertedSessions =
            states.filter {
                $0.hasAlert
            }
            .count

        let trueAlertSessions =
            states.filter {
                $0.hasMatchedPreEventAlert
            }
            .count

        let recall =
            Double(
                trueAlertSessions
            )
            / Double(
                max(
                    eventSessions,
                    1
                )
            )

        let precision =
            Double(
                trueAlertSessions
            )
            / Double(
                max(
                    alertedSessions,
                    1
                )
            )

        let betaSquared = 4.0

        let f2 =
            precision + recall > 0
            ? (
                (1 + betaSquared)
                * precision
                * recall
                / (
                    betaSquared
                    * precision
                    + recall
                )
            )
            : 0

        return Metrics(
            alertRate:
                Double(
                    alertedSessions
                )
                / Double(
                    max(
                        states.count,
                        1
                    )
                ),
            recall: recall,
            precision:
                precision,
            f2: f2,
            brier:
                brierSum
                / Double(count),
            meanProbability:
                probabilitySum
                / Double(count)
        )
    }

    private static func selectRecallThreshold(
        probabilities: [Double],
        examples: [Example]
    ) -> Double {
        let count =
            min(
                probabilities.count,
                examples.count
            )

        guard count > 0 else {
            return 0.25
        }

        let usedExamples =
            Array(
                examples.prefix(
                    count
                )
            )

        if positiveSessionCount(
            usedExamples
        ) == 0 {

            let sorted =
                Array(
                    probabilities
                        .prefix(count)
                )
                .sorted()

            let index =
                min(
                    sorted.count - 1,
                    Int(
                        floor(
                            Double(
                                sorted.count - 1
                            )
                            * 0.95
                        )
                    )
                )

            return max(
                0.10,
                sorted[index]
            )
        }

        var bestThreshold = 0.25
        var bestRecall = -1.0
        var bestPrecision = -1.0
        var bestF2 = -1.0

        var fallbackThreshold = 0.25
        var fallbackScore =
            -Double.greatestFiniteMagnitude

        var threshold = 0.05

        while threshold <= 0.60 {
            let result =
                metrics(
                    probabilities:
                        probabilities,
                    examples:
                        examples,
                    threshold:
                        threshold
                )

            let excessAlertRate =
                max(
                    0,
                    result.alertRate
                        - 0.20
                )

            let fallback =
                result.f2
                - 2.0
                * excessAlertRate

            if fallback
                > fallbackScore {

                fallbackScore =
                    fallback

                fallbackThreshold =
                    threshold
            }

            let acceptable =
                result.alertRate <= 0.20
                && result.precision
                    >= 0.10

            if acceptable,
               (
                    result.recall
                        > bestRecall
                    || (
                        abs(
                            result.recall
                            - bestRecall
                        ) < 1e-12
                        && result.precision
                            > bestPrecision
                    )
                    || (
                        abs(
                            result.recall
                            - bestRecall
                        ) < 1e-12
                        && abs(
                            result.precision
                            - bestPrecision
                        ) < 1e-12
                        && result.f2
                            > bestF2
                    )
               ) {

                bestRecall =
                    result.recall

                bestPrecision =
                    result.precision

                bestF2 =
                    result.f2

                bestThreshold =
                    threshold
            }

            threshold += 0.025
        }

        return bestRecall >= 0
        ? bestThreshold
        : fallbackThreshold
    }

    private static func selectRegularization(
        examples: [Example]
    ) -> Double {
        let candidates = [
            0.05,
            0.25,
            1.0
        ]

        let split =
            max(
                100,
                Int(
                    Double(
                        examples.count
                    )
                    * 0.75
                )
            )

        guard
            split < examples.count
                - 50
        else {
            return 0.25
        }

        let innerTrain =
            Array(
                examples[
                    0..<split
                ]
            )

        let innerValidation =
            Array(
                examples[
                    split
                        ..< examples.count
                ]
            )

        let tuningTrain =
            evenlySample(
                innerTrain,
                maximumCount:
                    1_500
            )

        let labels =
            innerValidation.map {
                $0.y
            }

        var bestL2 = 0.25
        var bestBrier =
            Double.greatestFiniteMagnitude

        for l2 in candidates {
            if Task.isCancelled {
                break
            }

            let model =
                trainLogistic(
                    examples:
                        tuningTrain,
                    l2: l2,
                    epochs: 20
                )

            let probabilities =
                innerValidation.map {
                    model.probability(
                        $0.x
                    )
                }

            let brier =
                meanSquaredError(
                    probabilities:
                        probabilities,
                    labels: labels
                )

            if brier < bestBrier {
                bestBrier = brier
                bestL2 = l2
            }
        }

        return bestL2
    }

    private static func trainLogistic(
        examples: [Example],
        l2: Double,
        epochs: Int
    ) -> LogisticModel {
        guard
            let first =
                examples.first
        else {
            return LogisticModel(
                weights: [],
                bias: 0
            )
        }

        let featureCount =
            first.x.count

        var weights =
            Array(
                repeating: 0.0,
                count: featureCount
            )

        let positives =
            Double(
                positiveCount(
                    examples
                )
            )

        let negatives =
            Double(examples.count)
            - positives

        let positiveWeight =
            positives > 0
            ? min(
                max(
                    negatives
                    / positives,
                    1
                ),
                12
            )
            : 1

        let prior =
            min(
                max(
                    positives
                    / Double(
                        max(
                            examples.count,
                            1
                        )
                    ),
                    0.001
                ),
                0.999
            )

        var bias =
            log(
                prior
                / (1 - prior)
            )

        let learningRate = 0.05
        let n =
            Double(
                max(
                    examples.count,
                    1
                )
            )

        for _ in 0..<epochs {
            if Task.isCancelled {
                break
            }

            var gradient =
                Array(
                    repeating: 0.0,
                    count: featureCount
                )

            var biasGradient = 0.0

            for example in examples {
                var z = bias

                for index in
                    0..<featureCount {

                    z +=
                        weights[index]
                        * example.x[index]
                }

                let probability =
                    sigmoid(z)

                let sampleWeight =
                    example.y >= 0.5
                    ? positiveWeight
                    : 1

                let error =
                    (
                        probability
                        - example.y
                    )
                    * sampleWeight

                biasGradient +=
                    error

                for index in
                    0..<featureCount {

                    gradient[index] +=
                        error
                        * example.x[index]
                }
            }

            bias -=
                learningRate
                * (
                    biasGradient / n
                )

            for index in
                0..<featureCount {

                weights[index] -=
                    learningRate
                    * (
                        gradient[index]
                        / n
                        + l2
                        * weights[index]
                    )
            }
        }

        return LogisticModel(
            weights: weights,
            bias: bias
        )
    }

    private static func fitPlattScaler(
        probabilities: [Double],
        labels: [Double]
    ) -> PlattScaler {
        let count =
            min(
                probabilities.count,
                labels.count
            )

        guard count > 0 else {
            return PlattScaler(
                slope: 1,
                intercept: 0
            )
        }

        var slope = 1.0
        var intercept = 0.0

        let positives =
            labels.reduce(0) {
                $0 + $1
            }

        let negatives =
            Double(count)
            - positives

        let positiveWeight =
            positives > 0
            ? min(
                max(
                    negatives
                    / positives,
                    1
                ),
                12
            )
            : 1

        for _ in 0..<80 {
            if Task.isCancelled {
                break
            }

            var slopeGradient = 0.0
            var interceptGradient = 0.0

            for index in 0..<count {
                let raw =
                    min(
                        max(
                            probabilities[index],
                            0.000_001
                        ),
                        0.999_999
                    )

                let logit =
                    log(
                        raw / (1 - raw)
                    )

                let predicted =
                    sigmoid(
                        slope * logit
                        + intercept
                    )

                let sampleWeight =
                    labels[index] >= 0.5
                    ? positiveWeight
                    : 1

                let error =
                    (
                        predicted
                        - labels[index]
                    )
                    * sampleWeight

                slopeGradient +=
                    error * logit

                interceptGradient +=
                    error
            }

            let n =
                Double(count)

            slope -=
                0.02
                * (
                    slopeGradient / n
                    + 0.001 * slope
                )

            intercept -=
                0.02
                * (
                    interceptGradient / n
                )
        }

        return PlattScaler(
            slope: slope,
            intercept: intercept
        )
    }

    private static func examples(
        rows: [ResearchRow],
        context:
            [String: [Double]],
        definition:
            TailRiskDefinition
    ) -> [Example] {
        rows.compactMap { row in
            guard
                let contextFeatures =
                    context[row.id]
            else {
                return nil
            }

            let severeDrop =
                max(
                    definition
                        .minimumDropPct,
                    definition
                        .atrMultiple
                    * row.atr14Pct
                )

            let event =
                row.maePct
                    <= -severeDrop

            return Example(
                timestamp:
                    row.timestamp,
                sessionKey:
                    row.sessionKey,
                x:
                    coreFeatures(row)
                    + contextFeatures
                    + stressFeatures(
                        row,
                        contextFeatures:
                            contextFeatures
                    ),
                y:
                    event
                    ? 1
                    : 0
            )
        }
    }

    private static func coreFeatures(
        _ row: ResearchRow
    ) -> [Double] {
        [
            Double(
                row.minuteOfSession
            ),
            row.sessionProgress,
            row.return1,
            row.return5,
            row.return15,
            row.return30,
            row.return60,
            row.rangePct,
            row.atr14Pct,
            row.realizedVol20,
            row.volumeZ20 ?? 0,
            row.distanceToSMA20,
            row.distanceToSMA50,
            row.distanceToSessionHigh,
            row.distanceToSessionLow,
            row.distanceToSessionVWAP
                ?? 0
        ]
    }

    private static func stressFeatures(
        _ row: ResearchRow,
        contextFeatures:
            [Double]
    ) -> [Double] {
        guard
            contextFeatures.count >= 12
        else {
            return Array(
                repeating: 0,
                count: 10
            )
        }

        let atr =
            max(
                row.atr14Pct,
                0.000_001
            )

        let return5Acceleration =
            row.return5
            - row.return15 / 3.0

        let return15Acceleration =
            row.return15
            - row.return60 / 4.0

        let rangeExpansion =
            row.rangePct / atr

        let volumeShock =
            max(
                row.volumeZ20 ?? 0,
                0
            )

        let belowVWAPNormalized =
            min(
                row.distanceToSessionVWAP
                    ?? 0,
                0
            )
            / atr

        let distanceToLowATR =
            max(
                row.distanceToSessionLow,
                0
            )
            / atr

        let sessionLowPressure =
            1.0
            / (
                1.0
                + distanceToLowATR
            )

        let spyReturn15 =
            contextFeatures[1]

        let iwmReturn15 =
            contextFeatures[5]

        let vixReturn5 =
            contextFeatures[8]

        let vixReturn15 =
            contextFeatures[9]

        let relativeWeaknessSPY =
            row.return15
            - spyReturn15

        let relativeWeaknessIWM =
            row.return15
            - iwmReturn15

        let vixAcceleration =
            vixReturn5
            - vixReturn15 / 3.0

        return [
            return5Acceleration,
            return15Acceleration,
            rangeExpansion,
            volumeShock,
            belowVWAPNormalized,
            sessionLowPressure,
            relativeWeaknessSPY,
            relativeWeaknessIWM,
            vixReturn5,
            vixAcceleration
        ]
    }

    private static func buildMarketContextFeatures(
        rows: [ResearchRow],
        contextBars:
            [String: [MarketBar]]
    ) -> [String: [Double]] {
        let requiredSymbols = [
            "SPY",
            "IWM",
            "VIXY"
        ]

        var featureBySymbol:
            [String: [Date: [Double]]] = [:]

        for symbol in requiredSymbols {
            guard
                let bars =
                    contextBars[symbol],
                !bars.isEmpty
            else {
                return [:]
            }

            featureBySymbol[symbol] =
                marketFeaturesByTimestamp(
                    bars: bars
                )
        }

        var result:
            [String: [Double]] = [:]

        for row in rows {
            guard
                let spy =
                    featureBySymbol["SPY"]?[
                        row.timestamp
                    ],
                let iwm =
                    featureBySymbol["IWM"]?[
                        row.timestamp
                    ],
                let vixy =
                    featureBySymbol["VIXY"]?[
                        row.timestamp
                    ]
            else {
                continue
            }

            result[row.id] =
                spy + iwm + vixy
        }

        return result
    }

    private static func marketFeaturesByTimestamp(
        bars: [MarketBar]
    ) -> [Date: [Double]] {
        let timezone =
            TimeZone(
                identifier:
                    "America/New_York"
            )
            ?? .current

        var calendar =
            Calendar(
                identifier:
                    .gregorian
            )

        calendar.timeZone =
            timezone

        let regularBars =
            bars.filter { bar in
                let components =
                    calendar.dateComponents(
                        [.hour, .minute],
                        from:
                            bar.timestamp
                    )

                guard
                    let hour =
                        components.hour,
                    let minute =
                        components.minute
                else {
                    return false
                }

                let minuteOfDay =
                    hour * 60 + minute

                return minuteOfDay >= 570
                    && minuteOfDay < 960
            }
            .sorted {
                $0.timestamp
                    < $1.timestamp
            }

        let grouped =
            Dictionary(
                grouping:
                    regularBars
            ) { bar in
                let components =
                    calendar.dateComponents(
                        [.year, .month, .day],
                        from:
                            bar.timestamp
                    )

                return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
            }

        var result:
            [Date: [Double]] = [:]

        for session in grouped.values {
            let ordered =
                session.sorted {
                    $0.timestamp
                        < $1.timestamp
                }

            guard
                let first =
                    ordered.first
            else {
                continue
            }

            for index in ordered.indices {
                guard index >= 60 else {
                    continue
                }

                let current =
                    ordered[index]

                result[
                    current.timestamp
                ] = [
                    safeReturn(
                        current.close,
                        ordered[
                            index - 5
                        ].close
                    ),
                    safeReturn(
                        current.close,
                        ordered[
                            index - 15
                        ].close
                    ),
                    safeReturn(
                        current.close,
                        ordered[
                            index - 60
                        ].close
                    ),
                    safeReturn(
                        current.close,
                        first.close
                    )
                ]
            }
        }

        return result
    }

    private static func fitStandardizer(
        _ matrix: [[Double]]
    ) -> Standardizer {
        guard
            let first =
                matrix.first
        else {
            return Standardizer(
                mean: [],
                scale: []
            )
        }

        let featureCount =
            first.count

        var mean =
            Array(
                repeating: 0.0,
                count: featureCount
            )

        for row in matrix {
            for index in
                0..<featureCount {

                mean[index] +=
                    row[index]
            }
        }

        let n =
            Double(
                max(
                    matrix.count,
                    1
                )
            )

        for index in mean.indices {
            mean[index] /= n
        }

        var variance =
            Array(
                repeating: 0.0,
                count: featureCount
            )

        for row in matrix {
            for index in
                0..<featureCount {

                let delta =
                    row[index]
                    - mean[index]

                variance[index] +=
                    delta * delta
            }
        }

        var scale =
            variance.map {
                sqrt(
                    $0 / n
                )
            }

        for index in scale.indices {
            if !scale[index].isFinite
                || scale[index] < 1e-9 {

                scale[index] = 1
            }
        }

        return Standardizer(
            mean: mean,
            scale: scale
        )
    }

    private static func positiveSessionCount(
        _ examples: [Example]
    ) -> Int {
        Set(
            examples
                .filter {
                    $0.y >= 0.5
                }
                .map {
                    $0.sessionKey
                }
        )
        .count
    }

    private static func positiveCount(
        _ examples: [Example]
    ) -> Int {
        examples.filter {
            $0.y >= 0.5
        }
        .count
    }

    private static func meanSquaredError(
        probabilities: [Double],
        labels: [Double]
    ) -> Double {
        let count =
            min(
                probabilities.count,
                labels.count
            )

        guard count > 0 else {
            return 0
        }

        var sum = 0.0

        for index in 0..<count {
            let delta =
                probabilities[index]
                - labels[index]

            sum +=
                delta * delta
        }

        return sum
            / Double(count)
    }

    private static func evenlySample(
        _ examples: [Example],
        maximumCount: Int
    ) -> [Example] {
        guard
            maximumCount > 1,
            examples.count
                > maximumCount
        else {
            return examples
        }

        let step =
            Double(
                examples.count - 1
            )
            / Double(
                maximumCount - 1
            )

        return (
            0..<maximumCount
        )
        .map {
            index in

            examples[
                min(
                    examples.count - 1,
                    Int(
                        round(
                            Double(index)
                            * step
                        )
                    )
                )
            ]
        }
    }

    private static func safeReturn(
        _ end: Double,
        _ start: Double
    ) -> Double {
        guard start != 0 else {
            return 0
        }

        return end / start - 1
    }

    private static func sigmoid(
        _ value: Double
    ) -> Double {
        let clamped =
            min(
                max(
                    value,
                    -35
                ),
                35
            )

        return 1
            / (
                1
                + exp(-clamped)
            )
    }
}
