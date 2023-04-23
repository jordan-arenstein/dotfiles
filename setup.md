# Clone this repository into ~
```
> git init
> git remote add origin https://github.com/jordan-arenstein/dotfiles
> git fetch
> git checkout -t origin/main
```

# Install [Homebrew](brew.sh)
```
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
> (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> .zprofile
> eval "$(/opt/homebrew/bin/brew shellenv)"
```

# Install [iTerm2](iterm2.com)
```
> brew install iterm2
iTerm2 > Make iTerm2 Default Term
iTerm2 > Install Shell Integration
> brew tap homebrew/cask-fonts 
> brew install font-iosevka-nerd-font font-jetbrains-mono-nerd-font font-inconsolata-nerd-font
```

# Install [Neovim](neovim.io)
```
> brew install neovim --HEAD
> nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
```

# Install LaTeX
```
> brew install mactex-no-gui tex-live-utility
```

# Install Transmission
```
> brew install transmission
```

# Install VLC
```
> brew install vlc
```

# Install [Calibre](calibre-ebook.com)
```
> brew install calibre
```

# Install BetterTouchTool
```
brew install bettertouchtool
```

# Install FileBot
```
> brew install filebot
```

# Install [Bitwarden](https://apps.apple.com/za/app/bitwarden/id1352778147)
