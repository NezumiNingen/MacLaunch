import AppKit
import QuartzCore

extension CAGridView {
    /// Give changed tiles a short, staggered settling motion after auto-organizing.
    /// This stays in an additive extension so the upstream grid's layout logic
    /// remains untouched.
    func playOrganizationSuccessAnimation(for itemIDs: Set<String>) {
        guard animationsEnabled,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !itemIDs.isEmpty else { return }

        let affectedLayers = zip(items, iconLayers.flatMap { $0 })
            .enumerated()
            .compactMap { index, pair -> (Int, CALayer)? in
                itemIDs.contains(pair.0.id) ? (index, pair.1) : nil
            }
            .sorted { $0.0 < $1.0 }

        guard !affectedLayers.isEmpty else { return }
        let stagger = min(0.022, 0.32 / Double(affectedLayers.count))

        for (sequence, entry) in affectedLayers.enumerated() {
            let layer = entry.1
            let animation = CAKeyframeAnimation(keyPath: "transform.scale")
            animation.values = [0.88, 1.055, 0.985, 1.0]
            animation.keyTimes = [0, 0.4, 0.74, 1]
            animation.duration = 0.42
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + Double(sequence) * stagger
            animation.fillMode = .backwards
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeOut)
            ]
            layer.add(animation, forKey: "automaticOrganizationSuccess")
        }
    }
}
