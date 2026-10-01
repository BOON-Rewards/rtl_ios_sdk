import Foundation

/// Lets an embedding app answer native web and API authentication challenges.
@_spi(RTLExample)
public protocol RTLAuthenticationChallengeHandler: URLSessionTaskDelegate {
    func response(to challenge: URLAuthenticationChallenge) -> (
        URLSession.AuthChallengeDisposition, URLCredential?
    )
}
