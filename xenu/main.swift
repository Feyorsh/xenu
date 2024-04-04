import Foundation
import Virtualization

// MARK: Parse the Command Line

guard CommandLine.argc == 4 else {
    printUsageAndExit()
}

let kernelURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: false)
let initialRamdiskURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: false)
// let isoURL = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: false)
// let initURL = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: false)
let storeURL = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: false)

// MARK: Create the Virtual Machine Configuration

let configuration = VZVirtualMachineConfiguration()
configuration.cpuCount = 1
configuration.memorySize = 1024 * 1024 * 1024 // 1 GiB
configuration.serialPorts = [ createConsoleConfiguration() ]
configuration.bootLoader = createBootLoader(kernelURL: kernelURL, initialRamdiskURL: initialRamdiskURL)
configuration.entropyDevices = [ VZVirtioEntropyDeviceConfiguration() ]
configuration.memoryBalloonDevices = [ VZVirtioTraditionalMemoryBalloonDeviceConfiguration() ]

configuration.storageDevices = [
	// VZVirtioBlockDeviceConfiguration(attachment: try! VZDiskImageStorageDeviceAttachment(url: isoURL, readOnly: false)),
	VZVirtioBlockDeviceConfiguration(attachment: try! VZDiskImageStorageDeviceAttachment(url: storeURL, readOnly: false))
]
configuration.directorySharingDevices = [
    // VZVirtioFileSystemDeviceConfiguration(tag: "nix-store", share: VZSingleDirectoryShare(directory: VZSharedDirectory(url: URL(fileURLWithPath: "/nix/store"), readOnly: true)))
	createSharedDirectory(filePath: URL(fileURLWithPath: "/nix/store"), tag: "nix-store", readOnly: true),
    createSharedDirectory(filePath: URL(fileURLWithPath: "/Users/ghuebner/Downloads/xenu"), tag: "shared", readOnly: false),
    createSharedDirectory(filePath: URL(fileURLWithPath: "/Users/ghuebner/Downloads/xenu/tmpdir"), tag: "xchg", readOnly: false),
    mountRosetta()
]
let net_dev = VZVirtioNetworkDeviceConfiguration()
net_dev.attachment = VZNATNetworkDeviceAttachment()
configuration.networkDevices = [ net_dev ]

do {
    try configuration.validate()
} catch {
    print("Failed to validate the virtual machine configuration. \(error)")
    exit(EXIT_FAILURE)
}

// MARK: Instantiate and Start the Virtual Machine

let virtualMachine = VZVirtualMachine(configuration: configuration)

let delegate = Delegate()
virtualMachine.delegate = delegate

virtualMachine.start { (result) in
    if case let .failure(error) = result {
        print("Failed to start the virtual machine. \(error)")
        exit(EXIT_FAILURE)
    }
}

RunLoop.main.run(until: Date.distantFuture)

// MARK: - Virtual Machine Delegate

class Delegate: NSObject {
}

extension Delegate: VZVirtualMachineDelegate {
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print("The guest shut down. Exiting.")
        exit(EXIT_SUCCESS)
    }
}

// MARK: - Helper Functions

/// Creates a Linux bootloader with the given kernel and initial ramdisk.
func createBootLoader(kernelURL: URL, initialRamdiskURL: URL) -> VZBootLoader {
    let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
    bootLoader.initialRamdiskURL = initialRamdiskURL

    let kernelCommandLineArguments = [
        // Use the first virtio console device as system console.
        "console=hvc0",
        // Stop in the initial ramdisk before attempting to transition to the root file system.
        "rd.break=initqueue",

        // "$(cat /nix/store/0kih1j1kwjcjlk45dinhsr02pvwlcdbf-nixos-system-nixos-24.05.20240210.10b8130/kernel-params)"
        "loglevel=4", "net.ifnames=0",
        "boot.shell_on_fail",
		"init=/nix/store/lsgdswc9q1c98w3rn0zhs5cg9v29qrka-nixos-system-nixos-24.05.20240330.eaa66d2/init",

		"regInfo=/nix/store/c0wmwqnr6250vyfpnadv9wwa0yzp3hx5-closure-info/registration" //console=tty0 console=ttyAMA0,115200n8 $QEMU_KERNEL_PARAMS"
    ]

    bootLoader.commandLine = kernelCommandLineArguments.joined(separator: " ")

    return bootLoader
}

/// Creates a serial configuration object for a virtio console device,
/// and attaches it to stdin and stdout.
func createConsoleConfiguration() -> VZSerialPortConfiguration {
    let consoleConfiguration = VZVirtioConsoleDeviceSerialPortConfiguration()

    let inputFileHandle = FileHandle.standardInput
    let outputFileHandle = FileHandle.standardOutput

    // Put stdin into raw mode, disabling local echo, input canonicalization,
    // and CR-NL mapping.
    var attributes = termios()
    tcgetattr(inputFileHandle.fileDescriptor, &attributes)
    attributes.c_iflag &= ~tcflag_t(ICRNL)
    attributes.c_lflag &= ~tcflag_t(ICANON | ECHO)
    tcsetattr(inputFileHandle.fileDescriptor, TCSANOW, &attributes)

    let stdioAttachment = VZFileHandleSerialPortAttachment(fileHandleForReading: inputFileHandle,
                                                           fileHandleForWriting: outputFileHandle)

    consoleConfiguration.attachment = stdioAttachment

    return consoleConfiguration
}

func createSharedDirectory(filePath: URL, tag: String, readOnly: Bool) -> VZVirtioFileSystemDeviceConfiguration {
    let fsConf = VZVirtioFileSystemDeviceConfiguration(tag: tag)
	fsConf.share = VZSingleDirectoryShare(directory: VZSharedDirectory(url: filePath, readOnly: readOnly))

    return fsConf
}

func mountRosetta() -> VZVirtioFileSystemDeviceConfiguration {
    let rosettaDirectoryShare = try! VZLinuxRosettaDirectoryShare()
    let fsConf = VZVirtioFileSystemDeviceConfiguration(tag: "rosetta")
    fsConf.share = rosettaDirectoryShare

    return fsConf
}

func printUsageAndExit() -> Never {
    print(CommandLine.argc)
    print("Usage: \(CommandLine.arguments[0]) <kernel-path> <initial-ramdisk-path> <stage2-init-path> <fs-img-path>")
    exit(EX_USAGE)
}
