import Foundation

struct AnimationTransition {
    let isTransition: Bool
    let repeatCount: Int
    let nextState: PetAnimationState

    static func none(looping state: PetAnimationState) -> AnimationTransition {
        AnimationTransition(isTransition: false, repeatCount: 0, nextState: state)
    }
}

enum PetAnimationState {
    case idleDefault
    case idleSmile
    case idleBoring
    case idleJumping
    case idleWalk
    case idleTouch
    case idleTouchWalk
    case idleWorkingPrepare
    case idleWorking

    var assetName: String {
        switch self {
        case .idleDefault: return "Idle_Default"
        case .idleSmile: return "Idle_Smile"
        case .idleBoring: return "Idle_Boring"
        case .idleJumping: return "Idle_Jumping"
        case .idleWalk: return "Idle_Walk"
        case .idleTouch: return "Idle_Touch"
        case .idleTouchWalk: return "Idle_Touch_Walk"
        case .idleWorkingPrepare: return "Idle_Working_Prepare"
        case .idleWorking: return "Idle_Working"
        }
    }

    var frameDurationsMs: [Double] {
        switch self {
        case .idleDefault:
            return [500, 100, 100, 100]
        case .idleSmile:
            return [500, 100, 100, 100]
        case .idleBoring:
            return [500, 100, 100, 100]
        case .idleJumping:
            return [1, 80, 80, 80, 80, 80, 80]
        case .idleWalk:
            return [70, 70, 70, 70]
        case .idleTouch:
            return [1, 60, 60, 60, 60]
        case .idleTouchWalk:
            return [100, 100, 100, 100]
        case .idleWorkingPrepare:
            return [1, 70, 70, 80, 80, 80, 80, 70, 70, 50, 50, 150, 300, 80, 80, 80, 500]
        case .idleWorking:
            return [30, 30, 30, 30, 30, 30]
        }
    }

    var transition: AnimationTransition {
        switch self {
        case .idleSmile:
            return AnimationTransition(isTransition: true, repeatCount: 2, nextState: .idleDefault)
        case .idleBoring:
            return AnimationTransition(isTransition: true, repeatCount: 2, nextState: .idleDefault)
        case .idleJumping:
            return AnimationTransition(isTransition: true, repeatCount: 1, nextState: .idleDefault)
        case .idleTouch:
            return AnimationTransition(isTransition: true, repeatCount: 1, nextState: .idleTouchWalk)
        case .idleWorkingPrepare:
            return AnimationTransition(isTransition: true, repeatCount: 1, nextState: .idleWorking)
        case .idleDefault, .idleWalk, .idleTouchWalk, .idleWorking:
            return .none(looping: self)
        }
    }

    var isPrimaryInteractionState: Bool {
        self == .idleDefault || self == .idleWorking
    }

    var isWorkingState: Bool {
        self == .idleWorking || self == .idleWorkingPrepare
    }
}
