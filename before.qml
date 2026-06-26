                                        : 0
                                    height: parent.height
                                    radius: parent.radius
                                    color: providerCostSection.accent
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    text: providerCostSection.providerCost ? providerCostSection.providerCost.spendLine : ""
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents.Label {
                                    visible: providerCostSection.providerCost && providerCostSection.providerCost.percentLine.length > 0 ? true : false
                                    text: providerCostSection.providerCost ? providerCostSection.providerCost.percentLine : ""
                                    opacity: 0.66
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }

                            PlasmaComponents.Label {
                                visible: providerCostSection.providerCost && providerCostSection.providerCost.personalSpendLine.length > 0 ? true : false
                                text: providerCostSection.providerCost ? providerCostSection.providerCost.personalSpendLine : ""
                                opacity: 0.66
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        ColumnLayout {
                            id: tokenCostSection

                            readonly property var tokenCost: root.selectedProviderData ? root.selectedProviderData.tokenCost : null

                            visible: tokenCostSection.tokenCost ? true : false
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 1.5

                            Kirigami.Separator {
                                Layout.fillWidth: true
                            }

                            Kirigami.Heading {
                                text: i18n("Cost")
                                level: 4
                                Layout.fillWidth: true
                            }

                            PlasmaComponents.Label {
                                text: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.sessionLine : ""
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            PlasmaComponents.Label {
                                text: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.monthLine : ""
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Canvas {
                                id: costSparkline

                                property var points: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.daily : []
                                readonly property real maxValue: root.costSparklineMax(points)
                                readonly property color accent: root.providerColor(root.selectedProviderData ? root.selectedProviderData.provider : "")

                                visible: points.length > 1 && maxValue > 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 4

                                onPointsChanged: requestPaint()
                                onMaxValueChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    if (!points || points.length < 2 || maxValue <= 0 || width <= 0 || height <= 0) {
                                        return
                                    }

                                    var gap = Math.max(1, Math.floor(width / 180))
                                    var barWidth = Math.max(2, (width - gap * (points.length - 1)) / points.length)
                                    var baseline = height - 1

                                    ctx.fillStyle = root.canvasColor(Kirigami.Theme.textColor, 0.22)
                                    ctx.fillRect(0, baseline, width, 1)

                                    ctx.fillStyle = root.canvasColor(costSparkline.accent, 0.9)
                                    for (var i = 0; i < points.length; i++) {
                                        var value = Math.max(0, Number(points[i].cost) || 0)
                                        var barHeight = Math.max(1, (height - 3) * value / maxValue)
                                        var x = i * (barWidth + gap)
                                        ctx.fillRect(x, baseline - barHeight, barWidth, barHeight)
                                    }
                                }
                            }

                            RowLayout {
                                visible: tokenCostSection.tokenCost
                                    && tokenCostSection.tokenCost.daily
                                    && tokenCostSection.tokenCost.daily.length > 1
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    text: tokenCostSection.tokenCost ? root.costSparklineSummary(tokenCostSection.tokenCost.daily) : ""
                                    opacity: 0.62
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents.Label {
                                    text: tokenCostSection.tokenCost
                                        ? i18np("%1 day", "%1 days", tokenCostSection.tokenCost.daily.length)
                                        : ""
                                    opacity: 0.62
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }

                            ColumnLayout {
                                id: costHistoryChartSection

                                readonly property var rows: root.costHistoryRows(tokenCostSection.tokenCost)
                                readonly property string peakLine: tokenCostSection.tokenCost ? root.costPeakLine(tokenCostSection.tokenCost.daily) : ""
                                readonly property string averageLine: tokenCostSection.tokenCost ? root.costAverageDailyLine(tokenCostSection.tokenCost.daily) : ""
                                readonly property color accent: root.providerColor(root.selectedProviderData ? root.selectedProviderData.provider : "")

                                visible: rows.length > 1
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing / 2

                                PlasmaComponents.Label {
                                    text: i18n("Cost history")
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    visible: costHistoryChartSection.peakLine.length > 0
                                        || costHistoryChartSection.averageLine.length > 0
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents.Label {
                                        text: costHistoryChartSection.peakLine
                                        opacity: 0.66
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    PlasmaComponents.Label {
                                        text: costHistoryChartSection.averageLine
                                        opacity: 0.66
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }
                                }

                                Repeater {
                                    model: root.costHistoryRows(tokenCostSection.tokenCost)

                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing

                                        PlasmaComponents.Label {
                                            text: modelData.label
                                            opacity: 0.66
                                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            id: costHistoryBarTrack

                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 6
                                            radius: height / 2
                                            color: root.withAlpha(Kirigami.Theme.textColor, 0.12)
                                            clip: true

                                            Rectangle {
                                                width: parent.width * Math.max(0, Math.min(100, modelData.percent)) / 100
                                                height: parent.height
                                                radius: parent.radius
                                                color: modelData.isPeak
                                                    ? root.withAlpha(costHistoryChartSection.accent, 1)
                                                    : root.withAlpha(costHistoryChartSection.accent, 0.72)
                                            }
                                        }

                                        PlasmaComponents.Label {
                                            text: modelData.value
                                            opacity: modelData.isPeak ? 0.9 : 0.7
                                            font.weight: modelData.isPeak ? Font.DemiBold : Font.Normal
                                            horizontalAlignment: Text.AlignRight
                                            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                id: costDrillDownSection

                                visible: tokenCostSection.tokenCost
                                    && (root.costBreakdownRows(tokenCostSection.tokenCost).length > 0
                                        || root.costModelRows(tokenCostSection.tokenCost).length > 0
                                        || root.costDailyRows(tokenCostSection.tokenCost).length > 0)
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    text: i18n("Cost drill-down")
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents.Label {
                                    visible: tokenCostSection.tokenCost && root.costPerMillionLine(tokenCostSection.tokenCost).length > 0
                                    text: tokenCostSection.tokenCost ? root.costPerMillionLine(tokenCostSection.tokenCost) : ""
                                    opacity: 0.7
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                ColumnLayout {
                                    visible: root.costBreakdownRows(tokenCostSection.tokenCost).length > 0
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    Repeater {
                                        model: root.costBreakdownRows(tokenCostSection.tokenCost)

                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing

                                            PlasmaComponents.Label {
                                                text: modelData.label
                                                opacity: 0.66
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            PlasmaComponents.Label {
                                                text: modelData.value
                                                opacity: 0.78
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }

                                Kirigami.Separator {
                                    visible: root.costModelRows(tokenCostSection.tokenCost).length > 0
                                    Layout.fillWidth: true
                                }

                                ColumnLayout {
                                    visible: root.costModelRows(tokenCostSection.tokenCost).length > 0
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    PlasmaComponents.Label {
                                        text: i18n("Models")
                                        opacity: 0.66
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Repeater {
                                        model: root.costModelRows(tokenCostSection.tokenCost)

                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing

                                            PlasmaComponents.Label {
                                                text: modelData.label
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            PlasmaComponents.Label {
                                                text: modelData.value
                                                opacity: 0.7
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }

                                Kirigami.Separator {
                                    visible: root.costDailyRows(tokenCostSection.tokenCost).length > 0
                                    Layout.fillWidth: true
                                }

                                ColumnLayout {
                                    visible: root.costDailyRows(tokenCostSection.tokenCost).length > 0
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    PlasmaComponents.Label {
                                        text: i18n("Recent days")
                                        opacity: 0.66
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Repeater {
                                        model: root.costDailyRows(tokenCostSection.tokenCost)

                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing

                                            PlasmaComponents.Label {
                                                text: modelData.label
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            PlasmaComponents.Label {
                                                text: modelData.value
                                                opacity: 0.7
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }

                            PlasmaComponents.Label {
