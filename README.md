# Claude Code Tools

Manage your Claude Code sessions asynchronously via SMS, with automatic session resumption when rate limits reset.

## Why Use Claude Code Tools?

Stay connected to Claude Code when you're away from your computer—whether you're out running errands, enjoying a coffee, taking a walk with family, or having lunch. No need to track rate limit expiration manually—the tools automatically handle session resumption for you when rate limits reset.

## What You Get

### Smart SMS Notifications
- Instant notification via SMS when Claude finishes tasks or needs your input
- View real-time screenshots of the Claude Code terminal for full visibility (configurable by you)

### Intelligent Auto-Resume
- Automatically detects when Claude hits a rate limit
- Seamlessly resumes the Claude session as soon as the limit resets
- No need to track or manually resume your session. It's handled for you.

### Free & Secure & Private
- All through your native Messages app on MacOS. No third-party services involved.
- Only commands from authorized sender are accepted.
- Everything operates locally on your machine for maximum privacy.

### Remote Control vis SMS
- Send prompts to Claude Code from anywhere via Messages app on any Apple device
- Check Claude’s current status anytime by texting `cc status`. It will text a live screenshot of the Claude Code terminal window directly back to your phone via SMS

## Quick Start

### Prerequisites & Dependencies

- **macOS** with Messages app signed in to your Apple ID
- **iPhone** set up Messages app on your MacOS to send and receive messages.
- **Terminal App (Terminal, iTerm, or Iterm2) Permissions**:
  - Full Disk Access (to read Messages database for new messages): `System Settings → Privacy & Security → Screen Recording`
  - Accessibility (for sending the screenshots): `System Settings → Privacy & Security → Accessibility`
  - Screen Recording (for taking the screenshot):  `System Settings → Privacy & Security → Screen Recording`
- **jq** command-line tool: `brew install jq`

### Initial Setup
```bash
git clone https://github.com/cyzhao/claude-code-tools.git
cd claude-code-tools
./setup.sh
```

The setup wizard will guide you through:
- Entering your phone number and authorized contacts
- Enabling or disabling auto-resume
- Choosing whether to enable screenshots
- Setting how often to check for new SMS messages
- Configuring the auto-resume interval

### Configure Claude Code Hooks in Your Project
```bash
# Set the tools directory, add it to .bashrc or equivilent of your shell
export CC_TOOLS_DIR="/path/to/claude-code-tools"

# Go to your Claude Code project and add hooks
cd /your/claude-code-project
cp $CC_TOOLS_DIR/.claude/settings.json .claude/settings.json
```

### Start All Features
```bash
./start.sh
```

This command starts the background daemons to enable SMS notifications, SMS commands, and auto-resume features. You'll want to run it whenever you need the tools active. By default, they're disabled to prevent unnecessary distractions while you're working on your Mac. Personally, I start it only when I need to step away from my computer for a while, and stop it once I'm back and actively working.

This command also asks you select the Claude terminal window, make sure that you choose the right one that you would like to control with SMS remotely.

**NOTE**: You need to start this in the Terminal app (Terminal, iTerm, or iTerm2) that you configured with proper permissions from above.

**Stop all features:**
```bash
./stop.sh
```

### Start Using Claude Code Normally
That's it! Your Claude Code sessions will now:
- Send you SMS notifications when tasks finish
- Notify you immediately if your input is required
- Send terminal screenshots via SMS if the feature is enabled by you
- Automatically resume after rate limit expires

### Send Prompts/Commands via SMS
You can also control Claude remotely by sending commands using the cc prefix. - For example:
- `cc status` – requests a screenshot of the Claude session to be sent to you via SMS
- `cc <your prompt>` – sends a new prompt to Claude to start the next task

The 'cc' (case insensitive) prefix helps distinguish your commands to Claude from regular text messages.

