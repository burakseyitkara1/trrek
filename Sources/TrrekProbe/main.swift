import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    printUsage()
    exit(0)
}

let options = Array(arguments.dropFirst())

switch command {
case "devices":
    runDevices()
case "frames":
    runFrames(options)
case "layout-check":
    runLayoutCheck()
case "haptic":
    runHaptic(options)
case "key":
    runKey(options)
case "switcher":
    runSwitcher()
case "freeze":
    runFreeze(options)
case "mem":
    runMem()
case "pipeline":
    runPipeline(options)
case "backlight":
    runBacklight(options)
case "keys":
    runKeys(options)
case "ddc":
    runDDC(options)
case "help", "-h", "--help":
    printUsage()
default:
    output("unknown command: \(command)")
    printUsage()
    exit(64)
}
