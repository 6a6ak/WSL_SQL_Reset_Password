# MySQL Root Password Reset in WSL

## Overview
This project provides a simple script (`force-root-pass.sh`) to reset the MySQL root password in a WSL (Windows Subsystem for Linux) environment.

## Why Reset the MySQL Root Password?
- **Default Password Complexity:** MySQL often generates a long and complex root password by default for security reasons. While this is good for production, it can be hard to remember, especially in a development or sandbox environment like WSL.
- **Forgotten Passwords:** It's common to forget the default or previously set root password, especially if you haven't used MySQL for a while or are just experimenting.

## Why is it Safe to Reset in WSL?
- **WSL is a Sandbox:** WSL is typically used for development and testing. Resetting the root password here does not affect any production systems or sensitive data.
- **No Security Risk:** Since WSL is isolated from your main system and usually not exposed to the internet, resetting the password is safe and convenient.

## How to Use
1. Open your WSL terminal.
2. Navigate to the directory containing `force-root-pass.sh`.
3. Run the script:
   ```sh
   sudo bash force-root-pass.sh
   ```
4. Follow the prompts to set a new MySQL root password.

## Notes
- This script is intended for use in WSL or other non-production environments.
- Always use strong passwords in production systems.

## License
MIT License
