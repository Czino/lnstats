NC='\033[0m' # No Color
RED='\033[0m'
GREEN='\033[0m'
ORANGE='\033[0m'

stop=false

_setArgs(){
  while [ "$1" != "" ]; do
    case $1 in
      "-h" | "--help")
        echo "options:"
        echo "-h, --help         show brief help"
        echo "-c, --color    (optional) add colors to output"
        stop=true
        ;;
      "-c" | "--color")
        shift
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        ORANGE='\033[0;33m'
        ;;
    esac
    shift
  done
}

_setArgs $*

if "$stop"; then
  return
fi

MINIMUM_TX_SIZE=109 # in virtual bytes, assuming no change output
MINIMUM_TX_SIZE_CHANNEL_OPENING=121 # in virtual bytes, assuming no change output
KILOBYTE=1024
MEGABYTE=$(expr 1024 \* 1024)
ONEMILLION=1000000
ONETHOUSAND=1000

compactBytes() {
  number="${1}"
  if [ "$number" -ge "$MEGABYTE" ]; then
    number=$(($number / $MEGABYTE))
    number=$(echo "$number vMB")
  elif [ "$number" -ge "$KILOBYTE" ]; then
      number=$(($number / $KILOBYTE))
      number=$(echo "$number vKB")
  else
      number=$(echo "$number vB")
  fi
  echo "$number"
}

compactSats() {
  number="${1}"
  if [ "$number" -ge "$ONEMILLION" ]; then
    number=$(($number / $ONEMILLION))
    number=$(echo "${number}M sats")
  elif [ "$number" -ge "$ONETHOUSAND" ]; then
      number=$(($number / $ONETHOUSAND))
      number=$(echo "${number}k sats")
  else
      number=$(echo "$number sats")
  fi
  echo "$number"
}



payments=$(lncli listpayments --max_payments 9999 | jq -r '[.payments[] | select(.status == "SUCCEEDED")]')
onchainFees=$(lncli listchaintxns | jq -r '.transactions | map(.total_fees | tonumber) | add')
paymentAmount=$(echo "$payments" | jq -r length)
totalFeesPaid=$(echo "$payments" | jq -r '. | map(.fee_sat | tonumber) | add')
let totalFeesEarned="$(lncli fwdinghistory --max_events 10000 --start_time "-10y" | jq -r '.forwarding_events | map(.fee_msat | tonumber) | add')"/1000
channels=$(lncli listchannels | jq -r '[.channels[] | select(.initiator == true)]' | jq -r length)
closedChannels=$(lncli closedchannels | jq -r '[.channels[] | select(.open_initiator == "INITIATOR_LOCAL")]' | jq -r length)
let onchainTx="$channels"+"$closedChannels"*2
let txPerOnchainTx="$paymentAmount"/"$onchainTx"
let minimumSpaceUsed="$MINIMUM_TX_SIZE_CHANNEL_OPENING"*"$onchainTx"
let minimumSpaceSaved="$MINIMUM_TX_SIZE"*"$paymentAmount"-"$minimumSpaceUsed"
let minimumFeesSaved="$paymentAmount"*"$MINIMUM_TX_SIZE"-"$minimumSpaceUsed"
let allFeesPaid="$onchainFees"+"$totalFeesPaid"
let balance="$minimumFeesSaved"+"$totalFeesEarned"-"$allFeesPaid"

paidMoreThanSaved=false
if [ "$balance" -lt 0]; then
    paidMoreThanSaved=true
fi

minimumSpaceUsed=$(compactBytes "$minimumSpaceUsed")
minimumSpaceSaved=$(compactBytes "$minimumSpaceSaved")

totalFeesPaid=$(compactSats "$totalFeesPaid")
totalFeesEarned=$(compactSats "$totalFeesEarned")
minimumFeesSaved=$(compactSats "$minimumFeesSaved")
onchainFees=$(compactSats "$onchainFees")
balance=$(compactSats "$balance")

echo -e "You opened ${ORANGE}$channels channels${NC}, closed ${RED}$closedChannels channels${NC} and made ${ORANGE}$paymentAmount lightning payments${NC} which results in ${ORANGE}$txPerOnchainTx transactions${NC} per on-chain transaction."
echo -e "You used at least ${RED}$minimumSpaceUsed${NC} block space but saved at least ${GREEN}$minimumSpaceSaved${NC}."
echo -e "You paid ${RED}$onchainFees${NC} on-chain and ${RED}$totalFeesPaid${NC} in lightning fees but saved at least ${GREEN}$minimumFeesSaved${NC} by using lightning."
echo -e "You earned ${GREEN}$totalFeesEarned${NC} through routing."
echo ""
if [ $paidMoreThanSaved ]; then
  echo -e "${RED}You might be spending more than you save!${NC}"
else
  echo -e "${GREEN}You are most likely saving sats, keep it going!${NC}"
fi
