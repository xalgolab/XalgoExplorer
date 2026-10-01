import Foundation

enum FileOperationRequest: Sendable {
    case copy([URL], to: URL)
    case move([URL], to: URL)
    case trash([URL])
}

// Serializes disk mutations off the main actor while AppKit keeps processing input.
actor FileOperationWorker {
    func perform(_ request: FileOperationRequest) throws {
        switch request {
        case let .copy(urls, destination):
            try FileSystemService.copy(urls, to: destination)
        case let .move(urls, destination):
            try FileSystemService.move(urls, to: destination)
        case let .trash(urls):
            try FileSystemService.trash(urls)
        }
    }
}
