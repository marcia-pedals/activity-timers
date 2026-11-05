#!/usr/bin/env bash
# Writes the groups and activity types from seed/activities.json into Firestore
# for one user. Safe to re-run: documents are keyed by the "id" fields, so existing
# ones are updated in place. Items removed from the JSON are NOT deleted.
#
# "icon" is an SF Symbol name (browse them in Apple's SF Symbols app); it's shown
# in the Dynamic Island. Missing/unknown names fall back to a timer icon.
#
# Usage: scripts/seed.sh you@example.com [path/to/activities.json]
set -euo pipefail

cd "$(dirname "$0")/.."
email=${1:?usage: scripts/seed.sh EMAIL [JSON_FILE]}
file=${2:-seed/activities.json}
plist=ios/ActivityTimers/GoogleService-Info.plist

api_key=$(plutil -extract API_KEY raw "$plist")
project=$(plutil -extract PROJECT_ID raw "$plist")
bundle_id=$(plutil -extract BUNDLE_ID raw "$plist")

read -rsp "Password for $email: " password
echo

# Sign in as the user so writes go through the same security rules as the app.
auth=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -H "X-Ios-Bundle-Identifier: $bundle_id" \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$api_key" \
  -d "$(jq -n --arg e "$email" --arg p "$password" '{email: $e, password: $p, returnSecureToken: true}')")
token=$(jq -r '.idToken // empty' <<<"$auth")
uid=$(jq -r '.localId // empty' <<<"$auth")
if [[ -z $token ]]; then
  echo "Sign-in failed: $(jq -r '.error.message // .' <<<"$auth")" >&2
  exit 1
fi

base="https://firestore.googleapis.com/v1/projects/$project/databases/(default)/documents/users/$uid"

put() { # put COLLECTION ID FIELDS_JSON
  local out
  out=$(curl -sS -g -X PATCH \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "$base/$1/$2" -d "{\"fields\": $3}")
  if jq -e '.error' <<<"$out" >/dev/null; then
    echo "Failed writing $1/$2: $(jq -r '.error.message' <<<"$out")" >&2
    exit 1
  fi
  echo "  $1/$2"
}

echo "Writing to users/$uid:"
while IFS=$'\t' read -r id fields; do
  put groups "$id" "$fields"
done < <(jq -r '.groups | to_entries[] |
  [.value.id, ({name: {stringValue: .value.name}, sortOrder: {integerValue: (.key | tostring)}} | tojson)] | @tsv' "$file")

while IFS=$'\t' read -r id fields; do
  put activityTypes "$id" "$fields"
done < <(jq -r '.activityTypes | to_entries[] |
  [.value.id, ({
    name: {stringValue: .value.name},
    groupId: (if .value.groupId then {stringValue: .value.groupId} else {nullValue: null} end),
    icon: (if .value.icon then {stringValue: .value.icon} else {nullValue: null} end),
    sortOrder: {integerValue: (.key | tostring)}
  } | tojson)] | @tsv' "$file")

echo "Done."
