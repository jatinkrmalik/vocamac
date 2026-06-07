cask "vocamac" do
  version "0.6.2"

  url "https://github.com/jatinkrmalik/vocamac/releases/download/v#{version}/VocaMac-#{version}-arm64.dmg",
      verified: "github.com/jatinkrmalik/vocamac"
  name "VocaMac"
  desc "Local voice-to-text dictation for macOS, powered by WhisperKit"
  homepage "https://vocamac.com"

  # :no_check is used here because the sha256 will be injected by the
  # automated cask update workflow when a new release is published.
  sha256 :no_check

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
