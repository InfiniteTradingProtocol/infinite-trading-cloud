#!/bin/bash

# List of specific files to add
#!/bin/bash

# Adding individual files

sudo git add dashboard.R
sudo git add gateway.R
sudo git add github.sh

# Adding entire folders
sudo git add endpoints

# Check if a commit message is provided
if [ -z "$1" ]; then
    commit_message="Latest updates"
else
    commit_message="$1"
fi

# Commit the changes with a message
sudo git commit -m "$commit_message"

#git remote add origin https://github.com/InfiniteTradingProtocol/infinite-trading-api-gateway.git

#git branch -M main

# Push to the main branch

sudo git push origin main
