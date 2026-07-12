#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: bash scripts/verify-siri-ipa.sh <exported-ipa-path> <expected-production-api-url>" >&2
  exit 64
fi

ipa_path="$1"
expected_api_url="$2"

if [[ ! -f "$ipa_path" ]]; then
  echo "IPA not found: $ipa_path" >&2
  exit 66
fi

if [[ -z "$expected_api_url" ]]; then
  echo "Expected production API URL must not be empty." >&2
  exit 64
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/levy-home-siri-ipa.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

require_path() {
  local path="$1"
  local description="$2"

  if [[ ! -e "$path" ]]; then
    echo "Missing $description: $path" >&2
    exit 1
  fi
}

extract_plist_value() {
  local plist_path="$1"
  local key_path="$2"

  /usr/libexec/PlistBuddy -c "Print :$key_path" "$plist_path"
}

require_entitlement() {
  local entitlements_path="$1"
  local key_path="$2"
  local expected_value="$3"
  local description="$4"
  local actual_value

  actual_value="$(extract_plist_value "$entitlements_path" "$key_path")"
  if [[ "$actual_value" != "$expected_value" ]]; then
    echo "Unexpected $description entitlement. Expected '$expected_value', found '$actual_value'." >&2
    exit 1
  fi
}

require_entitlement_array_value() {
  local entitlements_path="$1"
  local key_path="$2"
  local expected_value="$3"
  local description="$4"

  if ! /usr/libexec/PlistBuddy -c "Print :$key_path" "$entitlements_path" | /usr/bin/sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | /usr/bin/grep -Fqx "$expected_value"; then
    echo "Missing $description entitlement value '$expected_value'." >&2
    exit 1
  fi
}

decode_and_validate_profile() {
  local profile_path="$1"
  local description="$2"
  local decoded_path="$work_dir/$description-profile.plist"
  local expiration_date
  local expiration_epoch
  local now_epoch

  /usr/bin/security cms -D -i "$profile_path" > "$decoded_path"
  expiration_date="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$decoded_path")"
  expiration_epoch="$(/bin/date -j -f '%a %b %d %T %Z %Y' "$expiration_date" '+%s')"
  now_epoch="$(/bin/date '+%s')"

  if (( expiration_epoch <= now_epoch )); then
    echo "$description provisioning profile is expired: $expiration_date" >&2
    exit 1
  fi
}

require_vocabulary_item_examples() {
  local vocabulary_plist="$1"
  local item_index="$2"
  local expected_identifier="$3"
  local synonym_count="$4"
  local actual_identifier
  local synonym_index

  actual_identifier="$(extract_plist_value "$vocabulary_plist" "ParameterVocabularies:0:ParameterVocabulary:$item_index:VocabularyItemIdentifier")"

  if [[ "$actual_identifier" != "$expected_identifier" ]]; then
    echo "Unexpected Siri vocabulary item at index $item_index. Expected '$expected_identifier', found '$actual_identifier'." >&2
    exit 1
  fi

  for ((synonym_index = 0; synonym_index < synonym_count; synonym_index++)); do
    if ! /usr/libexec/PlistBuddy -c "Print :ParameterVocabularies:0:ParameterVocabulary:$item_index:VocabularyItemSynonyms:$synonym_index:VocabularyItemExamples" "$vocabulary_plist" | /usr/bin/sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | /usr/bin/grep -Ev '^(Array \{|\})$' | /usr/bin/grep -q .; then
      echo "Missing Siri vocabulary examples for synonym $synonym_index of '$expected_identifier'." >&2
      exit 1
    fi
  done
}

/usr/bin/unzip -qq "$ipa_path" -d "$work_dir/unpacked"

app_path="$work_dir/unpacked/Payload/LevyHome.app"
extension_path="$app_path/PlugIns/LevyHomeIntents.appex"
app_info_plist="$app_path/Info.plist"
extension_info_plist="$extension_path/Info.plist"
vocabulary_plist="$app_path/Base.lproj/AppIntentVocabulary.plist"
app_entitlements="$work_dir/app-entitlements.plist"
extension_entitlements="$work_dir/extension-entitlements.plist"

require_path "$app_path" "Levy Home app bundle"
require_path "$extension_path" "LevyHomeIntents extension"
require_path "$app_info_plist" "host app Info.plist"
require_path "$extension_info_plist" "Intents extension Info.plist"
require_path "$vocabulary_plist" "English Siri vocabulary"
require_path "$app_path/embedded.mobileprovision" "host app provisioning profile"
require_path "$extension_path/embedded.mobileprovision" "Intents extension provisioning profile"

app_api_url="$(extract_plist_value "$app_info_plist" 'LevyHomeAPIBaseURL')"
extension_api_url="$(extract_plist_value "$extension_info_plist" 'LevyHomeAPIBaseURL')"

if [[ "$app_api_url" != "$expected_api_url" || "$extension_api_url" != "$expected_api_url" ]]; then
  echo "Unexpected LevyHomeAPIBaseURL. Host='$app_api_url' extension='$extension_api_url' expected='$expected_api_url'." >&2
  exit 1
fi

if ! /usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:IntentsSupported' "$extension_info_plist" | /usr/bin/grep -Eq '^[[:space:]]*INAddTasksIntent[[:space:]]*$'; then
  echo "LevyHomeIntents does not declare INAddTasksIntent." >&2
  exit 1
fi

require_vocabulary_item_examples "$vocabulary_plist" 0 'levy-home-shopping' 4
require_vocabulary_item_examples "$vocabulary_plist" 1 'levy-home-todo' 5

/usr/bin/codesign --verify --deep --strict "$app_path"
/usr/bin/codesign -d --entitlements :- "$app_path" > "$app_entitlements" 2>/dev/null
/usr/bin/codesign -d --entitlements :- "$extension_path" > "$extension_entitlements" 2>/dev/null

require_entitlement "$app_entitlements" 'com.apple.developer.siri' 'true' 'host Siri'
require_entitlement "$extension_entitlements" 'com.apple.developer.siri' 'true' 'extension Siri'
require_entitlement_array_value "$app_entitlements" 'com.apple.security.application-groups' 'group.com.levyhome.app' 'host App Group'
require_entitlement_array_value "$extension_entitlements" 'com.apple.security.application-groups' 'group.com.levyhome.app' 'extension App Group'
require_entitlement "$app_entitlements" 'aps-environment' 'production' 'host push'
require_entitlement "$app_entitlements" 'com.apple.developer.weatherkit' 'true' 'host WeatherKit'

decode_and_validate_profile "$app_path/embedded.mobileprovision" 'host-app'
decode_and_validate_profile "$extension_path/embedded.mobileprovision" 'intents-extension'

echo "Verified Siri packaging in $(/usr/bin/basename "$ipa_path")."
