import AppKit

// Promo renderer for Hoop, built by promo.sh from the app's own sources plus this folder.
//   hoop-promo video [out.mp4]      the captioned video (no path: simulate only and print the outcomes)
//   hoop-promo gameplay [out.mp4]   a plain gameplay recording with music, no captions
//   hoop-promo features [out.mp4]   the same style, showing streaks, backboard, folder hoop, Shot Clock
//   hoop-promo cover <out.png>      the cover image

_ = NSApplication.shared
let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case "video", "gameplay", "features":
        let cut: Director.Cut = switch arguments[0] {
        case "video": .funny
        case "gameplay": .gameplay
        default: .features
        }
        try Director(cut: cut).render(to: arguments.count > 1 ? URL(fileURLWithPath: arguments[1]) : nil)
    case "cover" where arguments.count > 1:
        try Cover.render(to: URL(fileURLWithPath: arguments[1]))
    default:
        print("usage: hoop-promo video|gameplay|features [out.mp4] | cover <out.png>")
        exit(2)
    }
} catch {
    print("error: \(error)")
    exit(1)
}
