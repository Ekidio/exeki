import AppKit

/// A program shown in the "Programjaim" list: either installed into the Windows environment
/// (found through its Start Menu shortcut) or added to the list by hand.
struct InstalledProgram: Identifiable, Hashable {
    let name: String
    let exe: URL
    let workingDirectory: URL?
    let arguments: [String]
    /// Added by hand (e.g. a portable .exe or a DOS game) rather than found in the Start Menu.
    let isPinned: Bool

    var id: String { exe.path.lowercased() }
}

/// Keeps the list of installed programs, rebuilt from the Windows environment's Start Menu.
@MainActor
final class ProgramLibrary: ObservableObject {
    static let shared = ProgramLibrary()

    @Published private(set) var programs: [InstalledProgram] = []
    @Published private(set) var icons: [String: NSImage] = [:]
    @Published private(set) var hiddenCount = 0

    private var hidden: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "hiddenPrograms") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "hiddenPrograms") }
    }

    private var pinned: [String] {
        get { UserDefaults.standard.stringArray(forKey: "pinnedPrograms") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "pinnedPrograms") }
    }

    func refresh() {
        let hidden = hidden
        let pinned = pinned
        Task.detached(priority: .utility) {
            let found = Self.scanStartMenu() + Self.pinnedPrograms(pinned)
            var seen = Set<String>()
            let unique = found.filter { seen.insert($0.id).inserted }
            let visible = unique
                .filter { !hidden.contains($0.id) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            var icons: [String: NSImage] = [:]
            for program in visible {
                icons[program.id] = ExeIcon.image(for: program.exe)
            }
            let hiddenCount = unique.count - visible.count
            let loadedIcons = icons
            await MainActor.run {
                self.programs = visible
                self.icons = loadedIcons
                self.hiddenCount = hiddenCount
            }
        }
    }

    func icon(for program: InstalledProgram) -> NSImage {
        icons[program.id] ?? NSWorkspace.shared.icon(forFile: program.exe.path)
    }

    /// Hand-added programs are removed from the list; installed ones are hidden (they'd come back otherwise).
    func remove(_ program: InstalledProgram) {
        if program.isPinned {
            pinned.removeAll { $0.lowercased() == program.id }
        } else {
            hidden.insert(program.id)
        }
        refresh()
    }

    func showHidden() {
        hidden = []
        refresh()
    }

    func chooseAndPin() {
        let panel = NSOpenPanel()
        panel.message = "Válaszd ki a programot, amit a listába szeretnél tenni"
        panel.allowedContentTypes = ProgramRunner.supportedTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var list = pinned
        for url in panel.urls where !list.contains(where: { $0.lowercased() == url.path.lowercased() }) {
            list.append(url.path)
        }
        pinned = list
        hidden.subtract(panel.urls.map { $0.path.lowercased() })
        refresh()
    }

    // MARK: - Scanning

    /// Shortcuts that installers leave behind which aren't the program itself.
    private nonisolated static let ignoredWords = ["uninstall", "unins0", "uninst", "eltávolít", "repair", "remove "]

    private nonisolated static func scanStartMenu() -> [InstalledProgram] {
        let fm = FileManager.default
        let driveC = AppPaths.prefix.appendingPathComponent("drive_c")
        let startMenu = "Microsoft/Windows/Start Menu/Programs"
        var roots = [driveC.appendingPathComponent("ProgramData/\(startMenu)")]
        let users = driveC.appendingPathComponent("users")
        for user in (try? fm.contentsOfDirectory(atPath: users.path)) ?? [] {
            roots.append(users.appendingPathComponent("\(user)/AppData/Roaming/\(startMenu)"))
            roots.append(users.appendingPathComponent("\(user)/Desktop"))
        }

        var programs: [InstalledProgram] = []
        for root in roots {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where file.pathExtension.lowercased() == "lnk" {
                guard let link = ShellLink(contentsOf: file),
                      let exe = WindowsPath.macURL(link.target),
                      exe.pathExtension.lowercased() == "exe",
                      fm.fileExists(atPath: exe.path)
                else { continue }
                let name = file.deletingPathExtension().lastPathComponent
                let haystack = (name + " " + exe.lastPathComponent).lowercased()
                if ignoredWords.contains(where: haystack.contains) { continue }
                programs.append(InstalledProgram(
                    name: name,
                    exe: exe,
                    workingDirectory: link.workingDirectory.flatMap(WindowsPath.macURL),
                    arguments: WindowsPath.splitArguments(link.arguments ?? ""),
                    isPinned: false))
            }
        }
        return programs
    }

    private nonisolated static func pinnedPrograms(_ paths: [String]) -> [InstalledProgram] {
        paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { InstalledProgram(name: $0.deletingPathExtension().lastPathComponent, exe: $0,
                                    workingDirectory: nil, arguments: [], isPinned: true) }
    }
}

