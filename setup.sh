#!/bin/zsh
# VAULT setup and weekly rebuild for the Mac app.
#
#   ./setup.sh            first time: asks for your team and name, builds, installs, opens
#   ./setup.sh            later: rebuilds and reinstalls (free Apple IDs expire builds every 7 days)
#   ./setup.sh --reset    forget the saved team and name and ask again
#
# Needs: Xcode (App Store, free), signed in with your Apple ID under Xcode > Settings > Accounts.
# Homebrew and XcodeGen are installed here if missing.
set -euo pipefail
cd "$(dirname "$0")"

LOCAL=Config/Local.xcconfig
APP_NAME=VAULT
DEST=/Applications/$APP_NAME.app

say() { print -P "%F{245}›%f $*"; }
die() { print -P "%F{red}✗%f $*" >&2; exit 1; }

[[ "${1:-}" == "--reset" ]] && rm -f "$LOCAL"

# 1. Xcode
if ! xcode-select -p >/dev/null 2>&1 || [[ ! -d "$(xcode-select -p)/../.." ]]; then
  die "Xcode is not installed. Get it from the App Store, open it once, then run this again."
fi
export DEVELOPER_DIR="$(xcode-select -p)"
[[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]] || die "xcodebuild not found under $DEVELOPER_DIR. In Xcode, Settings > Locations, pick the Command Line Tools."

# 2. XcodeGen
if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    say "Installing Homebrew (asks for your Mac password)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  fi
  say "Installing XcodeGen"
  brew install xcodegen
fi

# 3. Personal settings
if [[ ! -f "$LOCAL" ]]; then
  print ""
  print "First-time setup. Two things make this build yours."
  print ""
  # Team id from the Apple Development certificate Xcode created when you signed in.
  TEAMS=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null | python3 -c '
import sys,subprocess,re
pem=sys.stdin.read()
seen=[]
for c in ["-----BEGIN"+c for c in pem.split("-----BEGIN")[1:]]:
    r=subprocess.run(["openssl","x509","-noout","-subject"],input=c,capture_output=True,text=True).stdout
    ou=re.search(r"OU=([A-Z0-9]{10})",r); o=re.search(r"/O=([^/]+)",r)
    if ou and ou.group(1) not in [s[0] for s in seen]: seen.append((ou.group(1), o.group(1) if o else ""))
for t,n in seen: print(f"{t}\t{n}")
' || true)
  TEAM=""
  if [[ -n "$TEAMS" ]]; then
    print "Apple teams found on this Mac:"
    print "$TEAMS" | awk -F'\t' '{printf "   %s   %s\n", $1, $2}'
    FIRST=$(print "$TEAMS" | head -1 | cut -f1)
    read "TEAM?Team id to use [$FIRST]: "
    TEAM=${TEAM:-$FIRST}
  else
    print "No Apple Development certificate found."
    print "Open Xcode > Settings > Accounts, add your Apple ID, then open any project once so"
    print "Xcode creates your free Personal Team. Your Team id is shown next to the team name."
    read "TEAM?Team id (10 characters): "
  fi
  [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || die "A team id is 10 letters and digits, like AB12CD34EF."

  DEFAULT_NAME=$(whoami | tr -cd 'a-z0-9')
  read "NAME?Your short name for the app id, letters and digits only [$DEFAULT_NAME]: "
  NAME=$(print "${NAME:-$DEFAULT_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
  [[ -n "$NAME" ]] || die "Name cannot be empty."

  mkdir -p Config
  cat > "$LOCAL" <<CFG
DEVELOPMENT_TEAM = $TEAM
VAULT_BUNDLE_PREFIX = com.$NAME
CFG
  say "Saved to $LOCAL (team $TEAM, app id com.$NAME.vault). Keep these; the vault data is tied to them."
fi

# 4. Generate, build, install
say "Generating Xcode project"
xcodegen generate --quiet
say "Building (first time takes a few minutes)"
LOG=$(mktemp)
if ! xcodebuild -project Vault.xcodeproj -scheme "$APP_NAME" -configuration Debug \
     -derivedDataPath .build/DerivedData -allowProvisioningUpdates build >"$LOG" 2>&1; then
  grep -E "error:|requires a development team|No signing certificate|not registered" "$LOG" | sort -u | head -8 >&2
  print "" >&2
  print "Full log: $LOG" >&2
  die "Build failed. If it mentions signing: Xcode > Settings > Accounts, make sure your Apple ID is signed in, then run ./setup.sh --reset."
fi
BUILT=.build/DerivedData/Build/Products/Debug/$APP_NAME.app
[[ -d "$BUILT" ]] || die "Build finished but $BUILT is missing."

osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"
say "Installed $DEST"
open "$DEST"

# 5. Expiry note
PROFILE="$DEST/Contents/embedded.provisionprofile"
if [[ -f "$PROFILE" ]]; then
  EXP=$(security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null || true)
  [[ -n "$EXP" ]] && say "This build runs until ${EXP%%T*}. Run ./setup.sh again before then. Your vault and Touch ID enrolment are kept."
fi
