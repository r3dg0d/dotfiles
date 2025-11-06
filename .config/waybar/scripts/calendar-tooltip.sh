#!/usr/bin/env bash

# Script to generate a calendar tooltip for waybar

# Get current date
TODAY=$(date +%-d)  # Remove leading zero
MONTH=$(date +%-m)
YEAR=$(date +%Y)
MONTH_NAME=$(date +%B)

# Get the first day of the month (0 = Sunday, 6 = Saturday)
# date +%w gives 0-6 (Sunday-Saturday)
FIRST_DAY=$(date -d "$YEAR-$MONTH-01" +%w)

# Get number of days in month (without leading zero)
DAYS_IN_MONTH=$(date -d "$YEAR-$MONTH-01 +1 month -1 day" +%-d)

# Calendar header
CALENDAR="<tt><b>$MONTH_NAME $YEAR</b>\n"
CALENDAR+="─────────────────────\n"
CALENDAR+=" Su Mo Tu We Th Fr Sa\n"

# Add leading spaces for days before the first day of the month
for ((i=0; i<$FIRST_DAY; i++)); do
    CALENDAR+="   "
done

# Add days of the month
for ((day=1; day<=$DAYS_IN_MONTH; day++)); do
    # Calculate position (0 = Sunday, 6 = Saturday)
    POS=$(( ($FIRST_DAY + $day - 1) % 7 ))
    
    # Highlight today
    if [ "$day" -eq "$TODAY" ]; then
        CALENDAR+="<b><span foreground='#6366f1'>"
        printf -v CALENDAR "%s%3d" "$CALENDAR" "$day"
        CALENDAR+="</span></b>"
    else
        printf -v CALENDAR "%s%3d" "$CALENDAR" "$day"
    fi
    
    # New line after Saturday (position 6)
    if [ $POS -eq 6 ] && [ $day -lt $DAYS_IN_MONTH ]; then
        CALENDAR+="\n"
    fi
done

CALENDAR+="</tt>"

echo -e "$CALENDAR"

