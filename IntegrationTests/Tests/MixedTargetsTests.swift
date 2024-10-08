// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors

import XCTest

final class MixedTargetsTests: ConcurrencyRequiringTestCase {
    func testGenerateDocumentationForSpecificTarget() throws {
        let result = try swiftPackage(
            "generate-documentation", "--target", "Executable",
            workingDirectory: try setupTemporaryDirectoryForFixture(named: "MixedTargets")
        )
        
        result.assertExitStatusEquals(0)
        let archiveURL = try XCTUnwrap(result.onlyOutputArchive)
        
        XCTAssertEqual(try relativeFilePathsIn(.dataSubdirectory, of: archiveURL), expectedExecutableDataFiles)
    }
    
    func testGenerateDocumentationForMultipleSpecificTargets() throws {
        let result = try swiftPackage(
            "generate-documentation", "--target", "Executable", "--target", "Library",
            workingDirectory: try setupTemporaryDirectoryForFixture(named: "MixedTargets")
        )
        
        result.assertExitStatusEquals(0)
        let outputArchives = result.referencedDocCArchives
        XCTAssertEqual(result.referencedDocCArchives.count, 2)
        
        let executableArchiveURL = try XCTUnwrap(
            outputArchives.first(where: { $0.lastPathComponent == "Executable.doccarchive" })
        )
        XCTAssertEqual(try relativeFilePathsIn(.dataSubdirectory, of: executableArchiveURL), expectedExecutableDataFiles)
       
        let libraryArchiveURL = try XCTUnwrap(
            outputArchives.first(where: { $0.lastPathComponent == "Library.doccarchive" })
        )
        XCTAssertEqual(try relativeFilePathsIn(.dataSubdirectory, of: libraryArchiveURL), expectedLibraryDataFiles)
    }
    
    func testMultipleTargetsOutputPath() throws {
        let outputDirectory = try temporaryDirectory().appendingPathComponent("output")
        
        let result = try swiftPackage(
            "--disable-sandbox",
            "generate-documentation", "--target", "Executable", "--target", "Library",
            "--output-path", outputDirectory.path,
            workingDirectory: try setupTemporaryDirectoryForFixture(named: "MixedTargets")
        )
        
        result.assertExitStatusEquals(0)
        let outputArchives = result.referencedDocCArchives
        XCTAssertEqual(outputArchives.count, 2)
        XCTAssertEqual(outputArchives.map(\.path), [
            outputDirectory.appendingPathComponent("Executable.doccarchive").path,
            outputDirectory.appendingPathComponent("Library.doccarchive").path,
        ])
        
        let executableArchiveURL = try XCTUnwrap(
            outputArchives.first(where: { $0.lastPathComponent == "Executable.doccarchive" })
        )
        let executableDataDirectoryContents = try filesIn(.dataSubdirectory, of: executableArchiveURL)
            .map(\.relativePath)
            .sorted()
        
        XCTAssertEqual(executableDataDirectoryContents, expectedExecutableDataFiles)
        
        let libraryArchiveURL = try XCTUnwrap(
            outputArchives.first(where: { $0.lastPathComponent == "Library.doccarchive" })
        )
        let libraryDataDirectoryContents = try filesIn(.dataSubdirectory, of: libraryArchiveURL)
            .map(\.relativePath)
            .sorted()
        
        XCTAssertEqual(libraryDataDirectoryContents, expectedLibraryDataFiles)
    }

    func testCombinedDocumentation() throws {
#if compiler(>=6.0)
        let result = try swiftPackage(
            "generate-documentation", "--target", "Executable", "--target", "Library",
            "--enable-experimental-combined-documentation",
            workingDirectory: try setupTemporaryDirectoryForFixture(named: "MixedTargets")
        )
        
        result.assertExitStatusEquals(0)
        let outputArchives = result.referencedDocCArchives
        XCTAssertEqual(outputArchives.count, 1)
        XCTAssertEqual(outputArchives.map(\.lastPathComponent), [
            "MixedTargets.doccarchive",
        ])
        
        let combinedArchiveURL = try XCTUnwrap(outputArchives.first)
        let combinedDataDirectoryContents = try filesIn(.dataSubdirectory, of: combinedArchiveURL)
            .map(\.relativePath)
            .sorted()
        
        XCTAssertEqual(combinedDataDirectoryContents, expectedCombinedDataFiles)
#else
        XCTSkip("This test requires a Swift-DocC version that support the link-dependencies feature")
#endif
    }
    
    func testCombinedDocumentationWithOutputPath() throws {
#if compiler(>=6.0)
        let outputDirectory = try temporaryDirectory().appendingPathComponent("output")
        
        let result = try swiftPackage(
            "--disable-sandbox",
            "generate-documentation", "--target", "Executable", "--target", "Library",
            "--enable-experimental-combined-documentation",
            "--output-path", outputDirectory.path,
            workingDirectory: try setupTemporaryDirectoryForFixture(named: "MixedTargets")
        )
        
        result.assertExitStatusEquals(0)
        let outputArchives = result.referencedDocCArchives
        XCTAssertEqual(outputArchives.count, 1)
        XCTAssertEqual(outputArchives.map(\.path), [
            outputDirectory.path
        ])
        
        let combinedArchiveURL = try XCTUnwrap(outputArchives.first)
        let combinedDataDirectoryContents = try filesIn(.dataSubdirectory, of: combinedArchiveURL)
            .map(\.relativePath)
            .sorted()
        
        XCTAssertEqual(combinedDataDirectoryContents, expectedCombinedDataFiles)
#else
        XCTSkip("This test requires a Swift-DocC version that support the link-dependencies feature")
#endif
    }
}

private let expectedCombinedDataFiles = [
    "documentation.json"
] + expectedExecutableDataFiles + expectedLibraryDataFiles

private let expectedExecutableDataFiles = [
    "documentation/executable.json",
    "documentation/executable/foo.json",
    "documentation/executable/foo/foo().json",
    "documentation/executable/foo/init().json",
    "documentation/executable/foo/main().json",
]

private let expectedLibraryDataFiles = [
    "documentation/library.json",
    "documentation/library/foo.json",
    "documentation/library/foo/foo().json",
]
