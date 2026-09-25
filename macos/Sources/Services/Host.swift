/// Architecture names for this Mac, in the spellings each download source uses.
enum Host {
    #if arch(arm64)
    static let systemImageABI = "arm64-v8a"
    static let sdkRepositoryArch = "aarch64"
    static let adoptiumArch = "aarch64"
    #else
    static let systemImageABI = "x86_64"
    static let sdkRepositoryArch = "x64"
    static let adoptiumArch = "x64"
    #endif
}
