#!/usr/bin/env fish

# 1. Validation: Check arguments
if test (count $argv) -lt 2
    echo "Usage: ./sync_cluster.fish <hint> <target_branch_1> [target_branch_2] ..."
    echo "Example: ./sync_cluster.fish myupdate 0.4.8 0.4.9 main"
    exit 1
end

# 2. Setup Variables
set hint $argv[1]
set user_targets $argv[2..-1]
set source_branch (git branch --show-current)
set repo_root (git rev-parse --show-toplevel)
set files_to_sync "config.yaml" ".envrc.vars"
set branches_created

# Check if we are in a clean state before starting
if test -n "(git status --porcelain)"
    echo "Error: Working directory is not clean. Please commit or stash changes before running."
    exit 1
end

echo "--- Starting Sync ---"
echo "Source: $source_branch"
echo "Hint:   $hint"
echo "Targets: $user_targets"
echo "---------------------"

# 3. Main Loop
for target in $user_targets
    # logic: if input is just numbers (0.4.8), prepend release-line-. Else use as is (main).
    if string match -r '^[0-9]+\.[0-9]+\.[0-9]+$' -- $target
        set base_target "release-line-$target"
    else
        set base_target $target
    end

    set new_branch_name "nicuda/sync/$(string replace / - $base_target)_$hint"

    echo "Processing target: $base_target"
    
    # Switch to base target and pull latest
    echo " > Checking out $base_target..."
    git checkout $base_target --quiet
    or begin; echo "Failed to checkout $base_target"; exit 1; end
    
    git pull --quiet
    
    # Create the sync branch
    echo " > Creating branch $new_branch_name..."
    # If branch exists, delete it first to ensure clean state
    if git show-ref --verify --quiet refs/heads/$new_branch_name
        git branch -D $new_branch_name --quiet
    end
    git checkout -b $new_branch_name --quiet

    # Sync the specific files from the source branch
    echo " > Syncing files from $source_branch..."
    git checkout $source_branch -- $files_to_sync 2>/dev/null
    
    # Run the Build/Update Sequence
    echo " > Running build sequence (this may take a moment)..."
    
    # We combine commands. If one fails, the block fails.
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
        echo "Stopping execution to allow debugging."
        exit 1
    end
end

# 4. Preview Phase
echo ""
echo "--- Preview of Changes ---"

if test (count $branches_created) -eq 0
    echo "No branches were created or modified."
    git checkout $source_branch --quiet
    exit 0
end

for branch in $branches_created
    echo "Branch: $branch"
    # Show stats of the commit
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
    echo "Push cancelled."
    echo "Branches have been created locally."
end

# Return to original branch
git checkout $source_branch --quiet
echo "Returned to $source_branch."
