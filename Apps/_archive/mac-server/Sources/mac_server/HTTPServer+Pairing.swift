import Foundation
import Network
import ServerProtocol

extension HTTPServer {
    func handleCreatePairingChallenge(request: HTTPRequest, on connection: NWConnection) {
        let challengeRequest: PairingChallengeRequest
        if request.body.isEmpty {
            challengeRequest = PairingChallengeRequest()
        } else {
            do {
                challengeRequest = try ServerJSONCoding.makeDecoder().decode(
                    PairingChallengeRequest.self,
                    from: request.body
                )
            } catch {
                sendError(
                    statusCode: 400,
                    code: "invalid_request",
                    message: "Unable to decode pairing challenge payload",
                    on: connection
                )
                return
            }
        }

        purgeExpiredPairingChallenges()

        let challengeID = UUID().uuidString
        let setupCode = String(format: "%06d", Int.random(in: 0..<1_000_000))
        let expiresAt = Date().addingTimeInterval(10 * 60)

        pairingChallenges[challengeID] = PairingChallenge(
            id: challengeID,
            setupCode: setupCode,
            expiresAt: expiresAt,
            requestedDeviceName: challengeRequest.deviceName
        )

        let response = PairingChallengeResponse(
            challengeID: challengeID,
            setupCode: setupCode,
            expiresAt: expiresAt,
            serverName: serverName,
            serverFingerprint: serverFingerprint,
            canonicalHostname: ProcessInfo.processInfo.environment["DEVYS_CANONICAL_HOSTNAME"].flatMap(\.nilIfEmpty),
            fallbackAddress: ProcessInfo.processInfo.environment["DEVYS_FALLBACK_ADDRESS"].flatMap(\.nilIfEmpty)
        )
        sendJSON(statusCode: 201, payload: response, on: connection)
    }

    func handlePairingExchange(request: HTTPRequest, on connection: NWConnection) {
        guard let exchangeRequest = decodePairingExchangeRequest(request, on: connection) else { return }

        purgeExpiredPairingChallenges()
        guard let challenge = validatedPairingChallenge(for: exchangeRequest, on: connection) else { return }
        guard let deviceName = validatedPairingDeviceName(from: exchangeRequest.deviceName, on: connection) else {
            return
        }
        if let requested = challenge.requestedDeviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requested.isEmpty,
           requested != deviceName
        {
            sendError(
                statusCode: 409,
                code: "pairing_device_name_mismatch",
                message: "Device name does not match pairing challenge request",
                details: [
                    "expectedDeviceName": .string(requested),
                    "providedDeviceName": .string(deviceName)
                ],
                on: connection
            )
            return
        }

        let pairing = makePairingRecord(deviceName: deviceName)
        let authToken = makePairingToken()
        pairings[pairing.id] = pairing
        pairingTokens[pairing.id] = authToken
        pairingChallenges.removeValue(forKey: challenge.id)
        persistPairings()

        sendJSON(
            statusCode: 200,
            payload: PairingExchangeResponse(pairing: pairing, authToken: authToken),
            on: connection
        )
    }

    func handleListPairings(on connection: NWConnection) {
        let response = ListPairingsResponse(
            pairings: pairings.values.sorted { $0.updatedAt > $1.updatedAt }
        )
        sendJSON(statusCode: 200, payload: response, on: connection)
    }

    func handleRotatePairing(pairingID: String, on connection: NWConnection) {
        guard let pairing = pairings[pairingID] else {
            sendError(statusCode: 404, code: "pairing_not_found", message: "Pairing not found", on: connection)
            return
        }

        guard pairing.status == .active else {
            sendError(
                statusCode: 409,
                code: "pairing_not_active",
                message: "Pairing is not active",
                on: connection
            )
            return
        }

        let rotatedAt = Date()
        let updatedPairing = PairingRecord(
            id: pairing.id,
            deviceName: pairing.deviceName,
            createdAt: pairing.createdAt,
            updatedAt: rotatedAt,
            status: pairing.status
        )
        let authToken = UUID().uuidString.replacingOccurrences(of: "-", with: "") +
            UUID().uuidString.replacingOccurrences(of: "-", with: "")

        pairings[pairingID] = updatedPairing
        pairingTokens[pairingID] = authToken
        persistPairings()

        sendJSON(
            statusCode: 200,
            payload: RotatePairingResponse(pairing: updatedPairing, authToken: authToken, rotatedAt: rotatedAt),
            on: connection
        )
    }

    func handleRevokePairing(pairingID: String, on connection: NWConnection) {
        guard let pairing = pairings[pairingID] else {
            sendError(statusCode: 404, code: "pairing_not_found", message: "Pairing not found", on: connection)
            return
        }

        let revokedAt = Date()
        let revokedPairing = PairingRecord(
            id: pairing.id,
            deviceName: pairing.deviceName,
            createdAt: pairing.createdAt,
            updatedAt: revokedAt,
            status: .revoked
        )

        pairings[pairingID] = revokedPairing
        pairingTokens.removeValue(forKey: pairingID)
        persistPairings()

        sendJSON(
            statusCode: 200,
            payload: RevokePairingResponse(pairing: revokedPairing),
            on: connection
        )
    }

    func purgeExpiredPairingChallenges() {
        let now = Date()
        pairingChallenges = pairingChallenges.filter { _, challenge in
            challenge.expiresAt > now
        }
    }

    func decodePairingExchangeRequest(_ request: HTTPRequest, on connection: NWConnection) -> PairingExchangeRequest? {
        do {
            return try ServerJSONCoding.makeDecoder().decode(PairingExchangeRequest.self, from: request.body)
        } catch {
            sendError(
                statusCode: 400,
                code: "invalid_request",
                message: "Unable to decode pairing exchange payload",
                on: connection
            )
            return nil
        }
    }

    func validatedPairingChallenge(
        for exchangeRequest: PairingExchangeRequest,
        on connection: NWConnection
    ) -> PairingChallenge? {
        guard let challenge = pairingChallenges[exchangeRequest.challengeID] else {
            sendError(
                statusCode: 404,
                code: "pairing_challenge_not_found",
                message: "Pairing challenge not found or expired",
                on: connection
            )
            return nil
        }

        guard challenge.setupCode == exchangeRequest.setupCode else {
            sendError(
                statusCode: 401,
                code: "pairing_code_invalid",
                message: "Pairing code does not match the active challenge",
                on: connection
            )
            return nil
        }

        return challenge
    }

    func validatedPairingDeviceName(from input: String, on connection: NWConnection) -> String? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            sendError(
                statusCode: 422,
                code: "pairing_device_name_invalid",
                message: "Device name is required",
                on: connection
            )
            return nil
        }
        return normalized
    }

    func makePairingRecord(deviceName: String) -> PairingRecord {
        let now = Date()
        return PairingRecord(
            id: UUID().uuidString,
            deviceName: deviceName,
            createdAt: now,
            updatedAt: now,
            status: .active
        )
    }

    func makePairingToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "") +
            UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}
