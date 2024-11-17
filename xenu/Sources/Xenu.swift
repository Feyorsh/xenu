import ArgumentParser
import Foundation
import Virtualization


/////////////
// OPTIONS //
/////////////


struct XenuOptions: ParsableArguments {
    @Option(help: "Path to kernel", completion: .file(), transform: URL.init(fileURLWithPath:))
    var kernel: URL

    @Option(help: "Path to initrd", transform: URL.init(fileURLWithPath:))
    var initrd: URL

    @Option(name: [.long, .customLong("append")], help: "")
    var cmdline: String = ""

    @Option(name: [.long, .customLong("smp")], help: "Number of vCPU cores to expose to the guest.")
    var cpuCount: Int = 1

    @Option(name: [.long, .customShort("m")], help: "Physical memory available to the guest OS (in bytes)")
    var memory: UInt64 = 1024 * 1024 * 1024

    // virtio devices
    @Flag
    var keyboard: Keyboard?
    @Flag
    var pointer: PointingDevice?

    @Flag(inversion: .prefixedEnableDisable)
    var virtioSound: Bool = false // requires 

    @Flag(inversion: .prefixedNo)
    var display: Bool = false

    @Flag(inversion: .prefixedEnableDisable)
    var memoryBalloon: Bool = true // the real trick is verifying `targetVirtualMachineMemorySize` at runtime

    // TODO networking. Basically:
    // can use bridged interface from host (have to iterate over available protocols),
    // file,
    // or VZNat (default).
    // can also specify Mac address

    @Flag(inversion: .prefixedEnableDisable)
    var entropyDevice: Bool = true // VZVirtioEntropyDeviceConfiguration

    // TODO serial, can write to a file. Shouldn't just be a bool
    // @Flag(inversion: .prefixedEnableDisable)
    // var virtioSerial: Bool = true

    // TODO split up legacy virtfs option compatibility from future version
    // @Option(transform: {
    //             let arr = $0.components(separatedBy: ",")
    //             if arr.count == 2 {
    //                 return (arr[0], URL.init(fileURLWithPath: arr[1]), true)
    //             } else if 4 <= arr.count && arr.count <= 11 {
    //                 // check for _,path=PATH,mount_tag=TAG,_,...,readonly,...

    //             }
    //             throw ValidationError("Unrecognized shared directory config \($0)")
    //         }, name: .customLong("virtfs", withSingleDash: true), parsing: .unconditionalSingleValue)
    // var sharedDirectories: [(String, URL, Bool)]

    // @Option(name: .customLong("spice", withSingleDash: true), transform: {$0 != "disable-copy-paste"})
    // var spiceClipboard: Bool?


    // flags differing from QEMU
    @Flag(inversion: .prefixedNo, help: "Enable Linux Rosetta in guest VM.")
    var rosetta: Bool = true

    @Option(help: "The Virtiofs mount tag for Rosetta.")
    var rosettaTag: String = "rosetta"

    @Flag(inversion: .prefixedEnableDisable, help: "Expose CWD to the guest as a Virtiofs shared directory.")
    var shareCwd: Bool = true

    // TODO would like overlays to work, please
    // should be optional soon
    @Option(help: "Path to Nix store image", transform: URL.init(fileURLWithPath:))
    var storeImage: URL


    // TODO idk
    mutating func validate() throws { }

    func makeConfig() throws -> VZVirtualMachineConfiguration {
        // TODO check all URLs to be valid
        // guard FileManager.default.fileExists(atPath: pathToFile.path) else {
        //     throw ValidationError("\(pathToFile.path) does not exist")
        // }
        let cwd: String = FileManager.default.currentDirectoryPath

        let configuration = VZVirtualMachineConfiguration()
        configuration.cpuCount = cpuCount
        configuration.memorySize = memory
        configuration.serialPorts = [ XenuOptions.createConsoleConfiguration() ] // TODO
        configuration.bootLoader = XenuOptions.createBootLoader(kernelURL: kernel, initialRamdiskURL: initrd, kernelParams: cmdline.components(separatedBy: " "))
        configuration.entropyDevices = [ VZVirtioEntropyDeviceConfiguration() ] // TODO
        configuration.memoryBalloonDevices = [ VZVirtioTraditionalMemoryBalloonDeviceConfiguration() ] // TODO
        configuration.storageDevices = [
	      try XenuOptions.createBlockDevice(filePath: storeImage)
        ]
        configuration.directorySharingDevices = [
	      XenuOptions.createSharedDirectory(filePath: URL(fileURLWithPath: "/nix/store"), tag: "nix-store", readOnly: true),
          XenuOptions.mountRosetta(tag: rosettaTag)
        ] + (shareCwd ? [ XenuOptions.createSharedDirectory(filePath: URL(fileURLWithPath: cwd), tag: "shared", readOnly: false) ] : [])

        let net_dev = VZVirtioNetworkDeviceConfiguration()
        net_dev.attachment = VZNATNetworkDeviceAttachment()
        configuration.networkDevices = [ net_dev ]

        try configuration.validate()
        return configuration
    }

    // Helper functions

    static func mountRosetta(tag: String) -> VZVirtioFileSystemDeviceConfiguration {
        let rosettaDirectoryShare = try! VZLinuxRosettaDirectoryShare()
        let fsConf = VZVirtioFileSystemDeviceConfiguration(tag: tag)
        fsConf.share = rosettaDirectoryShare

        return fsConf
    }

