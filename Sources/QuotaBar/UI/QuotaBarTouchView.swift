import AppKit
import QuotaBarCore

final class QuotaBarTouchView: NSView {
    private let providerViews: [ProviderKind: ProviderPillView]

    override init(frame frameRect: NSRect) {
        providerViews = [
            .codex: ProviderPillView(provider: .codex),
            .claude: ProviderPillView(provider: .claude),
            .gemini: ProviderPillView(provider: .gemini)
        ]
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(_ snapshots: [ProviderKind: ProviderUsage]) {
        ProviderKind.allCases.forEach { provider in
            providerViews[provider]?.update(
                snapshots[provider] ?? .unavailable(provider, detail: "Waiting")
            )
        }
    }

    private func buildLayout() {
        let brandIcon = NSImageView()
        brandIcon.image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.50percent",
            accessibilityDescription: "QuotaBar"
        )
        brandIcon.contentTintColor = NSColor(calibratedRed: 0.52, green: 0.42, blue: 1, alpha: 1)
        brandIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            brandIcon.widthAnchor.constraint(equalToConstant: 24),
            brandIcon.heightAnchor.constraint(equalToConstant: 24)
        ])

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(brandIcon)
        ProviderKind.allCases.compactMap { providerViews[$0] }.forEach(stack.addArrangedSubview)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 740),
            heightAnchor.constraint(equalToConstant: 30)
        ])
    }
}

private final class ProviderPillView: NSView {
    private let provider: ProviderKind
    private let dotView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "—")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressView = UsageProgressView()

    init(provider: ProviderKind) {
        self.provider = provider
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(_ usage: ProviderUsage) {
        if provider == .claude {
            titleLabel.stringValue = "CLAUDE · 5H"
        } else if provider == .gemini,
                  let primary = usage.primary {
            titleLabel.stringValue = primary.windowMinutes == 300
                ? "GEMINI · 5H"
                : "GEMINI · 1W"
        } else {
            titleLabel.stringValue = provider.displayName.uppercased()
        }

        guard usage.state == .live, let primary = usage.primary else {
            percentLabel.stringValue = usage.state == .loading ? "…" : "—"

            switch usage.state {
            case .loading:
                detailLabel.stringValue = "LOADING"
                dotView.layer?.backgroundColor = NSColor.systemGray.cgColor
                progressView.update(usedPercent: 0, tint: .systemGray)
            case .actionRequired:
                detailLabel.stringValue = provider == .gemini
                    && usage.detail?.localizedCaseInsensitiveContains("set up") == true
                    ? "SET UP AGY"
                    : "OPEN MODELS"
                dotView.layer?.backgroundColor = NSColor.systemBlue.cgColor
                progressView.update(usedPercent: 0, tint: .systemBlue)
            case .unavailable:
                detailLabel.stringValue = provider == .gemini ? "NO AGY" : "OFFLINE"
                dotView.layer?.backgroundColor = NSColor.systemGray.cgColor
                progressView.update(usedPercent: 0, tint: .systemGray)
            case .error:
                detailLabel.stringValue = "ERROR"
                dotView.layer?.backgroundColor = NSColor.systemGray.cgColor
                progressView.update(usedPercent: 0, tint: .systemGray)
            case .live:
                detailLabel.stringValue = "LIVE"
                dotView.layer?.backgroundColor = NSColor.systemGray.cgColor
                progressView.update(usedPercent: 0, tint: .systemGray)
            }
            return
        }

        let used = Int(primary.usedPercent.rounded())
        let remaining = Int(primary.remainingPercent.rounded())
        percentLabel.stringValue = provider == .gemini
            ? "\(Self.formatPercent(primary.usedPercent))%"
            : "\(used)%"

        if provider == .claude {
            var details = ["\(remaining)% LEFT"]
            if let weekly = usage.secondary {
                details.append("WK \(Int(weekly.usedPercent.rounded()))%")
            }
            if let fable = usage.namedWeeklyLimits?.first(where: {
                $0.label.caseInsensitiveCompare("Fable") == .orderedSame
            }) {
                details.append("FABLE \(Int(fable.window.usedPercent.rounded()))%")
            }
            detailLabel.stringValue = details.joined(separator: " · ")
        } else if provider == .gemini {
            var details = ["\(Self.formatPercent(primary.remainingPercent))% LEFT"]
            if let weekly = usage.secondary {
                details.append("WK \(Self.formatPercent(weekly.usedPercent))%")
            }
            detailLabel.stringValue = details.joined(separator: " · ")
        } else if let secondary = usage.secondary {
            detailLabel.stringValue = "\(remaining)% LEFT · \(Int(secondary.usedPercent.rounded()))% \(secondary.compactWindowLabel)"
        } else {
            detailLabel.stringValue = "\(remaining)% LEFT · \(primary.compactWindowLabel)"
        }

        let tint = Self.tint(for: provider, usedPercent: primary.usedPercent)
        dotView.layer?.backgroundColor = tint.cgColor
        progressView.update(usedPercent: primary.usedPercent, tint: tint)
    }

    private func buildLayout() {
        wantsLayer = true

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3
        dotView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 8, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byClipping

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        percentLabel.textColor = .labelColor

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 7.5, weight: .medium)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byClipping

        let topRow = NSStackView(views: [dotView, titleLabel, percentLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 5

        let bottomRow = NSStackView(views: [progressView, detailLabel])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 5

        let content = NSStackView(views: [topRow, bottomRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 2
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 6),
            dotView.heightAnchor.constraint(equalToConstant: 6),
            progressView.widthAnchor.constraint(equalToConstant: 62),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 215)
        ])
    }

    private static func tint(for provider: ProviderKind, usedPercent: Double) -> NSColor {
        if usedPercent >= 85 { return .systemRed }
        if usedPercent >= 60 { return .systemYellow }

        switch provider {
        case .codex: return NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.60, alpha: 1)
        case .claude: return NSColor(calibratedRed: 0.91, green: 0.51, blue: 0.30, alpha: 1)
        case .gemini: return NSColor(calibratedRed: 0.36, green: 0.60, blue: 1.00, alpha: 1)
        }
    }

    private static func formatPercent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 100)
        if clamped > 0, clamped < 1 {
            return String(format: "%.2f", clamped)
        }
        if clamped != clamped.rounded() {
            return String(format: "%.1f", clamped)
        }
        return String(Int(clamped))
    }
}

private final class UsageProgressView: NSView {
    private let fillLayer = CALayer()
    private var usedPercent: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.cornerRadius = 2
        fillLayer.cornerRadius = 2
        layer?.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width * usedPercent / 100,
            height: bounds.height
        )
        CATransaction.commit()
    }

    func update(usedPercent: Double, tint: NSColor) {
        self.usedPercent = min(max(usedPercent, 0), 100)
        fillLayer.backgroundColor = tint.cgColor
        needsLayout = true
    }
}
