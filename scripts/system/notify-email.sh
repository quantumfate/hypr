#!/usr/bin/env bash
# Author: Leon Connor Holm
# Define options

iDIR="$HOME/.config/hypr/icons"

notify_cmd_shot="notify-send -h string:x-canonical-private-synchronous:shot-notify -u low -i ${iDIR}/mail.png"

log_message() {
    # Takes a message and variable as parameter
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
    fi

    local log_dir="$HOME/.local/log"
    local log_file="email-notify.log"
    local time_stamp=""
    time_stamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$time_stamp : $1" >> "$log_dir/$log_file"
}

if [[ ! -d "$log_dir" ]]; then
	mkdir -p "$log_dir"
fi
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

# Boolean vars for flags
message_is_old=false # When the email arrived while the client was offline
message_is_response=false # When the email is a follow up reply of one of your emails
message_is_marked=false # Whether the email is marked or not
message_is_flagged=false # Whether the email is flagged or not
message_is_new=false # Whether the email is new or not (e.g. moved between folders)
message_is_deleted=false # Whether the email was deleted

opts=:a:n:r:A:T:R:s:D:Z
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
        # Sender name %n or %a if none
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
        # Check for substring in flags -> aerc man page
        # +-----------------+----------------------------------------+
        # |       %Z        | flags (O=old, N=new, r=answered,       |
        # |                 | D=deleted, !=flagged, *=marked)        |
        # +-----------------+----------------------------------------+

        # Set the default notification urgency to low
        notification_urgency="low"

        if [[ $OPTARG == *O* ]] || [[ $OPTARG == *N* ]]; then
            # Handle old or new mails
            message_is_old=true
            message_is_new=true
            notification_urgency="low"
        elif [[ $OPTARG == *D* ]]; then
            # Handle deleted mails
            message_is_deleted=true
            notification_urgency="low"
        elif [[ $OPTARG == *r* ]]; then
            # Handle answered mails
            message_is_response=true
            notification_urgency="medium"
        elif [[ $OPTARG == *!* ]]; then
            # Handle flagged mails
            message_is_flagged=true
            notification_urgency="high"
        elif [[ $OPTARG == *\** ]]; then
            # Handle marked mails
            message_is_marked=true
            notification_urgency="high"
        else
          # Handle all other mails
          log_message "WARNING! Invalid flag in the %Z option found: '$OPTARG'! This flag was ignored."
        fi
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
    email_is_from+="$sender_name\033[3m($sender_address)\033[0m"
fi

reply_to=""
# Whom to reply to
if [[ "$sender_address" == "$reply_to_address" ]]; then
    reply_to+="$sender_address"
else
    reply_to+="$reply_to_address"
fi

notify_string=""

if [[ "$message_is_new" == "true" ]]; then
    
    if [[ "$message_is_deleted" == "true" ]] \
        && [[ "$message_is_flagged" == "true" || "$message_is_marked" == "true" ]]; then
    
        notify_string="\033[1mWarning!\033[0m A new E-Mail with high priority got deleted!\n\n"
    else
        notify_string+="New "
        if [[ "$message_is_flagged" == "true" || "$message_is_marked" == "true" ]]; then
            notify_string+=" prioritized "
        fi
        notify_string+="E-Mail arrived!\n\n"
    fi

    notify_string+="\033[1m$user_account_address\033[0m "

    if [[ "$message_is_response" == "true" ]]; then
        notify_string="replied to one of your E-Mails "
    else
        notify_string="sent you an E-Mail"
    fi

    if [[ "$message_is_old" == "true" ]]; then
        notify_string+=" while you were offline.n\n"
    else
        notify_string+=".\n"
    fi
    
    notify_string+="\033[1mFrom:\033[0m $email_is_from\n"

    # If the email_is_from received an email because they were cc'd
    if [[ $receive_list != *$user_account_address* ]] && [[  $cc_list == *$user_account_address* ]]; then
        notify_string+="Information: You are listed in the CC of the E-Mail\n"
    elif [[ $cc_list == *$user_account_address* ]]; then
        # The reveiver can be in reply-to and in cc
        notify_string+="Information: You will receive this E-Mail as a copy in CC\n"
    fi

    notify_string+="\033[1mSubject:\033[0m '$email_subject.'\n"

    notify_string+="Reply to $reply_to to continue the conversation\n"
    
    notify_string+="\033[1mTime:\033[0m $local_system_time"

    $notify_cmd_shot -u "$notification_urgency" "$notify_string"

fi
exit 0