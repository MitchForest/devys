// BundleExtension.swift
// Syntax - bundle lookup helpers
//
// Provides access to the module bundle for resource loading.

import Foundation

extension Bundle {
    /// The module bundle for DevysSyntax resources
    static var moduleBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: BundleToken.self)
        #endif
    }

}

#if !SWIFT_PACKAGE
private class BundleToken {}
#endif
