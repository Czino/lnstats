#! /usr/bin/env -S bash -e

if ! which lncli > /dev/null; then
    echo -e "\nPlease make sure 'lncli' is in your \$PATH. Exiting!"
    exit 1
fi

MINIMUM_TX_SIZE=109 # in virtual bytes, assuming no change output
MINIMUM_TX_SIZE_CHANNEL_OPENING=121 # in virtual bytes, assuming no change output

NC="$(tput sgr0)" # std format
BOLD="$(tput bold)"

for arg in "$@"; do
    case "$arg" in
        "-c" | "--color")
            use_colors="full"
            ;;
        "-nc" | "--nocolor")
            use_colors="bold"
            ;;
        *) # show help if not understood (includes -h / --help)
            echo -en "\n${BOLD}Usage:${NC}" \
                     "\n${0} [options]\n" \
                     "\n${BOLD}OPTIONS:${NC}" \
                     "\n-h, --help\t show brief help" \
                     "\n-c, --color\t (default if supported) colorize output" \
                     "\n-nc, --nocolor\t remove colors from output\n\n"
            exit 0
            ;;
    esac
done

# check if stdout is a terminal
if [ -z "${use_colors}" ]; then
    use_colors="no"
    if test -t 1; then
        # see if it supports colors
        ncolors=$(tput colors)
        if test -n "${ncolors}" && test "${ncolors}" -ge 8; then
            use_colors="full"
        else
            use_colors="bold"
        fi
    fi
fi

if [ "${use_colors}" == 'full' ]; then
    RED="$(tput bold; tput setaf 1)"
    GREEN="$(tput bold; tput setaf 2)"
    ORANGE="$(tput bold; tput setaf 3)"
elif [ "${use_colors}" == 'bold' ]; then
    RED="${BOLD}"; GREEN="${BOLD}"; ORANGE="${BOLD}"
else
    NC=""; BOLD=""; RED=""; GREEN=""; ORANGE=""
fi

KILOBYTE=1024
MEGABYTE=$((KILOBYTE * 1024))
ONETHOUSAND=1000
ONEMILLION=$((ONETHOUSAND * 1000))

compactBytes() {
  number="${1}"
  if [ "$number" -ge "$MEGABYTE" ]; then
      number=$(printf "%.1f\n" "$(bc <<< "scale = 3; ${number}/${MEGABYTE}")")
      number="$number vMB"
  elif [ "$number" -ge "$KILOBYTE" ]; then
      number=$(printf "%.1f\n" "$(bc <<< "scale = 3; ${number}/${KILOBYTE}")")
      number="$number vKB"
  else
      number="$number vB"
  fi
  echo "$number"
}

compactSats() {
  number="${1}"
  if [ "$number" -ge "$ONEMILLION" ]; then
      number=$(printf "%.1f\n" "$(bc <<< "scale = 3; ${number}/${ONEMILLION}")")
      number="${number}M SAT"
  elif [ "$number" -ge "$ONETHOUSAND" ]; then
      number=$(printf "%.1f\n" "$(bc <<< "scale = 3; ${number}/${ONETHOUSAND}")")
      number="${number}k SAT"
  else
      number="$number SAT"
  fi
  echo "$number"
}

echo -e "\nTalking to lnd, this will take a few seconds ...\n"

payments=$(lncli listpayments --max_payments 9999 | \
    jq -r '[.payments[] | select(.status == "SUCCEEDED")]')
onchainFees=$(lncli listchaintxns | jq -r '.transactions | map(.total_fees | tonumber) | add')
paymentAmount=$(echo "$payments" | jq -r length)
totalFeesPaid=$(echo "$payments" | jq -r '. | map(.fee_sat | tonumber) | add')
totalFeesEarned=$(("$(lncli fwdinghistory --max_events 10000 --start_time "-10y" | \
    jq -r '.forwarding_events | map(.fee_msat | tonumber) | add')" / ONETHOUSAND))
initiatedChansOpen=$(lncli listchannels | jq -r '[.channels[] | select(.initiator == true)]' | \
    jq -r length)
initiatedChansDead=$(lncli closedchannels | \
    jq -r '[.channels[] | select(.open_initiator == "INITIATOR_LOCAL")]' | \
    jq -r length)
initiatedChans=$((initiatedChansOpen + initiatedChansDead))
onchainTx=$((initiatedChansOpen + initiatedChansDead * 2))
txPerOnchainTx=$(printf "%.0f\n" "$(bc <<< "scale = 2; ${paymentAmount}/${onchainTx}")")
minimumSpaceUsed=$((MINIMUM_TX_SIZE_CHANNEL_OPENING * onchainTx))
minimumSpaceSaved=$((MINIMUM_TX_SIZE * paymentAmount - minimumSpaceUsed))
minimumFeesSaved=$((paymentAmount * MINIMUM_TX_SIZE - minimumSpaceUsed))
allFeesPaid=$((onchainFees + totalFeesPaid))
balance=$((minimumFeesSaved + totalFeesEarned - allFeesPaid))

paidMoreThanSaved=false
if [ "$balance" -lt 0 ]; then
    paidMoreThanSaved=true
fi

minimumSpaceUsed=$(compactBytes "$minimumSpaceUsed")
minimumSpaceSaved=$(compactBytes "$minimumSpaceSaved")

totalFeesPaid=$(compactSats "$totalFeesPaid")
totalFeesEarned=$(compactSats "$totalFeesEarned")
minimumFeesSaved=$(compactSats "$minimumFeesSaved")
onchainFees=$(compactSats "$onchainFees")
balance=$(compactSats "$balance")

echo -e "• You opened ${GREEN}${initiatedChans} channels${NC}, out of which" \
        "${RED}${initiatedChansDead} are now closed${NC}, and you made" \
        "${ORANGE}${paymentAmount} Lightning payments${NC}, which implies" \
        "${ORANGE}${txPerOnchainTx} payments${NC} per on-chain transaction."
echo -e "• You used at least ${RED}${minimumSpaceUsed}${NC} block space," \
        "but saved at least ${GREEN}${minimumSpaceSaved}${NC}."
echo -e "• You paid ${RED}${onchainFees}${NC} on-chain and${RED}" \
        "${totalFeesPaid}${NC} in Lightning fees, but saved at least" \
        "${GREEN}${minimumFeesSaved}${NC} by using Lightning."
echo -e "• You earned ${GREEN}${totalFeesEarned}${NC} through routing.\n"

if $paidMoreThanSaved; then
  echo -e "${RED}You might be spending more than you save!${NC}\n"
else
  echo -e "${GREEN}You are most likely saving Sats, keep it going!${NC}\n"
fi
