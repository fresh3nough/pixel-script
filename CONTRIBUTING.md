Contributing to pixel_cleanup.sh
=================================

We welcome contributions to improve the pixel_cleanup.sh script. Please follow
these guidelines to keep contributions clean and maintainable.

Code Style
----------

- Keep shell code POSIX-compatible where possible
- Use the existing logging function for all output
- Add comments explaining non-obvious logic
- Follow the existing code patterns and structure
- No emojis in code, comments, or commit messages

Adding New Features
-------------------

1. Discuss the feature idea by opening an issue first
2. Fork the repository and create a new branch from main
3. Implement the feature with full test coverage
4. Ensure all existing tests pass
5. Update TESTING.md with new test cases
6. Commit with a clear, descriptive message
7. Sign all commits with your SSH key

Commit Guidelines
-----------------

- All commits must be signed using SSH key verification
- Commit messages should be concise and descriptive
- Follow the "Always pull latest from main before starting" rule
- Never include emojis in commit messages or code
- Reference related issues in commit messages when applicable

Testing
-------

- Add test cases to TESTING.md for any new functionality
- Test on a real Google Pixel device with ADB access
- Verify exit codes and expected behavior
- Ensure no data loss occurs outside intended targets
- Review the Security Notes section in the script README

Pull Request Process
--------------------

1. Ensure your branch is up-to-date with main (git pull)
2. Run all existing tests to verify no regressions
3. Ensure code follows the style guidelines above
4. Sign your commits
5. Open a Pull Request with a clear description
6. Maintainer will review and merge upon approval

License
-------

See the script's included terms. All contributions follow the same licensing terms.