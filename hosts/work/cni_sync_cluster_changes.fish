#!/usr/bin/env fish

# 1. Validation: Check arguments
if test (count $argv) -lt 2
    echo "Usage: sync-cluster <hint> <target_branch_1> [target_branch_2] ..."
    echo "Example: sync-cluster mainnet 0.4.8 0.4.9 main"
    exit 1
end

# 2. Setup Variables & Location Awareness
set hint $argv[1]
set user_targets $argv[2..-1]

# Capture where we are relative to the git root (e.g., "cluster/deployment/mainnet/")
set relative_prefix (git rev-parse --show-prefix)
set repo_root (git rev-parse --show-toplevel)

# Define the files WITH their relative path
set files_to_sync "$relative_prefix"config.yaml "$relative_prefix".envrc.vars
set branches_created

# Verify files exist in the current directory before starting
if not test -f config.yaml; or not test -f .envrc.vars
    echo "Error: config.yaml or .envrc.vars not found in current directory."
    echo "You must run this script from the directory containing these files."
    exit 1
end

# Check if repo is clean
set git_status_output (git status --porcelain)
if test -n "$git_status_output"
    echo "Error: Working directory is not clean. Please commit or stash changes."
    echo "Untracked/Modified files:"
    echo $git_status_output
    exit 1
end

echo "--- Starting Sync ---"
set source_branch (git branch --show-current)
echo "Source Branch: $source_branch"
echo "Working Dir:   $relative_prefix"
echo "Syncing Files: $files_to_sync"
echo "Targets:       $user_targets"
echo "---------------------"

# Move to root so Make commands work consistently
cd $repo_root

# 3. Main Loop
for target in $user_targets
    # Format target branch name
    if string match -r '^[0-9]+\.[0-9]+\.[0-9]+$' -- $target
        set base_target "release-line-$target"
    else
        set base_target $target
    end

    set new_branch_name "nicuda/sync/$(string replace / - $base_target)_$hint"

    echo "Processing target: $base_target"
    
    # Switch to base target
    echo " > Checking out $base_target..."
    git checkout $base_target --quiet
    or begin; echo "Failed to checkout $base_target"; exit 1; end
    
    git pull --quiet
    
    # Create the sync branch
    echo " > Creating branch $new_branch_name..."
    if git show-ref --verify --quiet refs/heads/$new_branch_name
        git branch -D $new_branch_name --quiet
    end
    git checkout -b $new_branch_name --quiet

    # Sync the files to their original location (relative_prefix)
    echo " > Syncing files from $source_branch into $relative_prefix..."
    git checkout $source_branch -- $files_to_sync 2>/dev/null
    
    # Run Build Sequence
    echo " > Running build sequence..."
    
    if git submodule update --init --recursive
        and make -j8 -C splice cluster/clean
        and make -j8 -C splice cluster/build
        and make -j8 update-expected
        
        # Check for changes
        if test -n "(git status --porcelain)"
            echo " > Changes detected. Committing..."
            git add .
            git commit -m "sync cluster config for $hint from $source_branch" --quiet
            set -a branches_created $new_branch_name
        else
            echo " > No changes detected after build. Skipping commit."
        end
    else
        echo "Error: Build sequence failed on branch $new_branch_name"
        exit 1
    end
end

# 4. Preview Phase
echo ""
echo "--- Preview of Changes ---"

if test (count $branches_created) -eq 0
    echo "No branches were created or modified."
    git checkout $source_branch --quiet
    # Return to the directory where user started
    cd $repo_root/$relative_prefix
    exit 0
end

for branch in $branches_created
    echo "Branch: $branch"
    git show --stat --oneline HEAD
    echo "--------------------------"
end

# 5. Confirmation and Push
read -l -P "Do you want to push these branches to origin? (y/n) " confirm

if string match -r -i "^y(es)?\$" -- $confirm
    for branch in $branches_created
        echo "Pushing $branch..."
        git push origin $branch
    end
    echo "Done."
else
    echo "Push cancelled. Branches created locally."
end

# Cleanup: Return to original branch and directory
git checkout $source_branch --quiet
cd $repo_root/$relative_prefix
echo "Returned to $source_branch in $relative_prefix"
