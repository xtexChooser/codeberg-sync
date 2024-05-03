# sync::sync_repo <name> <url>
sync::sync_repo() {
	local name="$1" url="$2"
	try_call_func anysyncer::hook::should_sync_repo "$name" || return 0
	try_call_func "$SYNCER_TYPE"::hook::should_sync_repo "$name" || return 0

	echo "Syncing $name from $url"
	git::refs::fetch repo "$url"
	cp -f "$(git::refs::file repo)" "$(git::refs::file repo1)"
	while read -r ref; do
		try_call_func anysyncer::hook::should_sync_ref "$name" "$ref" || continue
		try_call_func "$SYNCER_TYPE"::hook::should_sync_ref "$name" "$ref" || continue
		local destRef isTag=''
		destRef="$SYNCER_DEST_PREFIX$name/$ref"
		if [[ "$ref" == *^{} ]]; then
			destRef="${destRef%\^\{\}}"
			isTag=true
		fi
		echo "Syncing $name $ref to $destRef"
		if git::refs::check repo1 "$ref^{}"; then
			# tags with message
			return 0
		fi
		wgit fetch --no-write-fetch-head "$SYNCER_DEST" "$destRef" || true
		if [[ -z "$isTag" ]]; then
			wgit fetch --write-fetch-head "$url" "$ref"
			headRev="$(wgit rev-parse FETCH_HEAD)"
		else
			wgit fetch --write-fetch-head "$url" "${ref%\^\{\}}"
			headRev="$(wgit rev-parse 'FETCH_HEAD^{commit}')"
		fi
		sync::push_branch "$headRev" "$destRef"
	done <"$(git::refs::file repo)"

	while read -r ref; do
		try_call_func anysyncer::hook::should_prune_ref "$ref" || continue
		try_call_func "$SYNCER_TYPE"::hook::should_prune_ref "$ref" || continue
		echo "Deleting ref $ref"
		wgit push --force "$SYNCER_DEST" :"$ref"
	done < <(git::refs::withprefix dest "$SYNCER_DEST_PREFIX$name/")
}

# sync::push_branch <ref> <dest ref>
sync::push_branch() {
	echo "Pushing $1 to $2"
	if ! wgit push --force "$SYNCER_DEST" "$1":"$2"; then
		result=$?
		if try_call_func anysyncer::hook::should_fail_on_push_err "$2" &&
			try_call_func "$SYNCER_TYPE"::hook::should_fail_on_push_err "$2"; then
			return $result
		fi
	fi
	git::refs::remove dest "$2"
	echo "Pushed $1 to $2"
}

# sync::prune_refs
sync::prune_refs() {
	while read -r ref; do
		try_call_func anysyncer::hook::should_prune_ref "$ref" || continue
		try_call_func "$SYNCER_TYPE"::hook::should_prune_ref "$ref" || continue
		echo "Deleting ref $ref"
		wgit push --force "$SYNCER_DEST" :"$ref"
	done < <(git::refs::withprefix dest "$SYNCER_DEST_PREFIX")
}