/// Maps Windows paths inside the Wine environment to Mac paths.
enum WindowsPath {
    /// "C:\Program Files\x.exe" → …/Windows/drive_c/Program Files/x.exe, following Wine's drive letters.
    static func macURL(_ path: String) -> URL? {
        let chars = Array(path)
        guard chars.count >= 3, chars[1] == ":", chars[2] == "\\" || chars[2] == "/" else { return nil }
        let letter = String(chars[0]).lowercased()
        let rest = String(chars[3...]).replacingOccurrences(of: "\\", with: "/")
        let devices = AppPaths.prefix.appendingPathComponent("dosdevices")
        let root: URL
        if letter == "c" {
            root = AppPaths.prefix.appendingPathComponent("drive_c")
        } else if let target = try? FileManager.default.destinationOfSymbolicLink(
                    atPath: devices.appendingPathComponent("\(letter):").path) {
            root = URL(fileURLWithPath: target, relativeTo: devices).standardizedFileURL
        } else {
            return nil
        }
        return rest.isEmpty ? root : root.appendingPathComponent(rest)
    }

    /// Splits a Windows command line on spaces, keeping "quoted parts" together.
    static func splitArguments(_ line: String) -> [String] {
        var args: [String] = []
        var current = ""
        var quoted = false
        for char in line {
            if char == "\"" {
                quoted.toggle()
            } else if char == " " && !quoted {
                if !current.isEmpty { args.append(current); current = "" }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { args.append(current) }
        return args
    }
}

/// Minimal reader for Windows shortcut (.lnk) files, per [MS-SHLLINK].
struct ShellLink {
    let target: String
    let workingDirectory: String?
    let arguments: String?

    init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url), data.count >= 0x4C,
              data.u32(0) == 0x4C
        else { return nil }
        let flags = data.u32(0x14)
        var offset = 0x4C

        if flags & 0x01 != 0 {  // HasLinkTargetIDList
            offset += 2 + Int(data.u16(offset))
        }

        var target: String?
        if flags & 0x02 != 0 {  // HasLinkInfo
            let info = offset
            let infoSize = Int(data.u32(info))
            let headerSize = data.u32(info + 4)
            let infoFlags = data.u32(info + 8)
            if infoFlags & 0x01 != 0 {  // VolumeIDAndLocalBasePath
                if headerSize >= 0x24, data.u32(info + 28) != 0 {
                    target = data.utf16String(at: info + Int(data.u32(info + 28)))
                } else {
                    target = data.ansiString(at: info + Int(data.u32(info + 16)))
                }
            }
            offset += infoSize
        }

        // StringData: name, relative path, working dir, arguments, icon location — each only if its flag is set.
        let unicode = flags & 0x80 != 0
        var strings: [UInt32: String] = [:]
        for bit: UInt32 in [0x04, 0x08, 0x10, 0x20, 0x40] where flags & bit != 0 {
            guard offset + 2 <= data.count else { break }
            let count = Int(data.u16(offset))
            let length = unicode ? count * 2 : count
            offset += 2
            guard offset + length <= data.count else { break }
            let bytes = data.subdata(in: offset..<offset + length)
            let decoded = unicode ? String(data: bytes, encoding: .utf16LittleEndian)
                                  : String(data: bytes, encoding: .windowsCP1252)
            strings[bit] = decoded?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            offset += length
        }

        guard let resolved = target ?? strings[0x08], !resolved.isEmpty else { return nil }
        self.target = resolved
        self.workingDirectory = strings[0x10].flatMap { $0.isEmpty ? nil : $0 }
        self.arguments = strings[0x20].flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Pulls the main icon out of a Windows .exe (its first RT_GROUP_ICON resource).
enum ExeIcon {
    static func image(for exe: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: exe, options: .mappedIfSafe), data.count > 0x40,
              data.u16(0) == 0x5A4D  // "MZ"
        else { return nil }
        let pe = Int(data.u32(0x3C))
        guard pe + 24 < data.count, data.u32(pe) == 0x0000_4550 else { return nil }  // "PE\0\0"
        let sectionCount = Int(data.u16(pe + 6))
        let optionalSize = Int(data.u16(pe + 20))
        let optional = pe + 24
        let directories = optional + (data.u16(optional) == 0x20B ? 112 : 96)
        let resourceRVA = Int(data.u32(directories + 2 * 8))
        guard resourceRVA != 0 else { return nil }

        var sections: [(va: Int, size: Int, raw: Int)] = []
        for i in 0..<sectionCount {
            let s = optional + optionalSize + i * 40
            guard s + 24 <= data.count else { break }
            sections.append((Int(data.u32(s + 12)), Int(max(data.u32(s + 8), data.u32(s + 16))), Int(data.u32(s + 20))))
        }
        func fileOffset(_ rva: Int) -> Int? {
            sections.first { rva >= $0.va && rva < $0.va + $0.size }.map { rva - $0.va + $0.raw }
        }
        guard let base = fileOffset(resourceRVA) else { return nil }

        func entries(_ dir: Int) -> [(id: UInt32, target: UInt32)] {
            guard dir + 16 <= data.count else { return [] }
            let count = min(Int(data.u16(dir + 12)) + Int(data.u16(dir + 14)), 4096)
            return (0..<count).compactMap { i in
                let e = dir + 16 + i * 8
                return e + 8 <= data.count ? (data.u32(e), data.u32(e + 4)) : nil
            }
        }
        func leaf(_ target: UInt32) -> Data? {
            var target = target
            var depth = 0
            while target & 0x8000_0000 != 0 {
                guard depth < 4, let first = entries(base + Int(target & 0x7FFF_FFFF)).first else { return nil }
                target = first.target
                depth += 1
            }
            let entry = base + Int(target)
            guard entry + 8 <= data.count, let start = fileOffset(Int(data.u32(entry))) else { return nil }
            let end = start + Int(data.u32(entry + 4))
            return end <= data.count ? data.subdata(in: start..<end) : nil
        }

        let types = Dictionary(entries(base).map { ($0.id, $0.target) }, uniquingKeysWith: { a, _ in a })
        guard let iconDir = types[3], let groupDir = types[14],
              let groupEntry = entries(base + Int(groupDir & 0x7FFF_FFFF)).first,
              let group = leaf(groupEntry.target), group.count >= 6
        else { return nil }
        let icons = Dictionary(entries(base + Int(iconDir & 0x7FFF_FFFF)).map { ($0.id, $0.target) },
                               uniquingKeysWith: { a, _ in a })

        // Pick the largest, most colourful image in the group.
        var best: (size: Int, bpp: Int, entry: Int)?
        for i in 0..<Int(group.u16(4)) {
            let e = 6 + i * 14
            guard e + 14 <= group.count else { break }
            let size = group[e] == 0 ? 256 : Int(group[e])
            let bpp = Int(group.u16(e + 6))
            if best == nil || (size, bpp) > (best!.size, best!.bpp) { best = (size, bpp, e) }
        }
        guard let pick = best, let target = icons[UInt32(group.u16(pick.entry + 12))],
              let image = leaf(target)
        else { return nil }

        if image.starts(with: [0x89, 0x50, 0x4E, 0x47]) {  // PNG
            return NSImage(data: image)
        }
        // Wrap the bitmap in a one-image .ico so ImageIO can decode it.
        var ico = Data([0, 0, 1, 0, 1, 0])
        ico.append(group.subdata(in: pick.entry..<pick.entry + 8))
        ico.append(contentsOf: withUnsafeBytes(of: UInt32(image.count).littleEndian, Array.init))
        ico.append(contentsOf: withUnsafeBytes(of: UInt32(22).littleEndian, Array.init))
        ico.append(image)
        return NSImage(data: ico)
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }

    func ansiString(at offset: Int) -> String? {
        guard offset >= 0, offset < count else { return nil }
        let bytes = self[(startIndex + offset)...].prefix { $0 != 0 }
        return String(data: Data(bytes), encoding: .windowsCP1252)
    }

    func utf16String(at offset: Int) -> String? {
        guard offset >= 0, offset < count else { return nil }
        var end = offset
        while end + 1 < count, u16(end) != 0 { end += 2 }
        return String(data: subdata(in: startIndex + offset..<startIndex + end), encoding: .utf16LittleEndian)
    }
}
