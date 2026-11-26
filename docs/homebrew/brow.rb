# DRAFT of Casks/brow.rb for the tap renodesper/homebrew-brow. It cannot be installed yet: there is no release to
# download. See "Homebrew" in docs/RELEASING.md for what has to exist first and for how to try it.
cask "brow" do
  version "1.0.0"
  sha256 "REPLACE_WITH_THE_SHA256_OF_THE_DMG"

  url "https://github.com/renodesper/brow/releases/download/v#{version}/Brow-#{version}.dmg"
  name "Brow"
  desc "Pomodoro, Keep Awake, AI usage and calendar in the MacBook notch"
  homepage "https://github.com/renodesper/brow"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Brow.app"

  # It has no Dock icon, so it is quit by its bundle id before the app is removed.
  uninstall quit: "dev.bosan.Brow"

  zap trash: "~/Library/Preferences/dev.bosan.Brow.plist"
end
