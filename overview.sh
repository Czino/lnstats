#! /usr/bin/env -S bash -e

MINIMUM_TX_SIZE=109 # in virtual bytes, assuming no change output
MINIMUM_TX_SIZE_CHANNEL_OPENING=121 # in virtual bytes, assuming no change output

NC='\033[0m' # std format
BOLD='\033[1m'
RED="${NC}"
GREEN="${NC}"
ORANGE="${NC}"

for arg in "$@"; do
    case "$arg" in
        "-c" | "--color")
            RED='\033[1;31m'
            GREEN='\033[1;32m'
            ORANGE='\033[1;33m'
            ;;
        *) # show help if not understood (includes -h / --help)
            echo -e "\n${BOLD}OPTIONS:${NC}"
            echo -e "-h, --help\t show brief help"
            echo -e "-c, --color\t (optional) add colors to output\n"
            exit 0
            ;;
    esac
done

KILOBYTE=1024
MEGABYTE=$((KILOBYTE * 1024))
ONETHOUSAND=1000
ONEMILLION=$((ONETHOUSAND * 1000))

compactBytes() {
  number="${1}"
  if [ "$number" -ge "$MEGABYTE" ]; then
    number=$((number / MEGABYTE))
    number="$number vMB"
  elif [ "$number" -ge "$KILOBYTE" ]; then
      number=$((number / KILOBYTE))
      number="$number vKB"
  else
      number="$number vB"
  fi
  echo "$number"
}

compactSats() {
  number="${1}"
  if [ "$number" -ge "$ONEMILLION" ]; then
    number=$((number / ONEMILLION))
    number="${number}M SAT"
  elif [ "$number" -ge "$ONETHOUSAND" ]; then
      number=$((number / ONETHOUSAND))
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
                      jq -r '.forwarding_events | map(.fee_msat | tonumber) | add')" / 1000))
channels=$(lncli listchannels | jq -r '[.channels[] | select(.initiator == true)]' | \
           jq -r length)
closedChannels=$(lncli closedchannels | \
                 jq -r '[.channels[] | select(.open_initiator == "INITIATOR_LOCAL")]' | \
                 jq -r length)
onchainTx=$((channels + closedChannels * 2))
txPerOnchainTx=$((paymentAmount / onchainTx))
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

echo -e "• You opened ${GREEN}${channels} channels${NC}, closed${RED}" \
        "${closedChannels} channels${NC}, and made ${ORANGE}${paymentAmount}" \
        "Lightning payments${NC}, which implies ${ORANGE}$txPerOnchainTx"\
        "transactions${NC} per on-chain transaction."
echo -e "• You used at least ${RED}${minimumSpaceUsed}${NC} block space," \
        "but saved at least ${GREEN}${minimumSpaceSaved}${NC}."
echo -e "• You paid ${RED}${onchainFees}${NC} on-chain and${RED}" \
        "${totalFeesPaid}${NC} in Lightning fees, but saved at least" \
        "${GREEN}${minimumFeesSaved}${NC} by using Lightning."
echo -e "• You earned ${GREEN}${totalFeesEarned}${NC} through routing.\n"

if [ $paidMoreThanSaved ]; then
  echo -e "${RED}You might be spending more than you save!${NC}\n"
else
  echo -e "${GREEN}You are most likely saving Sats, keep it going!${NC}\n"
fi
