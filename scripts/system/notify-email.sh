#!/usr/bin/env bash
# Author: Leon Connor Holm
# Define options

iDIR="$HOME/.config/hypr/icons"

cut_cmd="cut -c1-99"
notify_cmd_base="notify-send" 
notify_category="Mail"
notify_cmd_hint="string:x-canonical-private-synchronous:shot-notify"
notify_cmd_icon="${iDIR}/mail.png"

YELLOW='\e[33m'
log_message() {
    # Takes a message and variable as parameter
    local log_dir="$HOME/.local/log"
    local log_file="email-notify.log"
    local time_stamp=""

    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
    fi

    time_stamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "$time_stamp : $1" >> "$log_dir/$log_file"
}

cut_string() {
    # Cut the string and return [...]
    # To ensure that the style of the notification doesn't break

    local cut_part=""
    cut_part=$($cut_cmd <<< "$1")
    if [[ "${#cut_part}" -lt "${#1}" ]]; then
        # return the the smaller sliced part
        echo "$cut_part \[...\]"
        return
    fi
    # no cut needed and return the initial argument
    echo "$1"
    
}

# Initialize variable to store option
sender_address="" # %a
sender_name="" # %n or %a if none
receive_list="" # %r
reply_to_address="" # %A or %a if none
user_account_address="" # %T
cc_list="" # %R
email_subject="" # %s
local_system_time="" # %D
notification_urgency="" # The urgency incoming mails should be treated with
flags=""

# Boolean vars for flags
message_is_old=false # When the email arrived while the client was offline
message_is_response=false # When the email is a follow up reply of one of your emails
message_is_marked=false # Whether the email is marked or not
message_is_flagged=false # Whether the email is flagged or not
message_is_new=false # Whether the email is new or not (e.g. moved between folders)
message_is_deleted=false # Whether the email was deleted

new_recipient=false # Whether to reply to the sender or the new recipient

opts="a:n:r:A:T:R:s:D:Z:"
# Parse options
while getopts "$opts" opt; do
  case "$opt" in
    a) 
        # Sender address %a
        sender_address="$OPTARG"
        ;;
    n)
        # Sender name %n or %a if none
        sender_name="$OPTARG"        
        ;;
    r)
        # List of recipients %r
        receive_list="$OPTARG"        
        ;;

    A)
        # Reply-to address %A or %a if none
        reply_to_address="$OPTARG"
        ;;
    T)
        # Receiver adress (Email account) %T
        user_account_address="$OPTARG"
        ;;
    R)
        # CC-List %R (comma separated)
        cc_list="$OPTARG"
        ;;
    s)
        # Subject %s
        email_subject="$OPTARG"
        ;;
    D)
        # Local Time %D
        local_system_time="$OPTARG"
        ;;
    Z)
        # Set the default notification urgency to low
        flags="$OPTARG"
        notification_urgency="low"

        if [[ "$OPTARG" == *N* ]]; then
            # Handle old or new mails
            message_is_new=true
            notification_urgency="low"
        fi
        
        if [[ "$OPTARG" == *O* ]]; then
            message_is_old=true
            notification_urgency="low"
        fi

        if [[ "$OPTARG" == *D* ]]; then
            # Handle deleted mails
            message_is_deleted=true
            notification_urgency="low"
        fi

        if [[ "$OPTARG" == *r* ]]; then
            # Handle answered mails
            message_is_response=true
            notification_urgency="normal"
        fi

        if [[ "$OPTARG" == *!* ]]; then
            # Handle flagged mails
            message_is_flagged=true
            notification_urgency="critical"
        fi

        if [[ "$OPTARG" == *\** ]]; then
            # Handle marked mails
            message_is_marked=true
            notification_urgency="critical"
        fi
        
        supported_flags='rNOD!*'
        # unsupported flags
        for i in ${flags//,/ }
        do
            # Flag is unsupported -> ignored
            if [[ "$supported_flags" != *$i* ]]; then
                log_message "${YELLOW}WARNING!\e[0m Invalid flag in the %Z option found: '$i'! This flag was ignored. Input was: '$OPTARG'"
            fi

        done
        ;;
    \?)
        log_message "Invalid option: -$OPTARG"
        exit 1
        ;;
    :)
        log_message "Option -$opt requires an argument."
        exit 1
        ;;
  esac
done

email_is_from=""
# Check whether the sender_name is defined or not
if [[ "$sender_address" == "$sender_name" ]]; then
    email_is_from+="$sender_address"
else
    email_is_from+="$sender_name\[$sender_address\]"
fi

reply_to=""
# Whom to reply to
if [[ "$sender_address" == "$reply_to_address" ]]; then
    reply_to+="$sender_address"
else
    new_recipient=true
    reply_to+="$reply_to_address"
fi

notify_title=""
notify_body=""

if [[ "$message_is_new" == "true" ]]; then
    
    if [[ "$message_is_deleted" == "true" ]]; then
        if [[ "$message_is_flagged" == "true" || "$message_is_marked" == "true" ]]; then
            notify_title+="Warning! A new E-Mail with high priority got deleted!"
        else
            notify_title+="Warning! A new E-Mail got deleted!"
        fi
    else
        notify_title+="New "
        if [[ "$message_is_flagged" == "true" || "$message_is_marked" == "true" ]]; then
            notify_title+="prioritized "
        fi
        notify_title+="E-Mail arrived!"
    fi

    notify_body+="\n$email_is_from "

    if [[ "$message_is_response" == "true" ]]; then
        notify_body+="replied to one of your E-Mails"
    else
        notify_body+="sent you an E-Mail"
    fi

    if [[ "$message_is_old" == "true" ]]; then
        notify_body+=" while you were offline."
    else
        notify_body+="."
    fi
    
    notify_body+="\n\n<b>From:</b> $email_is_from\n"

    # If the email_is_from received an email because they were cc'd
    if [[ "$receive_list" != *$user_account_address* ]] && [[  "$cc_list" == *$user_account_address* ]]; then
        notify_body+="<b>Information:</b> You were mentioned in CC.\n"
    elif [[ "$cc_list" == *$user_account_address* ]]; then
        # The reveiver can be in reply-to and in cc
        notify_body+="<b>Information:</b> You received this E-Mail as a copy in CC.\n"
    fi

    notify_body+="<b>Subject:</b> $(cut_string "$email_subject").\n"

    # Reply to will either be the sender or a new specified recipient
    notify_body+="<b>Reply-To:</b> "
    if [[ "$new_recipient" == "true" ]]; then
        notify_body+="Reply to $reply_to to continue the conversation\n"
    else
        notify_body+="Reply to $email_is_from to continue the conversation\n"
    fi

    notify_body+="<b>Time:</b> $local_system_time"

    $notify_cmd_base -c "$notify_category" -h "$notify_cmd_hint" -u "$notification_urgency" -i "$notify_cmd_icon" "$notify_title" "$notify_body"

else 
    log_message "${YELLOW}WARNING! Unsupported behaviour detected.\e[0m"
fi
exit 0
