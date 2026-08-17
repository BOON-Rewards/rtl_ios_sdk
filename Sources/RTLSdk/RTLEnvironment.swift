import Foundation

/// Environment configuration for RTL SDK
public enum RTLEnvironment {
    /// Development environment (*-dev.staging.getboon.com)
    case development

    /// Staging environment (*.staging.getboon.com)
    case staging

    /// Production environment (*.prod.getboon.com)
    case production
}
