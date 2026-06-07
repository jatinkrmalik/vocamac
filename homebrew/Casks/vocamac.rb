cask "vocamac" do
  version "0.6.2"

  url "https://github.com/jatinkrmalik/vocamac/releases/download/v#{version}/VocaMac-#{version}-arm64.dmg",
      verified: "github.com/jatinkrmalik/vocamac"
  name "VocaMac"
  desc "Local voice-to-text dictation for macOS, powered by WhisperKit"
  homepage "https://vocamac.com"

  sha256 "9de43a316ac885deb7b84ead8fe292d16432cce9968d53941c855cc8ff3bed28"

  livecheck do
    url :url
    strategy :github_latest
  end

  license "AGPL-3.0-only"

  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  conflicts_with cask: "vocamac-nightly"

  app "VocaMac.app"

  zap trash: [
    "~/Library/Application Support/VocaMac",
    "~/Library/Caches/com.vocamac.app",
    "~/Library/Preferences/com.vocamac.app.plist",
    "~/Library/Saved Application State/com.vocamac.app.savedState",
  ]
end
