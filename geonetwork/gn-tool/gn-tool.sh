#!/bin/bash

# runs a git diff diff-filter command
# $1 - git directory
# $2 - from sha
# $3 - to sha
# $4 - diff filter
# "$@" - extra arguments to git diff
git_diff_filter() {
    local dir=$1; shift
    local sha1=$1; shift
    local sha2=$1; shift
    local diff_filter=$1; shift
    (cd $dir && git diff "$@" --diff-filter=$diff_filter --numstat ${sha1}..${sha2} | cut -f3)
}

# get modified/added geonetwork records in a git repository
# $1 - git directory
# $2 - from sha
# $3 - to sha
get_modified_new_records() {
    local dir=$1; shift
    local sha1=$1; shift
    local sha2=$1; shift
    git_diff_filter $dir $sha1 $sha2 MAC | cut -d'/' -f1 | sort | uniq
}

# get deleted geonetwork records in a git repository
# $1 - git directory
# $2 - from sha
# $3 - to sha
get_deleted_records() {
    local dir=$1; shift
    local sha1=$1; shift
    local sha2=$1; shift
    git_diff_filter $dir $sha1 $sha2 D -M | cut -d'/' -f1 | sort | uniq
}

# return all available record uuids in geonetwork
# $1 - geonetwork address
# $2 - geonetwork user
# $3 - geonetwork password
get_all_records() {
    local gn_addr=$1; shift
    local gn_user=$1; shift
    local gn_password=$1; shift

    curl -s "$gn_addr/srv/eng/xml.search.imos?fast=index" | \
        grep "<uuid>.*</uuid>" | tr -s " " | cut -c8-43
}

# delete a single record
# $1 - record uuid
# $2 - geonetwork address
# $3 - geonetwork user
# $4 - geonetwork password
delete_record() {
    local record_uuid=$1; shift
    local gn_addr=$1; shift
    local gn_user=$1; shift
    local gn_password=$1; shift

    echo "Deleting record '$record_uuid'"
    curl -s \
        -u $gn_user:$gn_password \
        -d "uuid=$record_uuid" \
        "$gn_addr/srv/eng/xml.metadata.delete"
}

# export a single geonetwork record
# $1 - record uuid
# $2 - directory to dump mef to
# $3 - geonetwork address
# $4 - geonetwork user
# $5 - geonetwork password
export_record() {
    local record_uuid=$1; shift
    local dir=$1; shift
    local gn_addr=$1; shift
    local gn_user=$1; shift
    local gn_password=$1; shift

    echo "Exporting '$record_uuid' -> '$dir/$record_uuid'"
    local tmp_mef=`mktemp`
    curl -s "$gn_addr/srv/eng/mef.export" -d "uuid=$record_uuid&format=full&version=2" -o $tmp_mef && \
        unzip -o -d $dir $tmp_mef && \
        rm -f $tmp_mef
}

# export geonetwork records
# $1 - record uuid
# $2 - directory to export record(s) to
# $3 - geonetwork address
# $4 - geonetwork user
# $5 - geonetwork password
export_records() {
    local record_uuid=$1; shift
    local record_dir=$1; shift
    local gn_addr=$1; shift
    local gn_user=$1; shift
    local gn_password=$1; shift

    local -i retval=0
    if [ x"$record_uuid" = x"ALL" ]; then
        mkdir -p $record_dir
        for record_uuid in `get_all_records $gn_addr $gn_user $gn_password`; do
            export_record $record_uuid $record_dir $gn_addr $gn_user $gn_password
            let retval=$retval+$?
        done
    else
        export_record $record_uuid $record_dir $gn_addr $gn_user $gn_password
        let retval=$retval+$?
    fi

    return $retval
}

# imports a single geonetwork record
# $1 - file to import from
# $2 - geonetwork address
# $3 - geonetwork user
# $4 - geonetwork password
import_record() {
    local record_dir_path=$1; shift
    local gn_addr=$1; shift
    local gn_user=$1; shift
    local gn_password=$1; shift

    # prepare MEF file
    local tmp_mef=`mktemp`

    local uuid=`basename $record_dir_path`
    (cd `dirname $record_dir_path` && rm -f $tmp_mef && zip -q -r $tmp_mef $uuid)

    echo "Importing record '$uuid' from '$record_dir_path'"

    curl -s -X POST \
        -u $gn_user:$gn_password \
        -F "insert_mode=1" \
        -F "file_type=mef" \
        -F "category=_none_" \
        -F "group=2" \
        -F "styleSheet=_none_" \
        -F "uuidAction=overwrite" \
        -F "template=n" \
        -F mefFile=@$tmp_mef \
        $gn_addr/srv/eng/mef.import && \
    curl -s \
        -u $gn_user:$gn_password \
        -d "_1_0=on&_1_1=on&_1_5=on&_1_6=on" \
        -d "uuid=$uuid" \
        $gn_addr/srv/eng/metadata.admin && \
    rm -f $tmp_mef
}

