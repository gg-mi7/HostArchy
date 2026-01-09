# Contributing to HostArchy

Thank you for your interest in contributing to HostArchy!

## Development Setup

HostArchy is a bash-based system layer for Arch Linux. To contribute:

1. Clone the repository:
```bash
git clone https://github.com/hostarchy/hostarchy.git
cd hostarchy
```

2. Make your changes

3. Test on an Arch Linux system (or VM)

4. Submit a pull request

## Code Style

- Use bash best practices
- Follow the existing code style
- Add comments for complex logic
- Use the common logging functions from `lib/common.sh`

## Testing

Test your changes on a clean Arch Linux installation before submitting.

## Project Structure

- `install.sh` - Main installation script
- `bin/hostarchy` - CLI tool
- `lib/` - Library scripts (common.sh, system-tuning.sh, service-config.sh)
- `profiles/` - Profile definitions (hosting.sh, performance.sh, database.sh)
- `templates/` - Configuration templates
- `pacman-hooks/` - Pacman hooks for automatic re-application

