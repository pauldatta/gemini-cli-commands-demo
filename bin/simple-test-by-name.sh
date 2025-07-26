#!/bin/bash
# bin/simple-test-by-name.sh

# This is the simplest possible test for the -e flag using the extension name.

echo "--- Running Test with -e flag and extension name ---"
npx https://github.com/google-gemini/gemini-cli -e "tdd-agent" -p "Hello, who are you?"
echo "--- Test Finished ---"
