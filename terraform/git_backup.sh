#!/bin/bash

# 1. Navigate to your repository root directory
cd /home/raj/localstack

# 2. Force Git to use your specific SSH private key for authentication
export GIT_SSH_COMMAND="ssh -i /home/raj/.ssh/id_ed25519 -o IdentitiesOnly=yes"

# 3. Supply the home environment path so Git can locate global configs inside Cron
export HOME=/home/raj

# 4. Safety Guardrail: Only commit and push if changes actually exist
if [[ -n $(git status --porcelain) ]]; then
    # Stage all changes within the terraform directory
    git add terraform/
    
    # Create a timestamped checkpoint commit
    git commit -m "chrono: automated checkpoint $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Push the changes to GitHub and pipe all outputs/errors to a dedicated log file
    git push origin main >> /home/raj/localstack/terraform/git_cron.log 2>&1
fi
