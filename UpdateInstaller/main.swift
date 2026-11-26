import Foundation

// The update installer service: see UpdateInstaller.swift.
let delegate = UpdateInstallerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
