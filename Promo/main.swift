import AppKit

// Promo renderer for Hoop, built by promo.sh from the app's own sources plus this folder.
//   hoop-promo video [out.mp4]      the captioned video (no path: simulate only and print the outcomes)
//   hoop-promo gameplay [out.mp4]   a plain gameplay recording with music, no captions
//   hoop-promo cover <out.png>      the cover image

_ = NSApplication.shared
let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case "video", "gameplay":
        let cut: Director.Cut = arguments[0] == "video" ? .funny : .gameplay
        try Director(cut: cut).render(to: arguments.count > 1 ? URL(fileURLWithPath: arguments[1]) : nil)
    case "cover" where arguments.count > 1:
        try Cover.render(to: URL(fileURLWithPath: arguments[1]))
    default:
        print("usage: hoop-promo video|gameplay [out.mp4] | cover <out.png>")
        exit(2)
    }
} catch {
    print("error: \(error)")
    exit(1)
}