**NOTE:** Ensure Claude Code is either Normal editing mode, or INSERT MODE when it is in Vim editing mode. Command can't be accepted now by Claude Code when it is NORMAL MODE in  Vim editing mode.

## Common Usage Examples

### Scenario 1: Long-Running Task
You start a complex and long running refactoring task and step away. When Claude finishes or requires your input, you get an SMS with a screenshot showing the current state. When Claude requires input, you will be notified and can respond via text message prefixed with 'cc'. See above for details.

### Scenario 2: Rate Limit Hit
Claude hits the usage limit. Instead of manually checking back later when limit expires, you get an SMS notification and the system automatically resumes when limits reset. This is especially valuable when rate limits reset during times you're unavailable—like overnight, during meetings, or while commuting—preventing hours or even days of delay that would otherwise occur if you had to manually resume the session.

### Scenario 3: Remote Monitoring
You're away from your computer but want to check on a Claude session. Text 'cc status' to get a current screenshot of the Claude terminal

### Scenario 4: Quick Response
Claude asks a question requiring your input. You get the SMS notification and can quickly respond with `cc <your response>`.

### Scenario 5: Work with Claude Remotely
You're away from your computer and come up with an idea for a new feature or task. Instead of waiting until you're back at your desk, simply text `cc <your idea>` to start Claude working on it immediately. For example: `cc Add dark mode toggle to the settings page` or `cc Refactor the user authentication system to use JWT tokens`.

## Configuration

The system uses a simple JSON configuration file that the setup wizard creates (`$CC_TOOLS_DIR/config/config.json`):

```json
{
  "user_phone": "+1234567890",
  "contacts": ["+1234567890"], 
  "sms_enabled": true,
  "auto_resume": true,
  "screenshot_enabled": false,
  "max_message_length": 160
}
```

**Reconfigure anytime:**
```bash
./setup.sh --reconfigure
```



## Testing Your Setup

**Test everything:**
```bash
./sms/test-sms.sh
```

**Test specific components:**
```bash
./sms/test-sms.sh --basic        # Configuration tests
./sms/test-sms.sh --integration  # Send test SMS
./setup.sh --test-config         # Validate settings
```

## Troubleshooting

### Not receiving notifications via SMS
1. Verify Messages app is signed in: `Open Messages → Preferences → iMessage`
2. Check contacts exist in Messages app
3. Verify configuration: `./setup.sh --test-config`

### Not sending screenshot
1. Grant Screen Recording permission: `System Settings → Privacy & Security → Screen Recording → Add Terminal app (Terminal or iTerm or iTerm2)`
2. Grant Accessibility permission for screenshot automation: `System Settings → Privacy & Security → Accessibility → Add Terminal app  (Terminal or iTerm or iTerm2)`
3. Restart your Terminal app after granting permissions
4. Ensure your screen is not turned off while you are away. `System Settings → Lock Screen -> Start Screen Saver When inactive -> Never`,  `System Settings → Lock Screen -> Turn display off on power adapter when inactive -> Never`. You can adjust the brightness of the screen to dark.

### Command sent via 'cc <command>' not received by Claude Code
1. Ensure sender is in `contacts` list in `config/config.json`
2. Check SMS receiver daemon is running: `ps aux | grep sms-receiver`
3. Start daemon: `./start.sh` if it is not running

### Session is not auto-resumed after limit resets
1. Ensure `auto_resume` is set to true in `config/config.json`
2. Check `resume_check_interval` is set to a proper value.
3. Ensure Claude Code is either Normal editing mode, or INSERT MODE when it is in Vim editing mode. Command can't be accepted now by Claude Code when it is NORMAL MODE in  Vim editing mode.
4. Check rate limit monitor daemon is running: `ps aux | grep rate-limit-monitor.sh`
5. Start daemon: `./start.sh` if it is not running

### How to turn on debug mode
```bash
./start.sh --debug
```

**NOTE:** This has only been thoroughly tested with iTerm2, as it's the terminal I personally use.
