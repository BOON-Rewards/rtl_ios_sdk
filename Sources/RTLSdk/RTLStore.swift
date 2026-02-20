import Foundation

/// Model representing a retail store with location and offer information
@objc public class RTLStore: NSObject, Codable {
    @objc public let id: String
    @objc public let name: String
    @objc public let merchantId: String
    @objc public let latitude: Double
    @objc public let longitude: Double
    @objc public let offerTitle: String?
    @objc public let offerDescription: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case merchantId
        case latitude
        case longitude
        case offerTitle
        case offerDescription
    }

    public init(
        id: String,
        name: String,
        merchantId: String,
        latitude: Double,
        longitude: Double,
        offerTitle: String? = nil,
        offerDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.merchantId = merchantId
        self.latitude = latitude
        self.longitude = longitude
        self.offerTitle = offerTitle
        self.offerDescription = offerDescription
        super.init()
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        merchantId = try container.decode(String.self, forKey: .merchantId)

        // Handle latitude/longitude as strings from API
        let latString = try container.decode(String.self, forKey: .latitude)
        let longString = try container.decode(String.self, forKey: .longitude)
        guard let lat = Double(latString), let long = Double(longString) else {
            throw DecodingError.dataCorruptedError(forKey: .latitude, in: container, debugDescription: "Invalid coordinate format")
        }
        latitude = lat
        longitude = long

        offerTitle = try container.decodeIfPresent(String.self, forKey: .offerTitle)
        offerDescription = try container.decodeIfPresent(String.self, forKey: .offerDescription)
        super.init()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(merchantId, forKey: .merchantId)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encodeIfPresent(offerTitle, forKey: .offerTitle)
        try container.encodeIfPresent(offerDescription, forKey: .offerDescription)
    }
}
