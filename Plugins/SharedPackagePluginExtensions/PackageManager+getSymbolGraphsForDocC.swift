// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors

import Foundation
import PackagePlugin

/// Generating symbol graphs is the only task that can't run in parallel.
///
/// We serialize its execution to support build concurrency for the other tasks.
private let symbolGraphGenerationLock = Lock()

extension PackageManager {
    struct DocCSymbolGraphResult {
        let unifiedSymbolGraphsDirectory: URL
        let targetSymbolGraphsDirectory: URL
        let snippetSymbolGraphFile: URL?
        
        init(
            unifiedSymbolGraphsDirectory: URL,
            targetSymbolGraphsDirectory: URL,
            snippetSymbolGraphFile: URL?
        ) {
            self.unifiedSymbolGraphsDirectory = unifiedSymbolGraphsDirectory
            self.targetSymbolGraphsDirectory = targetSymbolGraphsDirectory
            self.snippetSymbolGraphFile = snippetSymbolGraphFile
        }
        
        init(targetSymbolGraphsDirectory: URL) {
            self.unifiedSymbolGraphsDirectory = targetSymbolGraphsDirectory
            self.targetSymbolGraphsDirectory = targetSymbolGraphsDirectory
            self.snippetSymbolGraphFile = nil
        }
    }
    
    /// Returns the relevant symbols graphs for Swift-DocC documentation generation for the given target.
    func doccSymbolGraphs(
        for target: SourceModuleTarget,
        context: PluginContext,
        verbose: Bool,
        snippetExtractor: SnippetExtractor?,
        customSymbolGraphOptions: ParsedSymbolGraphArguments
    ) throws -> DocCSymbolGraphResult {
        // First generate the primary symbol graphs containing information about the
        // symbols defined in the target itself.
        var symbolGraphOptions = target.defaultSymbolGraphOptions(in: context.package)
        
        if let rawMinimumAccessLevel = customSymbolGraphOptions.minimumAccessLevel,
           let minimumAccessLevel = SymbolGraphOptions.AccessLevel(rawValue: rawMinimumAccessLevel)
        {
            symbolGraphOptions.minimumAccessLevel = minimumAccessLevel
        }
        
        if customSymbolGraphOptions.skipSynthesizedSymbols == true {
            symbolGraphOptions.includeSynthesized = false
        }
        
        if let includeExtendedTypes = customSymbolGraphOptions.includeExtendedTypes {
#if swift(<5.8)
            print("warning: detected '--\(includeExtendedTypes ? "include" : "exclude")-extended-types' option, which is incompatible with your swift version (required: 5.8)")
#else
            symbolGraphOptions.emitExtensionBlocks = includeExtendedTypes
#endif
        }
        
        if verbose {
            print("symbol graph options: '\(symbolGraphOptions)'")
        }
        
        let targetSymbolGraphs = try symbolGraphGenerationLock.withLock {
            try getSymbolGraph(for: target, options: symbolGraphOptions)
        }
        let targetSymbolGraphsDirectory = URL(
            fileURLWithPath: targetSymbolGraphs.directoryPath.string,
            isDirectory: true
        )
        
        if verbose {
            print("target symbol graph directory path: '\(targetSymbolGraphsDirectory.path)'")
        }
        
        // Then, check to see if we were provided a snippet extractor. If so,
        // we should attempt to generate symbol graphs for any snippets included in the
        // target's containing package.
        guard let snippetExtractor = snippetExtractor else {
            return DocCSymbolGraphResult(targetSymbolGraphsDirectory: targetSymbolGraphsDirectory)
        }
        
        if verbose {
            print("snippet extractor provided, attempting to generate snippet symbol graph")
        }
        
        guard let snippetSymbolGraphFile = try snippetExtractor.generateSnippets(
            for: target,
            context: context
        ) else {
            if verbose {
                print("no snippet symbol graphs generated")
            }
            
            return DocCSymbolGraphResult(targetSymbolGraphsDirectory: targetSymbolGraphsDirectory)
        }
        
        if verbose {
            print("snippet symbol graph file: '\(snippetSymbolGraphFile.path)'")
        }
        
        // Since we successfully produced symbol graphs for snippets contained in the
        // target's containing package, we need to move all generated symbol graphs into
        // a single, unified, symbol graph directory.
        //
        // This is necessary because the `docc` CLI only supports accepting a single directory
        // of symbol graphs.
        
        let unifiedSymbolGraphsDirectory = URL(
            fileURLWithPath: context.pluginWorkDirectory.string,
            isDirectory: true
        )
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("symbol-graphs", isDirectory: true)
        .appendingPathComponent("unified-symbol-graphs", isDirectory: true)
        .appendingPathComponent("\(target.name)-\(target.id)", isDirectory: true)
        
        if verbose {
            print("unified symbol graphs directory path: '\(unifiedSymbolGraphsDirectory.path)'")
        }
        
        // If there's an existing directory containing unified symbol graphs for this target,
        // just remove it. Ignore the error that could occur if the directory doesn't exist.
        try? FileManager.default.removeItem(atPath: unifiedSymbolGraphsDirectory.path)
        
        try FileManager.default.createDirectory(
            atPath: unifiedSymbolGraphsDirectory.path,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        let targetSymbolGraphsUnifiedDirectory = unifiedSymbolGraphsDirectory.appendingPathComponent(
            "target-symbol-graphs", isDirectory: true
        )
        
        // Copy the symbol graphs for the target into the unified directory
        try FileManager.default.copyItem(
            atPath: targetSymbolGraphsDirectory.path,
            toPath: targetSymbolGraphsUnifiedDirectory.path
        )
        
        let snippetSymbolGraphFileInUnifiedDirectory = unifiedSymbolGraphsDirectory.appendingPathComponent(
            snippetSymbolGraphFile.lastPathComponent, isDirectory: false
        )
        
        // Copy the snippet symbol graphs into the unified directory
        try FileManager.default.copyItem(
            atPath: snippetSymbolGraphFile.path,
            toPath: snippetSymbolGraphFileInUnifiedDirectory.path
        )
        
        return DocCSymbolGraphResult(
            unifiedSymbolGraphsDirectory: unifiedSymbolGraphsDirectory,
            targetSymbolGraphsDirectory: targetSymbolGraphsUnifiedDirectory,
            snippetSymbolGraphFile: snippetSymbolGraphFileInUnifiedDirectory
        )
    }
}
