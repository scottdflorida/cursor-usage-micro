import Foundation

func cursorUsageResponseParserTests() -> [TestCase] {
    let legacyDate = Date(timeIntervalSince1970: 1_701_000_000)
    let currentSampleDate = Date(timeIntervalSince1970: 1_785_000_000)

    func parse(_ data: Data, at date: Date? = nil) throws -> UsageReport {
        try CursorUsageResponseParser.parse(data, at: date ?? legacyDate)
    }

    return [
        TestCase(name: "current split-pool response maps Cursor Grok and API usage") {
            let report = try parse(
                Data(
                    """
                    {
                      "billingCycleStart": "1783729395000",
                      "billingCycleEnd": "1786407795000",
                      "planUsage": {
                        "includedSpend": 26,
                        "limit": 2000,
                        "autoPercentUsed": 0.08666666666666667,
                        "apiPercentUsed": 12.5,
                        "totalPercentUsed": 0.0753623188405797
                      },
                      "enabled": true,
                      "autoBucketModels": ["composer-2.5", "grok-4.5", "cursor-grok-4.5-high"]
                    }
                    """.utf8
                ),
                at: currentSampleDate
            )

            try expectEqual(report.cursorModels?.usedPercent, 0.08666666666666667)
            try expectEqual(report.api?.usedPercent, 12.5)
            try expectEqual(
                report.cursorModels?.resetsAt,
                Date(timeIntervalSince1970: 1_786_407_795)
            )
        },
        TestCase(name: "older total-only response remains readable") {
            let report = try parse(
                Data(
                    """
                    {
                      "billingCycleStart": 1700000000000,
                      "billingCycleEnd": 1702678400000,
                      "planUsage": {
                        "includedSpend": 500,
                        "limit": 2000,
                        "totalPercentUsed": 25
                      }
                    }
                    """.utf8
                )
            )

            try expectEqual(report.cursorModels?.usedPercent, 25)
            try expectEqual(report.api, nil)
        },
        TestCase(name: "spend and limit provide a final compatibility fallback") {
            let report = try parse(
                Data(
                    """
                    {
                      "billingCycleStart": "1700000000000",
                      "billingCycleEnd": "1702678400000",
                      "planUsage": {"includedSpend": 500, "limit": 2000}
                    }
                    """.utf8
                )
            )
            try expectEqual(report.cursorModels?.usedPercent, 25)
        },
        TestCase(name: "wrapped snake-case responses and numeric strings remain readable") {
            let report = try parse(
                Data(
                    """
                    {
                      "data": {
                        "billingCycleStart": "unknown",
                        "billing_cycle_start": "1700000000",
                        "billing_cycle_end": "1702678400",
                        "plan_usage": {
                          "auto_percent_used": "18.25",
                          "api_percent_used": "7.5"
                        },
                        "enabled": "true"
                      }
                    }
                    """.utf8
                )
            )

            try expectEqual(report.cursorModels?.usedPercent, 18.25)
            try expectEqual(report.api?.usedPercent, 7.5)
            try expectEqual(
                report.cursorModels?.startsAt,
                Date(timeIntervalSince1970: 1_700_000_000)
            )
        },
        TestCase(name: "ISO dates and over-limit usage remain readable") {
            let report = try parse(
                Data(
                    """
                    {
                      "billingCycleStart": "2026-07-01T00:00:00Z",
                      "billingCycleEnd": "2026-08-01T00:00:00.000Z",
                      "planUsage": {"autoPercentUsed": 125}
                    }
                    """.utf8
                ),
                at: currentSampleDate
            )

            try expectEqual(report.cursorModels?.usedPercent, 125)
            try expectEqual(report.cursorModels?.usageRemainingPercent, 0)
        },
        TestCase(name: "one malformed pool does not discard another valid pool") {
            let report = try parse(
                Data(
                    """
                    {
                      "billingCycleStart": 1700000000000,
                      "billingCycleEnd": 1702678400000,
                      "planUsage": {
                        "autoPercentUsed": -1,
                        "totalPercentUsed": "not a number",
                        "apiPercentUsed": 42
                      }
                    }
                    """.utf8
                )
            )

            try expectEqual(report.cursorModels, nil)
            try expectEqual(report.api?.usedPercent, 42)
        },
        TestCase(name: "aggregate totals do not replace a malformed split-pool field") {
            try expectThrows(CursorUsageResponseParsingError.invalidResponse) {
                _ = try parse(
                    Data(
                        """
                        {
                          "billingCycleStart": 1700000000000,
                          "billingCycleEnd": 1702678400000,
                          "planUsage": {
                            "autoPercentUsed": "unknown",
                            "totalPercentUsed": 31
                          }
                        }
                        """.utf8
                    )
                )
            }
        },
        TestCase(name: "aggregate spend does not synthesize Cursor usage in a split response") {
            let report = try parse(
                Data(
                    """
                    {
                      "billingCycleStart": 1700000000000,
                      "billingCycleEnd": 1702678400000,
                      "planUsage": {
                        "includedSpend": 500,
                        "limit": 2000,
                        "apiPercentUsed": 42
                      }
                    }
                    """.utf8
                )
            )

            try expectEqual(report.cursorModels, nil)
            try expectEqual(report.api?.usedPercent, 42)
        },
        TestCase(name: "provider wrapper traversal is explicitly bounded") {
            try expectThrows(CursorUsageResponseParsingError.invalidResponse) {
                _ = try parse(
                    Data(
                        """
                        {
                          "data": {"data": {"data": {"data": {
                            "billingCycleStart": 1700000000000,
                            "billingCycleEnd": 1702678400000,
                            "planUsage": {"autoPercentUsed": 1}
                          }}}}
                        }
                        """.utf8
                    )
                )
            }
        },
        TestCase(name: "current-period validation rejects stale, future, and implausible cycles") {
            try expectThrows(CursorUsageResponseParsingError.invalidResponse) {
                _ = try parse(
                    Data(
                        """
                        {
                          "billingCycleStart": 1700000000,
                          "billingCycleEnd": 1700999699,
                          "planUsage": {"autoPercentUsed": 1}
                        }
                        """.utf8
                    )
                )
            }
            try expectThrows(CursorUsageResponseParsingError.invalidResponse) {
                _ = try parse(
                    Data(
                        """
                        {
                          "billingCycleStart": 1701000301,
                          "billingCycleEnd": 1702000000,
                          "planUsage": {"autoPercentUsed": 1}
                        }
                        """.utf8
                    )
                )
            }
            try expectThrows(CursorUsageResponseParsingError.invalidResponse) {
                _ = try parse(
                    Data(
                        """
                        {
                          "billingCycleStart": 1700000000,
                          "billingCycleEnd": 1733000000,
                          "planUsage": {"autoPercentUsed": 1}
                        }
                        """.utf8
                    )
                )
            }
        },
        TestCase(name: "current-period validation tolerates modest provider clock skew") {
            let report = try parse(
                Data(
                    """
                    {
                      "billingCycleStart": 1699000000,
                      "billingCycleEnd": 1700999940,
                      "planUsage": {"autoPercentUsed": 1}
                    }
                    """.utf8
                )
            )
            try expectEqual(report.cursorModels?.usedPercent, 1)
        },
        TestCase(name: "disabled and malformed usage responses are rejected") {
            try expectThrows(CursorUsageResponseParsingError.usageUnavailable) {
                _ = try parse(
                    Data(
                        """
                        {
                          "billingCycleStart": "1700000000000",
                          "billingCycleEnd": "1702678400000",
                          "planUsage": {"autoPercentUsed": 1},
                          "enabled": false
                        }
                        """.utf8
                    )
                )
            }
            try expectThrows(CursorUsageResponseParsingError.invalidResponse) {
                _ = try parse(Data("{}".utf8))
            }
            try expectThrows(CursorUsageResponseParsingError.usageUnavailable) {
                _ = try parse(
                    Data(
                        """
                        {
                          "result": {
                            "billingCycleStart": 1700000000000,
                            "billingCycleEnd": 1702678400000,
                            "planUsage": {"autoPercentUsed": 1},
                            "enabled": 0
                          }
                        }
                        """.utf8
                    )
                )
            }
            try expectThrows(CursorUsageResponseParsingError.usageUnavailable) {
                _ = try parse(Data("{\"enabled\":false}".utf8))
            }
        },
    ]
}
