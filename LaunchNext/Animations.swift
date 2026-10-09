import SwiftUI

enum LNAnimations {
    // MARK: - Springs - 优化性能的动画配置
    static var springFast: Animation {
        guard AnimationPreferences.isEnabled else { return .linear(duration: 0.0001) }
        return .spring(response: AnimationPreferences.springResponse, dampingFraction: 0.8)
    }
    
    // MARK: - 性能优化的动画
    static var dragPreview: Animation {
        guard AnimationPreferences.isEnabled else { return .linear(duration: 0.0001) }
        return .easeOut(duration: AnimationPreferences.baseDuration)
    }
    static var gridUpdate: Animation {
        guard AnimationPreferences.isEnabled else { return .linear(duration: 0.0001) }
        return .easeInOut(duration: AnimationPreferences.baseDuration)
    }
    
    // MARK: - Transitions
    static var folderOpenTransition: AnyTransition {
        if AnimationPreferences.isEnabled {
            return AnyTransition.scale(scale: 0.95).combined(with: .opacity)
        } else {
            return AnyTransition.opacity
        }
    }
}

private enum AnimationPreferences {
    static let isEnabled = true
    static let baseDuration = AppStore.fixedWindowAnimationDuration

    static var springResponse: Double {
        max(0.15, baseDuration)
    }
}