# imports geonetwork records
# $1 - file/directory to import
# $2 - geonetwork address
# $3 - geonetwork user
# $4 - geonetwork password
import_records() {
    local record_location=$1; shift
    local gn_addr=$1; shift
    local gn_user=$1; shift
    local gn_password=$1; shift

    local record_file
    local -i retval=0
    if [ -d $record_location ]; then
        for record_file in $record_location/*; do
            import_record $record_file $gn_addr $gn_user $gn_password
            let retval=$retval+$?
        done
    else
        import_record $record_location $gn_addr $gn_user $gn_password
        let retval=$retval+$?
    fi
    return $retval
}

# imports geonetwork records, assume git directory
# $1 - git directory to import
# $2 - geonetwork address
# $3 - geonetwork user
# $4 - geonetwork password
import_records_git() {
    local record_location=$1; shift
    local gn_addr=$1; shift
    local gn_user=$1; shift
    local gn_password=$1; shift

    if [ ! -d "$record_location" ] || [ ! -d "$record_location/.git" ]; then
        echo "'$record_location' is not a git directory"
        return 1
    fi

    local -i retval=0
    echo "Performing intelligent import from git directory '$record_location'"

    # either start from the begining, or take sha from last_update file
    local from_sha=`(cat $record_location/last_update 2> /dev/null) || (cd $record_location && git log --oneline | tail -1 | cut -d' ' -f1)`
    local to_sha=`(cd $record_location && git log --oneline | head -1 | cut -d' ' -f1)`

    # special case when there's only one commit in the repository - import all
    local -i num_commits=`cd $record_location && git log | grep ^commit | wc -l`
    if [ $num_commits -eq 1 ] && [ ! -f $record_location/last_update ]; then
        import_records $record_location $gn_addr $gn_user $gn_password
    else
        if [ "$from_sha" = "$to_sha" ]; then
            echo "No new changes detected"
            return 0
        fi

        echo "Applying changes from '$from_sha' to '$to_sha'"
        local record_file
        for record_file in `get_modified_new_records $record_location $from_sha HEAD`; do
            import_record $record_location/$record_file $gn_addr $gn_user $gn_password
            let retval=$retval+$?
        done

        for record_file in `get_deleted_records $record_location $from_sha HEAD`; do
            local uuid=`basename $record_file | cut -d. -f1`
            delete_record $uuid $gn_addr $gn_user $gn_password
            let retval=$retval+$?
        done
    fi

    local last_commit=`cd $record_location && git log --oneline | head -1 | cut -d' ' -f1`
    if [ $retval -eq 0 ]; then
        echo $last_commit > $record_location/last_update
    else
        echo "Could not apply changes from '$from_sha' to '$last_commit'"
    fi

    return $retval
}

# prints usage and exit
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Import/export Geonetwork records."
    echo "
Options:
  -G                         Intelligent import using git.
  -o                         Operation, must be one of 'import' or 'export'.
  -l                         Location to read/write records from/to.
  -g                         Geonetwork address like http://a.b.c.d/geonetwork
  -u                         Username to login with.
  -p                         Password to login with."
    exit 3
}

main() {
    # parse options with getopt
    local tmp_getops
    tmp_getops=`getopt hGo:l:g:u:p: $*`
    [ $? != 0 ] && usage

    set -- $tmp_getops
    local gn_addr gn_user gn_password
    local location operation
    local record_uuid="ALL"
    local git=no

    # parse the options
    while true ; do
        case "$1" in
            -h) usage;;
            -G) git=yes; shift 1;;
            -o) operation=$2; shift 2;;
            -l) location="$2"; shift 2;;
            -r) record_uuid="$2"; shift 2;;
            -g) gn_addr="$2"; shift 2;;
            -u) gn_user="$2"; shift 2;;
            -p) gn_password="$2"; shift 2;;
            --) shift; break;;
            *) usage;;
        esac
    done

    [ x"$operation" = x ] && usage
    [ x"$location" = x ] && usage
    [ x"$gn_addr" = x ] && usage

    if [ "$operation" = "import" ]; then
        # must authenticate to run import
        if [ x"$gn_user" = x ] || [ x"$gn_password" = x ]; then
            usage
        fi

        if [ "$git" = "yes" ]; then
            import_records_git $location $gn_addr $gn_user $gn_password
        else
            import_records $location $gn_addr $gn_user $gn_password
        fi
    elif [ "$operation" = "export" ]; then
        export_records $record_uuid $location $gn_addr $gn_user $gn_password
    else
        usage
    fi
}

main "$@"
