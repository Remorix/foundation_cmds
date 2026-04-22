# foundation_cmds
Function-to-function identical implementation of missing `pl`, `plutil` and `defaults` for non-macOS.

### Current Status

Aligned with Foundation-1940 (Darwin 22).
Minimal target has not been tested yet, but should at least supporting Darwin 19 (macOS 10.14 / iOS 13), backports welcomed.

### TODO

- [x] `pl`
- [x] `plutil`
- [x] `defaults`
- [ ] Foundation-less port or GNUstep port for non-Darwin systems

### `/usr/libexec/PlistBuddy`?

See [PlistBuddy](https://github.com/Remorix/PlistBuddy)
