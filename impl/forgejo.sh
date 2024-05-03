sync() {
	git::refs::fetch dest "$SYNCER_DEST"

	local page=1 count=1
	while ((count != 0)); do
		count=0
		while read -r repo; do
			[[ "$repo" != "" ]] || continue
			local name url
			name="$(wyqs '.name' <<<"$repo")"
			url="$(wyqs '.url' <<<"$repo")"
			((count++)) || true

			echo "Syncing $name from $url"
			git::refs::fetch repo "$url"
			while read -r ref; do
				local destRef
				destRef="$SYNCER_DEST_PREFIX$name/$ref"
				echo "Syncing $name $ref to $destRef"
				wgit fetch --no-write-fetch-head "$SYNCER_DEST" "$destRef" || true
				wgit fetch --write-fetch-head "$url" "$ref"
				headRev="$(wgit rev-parse FETCH_HEAD)"
				forgejo::push_branch "$headRev" "$destRef"
			done <"$(git::refs::file repo)"

			while read -r ref; do
				echo "Deleting ref $ref"
				wget push --force :"$ref"
			done < <(git::refs::withprefix dest "$SYNCER_DEST_PREFIX$name/")
		done < <(forgejo::list_repos "$FORGEJO_USERNAME" "$((page))")
		((page++))
	done
	echo "Forgejo push end"

	while read -r ref; do
		echo "Deleting ref $ref"
		wget push --force :"$ref"
	done < <(git::refs::withprefix dest "$SYNCER_DEST_PREFIX")
	echo "Forgejo prune end"

	echo "Forgejo sync end"
}

# forgejo::push_branch <ref> <ref>
forgejo::push_branch() {
	echo "Pushing $1 to $2"
	wgit push --force "$SYNCER_DEST" "$1":"$2"
	git::refs::remove dest "$2"
	echo "Pushed $1 to $2"
}

# forgejo::list_repos <owner> <page (from 1)>
forgejo::list_repos() {
	wcurl -X 'GET' \
		"https://codeberg.org/api/v1/users/$1/repos?page=$2&limit=10" \
		-H 'Accept: application/json' |
		wyq '.[] | { "name": .name, "url": .clone_url }'
}