class SkillSet < Formula
  desc "Switch filesystem skill sets across AI coding agents"
  homepage "https://github.com/kreek/skill-set"
  url "https://github.com/kreek/skill-set.git", tag: "v0.1.0"
  license "MIT"
  head "https://github.com/kreek/skill-set.git", branch: "main"


  def install
    bin.install "bin/skill-set"
    bin.install_symlink "skill-set" => "sklset"
    bash_completion.install "completions/skill-set.bash" => "skill-set"
    zsh_completion.install "completions/_skill-set"
  end

  test do
    assert_match "Usage: skill-set", shell_output("#{bin}/skill-set --help")
    assert_match "Usage: skill-set", shell_output("#{bin}/sklset --help")
  end
end
