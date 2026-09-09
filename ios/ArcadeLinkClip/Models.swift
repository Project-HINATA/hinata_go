import Foundation

struct PublicMachine: Decodable {
  let publicId: String
  let name: String
  let shop: Shop
}

struct Shop: Decodable {
  let name: String
  let heroUrl: String?
  let latitude: Double
  let longitude: Double
  let radiusMeters: Double
}

struct ArcadeLinkUser: Decodable {
  let id: String
  let username: String
  let displayName: String
}

struct ArcadeCard: Decodable, Identifiable {
  let id: String
  let label: String
  let accessCode: String
  let disabledAt: String?
}

struct MachineSessionResponse: Decodable {
  let ticket: String
  let expiresIn: Int
  let machine: PublicMachine
}

struct MeResponse: Decodable {
  let user: ArcadeLinkUser?
}

struct CardsResponse: Decodable {
  let cards: [ArcadeCard]
}

struct PasskeyRequestOptions: Decodable {
  let challenge: String
  let rpId: String
}

struct PasskeyAssertion: Encodable {
  let id: String
  let rawId: String
  let response: PasskeyAssertionResponse
  let type: String
}

struct PasskeyAssertionResponse: Encodable {
  let clientDataJSON: String
  let authenticatorData: String
  let signature: String
  let userHandle: String?
}

struct MachineLoginRequest: Encodable {
  let cardId: String
  let lat: Double
  let lng: Double
  let accuracy: Double
  let ticket: String
}

struct EmptyResponse: Decodable {
  let ok: Bool
}
