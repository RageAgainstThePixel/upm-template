#!/usr/bin/env bash
# Copyright (c) Stephen Hodgson. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for license information.

set -e pipefail
IFS=$'\n\t'

read -rp "Set Author name: (i.e. your GitHub username) " InputAuthor
if [[ -z "$InputAuthor" ]]; then
  echo "Author cannot be empty"
  exit 1
fi

read -rp "Enter a name for your new project: " InputName
if [[ -z "$InputName" ]]; then
  echo "Project name cannot be empty"
  exit 1
fi

read -rp "Enter a scope for your new project (optional): " InputScope

if [[ -n "$InputScope" && -n "${InputScope// }" ]]; then
  InputScope="${InputScope}."
else
  InputScope="" # Default to empty if none provided
fi

read -rp "Enter an Organization for your project (Optional) (i.e. your github or organization name): " InputOrganization

# If InputOrganization is empty or contains only whitespace, default to InputName
if [[ -z "$InputOrganization" || -z "${InputOrganization// }" ]]; then
  InputOrganization="${InputName}" # Default to InputName if none provided
fi

ProjectAuthor="ProjectAuthor"
ProjectName="ProjectName"
ProjectScope="ProjectScope."
ProjectOrganization="ProjectOrganization"

# Announce
echo "Your new com.${InputScope,,}${InputName,,} project is being created..."
echo "Author: ${InputAuthor}"
if [[ "${InputOrganization}" != "${InputName}" ]]; then
  echo "Organization: ${InputOrganization}"
fi
echo "Project Name: ${InputName}"
echo "Project Scope: ${InputScope}"

oldPackageRoot="./${ProjectScope}${ProjectName}/Packages/com.${ProjectScope,,}${ProjectName,,}"

# Remove existing Readme.md if present at repo root
if [[ -f ./Readme.md ]]; then
  rm -f ./Readme.md
fi

# Remove Samples directory under the template Assets
if [[ -d ./${ProjectScope}${ProjectName}/Assets/Samples ]]; then
  rm -rf ./${ProjectScope}${ProjectName}/Assets/Samples
fi

# Copy Documentation~/Readme.md from package to repo Readme.md
if [[ -f "${oldPackageRoot}/Documentation~/Readme.md" ]]; then
  cp "${oldPackageRoot}/Documentation~/Readme.md" ./Readme.md
fi

# Helper function to safely rename files
safe_rename() {
  src="$1"
  dst="$2"
  if [[ -f "${src}" ]]; then
    mv "${src}" "${dst}"
  fi
}

