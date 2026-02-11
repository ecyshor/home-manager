#!/usr/bin/env fish

# --- 1. Validation & Setup ---

if test (count $argv) -lt 2
    echo "Usage: sync-cluster <hint> <target_branch_1> [target_branch_2] ..."
    exit 1
end

set hint $argv[1]
set user_targets $argv[2..-1]

# Save starting state to return to later
set start_dir (pwd)
set source_branch (git branch --show-current)
set repo_root (git rev-parse --show-toplevel)
set relative_prefix (git rev-parse --show-prefix)

# Paths relative to the Repo Root
set files_to_sync "$relative_prefix"config.yaml "$relative_prefix".envrc.vars

# --- 2. Safety Functions ---

# Function to handle failures and clean up
function cleanup_and_fail
    echo ""
    echo "!!! Error detected or interrupted !!!"
    echo " > Resetting current branch state..."
    git reset --hard --quiet HEAD
    
    echo " > Returning to original branch: $source_branch"
    git checkout $source_branch --quiet
    
    echo " > Returning to original directory"
    cd $start_dir
    
    exit 1
end

# Trap interrupts (Ctrl+C) so we don't get stuck on a weird branch
trap cleanup_and_fail INT

# --- 3. Pre-flight Checks ---

# Verify files exist in current dir
if not test -f config.yaml; or not test -f .envrc.vars
    echo "Error: config.yaml or .envrc.vars not found in current directory."
    exit 1
end

# Verify clean state
if test -n "(git status --porcelain)"
    echo "Error: Working directory is not clean. Please commit/stash changes."
    exit 1
end

echo "--- Starting Sync ---"
echo "Source: $source_branch"
echo "Dir:    $relative_prefix"
echo "Targets: $user_targets"
echo "---------------------"

# Move to root for Make commands
cd $repo_root

set branches_created

# --- 4. Main Loop ---

for target in $user_targets
    # Determine base branch name
    if string match -r '^[0-9]+\.[0-9]+\.[0-9]+$' -- $target
        set base_target "release-line-$target"
    else
        set base_target $target
    end

    set new_branch_name "nicuda/sync/$(string replace / - $base_target)_$hint"

    echo "Processing target: $base_target"
    
    # Checkout Base
    git checkout $base_target --quiet
    or cleanup_and_fail
    
    git pull --quiet
    or cleanup_and_fail

    # Create/Reset Sync Branch
    echo " > Creating branch $new_branch_name..."
    if git show-ref --verify --quiet refs/heads/$new_branch_name
        git branch -D $new_branch_name --quiet
    end
    git checkout -b $new_branch_name --quiet

    # Sync Files
    echo " > Syncing files from $source_branch..."
    git checkout $source_branch -- $files_to_sync 2>/dev/null
    or cleanup_and_fail

    # Build Sequence
    echo " > Running build sequence..."
    
    # We use a block to ensure we catch failure at any step
    begin
        git submodule update --init --recursive
        and make -j8 -C splice cluster/clean
        and make -j8 -C splice cluster/build
        and make -j8 update-expected
    end
    
    # Check status of the build block
    if test $status -eq 0
        # Build Success: Commit
        if test -n "(git status --porcelain)"
            echo " > Changes detected (including update-expected). Committing..."
            git add .
            git commit -m "sync cluster config for $hint from $source_branch" --quiet
            set -a branches_created $new_branch_name
        else
            echo " > No changes detected. Skipping commit."
        end
    else
        # Build Failure
        echo "Error: Build sequence failed on $new_branch_name"
        cleanup_and_fail
    end
end

# --- 5. Preview & Push ---

echo ""
echo "--- Preview ---"

if test (count $branches_created) -eq 0
    echo "No branches modified."
    git checkout $source_branch --quiet
    cd $start_dir
    exit 0
end

for branch in $branches_created
    echo "Branch: $branch"
    git show --stat --oneline HEAD
    echo "--------------------------"
end

read -l -P "Push branches to origin? (y/n) " confirm

if string match -r -i "^y(es)?\$" -- $confirm
    for branch in $branches_created
        echo "Pushing $branch..."
        git push origin $branch
    end
    echo "Done."
else
    echo "Push cancelled."
end

# --- 6. Final Cleanup ---
git checkout $source_branch --quiet
cd $start_dir
echo "Returned to $source_branch in $relative_prefix"
