import Cocoa

let args = CommandLine.arguments
guard args.count >= 3, ["on", "off"].contains(args[2]) else {
    print("usage: ax-enable <pid|app-name> on|off")
    exit(2)
}
let want = args[2] == "on"
var pid: pid_t? = nil
if let p = Int32(args[1]) {
    pid = p
} else {
    for app in NSWorkspace.shared.runningApplications where app.localizedName == args[1] {
        pid = app.processIdentifier
        break
    }
}
guard let target = pid else {
    print("app no encontrada: \(args[1])")
    exit(1)
}
let app = AXUIElementCreateApplication(target)
for attr in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
    let err = AXUIElementSetAttributeValue(app, attr as CFString, (want ? kCFBooleanTrue : kCFBooleanFalse))
    print("\(attr)=\(want ? 1 : 0) err=\(err.rawValue)")
}