# Cross-platform GUID/UUID v4 generator
generate_guid() {
    # Try /proc on Linux
    if command -v cat >/dev/null 2>&1 && [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid 2>/dev/null || true
        return
    fi

    # Try uuidgen
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen 2>/dev/null && return
    fi

    # Try openssl to create 16 bytes and format as UUID v4
    if command -v openssl >/dev/null 2>&1; then
        # openssl rand -hex 16 -> 32 hex chars; format to UUID 8-4-4-4-12
        hex=$(openssl rand -hex 16 2>/dev/null || true)
        if [[ -n "$hex" && ${#hex} -ge 32 ]]; then
        printf '%s-%s-%s-%s-%s' "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}"
        return
        fi
    fi

    # Try Python (works on many systems including macOS)
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null && return
    elif command -v python >/dev/null 2>&1; then
        python -c 'import uuid; print(uuid.uuid4())' 2>/dev/null && return
    fi

    # Try PowerShell (useful on Windows with Git Bash / MSYS where pwsh may be present)
    if command -v pwsh >/dev/null 2>&1; then
        pwsh -NoProfile -Command '[guid]::NewGuid().ToString()' 2>/dev/null && return
    elif command -v powershell >/dev/null 2>&1; then
        powershell -NoProfile -Command '[guid]::NewGuid().ToString()' 2>/dev/null && return
    fi

    # As a last resort, generate using /dev/urandom if available
    if [[ -r /dev/urandom ]]; then
        # Read 16 bytes and format
        if command -v od >/dev/null 2>&1; then
        bytes=$(od -An -N16 -tx1 /dev/urandom | tr -d '\n' | sed 's/ \+/ /g' | sed 's/ //g')
        if [[ -n "$bytes" && ${#bytes} -ge 32 ]]; then
            printf '%s-%s-%s-%s-%s' "${bytes:0:8}" "${bytes:8:4}" "${bytes:12:4}" "${bytes:16:4}" "${bytes:20:12}"
            return
        fi
        fi
    fi

    # If all methods fail, return error
    return 1
}

# Rename asmdef files
safe_rename "${oldPackageRoot}/Runtime/${ProjectScope}${ProjectName}.asmdef" "${oldPackageRoot}/Runtime/${InputScope}${InputName}.asmdef"
safe_rename "${oldPackageRoot}/Editor/${ProjectScope}${ProjectName}.Editor.asmdef" "${oldPackageRoot}/Editor/${InputScope}${InputName}.Editor.asmdef"
safe_rename "${oldPackageRoot}/Tests/${ProjectScope}${ProjectName}.Tests.asmdef" "${oldPackageRoot}/Tests/${InputScope}${InputName}.Tests.asmdef"
safe_rename "${oldPackageRoot}/Samples~/Demo/${ProjectScope}${ProjectName}.Demo.asmdef" "${oldPackageRoot}/Samples~/Demo/${InputScope}${InputName}.Demo.asmdef"

# Rename package folder
if [[ -d "${oldPackageRoot}" ]]; then
  newPackageName="com.${InputScope,,}${InputName,,}"
  mv "${oldPackageRoot}" "./${ProjectScope}${ProjectName}/Packages/${newPackageName}"
  oldPackageRoot="./${ProjectScope}${ProjectName}/Packages/${newPackageName}"
fi

# Rename top-level project folder
if [[ -d "./${ProjectScope}${ProjectName}" ]]; then
  mv "./${ProjectScope}${ProjectName}" "./${InputScope}${InputName}"
fi

# Exclude patterns
excludes=("*\.git*" "*Library*" "*Obj*" "*InitializeTemplate*")

# Find files recursively (excluding matches)
# We'll use find and filter out paths that match any exclude pattern
while IFS= read -r -d '' file; do
  # Skip if parent path matches any exclude
  skip=false
  for ex in "${excludes[@]}"; do
    if [[ "${file}" == *${ex#*}* ]]; then
      skip=true
      break
    fi
  done
  if $skip; then
    continue
  fi

  # Process text files only - skip binaries to avoid "ignored null byte" warnings
  if [[ -f "${file}" ]]; then
    # Use grep -Iq to test if file is text. grep -Iq returns 0 for text, 1 for binary.
    if ! grep -Iq . "${file}" 2>/dev/null; then
      # Skip binary files (images, compiled assemblies, etc.)
      continue
    fi
    updated=false
    # Read file content
    content=$(<"${file}")

    # Replace PascalCase ProjectName -> InputName
    if grep -q "${ProjectName}" <<< "${content}"; then
      content="${content//${ProjectName}/${InputName}}"
      updated=true
    fi

    # Replace ProjectScope -> InputScope
    if grep -q "${ProjectScope}" <<< "${content}"; then
      content="${content//${ProjectScope}/${InputScope}}"
      updated=true
    fi

    # Replace ProjectOrganization -> InputOrganization
    if grep -q "${ProjectOrganization}" <<< "${content}"; then
      content="${content//${ProjectOrganization}/${InputOrganization}}"
      updated=true
    fi

    # Replace ProjectAuthor -> InputAuthor
    if grep -q "${ProjectAuthor}" <<< "${content}"; then
      content="${content//${ProjectAuthor}/${InputAuthor}}"
      updated=true
    fi

    # Replace StephenHodgson -> InputAuthor
    if grep -q "StephenHodgson" <<< "${content}"; then
      content="${content//StephenHodgson/${InputAuthor}}"
      updated=true
    fi

    # Replace lowercase project name
    if grep -q "${ProjectName,,}" <<< "${content}"; then
      content="${content//${ProjectName,,}/${InputName,,}}"
      updated=true
    fi

    # Replace lowercase project scope
    if grep -q "${ProjectScope,,}" <<< "${content}"; then
      content="${content//${ProjectScope,,}/${InputScope,,}}"
      updated=true
    fi

    # Replace uppercase project name
    if grep -q "${ProjectName^^}" <<< "${content}"; then
      content="${content//${ProjectName^^}/${InputName^^}}"
      updated=true
    fi

    # Replace uppercase project scope
    if grep -q "${ProjectScope^^}" <<< "${content}"; then
      content="${content//${ProjectScope^^}/${InputScope^^}}"
      updated=true
    fi

    # Replace #INSERT_GUID_HERE# with a new GUID
    if grep -q "#INSERT_GUID_HERE#" <<< "$content"; then
      guid=$(generate_guid)

      if [[ -z "$guid" || $? -ne 0 ]]; then
        echo "Failed to generate GUID."
        exit 1
      fi

      content=${content//#INSERT_GUID_HERE#/${guid}}
      updated=true
    fi

    # Replace #CURRENT_YEAR#
    if grep -q "#CURRENT_YEAR#" <<< "${content}"; then
      year=$(date +%Y)
      content=${content//#CURRENT_YEAR#/${year}}
      updated=true
    fi

    if $updated; then
      printf "%s" "${content}" > "${file}"
      echo "Updated: ${file}"
    fi

    # Rename files whose name contains ProjectName
    filename=$(basename -- "${file}")
    dir=$(dirname -- "${file}")
    if [[ "${filename}" == *"${ProjectName}"* ]]; then
      newName=${filename//${ProjectName}/${InputName}}
      mv "${file}" "${dir}/${newName}"
      echo "Renamed file: ${file} -> ${dir}/${newName}"
    fi
  fi

done < <(find . -type f -print0)

assets_path="./${InputScope}${InputName}/Assets"

if [[ -d "$assets_path" ]]; then
  pushd "$assets_path" >/dev/null || true
  # Relative path from Assets -> Packages (one directory up)
  target="../Packages/com.${InputScope,,}${InputName,,}/Samples~"

  # create symlink using cmd mklink on Windows, else use ln -s on POSIX
  isWindows=false

  case "$(uname -s)" in
    CYGWIN*|MINGW*|MSYS*|Windows_NT)
      isWindows=true
      ;;
  esac

  if $isWindows; then
    # Convert POSIX relative path to Windows relative path (keep it relative — do NOT make absolute)
    # Strip leading ./ if present and convert forward slashes to backslashes
    win_target="${target#./}"
    win_target="${win_target//\//\\}"

    # Prefer running mklink via PowerShell (pwsh or powershell) to ensure proper path handling
    # Build the command we want to run in cmd.exe
    cmd_inner="mklink /D \"Samples\" \"${win_target}\""

    # Try pwsh first, then powershell, then fallback to direct cmd.exe
    if command -v pwsh >/dev/null 2>&1; then
      echo "pwsh -NoProfile -Command \"cmd /c '${cmd_inner}'\""
      cmd_output=$(pwsh -NoProfile -Command "cmd /c '${cmd_inner}'" 2>&1)
      cmd_rc=$?
    elif command -v powershell >/dev/null 2>&1; then
      echo "powershell -NoProfile -Command \"cmd /c '${cmd_inner}'\""
      cmd_output=$(powershell -NoProfile -Command "cmd /c '${cmd_inner}'" 2>&1)
      cmd_rc=$?
    else
      # Last resort: call cmd.exe directly
      echo "cmd /c ${cmd_inner}"
      cmd_output=$(cmd.exe /c "${cmd_inner}" 2>&1)
      cmd_rc=$?
    fi

    if [ ${cmd_rc} -ne 0 ]; then
      echo "Failed to create Samples symlink! command output:"
      printf '%s\n' "${cmd_output}"
      echo "Hint: mklink may require Administrator privileges or Developer Mode on Windows."
    else
      # print success message so user sees the created link
      printf '%s\n' "${cmd_output}"
    fi
  else
    echo "Creating Samples symlink to ${target}..."
    ln -s "${target}" "Samples" || {
      echo "Failed to create Samples symlink!"
    }
  fi

  popd >/dev/null || true
fi

# Remove this script
if [[ -f ./InitializeTemplate.sh ]]; then
  rm -f ./InitializeTemplate.sh
fi

echo "Initialization complete."
# test if unity-cli is installed, if so open project
if command -v unity-cli >/dev/null 2>&1; then
  unity-cli open-project || {
    echo "Failed to open project with unity-cli."
  }
fi
exit 0