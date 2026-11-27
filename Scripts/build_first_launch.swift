// Draws Scripts/dmg/First Launch.pdf - the guide for opening the not yet notarized app for the first time.
// The PDF is shipped with the releases by build_signed.sh and is kept in the repository,
// so this needs to be run only after changing the guide or its screenshots in Docs/FirstLaunch.
// Usage: ./build_first_launch.sh

import AppKit

// MARK: - Content

struct Paragraph {
    let language: String
    // Text in **double asterisks** is drawn in bold.
    let text: String
}

struct Step {
    let title: String
    let image: String
    let imageWidthFraction: CGFloat
    let paragraphs: [Paragraph]
}

let title = "Dextra Commander - First Launch"
let subtitle = "English · Deutsch · Русский"

let intro = [
    Paragraph(language: "EN", text: "Dextra Commander is not notarized by Apple yet, so macOS asks you to confirm that you trust it the first time you open it. This is needed only once."),
    Paragraph(language: "DE", text: "Dextra Commander ist noch nicht von Apple notarisiert. Deshalb fragt macOS beim ersten Öffnen nach, ob Sie der App vertrauen. Das ist nur einmal nötig."),
    Paragraph(language: "RU", text: "Dextra Commander пока не прошёл нотаризацию Apple, поэтому при первом запуске macOS просит подтвердить, что вы доверяете приложению. Это нужно сделать один раз."),
]

let steps = [
    Step(title: "1   Install · Installieren · Установка", image: "step1.png", imageWidthFraction: 0.5, paragraphs: [
        Paragraph(language: "EN", text: "Open the disk image and drag “Dextra Commander” into the “Applications” folder."),
        Paragraph(language: "DE", text: "Öffnen Sie das Disk-Image und ziehen Sie „Dextra Commander“ in den Ordner „Programme“."),
        Paragraph(language: "RU", text: "Откройте образ диска и перетащите «Dextra Commander» в папку «Программы»."),
    ]),
    Step(title: "2   First start · Erster Start · Первый запуск", image: "step2.png", imageWidthFraction: 0.32, paragraphs: [
        Paragraph(language: "EN", text: "Open Dextra Commander from the Applications folder. macOS says that it could not verify the app. Click **Done**."),
        Paragraph(language: "DE", text: "Öffnen Sie Dextra Commander im Ordner „Programme“. macOS meldet, dass die App nicht überprüft werden konnte. Klicken Sie auf **Fertig**."),
        Paragraph(language: "RU", text: "Откройте Dextra Commander из папки «Программы». macOS сообщит, что не удалось проверить приложение. Нажмите **Готово**."),
    ]),
    Step(title: "3   Allow · Erlauben · Разрешить", image: "step3.png", imageWidthFraction: 0.5, paragraphs: [
        Paragraph(language: "EN", text: "Open the Apple menu > **System Settings** > **Privacy & Security**. Scroll down to “Security”, where it says that Dextra Commander was blocked, and click **Open Anyway**."),
        Paragraph(language: "DE", text: "Öffnen Sie Apple-Menü > **Systemeinstellungen** > **Datenschutz & Sicherheit**. Scrollen Sie zu „Sicherheit“, wo steht, dass Dextra Commander blockiert wurde, und klicken Sie auf **Dennoch öffnen**."),
        Paragraph(language: "RU", text: "Откройте меню Apple > **Системные настройки** > **Конфиденциальность и безопасность**. Прокрутите до раздела «Безопасность» со строкой о блокировке Dextra Commander и нажмите **Всё равно открыть**."),
    ]),
    Step(title: "4   Confirm · Bestätigen · Подтвердить", image: "step4.png", imageWidthFraction: 0.28, paragraphs: [
        Paragraph(language: "EN", text: "Click **Open Anyway** once more and enter your password if asked. From now on Dextra Commander opens normally."),
        Paragraph(language: "DE", text: "Klicken Sie noch einmal auf **Dennoch öffnen** und geben Sie bei Bedarf Ihr Passwort ein. Ab jetzt startet Dextra Commander ganz normal."),
        Paragraph(language: "RU", text: "Ещё раз нажмите **Всё равно открыть** и, если потребуется, введите пароль. После этого Dextra Commander открывается как обычно."),
    ]),
]

let troubleshootingTitle = "If it doesn’t work · Falls es nicht klappt · Если не получилось"
let troubleshooting = [
    Paragraph(language: "EN", text: "If macOS says the app “is damaged”, or there is no “Open Anyway” button, open the Terminal app, run this command and open Dextra Commander again:"),
    Paragraph(language: "DE", text: "Falls macOS meldet, die App sei „beschädigt“, oder die Taste „Dennoch öffnen“ fehlt, öffnen Sie das Programm „Terminal“, führen Sie diesen Befehl aus und öffnen Sie Dextra Commander erneut:"),
    Paragraph(language: "RU", text: "Если macOS пишет, что приложение «повреждено», или кнопки «Всё равно открыть» нет, откройте программу «Терминал», выполните эту команду и снова откройте Dextra Commander:"),
]
let command = "xattr -dr com.apple.quarantine \"/Applications/Dextra Commander.app\""

// MARK: - Layout

let pageSize = CGSize(width: 595.28, height: 841.89) // A4
let margin: CGFloat = 44
let contentWidth = pageSize.width - 2 * margin
let accent = NSColor(srgbRed: 0.91, green: 0.45, blue: 0.18, alpha: 1)
let textColor = NSColor(white: 0.13, alpha: 1)
let bodySize: CGFloat = 10

