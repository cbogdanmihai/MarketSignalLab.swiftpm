import SwiftUI

struct BigShortWatchView: View {
    @EnvironmentObject
    private var store: AppStore

    var body: some View {
        ResearchCard(
            title:
                "Phase 2D.4 · Robust Tail-Risk Validation",
            subtitle:
                "Five-fold chronological validation · pre-event matching · Stress38 features · deterministic Market Stress Monitor · prospective holdout untouched"
        ) {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                header

                if store.isTrainingBigShortWatch
                    || store.bigShortLastRunDuration
                        != nil {

                    BigShortRunMonitorView()
                        .environmentObject(
                            store
                        )
                }

                if let result =
                    store.bigShortResult {

                    summary(
                        result
                    )

                    folds(
                        result
                    )

                    readiness(
                        result
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(
                    store.bigShortMessage
                )
                .font(.callout)
                .textSelection(
                    .enabled
                )

                Text(
                    "Each alert only counts as a hit if it occurs on a causal row whose forward window actually contains the later downside event. The experiment compares Tail Watch, Big Short and Crash Watch with Stress38 features, plus a separate deterministic Market Stress Monitor benchmark."
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }

            Spacer()

            Button {
                Task {
                    await store
                        .trainBigShortWatch()
                }
            } label: {
                Label(
                    store
                        .isTrainingBigShortWatch
                    ? "Training…"
                    : "Train Big Short Watch",
                    systemImage:
                        "exclamationmark.triangle.fill"
                )
            }
            .buttonStyle(
                .borderedProminent
            )
            .disabled(
                store
                    .isTrainingBigShortWatch
                || store
                    .isTrainingBaseline
                || store
                    .isPreparingBigShortHistory
                || store
                    .selectedLockedLabelPolicy
                    == nil
            )
        }
    }

    @ViewBuilder
    private func summary(
        _ result:
            BigShortWatchResult
    ) -> some View {
        HStack(spacing: 12) {
            MetricTile(
                title:
                    "Selected tier",
                value:
                    result.tierTitle,
                subtitle:
                    "max(\(String(format: "%.2f", result.minimumDropPct * 100))%, \(String(format: "%.0f", result.atrMultiple))×ATR14)"
            )

            MetricTile(
                title:
                    "Watch status",
                value:
                    result.status.rawValue,
                subtitle:
                    result.architectureFrozen
                    ? "Eligible for frozen architecture"
                    : "Keep holdout closed"
            )

            MetricTile(
                title:
                    "Pre-event recall",
                value:
                    percent(
                        result.meanRecall
                    ),
                subtitle:
                    "\(result.totalTestEvents) event sessions"
            )

            MetricTile(
                title:
                    "Precision",
                value:
                    percent(
                        result.meanPrecision
                    ),
                subtitle:
                    "Matched before event"
            )

            MetricTile(
                title:
                    "Alert rate",
                value:
                    percent(
                        result.meanAlertRate
                    ),
                subtitle:
                    "Target ≤ 20%"
            )

            MetricTile(
                title:
                    "Stress recall",
                value:
                    percent(
                        result.stressMeanRecall
                    ),
                subtitle:
                    "Deterministic monitor"
            )

            MetricTile(
                title:
                    "Stress alerts",
                value:
                    percent(
                        result.stressMeanAlertRate
                    ),
                subtitle:
                    "Fixed rule benchmark"
            )

            MetricTile(
                title:
                    "Context coverage",
                value:
                    percent(
                        result.contextCoverage
                    ),
                subtitle:
                    "SPY · IWM · VIXY"
            )
        }
    }

    @ViewBuilder
    private func folds(
        _ result:
            BigShortWatchResult
    ) -> some View {
        if store.bigShortCandidates.count > 1 {
            DisclosureGroup(
                "Tail-risk tier candidates"
            ) {
                VStack(spacing: 8) {
                    ForEach(
                        store.bigShortCandidates,
                        id: \.tierID
                    ) { candidate in
                        HStack(
                            spacing: 14
                        ) {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    candidate.tierTitle
                                )
                                .font(
                                    .caption.bold()
                                )

                                Text(
                                    "max(\(String(format: "%.2f", candidate.minimumDropPct * 100))%, \(String(format: "%.0f", candidate.atrMultiple))×ATR14)"
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                            .frame(
                                width: 150,
                                alignment:
                                    .leading
                            )

                            compactMetric(
                                "Events",
                                String(
                                    candidate.totalTestEvents
                                )
                            )

                            compactMetric(
                                "Pre-event",
                                percent(
                                    candidate.meanRecall
                                )
                            )

                            compactMetric(
                                "Stress",
                                percent(
                                    candidate.stressMeanRecall
                                )
                            )

                            compactMetric(
                                "Precision",
                                percent(
                                    candidate.meanPrecision
                                )
                            )

                            compactMetric(
                                "F2",
                                percent(
                                    candidate.meanF2
                                )
                            )

                            compactMetric(
                                "Alert",
                                percent(
                                    candidate.meanAlertRate
                                )
                            )

                            Spacer()

                            Text(
                                candidate.status
                                    .rawValue
                            )
                            .font(
                                .caption.bold()
                            )
                            .foregroundStyle(
                                candidate.architectureFrozen
                                ? Color.green
                                : Color.orange
                            )
                        }

                        Divider()
                    }
                }
                .padding(
                    .top,
                    8
                )
            }
        }

        DisclosureGroup(
            "Big Short development folds"
        ) {
            VStack(spacing: 8) {
                ForEach(
                    result.folds
                ) { fold in
                    HStack(
                        spacing: 14
                    ) {
                        Text(
                            "Fold \(fold.fold)"
                        )
                        .font(
                            .caption.bold()
                        )
                        .frame(
                            width: 55,
                            alignment:
                                .leading
                        )

                        compactMetric(
                            "Events",
                            String(
                                fold.testEvents
                            )
                        )

                        compactMetric(
                            "Pre-event",
                            percent(
                                fold.recall
                            )
                        )

                        compactMetric(
                            "Stress",
                            percent(
                                fold.stressRecall
                            )
                        )

                        compactMetric(
                            "Precision",
                            percent(
                                fold.precision
                            )
                        )

                        compactMetric(
                            "F2",
                            percent(
                                fold.f2
                            )
                        )

                        compactMetric(
                            "Alert",
                            percent(
                                fold.alertRate
                            )
                        )

                        compactMetric(
                            "Stress alert",
                            percent(
                                fold.stressAlertRate
                            )
                        )

                        compactMetric(
                            "Threshold",
                            percent(
                                fold.selectedThreshold
                            )
                        )

                        compactMetric(
                            "L2",
                            fold.selectedL2
                                .formatted(
                                    .number.precision(
                                        .fractionLength(
                                            3
                                        )
                                    )
                                )
                        )

                        Spacer()
                    }
                    .padding(
                        .vertical,
                        4
                    )

                    Divider()
                }
            }
            .padding(
                .top,
                8
            )
        }
    }

    @ViewBuilder
    private func readiness(
        _ result:
            BigShortWatchResult
    ) -> some View {
        switch result.status {
        case .ready:
            Label(
                "The probabilistic Tail-Risk Watch passed the development gate using pre-event matching. It can be frozen with the directional architecture.",
                systemImage:
                    "checkmark.seal.fill"
            )
            .font(.caption)
            .foregroundStyle(
                .green
            )

        case .stressReady:
            Label(
                "The learned detector did not pass, but the deterministic Market Stress Monitor did. Freeze it only as a WATCH layer, not as an automatic SHORT entry.",
                systemImage:
                    "checkmark.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(
                .green
            )

        case .review:
            Label(
                "Rare-event coverage exists, but recall/precision/alert-rate gates are not good enough yet. Keep the sealed holdout closed.",
                systemImage:
                    "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(
                .orange
            )

        case .insufficientEvents:
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                Label(
                    "There are not enough independent severe-downside sessions to validate this detector. Add substantially more historical sessions before using the final holdout.",
                    systemImage:
                        "clock.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(
                    .orange
                )

                Text(
                    store.bigShortHistoryMessage
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )

                HStack {
                    Button {
                        Task {
                            await store
                                .prepareBigShortHistory(
                                    days: 365
                                )
                        }
                    } label: {
                        Label(
                            store
                                .isPreparingBigShortHistory
                            ? "Extending History…"
                            : "Extend Tail History · 1Y",
                            systemImage:
                                "calendar.badge.plus"
                        )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .disabled(
                        store
                            .isPreparingBigShortHistory
                        || store
                            .isDownloadingHistory
                        || store
                            .isTrainingBigShortWatch
                    )

                    Spacer()
                }

                if store.isPreparingBigShortHistory
                    || store.isDownloadingHistory {

                    HistoryRunMonitorView()
                        .environmentObject(
                            store
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func compactMetric(
        _ title: String,
        _ value: String
    ) -> some View {
        VStack(
            alignment: .trailing,
            spacing: 2
        ) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )

            Text(value)
                .font(
                    .caption.bold()
                )
                .monospacedDigit()
        }
    }

    private func percent(
        _ value: Double
    ) -> String {
        value.formatted(
            .percent.precision(
                .fractionLength(
                    1
                )
            )
        )
    }
}
