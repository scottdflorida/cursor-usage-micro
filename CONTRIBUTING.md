# Contributing

Thanks for helping improve Cursor Usage Micro. Bug reports, small fixes, tests, and focused feature ideas are welcome.

## Before opening an issue

- Search the existing issues first.
- Use the issue forms when one fits.
- Remove account details, credentials, tokens, and raw provider responses from logs and screenshots.
- Report security problems privately through [GitHub Security Advisories](https://github.com/scottdflorida/cursor-usage-micro/security/advisories/new).

## Making a change

1. Read the setup instructions in the README.
2. Keep the change focused and include deterministic tests where practical.
3. Run `./test.sh`.
4. Run `./build.sh` when the change affects the app or packaging.
5. Update documentation when behavior changes.

Please do not commit build output, credentials, or captured usage data. Pull requests should explain the problem, the approach, and how the change was verified.
