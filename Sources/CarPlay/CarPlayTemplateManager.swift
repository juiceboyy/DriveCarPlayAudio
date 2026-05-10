import CarPlay

// Manages all CarPlay UI templates and reacts to Drive/player state.
final class CarPlayTemplateManager: NSObject {
    static let shared = CarPlayTemplateManager()

    private weak var interfaceController: CPInterfaceController?

    // MARK: - Connection lifecycle

    func connect(to controller: CPInterfaceController) {
        interfaceController = controller
        showFolder(id: "root", title: "Google Drive", animated: false)
    }

    func disconnect() {
        interfaceController = nil
    }

    // MARK: - Navigation

    func showFolder(id: String, title: String, animated: Bool = true) {
        let template = CPListTemplate(title: title, sections: [])
        template.emptyViewTitleVariants   = ["Laden\u{2026}"]
        template.emptyViewSubtitleVariants = ["Even geduld"]

        if interfaceController?.templates.isEmpty ?? true {
            interfaceController?.setRootTemplate(template, animated: false, completion: nil)
        } else {
            interfaceController?.pushTemplate(template, animated: animated, completion: nil)
        }

        Task { await self.loadFolder(id: id, into: template) }
    }

    // MARK: - Data loading

    private func loadFolder(id: String, into template: CPListTemplate) async {
        do {
            let files   = try await GoogleDriveService.shared.listFiles(inFolder: id)
            let folders = files.filter(\.isFolder)
            let audio   = files.filter(\.isAudio)

            var sections: [CPListSection] = []

            if !folders.isEmpty {
                let items = folders.map { folder -> CPListItem in
                    let item = CPListItem(text: folder.name, detailText: "Map")
                    item.handler = { [weak self] _, completion in
                        self?.showFolder(id: folder.id, title: folder.name)
                        completion()
                    }
                    return item
                }
                sections.append(CPListSection(items: items, header: "Mappen", sectionIndexTitle: nil))
            }

            if !audio.isEmpty {
                let items = audio.map { file -> CPListItem in
                    let item = CPListItem(text: file.name, detailText: file.displayMimeLabel)
                    item.handler = { _, completion in
                        Task { await AudioPlayerService.shared.play(file: file, fromQueue: audio) }
                        completion()
                    }
                    return item
                }
                sections.append(CPListSection(items: items, header: "Audio", sectionIndexTitle: nil))
            }

            if sections.isEmpty {
                template.emptyViewTitleVariants    = ["Geen bestanden"]
                template.emptyViewSubtitleVariants = ["Deze map bevat geen audio of submappen."]
            }

            await MainActor.run { template.updateSections(sections) }

        } catch GoogleDriveService.DriveError.unauthorized {
            await MainActor.run { template.emptyViewTitleVariants = ["Sessie verlopen — open de app om opnieuw in te loggen."] }
            NotificationCenter.default.post(name: .driveAuthRequired, object: nil)

        } catch GoogleDriveService.DriveError.networkUnavailable {
            await setError("Geen internetverbinding.", on: template)

        } catch {
            await setError(error.localizedDescription, on: template)
        }
    }

    private func setError(_ message: String, on template: CPListTemplate) async {
        await MainActor.run {
            template.emptyViewTitleVariants    = ["Fout"]
            template.emptyViewSubtitleVariants = [message]
            template.updateSections([])
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let driveAuthRequired = Notification.Name("driveAuthRequired")
}
