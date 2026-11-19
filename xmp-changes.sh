#!/bin/ash
# Records which .xmp sidecars changed since the last run.
#
# icloudpd rewrites every sidecar it touches even when the content is
# identical, so mtimes can't tell which ones changed. This hashes every sidecar
# under download_path, compares against the previous run's manifest, and
# appends the paths (relative to download_path) of sidecars whose content
# changed, or that are new, to pending.list for a consumer to pick up. The
# first run only records a baseline.
#
# Environment:
#   download_path    Sidecar root. Default: /home/user/iCloud
#   xmp_manifest     Hash manifest from the previous run. Default: /config/xmp-manifest.sha256
#   xmp_pending_dir  Directory holding pending.list. Default: <download_path>/.xmp-changes

download_path="${download_path:-/home/user/iCloud}"
xmp_manifest="${xmp_manifest:-/config/xmp-manifest.sha256}"
xmp_pending_dir="${xmp_pending_dir:-${download_path}/.xmp-changes}"

log_info()
{
   echo "$(date '+%Y-%m-%d %H:%M:%S') INFO     ${1}"
}

set -eu
export LC_ALL=C

if [ ! -f "${download_path}/.mounted" ]
then
   echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR    ${download_path}/.mounted does not exist, refusing to run" >&2
   exit 1
fi

new_manifest="${xmp_manifest}.new"
changed_list="/tmp/xmp-changed.$$"
cd "${download_path}"
find . -name '*.xmp' -type f -print0 | xargs -0 -r sha256sum | sort > "${new_manifest}"
total="$(wc -l < "${new_manifest}")"

if [ ! -f "${xmp_manifest}" ]
then
   mv "${new_manifest}" "${xmp_manifest}"
   log_info "XMP manifest: baseline of ${total} sidecars recorded, nothing queued"
   exit 0
fi

# Lines only in the new manifest are sidecars whose hash changed or that are
# new. sha256sum prefixes a backslash to lines for names it has to escape.
comm -13 "${xmp_manifest}" "${new_manifest}" | sed 's/^\\\{0,1\}[0-9a-f]\{64\}  \.\///' > "${changed_list}"
changed="$(wc -l < "${changed_list}")"

if [ "${changed}" -gt 0 ]
then
   mkdir -p "${xmp_pending_dir}"
   cat "${changed_list}" >> "${xmp_pending_dir}/pending.list"
   # The consumer runs as a different user and renames pending.list.
   chmod 777 "${xmp_pending_dir}"
   chmod 666 "${xmp_pending_dir}/pending.list"
fi
mv "${new_manifest}" "${xmp_manifest}"

log_info "XMP manifest: ${total} sidecars, ${changed} changed or new"
if [ "${changed}" -gt 0 ]
then
   log_info "XMP changes queued in ${xmp_pending_dir}/pending.list, first 20:"
   head -n 20 "${changed_list}" | sed 's/^/   /'
fi
