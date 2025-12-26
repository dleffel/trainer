import Foundation

/// Manages credentials for the Organizer Exercise API
/// Stores email and app password in UserDefaults for API authentication
class ExerciseAPICredentials {
    static let shared = ExerciseAPICredentials()
    
    private init() {}
    
    // MARK: - Properties
    
    /// User's email for Organizer API
    var email: String {
        get { UserDefaults.standard.string(forKey: PersistenceKey.OrganizerAPI.email) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: PersistenceKey.OrganizerAPI.email) }
    }
    
    /// App password for Organizer API (format: xxxx-xxxx-xxxx-xxxx-xxxx-xxxx)
    var password: String {
        get { UserDefaults.standard.string(forKey: PersistenceKey.OrganizerAPI.password) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: PersistenceKey.OrganizerAPI.password) }
    }
    
    /// Check if both credentials are configured
    var hasCredentials: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Authentication
    
    /// Generate HTTP Basic Auth header value
    var basicAuthHeader: String {
        let credentials = "\(email):\(password)"
        let data = credentials.data(using: .utf8)!
        return "Basic \(data.base64EncodedString())"
    }
    
    // MARK: - Validation
    
    /// Validate password format (xxxx-xxxx-xxxx-xxxx-xxxx-xxxx)
    /// - Parameter password: The password to validate
    /// - Returns: true if format is valid
    func validatePasswordFormat(_ password: String) -> Bool {
        // Pattern: 6 groups of 4 alphanumeric characters separated by dashes
        let pattern = "^[a-zA-Z0-9]{4}(-[a-zA-Z0-9]{4}){5}$"
        return password.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// Validate email format
    /// - Parameter email: The email to validate
    /// - Returns: true if format appears valid
    func validateEmailFormat(_ email: String) -> Bool {
        let pattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return email.range(of: pattern, options: .regularExpression) != nil
    }
    
    // MARK: - Clear
    
    /// Clear stored credentials
    func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: PersistenceKey.OrganizerAPI.email)
        UserDefaults.standard.removeObject(forKey: PersistenceKey.OrganizerAPI.password)
    }
}
