    # Checkout Base (Force to overwrite ignored artifacts)
    git checkout -f $base_target --quiet
    or cleanup_and_fail
    
    git pull --quiet
    or cleanup_and_fail

    # Create Branch
    echo " > Creating branch $new_branch_name..."
    if git show-ref --verify --quiet refs/heads/$new_branch_name
        git branch -D $new_branch_name --quiet
    end
    git checkout -b $new_branch_name --quiet

    # --- SYNC LOGIC ---
    if set -q _flag_only_config
        echo " > Syncing .envrc.vars and partial config ($yq_path)..."
        
        git checkout $source_branch -- $env_file 2>/dev/null
        or cleanup_and_fail
        
        git show "$source_branch:$config_file" > "$config_file.tmp_source"
        
        yq eval-all -i "select(fileIndex == 0) | .$yq_path = (select(fileIndex == 1) | .$yq_path) | select(fileIndex == 0)" $config_file "$config_file.tmp_source"
        
        rm "$config_file.tmp_source"
        
    else
        echo " > Syncing files fully from $source_branch..."
        git checkout $source_branch -- $files_to_sync 2>/dev/null
        or cleanup_and_fail
    end

    # Build Sequence
    echo " > Running build sequence..."
    
    if begin
        # 1. Reset splice submodule to avoid dirty state
        if test -d splice/.git
             git -C splice reset --hard HEAD >/dev/null 2>&1
        end

        # 2. Update submodules (Force)
        git submodule update --init --recursive --force
        
        and make -j8 -C splice cluster/clean
        and make -j8 -C splice cluster/build
        and make -j8 update-expected
    end
        # Check for changes
        set build_status_output (git status --porcelain)
        
        if test -n "$build_status_output"
            echo " > Changes detected. Committing..."
            git add .
            git commit -m "sync cluster config for $hint from $source_branch" --quiet
            set -a branches_created $new_branch_name
        else
            echo " > No changes detected. Skipping commit."
        end
    else
        echo "Error: Build sequence failed on $new_branch_name"
        cleanup_and_fail
    end
end

# --- 6. Preview & Push ---

echo ""
echo "--- Preview of Changes ---"

if test (count $branches_created) -eq 0
    echo "No branches modified."
    git checkout -f $source_branch --quiet
    cd $start_dir
    exit 0
end

for branch in $branches_created
    echo "Branch: $branch"
    # Show strict diff of config/env files for the commit
    # We use ^! to show the diff of the commit relative to its parent
    git diff $branch^ $branch -- $files_to_sync
    echo "--------------------------"
end

read -l -P "Force push these branches to origin? (y/n) " confirm

if string match -r -i "^y(es)?\$" -- $confirm
    for branch in $branches_created
        echo "Pushing $branch (force)..."
        git push --force origin $branch
    end
    echo "Done."
else
    echo "Push cancelled."
end

# --- 7. Final Cleanup ---
git checkout -f $source_branch --quiet
cd $start_dir
echo "Returned to $source_branch in $relative_prefix"
