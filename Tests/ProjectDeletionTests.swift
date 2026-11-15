import XCTest
@testable import VietVideoVoiceCheck

final class ProjectDeletionTests: XCTestCase {
    private func makeProject(_ title: String) throws -> VideoProject {
        var project = VideoProject(title: title, duration: 2, movieName: "source.mp4")
        project.draft = SRT.encode([Subtitle(start: 0, end: 1, text: "Xin chào")])
        project.outputName = "export.mp4"
        try ProjectDisk.save(project)
        let folder = ProjectDisk.folder(project.id)
        try Data("source".utf8).write(to: folder.appendingPathComponent("source.mp4"))
        try Data("export".utf8).write(to: folder.appendingPathComponent("export.mp4"))
        let cache = folder.appendingPathComponent("dub-voices", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("voice".utf8).write(to: cache.appendingPathComponent("cached.wav"))
        return project
    }
    @MainActor func testDeletingCurrentRemovesFilesWithoutAutosaveRecreatingProject() async throws {
        let first = try makeProject("Delete me"), other = try makeProject("Keep me")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("saved separately".utf8).write(to: outside)
        defer { try? ProjectDisk.remove(first.id); try? ProjectDisk.remove(other.id); try? FileManager.default.removeItem(at: outside) }
        let store = ProjectStore()
        store.open(first); store.draft += "\n"; store.settings.originalVolume = 75; store.scheduleSave()
        store.delete(first)
        XCTAssertNil(store.current); XCTAssertNil(store.output); XCTAssertEqual(store.draft, "")
        XCTAssertEqual(store.settings, ExportSettings())
        try await Task.sleep(nanoseconds: 700_000_000)
        store.saveDraft()
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectDisk.folder(first.id).path))
        XCTAssertFalse(store.projects.contains { $0.id == first.id })
        XCTAssertFalse(try ProjectDisk.load().contains { $0.id == first.id })
        XCTAssertEqual(try Data(contentsOf: ProjectDisk.folder(other.id).appendingPathComponent("source.mp4")), Data("source".utf8))
        XCTAssertEqual(try Data(contentsOf: outside), Data("saved separately".utf8))
    }
    @MainActor func testBusyDeletionIsBlockedAndDeletingAnotherProjectPreservesDraft() throws {
        let active = try makeProject("Active"), other = try makeProject("Other")
        defer { try? ProjectDisk.remove(active.id); try? ProjectDisk.remove(other.id) }
        let store = ProjectStore(); store.open(active); store.draft = "An edited draft"
        store.busy = true; store.delete(other)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ProjectDisk.folder(other.id).path))
        store.busy = false; store.delete(other)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectDisk.folder(other.id).path))
        XCTAssertEqual(store.current?.id, active.id); XCTAssertEqual(store.draft, "An edited draft")
        store.saveDraft()
        XCTAssertEqual(try ProjectDisk.load().first { $0.id == active.id }?.draft, "An edited draft")
    }
}

