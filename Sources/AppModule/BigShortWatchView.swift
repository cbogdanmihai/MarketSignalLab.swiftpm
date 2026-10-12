import SwiftUI

struct BigShortWatchView: View {
    @EnvironmentObject
    private var store: AppStore

    var body: some View {
        ResearchCard(
            title:
                "Phase 2D.1 · Big Short Watch",
            subtitle:
                "Rare severe-downside detector · recall-first objective · development folds only · sealed holdout untouched"
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
                    "Event label: within the locked horizon, downside excursion reaches at least max(1.5%, 8×ATR14). This detector is separate from the ordinary SHORT model."
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
                    "Event recall",
                value:
                    percent(
                        result.meanRecall
                    ),
                subtitle:
                    "\(result.totalTestEvents) severe events"
            )

            MetricTile(
                title:
                    "Precision",
                value:
                    percent(
                        result.meanPrecision
                    ),
                subtitle:
                    "Recall-first detector"
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
                            "Recall",
                            percent(
                                fold.recall
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
                "Big Short Watch passed its development gate. It can be frozen together with the LONG architecture before the final holdout.",
                systemImage:
                    "checkmark.seal.fill"
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
            Label(
                "There are not enough independent severe-downside sessions to validate this detector. Add substantially more historical sessions before using the final holdout.",
                systemImage:
                    "clock.badge.exclamationmark"
            )
            .font(.caption)
            .foregroundStyle(
                .orange
            )
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