    static func createConsoleConfiguration() -> VZSerialPortConfiguration {
        let consoleConfiguration = VZVirtioConsoleDeviceSerialPortConfiguration()

        let inputFileHandle = FileHandle.standardInput
        let outputFileHandle = FileHandle.standardOutput

        // Put stdin into raw mode, disabling local echo, input canonicalization,
        // interrupts, and CR-NL mapping.
        var attributes = termios()
        tcgetattr(inputFileHandle.fileDescriptor, &attributes)
        attributes.c_iflag &= ~tcflag_t(ICRNL)
        attributes.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
        tcsetattr(inputFileHandle.fileDescriptor, TCSANOW, &attributes)

        let stdioAttachment = VZFileHandleSerialPortAttachment(fileHandleForReading: inputFileHandle,
                                                               fileHandleForWriting: outputFileHandle)

        consoleConfiguration.attachment = stdioAttachment

        return consoleConfiguration
    }

    // subsequent parameters override these
    static let defaultKernelParams = [
      // Use the first virtio console device as system console.
      "console=hvc0",
      // Stop in the initial ramdisk before attempting to transition to the root file system.
      "rd.break=initqueue",
    ]

    static func createBootLoader(kernelURL: URL, initialRamdiskURL: URL, kernelParams: [String] = []) -> VZBootLoader {
        let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
        bootLoader.initialRamdiskURL = initialRamdiskURL
        bootLoader.commandLine = (defaultKernelParams + kernelParams).joined(separator: " ")
        return bootLoader
    }

    // TODO make a `createBlockDevice` method
    static func createSharedDirectory(filePath: URL, tag: String, readOnly: Bool) -> VZVirtioFileSystemDeviceConfiguration {
        let fsConf = VZVirtioFileSystemDeviceConfiguration(tag: tag)
	    fsConf.share = VZSingleDirectoryShare(directory: VZSharedDirectory(url: filePath, readOnly: readOnly))
        return fsConf
    }

    static func createBlockDevice(filePath: URL, _ readOnly: Bool = false) throws -> VZStorageDeviceConfiguration {
	      return VZVirtioBlockDeviceConfiguration(attachment: try VZDiskImageStorageDeviceAttachment(url: filePath, readOnly: readOnly, cachingMode: .cached, synchronizationMode: .full))
    }

    static func createAudio() -> VZVirtioSoundDeviceConfiguration {
        let dev = VZVirtioSoundDeviceConfiguration()
        let input = VZVirtioSoundDeviceInputStreamConfiguration()
        input.source = VZHostAudioInputStreamSource()
        let out = VZVirtioSoundDeviceOutputStreamConfiguration()
        out.sink = VZHostAudioOutputStreamSink()
        dev.streams = [ input, out ]

        return dev
    }

    static func createDisplay(isMac: Bool = false) -> VZGraphicsDeviceConfiguration {
        if isMac {
            func getScreenWithMouse() -> NSScreen? {
                let mouseLocation = NSEvent.mouseLocation
                let screens = NSScreen.screens
                let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) })

                return screenWithMouse
            }

            let dev = VZMacGraphicsDeviceConfiguration()
            let config = VZMacGraphicsDisplayConfiguration(widthInPixels: 1080, heightInPixels: 900, pixelsPerInch: 5)
            dev.displays = [ config ]
            return dev
        } else {
            let dev = VZVirtioGraphicsDeviceConfiguration()
            dev.scanouts = [ VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1080, heightInPixels: 900) ]
            return dev
        }
    }

    // Enums

    // only relevant for GUI
    enum Keyboard: EnumerableFlag {
        case macKeyboard
        case usbKeyboard
    }
    // only relevant for GUI
    enum PointingDevice: EnumerableFlag {
        case macTrackpad
        case usbPointingDevice
    }
}

struct GlobalOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "UNIMPLEMENTED Verbosity.") // maybe an int instead for levels?
    var verbose: Bool = false

    @Option(help: "Port number of target Xenu VM.")
    var port: Int = 6969 // it ain't no acmsoda... but thanks, daniel simms!
}


//////////////
// COMMANDS //
//////////////


@main
struct Xenu: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "xenu is a QEMU-like interface to the Apple Virtualization framework.",
      subcommands: [Launch.self, Monitor.self, Exec.self],
      defaultSubcommand: Launch.self
    )
}

extension Xenu {
    struct Launch: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create and run a VM.")

        @OptionGroup
        var options: GlobalOptions

        @OptionGroup
        var vmOptions: XenuOptions

        mutating func run() throws {
            let virtualMachine = try VZVirtualMachine(configuration: vmOptions.makeConfig())

            let delegate = Delegate()
            virtualMachine.delegate = delegate

            virtualMachine.start { (result) in
                if case let .failure(error) = result {
                    print("Failed to start the virtual machine. \(error)")
                    Foundation.exit(EXIT_FAILURE)
                }
            }

            RunLoop.main.run(until: Date.distantFuture)
        }
    }
}

extension Xenu {
    struct Monitor: ParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Send commands to Xenu using a QEMU monitor-like interface.",
          discussion: "This is a legacy interface that tries to provide a similar UX to that of QEMU."
        )

        mutating func run() { }
    }

    struct Exec: ParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Execute a command on a guest VM."
        )

        mutating func run() { }
    }
}


// TODO this is only here cause idk what it does
struct RuntimeError: Error, CustomStringConvertible {
    var description: String
    
    init(_ description: String) {
        self.description = description
    }
}

class Delegate: NSObject {
}

extension Delegate: VZVirtualMachineDelegate {
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print("The guest shut down. Exiting.")
        exit(EXIT_SUCCESS)
    }
}