func attributed(_ paragraph: Paragraph) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = 1.15
    style.headIndent = 22
    style.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
    let result = NSMutableAttributedString(string: paragraph.language + "\t", attributes: [
        .font: NSFont.systemFont(ofSize: bodySize, weight: .semibold), .foregroundColor: accent, .paragraphStyle: style,
    ])
    // Odd parts of the split are the ones between the double asterisks.
    for (index, part) in paragraph.text.components(separatedBy: "**").enumerated() {
        let weight: NSFont.Weight = index % 2 == 1 ? .semibold : .regular
        result.append(NSAttributedString(string: part, attributes: [
            .font: NSFont.systemFont(ofSize: bodySize, weight: weight), .foregroundColor: textColor, .paragraphStyle: style,
        ]))
    }
    return result
}

func height(of string: NSAttributedString, width: CGFloat) -> CGFloat {
    ceil(string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                             options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
}

func paragraphsHeight(_ paragraphs: [NSAttributedString], width: CGFloat, spacing: CGFloat) -> CGFloat {
    paragraphs.map { height(of: $0, width: width) }.reduce(0, +) + spacing * CGFloat(max(paragraphs.count - 1, 0))
}

final class Document {
    private let context: CGContext
    private var y: CGFloat = 0

    init(url: URL) {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            fatalError("Can't create \(url.path)")
        }
        self.context = context
    }

    func beginPage() {
        context.beginPDFPage(nil)
        // Draw top-down, like the text system expects in a flipped context.
        context.translateBy(x: 0, y: pageSize.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        y = margin
    }

    func endPage() {
        NSGraphicsContext.current = nil
        context.endPDFPage()
    }

    func close() {
        endPage()
        context.closePDF()
    }

    // Starts a new page unless the block of the given height fits on the current one.
    func ensureSpace(_ needed: CGFloat) {
        if y + needed > pageSize.height - margin {
            endPage()
            beginPage()
        }
    }

    func text(_ string: NSAttributedString, x: CGFloat = margin, width: CGFloat = contentWidth, after: CGFloat = 0) {
        let h = height(of: string, width: width)
        string.draw(with: CGRect(x: x, y: y, width: width, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading])
        y += h + after
    }

    func paragraphs(_ list: [NSAttributedString], x: CGFloat, width: CGFloat, spacing: CGFloat) {
        for (index, paragraph) in list.enumerated() {
            text(paragraph, x: x, width: width, after: index == list.count - 1 ? 0 : spacing)
        }
    }

    func separator() {
        // A line at the very top of a page separates nothing.
        if y == margin {
            return
        }
        context.setStrokeColor(NSColor(white: 0.85, alpha: 1).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
        context.strokePath()
        y += 12
    }

    func image(_ image: NSImage, width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        var size = CGSize(width: width, height: width * image.size.height / image.size.width)
        if size.height > maxHeight {
            size = CGSize(width: maxHeight * image.size.width / image.size.height, height: maxHeight)
        }
        image.draw(in: CGRect(origin: CGPoint(x: margin, y: y), size: size), from: .zero, operation: .sourceOver,
                   fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        return size.height
    }

    func advance(_ delta: CGFloat) {
        y += delta
    }
}

// MARK: - Drawing

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("Usage: build_first_launch <images directory> <output.pdf>\n".data(using: .utf8)!)
    exit(1)
}
let imagesDirectory = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])

func heading(_ string: String, size: CGFloat) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: textColor,
    ])
}

let document = Document(url: output)
document.beginPage()
document.text(heading(title, size: 20), after: 2)
document.text(NSAttributedString(string: subtitle, attributes: [
    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 0.45, alpha: 1),
]), after: 14)
document.paragraphs(intro.map(attributed), x: margin, width: contentWidth, spacing: 6)
document.advance(14)

let gap: CGFloat = 16
let maxImageHeight: CGFloat = 215
for step in steps {
    guard let picture = NSImage(contentsOf: imagesDirectory.appendingPathComponent(step.image)) else {
        fatalError("Can't load \(step.image)")
    }
    let imageWidth = contentWidth * step.imageWidthFraction
    let textWidth = contentWidth - imageWidth - gap
    let texts = step.paragraphs.map(attributed)
    let imageHeight = min(imageWidth * picture.size.height / picture.size.width, maxImageHeight)
    let headingString = heading(step.title, size: 13)
    let rowHeight = max(imageHeight, paragraphsHeight(texts, width: textWidth, spacing: 8))
    document.ensureSpace(12 + height(of: headingString, width: contentWidth) + 8 + rowHeight)

    document.separator()
    document.text(headingString, after: 8)
    // The text goes to the right of the image: both start at the same top, then move below the taller of them.
    _ = document.image(picture, width: imageWidth, maxHeight: maxImageHeight)
    document.paragraphs(texts, x: margin + imageWidth + gap, width: textWidth, spacing: 8)
    document.advance(rowHeight - paragraphsHeight(texts, width: textWidth, spacing: 8) + 16)
}

let commandString = NSAttributedString(string: command, attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: textColor,
])
let troubleshootingTexts = troubleshooting.map(attributed)
let troubleshootingHeading = heading(troubleshootingTitle, size: 13)
document.ensureSpace(12 + height(of: troubleshootingHeading, width: contentWidth) + 8 +
                     paragraphsHeight(troubleshootingTexts, width: contentWidth, spacing: 6) + 40)
document.separator()
document.text(troubleshootingHeading, after: 8)
document.paragraphs(troubleshootingTexts, x: margin, width: contentWidth, spacing: 6)
document.advance(10)
document.text(commandString, x: margin + 22, width: contentWidth - 22)
document.close()
print("Created \(output.path)")
