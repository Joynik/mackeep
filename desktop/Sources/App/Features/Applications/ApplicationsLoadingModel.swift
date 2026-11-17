import Foundation

extension ApplicationsModel {
    /// What is read from Mackeep.
    struct LoadResult: Sendable {
        /// The applications of Mackeep.
        let applications: [MackeepApplication]

        /// The path of the config file Mackeep uses.
        let configURL: URL?

        /// The content of the config file.
        let configDocument: INIDocument?

        /// The directory where the config files of the user are.
        let customAppsDir: String?

        /// The message of the error, when there is one.
        let errorMessage: String?
    }

    /// Read the applications and the config of Mackeep.
    ///
    /// - Parameter command: The command line tool of Mackeep.
    /// - Returns: What was read.
    nonisolated static func load(with command: MackeepCommand) -> LoadResult {
        do {
            let applications: [MackeepApplication] = try command.runJSON(
                ["--json", "list"],
                as: [MackeepApplication].self
            )

            // The config file Mackeep uses is the one that is edited
            let json: MackeepConfig = try command.runJSON(
                ["--json", "config"],
                as: MackeepConfig.self
            )
            let url: URL = URL(fileURLWithPath: json.configFile)
            let document: INIDocument = try INIFile.load(
                from: url,
                stripsInlineComments: true
            )
            return LoadResult(
                applications: applications,
                configURL: url,
                configDocument: document,
                customAppsDir: json.customAppsDir,
                errorMessage: nil
            )
        } catch {
            return LoadResult(
                applications: [],
                configURL: nil,
                configDocument: nil,
                customAppsDir: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    /// Take what was read from Mackeep.
    ///
    /// - Parameter result: What was read.
    func apply(_ result: LoadResult) {
        if let message: String = result.errorMessage {
            presentedError = AppError(
                title: L10n.string("error.load.title"),
                message: message
            )
            return
        }

        applications = result.applications
        customAppsDir = result.customAppsDir
        if let url: URL = result.configURL, let document: INIDocument = result.configDocument {
            setConfig(MainConfig(url: url, document: document))
        }
        sizeTask?.cancel()
        sizes = [:]
    }
}
