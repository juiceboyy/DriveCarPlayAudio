import Foundation

final class GoogleDriveService {
    static let shared = GoogleDriveService()

    private let baseURL = "https://www.googleapis.com/drive/v3"

    // MARK: - Public API

    func listFiles(inFolder folderID: String) async throws -> [DriveFile] {
        let token = try await GoogleAuthService.shared.getValidToken()

        var components = URLComponents(string: "\(baseURL)/files")!
        components.queryItems = [
            URLQueryItem(name: "q",        value: "'\(folderID)' in parents and trashed = false"),
            URLQueryItem(name: "fields",   value: "files(id,name,mimeType,size,parents)"),
            URLQueryItem(name: "orderBy",  value: "folder,name"),
            URLQueryItem(name: "pageSize", value: "200"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let response: FileListResponse = try await fetchWithRetry(request)
        return response.files.map { item in
            DriveFile(
                id:       item.id,
                name:     item.name,
                mimeType: item.mimeType,
                size:     item.size.flatMap { Int64($0) },
                parents:  item.parents
            )
        }
    }

    /// Returns the HTTP headers needed to stream a file.
    func streamHeaders() async throws -> [String: String] {
        let token = try await GoogleAuthService.shared.getValidToken()
        return ["Authorization": "Bearer \(token)"]
    }

    /// Direct media URL for a file ID.
    func mediaURL(for fileID: String) -> URL {
        URL(string: "\(baseURL)/files/\(fileID)?alt=media")!
    }

    // MARK: - fetchWithRetry

    private func fetchWithRetry<T: Decodable>(
        _ request: URLRequest,
        maxRetries: Int = 3
    ) async throws -> T {
        var lastError: Error = DriveError.maxRetriesExceeded
        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw DriveError.invalidResponse
                }
                switch http.statusCode {
                case 200...299:
                    return try JSONDecoder().decode(T.self, from: data)
                case 401:
                    throw DriveError.unauthorized
                case 429, 500...599:
                    lastError = DriveError.serverError(http.statusCode)
                default:
                    throw DriveError.httpError(http.statusCode)
                }
            } catch let error as DriveError {
                switch error {
                case .unauthorized: throw error    // never retry auth failures
                case .serverError:  lastError = error  // retry transient failures
                default:            throw error
                }
            } catch let urlError as URLError where urlError.code == .notConnectedToInternet {
                throw DriveError.networkUnavailable
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Errors

    enum DriveError: LocalizedError, Equatable {
        case invalidResponse
        case unauthorized
        case serverError(Int)
        case httpError(Int)
        case maxRetriesExceeded
        case networkUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidResponse:   return "Ongeldig serverantwoord."
            case .unauthorized:      return "Sessie verlopen. Log opnieuw in."
            case .serverError(let c):return "Serverfout (\(c)). Probeer opnieuw."
            case .httpError(let c):  return "HTTP fout \(c)."
            case .maxRetriesExceeded:return "Maximale pogingen bereikt."
            case .networkUnavailable:return "Geen internetverbinding."
            }
        }
    }

    // MARK: - Private decodable models

    private struct FileListResponse: Decodable {
        let files: [FileItem]
        struct FileItem: Decodable {
            let id: String
            let name: String
            let mimeType: String
            let size: String?
            let parents: [String]?
        }
    }
}
